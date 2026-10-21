class_name Player
extends CharacterBody3D
## 玩家控制器：第一/第三人称、冲刺体力、射击后坐、受伤/倒地/急救。
##
## POLYGON 角色没有动画片段，身体姿态由 CharacterRig 驱动。

enum State { ALIVE, DOWNED, DEAD }

const WALK_SPEED := 4.8
const SPRINT_SPEED := 7.8
const CROUCH_SPEED := 2.4
const ADS_SPEED := 2.9
const DOWNED_SPEED := 1.1
const ACCEL := 12.0
const JUMP_VELOCITY := 7.0
const GRAVITY := 24.0
const MOUSE_SENS := 0.0022

var faction: String = "player"
var state: int = State.ALIVE

var health: float = 100.0
var max_health: float = 100.0
var armor: float = 60.0
var max_armor: float = 60.0
var stamina: float = 100.0
var max_stamina: float = 100.0

var meds := {"bandage": 4, "dressing": 3, "vitamins": 1}
var _last_med: String = ""
var _regen_pool: float = 0.0

var bleed_time: float = 60.0
var bleed_total: float = 60.0

var weapon_id: String = "SM_Wep_Preset_A_Rifle_01"
var sidearm_id: String = "SM_Wep_Pistol_01"
var _def: Dictionary = {}
var _burst_left: int = 0
var _burst_t: float = 0.0
var _nvg_on: bool = false
var _nvg_layer: CanvasLayer
var _speed_mult: float = 1.0
var vehicle: Vehicle = null
var active_slot: int = 0
var ammo_mag: int = 30
var ammo_reserve: int = 180
var sidearm_mag: int = 15
var sidearm_reserve: int = 90
var _primary_mag: int = 30
var _primary_reserve: int = 180

var kills: int = 0
var damage_dealt: float = 0.0

# 视角
var _yaw: float = 0.0
var _pitch: float = 0.0
var _recoil := Vector2.ZERO
var _shake: float = 0.0
var _spread: float = 0.0
var _fire_cd: float = 0.0
var _step_distance: float = 0.0
var _reloading: bool = false
var _reload_t: float = 0.0
var _ads: bool = false
var _ads_blend: float = 0.0
var _sprint_lock: float = 0.0
var _third_person: bool = false

var _bob: float = 0.0
var _sway := Vector2.ZERO
var _mouse_delta := Vector2.ZERO
var _weapon_kick: float = 0.0
var _ads_position := Vector3(0.0, -0.09, -0.70)
var _weapon_hip := Vector3(0.28, -0.26, -0.58)
var _viewmodel_animation: AnimationPlayer
var _viewmodel_reload: StringName
var _viewmodel_reload_length := 3.0
var _interact_target: Node = null

# 节点
var cam_pivot: Node3D
var spring: SpringArm3D
var camera: Camera3D
var weapon_mount: Node3D
var weapon_model: Node3D
var muzzle: OmniLight3D
var body_model: Node3D
var body_rig
var _body_weapon: Node3D
const RIG_SCRIPT := preload("res://src/ai/character_rig.gd")
const FIRST_PERSON_MODELS := {"BT_M4A1": "BT_FP_M4", "BT_AK47": "BT_FP_AK", "BT_M1911": "BT_FP_M1911"}

static func first_person_model(id: String) -> String:
	var source: String = AssetLib.REALISTIC_WEAPONS.get(id, "")
	return "BT_FP_" + id if source.begins_with("BT_Fitted_") else str(FIRST_PERSON_MODELS.get(source, ""))
var _capsule: CollisionShape3D
var _stand_shape: CapsuleShape3D
var _crouch_shape: CapsuleShape3D

