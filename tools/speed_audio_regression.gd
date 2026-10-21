extends Node
## Use BLACK_TIDE_TEST_PROFILE=1 and a graphical renderer with normal audio.

var passed := 0
var failed := 0
var _capture := AudioEffectCapture.new()

func check(ok: bool, label: String) -> void:
	passed += int(ok)
	failed += int(not ok)
	print("PASS | " if ok else "FAIL | ", label)

func _ready() -> void:
	if OS.get_environment("BLACK_TIDE_TEST_PROFILE") != "1" or DisplayServer.get_name() == "headless":
		push_error("Use a graphical renderer and an isolated test profile")
		get_tree().quit(1)
		return
	_run.call_deferred()

func quiet() -> void:
	AudioSfx.stop_world()
	for voice in AudioSfx._ui:
		voice.stop()
	await get_tree().create_timer(0.1).timeout
	_capture.clear_buffer()

func peak() -> float:
	await get_tree().create_timer(0.14).timeout
	var samples := _capture.get_buffer(_capture.get_frames_available())
	var amplitude := 0.0
	for frame in samples:
		amplitude = maxf(amplitude, maxf(absf(frame.x), absf(frame.y)))
	return amplitude

func _run() -> void:
	var terrain := Terrain.new()
	add_child(terrain)
	terrain.generate(20261019)
	for poi in WorldRoot.POI_DEFS:
		var angle := deg_to_rad(float(poi["angle"]))
		terrain.add_pad(Vector2(cos(angle), sin(angle)) * float(poi["dist"]), float(poi["radius"]))
	terrain.apply_pads()
	var started := Time.get_ticks_usec()
	terrain.build_mesh()
	print("TERRAIN_BUILD_MS|", (Time.get_ticks_usec() - started) / 1000.0)
	var arrays := terrain.mesh_instance.mesh.surface_get_arrays(0)
	check(arrays[Mesh.ARRAY_VERTEX].size() == Terrain.RES * Terrain.RES, "Terrain shares vertices across triangles")
	check(arrays[Mesh.ARRAY_INDEX].size() == (Terrain.RES - 1) * (Terrain.RES - 1) * 6, "Terrain retains every triangle")
	var shape_ok := true
	for z in Terrain.RES - 1:
		for x in Terrain.RES - 1:
			var vertex := z * Terrain.RES + x
			var offset := (z * (Terrain.RES - 1) + x) * 6
			var expected := [vertex, vertex + 1, vertex + Terrain.RES, vertex + 1, vertex + Terrain.RES + 1, vertex + Terrain.RES]
			for corner in 6:
				shape_ok = shape_ok and arrays[Mesh.ARRAY_INDEX][offset + corner] == expected[corner]
	check(shape_ok, "Terrain retains winding and grid connectivity")
	var attributes_ok := true
	for z in Terrain.RES:
		for x in Terrain.RES:
			var vertex := z * Terrain.RES + x
			var point := Vector2(-Terrain.SIZE * 0.5 + x * Terrain.SIZE / (Terrain.RES - 1), -Terrain.SIZE * 0.5 + z * Terrain.SIZE / (Terrain.RES - 1))
			attributes_ok = attributes_ok and arrays[Mesh.ARRAY_VERTEX][vertex].is_equal_approx(Vector3(point.x, terrain.heights[vertex], point.y))
			attributes_ok = attributes_ok and arrays[Mesh.ARRAY_NORMAL][vertex].dot(terrain.normal_at(point.x, point.y)) > 0.999
			attributes_ok = attributes_ok and absf(arrays[Mesh.ARRAY_COLOR][vertex].r - terrain._ground_wear(point)) < 0.005
	check(attributes_ok, "Terrain keeps heights, smooth normals and material blending")
	terrain.build_collision()
	var shape: HeightMapShape3D = terrain.body.get_child(0).shape
	check(shape.map_data == terrain.heights and shape.map_width == Terrain.RES, "Terrain collision still uses the same height map")
	terrain.free()

	print("AUDIO_DRIVER|", AudioServer.get_driver_name(), "|", AudioServer.output_device)
	check(AudioSfx._streams.size() == 12, "All twelve effects load")
	check(AudioSfx._ui.size() == 8 and AudioSfx._world.size() == 24, "Audio uses bounded voice pools")
	var valid := true
	for stream in AudioSfx._streams.values():
		valid = valid and stream != null and stream.get_length() > 0.003 and stream.mix_rate == 22050
	check(valid, "Every effect contains nonempty PCM audio")
	_capture.buffer_length = 1.0
	AudioServer.add_bus_effect(0, _capture)
	GameState.master_volume = 0.8
	GameState.apply_audio()
	var menu: Control = load("res://src/ui/menu.tscn").instantiate()
	add_child(menu)
	await quiet()
	menu._tabs[2].pressed.emit()
	check(await peak() > 0.001, "A real menu button produces mixed click audio")
	menu.free()
	var player := Player.new()
	add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	player.camera.current = true
	check(AssetLib._scenes.has(Player.first_person_model(player.sidearm_id)), "Secondary first-person model and hands preload before switching")
	GameState.in_raid = true
	await quiet()
	player._fire()
	check(await peak() > 0.005, "Player shooting produces mixed gunshot audio")
	await quiet()
	player.weapon_id = "SM_Wep_Shotgun_01"
	player._equip(player.weapon_id)
	player.ammo_mag = 3
	player._fire()
	check(AudioSfx._ui.filter(func(voice): return voice.playing and voice.stream == AudioSfx._streams["shotgun"]).size() == 1, "Shotgun pellets share exactly one gunshot voice")
	await quiet()
	player.ammo_mag = 5
	player._reloading = false
	player._start_reload()
	check(await peak() > 0.001, "Reload action produces mixed mechanical audio")
	await quiet()
	EventBus.player_damaged.emit(5, null)
	check(await peak() > 0.001, "Damage event produces mixed impact audio")
	await quiet()
	EventBus.hitmarker.emit("head")
	check(await peak() > 0.001, "Hit marker event produces mixed feedback audio")
	await quiet()
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, 1, 20)
	floor_shape.shape = box
	floor_shape.position.y = -0.5
	floor_body.add_child(floor_shape)
	add_child(floor_body)
	player.global_position = Vector3(0, 0.1, 0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	player.velocity = Vector3(0, -20, 0)
	player.move_and_slide()
	player.velocity = Vector3(4.8, 0, 0)
	player._update_footsteps(0.5)
	check(await peak() > 0.001, "Walking on the ground produces mixed footstep audio")
	await quiet()
	player.velocity = Vector3.ZERO
	player._update_footsteps(1)
	check(AudioSfx._ui.all(func(voice): return not voice.playing), "Standing still does not produce footsteps")
	floor_body.free()
	await quiet()
	AudioSfx.play_at("rifle", player.camera.global_position + Vector3(0, 0, -12))
	check(await peak() > 0.001, "Nearby AI gunshot produces spatial audio")
	await quiet()
	AudioSfx.play_at("rifle", player.camera.global_position + Vector3(1000, 0, 0))
	check(AudioSfx._world.all(func(voice): return not voice.playing), "Inaudible distant shots do not consume voices")
	for i in 100:
		AudioSfx.play_at("rifle", player.camera.global_position + Vector3(0, 0, -10))
	check(AudioSfx._world.filter(func(voice): return voice.playing).size() == 24, "Gunfire overload stays within the fixed voice limit")
	await quiet()
	var vehicle := Vehicle.new()
	vehicle.setup("SM_Veh_Car_01", "ground", 20, 0, "test")
	add_child(vehicle)
	vehicle.set_physics_process(false)
	vehicle.enter(player)
	check(vehicle._engine.playing and vehicle._engine.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "Driving starts the looping engine")
	check(vehicle._engine.stream.loop_end == 44100, "Compressed engine loops use decoded sample positions")
	await get_tree().create_timer(2.2).timeout
	check(vehicle._engine.playing and await peak() > 0.001, "Engine remains audible after the first full loop")
	vehicle.exit_vehicle()
	check(not vehicle._engine.playing, "Leaving a vehicle stops the engine")
	var heli := ExtractionHeli.new()
	add_child(heli)
	heli.set_process(false)
	check(get_tree().get_nodes_in_group("world_audio").any(func(voice): return voice.get_parent() == heli and voice.playing), "Extraction helicopter starts spatial rotor audio")
	AudioSfx.stop_world()
	check(get_tree().get_nodes_in_group("world_audio").all(func(voice): return not voice.playing), "Settlement stops all world audio")
	GameState.master_volume = 0
	GameState.apply_audio()
	check(AudioServer.is_bus_mute(0), "Zero master volume mutes effects")
	GameState.master_volume = 0.8
	GameState.apply_audio()
	check(not AudioServer.is_bus_mute(0) and is_equal_approx(AudioServer.get_bus_volume_db(0), linear_to_db(0.8)), "Master volume restores the configured level")
	GameState.in_raid = false
	AudioServer.remove_bus_effect(0, AudioServer.get_bus_effect_count(0) - 1)
	heli.free()
	vehicle.free()
	player.free()
	print("SPEED_AUDIO_REGRESSION: %d passed / %d failed" % [passed, failed])
	get_tree().quit(1 if failed else 0)
