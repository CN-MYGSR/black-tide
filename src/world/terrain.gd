class_name Terrain
extends Node3D
## 程序化地形：噪声高度图 + 据点平台整平 + 平面着色低模网格 + HeightMapShape3D 碰撞。
##
## 关键点：先出高度图，再把据点周围"压平"成平台，最后才生成网格和碰撞。
## 这样建筑不会浮空，也不用运行时做射线找地面。

const SIZE := 1600.0          ## 世界边长（米）
const RES := 193              ## 高度图采样点数（RES-1 个格子）
const WATER_LEVEL := 0.0
const MAX_HEIGHT := 62.0

var heights: PackedFloat32Array
var pads: Array = []          ## [{pos: Vector2, radius: float, falloff: float, height: float}]
var mesh_instance: MeshInstance3D
var body: StaticBody3D
var rng := RandomNumberGenerator.new()


func generate(world_seed: int) -> void:
	rng.seed = world_seed
	heights.resize(RES * RES)

	var base := FastNoiseLite.new()
	base.seed = world_seed
	base.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	base.frequency = 0.0026
	base.fractal_type = FastNoiseLite.FRACTAL_FBM
	base.fractal_octaves = 5
	base.fractal_gain = 0.5

	var ridge := FastNoiseLite.new()
	ridge.seed = world_seed + 991
	ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX
	ridge.frequency = 0.006
	ridge.fractal_octaves = 3

	var detail := FastNoiseLite.new()
	detail.seed = world_seed + 17
	detail.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	detail.frequency = 0.02
	detail.fractal_octaves = 2

	var half := SIZE * 0.5
	for z in RES:
		for x in RES:
			var wx := -half + float(x) / float(RES - 1) * SIZE
			var wz := -half + float(z) / float(RES - 1) * SIZE
			var d := Vector2(wx, wz).length() / half
			# 岛屿轮廓：中间高、外圈沉到水下
			var island := clampf(1.0 - pow(d, 2.6), 0.0, 1.0)
			var h := (base.get_noise_2d(wx, wz) * 0.5 + 0.5)
			h = pow(h, 1.25) * MAX_HEIGHT
			h += ridge.get_noise_2d(wx, wz) * 8.0 * island
			h += detail.get_noise_2d(wx, wz) * 1.2
			h *= island
			h -= (1.0 - island) * 14.0
			heights[z * RES + x] = h


func add_pad(pos: Vector2, radius: float, falloff: float = 18.0, height: float = NAN) -> float:
	## 注册一块平台。height 传 NAN 表示"用中心点当前高度"
	var h := height
	if is_nan(h):
		h = height_at(pos.x, pos.y)
	pads.append({"pos": pos, "radius": radius, "falloff": falloff, "height": h})
	return h


func apply_pads() -> void:
	for pad in pads:
		var c: Vector2 = pad["pos"]
		var r: float = pad["radius"]
		var fo: float = pad["falloff"]
		var target: float = pad["height"]
		var outer := r + fo
		var x0 := clampi(int((c.x - outer + SIZE * 0.5) / SIZE * (RES - 1)) - 1, 0, RES - 1)
		var x1 := clampi(int((c.x + outer + SIZE * 0.5) / SIZE * (RES - 1)) + 1, 0, RES - 1)
		var z0 := clampi(int((c.y - outer + SIZE * 0.5) / SIZE * (RES - 1)) - 1, 0, RES - 1)
		var z1 := clampi(int((c.y + outer + SIZE * 0.5) / SIZE * (RES - 1)) + 1, 0, RES - 1)
		for z in range(z0, z1 + 1):
			for x in range(x0, x1 + 1):
				var wx := -SIZE * 0.5 + float(x) / float(RES - 1) * SIZE
				var wz := -SIZE * 0.5 + float(z) / float(RES - 1) * SIZE
				var dist := Vector2(wx, wz).distance_to(c)
				if dist > outer:
					continue
				var t := 1.0
				if dist > r:
					t = 1.0 - smoothstep(r, outer, dist)
				var idx := z * RES + x
				heights[idx] = lerpf(heights[idx], target, t)


