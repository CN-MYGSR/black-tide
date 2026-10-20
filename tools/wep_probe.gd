extends Node3D

func _ready() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	sun.light_energy = 1.5
	add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.5, 0.55, 0.6)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.6, 0.65)
	e.ambient_light_energy = 1.0
	env.environment = e
	add_child(env)

	var rots := [0.0, 90.0, 180.0, 270.0]
	for i in 4:
		var w := AssetLib.spawn("SM_Wep_Preset_A_Rifle_01", self, Vector3(-2.4 + i * 1.6, 1.0, 0), deg_to_rad(rots[i]), true)
		if w != null:
			var lbl := Label3D.new()
			lbl.text = "y=%d" % int(rots[i])
			lbl.position = Vector3(0, 0.6, 0)
			lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			lbl.font_size = 64
			w.add_child(lbl)

	# 前方标记（-Z 方向的红柱）
	var marker := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.05
	cm.bottom_radius = 0.05
	cm.height = 1.0
	marker.mesh = cm
	var mm := StandardMaterial3D.new()
	mm.albedo_color = Color(0.9, 0.15, 0.1)
	marker.material_override = mm
	marker.position = Vector3(0, 1.0, -1.5)
	add_child(marker)

	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.global_position = Vector3(0, 1.9, 4.2)
	cam.look_at(Vector3(0, 1.0, 0), Vector3.UP)

	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://_shots/wep_orient.png"))
	print("snap wep")
	get_tree().quit()