var _crouching: bool = false
var _gravity: float = 24.0


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1 | 4 | 16
	floor_max_angle = deg_to_rad(52.0)
	add_to_group("combatant")
	add_to_group("blufor")

	_stand_shape = CapsuleShape3D.new()
	_stand_shape.radius = 0.42
	_stand_shape.height = 1.8
	_crouch_shape = CapsuleShape3D.new()
	_crouch_shape.radius = 0.42
	_crouch_shape.height = 1.2

	_capsule = CollisionShape3D.new()
	_capsule.shape = _stand_shape
	_capsule.position.y = 0.9
	add_child(_capsule)

	cam_pivot = Node3D.new()
	cam_pivot.name = "CamPivot"
	cam_pivot.position = Vector3(0, 1.62, 0)
	add_child(cam_pivot)

	spring = SpringArm3D.new()
	spring.spring_length = 0.0
	spring.collision_mask = 1
	spring.margin = 0.2
	cam_pivot.add_child(spring)

	camera = Camera3D.new()
	camera.fov = 78.0
	camera.near = 0.05
	camera.far = 1400.0
	spring.add_child(camera)

	weapon_mount = Node3D.new()
	weapon_mount.name = "WeaponMount"
	camera.add_child(weapon_mount)

	muzzle = OmniLight3D.new()
	muzzle.light_color = Color(1.0, 0.82, 0.45)
	muzzle.light_energy = 0.0
	muzzle.omni_range = 9.0
	muzzle.position = Vector3(0, 0, -1.1)
	weapon_mount.add_child(muzzle)

	weapon_id = Loadout.primary
	sidearm_id = Loadout.secondary
	AssetLib.get_scene(sidearm_id)
	AssetLib.get_scene(first_person_model(sidearm_id))
	max_armor = maxf(0.0, Loadout.armor_value())
	armor = max_armor
	_speed_mult = Loadout.speed_mult()
	_equip(weapon_id)
	ammo_mag = int(current_def()["mag"])
	ammo_reserve = int(current_def()["reserve"])
	var secondary := Loadout.resolved_secondary()
	sidearm_mag = int(secondary["mag"])
	sidearm_reserve = int(secondary["reserve"])
	_build_body()
	GameState.in_raid = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _build_body() -> void:
	body_model = AssetLib.spawn("SM_Chr_Soldier_Male_01", self, Vector3.ZERO, 0.0, true)
	if body_model != null:
		body_model.rotation.y = PI
		body_model.visible = false
		body_rig = RIG_SCRIPT.new()
		body_rig.setup(body_model)
		_attach_body_weapon(weapon_id)


func _attach_body_weapon(id: String) -> void:
	## 第三人称时手里的枪（和 AI 一样挂在右手骨骼上）
	if body_rig == null or not body_rig.ready or body_rig.skel == null:
		return
	if _body_weapon != null and is_instance_valid(_body_weapon):
		_body_weapon.get_parent().queue_free()
		_body_weapon = null
	if body_rig.skel.find_bone("Hand_R") < 0:
		return
	_body_weapon = body_rig.attach_weapon(id, body_model)


