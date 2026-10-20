class_name Soldier
extends CharacterBody3D
## 敌方 / 友方 AI。没有用 NavigationAgent3D —— 大地形上实时烘焙导航网格太贵，
## 这里用"前向探障 + 侧向绕行"的转向，配合据点周围的巡逻点，行为足够可信。

enum AIState { IDLE, PATROL, ALERT, COMBAT, SEARCH, DOWNED, DEAD }

const WALK := 2.3
const RUN := 5.4
const GRAVITY := 24.0

var faction: String = "opfor"
var health: float = 100.0
var max_health: float = 100.0
var state: int = AIState.PATROL

var weapon_damage: float = 14.0
var weapon_range: float = 120.0
var fire_interval: float = 0.42
var accuracy: float = 0.55          ## 0~1，越高越准
var view_distance: float = 95.0
var fov_deg: float = 110.0
var reaction_time: float = 0.45

var patrol_points: Array[Vector3] = []
var home: Vector3 = Vector3.ZERO
var follow_target: Node3D = null   ## 友军跟随目标（玩家）

var squad = null                   ## 所属小队（Squad）
var squad_role: String = "rifleman"
var _suppress: bool = false
var _retreating: bool = false

var _patrol_idx: int = 0
var _target: Node3D = null
var _last_seen: Vector3 = Vector3.ZERO
var _see_timer: float = 0.0
var _fire_cd: float = 0.0
var _burst: int = 0
var _reaction: float = 0.0
var _search_t: float = 0.0
var _strafe_dir: float = 1.0
var _strafe_t: float = 0.0
var _percept_cd: float = 0.0
var _bob: float = 0.0
var _bleed: float = 45.0

const RIG_SCRIPT := preload("res://src/ai/character_rig.gd")

var model: Node3D
var rig                     ## CharacterRig 实例（不写死类型，避免类缓存失效时整条链崩掉）
var _capsule: CollisionShape3D
var _muzzle: Node3D


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	add_to_group("combatant")
	_sync_groups()

	_capsule = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.42
	cap.height = 1.8
	_capsule.shape = cap
	_capsule.position.y = 0.9
	add_child(_capsule)

	_muzzle = Node3D.new()
	_muzzle.position = Vector3(0.22, 1.35, -0.45)
	add_child(_muzzle)

	if home == Vector3.ZERO:
		home = global_position


func configure(p_faction: String, model_name: String, difficulty: float = 1.0, weapon_model: String = "") -> void:
	faction = p_faction
	_sync_groups()
	accuracy = clampf(0.42 + 0.22 * difficulty, 0.2, 0.92)
	weapon_damage = 12.0 + 6.0 * difficulty
	fire_interval = clampf(0.55 - 0.12 * difficulty, 0.18, 0.9)
	reaction_time = clampf(0.7 - 0.2 * difficulty, 0.15, 1.0)
	health = 90.0 + 40.0 * difficulty
	max_health = health

	# 手里拿什么枪，就打什么枪的数值
	if weapon_model != "":
		var w: Dictionary = ItemDB.weapon(weapon_model)
		if not w.is_empty():
			weapon_damage = float(w["damage"]) * 0.5
			fire_interval = clampf(60.0 / maxf(60.0, float(w["rpm"])) * 3.2, 0.18, 0.9)
			weapon_range = float(w["range"])
			accuracy = clampf(accuracy * 0.92 + (1.0 - float(w["spread_ads"]) * 0.1) * 0.08, 0.2, 0.95)

	if model_name == "":
		model_name = "SM_Chr_Insurgent_Male_01" if faction == "opfor" else "SM_Chr_Soldier_Male_02"
	model = AssetLib.spawn(model_name, self, Vector3.ZERO, 0.0, true)
	if model != null:
		rig = RIG_SCRIPT.new()
		rig.setup(model)
		_attach_weapon(weapon_model if weapon_model != "" else
			("SM_Wep_Rifle_01" if faction == "opfor" else "SM_Wep_Preset_A_Rifle_01"))
	if model == null:
		# 模型缺失时至少给个可辨认的替身，别静默变透明
		var mi := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.4
		cm.height = 1.8
		mi.mesh = cm
		mi.position.y = 0.9
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.7, 0.2, 0.2) if faction == "opfor" else Color(0.2, 0.4, 0.8)
		mi.material_override = mat
		add_child(mi)


func is_alive() -> bool:
	return state != AIState.DEAD and state != AIState.DOWNED


