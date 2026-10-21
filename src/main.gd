extends Node3D
## 关卡总控：世界 -> 玩家 -> 敌人 -> 任务 -> 撤离。
## 一局流程：落地在铁砧基地 -> 夺取敌方据点 -> 呼叫直升机 -> 登机结算。

const ENEMY_CAP := 34
var progressive_loading: bool = true
var generation_seed: int = -1
var loading_complete: bool = false
signal level_ready

var world: WorldRoot
var player: Player
var hud: HUD
var heli: ExtractionHeli

var _enemies: Array[Soldier] = []
var _squads: Array = []            ## 全部 AI 小队
var _poi_squads: Dictionary = {}   ## poi_id -> Squad（增援时补进原班）
var _vehicle: Vehicle = null

## 友军发美械、敌人发俄械（按用户要求）
const US_GUNS := ["SM_Wep_Preset_A_Rifle_01", "SM_Wep_Preset_A_Rifle_02",
	"SM_Wep_Preset_A_Rifle_03", "SM_Wep_Preset_A_SMG_01", "SM_Wep_Preset_A_Heavy_01"]
const RU_GUNS := ["SM_Wep_Preset_B_Rifle_01", "SM_Wep_Preset_B_Rifle_02",
	"SM_Wep_Preset_B_Rifle_03", "SM_Wep_Preset_B_SMG_01", "SM_Wep_Rifle_01",
	"SM_Wep_MachineGun_Bandit_01"]


func _random_gun(origin: String) -> String:
	var pool: Array = US_GUNS if origin == "us" else RU_GUNS
	return str(pool[randi() % pool.size()])
var _allies: Array[Soldier] = []
var _mission_state: String = "active"     ## active / extract / done
var _target_outpost: Outpost
var _kill_goal: int = 8
var _kill_now: int = 0
var _reinforce_t: float = 40.0
var _death_t: float = -1.0
var _tracers: int = 0


func _ready() -> void:
	if generation_seed < 0:
		generation_seed = int(Time.get_unix_time_from_system()) % 100000
	seed(generation_seed)
	GameState.raid_loot = 0
	GameState.raid_kills = 0
	GameState.raid_time = 0.0
	GameState.last_raid = {}
	EventBus.mission_completed.connect(_on_mission_completed)
	var loading: CanvasLayer
	if progressive_loading:
		loading = CanvasLayer.new()
		loading.layer = 100
		add_child(loading)
		var shade := ColorRect.new()
		shade.color = Color(0.04, 0.05, 0.06)
		shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		loading.add_child(shade)
		var label := Label.new()
		label.name = "LoadingProgress"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 24)
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		shade.add_child(label)
		world = WorldRoot.new()
		world.name = "World"
		add_child(world)
		world.loading_progress.connect(func(message: String, progress: float): label.text = "正在准备行动  %d%%\n%s" % [int(progress * 90), message])
		var models: Array = US_GUNS + RU_GUNS + [Loadout.primary, Loadout.secondary, "SM_Chr_Soldier_Male_01", "SM_Veh_Helicopter_Transport_01", "SM_Prop_Crate_Ammo_01"]
		for weapon in [Loadout.primary, Loadout.secondary]:
			var viewmodel := Player.first_person_model(weapon)
			models.append(viewmodel if viewmodel != "" else ("BT_Arms_Pistol" if weapon.contains("Pistol") else "BT_Arms_Rifle"))
		models.append_array(["BT_Hand_R_Rifle", "BT_Hand_L_Rifle", "BT_Hand_R_Pistol", "BT_Hand_L_Pistol"])
		if Loadout.vehicle != "none":
			models.append(Loadout.vehicle)
		var paths: Array = []
		for model in models:
			paths.append(AssetLib.model_path(model))
		await world.generate_async(generation_seed, paths)
		label.text = "正在部署角色…"
		await get_tree().process_frame
	else:
		_build_world()
	_spawn_player()
	GameState.in_raid = false
	_build_hud()
	if progressive_loading:
		await get_tree().process_frame
	await _spawn_allies()
	await _spawn_enemies()
	await _spawn_rivals()
	await _spawn_loot()
	_spawn_vehicle()
	AssetLib.get_scene("SM_Veh_Helicopter_Transport_01")
	GameState.in_raid = true
	_start_mission()
	EventBus.shot_fired.connect(_on_shot_fired)
	EventBus.enemy_killed.connect(_on_enemy_killed)
	EventBus.outpost_captured.connect(_on_outpost_captured)
	EventBus.player_died.connect(_on_player_died)
	loading_complete = true
	level_ready.emit()
	if loading != null:
		loading.queue_free()