# ---------------------------------------------------------------- 装备
func _equip(id: String) -> void:
	if weapon_model != null:
		weapon_model.queue_free()
		weapon_model = null
	_def = ItemDB.resolve(id, Loadout.attachments if active_slot == 0 else {})
	_viewmodel_animation = null
	_viewmodel_reload = &""
	var viewmodel := first_person_model(id)
	weapon_model = AssetLib.spawn(viewmodel if viewmodel != "" else id, weapon_mount, Vector3.ZERO, 0.0, false)
	if weapon_model != null:
		weapon_model.visible = not _third_person
		# Detailed viewmodels use the measured firing grip as their origin.
		_weapon_hip = Vector3(0.16, -0.13, -0.26) if viewmodel != "" else Vector3(0.18, -0.16, -0.28)
		weapon_model.position = _weapon_hip
		# 实测：模型枪口朝 +Z，必须转 180° 才指向前方；90° 会让枪横在镜头前
		weapon_model.rotation_degrees = Vector3(0, 180, 0)
		weapon_model.scale = Vector3.ONE if viewmodel != "" else Vector3.ONE * 0.70
		if viewmodel == "":
			# shortcut: remaining guns share a generic grip; author per-gun poses when replacing them.
			var pistol := id.contains("Pistol")
			AssetLib.spawn("BT_Arms_Pistol" if pistol else "BT_Arms_Rifle", weapon_model, Vector3.ZERO, 0.0, false)
		AssetLib.apply_tint(weapon_model, Loadout.camo_color())
		_set_weapon_layer(weapon_model)
		_ads_position = Vector3(0.0, -0.09, -0.70)
		var anchor := weapon_model.find_child("BT_AimAnchor", true, false) as Node3D
		if anchor != null:
			var anchor_center := weapon_model.to_local(anchor.global_position)
			_ads_position = Vector3(0, 0, -0.38) - weapon_model.basis * anchor_center
		for sight in weapon_model.find_children("*Sight_Glass*", "MeshInstance3D", true, false) if anchor == null else []:
			if "RailCanted" in str(sight.name):
				continue
			var center: Vector3 = weapon_model.to_local(sight.to_global(sight.get_aabb().get_center()))
			_ads_position = Vector3(0, 0, -0.70) - weapon_model.basis * center
			break
		var players := weapon_model.find_children("*", "AnimationPlayer", true, false)
		if viewmodel != "" and not players.is_empty():
			_viewmodel_animation = players[0] as AnimationPlayer
			for clip in _viewmodel_animation.get_animation_list():
				if str(clip).ends_with("Reload"):
					_viewmodel_reload = clip
					_viewmodel_reload_length = _viewmodel_animation.get_animation(clip).length
					_viewmodel_animation.play(clip)
					_viewmodel_animation.pause()
					_viewmodel_animation.seek(0, true)
					break
	if body_rig != null:
		_attach_body_weapon(id)


func _set_weapon_layer(n: Node) -> void:
	## 手上的枪不要挡住射线，也不要被自己的射线打到
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is GeometryInstance3D:
			(cur as GeometryInstance3D).layers = 2
		for c in cur.get_children():
			stack.append(c)


func current_def() -> Dictionary:
	if _def.is_empty():
		_def = ItemDB.resolve(weapon_id if active_slot == 0 else sidearm_id, {})
	return _def


func is_alive() -> bool:
	return state == State.ALIVE or state == State.DOWNED


# ---------------------------------------------------------------- 输入
func _unhandled_input(event: InputEvent) -> void:
	if not GameState.in_raid or state == State.DEAD:
		return
	if vehicle != null:
		if event.is_action_pressed("interact"):
			vehicle.exit_vehicle()
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm := event as InputEventMouseMotion
		_mouse_delta += mm.relative
		_yaw -= mm.relative.x * GameState.mouse_sensitivity
		_pitch -= mm.relative.y * GameState.mouse_sensitivity
		_pitch = clampf(_pitch, deg_to_rad(-88.0), deg_to_rad(88.0))
		_apply_look()
	elif event.is_action_pressed("toggle_view") and state == State.ALIVE:
		_third_person = not _third_person
		spring.spring_length = 3.4 if _third_person else 0.0
		if body_model != null:
			body_model.visible = _third_person
		if weapon_model != null:
			weapon_model.visible = not _third_person
	elif event.is_action_pressed("slot_primary") and state == State.ALIVE:
		_switch_slot(0)
	elif event.is_action_pressed("slot_secondary") and state == State.ALIVE:
		_switch_slot(1)
	elif event.is_action_pressed("reload"):
		_start_reload()
	elif event.is_action_pressed("use_bandage"):
		_use_med("bandage")
	elif event.is_action_pressed("use_dressing"):
		_use_med("dressing")
	elif event.is_action_pressed("use_vitamins"):
		_use_med("vitamins")
	elif event.is_action_pressed("interact"):
		_interact()
	elif event.is_action_pressed("toggle_nvg"):
		_toggle_nvg()


