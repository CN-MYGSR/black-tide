class_name LootCrate
extends StaticBody3D
## 可搜刮的补给箱。给玩家一个"往前走有收益"的理由。

var credits: int = 180
var opened: bool = false
var _model: Node3D
var _label: Label3D


func setup(credits_value: int, model_name: String = "SM_Prop_Crate_Ammo_01") -> void:
	credits = credits_value
	collision_layer = 1
	collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 1.0, 1.0)
	cs.shape = box
	cs.position.y = 0.5
	add_child(cs)
	_model = AssetLib.spawn(model_name, self, Vector3.ZERO, randf() * TAU, true)


func interact_prompt() -> String:
	if opened:
		return ""
	return "搜刮补给 [F]"


func interact(_player: Node) -> void:
	if opened:
		return
	opened = true
	GameState.raid_loot += credits
	EventBus.notify.emit("搜刮到 %d 信用点" % credits)
	if _model != null:
		_model.rotation_degrees.z = 8.0
		_model.position.y = -0.06
	# 收完就别再提示了
	collision_layer = 0
