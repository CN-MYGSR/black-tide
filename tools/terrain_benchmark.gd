extends Node3D
## Isolate terrain shading from actors, vegetation and shadows.
func _ready() -> void:
	if DisplayServer.get_name() == "headless" or OS.get_environment("BLACK_TIDE_TEST_PROFILE") != "1":
		get_tree().quit(1)
		return
	_run.call_deferred()

func _run() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, -25, 0)
	add_child(light)
	var terrain := Terrain.new()
	add_child(terrain)
	terrain.generate(20261019)
	terrain.build_mesh()
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(0, 130, 170)
	camera.look_at(Vector3(0, 10, 70))
	var material: ShaderMaterial = terrain.mesh_instance.get_active_material(0)
	var code: String = material.shader.code
	var old := Shader.new()
	old.code = FileAccess.get_file_as_string(OS.get_environment("BLACK_TIDE_BASELINE_SHADER"))
	material.shader = old
	var layers := {"grass": "Grass001", "soil": "Ground109", "rock": "Rock030", "sand": "Ground054"}
	for layer in layers:
		material.set_shader_parameter(layer + "_roughness", load(EnvironmentMaterials.ROOT + layers[layer] + "/Roughness.jpg"))
	var variants := {"old": old}
	var branch := Shader.new()
	branch.code = code
	variants["packed_branch"] = branch
	var conditional := RegEx.create_from_string("if \\(weights\\.[xyzw] > 0\\.0\\)")
	var unconditional := conditional.sub(code, "", true)
	var static_grad := Shader.new()
	static_grad.code = unconditional
	variants["packed_static_grad"] = static_grad
	var texture := RegEx.create_from_string("textureGrad\\((\\w+), (\\w+), dx / [0-9.]+, dy / [0-9.]+\\)")
	var static_implicit := Shader.new()
	static_implicit.code = texture.sub(unconditional, "texture($1, $2)", true).replace("textureGrad(grass_color, p / 6.7 + vec2(0.37, 0.61), dx / 6.7, dy / 6.7)", "texture(grass_color, p / 6.7 + vec2(0.37, 0.61))")
	variants["packed_static_implicit"] = static_implicit
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	for round in 2:
		for label in variants:
			material.shader = variants[label]
			for i in 60:
				await get_tree().process_frame
			var deadline := Time.get_ticks_msec() + 1500
			var total := 0.0
			var frames := 0
			while Time.get_ticks_msec() < deadline:
				await get_tree().process_frame
				total += RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
				frames += 1
			print("TERRAIN_GPU|", round, "|", label, "|", total / frames)
	print("TERRAIN_BENCHMARK_DONE")
	get_tree().quit()