func _switch_slot(slot: int) -> void:
	if slot == active_slot:
		return
	if active_slot == 0:
		_primary_mag = ammo_mag
		_primary_reserve = ammo_reserve
	else:
		sidearm_mag = ammo_mag
		sidearm_reserve = ammo_reserve
	active_slot = slot
	_reloading = false
	AudioSfx.stop_reload()
	_burst_left = 0
	_burst_t = 0.0
	if slot == 0:
		_equip(weapon_id)
		ammo_mag = _primary_mag
		ammo_reserve = _primary_reserve
	else:
		_equip(sidearm_id)
		ammo_mag = sidearm_mag
		ammo_reserve = sidearm_reserve


# ---------------------------------------------------------------- 主循环
func _physics_process(delta: float) -> void:
	if state == State.DEAD or not GameState.in_raid:
		return
	if _check_bounds():
		return
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 24.0))

	if not is_on_floor():
		velocity.y -= _gravity * delta

	_apply_look()

	if state == State.DOWNED:
		_process_downed(delta)
		move_and_slide()
		return

	_process_movement(delta)
	_process_combat(delta)
	_update_interact_target()
	_update_body_rig(delta)
	move_and_slide()
	_update_footsteps(delta)


func _update_footsteps(delta: float) -> void:
	if not is_on_floor() or state != State.ALIVE or vehicle != null:
		_step_distance = 0.0
		return
	var speed := Vector2(velocity.x, velocity.z).length()
	if speed < 0.5:
		_step_distance = 0.0
		return
	_step_distance += speed * delta
	if _step_distance >= (2.2 if speed > WALK_SPEED else 1.7):
		_step_distance = 0.0
		AudioSfx.play_ui("step", -29.0 if _crouching else -22.0)


func _check_bounds() -> bool:
	var half := Terrain.SIZE * 0.5
	if absf(global_position.x) <= half and absf(global_position.z) <= half and global_position.y >= -50.0:
		return false
	var world := get_parent().get_node_or_null("World") as WorldRoot
	var safe := world.player_spawn_transform().origin if world != null else Vector3(0, 5, 0)
	if vehicle != null:
		var old_vehicle := vehicle
		old_vehicle.exit_vehicle()
		old_vehicle.global_position = safe + Vector3(12, 10, 0)
		old_vehicle.velocity = Vector3.ZERO
	global_position = safe
	velocity = Vector3.ZERO
	EventBus.notify.emit("已离开地图，返回基地安全位置")
	return true


func _process_movement(delta: float) -> void:
	var input := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_back") - Input.get_action_strength("move_forward")
	)
	if input.length() > 1.0:
		input = input.normalized()

	_crouching = Input.is_action_pressed("crouch")
	_capsule.shape = _crouch_shape if _crouching else _stand_shape
	_capsule.position.y = 0.6 if _crouching else 0.9
	cam_pivot.position.y = lerpf(cam_pivot.position.y, 1.02 if _crouching else 1.62, delta * 12.0)

	var want_sprint := Input.is_action_pressed("sprint") and not _ads and input.y < -0.1 and not _crouching
	if _sprint_lock > 0.0:
		want_sprint = false
	var sprinting := want_sprint and stamina > 3.0

	if sprinting:
		stamina = maxf(0.0, stamina - 17.0 * delta)
		if stamina <= 0.0:
			_sprint_lock = 2.0
	else:
		_sprint_lock = maxf(0.0, _sprint_lock - delta)
		if _sprint_lock <= 0.0:
			stamina = minf(max_stamina, stamina + 13.0 * delta)

	var speed := WALK_SPEED
	if _crouching:
		speed = CROUCH_SPEED
	elif sprinting:
		speed = SPRINT_SPEED
	elif _ads:
		speed = ADS_SPEED
	speed *= _speed_mult

	var dir := (transform.basis * Vector3(input.x, 0, input.y)).normalized()
	var target := dir * speed
	velocity.x = move_toward(velocity.x, target.x, ACCEL * speed * delta)
	velocity.z = move_toward(velocity.z, target.z, ACCEL * speed * delta)

	if Input.is_action_just_pressed("jump") and is_on_floor() and stamina > 12.0 and not _crouching:
		velocity.y = JUMP_VELOCITY
		stamina -= 12.0

	_bob += velocity.length() * delta * 2.4


