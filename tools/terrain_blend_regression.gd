extends Node3D
## Render the production noise on the GPU: adjacent pixels must not jump at cell edges.

func _ready() -> void:
	var baseline := OS.get_environment("BLACK_TIDE_NOISE_BASELINE") == "1"
	var source := FileAccess.get_file_as_string("res://_shots/terrain_surface_before.gdshader" if baseline else "res://assets/shaders/terrain_surface.gdshader")
	var prefix := source.substr(0, source.find("void fragment()"))
	prefix = prefix.replace("render_mode diffuse_burley, specular_schlick_ggx;", "render_mode unshaded;")
	var shader := Shader.new()
	shader.code = prefix + "void fragment() { vec2 p = world_pos.xz; ALBEDO = vec3(noise(p * 0.065) * 0.65 + noise(p * 0.19) * 0.35); }"
	var material := ShaderMaterial.new()
	material.shader = shader
	var plane := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(1000, 1000)
	plane.mesh = mesh
	plane.material_override = material
	plane.position = Vector3(-140, 0, 500)
	add_child(plane)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 160.0
	camera.position = Vector3(-140, 100, 500)
	add_child(camera)
	camera.look_at(plane.position, Vector3.FORWARD)
	camera.current = true
	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var max_jump := 0.0
	var seams := 0
	for y in range(1, img.get_height() - 1):
		for x in range(1, img.get_width() - 1):
			var value := img.get_pixel(x, y).r
			var jump := maxf(absf(value - img.get_pixel(x + 1, y).r), absf(value - img.get_pixel(x, y + 1).r))
			max_jump = maxf(max_jump, jump)
			if jump > 0.08:
				seams += 1
	img.save_png(ProjectSettings.globalize_path("res://_shots/terrain_noise_" + ("before" if baseline else "after") + ".png"))
	print("TERRAIN_NOISE|max_jump=", max_jump, "|seam_pixels=", seams)
	if not baseline and seams > 0:
		push_error("Terrain blend contains discontinuous noise cell edges")
	get_tree().quit(0 if baseline or seams == 0 else 1)
