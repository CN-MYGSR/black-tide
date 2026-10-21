class_name CharacterRig
extends RefCounted
## 程序化骨骼动画。
##
## POLYGON 的角色只带一套静态姿势，没有 walk / idle 动画片段。
## 这里直接驱动 50 根骨骼里的十几根关键骨，做出走、跑、瞄准、倒地。
##
## 难点：每根骨骼的局部轴都不一样（还有整体 90°X 的 Z-up 转换）。
## 所以不猜轴 —— 统一用角色模型的局部轴表达意图，再换算到骨骼局部。

const BONES := [
	"Hips", "Spine_01", "Spine_02", "Neck", "Head",
	"Shoulder_L", "Elbow_L", "Shoulder_R", "Elbow_R",
	"UpperLeg_L", "LowerLeg_L", "UpperLeg_R", "LowerLeg_R",
	"Ankle_L", "Ankle_R",
	"Clavicle_L", "Clavicle_R", "Hand_L", "Hand_R",
]

var skel: Skeleton3D
var ready: bool = false

var _idx: Dictionary = {}
var _inv: Dictionary = {}      ## bone -> 场景轴到骨骼局部的换算矩阵
var _base: Dictionary = {}     ## bone -> 默认 pose 四元数（不是单位四元数！）
var _base_position: Dictionary = {}
var _base_scale: Dictionary = {}
var _model_bone_scale: Dictionary = {}
var _acc: Dictionary = {}      ## bone -> 本帧累积的增量四元数

var _phase: float = 0.0
var _lean: float = 0.0
var _aim: float = 0.0
var _look_yaw: float = 0.0
var _model: Node3D
var _weapon_mount: Node3D
var _held_gun: Node3D
var _gloves: Array[Node3D] = []
var _glove_grips: Array[Transform3D] = []
var _wrists: Array[Transform3D] = []
var _loose_hands: Array[BoneAttachment3D] = []
var _hold_type := 0
var _released := false


