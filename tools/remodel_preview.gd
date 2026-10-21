extends Node3D
## Asset review in the actual engine. Uses no player profile writes.

var failures := 0

func check(ok: bool, label: String) -> void:
	print("PASS | " if ok else "FAIL | ", label)
	if not ok:
		failures += 1

func bounds(root: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = root.global_transform.affine_inverse() * n.global_transform * n.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("141e26")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("b4c5cf")
	e.ambient_light_energy = 0.65
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -30, 0)
	sun.light_energy = 1.7
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	ground.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("253139")
	material.roughness = 0.9
	ground.material_override = material
	add_child(ground)
	var names := ["SM_Chr_Soldier_Male_01", "SM_Chr_Soldier_Male_02", "SM_Chr_Insurgent_Male_01",
		"SM_Chr_Insurgent_Male_02", "SM_Chr_Insurgent_Male_03", "SM_Chr_Leader_Male_01", "SM_Chr_Ghillie_Male_01"]
	for i in names.size():
		var model := AssetLib.spawn(names[i], self, Vector3((i - 3) * 1.15, 0, 0))
		check(model != null, names[i] + " loads")
		if model == null:
			continue
		var rig := CharacterRig.new()
		check(rig.setup(model), names[i] + " skeleton ready")
		check(rig.skel.find_bone("Hand_R") >= 0, names[i] + " hand attachment")
		check(rig.attach_weapon("SM_Wep_Preset_A_Rifle_01", model) != null and rig._gloves.size() == 2,
			names[i] + " preview includes closed gloves")
		var head := rig.skel.to_global(rig.skel.get_bone_global_pose(rig.skel.find_bone("Head")).origin)
		var ankle := rig.skel.to_global(rig.skel.get_bone_global_pose(rig.skel.find_bone("Ankle_L")).origin)
		check(head.y - ankle.y > 1.35 and head.y - ankle.y < 1.65, names[i] + " meter scale")
		check(rig.skel.global_basis.get_scale().is_equal_approx(Vector3.ONE * 0.01), names[i] + " centimeter skeleton retained")
		for step in 45:
			rig.animate_locomotion(1.0 / 60.0, 0.65, 1.0)
		await get_tree().process_frame
		check(bounds(model).size.length() < 4.0, names[i] + " animation bounded")
		rig.reset()
		for step in 60:
			rig.animate_locomotion(1.0 / 60.0, 0, 0)
		var label := Label3D.new()
		label.text = ["ASSAULT / SAND", "ASSAULT / OLIVE", "OPFOR / RIFLE", "OPFOR / SCOUT", "OPFOR / HEAVY", "OPFOR / LEAD", "RECON"][i]
		label.font_size = 32
		label.pixel_size = 0.0018
		label.position = Vector3((i - 3) * 1.15, -0.08, 0.15)
		add_child(label)
	var guns := ["SM_Wep_Preset_A_Rifle_01", "SM_Wep_Preset_A_Rifle_03", "SM_Wep_Preset_B_Rifle_01",
		"SM_Wep_Preset_B_Rifle_02", "SM_Wep_Preset_B_Rifle_03", "SM_Wep_Rifle_01", "SM_Wep_Pistol_01"]
	for i in guns.size():
		var gun := AssetLib.spawn(guns[i], self, Vector3((i - 3) * 1.15, 0.28, 0.9))
		check(gun != null, guns[i] + " loads")
		if gun != null:
			var length := bounds(gun).size.z
			check(length > (0.12 if guns[i].contains("Pistol") else 0.2) and length < 1.2, guns[i] + " weapon dimensions")
			gun.rotation_degrees = Vector3(0, 75, 0)
	check(AssetLib.unresolved.is_empty(), "No unresolved materials")
	check(AssetLib.missing_models.is_empty(), "No missing models")
	var player := Player.new()
	add_child(player)
	player.set_process(false)
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	for id in guns:
		player._equip(id)
		player._sway = Vector2.ZERO
		player._mouse_delta = Vector2.ZERO
		player._weapon_kick = 0.0
		player._ads_blend = 1.0
		player._update_weapon_pose(0.0)
		for sight in player.weapon_model.find_children("*Sight_Glass*", "MeshInstance3D", true, false):
			var point: Vector3 = player.camera.to_local(sight.to_global(sight.get_aabb().get_center()))
			var glass: BaseMaterial3D = sight.get_active_material(0)
			check(absf(point.x) < 0.001 and absf(point.y) < 0.001, id + " optic aligns")
			check(glass.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and glass.albedo_color.a < 0.5, id + " glass transparent")
	player.queue_free()
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 4.8
	add_child(cam)
	cam.position = Vector3(0.6, 2.0, 8)
	cam.look_at(Vector3(0, 0.85, 0))
	cam.current = true
	if DisplayServer.get_name() != "headless":
		await get_tree().create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://_shots/remodel_engine.png"))
		cam.size = 1.65
		cam.position = Vector3(-2.65, 1.8, 3.0)
		cam.look_at(Vector3(-3.45, 1.0, 0))
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://_shots/remodel_engine_close.png"))
	print("REMODEL_CHECK_DONE failures=", failures)
	get_tree().quit(1 if failures else 0)