# ---------------------------------------------------------------- 构建
func _build_world() -> void:
	world = WorldRoot.new()
	world.name = "World"
	add_child(world)
	world.generate(generation_seed)


func _spawn_player() -> void:
	player = Player.new()
	player.name = "Player"
	add_child(player)
	player.global_position = world.player_spawn_transform().origin
	player._yaw = deg_to_rad(180.0)


func _build_hud() -> void:
	var cl := CanvasLayer.new()
	cl.name = "UI"
	add_child(cl)
	hud = HUD.new()
	hud.player = player
	hud.world = world
	cl.add_child(hud)


func _make_squad(faction: String, id: String, center: Vector3, radius: float = 25.0) -> Squad:
	var q := Squad.new()
	q.name = "Squad_" + id
	add_child(q)
	q.setup(faction, id, center, radius)
	_squads.append(q)
	return q


func _spawn_allies() -> void:
	var fob := world.poi_by_id("fob")
	var base := Vector3(fob["pos"].x, 0, fob["pos"].y)
	var ally_squad := _make_squad("blufor", "alpha", base, 20.0)
	ally_squad.follow_target = player
	for i in 3:
		var s := Soldier.new()
		s.name = "Ally_%d" % i
		add_child(s)
		var off := Vector3(cos(i * 2.1) * 6.0, 0, sin(i * 2.1) * 6.0)
		s.global_position = base + off + Vector3(0, world.terrain.height_at(base.x + off.x, base.z + off.z) + 1.2, 0)
		s.configure("blufor", "SM_Chr_Soldier_Male_02" if i % 2 == 0 else "SM_Chr_Soldier_Male_01",
			0.7, _random_gun("us"))
		s.follow_target = player
		ally_squad.add_member(s)
		_allies.append(s)
		if progressive_loading:
			await get_tree().process_frame


func _spawn_enemies() -> void:
	var difficulty := clampf(0.55 + GameState.level * 0.12, 0.4, 1.6)
	for poi in world.pois:
		if str(poi["faction"]) != "opfor":
			continue
		var points: Array = poi.get("spawn_points", [])
		if points.is_empty():
			continue
		var count := clampi(3 + int(difficulty * 2.0), 3, 7)
		var center: Vector2 = poi["pos"]
		var sq := _make_squad("opfor", str(poi["id"]), Vector3(center.x, 0, center.y),
			float(poi["radius"]) * 0.6)
		_poi_squads[str(poi["id"])] = sq
		for i in count:
			var p: Vector3 = points[i % points.size()]
			p += Vector3(randf_range(-3, 3), 0.4, randf_range(-3, 3))
			var s := _spawn_one_enemy(p, poi)
			sq.add_member(s)
			if progressive_loading:
				await get_tree().process_frame


func _spawn_one_enemy(pos: Vector3, poi: Dictionary) -> Soldier:
	var s := Soldier.new()
	add_child(s)
	s.global_position = pos
	var roll := randf()
	var model := "SM_Chr_Insurgent_Male_01"
	if roll > 0.82:
		model = "SM_Chr_Leader_Male_01"
	elif roll > 0.66:
		model = "SM_Chr_Insurgent_Male_03"
	elif roll > 0.4:
		model = "SM_Chr_Insurgent_Male_02"
	s.configure("opfor", model, clampf(0.55 + GameState.level * 0.12, 0.4, 1.6), _random_gun("ru"))
	var center: Vector2 = poi["pos"]
	var pts: Array[Vector3] = []
	for i in 4:
		var a := randf() * TAU
		var r := randf_range(8.0, float(poi["radius"]) * 0.7)
		var wx := center.x + cos(a) * r
		var wz := center.y + sin(a) * r
		pts.append(Vector3(wx, world.terrain.height_at(wx, wz) + 1.2, wz))
	s.patrol_points = pts
	s.home = pos
	_enemies.append(s)
	return s


