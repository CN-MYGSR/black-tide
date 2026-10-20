class_name Squad
extends Node
## AI 小队：把一群各自为战的士兵编成班组，让它们共享情报、按战术行动。
##
## 参考真实步兵班的两条核心：
##   1) 一个人看见 ≠ 全队看见 —— 但看见了就要喊出来（共享接触点）
##   2) 不要全员一起冲 —— 两个火力组交替：一组压制、一组跃进（bounding overwatch）
##
## 状态机：
##   PATROL ──发现敌人──> CONTACT ──2s──> ASSAULT ──减员过半──> BROKEN
##      ↑                    │              │                    │
##      └──── 丢失接触 8s ────┘              └──── 撤离回家 <──────┘

enum State { PATROL, CONTACT, ASSAULT, BROKEN }

const CONTACT_HOLD := 1.8        ## 接触后先稳住多久再突击
const CONTACT_LOST := 8.0        ## 多久没再看到人就算丢失接触
const ASSAULT_SWITCH := 4.5      ## 两个火力组交替的间隔
const BREAK_MORALE := 0.35       ## 士气低于此值就溃退

var squad_id: String = ""
var faction: String = "opfor"
var state: int = State.PATROL
var morale: float = 1.0

var members: Array = []
var leader = null
var follow_target: Node3D = null      ## 友军小队跟着玩家走
var home: Vector3 = Vector3.ZERO
var patrol_center: Vector3 = Vector3.ZERO
var patrol_radius: float = 25.0
var patrol_points: Array[Vector3] = []

var contact_pos: Vector3 = Vector3.ZERO
var contact_time: float = -999.0
var has_contact: bool = false
var _contact_target: Node3D = null

var _state_t: float = 0.0
var _assault_t: float = 0.0
var _phase: int = 0                  ## 0/1 两个火力组轮流
var _patrol_idx: int = 0
var _reported: bool = false


func setup(p_faction: String, p_id: String, center: Vector3, radius: float = 25.0) -> void:
	faction = p_faction
	squad_id = p_id
	home = center
	patrol_center = center
	patrol_radius = radius
	_build_patrol_points()


func _build_patrol_points() -> void:
	patrol_points.clear()
	for i in 4:
		var a := TAU * float(i) / 4.0 + randf() * 0.4
		var r := patrol_radius * randf_range(0.45, 0.95)
		patrol_points.append(patrol_center + Vector3(cos(a) * r, 0, sin(a) * r))


# ---------------------------------------------------------------- 编组
func add_member(s: Node, role: String = "") -> void:
	if s == null or members.has(s):
		return
	members.append(s)
	s.squad = self
	if role == "":
		role = _default_role(members.size() - 1)
	s.squad_role = role
	_apply_role(s, role)
	if leader == null and role == "leader":
		leader = s
	if leader == null:
		leader = s


func _default_role(index: int) -> String:
	match index:
		0:
			return "leader"
		1:
			return "support"
		2:
			return "marksman"
		_:
			return "rifleman"


func _apply_role(s: Node, role: String) -> void:
	match role:
		"leader":
			s.accuracy = minf(0.95, s.accuracy + 0.08)
			s.health += 25.0
			s.max_health = s.health
		"support":
			s.weapon_damage += 4.0
			s.fire_interval = maxf(0.16, s.fire_interval - 0.09)
			s.accuracy = maxf(0.15, s.accuracy - 0.05)
		"marksman":
			s.accuracy = minf(0.97, s.accuracy + 0.16)
			s.weapon_range += 70.0
			s.view_distance += 30.0
			s.fire_interval += 0.25
		_:
			pass


func alive_members() -> Array:
	var out: Array = []
	for m in members:
		if is_instance_valid(m) and m.has_method("is_alive") and m.is_alive():
			out.append(m)
	return out


func size() -> int:
	return members.size()


# ---------------------------------------------------------------- 情报共享
func report_contact(pos: Vector3, target: Node3D = null) -> void:
	contact_pos = pos
	contact_time = Time.get_ticks_msec() / 1000.0
	has_contact = true
	if target != null and is_instance_valid(target):
		_contact_target = target
	if state == State.PATROL:
		state = State.CONTACT
		_state_t = 0.0
		_assault_t = 0.0
		_phase = 0
		if not _reported and (faction == "opfor" or faction == "rival"):
			_reported = true
			EventBus.notify.emit("遭遇敌军小队（%d 人）" % members.size())


