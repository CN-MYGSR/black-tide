class_name POIBuilder
extends Node
## 据点生成器：把转换好的 POLYGON 模型按"军事逻辑"摆成前哨站 / 村庄 / 机场 / 油库……
##
## 布局不是纯随机撒点 —— 每个据点先定中心与朝向，再按
## 外围防线 -> 主体建筑 -> 功能道具 -> 杂物 的顺序铺，
## 这样从空中看能一眼认出"这是个据点"，而不是一堆模型的集合。

var terrain: Terrain
var world: Node3D

var _center: Vector3 = Vector3.ZERO
var _rng := RandomNumberGenerator.new()
var _node: Node3D
var _spawns: Array[Vector3] = []
var _loot: Array[Vector3] = []
var _planning: bool = false
var _required: Dictionary = {}


func setup(p_terrain: Terrain, p_world: Node3D) -> void:
	terrain = p_terrain
	world = p_world


# ---------------------------------------------------------------- 入口
func build(poi: Dictionary) -> Dictionary:
	var pos: Vector2 = poi["pos"]
	_center = Vector3(pos.x, 0.0, pos.y)
	_center.y = terrain.height_at(_center.x, _center.z)
	_rng.seed = int(poi.get("seed", 12345))
	_spawns.clear()
	_loot.clear()

	_node = Node3D.new()
	_node.name = "POI_" + str(poi["id"])
	_node.position = _center
	if not _planning:
		world.add_child(_node)

	match str(poi["type"]):
		"fob":
			_build_fob()
		"outpost":
			_build_outpost()
		"village":
			_build_village()
		"airfield":
			_build_airfield()
		"radar":
			_build_radar()
		"depot":
			_build_depot()
		"checkpoint":
			_build_checkpoint()
		"ruins":
			_build_ruins()
		_:
			_build_outpost()

	poi["spawn_points"] = _spawns.duplicate()
	poi["loot_points"] = _loot.duplicate()
	poi["node"] = _node
	return poi


func required_models(poi: Dictionary) -> Array:
	_planning = true
	_required.clear()
	build(poi.duplicate())
	_node.free()
	_planning = false
	return _required.keys()


# ---------------------------------------------------------------- 基础摆放
func _needs_collision(model: String) -> bool:
	## 只有"能挡住人"的东西才加碰撞：建筑、载具、墙体、围栏、大箱子。
	## 小道具（锥桶、纸箱）不加，否则满地都是看不见的绊脚石。
	var cat := AssetLib.category_of(model)
	if cat == "buildings" or cat == "vehicles":
		return true
	for k in ["Barrier", "Fence", "Wall", "Crate_Stack", "Container", "Gastank",
			"Pipeline_Tank", "WaterTank", "Gate", "Locker", "Generator", "Helipad"]:
		if model.findn(k) >= 0:
			return true
	return false


func _put(model: String, local: Vector2, rot_deg: float = 0.0, y_off: float = 0.0,
		shadow: bool = true, scale: float = 1.0) -> Node3D:
	if model == "" or not AssetLib.has_model(model):
		return null
	if _planning:
		_required[model] = true
		return null
	var wp := _center + Vector3(local.x, 0.0, local.y)
	wp.y = terrain.height_at(wp.x, wp.z) + y_off
	# _node 本身已经放在 _center，这里必须转成局部坐标，否则会叠加两次偏移
	var lp := wp - _center
	var n := EnvironmentAssets.spawn(model, _node, lp, deg_to_rad(rot_deg), shadow, _needs_collision(model))
	if n != null and not is_equal_approx(scale, 1.0):
		n.scale = Vector3.ONE * scale
	return n


func _put_local(model: String, local: Vector3, rot_deg: float = 0.0, shadow: bool = true) -> Node3D:
	if model == "" or not AssetLib.has_model(model):
		return null
	if _planning:
		_required[model] = true
		return null
	var wp := _center + local
	wp.y = terrain.height_at(wp.x, wp.z) + local.y
	var n := EnvironmentAssets.spawn(model, _node, wp - _center, deg_to_rad(rot_deg), shadow, _needs_collision(model))
	return n


