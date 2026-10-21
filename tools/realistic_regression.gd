extends Node3D
## Verify the free assets in the real engine, including hands and reload deformation.

var failures := 0
var checks := 0
var player: Player

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("PASS | " if ok else "FAIL | ", label)

func snap(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path("res://_shots/realistic")
	DirAccess.make_dir_recursive_absolute(path)
	get_viewport().get_texture().get_image().save_png(path.path_join(label + ".png"))

func _ready() -> void:
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("9bafb9")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("a5b4bd")
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.environment = env
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -25, 0)
	sun.light_energy = 1.7
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	ground.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("51605a")
	ground.material_override = material
	add_child(ground)
	var target := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.6, 1.8, 0.3)
	target.mesh = box
	target.position = Vector3(0, 0.9, -10)
	add_child(target)
	player = Player.new()
	add_child(player)
	player.set_process(false)
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for id in ItemDB.WEAPONS:
		player._equip(id)
		player._sway = Vector2.ZERO
		player._mouse_delta = Vector2.ZERO
		player._weapon_kick = 0
		check(not player.weapon_model.find_children("*FPArms*", "MeshInstance3D", true, false).is_empty(), id + " has first-person hands")
	player._equip("SM_Wep_Preset_A_Rifle_01")
	player._ads_blend = 0
	player._update_weapon_pose(0)
	await snap("01_m4_hip")
	var still := player.weapon_model.position
	player.velocity = Vector3(4, 0, 0)
	player._bob = PI / 2
	player._update_weapon_pose(0)
	check(player.weapon_model.position.distance_to(still) > 0.005, "Walking moves the complete gun / hands rig")
	player.velocity = Vector3.ZERO
	player._shake = 0.6
	player._update_camera_fx(0)
	check(player.weapon_mount.rotation.length() > 0.001, "Arms respond relative to camera shake")
	check(player.weapon_mount.rotation.dot(player.camera.rotation) < 0, "Eye shake and body-held arms have relative inertia")
	player._shake = 0
	player._update_camera_fx(0)
	player._update_weapon_pose(0)
	check(player._viewmodel_animation != null and player._viewmodel_reload != &"", "M4 has authored reload")
	var skeletons := player.weapon_model.find_children("*", "Skeleton3D", true, false)
	check(not skeletons.is_empty(), "M4 has articulated fingers / arms")
	var skel := skeletons[0] as Skeleton3D
	for side in ["L", "R"]:
		var shoulder := skel.get_bone_global_pose(skel.find_bone("UpArm_" + side)).origin
		check(player.camera.to_local(skel.to_global(shoulder)).z > 0.03, side + " shoulder cutoff is behind the camera")
	var hand := skel.find_bone("Hand_L")
	var original := skel.get_bone_global_pose(hand).origin
	player._reloading = true
	player._reload_t = float(player.current_def()["reload"]) * 0.65
	player._update_weapon_pose(0)
	await get_tree().process_frame
	check(skel.get_bone_global_pose(hand).origin.distance_to(original) > 0.1, "Reload moves the support hand off the handguard")
	await snap("02_m4_reload_out")
	player._reload_t = float(player.current_def()["reload"]) * 0.31
	player._update_weapon_pose(0)
	await snap("03_m4_reload_in")
	player._reloading = false
	player._ads_blend = 1
	player.camera.fov = float(player.current_def()["zoom"])
	player._update_weapon_pose(0)
	var anchor := player.weapon_model.find_child("BT_AimAnchor", true, false) as Node3D
	var point := player.camera.to_local(anchor.global_position)
	check(absf(point.x) < 0.001 and absf(point.y) < 0.001, "M4 sight anchor is centered")
	await snap("04_m4_ads")
	player._ads_blend = 0
	player.camera.fov = 78
	for pair in [["SM_Wep_Rifle_01", "05_ak_hip"], ["SM_Wep_Pistol_Metal_01", "06_m1911_hip"], ["SM_Wep_Pistol_01", "07_m9_hands"]]:
		player._equip(pair[0])
		player._update_weapon_pose(0)
		await snap(pair[1])
	var npc := Soldier.new()
	add_child(npc)
	npc.configure("blufor", "SM_Chr_Soldier_Male_01", 1.0, "SM_Wep_Preset_A_Rifle_01")
	npc.set_physics_process(false)
	npc.position = Vector3(0, 0, -4)
	npc.model.rotation.y = 0
	for step in 60:
		npc.rig.animate_locomotion(1.0 / 60.0, 0, 0)
	check(npc.rig.ready, "Realistic operator animates")
	check(npc.rig._gloves.size() == 2, "Third-person has weapon-specific closed gloves")
	for id in ItemDB.WEAPONS:
		if is_instance_valid(npc.rig._weapon_mount):
			npc.rig._weapon_mount.queue_free()
		var gun: Node3D = npc.rig.attach_weapon(id, npc.model)
		check(gun != null and gun.find_child("BT_GripL", true, false) != null, id + " has measured support contact")
		var largest_gap := 0.0
		for aim in [0.0, 0.5, 1.0]:
			for step in 90:
				npc.rig.animate_locomotion(1.0 / 60, 0.5, aim, 0.4 if aim == 0.5 else 0)
			for i in 2:
				var expected: Vector3 = (npc.rig._gloves[i].global_transform * npc.rig._wrists[i]).origin
				var actual: Vector3 = npc.rig.skel.to_global(npc.rig.skel.get_bone_global_pose(npc.rig.skel.find_bone("Hand_R" if i == 0 else "Hand_L")).origin)
				largest_gap = maxf(largest_gap, expected.distance_to(actual))
		check(largest_gap < 0.012, id + " wrists meet gloves across ready / walk / aim (gap %.4fm)" % largest_gap)
		npc.rig.pose_downed()
		await get_tree().process_frame
		check(not gun.visible and npc.rig._gloves[0].is_visible_in_tree(), id + " downed keeps gloves and releases gun")
		npc.rig.animate_locomotion(1.0 / 60, 0, 1)
		await get_tree().process_frame
		check(gun.visible and npc.rig._gloves[0].get_parent() == gun, id + " revive restores grip")
	for step in 1800:
		npc.rig.animate_locomotion(1.0 / 60, 0.5, 0.8, sin(step * 0.02) * 0.3)
	var scale: Vector3 = (npc.rig.skel.global_basis * npc.rig.skel.get_bone_global_pose(npc.rig.skel.find_bone("Hand_R")).basis).get_scale()
	check(scale.distance_to(Vector3.ONE * 0.01) < 0.0001, "Arm IK scale stays stable after 1800 frames")
	player.visible = false
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(1.6, 1.5, -1.3)
	camera.look_at(Vector3(0, 1.0, -4))
	camera.fov = 45
	camera.current = true
	await snap("08_operator_engine")
	check(AssetLib.missing_models.is_empty(), "No missing model resources")
	check(AssetLib.unresolved.is_empty(), "PBR materials resolve")
	print("REALISTIC_RESULT checks=%d failures=%d" % [checks, failures])
	get_tree().quit(1 if failures else 0)
