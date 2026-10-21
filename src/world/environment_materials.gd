class_name EnvironmentMaterials
extends RefCounted
## Shared world-space detail materials; the source atlas and model UVs stay intact.

const ROOT := "res://assets/textures/environment/"
const DETAIL := preload("res://assets/shaders/environment_detail.gdshader")
const GROUND := preload("res://assets/shaders/terrain_surface.gdshader")
static var _cache: Dictionary = {}

static func terrain_material() -> ShaderMaterial:
	if not _cache.has("terrain"):
		var mat := ShaderMaterial.new()
		mat.shader = GROUND
		var layers := {"grass": "Grass001", "soil": "Ground109", "rock": "Rock030", "sand": "Ground054"}
		var maps := {"color": "ColorRoughness", "normal": "NormalGL"}
		for layer in layers:
			for kind in maps:
				mat.set_shader_parameter(layer + "_" + kind, load(ROOT + layers[layer] + "/" + maps[kind] + (".png" if kind == "color" else ".jpg")))
		_cache["terrain"] = mat
	return _cache["terrain"]

static func material_for(model: String, base: StandardMaterial3D) -> Material:
	if base == null or base.albedo_texture == null or base.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		return base
	var texture_id := ""
	var meters := 2.0
	if model.contains("Road") or model.contains("Runway") or model.contains("Helipad"):
		texture_id = "Asphalt012"
		meters = 4.0
	elif model.contains("Tent") or model.contains("Sandbag") or model.contains("Cloth") or model.contains("Sack"):
		texture_id = "Fabric029"
		meters = 0.6
	elif model.contains("Wood") or model.contains("Pallet"):
		texture_id = "WoodFloor051"
		meters = 1.8
	elif model.begins_with("SM_Bld_") and not model.contains("Tent"):
		texture_id = "Concrete034"
		meters = 1.8
	elif model.contains("Barrier_Concrete") or model.contains("Rubble"):
		texture_id = "Concrete034"
	elif model.begins_with("SM_Prop_") or model.begins_with("SM_Veh_"):
		texture_id = "Metal032"
		meters = 1.2
	if texture_id.is_empty():
		return base
	var key := "%s|%s|%s" % [texture_id, base.get_instance_id(), meters]
	if not _cache.has(key):
		var mat := ShaderMaterial.new()
		mat.shader = DETAIL
		mat.set_shader_parameter("atlas", base.albedo_texture)
		mat.set_shader_parameter("tint", base.albedo_color)
		mat.set_shader_parameter("detail_color", load(ROOT + texture_id + "/Color.jpg"))
		mat.set_shader_parameter("detail_normal", load(ROOT + texture_id + "/NormalGL.jpg"))
		mat.set_shader_parameter("detail_roughness", load(ROOT + texture_id + "/Roughness.jpg"))
		mat.set_shader_parameter("tile_meters", meters)
		_cache[key] = mat
	return _cache[key]

static func apply(root: Node, model: String) -> void:
	if root is MeshInstance3D:
		var mi := root as MeshInstance3D
		if mi.mesh != null:
			for i in mi.mesh.get_surface_count():
				var base := mi.get_active_material(i)
				if base is StandardMaterial3D:
					mi.set_surface_override_material(i, material_for(model, base))
	for child in root.get_children():
		apply(child, model)
