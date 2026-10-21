extends Node
## Writes only to a disposable APPDATA with BLACK_TIDE_TEST_PROFILE=1.
var passed := 0
var failed := 0

func check(ok: bool, label: String) -> void:
	passed += int(ok)
	failed += int(not ok)
	print("PASS | " if ok else "FAIL | ", label)

func _ready() -> void:
	if OS.get_environment("BLACK_TIDE_TEST_PROFILE") != "1" or DisplayServer.get_name() == "headless":
		get_tree().quit(1)
		return
	_run.call_deferred()

func _run() -> void:
	check(GameState.profile_valid({"credits": 1234}), "Legacy partial profiles remain valid")
	for bad in [{"credits": "2500"}, {"resolution": [1280, "720"]}, {"armory": []},
		{"armory": {"owned_weapons": "rifle"}}, {"armory": {"primary": "missing"}},
		{"armory": {"attachments": {"unknown": "none"}}}, {"master_volume": 2}, {"graphics_quality": 3}, {"credits": 1e30}, {"loadout_weapon": []}]:
		check(not GameState.profile_valid(bad), "Reject malformed profile: " + JSON.stringify(bad))
	GameState.credits = 9000
	check(GameState.save_profile() and GameState.save_profile(), "Create valid primary and backup")
	var file := FileAccess.open(GameState.SAVE_PATH, FileAccess.WRITE)
	file.store_string('{"credits": "broken", "xp": 888}')
	file.close()
	GameState.credits = 1
	GameState.xp = 0
	GameState.load_profile()
	check(GameState.credits == 9000 and GameState.xp == 0, "Wrong-type primary falls back without partial state")
	GameState.save_profile()
	check(DirAccess.make_dir_absolute(GameState.SAVE_PATH + ".tmp") == OK, "Simulate blocked temporary save path")
	GameState.in_raid = true
	check(GameState.end_raid(true, 1200) and GameState.save_pending, "Failed settlement queues retry")
	GameState.load_profile()
	check(GameState.credits == 10200, "Reload cannot discard unsaved reward")
	check(not GameState.request_quit(), "Quit is canceled while settlement cannot be saved")
	check(not GameState.end_raid(true, 1200), "Settlement cannot award twice")
	check(DirAccess.rename_absolute(GameState.SAVE_PATH + ".tmp", GameState.SAVE_PATH + ".blocked-fixture") == OK, "Restore writable path and retain fixture")
	GameState._process(2.1)
	check(not GameState.save_pending, "Automatic retry succeeds")
	GameState.credits = 0
	GameState.load_profile()
	check(GameState.credits == 10200, "Retried reward persists exactly once")
	var menu: Control = load("res://src/ui/menu.tscn").instantiate()
	add_child(menu)
	menu._switch_tab(4)
	var volume: HSlider = menu.find_child("MasterVolume", true, false)
	var before := FileAccess.get_file_as_string(GameState.SAVE_PATH)
	var start := Time.get_ticks_usec()
	for i in 80:
		volume.value = i
	check(FileAccess.get_file_as_string(GameState.SAVE_PATH) == before and GameState.save_pending, "80 slider changes do not synchronously write")
	print("VOLUME_80_STEPS_MS|", (Time.get_ticks_usec() - start) / 1000.0)
	await get_tree().create_timer(0.4).timeout
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GameState.SAVE_PATH))
	check(is_equal_approx(data.master_volume, 0.79), "Debounce saves the final slider value")
	menu.queue_free()
	await get_tree().process_frame
	var model := "SM_Wep_Preset_A_Rifle_01"
	var path := AssetLib.model_path(model)
	await AssetLib.preload_paths([path, path])
	check(AssetLib.path_scene(path) == AssetLib.get_scene(model), "Preload and alias spawn share the actual scene")
	var player := Player.new()
	add_child(player)
	GameState.in_raid = true
	player.set_physics_process(false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(100, 30)
	var old_yaw := player.rotation.y
	player._unhandled_input(motion)
	check(not is_equal_approx(player.rotation.y, old_yaw) and is_equal_approx(player.rotation.y, player._yaw), "Mouse changes camera orientation before physics tick")
	player.ammo_mag = 0
	player.ammo_reserve = 60
	player._start_reload()
	check(player._reloading and AudioSfx._reload.playing, "Reload starts its dedicated voice")
	player._switch_slot(1)
	check(not player._reloading and not AudioSfx._reload.playing, "Switching cancels both reload and sound")
	player.queue_free()
	GameState.in_raid = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var world := WorldRoot.new()
	add_child(world)
	var progress := [0]
	world.loading_progress.connect(func(_text, _fraction): progress[0] += 1)
	await world.generate_async(20261019)
	check(progress[0] > 10 and world.outposts.size() == 6, "Staged loading reports progress and creates all outposts")
	var reference := WorldRoot.new()
	add_child(reference)
	reference.generate(20261019)
	check(world.terrain.heights == reference.terrain.heights, "Staged and synchronous terrain/collision heights match")
	check(vegetation(world) == vegetation(reference), "Staged and synchronous vegetation transforms match exactly")
	var transforms: Array[Transform3D] = [Transform3D(Basis.IDENTITY, Vector3(1, 2, 3))]
	var chunks := EnvironmentAssets.chunk_batches([{"model": "SM_Env_Grass_01", "transforms": transforms}, {"model": "SM_Env_Grass_01", "transforms": transforms}])
	check(chunks.size() == 2 and chunks[0].transforms.size() == 2, "Same mesh and cell merge while preserving near/far instances")
	reference.queue_free()
	await get_tree().process_frame
	for quality in [0, 1, 2]:
		GameState.graphics_quality = quality
		GameState.apply_graphics()
		check(world.env.environment.ssao_enabled == (quality < 2) and world.env.environment.glow_enabled == (quality == 0), "Quality tier %d updates environment" % quality)
	GameState.save_profile()
	GameState.graphics_quality = 0
	GameState.load_profile()
	check(GameState.graphics_quality == 2, "Quality tier survives save and reload")
	world.queue_free()
	await get_tree().process_frame
	print("TWELVE_REGRESSION: %d passed / %d failed" % [passed, failed])
	get_tree().quit(1 if failed else 0)

func vegetation(world: WorldRoot) -> Dictionary:
	var result := {}
	for node in world._veg_root.get_children():
		var points: Array = []
		for i in node.multimesh.instance_count:
			points.append(node.multimesh.get_instance_transform(i))
		result[node.name] = points
	return result