func setup(model_root: Node3D) -> bool:
	if model_root == null:
		return false
	_model = model_root
	var stack: Array[Node] = [model_root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Skeleton3D:
			skel = n as Skeleton3D
			break
		for c in n.get_children():
			stack.append(c)
	if skel == null:
		return false
	# 关键：这个 GLB 的默认 pose 不是单位四元数（Root 90°、Spine 180°…）。
	# 直接把骨骼设成 identity 等于把角色掰平 —— 必须先记下默认姿势，增量叠在它上面。
	for b in BONES:
		var i := skel.find_bone(b)
		if i < 0:
			continue
		_idx[b] = i
		_base[b] = skel.get_bone_pose_rotation(i)
		_base_position[b] = skel.get_bone_pose_position(i)
		_base_scale[b] = skel.get_bone_pose_scale(i)
		var pose_global: Transform3D = skel.get_bone_global_pose(i)
		# 排除角色的朝向，避免转身后摆腿或举枪反向。
		var model_basis := model_root.global_transform.basis.inverse() * skel.global_transform.basis
		_model_bone_scale[b] = (model_basis * pose_global.basis).get_scale()
		_inv[b] = (model_basis * pose_global.basis).inverse()
	ready = _idx.size() >= 8
	return ready


func has_bone(b: String) -> bool:
	return _idx.has(b)


func attach_weapon(weapon: String, model: Node3D) -> Node3D:
	if not ready or skel == null:
		return null
	var hand := skel.find_bone("Hand_R")
	if hand < 0:
		return null
	if skel.find_bone("Spine_03") < 0:
		_weapon_mount = Node3D.new()
		_weapon_mount.name = "WeaponMount"
		model.add_child(_weapon_mount)
		_held_gun = AssetLib.spawn(weapon, _weapon_mount)
		if _held_gun == null:
			_weapon_mount.queue_free()
			return null
		_hold_type = 1 if weapon.contains("Pistol") else (2 if weapon.contains("RPG") or weapon.contains("RocketLauncher") else 0)
		_gloves.clear()
		_glove_grips.clear()
		_wrists.clear()
		_released = false
		var support := _held_gun.find_child("BT_GripL", true, false) as Node3D
		for side in ["R", "L"]:
			var glove := AssetLib.spawn("BT_Hand_" + side + ("_Pistol" if _hold_type == 1 else "_Rifle"), _held_gun)
			if side == "L" and support != null:
				glove.position = _held_gun.to_local(support.global_position)
			var wrist := glove.find_child("BT_Wrist", true, false) as Node3D
			_gloves.append(glove)
			_glove_grips.append(glove.transform)
			_wrists.append(glove.global_transform.affine_inverse() * wrist.global_transform)
		_pose_weapon()
		return _held_gun
	var attachment := BoneAttachment3D.new()
	attachment.name = "WeaponBone"
	attachment.bone_name = "Hand_R"
	skel.add_child(attachment)
	var gun := AssetLib.spawn(weapon, attachment)
	if gun == null:
		attachment.queue_free()
		return null
	gun.scale = Vector3.ONE * 100.0
	gun.position = Vector3(6.0, -3.0, 4.0)
	gun.rotation_degrees = Vector3(0, 90, -90)
	return gun


func _pose_weapon() -> void:
	if not is_instance_valid(_held_gun):
		return
	if _released:
		for i in _gloves.size():
			_gloves[i].reparent(_held_gun, false)
			_gloves[i].transform = _glove_grips[i]
		for attachment in _loose_hands:
			attachment.queue_free()
		_loose_hands.clear()
		_released = false
	_held_gun.visible = true
	var grip := Vector3(-0.04, lerpf(1.30, 1.45, _aim), lerpf(0.10, 0.17, _aim))
	if _hold_type == 1:
		grip = Vector3(0, lerpf(1.18, 1.50, _aim), lerpf(0.25, 0.42, _aim))
	elif _hold_type == 2:
		grip = Vector3(-0.20, lerpf(1.28, 1.45, _aim), 0.02)
	grip.y += sin(_phase * 2) * _lean * 0.004
	var pitch := lerpf(0.18 if _hold_type != 2 else 0.05, 0, _aim)
	_weapon_mount.transform = Transform3D(Basis.from_euler(Vector3(pitch, _look_yaw * 0.4, 0)), grip)
	var model_from_skeleton := _model.global_transform.affine_inverse() * skel.global_transform
	for side in ["R", "L"]:
		var clavicle := skel.find_bone("Clavicle_" + side)
		var pose := model_from_skeleton * skel.get_bone_global_pose(clavicle)
		pose.origin += Vector3(0.015 if side == "R" else -0.015, 0, lerpf(0.06, 0.075, _aim))
		skel.set_bone_global_pose(clavicle, model_from_skeleton.affine_inverse() * pose)
	for i in _gloves.size():
		var target := _model.global_transform.affine_inverse() * _gloves[i].global_transform * _wrists[i]
		_solve_arm("R" if i == 0 else "L", target, model_from_skeleton)


func _solve_arm(side: String, target: Transform3D, model_from_skeleton: Transform3D) -> void:
	var upper := skel.find_bone("Shoulder_" + side)
	var fore := skel.find_bone("Elbow_" + side)
	var hand := skel.find_bone("Hand_" + side)
	var u := model_from_skeleton * skel.get_bone_global_pose(upper)
	var f := model_from_skeleton * skel.get_bone_global_pose(fore)
	var wrist := (model_from_skeleton * skel.get_bone_global_pose(hand)).origin
	var a := u.origin.distance_to(f.origin)
	var b := f.origin.distance_to(wrist)
	var direction := (target.origin - u.origin).normalized()
	var distance := clampf(u.origin.distance_to(target.origin), absf(a - b) + 0.001, a + b - 0.001)
	var along := (a * a - b * b + distance * distance) / (2 * distance)
	var pole := Vector3(-0.55 if side == "R" else 0.55, 1.02, 0.02) - u.origin
	pole -= direction * pole.dot(direction)
	var elbow := u.origin + direction * along + pole.normalized() * sqrt(maxf(0, a * a - along * along))
	var rotation := Quaternion((f.origin - u.origin).normalized(), (elbow - u.origin).normalized())
	u.basis = Basis(rotation) * u.basis
	skel.set_bone_global_pose(upper, model_from_skeleton.affine_inverse() * u)
	f = model_from_skeleton * skel.get_bone_global_pose(fore)
	wrist = (model_from_skeleton * skel.get_bone_global_pose(hand)).origin
	rotation = Quaternion((wrist - f.origin).normalized(), (target.origin - f.origin).normalized())
	f.basis = Basis(rotation) * f.basis
	skel.set_bone_global_pose(fore, model_from_skeleton.affine_inverse() * f)
	var h := model_from_skeleton * skel.get_bone_global_pose(hand)
	h.basis = target.basis.orthonormalized().scaled(_model_bone_scale["Hand_" + side])
	skel.set_bone_global_pose(hand, model_from_skeleton.affine_inverse() * h)


func _release_weapon() -> void:
	if not is_instance_valid(_held_gun) or _released:
		return
	for i in _gloves.size():
		var attachment := BoneAttachment3D.new()
		attachment.bone_name = "Hand_R" if i == 0 else "Hand_L"
		skel.add_child(attachment)
		_gloves[i].reparent(attachment, true)
		var wrist := skel.global_transform * skel.get_bone_global_pose(skel.find_bone(attachment.bone_name))
		wrist.basis = wrist.basis.orthonormalized()
		_gloves[i].global_transform = wrist * _wrists[i].affine_inverse()
		_loose_hands.append(attachment)
	_held_gun.visible = false
	_released = true


# ---------------------------------------------------------------- 帧内累积
func begin() -> void:
	_acc.clear()


func rot(bone: String, axis_scene: Vector3, angle: float) -> void:
	if not _idx.has(bone) or is_zero_approx(angle):
		return
	var m: Basis = _inv[bone]
	var axis := (m * axis_scene).normalized()
	if axis.length_squared() < 0.001:
		return
	var q := Quaternion(axis, angle)
	if _acc.has(bone):
		_acc[bone] = q * (_acc[bone] as Quaternion)
	else:
		_acc[bone] = q


func flush() -> void:
	for b in _idx.keys():
		skel.set_bone_pose_position(_idx[b], _base_position[b])
		skel.set_bone_pose_scale(_idx[b], _base_scale[b])
		var base: Quaternion = _base[b]
		if _acc.has(b):
			# 增量作用在骨骼自身坐标系里，所以叠在默认姿势之后
			skel.set_bone_pose_rotation(_idx[b], base * (_acc[b] as Quaternion))
		else:
			skel.set_bone_pose_rotation(_idx[b], base)


func reset() -> void:
	_acc.clear()
	if skel == null:
		return
	for b in _idx.keys():
		skel.set_bone_pose_rotation(_idx[b], _base[b])
		skel.set_bone_pose_position(_idx[b], _base_position[b])
		skel.set_bone_pose_scale(_idx[b], _base_scale[b])


# ---------------------------------------------------------------- 姿态
## speed_ratio: 0~1（相对跑步速度），aim: 0~1 举枪程度
func animate_locomotion(delta: float, speed_ratio: float, aim: float, look_yaw: float = 0.0) -> void:
	if not ready:
		return
	var r := clampf(speed_ratio, 0.0, 1.0)
	_aim = lerpf(_aim, clampf(aim, 0.0, 1.0), delta * 6.0)
	_look_yaw = lerpf(_look_yaw, look_yaw, delta * 6.0)
	_lean = lerpf(_lean, r, delta * 5.0)

	# 步频：慢走 ~1.6 步/秒，冲刺 ~3 步/秒
	_phase += delta * lerpf(1.6, 3.2, r) * TAU
	if r < 0.02:
		_phase = lerpf(_phase, 0.0, delta * 4.0)

	var swing := sin(_phase)
	var swing2 := sin(_phase + PI)
	var amp := lerpf(0.10, 0.62, r)

	begin()

	# 腿：大腿前后摆，膝盖只往后弯
	rot("UpperLeg_L", Vector3.RIGHT, swing * amp)
	rot("UpperLeg_R", Vector3.RIGHT, swing2 * amp)
	var knee_l := -maxf(0.0, -swing) * lerpf(0.25, 1.0, r)
	var knee_r := -maxf(0.0, -swing2) * lerpf(0.25, 1.0, r)
	rot("LowerLeg_L", Vector3.RIGHT, knee_l)
	rot("LowerLeg_R", Vector3.RIGHT, knee_r)
	rot("Ankle_L", Vector3.RIGHT, -knee_l * 0.4)
	rot("Ankle_R", Vector3.RIGHT, -knee_r * 0.4)

	# 躯干：跑起来前倾 + 轻微左右摆
	rot("Spine_01", Vector3.RIGHT, -_lean * 0.16)
	rot("Spine_02", Vector3.RIGHT, -_lean * 0.10)
	rot("Spine_02", Vector3.UP, sin(_phase) * 0.05 * r)
	rot("Hips", Vector3.UP, -sin(_phase) * 0.08 * r)

	# 头：看向目标方向
	rot("Neck", Vector3.UP, _look_yaw * 0.4)
	rot("Head", Vector3.UP, _look_yaw * 0.6)
	rot("Head", Vector3.RIGHT, -0.05 * _lean)

	# 手臂：T-pose 先放下来（绕前后轴转），持枪时再往前送一点
	# 注意：左臂指向 +X、右臂指向 -X，所以同一个"往下"要一正一负
	var arm_swing := (1.0 - _aim) * 0.35 * r
	var down := 1.12
	var fwd := 0.38 * _aim
	rot("Shoulder_L", Vector3.BACK, -down)
	rot("Shoulder_R", Vector3.BACK, down)
	rot("Shoulder_L", Vector3.RIGHT, -fwd + swing2 * arm_swing * 0.5)
	rot("Shoulder_R", Vector3.RIGHT, -fwd + swing * arm_swing * 0.5)
	# 小臂：持枪时收起来，走路时轻微跟随
	rot("Elbow_L", Vector3.RIGHT, -0.55 * _aim - maxf(0.0, swing2) * 0.18 * arm_swing)
	rot("Elbow_R", Vector3.RIGHT, -0.75 * _aim - maxf(0.0, swing) * 0.18 * arm_swing)

	flush()
	_pose_weapon()


## 倒地：四肢摊开、头歪向一边
func pose_downed() -> void:
	if not ready:
		return
	begin()
	rot("UpperLeg_L", Vector3.RIGHT, 0.25)
	rot("UpperLeg_R", Vector3.RIGHT, -0.1)
	rot("LowerLeg_L", Vector3.RIGHT, -0.5)
	rot("Shoulder_L", Vector3.RIGHT, -0.9)
	rot("Shoulder_R", Vector3.RIGHT, -0.5)
	rot("Elbow_L", Vector3.RIGHT, -0.9)
	rot("Neck", Vector3.UP, 0.4)
	rot("Head", Vector3.UP, 0.5)
	flush()
	_release_weapon()


## 死亡：彻底松掉
func pose_dead() -> void:
	if not ready:
		return
	begin()
	rot("UpperLeg_L", Vector3.RIGHT, 0.35)
	rot("UpperLeg_R", Vector3.RIGHT, -0.2)
	rot("LowerLeg_L", Vector3.RIGHT, -0.8)
	rot("Shoulder_L", Vector3.RIGHT, -1.2)
	rot("Shoulder_R", Vector3.RIGHT, -0.7)
	rot("Elbow_L", Vector3.RIGHT, -0.6)
	rot("Elbow_R", Vector3.RIGHT, -0.4)
	rot("Spine_02", Vector3.UP, 0.25)
	rot("Neck", Vector3.UP, 0.5)
	flush()
	_release_weapon()
