extends Node
## 无头自检：资源、地形、据点、战斗、倒地、结算，一条条断言。
## 跑法: godot --headless --path . res://tools/selftest.tscn

var _pass := 0
var _fail := 0
var _t0 := 0


func _ready() -> void:
	_t0 = Time.get_ticks_msec()
	print("=== 黑潮行动 自检 ===")
	await get_tree().process_frame

	await _test_assets()
	await _test_terrain()
	await _test_world()
	await _test_combat()
	await _test_outpost()
	await _test_squad()
	await _test_loadout()

	var dt := Time.get_ticks_msec() - _t0
	print("\n=== 结果: %d 通过 / %d 失败  (%d ms) ===" % [_pass, _fail, dt])
	if _fail > 0:
		print("❌ SELFTEST FAILED")
		get_tree().quit(1)
	else:
		print("✅ SELFTEST PASSED")
		get_tree().quit(0)


func check(cond: bool, label: String, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("  ✅ ", label, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  ❌ ", label, ("  " + detail) if detail != "" else "")


# ---------------------------------------------------------------- 资源
func _test_assets() -> void:
	print("\n[1] 素材库")
	check(AssetLib.meta.size() > 700, "模型元数据已加载", "%d 个" % AssetLib.meta.size())
	check(AssetLib.mat_defs.size() > 20, "材质表已加载", "%d 条" % AssetLib.mat_defs.size())

	var missing := []
	for m in ["SM_Bld_Barracks_01", "SM_Bld_Village_House_01", "SM_Veh_APC_01",
			"SM_Wep_Preset_A_Rifle_01", "SM_Chr_Insurgent_Male_01", "SM_Env_Tree_01",
			"SM_Prop_Crate_Ammo_01", "SM_Env_Helipad_01", "SM_Bld_Hangar_01"]:
		if not AssetLib.has_model(m):
			missing.append(m)
	check(missing.is_empty(), "关键模型齐全", str(missing))

	var node := AssetLib.spawn("SM_Bld_Barracks_01", null)
	check(node != null, "实例化建筑成功")
	var meshes := 0
	var surfaces := 0
	var with_mat := 0
	if node != null:
		var stack: Array[Node] = [node]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			if n is MeshInstance3D:
				meshes += 1
				var mi := n as MeshInstance3D
				if mi.mesh != null:
					surfaces += mi.mesh.get_surface_count()
					for i in mi.mesh.get_surface_count():
						if mi.get_surface_override_material(i) != null:
							with_mat += 1
			for c in n.get_children():
				stack.append(c)
	# 注意：这里断言的是"内容量"，不是"对象存在" —— 空 Group 也能骗过 !!node
	check(meshes >= 3, "建筑含多个网格", "%d 个 MeshInstance3D" % meshes)
	check(surfaces > 0, "网格有表面", "%d 个 surface" % surfaces)
	check(with_mat == surfaces, "所有表面都挂上了共享材质", "%d/%d" % [with_mat, surfaces])
	if node != null:
		node.queue_free()

	var size := AssetLib.size_of("SM_Bld_Barracks_01")
	check(size.y > 3.0 and size.y < 12.0, "建筑高度在合理范围", "%.2f m" % size.y)


# ---------------------------------------------------------------- 地形
func _test_terrain() -> void:
	print("\n[2] 地形")
	var t := Terrain.new()
	add_child(t)
	t.generate(12345)
	var h_center := t.height_at(0, 0)
	var h_edge := t.height_at(760, 760)
	check(h_center > h_edge, "岛中心高于边缘", "中心 %.1f / 边缘 %.1f" % [h_center, h_edge])
	check(h_edge < 0.0, "边缘沉到水下", "%.1f" % h_edge)
	var cell := Terrain.SIZE / float(Terrain.RES - 1)
	var corner := Vector2(-Terrain.SIZE * 0.5 + 90 * cell, -Terrain.SIZE * 0.5 + 96 * cell)
	var h00 := t.heights[96 * Terrain.RES + 90]
	var h10 := t.heights[96 * Terrain.RES + 91]
	var h01 := t.heights[97 * Terrain.RES + 90]
	var h11 := t.heights[97 * Terrain.RES + 91]
	var first := corner + Vector2(0.25, 0.35) * cell
	var second := corner + Vector2(0.7, 0.8) * cell
	check(absf(t.surface_height_at(first.x, first.y) - (h00 * 0.4 + h10 * 0.25 + h01 * 0.35)) < 0.001, "草根贴合第一个地形三角形")
	check(absf(t.surface_height_at(second.x, second.y) - (h11 * 0.5 + h01 * 0.3 + h10 * 0.2)) < 0.001, "草根贴合第二个地形三角形")

	var before := t.height_at(200, 200)
	t.add_pad(Vector2(200, 200), 30.0, 15.0, 25.0)
	t.apply_pads()
	var after := t.height_at(200, 200)
	check(absf(after - 25.0) < 0.6, "平台压平生效", "%.2f -> %.2f" % [before, after])

	t.build_mesh()
	t.build_collision()
	var verts := 0
	if t.mesh_instance != null and t.mesh_instance.mesh != null:
		verts = t.mesh_instance.mesh.get_faces().size()
	check(verts > 100000, "地形网格已生成", "%d 三角形顶点" % verts)
	var has_shape := false
	for c in t.body.get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape is HeightMapShape3D:
			has_shape = true
			var hs := (c as CollisionShape3D).shape as HeightMapShape3D
			check(hs.map_data.size() == hs.map_width * hs.map_depth, "高度图数据完整",
				"%dx%d" % [hs.map_width, hs.map_depth])
	check(has_shape, "地形碰撞体是 HeightMapShape3D")
	t.queue_free()


# ---------------------------------------------------------------- 世界
func _test_world() -> void:
	print("\n[3] 世界与据点")
	var w := WorldRoot.new()
	add_child(w)
	var t0 := Time.get_ticks_msec()
	w.generate(20261019)
	var dt := Time.get_ticks_msec() - t0
	print("    世界生成耗时 %d ms" % dt)

	check(w.pois.size() == 8, "据点数量", "%d" % w.pois.size())
	var with_spawns := 0
	for p in w.pois:
		if not p.get("spawn_points", []).is_empty():
			with_spawns += 1
	check(with_spawns >= 7, "据点都有出生点", "%d/8" % with_spawns)
	check(w.outposts.size() >= 5, "可争夺据点已建立", "%d 个" % w.outposts.size())

	var node_count := _count_nodes(w)
	var mesh_count := _count_type(w, "MeshInstance3D")
	check(mesh_count > 600, "世界里真的摆出了模型", "%d 个 MeshInstance3D / %d 节点" % [mesh_count, node_count])
	check(AssetLib.missing_models.is_empty(), "没有缺失的模型名", str(AssetLib.missing_models))
	check(AssetLib.unresolved.is_empty(), "所有材质名都能对上贴图表", str(AssetLib.unresolved))

	var thin_pois: Array = []
	for p in w.pois:
		var n: Node = p.get("node")
		if n == null:
			thin_pois.append(str(p["id"]) + ":无节点")
			continue
		var c := _count_type(n, "MeshInstance3D")
		if c < 15:
			thin_pois.append("%s:%d" % [str(p["id"]), c])
	check(thin_pois.is_empty(), "每个据点都有足够的内容", str(thin_pois))

	# 位置校验：模型必须落在据点附近，不能因为坐标叠加飞到岛外
	var stray: Array = []
	for p in w.pois:
		var n: Node = p.get("node")
		if n == null:
			continue
		var center := Vector3(p["pos"].x, w.terrain.height_at(p["pos"].x, p["pos"].y), p["pos"].y)
		var limit: float = float(p["radius"]) * 2.2 + 20.0
		var stack: Array[Node] = [n]
		var far := 0
		while not stack.is_empty():
			var cur: Node = stack.pop_back()
			if cur is MeshInstance3D:
				if (cur as Node3D).global_position.distance_to(center) > limit:
					far += 1
			for ch in cur.get_children():
				stack.append(ch)
		if far > 0:
			stray.append("%s:%d" % [str(p["id"]), far])
	check(stray.is_empty(), "据点模型没有跑到据点外面", str(stray))

	# 围墙朝向：每块挡墙的长轴必须和它所在的那条边平行
	# （这正是主人截图里看出来的问题：整体转了 90°，块与块之间还漏风）
	var fob_node: Node = null
	for p in w.pois:
		if str(p["id"]) == "fob":
			fob_node = p.get("node")
	if fob_node != null:
		var bad_rot := 0
		var pieces := 0
		var stack2: Array[Node] = [fob_node]
		while not stack2.is_empty():
			var cur: Node = stack2.pop_back()
			if cur is Node3D and str(cur.name).begins_with("SM_Prop_Barrier_Tall_Group_01"):
				pieces += 1
				var n3 := cur as Node3D
				var rel: Vector3 = n3.global_position - (fob_node as Node3D).global_position
				# 用真实世界包围盒判断长轴 —— GLB 根节点带 90°X 旋转，
				# 看 basis.z 会被骗（它永远朝下），必须量几何本身
				var box := _world_aabb(n3)
				var on_x_edge := absf(absf(rel.x) - 34.0) < 3.5
				var on_z_edge := absf(absf(rel.z) - 34.0) < 3.5
				if on_x_edge and not on_z_edge:
					if box.size.z < box.size.x * 1.6:
						bad_rot += 1
				elif on_z_edge and not on_x_edge:
					if box.size.x < box.size.z * 1.6:
						bad_rot += 1
			for ch in cur.get_children():
				stack2.append(ch)
		check(pieces >= 45, "FOB 围墙段数够（约 5.2m 一段，周长 272m）", "%d 段" % pieces)
		check(bad_rot == 0, "每段围墙长轴与所在边平行", "%d 段方向错误" % bad_rot)

	# 墙体/建筑必须真的挡人：从外面朝里打一条射线，应该被 StaticBody3D 拦住
	var static_bodies := _count_type(w, "StaticBody3D")
	check(static_bodies > 150, "世界里铺了碰撞体", "%d 个 StaticBody3D" % static_bodies)

	var wall_piece: Node3D = null
	var stack3: Array[Node] = [fob_node]
	while not stack3.is_empty() and wall_piece == null:
		var cur: Node = stack3.pop_back()
		if cur is Node3D and str(cur.name).begins_with("SM_Prop_Barrier_Tall_Group_01"):
			wall_piece = cur as Node3D
		for ch in cur.get_children():
			stack3.append(ch)
	if wall_piece != null:
		# 刚生成的碰撞体要等物理服务器同步一帧才能被射线查到
		await get_tree().physics_frame
		await get_tree().physics_frame
		var from := wall_piece.global_position + Vector3(0, 1.5, 10.0)
		var to := wall_piece.global_position + Vector3(0, 1.5, 0)
		var rq := PhysicsRayQueryParameters3D.create(from, to, 1)
		var rhit := w.get_world_3d().direct_space_state.intersect_ray(rq)
		check(not rhit.is_empty(), "围墙能挡住射线（有碰撞）", str(rhit.get("collider", "无")))

	# 连续性：同一条边上的相邻墙段中心距不能超过段长太多，否则就是"漏风"
	if fob_node != null:
		var edges := {"n": [], "s": [], "w": [], "e": []}
		var st4: Array[Node] = [fob_node]
		while not st4.is_empty():
			var cur: Node = st4.pop_back()
			if cur is Node3D and str(cur.name).begins_with("SM_Prop_Barrier_Tall_Group_01"):
				var rel: Vector3 = (cur as Node3D).global_position - (fob_node as Node3D).global_position
				if absf(rel.z + 34.0) < 3.0:
					edges["n"].append(rel.x)
				elif absf(rel.z - 34.0) < 3.0:
					edges["s"].append(rel.x)
				elif absf(rel.x + 34.0) < 3.0:
					edges["w"].append(rel.z)
				elif absf(rel.x - 34.0) < 3.0:
					edges["e"].append(rel.z)
			for ch in cur.get_children():
				st4.append(ch)
		var worst_closed := 0.0
		for k in ["n", "w", "e"]:
			var arr: Array = edges[k]
			arr.sort()
			for i in range(1, arr.size()):
				worst_closed = maxf(worst_closed, float(arr[i]) - float(arr[i - 1]))
		check(worst_closed > 0.0 and worst_closed < 6.0, "北/东/西三面墙首尾相接",
			"最大间隔 %.1f m" % worst_closed)

		# 南面必须留门 —— 否则玩家被关在基地里出不来
		var south: Array = edges["s"]
		south.sort()
		var gate := 0.0
		for i in range(1, south.size()):
			gate = maxf(gate, float(south[i]) - float(south[i - 1]))
		check(gate > 8.0 and gate < 20.0, "南面留有出入口", "门口宽 %.1f m" % gate)

	var water_ok := true
	for p in w.pois:
		var h: float = w.terrain.height_at(p["pos"].x, p["pos"].y)
		if h < 2.0:
			water_ok = false
	check(water_ok, "所有据点都在陆地上")

	var mm := _count_type(w, "MultiMeshInstance3D")
	check(mm >= 4, "植被用 MultiMesh 批量实例化", "%d 组" % mm)
	w.queue_free()


func _count_nodes(root: Node) -> int:
	var n := 0
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		n += 1
		for c in cur.get_children():
			stack.append(c)
	return n


func _count_type(root: Node, type_name: String) -> int:
	var n := 0
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur.is_class(type_name):
			n += 1
		for c in cur.get_children():
			stack.append(c)
	return n


# ---------------------------------------------------------------- 战斗
func _test_combat() -> void:
	print("\n[4] 战斗与伤害")
	var ground := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	cs.shape = box
	cs.position.y = -0.5
	ground.add_child(cs)
	add_child(ground)

	var p := Player.new()
	add_child(p)
	p.global_position = Vector3(0, 1.0, 0)
	await get_tree().physics_frame
	await get_tree().physics_frame

	check(p.health == 100.0, "玩家初始生命", "%.0f" % p.health)
	p.take_damage(40.0, Vector3.ZERO, null)
	check(p.health < 100.0 and p.armor < 60.0, "护甲吸收部分伤害",
		"HP %.0f / 护甲 %.0f" % [p.health, p.armor])

	p.take_damage(400.0, Vector3.ZERO, null)
	check(p.state == Player.State.DOWNED, "生命归零进入倒地")
	check(p.bleed_time > 0.0, "倒地后开始失血计时", "%.0f s" % p.bleed_time)
	p.revive(45.0)
	check(p.state == Player.State.ALIVE and absf(p.health - 45.0) < 0.1, "被救起后恢复行动")

	# 敌人
	var e := Soldier.new()
	add_child(e)
	e.global_position = Vector3(0, 1.0, -8)
	e.configure("opfor", "SM_Chr_Insurgent_Male_01", 0.6)
	await get_tree().physics_frame
	check(e.health > 0.0 and e.is_alive(), "敌人已生成")
	e.take_damage(60.0, e.global_position, p)
	check(e.health < 100.0, "敌人受伤", "%.0f" % e.health)
	e.take_damage(400.0, e.global_position, p)
	check(not e.is_alive(), "敌人被击杀")

	# 骨骼动画：绑上了没有、动起来没有
	check(e.rig != null and e.rig.ready, "AI 骨骼已绑定",
		"%d 根骨骼" % (e.rig._idx.size() if e.rig != null else 0))
	if e.rig != null and e.rig.ready:
		var leg: int = e.rig.skel.find_bone("UpperLeg_L")
		var q0: Quaternion = e.rig.skel.get_bone_pose_rotation(leg)
		for i in 12:
			e.rig.animate_locomotion(1.0 / 60.0, 1.0, 0.0, 0.0)
		var q1: Quaternion = e.rig.skel.get_bone_pose_rotation(leg)
		check(q0 != q1, "动画真的驱动了骨骼", "UpperLeg_L 旋转发生变化")
		check(absf(rad_to_deg(q1.get_angle()) - rad_to_deg(q0.get_angle())) > 0.5,
			"摆腿幅度可见", "%.1f° -> %.1f°" % [rad_to_deg(q0.get_angle()), rad_to_deg(q1.get_angle())])

	# 射击
	var before_ammo := p.ammo_mag
	p._fire()
	check(p.ammo_mag == before_ammo - 1, "开火消耗弹药", "%d -> %d" % [before_ammo, p.ammo_mag])
	check(p.hud_spread() > 0.0, "开火产生散布")

	p.queue_free()
	e.queue_free()
	ground.queue_free()


# ---------------------------------------------------------------- 据点
func _test_outpost() -> void:
	print("\n[5] 据点争夺")
	var o := Outpost.new()
	add_child(o)
	o.setup("test", "测试据点", 20.0, "opfor")
	await get_tree().process_frame
	check(o.owner_faction == "opfor", "初始归属敌方")
	check(o.status_text().contains("敌方"), "状态文本正确", o.status_text())
	o._set_owner("blufor")
	check(o.is_owned_by_player(), "归属切换生效")
	check(o.status_text().contains("已控制"), "状态文本更新", o.status_text())
	o.queue_free()

func _world_aabb(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is MeshInstance3D:
			var mi := cur as MeshInstance3D
			var a: AABB = mi.global_transform * mi.get_aabb()
			if first:
				out = a
				first = false
			else:
				out = out.merge(a)
		for c in cur.get_children():
			stack.append(c)
	return out

# ---------------------------------------------------------------- 小队
func _test_squad() -> void:
	print("\n[6] 小队系统")
	var ground := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 1, 400)
	cs.shape = box
	cs.position.y = -0.5
	ground.add_child(cs)
	add_child(ground)

	var q := Squad.new()
	add_child(q)
	q.setup("opfor", "test_squad", Vector3.ZERO, 20.0)
	check(q.size() == 0, "空小队初始没有成员")

	var soldiers: Array[Soldier] = []
	for i in 4:
		var s := Soldier.new()
		add_child(s)
		s.global_position = Vector3(float(i) * 2.0 - 3.0, 1.0, 0.0)
		s.configure("opfor", "SM_Chr_Insurgent_Male_01", 0.6)
		q.add_member(s)
		soldiers.append(s)
	await get_tree().physics_frame

	check(q.size() == 4, "编组 4 人", "%d" % q.size())
	check(q.leader == soldiers[0], "第一个入队的是队长")
	check(soldiers[0].squad_role == "leader", "角色：队长")
	check(soldiers[1].squad_role == "support", "角色：机枪手")
	check(soldiers[2].squad_role == "marksman", "角色：精确射手")
	check(soldiers[2].weapon_range > soldiers[3].weapon_range, "精确射手射程更远",
		"%.0f vs %.0f" % [soldiers[2].weapon_range, soldiers[3].weapon_range])

	var o0: Dictionary = q.order_for(soldiers[0])
	var o1: Dictionary = q.order_for(soldiers[1])
	check(str(o0["mode"]) == "formation", "巡逻时按队形走", str(o0["mode"]))
	check((o0["pos"] as Vector3).distance_to(o1["pos"] as Vector3) > 1.0,
		"队形位置互不重叠", "%.1f m" % (o0["pos"] as Vector3).distance_to(o1["pos"] as Vector3))

	# 情报共享：一个人看到，全队都知道
	var contact := Vector3(0, 1, -40)
	q.report_contact(contact, null)
	check(q.has_contact, "报点后全队进入接触")
	check(q.state == Squad.State.CONTACT, "状态切到「接触」")
	check(q.contact_pos.distance_to(contact) < 0.1, "接触点已记录")

	var s3: Soldier = soldiers[3]
	s3.state = Soldier.AIState.PATROL
	s3._think()
	check(s3.state == Soldier.AIState.SEARCH, "没有视野的队员转入搜索")
	check(s3._last_seen.distance_to(contact) < 0.5, "搜索目标 = 队里报的接触点")

	# 突击：接触稳定后两个火力组分工
	q._process(Squad.CONTACT_HOLD + 0.2)
	check(q.state == Squad.State.ASSAULT, "接触稳定后转入突击")
	var modes := {}
	for s in soldiers:
		modes[str(q.order_for(s)["mode"])] = true
	check(modes.has("advance") and modes.has("hold"), "两组分别跃进/压制", str(modes.keys()))

	# 士气：连续减员后溃退
	q.on_member_down(soldiers[3])
	q.on_member_down(soldiers[2])
	q.on_member_down(soldiers[1])
	check(q.is_broken(), "减员后小队溃退", "士气 %.2f" % q.morale)
	check(str(q.order_for(soldiers[0])["mode"]) == "retreat", "溃退指令是撤回集结点")

	for s in soldiers:
		s.queue_free()
	q.queue_free()
	ground.queue_free()

# ---------------------------------------------------------------- 军械库 / 载具
func _test_loadout() -> void:
	print("\n[7] 军械库与载具")
	var orig_credits := GameState.credits
	var orig_weapons := Loadout.owned_weapons.duplicate()

	# 数据表完整性
	check(ItemDB.WEAPONS.size() >= 20, "武器表条目", "%d 把" % ItemDB.WEAPONS.size())
	check(ItemDB.weapon_ids_by_origin("us").size() >= 8, "美械数量",
		"%d 把" % ItemDB.weapon_ids_by_origin("us").size())
	check(ItemDB.weapon_ids_by_origin("ru").size() >= 8, "俄械数量",
		"%d 把" % ItemDB.weapon_ids_by_origin("ru").size())

	var m16: Dictionary = ItemDB.weapon("SM_Wep_Preset_A_Rifle_02")
	check(str(m16.get("fire_mode", "")) == "burst" and int(m16.get("burst", 0)) == 3,
		"M16A4 是三连发", str(m16.get("fire_mode")))

	# 配件结算：装补偿器后后坐应该变小
	var base: Dictionary = ItemDB.resolve("SM_Wep_Preset_A_Rifle_01", {})
	var modded: Dictionary = ItemDB.resolve("SM_Wep_Preset_A_Rifle_01",
		{"muzzle": "comp", "mag": "ext"})
	check(float(modded["recoil"]) < float(base["recoil"]), "补偿器降低后坐",
		"%.2f -> %.2f" % [float(base["recoil"]), float(modded["recoil"])])
	check(int(modded["mag"]) == int(base["mag"]) + 10, "扩容弹匣 +10 发",
		"%d -> %d" % [int(base["mag"]), int(modded["mag"])])

	# 购买
	GameState.credits = 5000
	Loadout.owned_weapons = ["SM_Wep_Preset_A_Rifle_01"]
	var r1 := Loadout.buy("weapon", "SM_Wep_Preset_A_Rifle_02")
	check(bool(r1["ok"]), "信用点够时能买", str(r1["msg"]))
	check(Loadout.has_weapon("SM_Wep_Preset_A_Rifle_02"), "买完进入已拥有列表")
	check(GameState.credits == 2600, "扣款正确", "%d" % GameState.credits)

	GameState.credits = 100
	var r2 := Loadout.buy("weapon", "SM_Wep_Preset_A_Rifle_03")
	check(not bool(r2["ok"]), "信用点不足时买不了", str(r2["msg"]))
	check(not Loadout.has_weapon("SM_Wep_Preset_A_Rifle_03"), "失败不会误发物品")

	# 还原，别把测试数据写进玩家存档
	GameState.credits = orig_credits
	Loadout.owned_weapons = orig_weapons
	Loadout.save_data()

	# 三连发：一次扳机打三发
	var p := Player.new()
	add_child(p)
	await get_tree().physics_frame
	p._def = ItemDB.resolve("SM_Wep_Preset_A_Rifle_02", {})
	p.ammo_mag = 30
	p._burst_left = 3
	p._burst_t = 0.0
	for i in 12:
		p._process_combat(0.05)
	check(p.ammo_mag == 27, "三连发消耗 3 发", "%d" % p.ammo_mag)
	p.queue_free()

	# 载具
	var v := Vehicle.new()
	v.setup("SM_Veh_Helicopter_Transport_01", "air", 38.0, 40.0, "UH-60 运输直升机")
	add_child(v)
	await get_tree().physics_frame
	check(v.kind == "air", "直升机构建为空中载具")
	check(v.interact_prompt() != "", "靠近有驾驶提示", v.interact_prompt())
	v.queue_free()

	# 夜视仪
	var had_nvg := Loadout.nvg
	Loadout.nvg = "pvs14"
	var p2 := Player.new()
	add_child(p2)
	await get_tree().physics_frame
	p2._toggle_nvg()
	check(p2._nvg_on, "夜视仪能开启")
	p2._toggle_nvg()
	check(not p2._nvg_on, "夜视仪能关闭")
	p2.queue_free()
	Loadout.nvg = had_nvg
	Loadout.save_data()
