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
var _vegetation_bases: Dictionary = {}
var _vegetation_batches: Array = []
var _worker: Thread
signal loading_progress(message: String, fraction: float)


func generate(seed_value: int = 20261019) -> void:
	_prepare_terrain(seed_value)
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


func _prepare_terrain(seed_value: int) -> void:
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

func generate_async(seed_value: int, extra_paths: Array = []) -> void:
	loading_progress.emit("预载模型与材质…", 0.05)
	var paths: Array = extra_paths.duplicate()
	for id in ["Grass001", "Ground109", "Rock030", "Ground054", "Asphalt012", "Fabric029", "WoodFloor051", "Concrete034", "Metal032"]:
		for map in (["ColorRoughness", "NormalGL"] if id in ["Grass001", "Ground109", "Rock030", "Ground054"] else ["Color", "NormalGL", "Roughness"]):
			paths.append(EnvironmentMaterials.ROOT + id + "/" + map + (".png" if map == "ColorRoughness" else ".jpg"))
	for entry in EnvironmentAssets.MODELS.values():
		for suffix in ["_near.gltf", "_far.gltf"]:
			paths.append(EnvironmentAssets.ROOT + entry[0] + suffix)
	await AssetLib.preload_paths(paths)
	_prepare_terrain(seed_value)
	var builder := POIBuilder.new()
	builder.name = "POIBuilder"
	add_child(builder)
	builder.setup(terrain, self)
	paths.clear()
	for poi in pois:
		for model in builder.required_models(poi):
			paths.append(AssetLib.model_path(model))
	loading_progress.emit("预载据点…", 0.2)
	await AssetLib.preload_paths(paths)
	terrain.build_mesh()
	terrain.build_collision()
	terrain.build_water()
	for i in pois.size():
		loading_progress.emit("建造" + str(pois[i]["name"]) + "…", 0.25 + i * 0.025)
		builder.build(pois[i])
		await get_tree().process_frame
	_prime_vegetation()
	loading_progress.emit("生成植被分布…", 0.5)
	# The worker only reads the fixed heightmap/POI layout and creates transform data.
	_worker = Thread.new()
	var chunks: Array
	if _worker.start(_vegetation_chunks) == OK:
		while _worker.is_alive():
			await get_tree().process_frame
		chunks = _worker.wait_to_finish()
	else:
		chunks = _vegetation_chunks()
	_worker = null
	_vegetation_batches.clear()
	_create_vegetation_root()
	var deadline := Time.get_ticks_usec() + 4000
	for i in chunks.size():
		EnvironmentAssets.create_chunk(_veg_root, chunks[i])
		chunks[i] = {}
		if Time.get_ticks_usec() >= deadline:
			loading_progress.emit("铺设植被…", 0.55 + 0.4 * float(i) / chunks.size())
			await get_tree().process_frame
			deadline = Time.get_ticks_usec() + 4000
	for poi in pois:
		if poi["faction"] == "opfor" and poi["type"] in ["outpost", "village", "airfield", "radar", "depot", "checkpoint"]:
			_make_outpost(poi)
	loading_progress.emit("世界已就绪", 1.0)


func _exit_tree() -> void:
	if _worker != null and _worker.is_started():
		_worker.wait_to_finish()


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
	e.ambient_light_energy = 0.65
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
	GameState.apply_graphics()


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
	o.owner_changed.connect(func(faction: String): poi["faction"] = faction)
	add_child(o)
	outposts.append(o)


# ---------------------------------------------------------------- 植被
func _create_vegetation_root() -> void:
	_veg_root = Node3D.new()
	_veg_root.name = "Vegetation"
	add_child(_veg_root)


func _prime_vegetation() -> void:
	for model in EnvironmentAssets.MODELS:
		_vegetation_bases[model] = EnvironmentAssets.mesh_data(model).get("transform", Transform3D.IDENTITY)
		EnvironmentAssets.mesh_data(model, true)


func _scatter_vegetation() -> void:
	_prime_vegetation()
	var chunks := _vegetation_chunks()
	_vegetation_batches.clear()
	_create_vegetation_root()
	for chunk in chunks:
		EnvironmentAssets.create_chunk(_veg_root, chunk)


