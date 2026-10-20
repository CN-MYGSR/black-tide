extends Node3D
## 骨骼动画调参台：三个士兵并排（待机 / 走路 / 瞄准），拍正面与侧面两张。

var rigs: Array = []
var mode: Array = []


func _ready() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 40, 0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	add_child(sun)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.42, 0.5, 0.58)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.6, 0.68)
	e.ambient_light_energy = 0.7
	env.environment = e
	add_child(env)

	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.36, 0.40, 0.30)
	ground.material_override = gm
	add_child(ground)

	var configs := [
		{"x": -2.6, "ratio": 0.0, "aim": 0.0},
		{"x": 0.0, "ratio": 0.55, "aim": 0.0},
		{"x": 2.6, "ratio": 0.0, "aim": 1.0},
	]
	for c in configs:
		var s := Soldier.new()
		add_child(s)
		s.global_position = Vector3(c["x"], 0, 0)
		s.configure("blufor", "SM_Chr_Soldier_Male_01", 0.8)
		s.state = Soldier.AIState.IDLE
		s.set_physics_process(false)
		s.model.rotation.y = 0.0
		rigs.append(s.rig)
		mode.append(c)

	var cam := Camera3D.new()
	cam.fov = 50.0
	add_child(cam)
	cam.current = true

	await get_tree().create_timer(0.4).timeout

	# 正面 3/4
	cam.global_position = Vector3(3.2, 1.7, 6.2)
	cam.look_at(Vector3(0, 1.0, 0), Vector3.UP)
	await get_tree().create_timer(0.6).timeout
	await _snap("anim_front")

	# 侧面（看腿的摆动）
	cam.global_position = Vector3(8.5, 1.5, 0.2)
	cam.look_at(Vector3(0, 1.0, 0), Vector3.UP)
	await get_tree().create_timer(0.3).timeout
	await _snap("anim_side")

	get_tree().quit()


func _process(delta: float) -> void:
	for i in rigs.size():
		var r = rigs[i]
		if r == null or not r.ready:
			continue
		r.animate_locomotion(delta, float(mode[i]["ratio"]), float(mode[i]["aim"]), 0.0)


func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://_shots/%s.png" % name))
	print("snap ", name)