func _process_combat(delta: float) -> void:
	_ads = Input.is_action_pressed("aim") and not _reloading
	_ads_blend = move_toward(_ads_blend, 1.0 if _ads else 0.0, delta * 7.0 * float(current_def().get("ads_speed", 1.0)))
	camera.fov = lerpf(78.0, float(current_def()["zoom"]), _ads_blend)

	_fire_cd = maxf(0.0, _fire_cd - delta)
	_spread = maxf(0.0, _spread - delta * 6.0)
	_recoil = _recoil.lerp(Vector2.ZERO, delta * 9.0)

	if _reloading:
		_reload_t -= delta
		if _reload_t <= 0.0:
			_finish_reload()

	if _burst_left > 0:
		_burst_t -= delta
		if _burst_t <= 0.0 and ammo_mag > 0 and not _reloading:
			_fire()
			_burst_left = maxi(0, _burst_left - 1)
			_burst_t = 60.0 / maxf(60.0, float(current_def().get("rpm", 700.0)))
	elif Input.is_action_pressed("fire") and _fire_cd <= 0.0 and not _reloading:
		var mode := str(current_def().get("fire_mode", "auto"))
		if mode == "auto":
			_fire()
		elif Input.is_action_just_pressed("fire"):
			if mode == "burst":
				_burst_left = int(current_def().get("burst", 3))
				_burst_t = 0.0
			else:
				_fire()



func _fire() -> void:
	if ammo_mag <= 0:
		_start_reload()
		return
	var def := current_def()
	ammo_mag -= 1
	_fire_cd = 60.0 / float(def["rpm"])
	_spread = minf(6.0, _spread + float(def["recoil"]) * 0.35)
	_recoil.x += deg_to_rad(float(def["recoil"]) * 0.55)
	_recoil.y += deg_to_rad(randf_range(-1.0, 1.0) * float(def["recoil_h"]))
	_weapon_kick = 1.0
	_shake = minf(0.5, _shake + 0.06)
	muzzle.light_energy = 4.0
	get_tree().create_timer(0.05).timeout.connect(_muzzle_off)

	var pellets := int(def.get("pellets", 1))
	AudioSfx.weapon_shot(weapon_id if active_slot == 0 else sidearm_id, camera.global_position, true,
		active_slot == 0 and Loadout.attachments.get("muzzle") == "suppressor")
	for i in pellets:
		_hitscan(def)

	if ammo_mag == 0:
		_start_reload()


func _hitscan(def: Dictionary) -> void:
	var origin := camera.global_position
	var basis := camera.global_transform.basis
	var dir := -basis.z
	var spread_deg := lerpf(float(def["spread_hip"]), float(def["spread_ads"]), _ads_blend) + _spread
	if not _ads:
		spread_deg += 1.2 * clampf(velocity.length() / SPRINT_SPEED, 0.0, 1.0)
	var rnd := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * tan(deg_to_rad(spread_deg))
	dir = (dir + basis.x * rnd.x + basis.y * rnd.y).normalized()

	var max_range := float(def["range"])
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * max_range, 1 | 4 | 16, [get_rid()])
	q.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var end := origin + dir * max_range
	if not hit.is_empty():
		end = hit["position"]
		var target: Object = hit["collider"]
		if target != null and target.has_method("take_damage"):
			var dist := origin.distance_to(end)
			var falloff := lerpf(1.0, float(def["falloff"]), clampf(dist / max_range, 0.0, 1.0))
			var dmg := float(def["damage"]) * falloff
			var head := false
			if target is Node3D:
				head = end.y - (target as Node3D).global_position.y > 1.45
			if head:
				dmg *= 2.6
			target.take_damage(dmg, end, self)
			damage_dealt += dmg
			EventBus.hitmarker.emit("head" if head else "body")
		else:
			_spawn_impact(end, hit.get("normal", Vector3.UP))
	EventBus.shot_fired.emit(self, origin, end, not hit.is_empty())


