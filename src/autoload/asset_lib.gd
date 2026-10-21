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
const REALISTIC_CHARACTERS := ["SM_Chr_Soldier_Male_01", "SM_Chr_Soldier_Male_02",
	"SM_Chr_Leader_Male_01", "SM_Chr_Insurgent_Male_01", "SM_Chr_Insurgent_Male_02",
	"SM_Chr_Insurgent_Male_03", "SM_Chr_Ghillie_Male_01"]
const REALISTIC_WEAPONS := {
	"SM_Wep_Preset_A_Rifle_01": "BT_M4A1",
	"SM_Wep_Preset_A_Rifle_03": "BT_M4A1",
	"SM_Wep_Preset_B_Rifle_01": "BT_AK47",
	"SM_Wep_Preset_B_Rifle_02": "BT_AK47",
	"SM_Wep_Preset_B_Rifle_03": "BT_AK47",
	"SM_Wep_Rifle_01": "BT_AK47",
	"SM_Wep_Pistol_Metal_01": "BT_M1911",
	"SM_Wep_Preset_A_Rifle_02": "BT_Fitted_SM_Wep_Preset_A_Rifle_02",
	"SM_Wep_Preset_A_Complex_01": "BT_Fitted_SM_Wep_Preset_A_Complex_01",
	"SM_Wep_Preset_A_SMG_01": "BT_Fitted_SM_Wep_Preset_A_SMG_01",
	"SM_Wep_Preset_A_Heavy_01": "BT_Fitted_SM_Wep_Preset_A_Heavy_01",
	"SM_Wep_Preset_A_Sniper_01": "BT_Fitted_SM_Wep_Preset_A_Sniper_01",
	"SM_Wep_MachineGun_USA_01": "BT_Fitted_SM_Wep_MachineGun_USA_01",
	"SM_Wep_Pistol_01": "BT_Fitted_SM_Wep_Pistol_01",
	"SM_Wep_Shotgun_01": "BT_Fitted_SM_Wep_Shotgun_01",
	"SM_Wep_RocketLauncher_01": "BT_Fitted_SM_Wep_RocketLauncher_01",
	"SM_Wep_Preset_B_Complex_01": "BT_Fitted_SM_Wep_Preset_B_Complex_01",
	"SM_Wep_Preset_B_SMG_01": "BT_Fitted_SM_Wep_Preset_B_SMG_01",
	"SM_Wep_Preset_B_Heavy_01": "BT_Fitted_SM_Wep_Preset_B_Heavy_01",
	"SM_Wep_Preset_B_Sniper_01": "BT_Fitted_SM_Wep_Preset_B_Sniper_01",
	"SM_Wep_Sniper_01": "BT_Fitted_SM_Wep_Sniper_01",
	"SM_Wep_Pistol_Small_01": "BT_Fitted_SM_Wep_Pistol_Small_01",
	"SM_Wep_MachineGun_Bandit_01": "BT_Fitted_SM_Wep_MachineGun_Bandit_01",
	"SM_Wep_RPG_01": "BT_Fitted_SM_Wep_RPG_01",
}

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
	if model_name in REALISTIC_CHARACTERS:
		model_name = "BT_Operator"
	else:
		model_name = REALISTIC_WEAPONS.get(model_name, model_name)
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
func resolved_model(model_name: String) -> String:
	if model_name in REALISTIC_CHARACTERS or model_name == "BT_Operator":
		if meta.has("BT_Operator_LOD"):
			return "BT_Operator_LOD"
		return "BT_Operator_Batched" if meta.has("BT_Operator_Batched") else "BT_Operator"
	return str(REALISTIC_WEAPONS.get(model_name, model_name))


func model_path(model_name: String) -> String:
	var resolved := resolved_model(model_name)
	return "%s/%s/%s.glb" % [MODEL_ROOT, category_of(resolved), resolved]


func is_cached(model_name: String) -> bool:
	return _scenes.has(resolved_model(model_name))


