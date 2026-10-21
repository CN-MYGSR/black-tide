class_name EnvironmentAssets
extends RefCounted
## Optimized CC0 models, addressed through the existing map's model names.

const ROOT := "res://assets/models/environment_hd/"
const MODELS := {
	"SM_Env_Tree_01": ["island_tree_01/tree_a", 1.0],
	"SM_Env_Tree_02": ["island_tree_02/tree_b", 1.0],
	"SM_Env_Tree_03": ["island_tree_01/tree_a", 0.7],
	"SM_Env_Tree_Big_01": ["island_tree_02/tree_b", 1.35],
	"SM_Env_Tree_Large_01": ["island_tree_01/tree_a", 1.2],
	"SM_Env_Tree_Round_01": ["island_tree_02/tree_b", 0.85],
	"SM_Env_Tree_Bush_01": ["wild_rooibos_bush/bush_a", 1.1],
	"SM_Env_Bush_Large_01": ["wild_rooibos_bush/bush_a", 1.0],
	"SM_Env_Bush_Small_01": ["wild_rooibos_bush/bush_b", 0.85],
	"SM_Env_Bush_Group_01": ["wild_rooibos_bush/bush_b", 1.3],
	"SM_Env_Grass_01": ["grass_bermuda_01/grass_a", 1.0],
	"SM_Env_Grass_02": ["grass_bermuda_01/grass_b", 1.0],
	"SM_Env_Grass_03": ["grass_medium_01/grass_c", 1.0],
	"SM_Env_Flowers_01": ["fern_02/fern", 0.85],
	"SM_Env_Rock_01": ["rock_moss_set_01/rock_a", 1.0],
	"SM_Env_Rock_02": ["rock_moss_set_01/rock_b", 1.0],
	"SM_Env_Rock_03": ["rock_moss_set_01/rock_c", 1.0],
	"SM_Env_Rock_04": ["rock_09/rock_d", 1.0],
}
static var _meshes: Dictionary = {}

static func mesh_data(model: String, far: bool = false) -> Dictionary:
	if not MODELS.has(model):
		return AssetLib.extract_mesh_data(model)
	var entry: Array = MODELS[model]
	var path: String = ROOT + entry[0] + ("_far.gltf" if far else "_near.gltf")
	if not _meshes.has(path):
		var scene: PackedScene = AssetLib.path_scene(path)
		assert(scene != null, "Missing environment asset: " + path)
		var inst := scene.instantiate()
		var result := _find_mesh(inst, Transform3D.IDENTITY)
		inst.free()
		assert(result.has("mesh"), "Empty environment asset: " + path)
		if far and path.contains("island_tree_"):
			var mesh: Mesh = result["mesh"]
			for i in mesh.get_surface_count():
				var material: StandardMaterial3D = mesh.surface_get_material(i)
				material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_meshes[path] = result
	var data: Dictionary = _meshes[path].duplicate()
	data["transform"] = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * float(entry[1])), Vector3.ZERO) * data["transform"]
	return data

static func _find_mesh(node: Node, transform: Transform3D) -> Dictionary:
	if node is Node3D:
		transform *= (node as Node3D).transform
	if node is MeshInstance3D:
		var mesh: ArrayMesh = (node as MeshInstance3D).mesh.duplicate()
		for surface in mesh.get_surface_count():
			var base: StandardMaterial3D = (node as MeshInstance3D).get_active_material(surface)
			if base != null:
				var material: StandardMaterial3D = base.duplicate()
				if material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
					material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
					material.alpha_scissor_threshold = 0.4
				material.cull_mode = BaseMaterial3D.CULL_DISABLED
				material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
				mesh.surface_set_material(surface, material)
		return {"mesh": mesh, "transform": transform}
	for child in node.get_children():
		var found := _find_mesh(child, transform)
		if not found.is_empty():
			return found
	return {}

static func spawn(model: String, parent: Node, position: Vector3, yaw: float, shadow: bool, collide: bool) -> Node3D:
	if not MODELS.has(model):
		var original := AssetLib.spawn(model, parent, position, yaw, shadow, collide)
		if original != null:
			EnvironmentMaterials.apply(original, model)
		return original
	var data := mesh_data(model)
	var root := Node3D.new()
	root.name = model
	var mi := MeshInstance3D.new()
	mi.mesh = data["mesh"]
	mi.transform = data["transform"]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	parent.add_child(root)
	root.position = position
	root.rotation.y = yaw
	return root

static func scatter(parent: Node3D, model: String, transforms: Array[Transform3D]) -> void:
	for chunk in chunk_batches([{"model": model, "transforms": transforms}]):
		create_chunk(parent, chunk)


static func chunk_batches(batches: Array) -> Array:
	var cell := 64.0
	var chunks: Dictionary = {}
	for batch in batches:
		var model: String = batch["model"]
		var grass := model.contains("Grass") or model.contains("Flowers")
		var bush := model.contains("Bush")
		for far in [false, true]:
			var data := mesh_data(model, far)
			if data.get("mesh") == null:
				continue
			for xf in batch["transforms"]:
				var cell_id := Vector2i(floori(xf.origin.x / cell), floori(xf.origin.z / cell))
				var key := "%d|%s|%s|%s|%d|%d" % [data["mesh"].get_instance_id(), grass, bush, far, cell_id.x, cell_id.y]
				if not chunks.has(key):
					chunks[key] = {"model": model, "mesh": data["mesh"], "grass": grass, "bush": bush, "far": far,
						"center": Vector3((cell_id.x + 0.5) * cell, 0, (cell_id.y + 0.5) * cell), "transforms": []}
				chunks[key]["transforms"].append(xf)
	return chunks.values()


static func create_chunk(parent: Node3D, chunk: Dictionary) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = chunk["mesh"]
	mm.instance_count = chunk["transforms"].size()
	var center: Vector3 = chunk["center"]
	for i in mm.instance_count:
		var local: Transform3D = chunk["transforms"][i]
		local.origin -= center
		mm.set_instance_transform(i, local)
	var mi := MultiMeshInstance3D.new()
	mi.name = "MM_%s_%d_%d_%s" % [chunk["model"], int(center.x), int(center.z), "far" if chunk["far"] else "near"]
	mi.multimesh = mm
	mi.position = center
	var switch_distance := 40.0 if chunk["grass"] else (75.0 if chunk["bush"] else 110.0)
	mi.visibility_range_begin = switch_distance if chunk["far"] else 0.0
	mi.visibility_range_end = (200.0 if chunk["grass"] else (220.0 if chunk["bush"] else 650.0)) if chunk["far"] else switch_distance
	if chunk["grass"]:
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		mi.visibility_range_begin_margin = 7.0
		mi.visibility_range_end_margin = 12.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if chunk["grass"] or chunk["far"] else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi, true)