func _physics_process(delta: float) -> void:
	if state == AIState.DEAD:
		return
	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	if state == AIState.DOWNED:
		_bleed -= delta
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		if _bleed <= 0.0:
			_die()
		return

	_percept_cd -= delta
	if _percept_cd <= 0.0:
		_percept_cd = 0.18
		_think()

	match state:
		AIState.IDLE:
			_do_idle(delta)
		AIState.PATROL:
			_do_patrol(delta)
		AIState.ALERT:
			_do_alert(delta)
		AIState.COMBAT:
			_do_combat(delta)
		AIState.SEARCH:
			_do_search(delta)

	_update_visual(delta)
	move_and_slide()


# ---------------------------------------------------------------- 感知
func _think() -> void:
	# 小队溃退中：不再交战，往家跑
	_retreating = squad != null and is_instance_valid(squad) and squad.is_broken()

	var t := _acquire_target()
	if t != null:
		if _target != t:
			_reaction = reaction_time
		_target = t
		_last_seen = t.global_position
		_see_timer = 0.0
		# 一个人看见 = 全队知道
		if squad != null:
			squad.report_contact(t.global_position, t)
		if state != AIState.COMBAT and _reaction <= 0.0:
			state = AIState.COMBAT
			EventBus.enemy_alerted.emit(self)
		else:
			state = AIState.COMBAT
	else:
		_see_timer += 0.18
		if squad != null and squad.has_contact:
			# 自己没视野，但队里有人报了点 —— 朝接触点摸过去
			if state != AIState.COMBAT:
				state = AIState.SEARCH
				_last_seen = squad.contact_pos
				_search_t = maxf(_search_t, 5.0)
		elif state == AIState.COMBAT and _see_timer > 2.5:
			state = AIState.SEARCH
			_search_t = 7.0
	_reaction = maxf(0.0, _reaction - 0.18)


func _acquire_target() -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for n in get_tree().get_nodes_in_group("combatant"):
		if n == self or not is_instance_valid(n):
			continue
		if not n.has_method("is_alive") or not n.is_alive():
			continue
		var f: String = str(n.get("faction"))
		if not _is_hostile(f):
			continue
		var d := global_position.distance_to(n.global_position)
		if d > view_distance or d >= best_d:
			continue
		if not _in_fov(n.global_position):
			continue
		if not _has_los(n.global_position):
			continue
		best = n
		best_d = d
	return best


func _is_hostile(other: String) -> bool:
	if other == faction:
		return false
	if faction == "opfor":
		return other in ["player", "blufor", "rival"]
	if faction == "blufor":
		return other in ["opfor", "rival"]
	if faction == "rival":
		return other != "rival"
	return false


func _in_fov(pos: Vector3) -> bool:
	var to := pos - global_position
	to.y = 0.0
	if to.length_squared() < 0.01:
		return true
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	return rad_to_deg(fwd.angle_to(to.normalized())) < fov_deg * 0.5


