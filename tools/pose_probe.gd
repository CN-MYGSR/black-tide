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
	for b in ["Root","Hips","Spine_01","UpperLeg_L","Shoulder_L"]:
		var i := skel.find_bone(b)
		if i < 0: continue
		var q := skel.get_bone_pose_rotation(i)
		var r := skel.get_bone_rest(i)
		print("%-11s pose.angle=%.1f°  rest.angle=%.1f°  pose=%s" % [
			b, rad_to_deg(q.get_angle()), rad_to_deg(r.basis.get_rotation_quaternion().get_angle()),
			str(q)])
	get_tree().quit()