## ---------------------------------------------------------------- 墙 / 围栏
## 关键：不能凭感觉写朝向。每块墙体的长轴到底在 X 还是 Z，是模型自己决定的
## （Barrier_Tall_01 是 0.7 x 1.72 —— 长轴在 Z；Barrier_Base_Row_01 是 3.4 x 1.2 —— 长轴在 X）。
## 所以这里统一从 model_meta 读真实尺寸，自动算"段数 + 朝向"。
func _wall_orient(model: String) -> Dictionary:
	var size := AssetLib.size_of(model)
	var along_z := size.z >= size.x
	return {
		"length": maxf(size.x, size.z),
		"along_z": along_z,
	}


func _wall_place(from: Vector2, to: Vector2, model: String, gap: float = 1.0,
		y_off: float = 0.0, shadow: bool = true) -> int:
	var info := _wall_orient(model)
	var seg_len: float = maxf(0.3, float(info["length"]) * 0.98)
	var d := to - from
	var total := d.length()
	if total < 0.6:
		return 0
	var count := maxi(1, int(round(total / (seg_len * gap))))
	var step := d / float(count)
	var dir := d.normalized()
	# 长轴在 Z 的模型：绕 Y 转 atan2(dx, dz) 就能让 +Z 对准墙的方向
	# 长轴在 X 的模型：再减 90°
	var yaw := atan2(dir.x, dir.y)
	if not bool(info["along_z"]):
		yaw -= PI * 0.5
	for i in count:
		var p := from + step * (float(i) + 0.5)
		_put(model, p, rad_to_deg(yaw), y_off, shadow)
	return count


## 矩形围墙（四边首尾相接，转角用重叠补齐）
func _wall_rect(half: Vector2, model: String, gap: float = 1.0) -> int:
	var n := 0
	n += _wall_place(Vector2(-half.x, -half.y), Vector2(half.x, -half.y), model, gap)
	n += _wall_place(Vector2(half.x, -half.y), Vector2(half.x, half.y), model, gap)
	n += _wall_place(Vector2(half.x, half.y), Vector2(-half.x, half.y), model, gap)
	n += _wall_place(Vector2(-half.x, half.y), Vector2(-half.x, -half.y), model, gap)
	return n


## 圆形围墙：按弧长算段数，每段沿切线方向
func _wall_ring(radius: float, model: String, gap: float = 1.0, y_off: float = 0.0) -> int:
	var info := _wall_orient(model)
	var seg_len: float = maxf(0.3, float(info["length"]) * 0.98)
	var circ := TAU * radius
	var count := maxi(6, int(round(circ / (seg_len * gap))))
	var n := 0
	for i in count:
		var a0 := TAU * float(i) / float(count)
		var a1 := TAU * float(i + 1) / float(count)
		var p0 := Vector2(cos(a0), sin(a0)) * radius
		var p1 := Vector2(cos(a1), sin(a1)) * radius
		var mid := (p0 + p1) * 0.5
		var dir := (p1 - p0).normalized()
		var yaw := atan2(dir.x, dir.y)
		if not bool(info["along_z"]):
			yaw -= PI * 0.5
		_put(model, mid, rad_to_deg(yaw), y_off)
		n += 1
	return n


func _scatter(models: Array, count: int, radius: float, min_r: float = 2.0,
		shadow: bool = false, y_off: float = 0.0) -> void:
	for i in count:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(min_r, radius)
		var p := Vector2(cos(a), sin(a)) * r
		var m: String = models[_rng.randi() % models.size()]
		_put(m, p, _rng.randf() * 360.0, y_off, shadow)


