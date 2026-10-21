extends Node
## Run with BLACK_TIDE_TEST_PROFILE=1 and an isolated APPDATA.

var passed := 0
var failed := 0

func _ready() -> void:
	if OS.get_environment("BLACK_TIDE_TEST_PROFILE") != "1":
		push_error("Use an isolated test profile; refusing to write a normal player save")
		get_tree().quit(1)
		return
	if OS.get_environment("BLACK_TIDE_TEST_RELOAD") == "1":
		_verify_reload.call_deferred()
		return
	_run.call_deferred()

func _verify_reload() -> void:
	check(GameState.credits == 11200 and GameState.xp == 720, "Balance and XP survive a new engine process")
	check(Loadout.has_weapon("SM_Wep_Preset_A_Rifle_02") and Loadout.secondary == "SM_Wep_Pistol_Metal_01", "Armory and secondary survive a new engine process")
	check(is_equal_approx(GameState.master_volume, 0.17) and GameState.resolution == Vector2i(1280, 720), "Settings survive a new engine process")
	check(Loadout.primary == "SM_Wep_Preset_A_Rifle_01", "Combined profile takes precedence over retained legacy armory")
	print("SAVE_RELOAD: %d passed / %d failed" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
	print("PASS | " if ok else "FAIL | ", label)

func freeze(n: Node) -> void:
	n.set_process(false)
	n.set_physics_process(false)
	n.set_process_unhandled_input(false)
	for c in n.get_children():
		freeze(c)

func screenshot(label: String) -> void:
	var output := OS.get_environment("BLACK_TIDE_SHOTS")
	if DisplayServer.get_name() == "headless" or output.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(output)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output.path_join(label + ".png"))