func height_at(wx: float, wz: float) -> float:
	var fx := (wx + SIZE * 0.5) / SIZE * float(RES - 1)
	var fz := (wz + SIZE * 0.5) / SIZE * float(RES - 1)
	fx = clampf(fx, 0.0, float(RES - 2))
	fz = clampf(fz, 0.0, float(RES - 2))
	var x0 := int(fx)
	var z0 := int(fz)
	var tx := fx - float(x0)
	var tz := fz - float(z0)
	var h00 := heights[z0 * RES + x0]
	var h10 := heights[z0 * RES + x0 + 1]
	var h01 := heights[(z0 + 1) * RES + x0]
	var h11 := heights[(z0 + 1) * RES + x0 + 1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


func normal_at(wx: float, wz: float) -> Vector3:
	var e := 3.0
	var hl := height_at(wx - e, wz)
	var hr := height_at(wx + e, wz)
	var hd := height_at(wx, wz - e)
	var hu := height_at(wx, wz + e)
	return Vector3(hl - hr, 2.0 * e, hd - hu).normalized()


func slope_at(wx: float, wz: float) -> float:
	return 1.0 - normal_at(wx, wz).y


func is_water(wx: float, wz: float) -> bool:
	return height_at(wx, wz) < WATER_LEVEL + 0.4


# ---------------------------------------------------------------- 网格
func build_mesh() -> void:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var tri_count := (RES - 1) * (RES - 1) * 2
	verts.resize(tri_count * 3)
	norms.resize(tri_count * 3)
	cols.resize(tri_count * 3)
	uvs.resize(tri_count * 3)

	var cell := SIZE / float(RES - 1)
	var vi := 0
	for z in RES - 1:
		for x in RES - 1:
			var wx := -SIZE * 0.5 + float(x) * cell
			var wz := -SIZE * 0.5 + float(z) * cell
			var p00 := Vector3(wx, heights[z * RES + x], wz)
			var p10 := Vector3(wx + cell, heights[z * RES + x + 1], wz)
			var p01 := Vector3(wx, heights[(z + 1) * RES + x], wz + cell)
			var p11 := Vector3(wx + cell, heights[(z + 1) * RES + x + 1], wz + cell)

			for tri in 2:
				var a := p00
				var b := p10
				var c := p01
				if tri == 1:
					a = p10
					b = p11
					c = p01
				var n := (b - a).cross(c - a).normalized()
				if n.y < 0.0:
					n = -n
				var col := _color_for((a.y + b.y + c.y) / 3.0, 1.0 - n.y, wx, wz)
				for p in [a, b, c]:
					verts[vi] = p
					norms[vi] = n
					cols[vi] = col
					uvs[vi] = Vector2(p.x, p.z) * 0.02
					vi += 1

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	am.surface_set_material(0, mat)

	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "TerrainMesh"
	mesh_instance.mesh = am
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mesh_instance)


func _color_for(h: float, slope: float, wx: float, wz: float) -> Color:
	var sand := Color(0.60, 0.55, 0.40)
	var grass := Color(0.27, 0.34, 0.20)
	var dry := Color(0.40, 0.39, 0.25)
	var rock := Color(0.36, 0.35, 0.33)
	var snow := Color(0.78, 0.80, 0.82)

	var c := grass.lerp(dry, clampf((h - 8.0) / 30.0, 0.0, 1.0))
	if h < 2.5:
		c = sand.lerp(c, clampf((h - 0.5) / 2.0, 0.0, 1.0))
	c = c.lerp(rock, clampf((slope - 0.35) / 0.35, 0.0, 1.0))
	if h > 44.0:
		c = c.lerp(snow, clampf((h - 44.0) / 12.0, 0.0, 1.0))
	# 大尺度斑块：让草原不是一整片死绿
	var macro := sin(wx * 0.0055) * cos(wz * 0.0068) * 0.5 + 0.5
	c = c.lerp(Color(0.44, 0.41, 0.29), macro * 0.28)
	var wet := sin(wx * 0.011 + 1.7) * cos(wz * 0.009 - 0.6) * 0.5 + 0.5
	c = c.lerp(Color(0.22, 0.31, 0.18), wet * 0.22)
	# 每块面轻微色差，低模才有的颗粒感
	var j := rng.randf_range(-0.035, 0.035)
	return Color(clampf(c.r + j, 0, 1), clampf(c.g + j, 0, 1), clampf(c.b + j, 0, 1))


# ---------------------------------------------------------------- 碰撞
func build_collision() -> void:
	var shape := HeightMapShape3D.new()
	shape.map_width = RES
	shape.map_depth = RES
	shape.map_data = heights
	var cs := CollisionShape3D.new()
	cs.shape = shape
	var s := SIZE / float(RES - 1)
	cs.scale = Vector3(s, 1.0, s)
	body = StaticBody3D.new()
	body.name = "TerrainBody"
	body.collision_layer = 1
	body.collision_mask = 0
	body.add_child(cs)
	add_child(body)


func build_water() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(SIZE * 1.4, SIZE * 1.4)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.09, 0.20, 0.26, 0.82)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.06
	mat.metallic = 0.55
	plane.material = mat
	var mi := MeshInstance3D.new()
	mi.name = "Water"
	mi.mesh = plane
	mi.position.y = WATER_LEVEL
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