func _has_los(pos: Vector3) -> bool:
	var from := global_position + Vector3(0, 1.5, 0)
	var q := PhysicsRayQueryParameters3D.create(from, pos + Vector3(0, 1.2, 0), 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty()


# ---------------------------------------------------------------- 行为
func _do_idle(delta: float) -> void:
	_slow_down(delta)


func _do_patrol(delta: float) -> void:
	if _retreating:
		var d_home := home - global_position
		d_home.y = 0.0
		if d_home.length() > 6.0:
			_move_towards(d_home.normalized(), RUN, delta)
		else:
			_slow_down(delta)
		return
	if follow_target != null and is_instance_valid(follow_target):
		var to_p := follow_target.global_position - global_position
		to_p.y = 0.0
		var d := to_p.length()
		if d > 14.0:
			_move_towards(to_p.normalized(), RUN, delta)
		elif d > 7.0:
			_move_towards(to_p.normalized(), WALK * 1.5, delta)
		else:
			_slow_down(delta)
		return
	if patrol_points.is_empty():
		_do_idle(delta)
		return
	var goal := patrol_points[_patrol_idx % patrol_points.size()]
	var to := goal - global_position
	to.y = 0.0
	if to.length() < 2.0:
		_patrol_idx += 1
		return
	_move_towards(to.normalized(), WALK, delta)


func _do_alert(delta: float) -> void:
	_slow_down(delta)


func _do_combat(delta: float) -> void:
	if _target == null or not is_instance_valid(_target) or not _target.is_alive():
		state = AIState.SEARCH
		_search_t = 6.0
		return
	var to := _target.global_position - global_position
	var dist := Vector2(to.x, to.z).length()
	var dir := Vector3(to.x, 0, to.z).normalized()

	# 面向目标
	var want_yaw := atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, want_yaw, delta * 6.0)

	_suppress = false
	var advancing := false
	var ordered := false
	if squad != null:
		var order: Dictionary = squad.order_for(self)
		ordered = true
		match str(order.get("mode", "")):
			"advance":
				# 跃进：跑到侧翼位置。跑动中不射击 —— 这是交替掩护的基本纪律，
				# 也避免全队同时开火把玩家瞬间打穿。
				advancing = true
				var goal: Vector3 = order.get("pos", global_position)
				var d_goal := goal - global_position
				d_goal.y = 0.0
				if d_goal.length() > 3.0:
					_move_towards(d_goal.normalized(), RUN * 0.9, delta)
				else:
					_slow_down(delta)
			"hold":
				# 压制组：站定输出，火力更密但更散
				_slow_down(delta)
				_suppress = bool(order.get("suppress", false))
			"retreat":
				var home_pos: Vector3 = order.get("pos", home)
				var d_home := home_pos - global_position
				d_home.y = 0.0
				_move_towards(d_home.normalized(), RUN, delta)
				return
			_:
				ordered = false

	if not ordered:
		# 没有小队 / 队形状态：保持原来的自由走位
		if dist > weapon_range * 0.8:
			_move_towards(dir, RUN, delta)
		elif dist < 12.0:
			_move_towards(-dir, WALK * 1.4, delta)
		else:
			_strafe_t -= delta
			if _strafe_t <= 0.0:
				_strafe_t = randf_range(1.0, 2.4)
				_strafe_dir = 1.0 if randf() < 0.5 else -1.0
			var side := Vector3(-dir.z, 0, dir.x) * _strafe_dir
			_move_towards((side * 0.7 + dir * 0.3).normalized(), WALK * 1.2, delta)

	_fire_cd -= delta
	if not advancing and _fire_cd <= 0.0 and _has_los(_target.global_position):
		_shoot_at(_target, dist)
		var interval := fire_interval * randf_range(0.85, 1.35)
		if _suppress:
			interval *= 0.7
		_fire_cd = interval


func _do_search(delta: float) -> void:
	_search_t -= delta
	if _search_t <= 0.0:
		state = AIState.PATROL
		return
	var to := _last_seen - global_position
	to.y = 0.0
	if to.length() > 3.0:
		_move_towards(to.normalized(), WALK * 1.3, delta)