func _spawn_impact(pos: Vector3, normal: Vector3) -> void:
	## 简单的弹着点：小方块 + 短暂存在，够表达"打到了"
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.09, 0.09, 0.02)
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.82, 0.7)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child(mi)
	mi.global_position = pos + normal * 0.02
	mi.look_at(pos + normal, Vector3.FORWARD if absf(normal.dot(Vector3.UP)) > 0.99 else Vector3.UP)
	var tw := create_tween()
	tw.tween_property(mi, "scale", Vector3.ZERO, 0.35)
	tw.tween_callback(mi.queue_free)


func _start_reload() -> void:
	if _reloading or ammo_mag >= int(current_def()["mag"]) or ammo_reserve <= 0:
		return
	_reloading = true
	_burst_left = 0
	_burst_t = 0.0
	_reload_t = float(current_def()["reload"])
	AudioSfx.play_reload()


func _finish_reload() -> void:
	_reloading = false
	AudioSfx.stop_reload()
	var def := current_def()
	var need := int(def["mag"]) - ammo_mag
	var take := mini(need, ammo_reserve)
	ammo_mag += take
	ammo_reserve -= take
	if active_slot == 1:
		sidearm_mag = ammo_mag
		sidearm_reserve = ammo_reserve


# ---------------------------------------------------------------- 持枪姿态
func _update_weapon_pose(delta: float) -> void:
	if weapon_model == null:
		return
	_weapon_kick = maxf(0.0, _weapon_kick - delta * 7.0)
	_sway = _sway.lerp(Vector2.ZERO, delta * 8.0)
	_sway += _mouse_delta * 0.0016
	_mouse_delta = Vector2.ZERO
	_sway.x = clampf(_sway.x, -0.05, 0.05)
	_sway.y = clampf(_sway.y, -0.05, 0.05)

	var bob_amt := clampf(velocity.length() / SPRINT_SPEED, 0.0, 1.0) * (1.0 - _ads_blend)
	var bx := sin(_bob) * 0.012 * bob_amt
	var by := absf(cos(_bob)) * 0.010 * bob_amt

	var hip := _weapon_hip
	var base := hip.lerp(_ads_position, _ads_blend)
	var reload_rot := 0.0
	if _reloading:
		var t := 1.0 - _reload_t / maxf(0.01, float(current_def()["reload"]))
		var authored := _viewmodel_animation != null and _viewmodel_reload != &""
		reload_rot = sin(t * PI) * (0.35 if authored else 0.7)
		base.y += sin(t * PI) * (0.06 if authored else -0.18)
		if _viewmodel_animation != null and _viewmodel_reload != &"":
			_viewmodel_animation.seek(clampf(t, 0, 1) * _viewmodel_reload_length, true)
	elif _viewmodel_animation != null and _viewmodel_reload != &"":
		_viewmodel_animation.seek(0, true)

	weapon_model.position = base + Vector3(bx - _sway.x, by - _sway.y, _weapon_kick * 0.05)
	weapon_model.rotation_degrees = Vector3(
		_weapon_kick * 3.5 + reload_rot * 20.0,
			180.0 + _sway.x * 120.0,
		reload_rot * 35.0 + _sway.y * 120.0
	)


