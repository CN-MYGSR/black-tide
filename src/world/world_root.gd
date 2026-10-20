class_name WorldRoot
extends Node3D
## 世界总装：地形 -> 据点平台 -> 网格/碰撞 -> 据点建筑 -> 植被散布 -> 据点逻辑。
##
## 顺序不能乱：平台必须在 build_mesh 之前压好，否则建筑会和地形打架。

const ISLAND_RADIUS := 800.0

const POI_DEFS := [
	{"id": "fob", "type": "fob", "name": "铁砧前线基地", "angle": 100.0, "dist": 470.0, "radius": 55.0, "faction": "blufor"},
	{"id": "hill42", "type": "outpost", "name": "42 号高地", "angle": 32.0, "dist": 430.0, "radius": 40.0, "faction": "opfor"},
	{"id": "zarya", "type": "village", "name": "扎里亚村", "angle": 196.0, "dist": 390.0, "radius": 66.0, "faction": "opfor"},
	{"id": "kestrel", "type": "airfield", "name": "红隼机场", "angle": 302.0, "dist": 500.0, "radius": 100.0, "faction": "opfor"},
	{"id": "vertex", "type": "radar", "name": "顶点雷达站", "angle": 352.0, "dist": 300.0, "radius": 44.0, "faction": "opfor"},
	{"id": "depot", "type": "depot", "name": "油桶中转站", "angle": 236.0, "dist": 500.0, "radius": 52.0, "faction": "opfor"},
	{"id": "ridge", "type": "checkpoint", "name": "北岭检查站", "angle": 62.0, "dist": 250.0, "radius": 26.0, "faction": "opfor"},
	{"id": "mill", "type": "ruins", "name": "旧磨坊废墟", "angle": 150.0, "dist": 300.0, "radius": 36.0, "faction": "neutral"},
]

var terrain: Terrain
var pois: Array = []
var outposts: Array[Outpost] = []
var world_seed: int = 20261019
var sun: DirectionalLight3D
var env: WorldEnvironment

var _rng := RandomNumberGenerator.new()
var _veg_root: Node3D


func generate(seed_value: int = 20261019) -> void:
	world_seed = seed_value
	_rng.seed = seed_value

	_build_environment()

	terrain = Terrain.new()
	terrain.name = "Terrain"
	add_child(terrain)
	terrain.generate(world_seed)

	# 1) 先定据点位置并压平
	pois = _layout_pois()
	for poi in pois:
		var pos: Vector2 = poi["pos"]
		var r: float = poi["radius"]
		terrain.add_pad(pos, r * 0.85, 26.0)
		if poi["type"] == "airfield":
			for off in [-180.0, -95.0, 95.0, 180.0]:
				terrain.add_pad(pos + Vector2(0, off), 60.0, 34.0)

	# 2) 压平 -> 建网格 -> 建碰撞
	terrain.apply_pads()
	terrain.build_mesh()
	terrain.build_collision()
	terrain.build_water()

	# 3) 铺据点
	var builder := POIBuilder.new()
	builder.name = "POIBuilder"
	add_child(builder)
	builder.setup(terrain, self)
	for poi in pois:
		builder.build(poi)

	# 4) 植被 / 石头散布（MultiMesh，避免几千个节点）
	_scatter_vegetation()

	# 5) 据点争夺逻辑
	for poi in pois:
		if poi["faction"] == "opfor" and poi["type"] in ["outpost", "village", "airfield", "radar", "depot", "checkpoint"]:
			_make_outpost(poi)


