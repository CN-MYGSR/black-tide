extends Node3D
## Check the candidate before AssetLib selects it for normal play.

func _ready() -> void:
	assert(OS.get_environment("BLACK_TIDE_TEST_PROFILE") == "1")
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("9bafb9")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_energy = 0.7
	environment.environment = env
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -25, 0)
	sun.light_energy = 1.5
	add_child(sun)
	var camera := Camera3D.new()
	add_child(camera)
	camera.current = true
	var output := ProjectSettings.globalize_path("res://_shots/operator_lod")
	DirAccess.make_dir_recursive_absolute(output)
	var reference: Skeleton3D
	for id in ["BT_Operator_Batched", "BT_Operator_LOD"]:
		var body := AssetLib.spawn(id, self)
		var rig := CharacterRig.new()
		assert(rig.setup(body))
		if reference == null:
			reference = rig.skel
		else:
			assert(rig.skel.get_bone_count() == reference.get_bone_count())
			for bone in reference.get_bone_count():
				assert(rig.skel.get_bone_name(bone) == reference.get_bone_name(bone))
				assert(rig.skel.get_bone_rest(bone).is_equal_approx(reference.get_bone_rest(bone)))
		var gun := rig.attach_weapon("SM_Wep_Preset_A_Rifle_01", body)
		assert(gun != null and rig._gloves.size() == 2)
		for mesh in body.find_children("BT_Operator*", "MeshInstance3D", true, false):
			assert(mesh.get_node(mesh.skeleton) == rig.skel)
			assert(mesh.skin.get_bind_count() == 22)
		for distance in ([3.0] if id == "BT_Operator_Batched" else [3.0, 20.0, 50.0]):
			camera.position = Vector3(0, 1.1, distance)
			camera.look_at(Vector3(0, 1.0, 0))
			camera.fov = rad_to_deg(2 * atan(1.1 / distance))
			for aim in [0.0, 1.0]:
				for frame in 90:
					rig.animate_locomotion(1.0 / 60, 0, aim)
				for hand in 2:
					var expected: Vector3 = (rig._gloves[hand].global_transform * rig._wrists[hand]).origin
					var actual := rig.skel.to_global(rig.skel.get_bone_global_pose(rig.skel.find_bone("Hand_R" if hand == 0 else "Hand_L")).origin)
					assert(expected.distance_to(actual) < 0.012)
				if DisplayServer.get_name() != "headless":
					for frame in 3: await get_tree().process_frame
					await RenderingServer.frame_post_draw
					assert(get_viewport().get_texture().get_image().save_png(output.path_join("%s_%d_%d.png" % [id, distance, aim])) == OK)
		if id == "BT_Operator_Batched":
			body.visible = false
		else:
			body.queue_free()
	assert(AssetLib.unresolved.is_empty())
	print("OPERATOR_LOD_ENGINE_PASSED: rest bones / skin / both wrists / three distances")
	get_tree().quit()
