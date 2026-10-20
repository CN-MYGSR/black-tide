extends Node3D
## 小队可视化：巡逻楔形队形 -> 接触 -> 突击（两组交替）

var squad: Squad
var members: Array = []
var cam: Camera3D
var target: Node3D


func _ready() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, 35, 0)
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.52, 0.56, 0.60)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.64, 0.66)
	e.ambient_light_energy = 0.9
	env.environment = e
	add_child(env)

	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.38, 0.42, 0.32)
	ground.material_override = gm
	add_child(ground)

	# 地面必须有碰撞，否则士兵会一直往下掉
	var gb := StaticBody3D.new()
	var gcs := CollisionShape3D.new()
	var gbox := BoxShape3D.new()
	gbox.size = Vector3(200, 1, 200)
	gcs.shape = gbox
	gcs.position.y = -0.5
	gb.add_child(gcs)
	add_child(gb)

	# 目标必须是一个"可交战的实体"（要有 faction / is_alive / take_damage），
	# 否则士兵不会进入 COMBAT，也就不会执行小队指令
	var dummy := Player.new()
	add_child(dummy)
	dummy.global_position = Vector3(0, 1.2, -40)
	dummy.set_physics_process(false)
	target = dummy

	squad = Squad.new()
	add_child(squad)
	squad.setup("opfor", "probe", Vector3(0, 0, 0), 12.0)

	var models := ["SM_Chr_Insurgent_Male_01", "SM_Chr_Insurgent_Male_02",
		"SM_Chr_Insurgent_Male_03", "SM_Chr_Leader_Male_01"]
	for i in 4:
		var s := Soldier.new()
		add_child(s)
		s.global_position = Vector3(float(i - 1) * 2.0, 0.3, 2.0)
		s.configure("opfor", models[i], 0.7)
		s.patrol_points = [Vector3(0, 0, -10)]
		squad.add_member(s)
		members.append(s)

	cam = Camera3D.new()
	cam.fov = 55.0
	add_child(cam)
	cam.current = true

	# 1. 巡逻队形
	for i in 40:
		await get_tree().process_frame
	_shot_from(Vector3(9, 6, 11), Vector3(0, 1, 0))
	await _snap("squad_01_formation")

	# 2. 接触后突击
	squad.report_contact(target.global_position, target)
	for i in 150:
		await get_tree().physics_frame
	_shot_from(Vector3(13, 7, 9), Vector3(0, 1, -10))
	await _snap("squad_02_assault")

	# 3. 减员后溃退
	squad.on_member_down(members[3])
	squad.on_member_down(members[2])
	squad.on_member_down(members[1])
	for i in 40:
		await get_tree().process_frame
	_shot_from(Vector3(10, 7, 13), Vector3(0, 1, 0))
	await _snap("squad_03_broken")

	print("squad state=", squad.status_text(), " morale=", squad.morale)
	get_tree().quit()


func _shot_from(pos: Vector3, look: Vector3) -> void:
	cam.global_position = pos
	cam.look_at(look, Vector3.UP)


func _snap(name: String) -> void:
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://_shots/%s.png" % name))
	print("snap ", name)