func on_member_down(s: Node) -> void:
	members.erase(s)
	var ratio := float(alive_members().size()) / maxf(1.0, float(members.size() + 1))
	morale = clampf(morale - 0.22, 0.0, 1.0)
	if leader == s or not is_instance_valid(leader):
		leader = null
		for m in alive_members():
			if m.squad_role != "leader":
				leader = m
				m.squad_role = "leader"
				break
	if morale <= BREAK_MORALE or alive_members().size() <= 1:
		state = State.BROKEN
		_state_t = 0.0
	elif ratio < 0.5:
		morale = clampf(morale - 0.1, 0.0, 1.0)


# ---------------------------------------------------------------- 每帧
func _process(delta: float) -> void:
	members = members.filter(func(m): return is_instance_valid(m))
	if members.is_empty():
		return
	_state_t += delta
	var now := Time.get_ticks_msec() / 1000.0
	if has_contact and now - contact_time > CONTACT_LOST:
		has_contact = false
		_contact_target = null
		if state != State.BROKEN:
			state = State.PATROL
			_state_t = 0.0

	match state:
		State.PATROL:
			_patrol(delta)
		State.CONTACT:
			if _state_t >= CONTACT_HOLD:
				state = State.ASSAULT
				_state_t = 0.0
				_assault_t = 0.0
		State.ASSAULT:
			_assault_t += delta
			if _assault_t >= ASSAULT_SWITCH:
				_assault_t = 0.0
				_phase = 1 - _phase
		State.BROKEN:
			pass


func _patrol(delta: float) -> void:
	## 由队长带路，其他人按楔形跟随
	if follow_target != null and is_instance_valid(follow_target):
		return
	if leader == null or not is_instance_valid(leader):
		return
	if patrol_points.is_empty():
		return
	var goal: Vector3 = patrol_points[_patrol_idx % patrol_points.size()]
	if leader.global_position.distance_to(goal) < 4.0:
		_patrol_idx += 1


# ---------------------------------------------------------------- 下达指令
## 返回 {mode: "hold"/"advance"/"retreat"/"formation", pos: Vector3, suppress: bool}
func order_for(s: Node) -> Dictionary:
	var idx := members.find(s)
	if idx < 0:
		idx = 0
	match state:
		State.BROKEN:
			return {"mode": "retreat", "pos": home, "suppress": false}
		State.ASSAULT:
			var team := idx % 2
			if team == _phase:
				# 这一组跃进：绕到接触点的侧翼
				return {"mode": "advance", "pos": _flank_point(idx), "suppress": false}
			return {"mode": "hold", "pos": s.global_position, "suppress": true}
		State.CONTACT:
			return {"mode": "hold", "pos": s.global_position, "suppress": true}
		_:
			return {"mode": "formation", "pos": _formation_point(idx), "suppress": false}


func _flank_point(idx: int) -> Vector3:
	## 以"小队中心 -> 接触点"为轴，取侧向 14~20m 的位置
	var from: Vector3 = leader.global_position if (leader != null and is_instance_valid(leader)) else patrol_center
	var d: Vector3 = contact_pos - from
	d.y = 0.0
	if d.length_squared() < 0.01:
		return contact_pos
	d = d.normalized()
	var side := Vector3(-d.z, 0, d.x)
	var sign_ := 1.0 if idx % 4 < 2 else -1.0
	var dist := 15.0 + float(idx % 3) * 3.0
	return contact_pos + side * sign_ * dist - d * 6.0


func _formation_point(idx: int) -> Vector3:
	## 楔形队形：队长在前，其余左右交替、依次靠后
	if leader == null or not is_instance_valid(leader):
		return patrol_center
	if idx == 0:
		if patrol_points.is_empty():
			return leader.global_position
		return patrol_points[_patrol_idx % patrol_points.size()]
	var fwd: Vector3 = -leader.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var side := Vector3(-fwd.z, 0, fwd.x)
	var row := float((idx + 1) / 2)
	var sign_ := 1.0 if idx % 2 == 1 else -1.0
	return leader.global_position + side * sign_ * (2.2 * row) - fwd * (2.6 * row)


func is_broken() -> bool:
	return state == State.BROKEN


func status_text() -> String:
	match state:
		State.PATROL:
			return "巡逻"
		State.CONTACT:
			return "接触"
		State.ASSAULT:
			return "突击"
		State.BROKEN:
			return "溃退"
	return "?"