func _spawn_rivals() -> void:
	## "另一队玩家"的替身：三方混战，走到哪都可能撞上，制造 PvP 压力
	var candidates: Array = []
	for poi in world.pois:
		if str(poi["id"]) != "fob":
			candidates.append(poi)
	if candidates.is_empty():
		return
	for squad_idx in 2:
		var poi: Dictionary = candidates[randi() % candidates.size()]
		var center: Vector2 = poi["pos"]
		var sq := _make_squad("rival", "rival_%d" % squad_idx,
			Vector3(center.x, 0, center.y), 40.0)
		for i in 3:
			var s := Soldier.new()
			add_child(s)
			var a := randf() * TAU
			var r := randf_range(10.0, 30.0)
			var wx := center.x + cos(a) * r
			var wz := center.y + sin(a) * r
			s.global_position = Vector3(wx, world.terrain.height_at(wx, wz) + 1.2, wz)
			s.configure("rival", "SM_Chr_Soldier_Male_01" if i % 2 == 0 else "SM_Chr_Ghillie_Male_01",
				0.85, _random_gun("us" if randf() < 0.5 else "ru"))
			var pts: Array[Vector3] = []
			for k in 3:
				var aa := randf() * TAU
				var rr := randf_range(20.0, 70.0)
				var px := wx + cos(aa) * rr
				var pz := wz + sin(aa) * rr
				pts.append(Vector3(px, world.terrain.height_at(px, pz) + 1.2, pz))
			s.patrol_points = pts
			sq.add_member(s)
			if progressive_loading:
				await get_tree().process_frame




func _spawn_vehicle() -> void:
	## 在基地里放玩家买的那台车
	if Loadout.vehicle == "none":
		return
	var info: Dictionary = ItemDB.VEHICLES.get(Loadout.vehicle, {})
	if info.is_empty():
		return
	var fob := world.poi_by_id("fob")
	if fob.is_empty():
		return
	var center: Vector2 = fob["pos"]
	var kind := str(info.get("kind", "ground"))
	var off := Vector2(0, 16) if kind == "ground" else Vector2(0, -5)
	var wx := center.x + off.x
	var wz := center.y + off.y
	var v := Vehicle.new()
	v.name = "PlayerVehicle"
	v.setup(Loadout.vehicle, kind, float(info.get("speed", 18.0)),
		float(info.get("armor", 0.0)), str(info.get("label", "载具")))
	add_child(v)
	var lift := 0.6 if kind == "ground" else AssetLib.size_of("SM_Env_Helipad_01").y + 0.25
	v.global_position = Vector3(wx, world.terrain.height_at(wx, wz) + lift, wz)
	_vehicle = v


func _spawn_loot() -> void:
	for poi in world.pois:
		if str(poi["faction"]) != "opfor":
			continue
		for lp in poi.get("loot_points", []):
			var c := LootCrate.new()
			add_child(c)
			c.global_position = lp
			c.setup(int(randf_range(120, 320)))
			if progressive_loading:
				await get_tree().process_frame


# ---------------------------------------------------------------- 任务
func _start_mission() -> void:
	var candidates: Array[Outpost] = []
	for o in world.outposts:
		if not o.is_owned_by_player():
			candidates.append(o)
	if candidates.is_empty():
		return
	_target_outpost = candidates[randi() % candidates.size()]
	_kill_goal = 6 + int(GameState.level * 1.5)
	_kill_now = 0
	_mission_state = "active"
	_update_objective()


func _update_objective() -> void:
	if _mission_state == "active":
		EventBus.objective_changed.emit(
			"夺取 %s" % _target_outpost.display_name,
			"击杀敌人 %d/%d   ·   进入据点圆圈内推进控制进度" % [_kill_now, _kill_goal]
		)
	elif _mission_state == "extract":
		EventBus.objective_changed.emit(
			"撤离",
			"按 G 呼叫直升机，登机完成结算"
		)


func _on_outpost_captured(outpost: Node, owner: String) -> void:
	if outpost == _target_outpost and owner == "blufor" and _mission_state == "active":
		_mission_state = "extract"
		_update_objective()


