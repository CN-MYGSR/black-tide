extends Node3D
## 最小渲染探针：天空 + 太阳 + 一个箱子，确认渲染管线本身是否正常。

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.25, 0.45, 0.75)
	sm.sky_horizon_color = Color(0.75, 0.72, 0.65)
	sm.ground_bottom_color = Color(0.2, 0.18, 0.16)
	sm.ground_horizon_color = Color(0.6, 0.58, 0.52)
	sky.sky_material = sm
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 120, 0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	add_child(sun)

	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	ground.mesh = pm
	add_child(ground)

	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(2, 2, 2)
	box.mesh = bm
	box.position = Vector3(0, 1, -6)
	add_child(box)

	var cam := Camera3D.new()
	cam.position = Vector3(0, 2.5, 8)
	cam.look_at(Vector3(0, 1, -6))
	cam.current = true
	add_child(cam)

	await get_tree().create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://_shots/00_probe.png"))
	print("PROBE ", img.get_width(), "x", img.get_height(),
		" center=", img.get_pixel(img.get_width() / 2, img.get_height() / 2),
		" top=", img.get_pixel(img.get_width() / 2, 40))
	get_tree().quit()
