extends Node3D
## Fixed-camera old/new render evidence; writes only BLACK_TIDE_SHOTS.
var camera: Camera3D
var output: String

func _ready() -> void:
	if DisplayServer.get_name() == "headless" or OS.get_environment("BLACK_TIDE_SHOTS").is_empty():
		get_tree().quit(1)
		return
	_run.call_deferred()

func snap(label: String) -> void:
	for i in 5:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output.path_join(label + ".png"))
	print("RENDER|", label, "|", JSON.stringify({"draws": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), "vram_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0}))

func _run() -> void:
	output = OS.get_environment("BLACK_TIDE_SHOTS")
	DirAccess.make_dir_recursive_absolute(output)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.3, 0.36, 0.4)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_energy = 0.6
	environment.environment = env
	add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, -25, 0)
	light.light_energy = 1.5
	add_child(light)
	camera = Camera3D.new()
	add_child(camera)
	camera.position = Vector3(0, 1, 3)
	camera.look_at(Vector3(0, 1, 0))
	for model in ["BT_Operator", "BT_Operator_Batched"]:
		var character: Node3D = load("res://assets/models/characters/" + model + ".glb").instantiate()
		add_child(character)
		AssetLib.apply_materials(character)
		for angle in [0, 120, 240]:
			character.rotation_degrees.y = angle
			await snap(model + "_%d" % angle)
		character.queue_free()
		await get_tree().process_frame
	var terrain := Terrain.new()
	add_child(terrain)
	terrain.generate(20261019)
	terrain.build_mesh()
	var mat: ShaderMaterial = terrain.mesh_instance.get_active_material(0)
	var optimized := mat.shader
	var old := Shader.new()
	old.code = FileAccess.get_file_as_string(OS.get_environment("BLACK_TIDE_BASELINE_SHADER"))
	mat.shader = old
	for layer in {"grass": "Grass001", "soil": "Ground109", "rock": "Rock030", "sand": "Ground054"}:
		var ids := {"grass": "Grass001", "soil": "Ground109", "rock": "Rock030", "sand": "Ground054"}
		mat.set_shader_parameter(layer + "_roughness", load(EnvironmentMaterials.ROOT + ids[layer] + "/Roughness.jpg"))
	for point in [Vector3(0, 130, 170), Vector3(580, 85, 150)]:
		camera.position = point
		camera.look_at(Vector3(point.x, 10, point.z - 100))
		for shader in [old, optimized]:
			mat.shader = shader
			await snap("terrain_%d_" % int(point.x) + ("old" if shader == old else "new"))
	print("RENDER_CHECK_DONE")
	get_tree().quit()
