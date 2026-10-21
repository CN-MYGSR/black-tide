extends Node
## Gameplay regressions. Use an isolated APPDATA; this script never saves a profile.

var failures := 0
var checks := 0
var output := ProjectSettings.globalize_path("res://_shots/regression")

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	_run.call_deferred()

func check(condition: bool, label: String, detail: String) -> void:
	checks += 1
	if not condition:
		failures += 1
	print("%s | %s | %s" % ["PASS" if condition else "FAIL", label, detail])

func snapshot(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	var result := get_viewport().get_texture().get_image().save_png(output.path_join(label + ".png"))
	print("SCREENSHOT | %s | error=%d" % [label, result])

func _run() -> void:
	print("USER_DATA | ", OS.get_user_data_dir())
	Loadout.vehicle = "SM_Veh_Helicopter_Transport_01"
	var main = load("res://src/main.tscn").instantiate()
	add_child(main)
	while not main.loading_complete:
		await get_tree().process_frame
	await get_tree().create_timer(1.5).timeout
	main.set_process(false)
	for node in get_tree().get_nodes_in_group("combatant"):
		node.set_physics_process(false)
	for squad in main._squads:
		squad.set_process(false)
		squad.set_physics_process(false)
	var p: Player = main.player
	check(main.hud.size.is_equal_approx(get_viewport().get_visible_rect().size), "HUD fills viewport and centers crosshair", "hud=%s viewport=%s" % [main.hud.size, get_viewport().get_visible_rect().size])
	var deck_height: float = p.global_position.y - main.world.terrain.height_at(p.global_position.x, p.global_position.z)
	check(deck_height > 0.5, "Player stands on helipad instead of sinking through it", str(deck_height))
	print("INITIAL | primary=%s secondary=%s current=%s ammo=%d reserve=%d" % [Loadout.primary, Loadout.secondary, p.current_def()["id"], p.ammo_mag, p.ammo_reserve])
	await snapshot("01_first_person")
	Input.action_press("aim")
	for i in 30:
		p._process_combat(1.0 / 60.0)
	Input.action_release("aim")
	await snapshot("01b_aim_down_sights")
	for sight in p.weapon_model.find_children("*Sight_Glass*", "MeshInstance3D", true, false):
		if "RailCanted" in str(sight.name):
			continue
		var point: Vector3 = p.camera.to_local(sight.to_global(sight.get_aabb().get_center()))
		check(absf(point.x) < 0.005 and absf(point.y) < 0.005, "Optic aligns with camera center", str(point))
		var material: BaseMaterial3D = sight.get_active_material(0)
		check(material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and material.albedo_color.a < 0.5, "Optic glass remains transparent", "mode=%d alpha=%f" % [material.transparency, material.albedo_color.a])
		AssetLib.apply_tint(p.weapon_model, Color(0.4, 0.5, 0.3))
		material = sight.get_active_material(0)
		check(material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and material.albedo_color.a < 0.5, "Camo preserves optic transparency", "mode=%d alpha=%f" % [material.transparency, material.albedo_color.a])
		break
	p._ads_blend = 0.0
	p._process_combat(0.0)

	var primary := p.weapon_id
	p._fire()
	var magazine := p.ammo_mag
	var reserve := p.ammo_reserve
	p._switch_slot(1)
	check(p.weapon_id == primary, "Switching to secondary preserves primary ID", "expected=%s actual=%s" % [primary, p.weapon_id])
	p._fire()
	var secondary_spent := p.ammo_mag
	p._switch_slot(0)
	check(str(p.current_def()["id"]) == primary, "Returning to primary restores the rifle", "expected=%s actual=%s" % [primary, p.current_def()["id"]])
	check(p.ammo_mag == magazine and p.ammo_reserve == reserve, "Switching preserves primary ammo", "before=%d/%d after=%d/%d" % [magazine, reserve, p.ammo_mag, p.ammo_reserve])
	p._switch_slot(1)
	check(p.ammo_mag == secondary_spent, "Switching preserves fired secondary ammo", "expected=%d actual=%d" % [secondary_spent, p.ammo_mag])
	p._start_reload()
	p._finish_reload()
	var secondary_loaded := p.ammo_mag
	var secondary_reserve := p.ammo_reserve
	p._switch_slot(0)
	p._switch_slot(1)
	check(p.ammo_mag == secondary_loaded and p.ammo_reserve == secondary_reserve, "Switching preserves secondary reload", "expected=%d/%d actual=%d/%d" % [secondary_loaded, secondary_reserve, p.ammo_mag, p.ammo_reserve])
	p._burst_left = 2
	p._reloading = true
	p._switch_slot(0)
	check(not p._reloading and p._burst_left == 0, "Switching cancels reload and queued burst", "reload=%s burst=%d" % [p._reloading, p._burst_left])
	await snapshot("02_primary_slot_after_switch")

	# Same weapon in both slots isolates the refill from the overwritten-ID bug.
	var probe := Player.new()
	var secondary := Loadout.secondary
	Loadout.secondary = Loadout.primary
	add_child(probe)
	Loadout.secondary = secondary
	probe.set_physics_process(false)
	probe.camera.current = false
	p.camera.current = true
	probe._fire()
	var spent := probe.ammo_mag
	probe._switch_slot(1)
	probe._switch_slot(0)
	check(probe.ammo_mag == spent, "Same-weapon swap does not refill ammo", "before=%d after=%d" % [spent, probe.ammo_mag])
	probe.queue_free()

	var toggle := InputEventAction.new()
	toggle.action = "toggle_view"
	toggle.pressed = true
	p._unhandled_input(toggle)
	check(p.body_model != null, "Third-person player body exists", "third_person=%s body_model=%s body_rig=%s" % [p._third_person, p.body_model, p.body_rig])
	if p.body_rig != null and p.body_rig.ready:
		var leg: int = p.body_rig.skel.find_bone("UpperLeg_L")
		var rest: Quaternion = p.body_rig.skel.get_bone_pose_rotation(leg)
		p.velocity = Vector3(0, 0, -p.SPRINT_SPEED)
		for i in 12:
			p._update_body_rig(1.0 / 60.0)
		check(not rest.is_equal_approx(p.body_rig.skel.get_bone_pose_rotation(leg)), "Player locomotion animates bones", str(p.body_rig.skel.get_bone_pose_rotation(leg)))
		p.velocity = Vector3.ZERO
	p._switch_slot(1)
	check(not p.weapon_model.visible and p._body_weapon != null, "Third-person weapon stays in the hand after switching", "fps_visible=%s hand_weapon=%s" % [p.weapon_model.visible, p._body_weapon])
	await snapshot("03_third_person")
	_test_npc_animation(main._allies[0])

	var v: Vehicle = main._vehicle
	check(v != null, "Purchased helicopter node exists", str(v))
	if v != null:
		v.set_physics_process(false)
		check(v._model != null, "Purchased helicopter has a visible model", "model_id=%s model=%s missing=%s" % [v.model_id, v._model, AssetLib.missing_models])
		check(v.motion_mode == CharacterBody3D.MOTION_MODE_FLOATING, "Helicopter uses floating motion", "expected=%d actual=%d" % [CharacterBody3D.MOTION_MODE_FLOATING, v.motion_mode])
		for child in v.get_children():
			if child is CollisionShape3D and child.shape is BoxShape3D:
				check(child.shape.size == Vector3(3.0, 2.2, 6.0), "Helicopter has its intended collider", "expected=(3,2.2,6) actual=%s" % child.shape.size)
				var query := PhysicsShapeQueryParameters3D.new()
				query.shape = child.shape
				query.transform = child.global_transform
				query.collision_mask = 1
				check(v.get_world_3d().direct_space_state.intersect_shape(query).is_empty(), "Helicopter spawns clear of buildings and deck", str(v.global_position))
		var cam := Camera3D.new()
		add_child(cam)
		cam.global_position = v.global_position + Vector3(10, 7, 12)
		cam.look_at(v.global_position + Vector3(0, 1, 0))
		cam.current = true
		await snapshot("04_purchased_helicopter")
		cam.queue_free()
		await _test_driving(v, p, true)

	var ground := Vehicle.new()
	ground.setup("SM_Veh_SUV_01", "ground", 22.0, 0.0, "Test SUV")
	add_child(ground)
	ground.set_physics_process(false)
	await _test_driving(ground, p, false)
	ground.queue_free()
	await _test_weapons()
	check(AssetLib.missing_models.is_empty(), "All tested models exist", str(AssetLib.missing_models))
	print("REPRO_RESULT | checks=%d failures=%d" % [checks, failures])
	get_tree().quit(1 if failures else 0)

func _test_driving(v: Vehicle, p: Player, air: bool) -> void:
	var label := "Helicopter" if air else "Ground vehicle"
	var floor_body: StaticBody3D
	if not air:
		floor_body = StaticBody3D.new()
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(30, 1, 30)
		collision.shape = shape
		floor_body.add_child(collision)
		floor_body.position = Vector3(60, 179.5, 0)
		add_child(floor_body)
	v.global_position = Vector3(0 if air else 60, 180, 0)
	if not air:
		for i in 45:
			await get_tree().physics_frame
			v._physics_process(1.0 / 60.0)
		check(v.is_on_floor(), "Ground vehicle rests on the road", str(v.global_position))
	check(v._model != null and v._model.global_transform.basis.z.normalized().dot(-v.global_transform.basis.z) > 0.99, label + " model faces travel direction", str(v._model.rotation.y))
	p._third_person = false
	p.spring.spring_length = 0.0
	p.rotation = Vector3.ZERO
	p._yaw = 0.0
	p.cam_pivot.rotation = Vector3.ZERO
	p.camera.rotation = Vector3.ZERO
	p.global_position = v.global_position + Vector3(0, 0, 4.5 if air else 3.8)
	for i in 3:
		await get_tree().physics_frame
	var interact := InputEventAction.new()
	interact.action = "interact"
	interact.pressed = true
	Input.action_press("interact")
	p._unhandled_input(interact)
	v._physics_process(1.0 / 60.0)
	Input.action_release("interact")
	check(v.driver == p and p.vehicle == v, label + " remains occupied after entry input", "driver=%s vehicle=%s" % [v.driver, p.vehicle])
	check(p.collision_layer == 0 and not p.visible, label + " hides driver collision", "layer=%d visible=%s" % [p.collision_layer, p.visible])
	await snapshot("05_driving_helicopter" if air else "06_driving_suv")
	Input.action_press("move_forward")
	Input.action_press("move_left")
	if air:
		Input.action_press("jump")
	var start := v.global_position
	for i in 15:
		await get_tree().physics_frame
		v._physics_process(1.0 / 60.0)
	Input.action_release("move_forward")
	Input.action_release("move_left")
	Input.action_release("jump")
	check(v.global_position.distance_to(start) > 0.01, label + " moves under throttle", str(v.global_position - start))
	check(v.rotation.y > 0.0, label + " turns left with A", str(v.rotation.y))
	check(p.global_position.is_equal_approx(v.global_position), label + " carries player position", "player=%s vehicle=%s" % [p.global_position, v.global_position])
	if air:
		check(v.global_position.y > start.y, label + " climbs with Space", str(v.global_position.y - start.y))
		Input.action_press("crouch")
		for i in 30:
			await get_tree().physics_frame
			v._physics_process(1.0 / 60.0)
		Input.action_release("crouch")
		check(v.velocity.y < 0, label + " descends with C", str(v.velocity.y))
	p._unhandled_input(interact)
	p.set_physics_process(false)
	check(v.driver == null and p.vehicle == null and p.collision_layer == 2 and p.visible and p.camera.current, label + " exits and restores player", "driver=%s vehicle=%s layer=%d" % [v.driver, p.vehicle, p.collision_layer])
	v.enter(p)
	p.take_damage(10000.0, p.global_position, null)
	check(p.state == Player.State.DOWNED and p.vehicle == null and v.driver == null and p.is_physics_processing(), label + " releases a downed driver", "state=%d vehicle=%s" % [p.state, p.vehicle])
	p.revive()
	p.set_physics_process(false)
	if floor_body != null:
		floor_body.queue_free()

func _test_npc_animation(s: Soldier) -> void:
	check(s.rig != null and s.rig.ready, "NPC skeleton is bound", str(s.rig))
	if s.rig == null or not s.rig.ready:
		return
	var leg: int = s.rig.skel.find_bone("UpperLeg_L")
	var rest: Quaternion = s.rig.skel.get_bone_pose_rotation(leg)
	s.velocity = Vector3(0, 0, -s.RUN)
	s.state = Soldier.AIState.PATROL
	for i in 12:
		s._update_visual(1.0 / 60.0)
	check(not rest.is_equal_approx(s.rig.skel.get_bone_pose_rotation(leg)), "NPC locomotion animates bones", str(s.rig.skel.get_bone_pose_rotation(leg)))
	check(is_equal_approx(absf(s.model.rotation.y), PI), "NPC model faces movement direction", str(s.model.rotation.y))
	s._go_down()
	var down: Quaternion = s.rig.skel.get_bone_pose_rotation(leg)
	s.revive()
	check(not down.is_equal_approx(s.rig.skel.get_bone_pose_rotation(leg)) and s.state == Soldier.AIState.PATROL, "NPC revival resets downed pose", str(s.rig.skel.get_bone_pose_rotation(leg)))
	s.velocity = Vector3.ZERO

func _test_weapons() -> void:
	var probe := Player.new()
	var secondary := Loadout.secondary
	Loadout.secondary = "SM_Wep_Pistol_Metal_01"
	add_child(probe)
	Loadout.secondary = secondary
	probe.set_physics_process(false)
	check(probe.sidearm_mag == 7 and probe.sidearm_reserve == 56, "Non-default secondary uses its own ammo capacity", "%d/%d" % [probe.sidearm_mag, probe.sidearm_reserve])
	for id in ItemDB.WEAPONS:
		probe._equip(id)
		probe._ads_blend = 1.0
		probe._update_weapon_pose(0.0)
		check(probe.weapon_model != null, "Weapon model: " + id, str(probe.weapon_model))
		for sight in probe.weapon_model.find_children("*Sight_Glass*", "MeshInstance3D", true, false):
			if "RailCanted" in str(sight.name):
				continue
			var point: Vector3 = probe.camera.to_local(sight.to_global(sight.get_aabb().get_center()))
			var material: BaseMaterial3D = sight.get_active_material(0)
			check(absf(point.x) < 0.001 and absf(point.y) < 0.001 and material.albedo_color.a < 0.5, "Aligned transparent optic: " + id, str(point))
			break
		await get_tree().process_frame
	probe.queue_free()
