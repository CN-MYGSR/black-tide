class_name ExtractionHeli
extends StaticBody3D
## 撤离直升机：从远处飞进来、降落、等玩家登机。

var state: String = "inbound"
var lz: Vector3 = Vector3.ZERO
var _t: float = 0.0
var _dur: float = 14.0
var _start: Vector3
var _model: Node3D
var _bob: float = 0.0


func setup(target: Vector3) -> void:
	lz = target
	_start = target + Vector3(260.0, 95.0, 190.0)
	global_position = _start


func _ready() -> void:
	collision_layer = 16
	collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6.0, 4.0, 12.0)
	cs.shape = box
	cs.position.y = 2.2
	add_child(cs)
	_model = AssetLib.spawn("SM_Veh_Helicopter_Transport_01", self, Vector3.ZERO, 0.0, true)
	if _model != null:
		_model.scale = Vector3.ONE * 1.1
	AudioSfx.create_engine(self, true).play()


func _process(delta: float) -> void:
	_bob += delta
	if state == "inbound":
		_t += delta
		var k := clampf(_t / _dur, 0.0, 1.0)
		var e := ease(k, 0.35)
		global_position = _start.lerp(lz + Vector3(0, 0.4, 0), e)
		rotation.y = lerp_angle(rotation.y, atan2(lz.x - global_position.x, lz.z - global_position.z), delta * 0.8)
		if _model != null:
			_model.rotation.z = sin(_bob * 1.2) * 0.03
		if k >= 1.0:
			state = "landed"
			rotation.y = 0.0
			EventBus.notify.emit("直升机已降落 —— 靠近后按 F 登机撤离")
	elif state == "landed":
		if _model != null:
			_model.position.y = sin(_bob * 3.0) * 0.02


func interact_prompt() -> String:
	if state == "landed":
		return "登机撤离 [F]"
	return ""


func interact(player: Node) -> void:
	if state != "landed" or not GameState.in_raid or not player is Player or player.state != Player.State.ALIVE:
		return
	state = "gone"
	var credits := 1200 + GameState.raid_loot
	EventBus.mission_completed.emit(credits, GameState.xp_for_credits(credits))
