class_name Vehicle
extends CharacterBody3D
## 可驾驶载具：地面车辆（轮式）与直升机（空中）。
##
## 不做真实车辆物理 —— 这套是"街机手感"：
##   地面：W/S 油门刹车，A/D 转向，靠 move_and_slide 贴地
##   空中：W/S 升降，A/D 转向，Shift 前推，松开就悬停

const GRAVITY := 24.0

var kind: String = "ground"
var model_id: String = ""
var display_name: String = ""
var max_speed: float = 20.0
var armor: float = 0.0
var health: float = 200.0

var driver: Player = null
var _model: Node3D
var _cam: Camera3D
var _yaw: float = 0.0
var _pitch: float = 0.0
var _hover_t: float = 0.0


func setup(id: String, p_kind: String, p_speed: float, p_armor: float, p_name: String) -> void:
	model_id = id
	kind = p_kind
	max_speed = p_speed
	armor = p_armor
	display_name = p_name


func _ready() -> void:
	collision_layer = 16
	collision_mask = 1 | 2 | 4
	if kind == "air":
		# 直升机不需要贴地，用浮动刚体式移动
		motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
		floor_stop_on_slope = false

	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.4, 1.6, 4.6) if kind == "ground" else Vector3(3.0, 2.2, 6.0)
	cs.shape = box
	cs.position.y = 1.0
	add_child(cs)

	_model = AssetLib.spawn(model_id, self, Vector3.ZERO, 0.0, true)
	if _model != null:
		_model.scale = Vector3.ONE * (1.0 if kind == "ground" else 1.05)
		AssetLib.apply_tint(_model, Loadout.camo_color())

	# 第三人称跟随相机
	var pivot := Node3D.new()
	pivot.position = Vector3(0, 2.2, 0)
	add_child(pivot)
	var spring := SpringArm3D.new()
	spring.spring_length = 8.5 if kind == "air" else 7.0
	spring.collision_mask = 1
	spring.rotation_degrees.x = -12.0
	pivot.add_child(spring)
	_cam = Camera3D.new()
	_cam.fov = 72.0
	_cam.far = 1600.0
	spring.add_child(_cam)
	_cam.current = false


# ---------------------------------------------------------------- 上下车
func interact_prompt() -> String:
	if driver != null:
		return ""
	return "驾驶 %s  [F]" % display_name


func interact(player: Node) -> void:
	if driver != null or not (player is Player):
		return
	enter(player as Player)


func enter(p: Player) -> void:
	driver = p
	p.vehicle = self
	p.set_physics_process(false)
	p.visible = false
	if p.camera != null:
		p.camera.current = false
	_cam.current = true
	_yaw = rotation.y
	EventBus.notify.emit("已进入 %s   （F 下车）" % display_name)


func exit_vehicle() -> void:
	if driver == null:
		return
	var p := driver
	driver = null
	p.vehicle = null
	p.visible = true
	p.global_position = global_position + Vector3(3.0, 1.0, 0)
	p.set_physics_process(true)
	_cam.current = false
	if p.camera != null:
		p.camera.current = true
	EventBus.notify.emit("已下车")


# ---------------------------------------------------------------- 驾驶
func _physics_process(delta: float) -> void:
	if driver == null:
		if kind == "ground":
			velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)
			if not is_on_floor():
				velocity.y -= GRAVITY * delta
			move_and_slide()
		return

	var throttle := Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")
	var steer := Input.get_action_strength("move_left") - Input.get_action_strength("move_right")
	var up := Input.get_action_strength("jump") - Input.get_action_strength("crouch")

	if Input.is_action_just_pressed("interact"):
		exit_vehicle()
		return

	if kind == "ground":
		_drive_ground(delta, throttle, steer)
	else:
		_fly(delta, throttle, steer, up)


func _drive_ground(delta: float, throttle: float, steer: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0

	_yaw -= steer * 1.6 * delta * clampf(velocity.length() / 6.0, 0.25, 1.0)
	rotation.y = _yaw

	var fwd := -global_transform.basis.z
	var target := fwd * throttle * max_speed
	velocity.x = move_toward(velocity.x, target.x, 14.0 * delta)
	velocity.z = move_toward(velocity.z, target.z, 14.0 * delta)

	# 地形起伏时车身贴合：给一点下压力
	if is_on_floor():
		velocity.y = -2.0
	move_and_slide()


func _fly(delta: float, throttle: float, steer: float, up: float) -> void:
	_hover_t += delta
	_yaw -= steer * 1.1 * delta
	rotation.y = _yaw

	var fwd := -global_transform.basis.z
	var speed := max_speed * (1.5 if Input.is_action_pressed("sprint") else 1.0)
	var target := fwd * throttle * speed
	velocity.x = move_toward(velocity.x, target.x, 10.0 * delta)
	velocity.z = move_toward(velocity.z, target.z, 10.0 * delta)
	velocity.y = move_toward(velocity.y, up * 9.0, 8.0 * delta)

	# 悬停微抖 + 姿态前倾
	if _model != null:
		_model.position.y = sin(_hover_t * 6.0) * 0.06
		_model.rotation.z = -steer * 0.12
		_model.rotation.x = -throttle * 0.10
	move_and_slide()


func take_damage(amount: float, _hit_pos: Vector3, source: Node) -> void:
	health -= amount * (1.0 - clampf(armor / 150.0, 0.0, 0.8))
	if health <= 0.0:
		EventBus.notify.emit("%s 被摧毁" % display_name)
		if driver != null:
			exit_vehicle()
		queue_free()