# ---------------------------------------------------------------- 相机效果
func _update_camera_fx(delta: float) -> void:
	_shake = maxf(0.0, _shake - delta * 2.2)
	if _shake > 0.001:
		camera.rotation_degrees = Vector3(
			randf_range(-1, 1) * _shake * 1.4,
			randf_range(-1, 1) * _shake * 1.4,
			randf_range(-1, 1) * _shake * 0.8
		)
	else:
		camera.rotation_degrees = Vector3.ZERO
	# Body-held arms lag the eye's shake instead of sticking to the same screen pixels.
	weapon_mount.rotation = -camera.rotation * 0.65 - Vector3(_recoil.x, _recoil.y, 0) * 0.35


# ---------------------------------------------------------------- 受伤 / 倒地
func take_damage(amount: float, hit_pos: Vector3, source: Node) -> void:
	if state == State.DEAD or not GameState.in_raid:
		return
	var to_armor := minf(armor, amount * 0.55)
	armor -= to_armor
	health -= (amount - to_armor)
	_shake = minf(1.0, _shake + 0.35)
	EventBus.player_damaged.emit(amount, source)

	if health <= 0.0:
		health = 0.0
		_go_down()


func _go_down() -> void:
	if state == State.DOWNED:
		return
	AudioSfx.stop_reload()
	if vehicle != null:
		vehicle.exit_vehicle()
	state = State.DOWNED
	bleed_time = bleed_total
	_third_person = true
	spring.spring_length = 3.0
	if body_model != null:
		body_model.visible = true
		body_model.rotation_degrees = Vector3(-80, 180, 0)
		body_model.position.y = 0.25
	if body_rig != null:
		body_rig.pose_downed()
	if weapon_model != null:
		weapon_model.visible = false
	EventBus.player_downed.emit()
	EventBus.notify.emit("你已倒地 —— 按住空格延缓失血，等待队友急救")


func _process_downed(delta: float) -> void:
	var slow := 0.45 if Input.is_action_pressed("jump") else 1.0
	bleed_time -= delta * slow
	var input := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_back") - Input.get_action_strength("move_forward")
	)
	var dir := (transform.basis * Vector3(input.x, 0, input.y)).normalized()
	velocity.x = move_toward(velocity.x, dir.x * DOWNED_SPEED, 6.0 * delta)
	velocity.z = move_toward(velocity.z, dir.z * DOWNED_SPEED, 6.0 * delta)
	if bleed_time <= 0.0:
		_die()


func revive(amount: float = 45.0) -> void:
	if state != State.DOWNED:
		return
	state = State.ALIVE
	health = amount
	_third_person = false
	spring.spring_length = 0.0
	if body_model != null:
		body_model.visible = false
		body_model.rotation_degrees = Vector3(0, 180, 0)
		body_model.position.y = 0.0
	if body_rig != null:
		body_rig.reset()
	if weapon_model != null:
		weapon_model.visible = true
	EventBus.player_revived.emit()
	EventBus.notify.emit("已被救起")


func _die() -> void:
	if state == State.DEAD or not GameState.in_raid:
		return
	state = State.DEAD
	AudioSfx.stop_reload()
	if body_rig != null:
		body_rig.pose_dead()
	EventBus.player_died.emit()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# ---------------------------------------------------------------- 医疗
func _use_med(kind: String) -> void:
	if state != State.ALIVE:
		return
	if meds.get(kind, 0) <= 0:
		EventBus.notify.emit("没有%s了" % _med_name(kind))
		return
	if health >= max_health and _regen_pool <= 0.0:
		EventBus.notify.emit("没有受伤")
		return
	meds[kind] -= 1
	match kind:
		"bandage":
			var bonus := 15.0 if _last_med == "dressing" else 0.0
			_heal(10.0 + bonus)
		"dressing":
			var bonus := 15.0 if _last_med == "bandage" else 0.0
			_heal(5.0 + bonus)
		"vitamins":
			_regen_pool += 100.0
	_last_med = kind
	EventBus.notify.emit("使用 %s" % _med_name(kind))


