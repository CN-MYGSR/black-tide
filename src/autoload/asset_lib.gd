extends Node
## 素材库：加载转换后的 GLB、按名字挂共享材质、给出模型尺寸。
##
## 为什么材质要单独挂：
##   POLYGON 的 400+ 个模型共用同一张 2048 图集，如果每个 GLB 都内嵌贴图，
##   显存里会出现几百份同样的图集。所以 GLB 只带几何 + 材质名，
##   这里按材质名查表拿共享 StandardMaterial3D，一份贴图全场景共用。

const MODEL_ROOT := "res://assets/models"
const META_PATH := "res://assets/data/model_meta.json"
const MAT_PATH := "res://assets/data/material_map.json"
const TEX_ROOT := "res://assets/textures"

var meta: Dictionary = {}
var mat_defs: Dictionary = {}
var _scenes: Dictionary = {}
var _materials: Dictionary = {}
var _by_category: Dictionary = {}

var missing_models: Array[String] = []
var unresolved: Dictionary = {}   ## 材质名没对上表的，记下来便于排查


func _ready() -> void:
	_load_json()


func _load_json() -> void:
	var f := FileAccess.open(META_PATH, FileAccess.READ)
	if f != null:
		var d: Variant = JSON.parse_string(f.get_as_text())
		if typeof(d) == TYPE_DICTIONARY:
			meta = d
	var f2 := FileAccess.open(MAT_PATH, FileAccess.READ)
	if f2 != null:
		var d2: Variant = JSON.parse_string(f2.get_as_text())
		if typeof(d2) == TYPE_DICTIONARY:
			mat_defs = d2
	for name in meta.keys():
		var cat: String = meta[name].get("category", "misc")
		if not _by_category.has(cat):
			_by_category[cat] = []
		_by_category[cat].append(name)


# ---------------------------------------------------------------- 查询
func has_model(model_name: String) -> bool:
	return meta.has(model_name)


func category_of(model_name: String) -> String:
	return str(meta.get(model_name, {}).get("category", ""))


func size_of(model_name: String) -> Vector3:
	var s: Array = meta.get(model_name, {}).get("size", [1, 1, 1])
	return Vector3(float(s[0]), float(s[1]), float(s[2]))


func models_in(cat: String) -> Array:
	return _by_category.get(cat, [])


func pick(cat: String, prefixes: Array, index: int = -1) -> String:
	## 从某分类里按前缀筛，index 为 -1 时随机取一个
	var pool: Array = []
	for m in models_in(cat):
		for p in prefixes:
			if str(m).begins_with(p):
				pool.append(m)
				break
	if pool.is_empty():
		return ""
	if index < 0:
		return pool[randi() % pool.size()]
	return pool[index % pool.size()]


# ---------------------------------------------------------------- 加载
func get_scene(model_name: String) -> PackedScene:
	if _scenes.has(model_name):
		return _scenes[model_name]
	var cat := category_of(model_name)
	if cat == "":
		if not missing_models.has(model_name):
			missing_models.append(model_name)
		return null
	var path := "%s/%s/%s.glb" % [MODEL_ROOT, cat, model_name]
	if not ResourceLoader.exists(path):
		if not missing_models.has(model_name):
			missing_models.append(model_name)
		return null
	var ps: PackedScene = load(path)
	_scenes[model_name] = ps
	return ps


func spawn(model_name: String, parent: Node = null, pos: Vector3 = Vector3.ZERO,
		rot_y: float = 0.0, shadow: bool = true, collide: bool = false) -> Node3D:
	## 返回的是一层包装节点，而不是 GLB 根节点本身。
	## 因为 GLB 根节点带 0.01 缩放，碰撞体挂上去会被一起缩小 —— 必须挂在包装层上。
	var ps := get_scene(model_name)
	if ps == null:
		return null
	var root := Node3D.new()
	root.name = model_name
	var inst: Node3D = ps.instantiate()
	inst.name = "Model"
	root.add_child(inst)
	apply_materials(inst, shadow)
	if collide:
		_add_box_collision(root, model_name)
	if parent != null:
		parent.add_child(root)
	root.position = pos
	root.rotation.y = rot_y
	return root


func _add_box_collision(root: Node3D, model_name: String) -> void:
	var size := size_of(model_name)
	if size.x <= 0.0 or size.y <= 0.0 or size.z <= 0.0:
		return
	var body := StaticBody3D.new()
	body.name = "Hitbox"
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position = Vector3(0, size.y * 0.5, 0)
	body.add_child(cs)
	root.add_child(body)