func _clutter(count: int, radius: float, pool: Array = []) -> void:
	## 成组地撒杂物：一堆箱子、一堆桶，比均匀随机更像有人住过
	if pool.is_empty():
		pool = ["SM_Prop_Crate_Wood_01", "SM_Prop_Crate_Plastic_01", "SM_Prop_Barrel_01",
			"SM_Prop_Barrel_02", "SM_Prop_Pallet_01", "SM_Prop_Tire_01", "SM_Prop_Cone_01",
			"SM_Prop_CardboardBox_01", "SM_Prop_Sack_01", "SM_Prop_AmmoBox_02"]
	for c in count:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(6.0, radius)
		var center := Vector2(cos(a), sin(a)) * r
		var n := _rng.randi_range(2, 4)
		for i in n:
			var off := Vector2(_rng.randf_range(-1.8, 1.8), _rng.randf_range(-1.8, 1.8))
			var m: String = pool[_rng.randi() % pool.size()]
			_put(m, center + off, _rng.randf() * 360.0, 0.0, false)


func _spawn_point(local: Vector2) -> void:
	var p := _center + Vector3(local.x, 0.0, local.y)
	p.y = terrain.height_at(p.x, p.z) + 0.2
	_spawns.append(p)


func _loot_point(local: Vector2) -> void:
	var p := _center + Vector3(local.x, 0.0, local.y)
	p.y = terrain.height_at(p.x, p.z) + 0.2
	_loot.append(p)


# ---------------------------------------------------------------- FOB 前线基地
func _build_fob() -> void:
	_put("SM_Env_Helipad_01", Vector2(0, 0), 0.0, 0.05)

	_put("SM_Bld_Tent_01", Vector2(-18, -14), 90.0)
	_put("SM_Bld_Tent_01", Vector2(-18, -6), 90.0)
	_put("SM_Bld_Barracks_01", Vector2(16, -18), 180.0)
	_put("SM_Bld_Tent_Medical_01" if AssetLib.has_model("SM_Bld_Tent_Medical_01") else "SM_Bld_Tent_02",
		Vector2(18, 8), 270.0)
	_put("SM_Bld_Barracks_01", Vector2(-22, 14), 0.0)

	for corner in [Vector2(-30, -30), Vector2(30, -30), Vector2(-30, 30), Vector2(30, 30)]:
		_put("SM_Bld_GuardTower_01", corner, 0.0)

	# 围墙必须留门：南侧 (z=+34) 中间空出 14 米，否则玩家被自己人关在基地里
	_wall_place(Vector2(-34, -34), Vector2(34, -34), "SM_Prop_Barrier_Tall_Group_01")
	_wall_place(Vector2(-34, 34), Vector2(-7, 34), "SM_Prop_Barrier_Tall_Group_01")
	_wall_place(Vector2(7, 34), Vector2(34, 34), "SM_Prop_Barrier_Tall_Group_01")
	_wall_place(Vector2(-34, -34), Vector2(-34, 34), "SM_Prop_Barrier_Tall_Group_01")
	_wall_place(Vector2(34, -34), Vector2(34, 34), "SM_Prop_Barrier_Tall_Group_01")
	# 门柱 + 门前的拒马，明确"这里是出口"
	_put("SM_Prop_Barrier_Tall_01", Vector2(-7.6, 34), 90.0)
	_put("SM_Prop_Barrier_Tall_01", Vector2(7.6, 34), 90.0)
	_put("SM_Prop_Barrier_Base_Row_01", Vector2(-4.2, 33.0), 0.0)
	_put("SM_Prop_Barrier_Base_Row_01", Vector2(4.2, 33.0), 0.0)

	# 指挥区
	_put("SM_Prop_Briefing_Board_01", Vector2(-14, -22), 90.0)
	_put("SM_Prop_Gunlocker_01", Vector2(-10, -20), 0.0)
	_put("SM_Prop_Gunrack_01", Vector2(-8, -20), 0.0)
	_put("SM_Prop_MedicalBox_01", Vector2(20, 4), 0.0)
	_put("SM_Prop_Medic_IV_01", Vector2(21, 2), 0.0)
	_put("SM_Prop_Bed_Medical_01", Vector2(22, 6), 0.0)

	# 补给
	for i in 4:
		_put("SM_Prop_Crate_Ammo_01", Vector2(10 + i * 1.4, -10), _rng.randf_range(-20, 20))
		_put("SM_Prop_AmmoBox_0%d" % (1 + i % 4), Vector2(10 + i * 1.4, -8.5), 0.0)
	_put("SM_Prop_Fuel_Bladder_01", Vector2(-26, -2), 0.0)
	_put("SM_Prop_Fuel_Bladder_02", Vector2(-26, 3), 0.0)
	_put("SM_Prop_Generator_Large_01", Vector2(-26, -8), 0.0)

	# 车辆
	_put("SM_Veh_Truck_01", Vector2(6, 22), 15.0)
	_put("SM_Veh_SUV_01", Vector2(-2, 24), -10.0)
	_put("SM_Veh_Pickup_Technical_01", Vector2(14, 24), 5.0)

	for p in [Vector2(-12, 12), Vector2(12, 12), Vector2(-12, -12), Vector2(12, -12)]:
		_put("SM_Prop_LightPole_01", p, 0.0)

	_scatter(["SM_Prop_Barrel_01", "SM_Prop_Barrel_02", "SM_Prop_Crate_Wood_01",
		"SM_Prop_Pallet_01", "SM_Prop_Cone_01"], 14, 30.0, 10.0)

	_clutter(9, 26.0)
	_spawn_point(Vector2(0, 12))
	_spawn_point(Vector2(-6, 12))
	_spawn_point(Vector2(6, 12))
	_loot_point(Vector2(10, -10))
	_loot_point(Vector2(-24, 0))