func _build_environment() -> void:
	env = WorldEnvironment.new()
	env.name = "WorldEnv"
	env.add_to_group("world_env")
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.20, 0.30, 0.45)
	sky_mat.sky_horizon_color = Color(0.62, 0.62, 0.58)
	sky_mat.ground_bottom_color = Color(0.16, 0.15, 0.13)
	sky_mat.ground_horizon_color = Color(0.55, 0.54, 0.50)
	sky_mat.sun_angle_max = 18.0
	sky.sky_material = sky_mat
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.42
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 1.05
	e.ssao_enabled = true
	e.ssao_radius = 1.6
	e.ssao_intensity = 1.4
	e.glow_enabled = true
	e.glow_intensity = 0.35
	e.fog_enabled = true
	e.fog_light_color = Color(0.62, 0.66, 0.70)
	e.fog_density = 0.0007
	e.fog_aerial_perspective = 0.55
	env.environment = e
	add_child(env)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_energy = 1.55
	sun.light_color = Color(1.0, 0.93, 0.82)
	sun.rotation_degrees = Vector3(-42, 128, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 220.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	add_child(sun)


# ---------------------------------------------------------------- 据点选址
func _layout_pois() -> Array:
	var out: Array = []
	for i in POI_DEFS.size():
		var d: Dictionary = POI_DEFS[i].duplicate()
		var a := deg_to_rad(float(d["angle"]))
		var dist := float(d["dist"])
		var pos := Vector2(cos(a), sin(a)) * dist
		# 往岛心收，直到落在可用的陆地上
		for attempt in 8:
			var h := terrain.height_at(pos.x, pos.y)
			var slope := terrain.slope_at(pos.x, pos.y)
			if h > 4.0 and h < 46.0 and slope < 0.22:
				break
			pos = pos.lerp(Vector2.ZERO, 0.12)
		d["pos"] = pos
		d["seed"] = world_seed + i * 7919
		out.append(d)
	return out


func _make_outpost(poi: Dictionary) -> void:
	var o := Outpost.new()
	o.name = "Outpost_" + str(poi["id"])
	o.position = Vector3(poi["pos"].x, terrain.height_at(poi["pos"].x, poi["pos"].y), poi["pos"].y)
	o.setup(str(poi["id"]), str(poi["name"]), float(poi["radius"]) * 0.75, str(poi["faction"]))
	add_child(o)
	outposts.append(o)


# ---------------------------------------------------------------- 植被
func _scatter_vegetation() -> void:
	_veg_root = Node3D.new()
	_veg_root.name = "Vegetation"
	add_child(_veg_root)

	var groups := [
		{"models": ["SM_Env_Tree_01", "SM_Env_Tree_02", "SM_Env_Tree_03", "SM_Env_Tree_Big_01",
			"SM_Env_Tree_Large_01", "SM_Env_Tree_Round_01"], "count": 1300, "min_h": 3.0, "max_h": 46.0, "max_slope": 0.45},
		{"models": ["SM_Env_Bush_Large_01", "SM_Env_Bush_Small_01", "SM_Env_Bush_Group_01",
			"SM_Env_Tree_Bush_01"], "count": 1700, "min_h": 2.0, "max_h": 50.0, "max_slope": 0.6},
		{"models": ["SM_Env_Rock_01", "SM_Env_Rock_02", "SM_Env_Rock_03", "SM_Env_Rock_04"],
			"count": 420, "min_h": 1.0, "max_h": 62.0, "max_slope": 1.0},
		{"models": ["SM_Env_Grass_01", "SM_Env_Grass_02", "SM_Env_Grass_03", "SM_Env_Flowers_01"],
			"count": 1400, "min_h": 3.0, "max_h": 34.0, "max_slope": 0.35},
	]

	for g in groups:
		var per_model := int(float(g["count"]) / float(g["models"].size()))
		for model in g["models"]:
			_make_multimesh(model, per_model, g["min_h"], g["max_h"], g["max_slope"])


func _make_multimesh(model: String, count: int, min_h: float, max_h: float, max_slope: float) -> void:
	var data := AssetLib.extract_mesh_data(model)
	var mesh: Mesh = data.get("mesh")
	if mesh == null:
		return
	var base_xf: Transform3D = data.get("transform", Transform3D.IDENTITY)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	var xforms: Array[Transform3D] = []
	var half := Terrain.SIZE * 0.5 - 30.0
	var guard := 0
	while xforms.size() < count and guard < count * 12:
		guard += 1
		var x := _rng.randf_range(-half, half)
		var z := _rng.randf_range(-half, half)
		var h := terrain.height_at(x, z)
		if h < min_h or h > max_h:
			continue
		if terrain.slope_at(x, z) > max_slope:
			continue
		if _near_poi(Vector2(x, z), 0.92):
			continue
		var s := _rng.randf_range(0.85, 1.35)
		var b := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s, s))
		xforms.append(Transform3D(b, Vector3(x, h - 0.15, z)) * base_xf)

	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])

	var mmi := MultiMeshInstance3D.new()
	mmi.name = "MM_" + model
	mmi.multimesh = mm
	mmi.material_override = AssetLib.material_for("PolygonMilitary_Mat_01_A")
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_veg_root.add_child(mmi)


func _near_poi(p: Vector2, factor: float = 1.0) -> bool:
	for poi in pois:
		var r: float = float(poi["radius"]) * factor + 12.0
		if p.distance_to(poi["pos"]) < r:
			return true
	return false


# ---------------------------------------------------------------- 查询
func poi_by_id(id: String) -> Dictionary:
	for p in pois:
		if str(p["id"]) == id:
			return p
	return {}


func player_spawn_transform() -> Transform3D:
	var fob := poi_by_id("fob")
	var p: Vector2 = fob["pos"]
	return Transform3D(Basis.IDENTITY, Vector3(p.x, terrain.height_at(p.x, p.y) + 1.2, p.y))


func all_spawn_points(faction: String = "opfor") -> Array:
	var out: Array = []
	for poi in pois:
		if str(poi["faction"]) == faction:
			for sp in poi.get("spawn_points", []):
				out.append(sp)
	return out


func enemy_spawn_points() -> Array:
	var out: Array = []
	for poi in pois:
		if str(poi["faction"]) == "opfor":
			for sp in poi.get("spawn_points", []):
				out.append(sp)
	return out


func nearest_poi(pos: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var best_d := INF
	for p in pois:
		var d := Vector2(pos.x, pos.z).distance_to(p["pos"])
		if d < best_d:
			best_d = d
			best = p
	return best
