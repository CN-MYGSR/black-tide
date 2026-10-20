extends Node
## 把主菜单 5 个页签各拍一张

var menu: Control

func _ready() -> void:
	GameState.credits = 9000
	menu = load("res://src/ui/menu.tscn").instantiate()
	add_child(menu)
	await get_tree().create_timer(0.6).timeout
	for i in 5:
		menu._switch_tab(i)
		await get_tree().create_timer(0.45).timeout
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path("res://_shots/menu_%d.png" % i))
		print("snap menu_", i)
		if i == 1 and menu._preview != null:
			var pv: SubViewport = menu._preview
			await RenderingServer.frame_post_draw
			var pi := pv.get_texture().get_image()
			pi.save_png(ProjectSettings.globalize_path("res://_shots/menu_preview_only.png"))
			print("preview only ", pi.get_width(), "x", pi.get_height(),
				" center=", pi.get_pixel(pi.get_width()/2, pi.get_height()/2))
			print("  cam3d=", pv.get_camera_3d(), " model=", menu._preview_model,
				" in_tree=", menu._preview_model.is_inside_tree() if menu._preview_model else false,
				" visible=", menu._preview_model.is_visible_in_tree() if menu._preview_model else false,
				" children=", pv.get_child_count())
			print("  aabb=", menu._node_aabb(menu._preview_model),
				" scale=", menu._preview_model.scale,
				" pos=", menu._preview_model.global_position,
				" cam_pos=", pv.get_camera_3d().global_position)
	get_tree().quit()