func preload_paths(paths: Array) -> void:
	if DisplayServer.get_name() == "headless":
		# Dummy rendering cannot initialize some textures from background loaders.
		for path in paths:
			if not _scenes.has(path):
				_scenes[path] = load(path)
		await get_tree().process_frame
		return
	# Finish one scene before requesting another: GLBs share imported textures.
	for path in paths:
		if _scenes.has(path):
			continue
		var error := ResourceLoader.load_threaded_request(path)
		if error != OK and error != ERR_BUSY:
			push_error("Cannot preload: " + str(path))
			continue
		while ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			await get_tree().process_frame
		var resource := ResourceLoader.load_threaded_get(path)
		if resource != null:
			_scenes[path] = resource


func path_scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load(path)
	return _scenes[path]


func get_scene(model_name: String) -> PackedScene:
	var resolved := resolved_model(model_name)
	if resolved != model_name:
		return get_scene(resolved)
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
	var ps: PackedScene = path_scene(path)
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
	for mesh in inst.find_children("*", "GeometryInstance3D", true, false):
		match str(mesh.name):
			"BT_Operator_Close": mesh.visibility_range_end = 12
			"BT_Operator_Mid":
				mesh.visibility_range_begin = 12
				mesh.visibility_range_end = 40
			"BT_Operator_Far": mesh.visibility_range_begin = 40
			"BT_Glove_Close": mesh.visibility_range_end = 10
			"BT_Glove_Far": mesh.visibility_range_begin = 10
	if model_name in REALISTIC_CHARACTERS:
		var color := Color(1.25, 1.08, 0.82) if model_name == "SM_Chr_Soldier_Male_01" else Color(0.90, 1.12, 0.86)
		if model_name.begins_with("SM_Chr_Insurgent") or model_name == "SM_Chr_Leader_Male_01":
			color = Color(1.12, 0.88, 0.78)
		apply_tint(inst, color)
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
					if key == "BT_OperatorAtlas" and base is StandardMaterial3D:
						if not _materials.has(key):
							var atlas := ShaderMaterial.new()
							atlas.shader = preload("res://assets/shaders/operator_atlas.gdshader")
							atlas.set_shader_parameter("tint", Color.WHITE)
							atlas.set_shader_parameter("atlas_color", base.albedo_texture)
							atlas.set_shader_parameter("atlas_normal", base.normal_texture)
							atlas.set_shader_parameter("atlas_surface", base.metallic_texture)
							atlas.set_shader_parameter("atlas_emission", base.emission_texture)
							_materials[key] = atlas
						mi.set_surface_override_material(i, _materials[key])
						continue
					if key == "BT_OpticGlass" and base is BaseMaterial3D:
						base.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
						base.cull_mode = BaseMaterial3D.CULL_DISABLED
					var resolved := _resolve_key(key)
					if resolved != "":
						var material := material_for(resolved)
						# GLB 的瞄具玻璃与枪身共用图集，但必须保留原始透明度。
						if base is BaseMaterial3D and base.albedo_color.a < 1.0:
							var glass_key := "%s|alpha=%f" % [resolved, base.albedo_color.a]
							if not _materials.has(glass_key):
								var glass: StandardMaterial3D = material.duplicate()
								glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
								glass.albedo_color.a = base.albedo_color.a
								glass.cull_mode = base.cull_mode
								_materials[glass_key] = glass
							material = _materials[glass_key]
						mi.set_surface_override_material(i, material)
					# Original remodel assets carry their own compact PBR palette.
					elif key != "" and not key.begins_with("BT_"):
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
	_tinted.clear()


var _tinted: Dictionary = {}


func material_tinted(base: Material, color: Color) -> Material:
	var key := "%s|%s" % [base.get_instance_id(), color.to_html()]
	if not _tinted.has(key):
		var tinted: Material = base.duplicate()
		if tinted is BaseMaterial3D:
			tinted.albedo_color *= color
		elif tinted is ShaderMaterial:
			var value: Variant = tinted.get_shader_parameter("tint")
			var original: Color = value if value is Color else Color.WHITE
			tinted.set_shader_parameter("tint", original * color)
		_tinted[key] = tinted
	return _tinted[key]

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
					if base is BaseMaterial3D or (base is ShaderMaterial and base.shader == preload("res://assets/shaders/operator_atlas.gdshader")):
						mi.set_surface_override_material(i, material_tinted(base, color))
		for c in n.get_children():
			stack.append(c)
