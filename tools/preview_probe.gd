extends Node
func _ready() -> void:
	var w := AssetLib.spawn("SM_Wep_Preset_A_Rifle_01", self)
	await get_tree().process_frame
	print("meta size=", AssetLib.size_of("SM_Wep_Preset_A_Rifle_01"))
	var stack: Array = [[w, Transform3D.IDENTITY]]
	var out := AABB()
	var first := true
	while not stack.is_empty():
		var it: Array = stack.pop_back()
		var n: Node = it[0]
		var xf: Transform3D = it[1]
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var a: AABB = xf * (n as MeshInstance3D).get_aabb()
			if first:
				out = a
				first = false
			else:
				out = out.merge(a)
		for c in n.get_children():
			var local: Transform3D = (c as Node3D).transform if c is Node3D else Transform3D.IDENTITY
			stack.append([c, xf * local])
	print("accumulated aabb size=", out.size, " center=", out.get_center())
	print("wrapper scale=", w.scale, " child scale=", (w.get_child(0) as Node3D).scale if w.get_child(0) is Node3D else "?")
	get_tree().quit()
