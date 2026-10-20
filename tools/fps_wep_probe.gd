extends Node3D
## 第一人称持枪角度对比：同一个相机位，只改 yaw，拍 4 张。

var cam: Camera3D
var w: Node3D

func _ready() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 25, 0)
	sun.light_energy = 1.6
	add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.58, 0.62)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.7, 0.72)
	e.ambient_light_energy = 1.0
	env.environment = e
	add_child(env)

	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	ground.mesh = pm
	ground.position = Vector3(0, 0, -8)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.45, 0.47, 0.40)
	ground.material_override = gm
	add_child(ground)

	cam = Camera3D.new()
	cam.fov = 78.0
	add_child(cam)
	cam.current = true
	cam.global_position = Vector3(0, 1.6, 0)

	w = AssetLib.spawn("SM_Wep_Preset_A_Rifle_01", cam, Vector3(0.28, -0.26, -0.58), 0.0, true)
	w.scale = Vector3.ONE * 0.70

	await get_tree().create_timer(0.3).timeout
	for yaw in [0, 90, 180, 270]:
		w.rotation_degrees = Vector3(0, yaw, 0)
		await get_tree().create_timer(0.15).timeout
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path("res://_shots/fps_yaw_%d.png" % yaw))
		print("snap yaw=", yaw)
	get_tree().quit()
