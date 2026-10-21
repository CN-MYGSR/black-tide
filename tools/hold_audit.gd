extends Node3D

func _ready() -> void:
	get_window().size = Vector2i(960, 540)
	var env := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("9bafb9")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_energy = 0.8
	env.environment = settings
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -25, 0)
	sun.light_energy = 1.7
	add_child(sun)
	var title := Label.new()
	title.add_theme_font_size_override("font_size", 24)
	title.position = Vector2(12, 12)
	add_child(title)
	var player := Player.new()
	add_child(player)
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var directory := "res://_shots/hold_audit/" + ("after" if "after" in OS.get_cmdline_user_args() else "before")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var index := 0
	for id in ItemDB.WEAPONS:
		player._equip(id)
		for aimed in [false, true]:
			player._ads_blend = 1.0 if aimed else 0.0
			player.camera.fov = float(player.current_def()["zoom"]) if aimed else 78.0
			player._update_weapon_pose(0)
			title.text = "%02d %s %s" % [index, ItemDB.WEAPONS[id]["short"], "ADS" if aimed else "HIP"]
			await save(directory.path_join(("ads" if aimed else "hip") + "_%02d.png" % index))
		index += 1
	player.visible = false
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(-1.4, 1.45, 2.2)
	camera.look_at(Vector3(0, 1.15, 0))
	camera.fov = 38
	camera.current = true
	index = 0
	for id in ["SM_Wep_Preset_A_Rifle_01", "SM_Wep_Pistol_01", "SM_Wep_Preset_A_Sniper_01", "SM_Wep_RPG_01"]:
		var body := AssetLib.spawn("SM_Chr_Soldier_Male_01", self)
		var rig := CharacterRig.new()
		rig.setup(body)
		rig.attach_weapon(id, body)
		for aim in [0.0, 1.0]:
			for frame in 90:
				rig.animate_locomotion(1.0 / 60, 0, aim)
			title.text = "%s %s" % [ItemDB.WEAPONS[id]["short"], "READY" if aim == 0 else "AIM"]
			await save(directory.path_join("body_%02d_%d.png" % [index, aim]))
		body.queue_free()
		await get_tree().process_frame
		index += 1
	print("HOLD_AUDIT weapons=24 views=56")
	get_tree().quit()

func save(path: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	assert(get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(path)) == OK)