func _heal(amount: float) -> void:
	var before := health
	health = minf(max_health, health + amount)
	EventBus.player_healed.emit(health - before)


func _med_name(kind: String) -> String:
	match kind:
		"bandage":
			return "绷带"
		"dressing":
			return "敷料"
		"vitamins":
			return "维生素"
	return kind


# ---------------------------------------------------------------- 交互
func _update_interact_target() -> void:
	_interact_target = null
	var origin := camera.global_position
	var dir := -camera.global_transform.basis.z
	var reach := 3.2 + origin.distance_to(cam_pivot.global_position)
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * reach, 1 | 4 | 16, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty() and cam_pivot.global_position.distance_to(hit["position"]) <= 3.2:
		var c: Object = hit["collider"]
		if c != null and c.has_method("interact_prompt"):
			_interact_target = c


func interact_prompt() -> String:
	if _interact_target != null and _interact_target.has_method("interact_prompt"):
		return str(_interact_target.interact_prompt())
	return ""


func _interact() -> void:
	if state != State.ALIVE or not GameState.in_raid:
		return
	_update_interact_target()
	if _interact_target != null and _interact_target.has_method("interact"):
		_interact_target.interact(self)


func _process(_delta: float) -> void:
	if GameState.in_raid and state != State.DEAD and vehicle == null:
		_apply_look()
		_update_camera_fx(_delta)
		if state == State.ALIVE:
			_update_weapon_pose(_delta)
	if state == State.ALIVE and GameState.in_raid and _regen_pool > 0.0 and health < max_health:
		var step := minf(_regen_pool, 22.0 * _delta)
		_regen_pool -= step
		_heal(step)


func _apply_look() -> void:
	rotation.y = _yaw
	cam_pivot.rotation.x = _pitch + _recoil.x
	cam_pivot.rotation.y = _recoil.y


# ---------------------------------------------------------------- HUD 取值
func hud_spread() -> float:
	return _spread


func ads_blend() -> float:
	return _ads_blend


func is_reloading() -> bool:
	return _reloading


func _muzzle_off() -> void:
	if is_instance_valid(muzzle):
		muzzle.light_energy = 0.0

func _update_body_rig(delta: float) -> void:
	if body_rig == null or not body_rig.ready:
		return
	var horiz := Vector2(velocity.x, velocity.z).length()
	var ratio := clampf(horiz / SPRINT_SPEED, 0.0, 1.0)
	body_rig.animate_locomotion(delta, ratio, 1.0 if _ads else 0.0, 0.0)

# ---------------------------------------------------------------- 夜视仪
func _toggle_nvg() -> void:
	if Loadout.nvg_gain() <= 0.0:
		EventBus.notify.emit("没有夜视设备")
		return
	_nvg_on = not _nvg_on
	if _nvg_layer == null:
		_nvg_layer = CanvasLayer.new()
		_nvg_layer.layer = 2
		add_child(_nvg_layer)
		var rect := ColorRect.new()
		rect.color = Color(0.15, 0.95, 0.35, 0.16)
		rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_nvg_layer.add_child(rect)
	_nvg_layer.visible = _nvg_on
	_apply_nvg_light(_nvg_on)
	EventBus.notify.emit("夜视仪 %s" % ("开启" if _nvg_on else "关闭"))


func _apply_nvg_light(on: bool) -> void:
	var env := get_tree().get_first_node_in_group("world_env")
	if env == null or not (env is WorldEnvironment):
		return
	var e: Environment = (env as WorldEnvironment).environment
	if e == null:
		return
	if on:
		e.ambient_light_energy = 0.42 + 0.55 * Loadout.nvg_gain()
	else:
		e.ambient_light_energy = 0.42
