extends Node

func _ready() -> void:
	var w := WorldRoot.new()
	add_child(w)
	w.generate(20261019)
	var fob: Node = null
	for p in w.pois:
		if str(p["id"]) == "fob":
			fob = p.get("node")
	var shown := 0
	var stack: Array[Node] = [fob]
	while not stack.is_empty() and shown < 8:
		var cur: Node = stack.pop_back()
		if cur is Node3D and str(cur.name).begins_with("SM_Prop_Barrier_Tall_Group_01"):
			var n3 := cur as Node3D
			var rel: Vector3 = n3.global_position - (fob as Node3D).global_position
			print("rel=(%.1f, %.1f)  yaw=%.1f  basis.z=(%.2f, %.2f, %.2f)" % [
				rel.x, rel.z, rad_to_deg(n3.rotation.y),
				n3.global_transform.basis.z.x, n3.global_transform.basis.z.y, n3.global_transform.basis.z.z])
			shown += 1
		for c in cur.get_children():
			stack.append(c)
	get_tree().quit()
