class_name CharacterRig
extends RefCounted
## 程序化骨骼动画。
##
## POLYGON 的角色只带一套静态姿势，没有 walk / idle 动画片段。
## 这里直接驱动 50 根骨骼里的十几根关键骨，做出走、跑、瞄准、倒地。
##
## 难点：每根骨骼的局部轴都不一样（还有整体 90°X 的 Z-up 转换）。
## 所以不猜轴 —— 统一用"场景空间轴"表达意图，再换算到骨骼局部：
##   bone_axis = (skeleton_global_basis * bone_global_rest.basis).inverse() * scene_axis
## 这样无论骨骼怎么摆，"绕世界 X 轴转 20 度" 都是同一个意思。

const BONES := [
	"Hips", "Spine_01", "Spine_02", "Neck", "Head",
	"Shoulder_L", "Elbow_L", "Shoulder_R", "Elbow_R",
	"UpperLeg_L", "LowerLeg_L", "UpperLeg_R", "LowerLeg_R",
	"Ankle_L", "Ankle_R",
]

var skel: Skeleton3D
var ready: bool = false

var _idx: Dictionary = {}
var _inv: Dictionary = {}      ## bone -> 场景轴到骨骼局部的换算矩阵
var _base: Dictionary = {}     ## bone -> 默认 pose 四元数（不是单位四元数！）
var _acc: Dictionary = {}      ## bone -> 本帧累积的增量四元数

var _phase: float = 0.0
var _lean: float = 0.0
var _aim: float = 0.0
var _look_yaw: float = 0.0


func setup(model_root: Node3D) -> bool:
	if model_root == null:
		return false
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
		var pose_global: Transform3D = skel.get_bone_global_pose(i)
		# 场景轴 -> 骨骼局部轴 的换算矩阵
		_inv[b] = (skel.global_transform.basis * pose_global.basis).inverse()
	ready = _idx.size() >= 8
	return ready


func has_bone(b: String) -> bool:
	return _idx.has(b)


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