func _move_towards(dir: Vector3, speed: float, delta: float) -> void:
	# 前方探障，撞上了就往侧面滑
	var from := global_position + Vector3(0, 1.0, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 1.8, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		var side := Vector3(-dir.z, 0, dir.x) * _strafe_dir
		dir = (side * 0.9 + dir * 0.25).normalized()
	var target_v := dir * speed
	velocity.x = move_toward(velocity.x, target_v.x, 14.0 * delta)
	velocity.z = move_toward(velocity.z, target_v.z, 14.0 * delta)
	if dir.length_squared() > 0.01 and state != AIState.COMBAT:
		var want_yaw := atan2(-dir.x, -dir.z)
		rotation.y = lerp_angle(rotation.y, want_yaw, delta * 4.0)


func _slow_down(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 10.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 10.0 * delta)


func _shoot_at(target: Node3D, dist: float) -> void:
	_burst += 1
	if _burst > 4:
		_burst = 0
		_fire_cd += 0.5

	var from := global_position + Vector3(0, 1.45, 0) + (-global_transform.basis.z) * 0.4
	var to := target.global_position + Vector3(0, 1.1, 0)
	var dir := (to - from).normalized()

	# 距离越远越散，移动中更散 —— 不用作弊式命中率，直接改散布
	var spread := deg_to_rad(lerpf(3.6, 0.6, accuracy) * (1.0 + dist / 120.0))
	if velocity.length() > 1.0:
		spread *= 1.5
	if _suppress:
		spread *= 1.35   # 压制射击：弹着点更散，逼对方低头
	var basis := Basis.looking_at(dir, Vector3.UP)
	var r := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * tan(spread)
	dir = (dir + basis.x * r.x + basis.y * r.y).normalized()

	var q := PhysicsRayQueryParameters3D.create(from, from + dir * weapon_range, 1 | 2 | 4, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var end := from + dir * weapon_range
	if not hit.is_empty():
		end = hit["position"]
		var c: Object = hit["collider"]
		if c != null and c.has_method("take_damage"):
			var head := false
			if c is Node3D:
				head = end.y - (c as Node3D).global_position.y > 1.45
			c.take_damage(weapon_damage * (2.2 if head else 1.0), end, self)
	EventBus.shot_fired.emit(self, from, end, not hit.is_empty())


# ---------------------------------------------------------------- 受伤
func take_damage(amount: float, hit_pos: Vector3, source: Node) -> void:
	if state == AIState.DEAD:
		return
	health -= amount
	_last_seen = source.global_position if source is Node3D else hit_pos
	_see_timer = 0.0
	if state == AIState.PATROL or state == AIState.IDLE:
		state = AIState.COMBAT
		_target = source as Node3D
	if health <= 0.0:
		health = 0.0
		if faction == "blufor" and randf() < 0.6:
			_go_down()
		else:
			_die(source)


func _go_down() -> void:
	state = AIState.DOWNED
	_bleed = 40.0
	if model != null:
		model.rotation_degrees = Vector3(-80, 0, 0)
		model.position.y = 0.25
	if rig != null:
		rig.pose_downed()
	EventBus.notify.emit("队友倒下了")


func revive() -> void:
	if state != AIState.DOWNED:
		return
	state = AIState.PATROL
	health = 45.0
	if model != null:
		model.rotation_degrees = Vector3.ZERO
		model.position.y = 0.0


func _die(source: Node = null) -> void:
	if state == AIState.DEAD:
		return
	state = AIState.DEAD
	collision_layer = 0
	collision_mask = 0
	remove_from_group("combatant")
	if model != null:
		model.rotation_degrees = Vector3(-88, 0, 0)
		model.position.y = 0.2
	if rig != null:
		rig.pose_dead()
	var headshot := false
	if source is Player:
		headshot = randf() < 0.25
	if squad != null and is_instance_valid(squad):
		squad.on_member_down(self)
	EventBus.enemy_killed.emit(self, headshot, faction)
	if faction == "opfor":
		GameState.raid_kills += 1
		GameState.kills_total += 1
		GameState.raid_loot += GameState.KILL_REWARD
	var tw := create_tween()
	tw.tween_interval(12.0)
	tw.tween_callback(queue_free)


# ---------------------------------------------------------------- 表现
func _update_visual(delta: float) -> void:
	if model == null:
		return
	var spd := velocity.length()
	_bob += spd * delta * 3.2
	# 上下起伏交给骨骼动画，模型层不再整体晃
	model.position.y = 0.0
	model.rotation.z = 0.0
	if rig != null and rig.ready:
		var aim := 1.0 if state == AIState.COMBAT else 0.0
		var look := 0.0
		if state == AIState.COMBAT and _target != null and is_instance_valid(_target):
			var to := _target.global_position - global_position
			look = clampf(wrapf(atan2(-to.x, -to.z) - rotation.y, -PI, PI), -0.7, 0.7)
		rig.animate_locomotion(delta, spd / RUN, aim, look)


func interact_prompt() -> String:
	if state == AIState.DOWNED and faction == "blufor":
		return "救起队友 [F]"
	return ""


func _sync_groups() -> void:
	## configure() 可能在 _ready() 之后才调用，阵营分组必须跟着刷新
	for g in ["opfor", "blufor", "rival"]:
		if is_in_group(g):
			remove_from_group(g)
	if faction != "":
		add_to_group(faction)

func _attach_weapon(weapon: String) -> void:
	## 把枪挂到右手骨骼上。
	## 注意骨骼空间是厘米（祖先节点带 0.01 缩放），所以枪要放大 100 倍才回到米。
	if rig == null or not rig.ready or rig.skel == null:
		return
	var hand: int = rig.skel.find_bone("Hand_R")
	if hand < 0:
		return
	var att := BoneAttachment3D.new()
	att.name = "WeaponBone"
	att.bone_name = "Hand_R"
	rig.skel.add_child(att)
	var w: Node3D = AssetLib.spawn(weapon, att, Vector3.ZERO, 0.0, true)
	if w == null:
		att.queue_free()
		return
	w.scale = Vector3.ONE * 100.0
	w.position = Vector3(6.0, -3.0, 4.0)
	w.rotation_degrees = Vector3(0, 90, -90)
