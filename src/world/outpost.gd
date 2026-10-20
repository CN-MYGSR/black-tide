class_name Outpost
extends Node3D
## 可争夺据点。规则参考 BRM5 的"据点控制"：站在圈里、圈里没有敌人，进度条才涨。

const CAPTURE_RATE := 9.0        ## 每秒进度
const DECAY_RATE := 4.0          ## 没人时回退速度
const MAX_PROGRESS := 100.0

@export var outpost_id: String = ""
@export var display_name: String = ""
@export var radius: float = 26.0
@export var owner_faction: String = "opfor"
@export var capturable: bool = true

var progress: float = 0.0
var contested: bool = false
var _area: Area3D
var _flag: MeshInstance3D
var _pole: MeshInstance3D
var _bodies: Array[Node3D] = []
var _captured_once: bool = false

const COL_OPFOR := Color(0.72, 0.16, 0.14)
const COL_BLUFOR := Color(0.16, 0.42, 0.78)
const COL_NEUTRAL := Color(0.75, 0.72, 0.62)


func setup(p_id: String, p_name: String, p_radius: float, p_owner: String) -> void:
	outpost_id = p_id
	display_name = p_name
	radius = p_radius
	owner_faction = p_owner


func _ready() -> void:
	_area = Area3D.new()
	_area.collision_layer = 16
	_area.collision_mask = 2 | 4
	_area.monitoring = true
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = 40.0
	cs.shape = cyl
	cs.position.y = 18.0
	_area.add_child(cs)
	add_child(_area)
	_area.body_entered.connect(_on_body_entered)
	_area.body_exited.connect(_on_body_exited)

	_build_flag()


func _build_flag() -> void:
	_pole = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.08
	cyl.bottom_radius = 0.1
	cyl.height = 7.0
	_pole.mesh = cyl
	_pole.position.y = 3.5
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.22, 0.22, 0.24)
	pole_mat.metallic = 0.6
	pole_mat.roughness = 0.4
	_pole.material_override = pole_mat
	add_child(_pole)

	_flag = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.8, 1.1)
	_flag.mesh = quad
	_flag.position = Vector3(0.9, 6.2, 0.0)
	_flag.material_override = _flag_material()
	add_child(_flag)


func _flag_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = _owner_color()
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.emission_enabled = true
	m.emission = _owner_color() * 0.35
	return m


func _owner_color() -> Color:
	match owner_faction:
		"opfor":
			return COL_OPFOR
		"blufor":
			return COL_BLUFOR
		_:
			return COL_NEUTRAL


func _on_body_entered(body: Node3D) -> void:
	if body not in _bodies:
		_bodies.append(body)


func _on_body_exited(body: Node3D) -> void:
	_bodies.erase(body)


func _process(delta: float) -> void:
	if not capturable or _captured_once and owner_faction == "blufor":
		return

	var attackers := 0
	var defenders := 0
	var alive: Array[Node3D] = []
	for b in _bodies:
		if not is_instance_valid(b):
			continue
		if b.has_method("is_alive") and not b.is_alive():
			continue
		alive.append(b)
		if b.get("faction") == "player" or b.get("faction") == "blufor":
			attackers += 1
		elif b.get("faction") == "opfor":
			defenders += 1
	_bodies = alive

	contested = attackers > 0 and defenders > 0

	if owner_faction == "blufor":
		# 已经拿下来了，敌人站进来会反推
		if defenders > 0 and attackers == 0:
			progress = maxf(0.0, progress - DECAY_RATE * delta)
			if progress <= 0.0:
				_set_owner("opfor")
		return

	if attackers > 0 and defenders == 0:
		progress = minf(MAX_PROGRESS, progress + CAPTURE_RATE * delta)
		EventBus.outpost_progress.emit(self, progress)
		if progress >= MAX_PROGRESS:
			_set_owner("blufor")
			_captured_once = true
			EventBus.outpost_captured.emit(self, "blufor")
			EventBus.notify.emit("据点已控制：%s" % display_name)
	elif attackers == 0 and progress > 0.0:
		progress = maxf(0.0, progress - DECAY_RATE * delta)
		EventBus.outpost_progress.emit(self, progress)


func _set_owner(faction: String) -> void:
	owner_faction = faction
	progress = 0.0
	if _flag != null:
		var m := StandardMaterial3D.new()
		m.albedo_color = _owner_color()
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.emission_enabled = true
		m.emission = _owner_color() * 0.35
		_flag.material_override = m


func is_owned_by_player() -> bool:
	return owner_faction == "blufor"


func status_text() -> String:
	if owner_faction == "blufor":
		return "%s 已控制" % display_name
	if contested:
		return "%s 争夺中" % display_name
	if progress > 0.0:
		return "%s 控制中 %d%%" % [display_name, int(progress)]
	return "%s 敌方控制" % display_name