func extract_mesh(model_name: String) -> ArrayMesh:
	## 取出模型里的第一个网格，供 MultiMesh 批量实例化用
	var d := extract_mesh_data(model_name)
	return d.get("mesh") if d.get("mesh") != null else null


func extract_mesh_data(model_name: String) -> Dictionary:
	## 返回 {mesh, transform}。
	## 关键：Synty 的 FBX 网格数据是厘米，缩放挂在 GLB 根节点上（0.01）。
	## 直接拿 mesh 塞进 MultiMesh 会丢掉这层缩放 —— 树会变成 400 米高。
	var ps := get_scene(model_name)
	if ps == null:
		return {"mesh": null, "transform": Transform3D.IDENTITY}
	var inst := ps.instantiate()
	var found_mesh: Mesh = null
	var found_xf := Transform3D.IDENTITY
	var stack: Array = [[inst, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var item: Array = stack.pop_back()
		var n: Node = item[0]
		var xf: Transform3D = item[1]
		if n is MeshInstance3D and found_mesh == null:
			found_mesh = (n as MeshInstance3D).mesh
			found_xf = xf
		for c in n.get_children():
			var local := (c as Node3D).transform if c is Node3D else Transform3D.IDENTITY
			stack.append([c, xf * local])
	inst.queue_free()
	return {"mesh": found_mesh, "transform": found_xf}


# ---------------------------------------------------------------- 材质
func material_for(mat_name: String) -> StandardMaterial3D:
	if _materials.has(mat_name):
		return _materials[mat_name]
	var def: Dictionary = mat_defs.get(mat_name, {})
	var mat := StandardMaterial3D.new()
	mat.resource_name = mat_name
	var tex_name: Variant = def.get("tex")
	var mode: String = str(def.get("mode", "opaque"))

	if tex_name != null and str(tex_name) != "":
		var tex_path := "%s/%s" % [TEX_ROOT, str(tex_name)]
		if ResourceLoader.exists(tex_path):
			mat.albedo_texture = load(tex_path)
			mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC

	mat.roughness = 0.86
	mat.metallic = 0.0
	match mode:
		"scissor":
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			mat.alpha_scissor_threshold = 0.5
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		"glass":
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color = Color(0.62, 0.72, 0.78, 0.28)
			mat.roughness = 0.08
			mat.metallic = 0.5
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_:
			mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED

	_materials[mat_name] = mat
	return mat


func apply_materials(root: Node, shadow: bool = true) -> void:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow \
				else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var mesh := mi.mesh
			if mesh != null:
				for i in mesh.get_surface_count():
					var base := mi.get_active_material(i)
					var key := ""
					if base != null:
						key = base.resource_name
						if key == "":
							key = base.name
					var resolved := _resolve_key(key)
					if resolved != "":
						mi.set_surface_override_material(i, material_for(resolved))
					elif key != "":
						unresolved[key] = int(unresolved.get(key, 0)) + 1
		for c in n.get_children():
			stack.append(c)


func _resolve_key(raw: String) -> String:
	## Blender 导出的材质重名会带 ".001" 后缀，这里做一次归一
	if mat_defs.has(raw):
		return raw
	var dot := raw.rfind(".")
	if dot > 0:
		var suffix := raw.substr(dot + 1)
		if suffix.is_valid_int():
			var base := raw.substr(0, dot)
			if mat_defs.has(base):
				return base
	return ""


func clear_cache() -> void:
	_scenes.clear()
	_materials.clear()

var _tinted: Dictionary = {}


func material_tinted(mat_name: String, color: Color) -> StandardMaterial3D:
	## 涂装：复制一份共享材质再乘颜色，不影响其他模型
	var key := "%s|%s" % [mat_name, color.to_html()]
	if _tinted.has(key):
		return _tinted[key]
	var base := material_for(mat_name)
	var m: StandardMaterial3D = base.duplicate()
	m.albedo_color = color
	_tinted[key] = m
	return m


func apply_tint(root: Node, color: Color) -> void:
	## 把整棵子树里的材质换成带色版本（color 为白色时等于原厂）
	if is_equal_approx(color.r, 1.0) and is_equal_approx(color.g, 1.0) and is_equal_approx(color.b, 1.0):
		return
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			var mesh := mi.mesh
			if mesh != null:
				for i in mesh.get_surface_count():
					var base := mi.get_active_material(i)
					var key := ""
					if base != null:
						key = base.resource_name
						if key == "":
							key = base.name
					var resolved := _resolve_key(key)
					if resolved != "":
						mi.set_surface_override_material(i, material_tinted(resolved, color))
		for c in n.get_children():
			stack.append(c)
