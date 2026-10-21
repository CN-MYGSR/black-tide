extends Node3D
## Character rendering / animation stress test, separate from full-game AI benchmark.

var actors: Array[Soldier] = []
var active_count := 0
var pose_usec := 0
var pose_ticks := 0

func _ready() -> void:
	assert(OS.get_environment("BLACK_TIDE_TEST_PROFILE") == "1")
	assert(DisplayServer.get_name() != "headless")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("9bafb9")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_energy = 0.8
	environment.environment = env
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -25, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(0, 6, 10)
	camera.look_at(Vector3(0, 0.8, -5))
	camera.fov = 68
	for i in 128:
		var actor := Soldier.new()
		add_child(actor)
		actor.configure("blufor", "SM_Chr_Soldier_Male_01", 1, "SM_Wep_Preset_A_Rifle_01")
		actor.set_physics_process(false)
		actor.position = Vector3((i % 16 - 7.5) * 1.0, 0, -float(i / 16) * 1.3)
		actor.model.rotation.y = 0
		actor.velocity = Vector3(0, 0, 1.3)
		actor.visible = false
		actors.append(actor)
	for count in [32, 64, 96, 128]:
		active_count = count
		pose_usec = 0
		pose_ticks = 0
		for i in actors.size(): actors[i].visible = i < count
		for frame in 60: await get_tree().process_frame
		var samples: Array[float] = []
		var last := Time.get_ticks_usec()
		for frame in 180:
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			samples.append((now - last) / 1000.0)
			last = now
		var total := 0.0
		for value in samples: total += value
		samples.sort()
		print("CROWD|", JSON.stringify({"count":count,"pose_ms":pose_usec / maxf(1,pose_ticks) / 1000.0,"mean_ms":total / samples.size(),"p95_ms":samples[170],"fps":1000.0 / (total / samples.size()),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"triangles":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)}))
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://_shots/crowd_128.png"))
	print("CROWD_DONE")
	get_tree().quit()

func _physics_process(delta: float) -> void:
	var started := Time.get_ticks_usec()
	for i in active_count:
		actors[i]._update_visual(delta)
	pose_usec += Time.get_ticks_usec() - started
	pose_ticks += 1
