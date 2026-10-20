extends Node

func _ready() -> void:
	for m in ["SM_Chr_Soldier_Male_01", "SM_Chr_Insurgent_Male_01", "SM_Bld_Barracks_01",
			"SM_Veh_APC_01", "SM_Env_Tree_01", "SM_Wep_Preset_A_Rifle_01"]:
		var n := AssetLib.spawn(m, null)
		if n == null:
			print(m, " -> null")
			continue
		var total := AABB()
		var first := true
		var stack: Array[Node] = [n]
		while not stack.is_empty():
			var cur: Node = stack.pop_back()
			if cur is MeshInstance3D:
				var mi := cur as MeshInstance3D
				var a := mi.get_aabb()
				if first:
					total = a
					first = false
				else:
					total = total.merge(a)
			for c in cur.get_children():
				stack.append(c)
		print("%-32s aabb size=%s" % [m, str(total.size)])
		n.free()
	get_tree().quit()