func _vegetation_chunks() -> Array:
	_vegetation_batches.clear()
	var groups := [
		{"models": ["SM_Env_Tree_01", "SM_Env_Tree_02", "SM_Env_Tree_03", "SM_Env_Tree_Big_01",
			"SM_Env_Tree_Large_01", "SM_Env_Tree_Round_01"], "count": 1300, "min_h": 3.0, "max_h": 46.0, "max_slope": 0.45},
		{"models": ["SM_Env_Bush_Large_01", "SM_Env_Bush_Small_01", "SM_Env_Bush_Group_01",
			"SM_Env_Tree_Bush_01"], "count": 1700, "min_h": 2.0, "max_h": 50.0, "max_slope": 0.6},
		{"models": ["SM_Env_Rock_01", "SM_Env_Rock_02", "SM_Env_Rock_03", "SM_Env_Rock_04"],
			"count": 420, "min_h": 1.0, "max_h": 62.0, "max_slope": 1.0},
		{"models": ["SM_Env_Grass_01", "SM_Env_Grass_02", "SM_Env_Grass_03"],
			"count": 4500, "min_h": 3.0, "max_h": 44.0, "max_slope": 0.25},
		{"models": ["SM_Env_Flowers_01"],
			"count": 1400, "min_h": 3.0, "max_h": 34.0, "max_slope": 0.35},
	]

	for g in groups:
		var per_model := int(float(g["count"]) / float(g["models"].size()))
		for model in g["models"]:
			_make_multimesh(model, per_model, g["min_h"], g["max_h"], g["max_slope"])
	_scatter_meadows()
	return EnvironmentAssets.chunk_batches(_vegetation_batches)


func _scatter_meadows() -> void:
	var models := ["SM_Env_Grass_01", "SM_Env_Grass_02", "SM_Env_Grass_03"]
	var batches: Array = [[], [], []]
	var bases: Array[Transform3D] = []
	for model in models:
		bases.append(_vegetation_bases[model])
	var random := RandomNumberGenerator.new()
	random.seed = world_seed + 7331
	var planted := 0
	var patches := 0
	for attempt in 1200:
		if planted >= 90000 or patches >= 120:
			break
		var center := Vector2(random.randf_range(-690, 690), random.randf_range(-690, 690))
		if attempt < pois.size() * 2:
			var poi: Dictionary = pois[attempt / 2]
			var direction := Vector2(-0.85, 0.65) if attempt % 2 == 0 else Vector2(0.35, 1.0)
			center = poi["pos"] + direction.normalized() * (float(poi["radius"]) + 45.0)
		var height := terrain.height_at(center.x, center.y)
		if height < 3.5 or height > 44.0 or terrain.slope_at(center.x, center.y) > 0.16 or _near_poi(center, 0.95):
			continue
		patches += 1
		var radius := random.randf_range(18.0, 38.0)
		var aspect := random.randf_range(0.55, 1.0)
		var yaw := random.randf() * TAU
		var candidates := int(PI * radius * radius * aspect * 0.9)
		for blade in candidates:
			if planted >= 90000:
				break
			var distance := sqrt(random.randf())
			if random.randf() > 1.0 - smoothstep(0.45, 1.0, distance):
				continue
			var angle := random.randf() * TAU
			var offset := Vector2(cos(angle), sin(angle) * aspect).rotated(yaw) * distance * radius
			var point := center + offset
			var h := terrain.surface_height_at(point.x, point.y)
			if h < 3.0 or h > 46.0 or terrain.slope_at(point.x, point.y) > 0.25 or _near_poi(point, 0.92):
				continue
			var pick := random.randf()
			var index := 0 if pick < 0.3 else (1 if pick < 0.6 else 2)
			var width := random.randf_range(1.1, 1.6)
			var tall := random.randf_range(1.45, 2.0)
			var basis := Basis(Vector3.UP, random.randf() * TAU).scaled(Vector3(width, tall, width))
			batches[index].append(Transform3D(basis, Vector3(point.x, h - 0.025, point.y)) * bases[index])
			planted += 1
	for i in models.size():
		var transforms: Array[Transform3D] = []
		transforms.assign(batches[i])
		_vegetation_batches.append({"model": models[i], "transforms": transforms})


func _make_multimesh(model: String, count: int, min_h: float, max_h: float, max_slope: float) -> void:
	var base_xf: Transform3D = _vegetation_bases[model]
	var xforms: Array[Transform3D] = []
	var half := Terrain.SIZE * 0.5 - 30.0
	var guard := 0
	while xforms.size() < count and guard < count * 12:
		guard += 1
		var x := _rng.randf_range(-half, half)
		var z := _rng.randf_range(-half, half)
		var grass := model.contains("Grass") or model.contains("Flowers")
		var h := terrain.surface_height_at(x, z) if grass else terrain.height_at(x, z)
		if h < min_h or h > max_h:
			continue
		if terrain.slope_at(x, z) > max_slope:
			continue
		if _near_poi(Vector2(x, z), 0.92):
			continue
		var s := _rng.randf_range(1.2, 1.8) if grass else _rng.randf_range(0.85, 1.35)
		var b := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s, s))
		xforms.append(Transform3D(b, Vector3(x, h - (0.025 if grass else 0.15), z)) * base_xf)

	_vegetation_batches.append({"model": model, "transforms": xforms})


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
	var p: Vector2 = fob["pos"] + Vector2(0, 12)
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