# ---------------------------------------------------------------- 敌方前哨
func _build_outpost() -> void:
	_put("SM_Bld_Barracks_01", Vector2(0, 0), _rng.randf_range(0, 360))
	_put("SM_Bld_GuardTower_01", Vector2(-20, -18), 45.0)
	_put("SM_Bld_GuardTower_02", Vector2(20, 18), 225.0)
	_put("SM_Bld_GuardTower_01", Vector2(20, -18), 135.0)
	_put("SM_Bld_Tent_02", Vector2(-14, 12), 30.0)
	_put("SM_Bld_Tent_Sandbags_01", Vector2(14, 12), 210.0)

	_wall_ring(24.0, "SM_Prop_Barrier_Base_Row_01")

	_put("SM_Prop_Radio_01", Vector2(-4, -8), 0.0)
	_put("SM_Prop_Crate_Ammo_01", Vector2(4, -8), 0.0)
	_put("SM_Prop_Crate_Ammo_02", Vector2(6, -8), 90.0)
	_put("SM_Prop_AmmoBox_01", Vector2(3, -10), 0.0)
	_put("SM_Prop_Mortar_Shell_01", Vector2(8, -10), 0.0)
	_put("SM_Prop_Missle_Crate_01", Vector2(-8, 8), 0.0)
	_put("SM_Prop_LightPole_02", Vector2(0, 14), 0.0)
	_put("SM_Prop_Generator_Small_01", Vector2(-10, -4), 0.0)

	_put("SM_Veh_Truck_01_Destroyed", Vector2(34, -6), 40.0)
	_scatter(["SM_Prop_Barrel_03", "SM_Prop_Sack_01", "SM_Prop_Rubble_Pile_01",
		"SM_Prop_DebrisPile_01"], 10, 22.0, 8.0)

	_clutter(7, 20.0)
	_spawn_point(Vector2(-12, -10))
	_spawn_point(Vector2(12, -10))
	_spawn_point(Vector2(0, 10))
	_spawn_point(Vector2(-16, 6))
	_loot_point(Vector2(4, -8))
	_loot_point(Vector2(-4, -8))


