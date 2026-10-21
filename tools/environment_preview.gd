extends Node3D
## Repeatable, isolated environment visual check; no player saves or combat AI.

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var world := WorldRoot.new()
	add_child(world)
	world.generate(20261019)
	assert(world.terrain.mesh_instance.mesh.surface_get_material(0) is ShaderMaterial)
	for model in EnvironmentAssets.MODELS:
		var near_mesh: Mesh = EnvironmentAssets.mesh_data(model)["mesh"]
		var far_mesh: Mesh = EnvironmentAssets.mesh_data(model, true)["mesh"]
		assert(near_mesh.get_aabb().size.y > 0.1, model + " has invalid dimensions")
		assert(_triangles(far_mesh) < _triangles(near_mesh), model + " needs a cheaper far LOD")
	var meadow := _check_meadows(world)
	var cam := Camera3D.new()
	cam.fov = 68.0
	cam.far = 2400.0
	add_child(cam)
	cam.current = true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var output := OS.get_environment("BLACK_TIDE_ENV_SHOTS")
	assert(not output.is_empty(), "Set BLACK_TIDE_ENV_SHOTS")
	DirAccess.make_dir_recursive_absolute(output)
	var fob: Vector2 = world.poi_by_id("fob")["pos"]
	var village: Vector2 = world.poi_by_id("zarya")["pos"]
	var runway: Vector2 = world.poi_by_id("kestrel")["pos"]
	var views := [
		["01_base", fob + Vector2(18, 26), 2.4, fob + Vector2(-8, 0), 1.3],
		["02_meadow", Vector2(35, 55), 1.7, Vector2(43, 43), 0.3],
		["03_village", village + Vector2(-26, -30), 2.2, village + Vector2(4, 6), 2.0],
		["04_coast", Vector2(560, 40), 10.0, Vector2(670, 20), 0.0],
		["05_airfield", runway + Vector2(16, 45), 2.0, runway + Vector2(-4, 12), 0.5],
		["06_overview", fob + Vector2(65, 65), 46.0, fob, 0.0],
		["07_grass_close", meadow + Vector2(8, 12), 1.8, meadow, 0.5],
		["08_meadow_patch", meadow + Vector2(16, 18), 24.0, meadow, 0.0],
	]
	for v in views:
		var eye: Vector2 = v[1]
		var look: Vector2 = v[3]
		cam.position = Vector3(eye.x, world.terrain.height_at(eye.x, eye.y) + v[2], eye.y)
		cam.look_at(Vector3(look.x, world.terrain.height_at(look.x, look.y) + v[4], look.y))
		await get_tree().create_timer(0.6).timeout
		var start := Time.get_ticks_usec()
		for frame in 60:
			await get_tree().process_frame
		var frame_ms := (Time.get_ticks_usec() - start) / 60000.0
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		assert(img.save_png(output.path_join(v[0] + ".png")) == OK)
		print("ENV_SHOT|", v[0], "|frame_ms=", snappedf(frame_ms, 0.01),
			"|draw_calls=", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			"|triangles=", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	assert(world.terrain.body != null and world.terrain.heights.size() == Terrain.RES * Terrain.RES)
	assert(AssetLib.missing_models.is_empty(), "Environment has missing models")
	print("ENVIRONMENT_PREVIEW_PASS")
	get_tree().quit()

func _triangles(mesh: Mesh) -> int:
	var count := 0
	for i in mesh.get_surface_count():
		count += mesh.surface_get_array_index_len(i) / 3
	return count

func _check_meadows(world: WorldRoot) -> Vector2:
	var total := 0
	var densest := 0
	var target := Vector2.ZERO
	var fob: Vector2 = world.poi_by_id("fob")["pos"]
	for child in world._veg_root.get_children():
		if not child is MultiMeshInstance3D or not child.name.contains("Grass") or child.visibility_range_begin > 0.0:
			continue
		var mi := child as MultiMeshInstance3D
		var mm := mi.multimesh
		total += mm.instance_count
		if mm.instance_count > 0:
			var root := mi.position + mm.get_instance_transform(mm.instance_count / 2).origin
			assert(absf(root.y + 0.025 - world.terrain.surface_height_at(root.x, root.z)) < 0.01, "Grass roots float or sink")
		if mm.instance_count > densest and Vector2(mi.position.x, mi.position.z).distance_to(fob) < 260.0:
			densest = mm.instance_count
			var center := Vector3.ZERO
			for i in mm.instance_count:
				center += mi.position + mm.get_instance_transform(i).origin
			center /= mm.instance_count
			target = Vector2(center.x, center.z)
	print("MEADOW_CHECK|grass_tufts=", total, "|densest_batch=", densest, "|target=", target)
	if total <= 40000 or densest <= 200:
		push_error("Meadows are too sparse")
		get_tree().quit(1)
	return target