func _on_enemy_killed(enemy: Node, _headshot: bool, killer_faction: String) -> void:
	if enemy.get("faction") != "opfor" or killer_faction != "player" or _mission_state == "done":
		return
	_kill_now += 1
	if _mission_state == "active":
		_update_objective()


func _on_player_died() -> void:
	if _mission_state != "done" and GameState.in_raid:
		_death_t = 2.5


func _on_mission_completed(credits: int, _xp: int) -> void:
	if _mission_state == "done" or not GameState.in_raid or player.state != Player.State.ALIVE:
		return
	_mission_state = "done"
	_death_t = -1.0
	GameState.end_raid(true, credits)
	_stop_action()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _stop_action() -> void:
	AudioSfx.stop_world()
	for child in get_children():
		if child.name != "UI":
			child.process_mode = Node.PROCESS_MODE_DISABLED


func _process(delta: float) -> void:
	if not loading_complete or _mission_state == "done":
		return
	if _death_t > 0.0:
		_death_t -= delta
		if _death_t <= 0.0:
			_mission_state = "done"
			GameState.end_raid(false, 0)
			_stop_action()
			EventBus.mission_failed.emit("你在行动中阵亡，损失了部分信用点")

	# 增援：敌方据点会持续补人，逼玩家别磨蹭
	if _mission_state != "done":
		_reinforce_t -= delta
		if _reinforce_t <= 0.0:
			_reinforce_t = 45.0
			_reinforce()


func _reinforce() -> void:
	_enemies = _enemies.filter(func(e): return is_instance_valid(e) and e.is_alive())
	if _enemies.size() >= ENEMY_CAP:
		return
	var pool: Array = []
	for poi in world.pois:
		if str(poi["faction"]) == "opfor" and not poi.get("spawn_points", []).is_empty():
			pool.append(poi)
	if pool.is_empty():
		return
	var poi: Dictionary = pool[randi() % pool.size()]
	var pts: Array = poi["spawn_points"]
	var p: Vector3 = pts[randi() % pts.size()]
	var s := _spawn_one_enemy(p + Vector3(randf_range(-4, 4), 0.4, randf_range(-4, 4)), poi)
	var sq = _poi_squads.get(str(poi["id"]))
	if sq != null and is_instance_valid(sq):
		sq.add_member(s)


# ---------------------------------------------------------------- 撤离
func _call_extraction() -> void:
	if _mission_state != "extract" or heli != null or player.state != Player.State.ALIVE:
		return
	heli = ExtractionHeli.new()
	heli.name = "ExtractionHeli"
	add_child(heli)
	var p := player.global_position
	var lz := p + Vector3(randf_range(-6, 6), 0, -34.0)
	lz.y = world.terrain.height_at(lz.x, lz.z) + 0.2
	heli.setup(lz)
	EventBus.notify.emit("直升机 inbound —— 大约 15 秒后抵达")


# ---------------------------------------------------------------- 输入
func _unhandled_input(event: InputEvent) -> void:
	if not loading_complete:
		return
	if event.is_action_pressed("call_extract"):
		_call_extraction()
	elif event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("ui_accept"):
		if hud != null and hud._show_debrief:
			get_tree().change_scene_to_file("res://src/ui/menu.tscn")


# ---------------------------------------------------------------- 曳光弹
func _on_shot_fired(shooter: Node, from: Vector3, to: Vector3, _hit: bool) -> void:
	if _tracers > 40:
		return
	var dist := from.distance_to(to)
	if dist < 2.0 or dist > 320.0:
		return
	var is_player := shooter == player
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.035, 0.035, dist)
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.88, 0.55, 0.9) if is_player else Color(1.0, 0.55, 0.35, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = (from + to) * 0.5
	mi.look_at(to, Vector3.UP)
	_tracers += 1
	var tw := create_tween()
	tw.tween_interval(0.05)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.12)
	tw.tween_callback(_kill_tracer.bind(mi))


func _kill_tracer(mi: Node) -> void:
	if is_instance_valid(mi):
		mi.queue_free()
	_tracers = maxi(0, _tracers - 1)