# ---------------------------------------------------------------- 村庄
func _build_village() -> void:
	var houses := ["SM_Bld_Village_House_01", "SM_Bld_Village_House_02", "SM_Bld_Village_House_03",
		"SM_Bld_Village_House_04", "SM_Bld_Village_House_05", "SM_Bld_Village_House_06",
		"SM_Bld_Village_House_07"]
	var used: Array[Vector2] = []
	var placed := 0
	var guard := 0
	while placed < 14 and guard < 200:
		guard += 1
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(14.0, 52.0)
		var p := Vector2(cos(a), sin(a)) * r
		var ok := true
		for u in used:
			if u.distance_to(p) < 16.0:
				ok = false
				break
		if not ok:
			continue
		used.append(p)
		var model: String = houses[_rng.randi() % houses.size()]
		var rot := _rng.randf_range(-20.0, 20.0) + (rad_to_deg(a) if _rng.randf() < 0.7 else 0.0)
		_put(model, p, rot)
		if _rng.randf() < 0.22:
			_put("SM_Bld_Village_House_0%d_Destroyed" % _rng.randi_range(1, 7), p + Vector2(9, 4), rot + 12.0)
		placed += 1

	_put("SM_Bld_Village_Well_01", Vector2(0, 0), 0.0)
	_put("SM_Bld_Village_Archway_01", Vector2(0, -18), 0.0)
	_put("SM_Bld_Village_Archway_Pillar_01", Vector2(-5, -18), 0.0)
	_put("SM_Bld_Village_Archway_Pillar_01", Vector2(5, -18), 0.0)
	_put("SM_Prop_Cart_Stall_01", Vector2(8, 4), 20.0)
	_put("SM_Prop_Makeshift_Table_01", Vector2(-7, 5), -30.0)
	_put("SM_Prop_Chair_01", Vector2(-8, 7), 0.0)

	# 村子不围死：四个方向各留一段院墙，中间是村口
	_wall_place(Vector2(-58, -58), Vector2(-12, -58), "SM_Prop_Fence_01")
	_wall_place(Vector2(12, -58), Vector2(58, -58), "SM_Prop_Fence_01")
	_wall_place(Vector2(-58, 58), Vector2(-18, 58), "SM_Prop_Fence_01")
	_wall_place(Vector2(18, 58), Vector2(58, 58), "SM_Prop_Fence_01")
	_wall_place(Vector2(-58, -58), Vector2(-58, -14), "SM_Prop_Fence_01")
	_wall_place(Vector2(-58, 14), Vector2(-58, 58), "SM_Prop_Fence_01")
	_wall_place(Vector2(58, -58), Vector2(58, -14), "SM_Prop_Fence_01")
	_wall_place(Vector2(58, 14), Vector2(58, 58), "SM_Prop_Fence_01")

	_scatter(["SM_Env_Tree_01", "SM_Env_Tree_03", "SM_Env_Tree_Bush_01", "SM_Env_Bush_Large_01"], 26, 62.0, 20.0, true)
	_scatter(["SM_Prop_Rubble_Pile_02", "SM_Prop_DebrisPile_02", "SM_Prop_Barrel_02"], 12, 45.0, 10.0)

	_clutter(8, 45.0, ["SM_Prop_Crate_Wood_01", "SM_Prop_Barrel_02", "SM_Prop_CardboardBox_01",
		"SM_Prop_Sack_01", "SM_Prop_Basket_01", "SM_Prop_Chair_01", "SM_Prop_Pot_01"])
	for i in 4:
		_spawn_point(Vector2(cos(i * 1.7) * 18.0, sin(i * 1.7) * 18.0))
	_loot_point(Vector2(8, 4))
	_loot_point(Vector2(-7, 5))


