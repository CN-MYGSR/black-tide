extends Node
## 截图工具：起真实窗口跑一局，用自由相机拍几个角度，存到 _shots/。
## 跑法: godot --path . res://tools/shot.tscn

var main: Node3D
var cam: Camera3D
var out_dir: String


func _ready() -> void:
	out_dir = ProjectSettings.globalize_path("res://_shots")
	DirAccess.make_dir_recursive_absolute(out_dir)

	var ps: PackedScene = load("res://src/main.tscn")
	main = ps.instantiate()
	add_child(main)
	await get_tree().create_timer(2.5).timeout

	cam = Camera3D.new()
	cam.fov = 68.0
	cam.far = 2000.0
	add_child(cam)
	cam.current = true

	var world: WorldRoot = main.world
	var fob: Dictionary = world.poi_by_id("fob")
	var fob_pos := Vector3(fob["pos"].x, world.terrain.height_at(fob["pos"].x, fob["pos"].y), fob["pos"].y)

	# 1. 玩家视角
	await _shoot(fob_pos + Vector3(6, 2.2, 14), fob_pos + Vector3(0, 2.0, -6), "01_player_view")

	# 2. 基地俯瞰
	await _shoot(fob_pos + Vector3(60, 55, 70), fob_pos + Vector3(0, 0, 0), "02_fob_air")

	# 3. 各据点
	for id in ["hill42", "zarya", "kestrel", "vertex", "depot"]:
		var poi: Dictionary = world.poi_by_id(id)
		if poi.is_empty():
			continue
		var p := Vector3(poi["pos"].x, world.terrain.height_at(poi["pos"].x, poi["pos"].y), poi["pos"].y)
		await _shoot(p + Vector3(70, 48, 78), p + Vector3(0, 2, 0), "03_" + id)

	# 4. 地面特写（看材质和建筑细节）
	var zarya: Dictionary = world.poi_by_id("zarya")
	if not zarya.is_empty():
		var zp := Vector3(zarya["pos"].x, world.terrain.height_at(zarya["pos"].x, zarya["pos"].y), zarya["pos"].y)
		await _shoot(zp + Vector3(-26, 3.2, -30), zp + Vector3(4, 3.0, 6), "04_ground_detail")

	# 5. 围墙近景（从外面看，确认朝向与连续性）
	await _shoot(fob_pos + Vector3(10, 2.4, 46), fob_pos + Vector3(0, 3.0, 30), "06_wall_close")

	# 6. 远景
	await _shoot(fob_pos + Vector3(-260, 150, 300), fob_pos + Vector3(0, 0, 0), "05_wide")

	print("SHOTS_DONE ", out_dir)
	get_tree().quit()


func _shoot(pos: Vector3, look: Vector3, name: String) -> void:
	cam.global_position = pos
	cam.look_at(look, Vector3.UP)
	await get_tree().create_timer(0.45).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [out_dir, name]
	img.save_png(path)
	print("shot ", path, " ", img.get_width(), "x", img.get_height())
