extends Node
## Deterministic in-engine viewmodel motion review; use an isolated APPDATA.

func _ready() -> void:
	get_window().size = Vector2i(960, 540)
	var main = load("res://src/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.5).timeout
	main.set_process(false)
	for node in get_tree().get_nodes_in_group("combatant"):
		node.set_physics_process(false)
	for squad in main._squads:
		squad.set_process(false)
		squad.set_physics_process(false)
	var player: Player = main.player
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var path := ProjectSettings.globalize_path("res://_shots/realistic_motion_frames")
	DirAccess.make_dir_recursive_absolute(path)
	for frame in 144:
		var dt := 1.0 / 24.0
		player.velocity = Vector3(4, 0, 0) if frame >= 12 and frame < 42 else Vector3.ZERO
		if player.velocity.length() > 0:
			player._bob += 0.48
		if frame >= 42 and frame < 66 and frame % 4 == 2:
			player._fire()
		if frame == 66:
			player._start_reload()
		if player._reloading:
			player._reload_t -= dt
			if player._reload_t <= 0:
				player._finish_reload()
		player._recoil = player._recoil.lerp(Vector2.ZERO, dt * 9)
		player.cam_pivot.rotation.x = player._pitch + player._recoil.x
		player.cam_pivot.rotation.y = player._recoil.y
		player._update_camera_fx(dt)
		player._update_weapon_pose(dt)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var result := get_viewport().get_texture().get_image().save_png(path.path_join("%04d.png" % frame))
		assert(result == OK, "Could not save motion review frame")
	print("MOTION_REVIEW frames=144 fps=24")
	get_tree().quit()