# ---------------------------------------------------------------- 机场
func _build_airfield() -> void:
	_put("SM_Env_Runway_01", Vector2(0, 0), 0.0, 0.02)
	_put("SM_Env_Runway_01", Vector2(0, 90), 0.0, 0.02)
	_put("SM_Env_Runway_01", Vector2(0, -90), 0.0, 0.02)

	_put("SM_Bld_Hangar_Open_01", Vector2(-46, 20), 90.0)
	_put("SM_Bld_Hangar_01", Vector2(-46, -30), 90.0)
	_put("SM_Bld_ControlTower_01", Vector2(38, 46), 200.0)
	_put("SM_Bld_Barracks_01", Vector2(42, -40), 90.0)

	_put("SM_Veh_Jet_01", Vector2(-40, 18), 90.0)
	_put("SM_Veh_Jet_02", Vector2(-40, -34), 90.0)
	_put("SM_Veh_TransportPlane_01", Vector2(0, 110), 0.0)

	for i in 8:
		_put("SM_Prop_Runway_Light_01", Vector2(-14, -110 + i * 30), 0.0, 0.0, false)
		_put("SM_Prop_Runway_Light_01", Vector2(14, -110 + i * 30), 0.0, 0.0, false)

	_put("SM_Prop_Gastank_01", Vector2(50, 6), 0.0)
	_put("SM_Prop_Gastank_01", Vector2(58, 6), 0.0)
	_put("SM_Veh_Truck_01_Tanker", Vector2(30, 10), 90.0)
	_put("SM_Prop_Generator_Large_01", Vector2(46, -10), 0.0)
	_put("SM_Prop_LightPole_01", Vector2(-20, -60), 0.0)
	_put("SM_Prop_LightPole_01", Vector2(-20, 60), 0.0)

	_wall_place(Vector2(-72, 72), Vector2(72, 72), "SM_Prop_Fence_02", 1.0, 0.0, false)
	_wall_place(Vector2(-72, -72), Vector2(72, -72), "SM_Prop_Fence_02", 1.0, 0.0, false)

	_scatter(["SM_Prop_Barrel_01", "SM_Prop_Crate_Plastic_01", "SM_Prop_Cone_01"], 16, 60.0, 20.0)
	_clutter(8, 55.0)
	_spawn_point(Vector2(0, 40))
	_spawn_point(Vector2(0, -40))
	_spawn_point(Vector2(40, 30))
	_spawn_point(Vector2(-30, 40))
	_loot_point(Vector2(-44, 20))
	_loot_point(Vector2(40, 44))


# ---------------------------------------------------------------- 雷达站
func _build_radar() -> void:
	_put("SM_Bld_ControlTower_01", Vector2(0, 0), 0.0)
	_put("SM_Prop_Satelite_Dish_02", Vector2(-18, 6), 30.0)
	_put("SM_Prop_Mobile_Radar_01", Vector2(16, 12), 120.0)
	_put("SM_Prop_Aerial_01", Vector2(6, -14), 0.0)
	_put("SM_Prop_Generator_Large_01", Vector2(12, -6), 0.0)
	_put("SM_Prop_Generator_Small_01", Vector2(14, -8), 0.0)
	_put("SM_Bld_Barracks_01", Vector2(-2, 26), 180.0)
	_put("SM_Bld_Tent_03", Vector2(20, -18), 0.0)

	_wall_ring(30.0, "SM_Prop_Fence_03", 1.02)
	_put("SM_Prop_LightPole_01", Vector2(-14, -14), 0.0)
	_put("SM_Prop_LightPole_01", Vector2(14, 20), 0.0)

	_scatter(["SM_Prop_Barrel_01", "SM_Prop_Crate_Plastic_02", "SM_Prop_Cable_01"], 10, 24.0, 8.0)
	_clutter(5, 22.0)
	_spawn_point(Vector2(-8, -8))
	_spawn_point(Vector2(8, -8))
	_spawn_point(Vector2(0, 14))
	_loot_point(Vector2(12, -6))


