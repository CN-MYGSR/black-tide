extends Node

func _ready() -> void:
	var n := AssetLib.spawn("SM_Chr_Soldier_Male_01", self)
	await get_tree().process_frame
	var skel: Skeleton3D = null
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is Skeleton3D:
			skel = cur as Skeleton3D
		for c in cur.get_children():
			stack.append(c)
	if skel == null:
		print("NO SKELETON")
		get_tree().quit()
		return
	print("bones=", skel.get_bone_count())
	for name in ["Root","Hips","Spine_01","Spine_02","Neck","Head","Clavicle_L","Shoulder_L","Elbow_L","Hand_L","UpperLeg_L","LowerLeg_L","Ankle_L","UpperLeg_R"]:
		var i := skel.find_bone(name)
		if i < 0:
			print(name, " 缺失")
			continue
		var rest := skel.get_bone_rest(i)
		var g := skel.get_bone_global_rest(i)
		print("%-12s idx=%2d  rest.basis.x=%s  y=%s  z=%s  origin=%s" % [
			name, i,
			str(rest.basis.x.snapped(Vector3.ONE*0.01)),
			str(rest.basis.y.snapped(Vector3.ONE*0.01)),
			str(rest.basis.z.snapped(Vector3.ONE*0.01)),
			str(g.origin.snapped(Vector3.ONE*0.01))])
	get_tree().quit()
