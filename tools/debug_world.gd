extends Node
## 调试：打印世界几何与光照的关键数值，定位"画面全黑"。

func _ready() -> void:
	var main: Node3D = load("res://src/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(2.0).timeout

	var w: WorldRoot = main.world
	print("--- POI 高度 ---")
	for p in w.pois:
		var h: float = w.terrain.height_at(p["pos"].x, p["pos"].y)
		print("  %-8s pos=(%.0f, %.0f) h=%.1f" % [str(p["id"]), p["pos"].x, p["pos"].y, h])

	var player: Player = main.player
	print("玩家位置: ", player.global_position)
	print("玩家是否落地: ", player.is_on_floor())

	var fob: Dictionary = w.poi_by_id("fob")
	var fob_pos := Vector3(fob["pos"].x, w.terrain.height_at(fob["pos"].x, fob["pos"].y), fob["pos"].y)
	print("FOB 中心: ", fob_pos)

	var cam := Camera3D.new()
	cam.far = 3000.0
	add_child(cam)
	cam.global_position = fob_pos + Vector3(60, 55, 70)
	cam.look_at(fob_pos, Vector3.UP)
	cam.current = true
	await get_tree().process_frame

	var space := get_viewport().world_3d.direct_space_state
	var q := PhysicsRayQueryParameters3D.create(cam.global_position, cam.global_position + Vector3(0, -400, 0), 1)
	var hit := space.intersect_ray(q)
	print("向下射线: ", hit.get("position", "无"))

	var q2 := PhysicsRayQueryParameters3D.create(cam.global_position, fob_pos, 1 | 4 | 16)
	var hit2 := space.intersect_ray(q2)
	print("看向FOB的射线: ", hit2.get("collider", "无"), " @ ", hit2.get("position", ""))

	# 统计附近几何
	var near := 0
	for n in get_tree().get_nodes_in_group("combatant"):
		pass
	var stack: Array[Node] = [main]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is MeshInstance3D:
			var mi := cur as MeshInstance3D
			if mi.global_position.distance_to(fob_pos) < 120.0:
				near += 1
		for c in cur.get_children():
			stack.append(c)
	print("FOB 120m 内的 MeshInstance3D: ", near)

	var env: WorldEnvironment = main.world.env
	print("WorldEnvironment: ", env)
	if env != null:
		print("  background=", env.environment.background_mode, " sky=", env.environment.sky,
			" ambient=", env.environment.ambient_light_source, " energy=", env.environment.ambient_light_energy)
	print("Sun: ", main.world.sun, " rot=", main.world.sun.rotation_degrees if main.world.sun else null)
	get_tree().quit()