func _run() -> void:
	# Migrate without modifying the old armory, then persist both sides together.
	var legacy := Loadout.to_data().duplicate(true)
	legacy["owned_weapons"].append("SM_Wep_Preset_A_Rifle_02")
	legacy["primary"] = "SM_Wep_Preset_A_Rifle_02"
	var file := FileAccess.open(Loadout.SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy))
	file.close()
	file = FileAccess.open(GameState.SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify({"credits": 7777}))
	file.close()
	GameState.load_profile()
	Loadout.load_data()
	check(GameState.credits == 7777 and Loadout.primary == legacy["primary"], "Legacy balance and armory load together")
	check(GameState.save_profile(), "Migration saves successfully")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GameState.SAVE_PATH))
	check(saved["armory"]["primary"] == legacy["primary"] and FileAccess.file_exists(Loadout.SAVE_PATH), "Combined save retains old armory file")
	Loadout._reset_defaults()
	Loadout.primary = "SM_Wep_Preset_A_Rifle_01"
	GameState.credits = 5000
	var buy := Loadout.buy("weapon", "SM_Wep_Preset_A_Rifle_02")
	check(buy["ok"] and GameState.credits == 2600, "Purchase commits balance and item")
	Loadout._reset_defaults()
	GameState.credits = 0
	GameState.load_profile()
	Loadout.load_data()
	check(GameState.credits == 2600 and Loadout.has_weapon("SM_Wep_Preset_A_Rifle_02"), "Purchase survives reload")
	GameState.credits = 5000
	check(GameState.save_profile(), "Save replaces an existing profile")
	var original := FileAccess.get_file_as_string(GameState.SAVE_PATH)
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(GameState.SAVE_PATH + ".tmp"))
	buy = Loadout.buy("weapon", "SM_Wep_Preset_A_Rifle_03")
	check(not buy["ok"] and GameState.credits == 5000 and not Loadout.has_weapon("SM_Wep_Preset_A_Rifle_03"), "Failed save cancels purchase without charging or granting")
	check(FileAccess.get_file_as_string(GameState.SAVE_PATH) == original, "Failed save preserves previous file")
	DirAccess.rename_absolute(GameState.SAVE_PATH + ".tmp", GameState.SAVE_PATH + ".blocked-fixture")
	check(not Loadout.buy("attachment", "bad")["ok"] and not Loadout.buy("weapon", "missing")["ok"], "Invalid item IDs are rejected")
	check(GameState.save_profile(), "Save works after a transient write failure")
	file = FileAccess.open(GameState.SAVE_PATH, FileAccess.WRITE)
	file.store_string("{truncated")
	file.close()
	GameState.credits = 0
	GameState.load_profile()
	check(GameState.credits == 5000, "Previous valid backup recovers a damaged profile")
	check(GameState.save_profile(), "Recovered profile saves again")

	var menu = load("res://src/ui/menu.tscn").instantiate()
	add_child(menu)
	menu._switch_tab(4)
	menu.find_children("*", "HSlider", true, false)[0].value = 17
	await get_tree().create_timer(0.35).timeout
	GameState.master_volume = 0.8
	GameState.load_profile()
	check(is_equal_approx(GameState.master_volume, 0.17), "Volume saves before starting a raid")
	var options = menu.find_children("*", "OptionButton", true, false)
	options[0].item_selected.emit(0)
	GameState.resolution = Vector2i(1600, 900)
	GameState.load_profile()
	check(GameState.resolution == Vector2i(1280, 720), "Resolution saves immediately")
	for button in menu.find_children("*", "Button", true, false):
		if button.text == "无边框全屏":
			button.pressed.emit()
			break
	GameState.display_mode = 0
	GameState.load_profile()
	check(GameState.display_mode == 1, "Display mode saves immediately")
	GameState.display_mode = 0
	GameState.apply_display()
	Loadout.owned_weapons.append("SM_Wep_Pistol_Metal_01")
	menu._switch_tab(1)
	var selector := menu.find_child("WeaponSlot", true, false) as OptionButton
	selector.item_selected.emit(1)
	var primary := Loadout.primary
	var row: Control = menu._weapon_row("SM_Wep_Pistol_Metal_01")
	menu.add_child(row)
	row.find_children("*", "Button", true, false)[0].pressed.emit()
	row.free()
	check(Loadout.secondary == "SM_Wep_Pistol_Metal_01" and Loadout.primary == primary, "Menu equips the selected secondary slot")
	GameState.credits = 0
	var current_page: Control = menu._pages[1]
	var rejected_row: Control = menu._weapon_row("SM_Wep_Preset_A_Rifle_03")
	menu.add_child(rejected_row)
	rejected_row.find_children("*", "Button", true, false)[0].pressed.emit()
	check(menu._pages[1] == current_page and menu._toast_label.text.contains("不足"), "Rejected weapon purchase does not rebuild the page")
	rejected_row.free()
	for tab in [2, 3]:
		menu._tabs[tab].pressed.emit()
		current_page = menu._pages[tab]
		for button in current_page.find_children("*", "Button", true, false):
			if button.text.contains("购买"):
				button.pressed.emit()
				break
		check(menu._pages[tab] == current_page and menu._toast_label.text.contains("不足"), "Rejected gear/vehicle purchase keeps page %d" % tab)
	menu._weapon_slot = 0
	menu._switch_tab(1)
	current_page = menu._pages[1]
	var rejected_attachment := false
	for option in current_page.find_children("*", "OptionButton", true, false):
		if option.name == "WeaponSlot":
			continue
		for index in option.item_count:
			if option.get_item_text(index).contains("["):
				var previous: int = option.selected
				option.select(index)
				option.item_selected.emit(index)
				rejected_attachment = option.selected == previous and menu._pages[1] == current_page
				break
		if rejected_attachment:
			break
	check(rejected_attachment, "Rejected attachment restores selection without rebuilding")
	var denied := Loadout.buy("weapon", "SM_Wep_Preset_A_Rifle_03")
	menu._toast(denied["msg"])
	menu._switch_tab(4)
	check(menu._toast_label.text.contains("不足") and menu._toast_label.is_visible_in_tree(), "Purchase failure remains visible after rebuilding the tab")
	EventBus.notify.emit("test notification")
	check(menu._toast_label.text == "test notification", "Menu receives shared notifications")
	menu._switch_tab(1)
	var deadline := Time.get_ticks_msec() + 5000
	while menu._preview_model == null and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.01).timeout
	check(menu._preview_model != null, "Asynchronous preview finishes loading")
	var armory_page: Control = menu._pages[1]
	var preview: SubViewport = menu._preview
	for i in 5:
		menu._tabs[0].pressed.emit()
		menu._tabs[1].pressed.emit()
	check(menu._pages[1] == armory_page and menu._preview == preview, "Repeated navigation reuses widgets and the preview")
	var saved_primary := Loadout.primary
	Loadout.equip_weapon(0, "SM_Wep_Preset_A_Rifle_02")
	menu._switch_tab(1)
	menu._tabs[0].pressed.emit()
	var fresh := false
	for label in menu._pages[0].find_children("*", "Label", true, false):
		if label.text.begins_with("主武器") and label.text.contains("M16A4"):
			fresh = true
	check(fresh, "Equipment changes invalidate cached preparation data")
	Loadout.equip_weapon(0, saved_primary)
	for i in 3:
		menu._switch_tab(1)
		await get_tree().process_frame
	deadline = Time.get_ticks_msec() + 5000
	while menu._preview_model == null and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.01).timeout
	check(menu._preview_model != null and menu._preview_model.get_parent() == menu._preview, "Rapid rebuilds cannot install an obsolete preview")
	await screenshot("armory-secondary")
	menu.free()

	var stage := Node3D.new()
	add_child(stage)
	var p := Player.new()
	stage.add_child(p)
	freeze(p)
	p.global_position = Vector3(0, 100, 0)
	var ally := Soldier.new()
	ally.faction = "blufor"
	stage.add_child(ally)
	freeze(ally)
	ally.global_position = p.global_position + Vector3(0, 0, -2)
	ally._go_down()
	for i in 3:
		await get_tree().physics_frame
	var interact := InputEventAction.new()
	interact.action = "interact"
	interact.pressed = true
	p._unhandled_input(interact)
	check(ally.state == Soldier.AIState.PATROL and ally.health == 45, "F interaction actually revives a downed ally")
	p.health = 50
	p._use_med("vitamins")
	p.take_damage(1000, p.global_position, ally)
	p._process(0.5)
	check(p.health == 0 and p._regen_pool == 100, "Regeneration pauses while downed")
	ally.global_position = p.global_position + Vector3(1, 0, 0)
	ally.follow_target = p
	ally._try_rescue(2.0)
	check(p.state == Player.State.DOWNED, "AI rescue requires time beside the player")
	ally._try_rescue(1.1)
	check(p.state == Player.State.ALIVE and p.health == 45, "Friendly AI revives the player")
	p._process(0.5)
	check(p.health == 56, "Regeneration resumes after rescue")
	ally.global_position += Vector3(10, 0, 0)
	var rival := Soldier.new()
	rival.faction = "rival"
	stage.add_child(rival)
	freeze(rival)
	rival.global_position = Vector3(30, 100, 0)
	GameState.raid_kills = 0
	GameState.raid_loot = 0
	var enemy := Soldier.new()
	stage.add_child(enemy)
	freeze(enemy)
	enemy.global_position = Vector3(20, 100, 0)
	enemy._die(rival)
	check(GameState.raid_kills == 0 and GameState.raid_loot == 0, "Rival kills do not reward the player")
	enemy = Soldier.new()
	stage.add_child(enemy)
	freeze(enemy)
	enemy.global_position = Vector3(20, 100, -10)
	var killers: Array = []
	var killed := func(_e: Node, _head: bool, faction: String): killers.append(faction)
	EventBus.enemy_killed.connect(killed)
	enemy._die(p)
	EventBus.enemy_killed.disconnect(killed)
	check(GameState.raid_kills == 1 and GameState.raid_loot == 30 and killers == ["player"], "Player kills have correct reward and attribution")
	var outpost := Outpost.new()
	stage.add_child(outpost)
	freeze(outpost)
	outpost._bodies.assign([p, rival])
	outpost._process(1)
	check(outpost.contested and outpost.progress == 0, "Rival presence blocks player capture")
	outpost._bodies.assign([p])
	outpost._process(12)
	check(outpost.owner_faction == "blufor" and outpost.progress == 100, "Friendly capture reaches a full control bar")
	var guard := Soldier.new()
	stage.add_child(guard)
	freeze(guard)
	guard.global_position = Vector3(40, 100, 0)
	outpost._bodies.assign([guard])
	outpost._process(1)
	check(outpost.owner_faction == "blufor" and outpost.progress == 96, "Enemy recapture takes time")
	outpost._process(24)
	check(outpost.owner_faction == "opfor", "Enemy can retake a captured outpost")
	outpost.free()
	p._equip("SM_Wep_Preset_A_Rifle_02")
	p.ammo_mag = 1
	p.ammo_reserve = 30
	p._burst_left = 3
	p._burst_t = 0
	for i in 70:
		p._process_combat(0.05)
	check(p.ammo_mag == 30 and p._burst_left == 0, "Empty-mag burst does not fire after reloading")
	Input.action_press("aim")
	Loadout.attachments["stock"] = "std"
	p._equip(Loadout.primary)
	p._ads_blend = 0
	p._process_combat(0.05)
	var base_blend := p._ads_blend
	Loadout.attachments["stock"] = "light"
	p._equip(Loadout.primary)
	p._ads_blend = 0
	p._process_combat(0.05)
	check(p._ads_blend > base_blend, "ADS speed modifier affects aiming time")
	Input.action_release("aim")
	Loadout.attachments["stock"] = "std"
	p.cam_pivot.rotation = Vector3.ZERO
	p.camera.rotation = Vector3.ZERO
	var crate := LootCrate.new()
	stage.add_child(crate)
	crate.setup(100)
	crate.global_position = p.camera.global_position + Vector3(0, -0.5, -2)
	p.spring.spring_length = 0
	for i in 3:
		await get_tree().physics_frame
	p._update_interact_target()
	check(p._interact_target == crate, "First person selects a nearby crate")
	p._third_person = true
	p.spring.spring_length = 3.4
	for i in 3:
		await get_tree().physics_frame
	p._update_interact_target()
	check(p._interact_target == crate, "Third person selects the same nearby crate")
	p._unhandled_input(interact)
	check(crate.opened, "Third person can actually loot with F")
	p.global_position = Vector3(1000, -100, 1000)
	check(p._check_bounds() and p.global_position.y > 0 and absf(p.global_position.x) < 800, "Out-of-bounds player returns to safety")
	var v := Vehicle.new()
	v.setup("SM_Veh_Helicopter_Transport_01", "air", 38, 40, "test")
	stage.add_child(v)
	freeze(v)
	v.global_position = Vector3(1000, 20, 1000)
	v.enter(p)
	v._physics_process(0)
	freeze(p)
	check(p.vehicle == null and absf(p.global_position.x) < 800 and absf(v.global_position.x) < 800, "Out-of-bounds driver and vehicle recover together")
	stage.free()

	var main = load("res://src/main.tscn").instantiate()
	get_tree().root.add_child(main)
	while not main.loading_complete:
		await get_tree().process_frame
	get_tree().current_scene = main
	freeze(main)
	var target: Outpost = main._target_outpost
	target._set_owner("blufor")
	check(main.world.poi_by_id(target.outpost_id)["faction"] == "blufor", "Captured owner updates world and minimap data")
	var pois: Array = main.world.pois
	main.world.pois = [main.world.poi_by_id(target.outpost_id)]
	var count: int = main._enemies.size()
	main._reinforce()
	check(main._enemies.size() == count, "Captured outpost no longer spawns enemy reinforcements")
	main.world.pois = pois
	var heli := ExtractionHeli.new()
	main.add_child(heli)
	freeze(heli)
	heli.state = "landed"
	main.player.state = Player.State.DEAD
	heli.interact(main.player)
	check(heli.state == "landed" and GameState.last_raid.is_empty(), "Dead player cannot board extraction")
	main.player._interact_target = heli
	main.player._unhandled_input(interact)
	check(heli.state == "landed", "Dead player cannot use a stale interaction target")
	main.player.state = Player.State.ALIVE
	GameState.credits = 10000
	GameState.xp = 0
	GameState.level = 1
	GameState.raids_survived = 0
	GameState.raids_lost = 0
	GameState.raid_kills = 7
	GameState.raid_loot = 0
	heli.interact(main.player)
	check(GameState.credits == 11200 and GameState.xp == 720, "Extraction pays the authoritative reward")
	check(main.hud._debrief["xp"] == 720 and main.hud._debrief["kills"] == 7, "Debrief matches actual XP and keeps kill count")
	main.player.take_damage(10000, main.player.global_position, null)
	main.player._die()
	main._on_player_died()
	main._process(3)
	check(GameState.raids_survived == 1 and GameState.raids_lost == 0 and GameState.credits == 11200 and main.hud._debrief["ok"], "Death after extraction cannot change the result")
	check(not GameState.end_raid(false, 0) and GameState.credits == 11200, "Duplicate settlement does not charge a penalty")
	check(main.player.process_mode == Node.PROCESS_MODE_DISABLED and main.world.process_mode == Node.PROCESS_MODE_DISABLED, "Gameplay stops behind the debrief")
	await screenshot("extraction-debrief")
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	main._unhandled_input(enter)
	await get_tree().process_frame
	await get_tree().process_frame
	check(get_tree().current_scene.scene_file_path == "res://src/ui/menu.tscn", "Return from debrief opens the preparation menu")
	var returned_menu = get_tree().current_scene
	returned_menu._on_start()
	check(returned_menu._starting and returned_menu.has_node("LoadingScreen"), "Start shows a loading screen before blocking scene work")
	var loading: Node = returned_menu.get_node("LoadingScreen")
	returned_menu._on_start()
	check(returned_menu.get_node("LoadingScreen") == loading, "Repeated start input creates only one scene transition")
	await screenshot("loading-screen")
	deadline = Time.get_ticks_msec() + 60000
	while (get_tree().current_scene == null or get_tree().current_scene.scene_file_path != "res://src/main.tscn" or not get_tree().current_scene.loading_complete) and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.01).timeout
	check(get_tree().current_scene.scene_file_path == "res://src/main.tscn", "Loading screen completes the transition into gameplay")
	check(not FileAccess.file_exists("res://src/player/weapon_defs.gd"), "Unused legacy weapon table is retired")
	print("AUDIT_REGRESSION: %d passed / %d failed" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)
