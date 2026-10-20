extends Node

var main: Node3D
var p: Player

func _ready() -> void:
	main = load("res://src/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(2.5).timeout
	p = main.player
	print("player pos=", p.global_position, " state=", p.state)
	if p.weapon_model != null:
		print("weapon pos=", p.weapon_model.position, " rot=", p.weapon_model.rotation_degrees,
			" scale=", p.weapon_model.scale, " ads_blend=", p.ads_blend(),
			" parent=", p.weapon_model.get_parent().name)
	await _snap("player_fps")

	# 切第三人称
	p._third_person = true
	p.spring.spring_length = 3.4
	if p.body_model != null:
		p.body_model.visible = true
	if p.weapon_model != null:
		p.weapon_model.visible = false
	p._ads = false
	await get_tree().create_timer(0.5).timeout
	await _snap("player_tps_idle")

	# 手动驱动一个"跑动 + 举枪"的姿势
	for i in 90:
		p.body_rig.animate_locomotion(1.0 / 60.0, 0.75, 1.0, 0.0)
		await get_tree().process_frame
	await _snap("player_tps_run")

	get_tree().quit()


func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://_shots/%s.png" % name))
	print("snap ", name)