# ---------------------------------------------------------------- 油库
func _build_depot() -> void:
	for i in 3:
		_put("SM_Prop_Pipeline_Tank_01", Vector2(-18 + i * 16.0, 0), 0.0)
		_put("SM_Prop_Gastank_01", Vector2(-18 + i * 16.0, 16), 0.0)
	_put("SM_Prop_Pipeline_SmokeStack_01", Vector2(-34, -12), 0.0)
	_put("SM_Prop_Pipeline_Pipe_Large_01", Vector2(0, -8), 0.0)
	_put("SM_Prop_Pipeline_Pipe_Large_02", Vector2(0, 8), 0.0)
	_put("SM_Prop_Pipeline_Pipe_Large_Support_01", Vector2(-8, 0), 0.0)
	_put("SM_Prop_Pipeline_Pipe_Large_Support_01", Vector2(8, 0), 0.0)
	_put("SM_Bld_GasStation_01", Vector2(24, -20), 90.0)
	_put("SM_Veh_Truck_01_Tanker", Vector2(20, 10), 90.0)
	_put("SM_Veh_Truck_01", Vector2(28, 14), 100.0)

	for i in 14:
		_put("SM_Prop_Barrel_0%d" % (1 + i % 3), Vector2(_rng.randf_range(-30, 30), _rng.randf_range(-30, 30)),
			_rng.randf() * 360.0, 0.0, false)

	_wall_ring(38.0, "SM_Prop_Fence_01", 1.02)
	_put("SM_Prop_LightPole_01", Vector2(-10, -20), 0.0)
	_put("SM_Prop_LightPole_01", Vector2(10, 20), 0.0)

	_clutter(6, 30.0, ["SM_Prop_Barrel_01", "SM_Prop_Barrel_03", "SM_Prop_Pallet_01",
		"SM_Prop_Crate_Plastic_03", "SM_Prop_Cone_01"])
	_spawn_point(Vector2(-6, -16))
	_spawn_point(Vector2(10, -16))
	_spawn_point(Vector2(2, 20))
	_loot_point(Vector2(24, -20))


# ---------------------------------------------------------------- 检查站
func _build_checkpoint() -> void:
	_put("SM_Bld_Archway_01", Vector2(0, 0), 0.0)
	_put("SM_Bld_GuardTower_01", Vector2(-14, 6), 45.0)
	_put("SM_Prop_Barrier_Tall_02", Vector2(-4, -2), 0.0)
	_put("SM_Prop_Barrier_Tall_03", Vector2(4, -2), 0.0)
	_put("SM_Prop_Barrier_Base_Row_01", Vector2(0, 4), 0.0)
	_put("SM_Prop_Cone_01", Vector2(-2, -6), 0.0)
	_put("SM_Prop_Cone_01", Vector2(3, -6), 0.0)
	_put("SM_Prop_Sign_Safety_01", Vector2(-8, -4), 0.0)
	_put("SM_Bld_Tent_04", Vector2(12, 10), 200.0)
	_put("SM_Veh_Light_Armored_Car_01", Vector2(14, -4), 90.0)
	_put("SM_Prop_Crate_Ammo_01", Vector2(-10, 10), 0.0)
	_clutter(4, 14.0)
	_spawn_point(Vector2(-6, 8))
	_spawn_point(Vector2(6, 8))
	_loot_point(Vector2(-10, 10))


# ---------------------------------------------------------------- 废墟
func _build_ruins() -> void:
	_put("SM_Bld_Ruins_01", Vector2(-8, 0), 20.0)
	_put("SM_Bld_Ruins_03", Vector2(12, 8), -40.0)
	_put("SM_Bld_Destroyed_01", Vector2(4, -14), 10.0)
	_put("SM_Bld_Village_House_02_Destroyed", Vector2(-16, -12), 70.0)
	_put("SM_Veh_APC_01_Destroyed", Vector2(18, -6), 30.0)
	_put("SM_Veh_Car_Small_Destroyed_01", Vector2(-4, 14), 0.0)
	_put("SM_Env_Crater_01", Vector2(0, 6), 0.0, 0.05)
	_put("SM_Env_Crater_01", Vector2(-14, 6), 40.0, 0.05)
	_put("SM_Prop_BloodPool_02", Vector2(2, 2), 0.0, 0.02, false)
	_scatter(["SM_Prop_Rubble_Pile_01", "SM_Prop_Rubble_Pile_03", "SM_Prop_DebrisPile_03",
		"SM_Prop_DebrisPile_04"], 18, 26.0, 4.0)
	_scatter(["SM_Env_Rock_01", "SM_Env_Rock_02", "SM_Env_Bush_Small_01"], 10, 28.0, 6.0, true)
	_spawn_point(Vector2(-10, 6))
	_spawn_point(Vector2(10, 2))
	_loot_point(Vector2(-8, 0))
