extends Node
## Graphical benchmark. Requires isolated APPDATA and BLACK_TIDE_TEST_PROFILE=1.
var seconds := 5.0
var main: Node3D

func _ready() -> void:
	if OS.get_environment("BLACK_TIDE_TEST_PROFILE") != "1" or DisplayServer.get_name() == "headless":
		push_error("Use a graphical renderer and an isolated test profile")
		get_tree().quit(1)
		return
	if not OS.get_environment("BLACK_TIDE_PERF_SECONDS").is_empty():
		seconds = clampf(float(OS.get_environment("BLACK_TIDE_PERF_SECONDS")), 1.0, 3600.0)
	_run.call_deferred()

func snapshot() -> Dictionary:
	return {"static_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"vram_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"objects": Performance.get_monitor(Performance.OBJECT_COUNT),
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"triangles": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)}

func sample(label: String, duration: float = -1.0) -> void:
	for i in 30:
		await get_tree().process_frame
	var frames: Array[float] = []
	var cpu := 0.0
	var gpu := 0.0
	var process_time := 0.0
	var physics_time := 0.0
	var viewport := get_viewport().get_viewport_rid()
	var previous := Time.get_ticks_usec()
	var end := previous + int((seconds if duration < 0 else duration) * 1000000)
	while Time.get_ticks_usec() < end:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		frames.append((now - previous) / 1000.0)
		previous = now
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(viewport)
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(viewport)
		process_time += Performance.get_monitor(Performance.TIME_PROCESS) * 1000
		physics_time += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000
	var total := 0.0
	for frame in frames:
		total += frame
	frames.sort()
	var result := snapshot()
	result.merge({"frames": frames.size(), "mean_ms": total / frames.size(),
		"p95_ms": frames[int((frames.size() - 1) * 0.95)], "p99_ms": frames[int((frames.size() - 1) * 0.99)],
		"max_ms": frames[-1], "process_ms": process_time / frames.size(), "physics_ms": physics_time / frames.size(), "render_cpu_ms": cpu / frames.size(), "render_gpu_ms": gpu / frames.size()})
	print("COMPONENT|frames|", label, "|", JSON.stringify(result))

func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	node.set_process_unhandled_input(false)
	for child in node.get_children():
		freeze(child)

func _run() -> void:
	Loadout.vehicle = "SM_Veh_Helicopter_Transport_01"
	main = load("res://src/main.tscn").instantiate()
	main.generation_seed = 20261019
	var started := Time.get_ticks_usec()
	add_child(main)
	main.world.loading_progress.connect(func(message, fraction): print("LOADING|", fraction, "|", message))
	var heartbeat := 0
	var max_gap := 0
	var previous := started
	while not main.loading_complete:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		max_gap = maxi(max_gap, now - previous)
		previous = now
		heartbeat += 1
	print("COMPONENT|startup|staged|", JSON.stringify({"ready_ms": (Time.get_ticks_usec() - started) / 1000.0,
		"loading_frames": heartbeat, "max_frame_ms": max_gap / 1000.0, "seed": main.generation_seed}))
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	freeze(main)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var soldiers: Array = get_tree().get_nodes_in_group("combatant").filter(func(n): return n is Soldier)
	await sample("fixed_base")
	for quality in [0, 1, 2, 0]:
		GameState.graphics_quality = quality
		GameState.apply_graphics()
		await sample("fixed_quality_%d" % quality)
	main.world._veg_root.hide()
	await sample("fixed_without_vegetation")
	main.world._veg_root.show()
	var shader_before := OS.get_environment("BLACK_TIDE_BASELINE_SHADER")
	if not shader_before.is_empty():
		var material: ShaderMaterial = main.world.terrain.mesh_instance.get_active_material(0)
		var optimized := material.shader
		var old := Shader.new()
		old.code = FileAccess.get_file_as_string(shader_before)
		material.shader = old
		for layer in {"grass": "Grass001", "soil": "Ground109", "rock": "Rock030", "sand": "Ground054"}:
			var ids := {"grass": "Grass001", "soil": "Ground109", "rock": "Rock030", "sand": "Ground054"}
			material.set_shader_parameter(layer + "_roughness", load(EnvironmentMaterials.ROOT + ids[layer] + "/Roughness.jpg"))
		for candidate in [old, optimized, old, optimized]:
			material.shader = candidate
			await sample("terrain_before" if candidate == old else "terrain_after")
	main.player.global_position = Vector3(0, main.world.terrain.height_at(0, 0) + 1.0, 0)
	main.player._yaw = 0
	main.player._pitch = 0
	main.player._apply_look()
	for i in soldiers.size():
		var angle := -0.9 + 1.8 * i / maxf(1, soldiers.size() - 1)
		var pos: Vector3 = main.player.global_position + Vector3(sin(angle) * 14, 0, -cos(angle) * 14)
		pos.y = main.world.terrain.height_at(pos.x, pos.z) + 1
		soldiers[i].global_position = pos
		soldiers[i].rotation.y = angle
	await sample("fixed_crowd")
	var soak := maxf(0, float(OS.get_environment("BLACK_TIDE_SOAK_SECONDS")))
	if soak > 0:
		main.player.health = 1000000
		main.set_process(true)
		for soldier in soldiers:
			soldier.set_physics_process(true)
		main.player.set_process(true)
		main.player.set_physics_process(true)
		for squad in main._squads:
			squad.set_process(true)
		var begin := snapshot()
		var elapsed := 0.0
		while elapsed < soak:
			var span := minf(30, soak - elapsed)
			await sample("soak_%ds" % int(elapsed + span), span)
			elapsed += span
		print("COMPONENT|soak|memory|", JSON.stringify({"start": begin, "end": snapshot(), "seconds": soak}))
	print("COMPONENT_PERF_DONE")
	get_tree().quit()
