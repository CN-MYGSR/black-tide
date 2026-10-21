extends Node
## 集成测试：真的把 main.tscn 跑起来，验证核心循环
##   ① 玩家落地 ② AI 能发现并交火 ③ 据点能被推进并易主 ④ 结算能落地

var _pass := 0
var _fail := 0


func _ready() -> void:
	print("=== 集成测试 ===")
	# 先选一台直升机，验证"买了就会停在基地里"
	var had_vehicle := Loadout.vehicle
	Loadout.vehicle = "SM_Veh_Helicopter_Transport_01"
	var main: Node3D = load("res://src/main.tscn").instantiate()
	add_child(main)
	while not main.loading_complete:
		await get_tree().process_frame
	await get_tree().create_timer(2.0).timeout

	var player: Player = main.player
	var world: WorldRoot = main.world
	check(player != null, "玩家已生成")
	check(player.is_on_floor(), "玩家站在地面上", str(player.global_position))
	check(world.outposts.size() >= 5, "据点数", str(world.outposts.size()))
	check(main._vehicle != null, "购买的载具出现在基地里",
		main._vehicle.display_name if main._vehicle != null else "无")
	Loadout.vehicle = had_vehicle

	var enemies := get_tree().get_nodes_in_group("opfor")
	check(enemies.size() >= 15, "敌方 AI 已铺开", "%d 个" % enemies.size())
	var allies := get_tree().get_nodes_in_group("blufor")
	check(allies.size() >= 3, "友军已生成", "%d 个" % allies.size())
	var rivals := get_tree().get_nodes_in_group("rival")
	check(rivals.size() >= 4, "第三方势力（模拟其他玩家）", "%d 个" % rivals.size())

	# 固定的高空平地，避免随机地形遮挡把感知检查变成概率测试。
	var arena := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(100, 1, 100)
	floor_shape.shape = floor_box
	arena.add_child(floor_shape)
	main.add_child(arena)
	arena.position = Vector3(0, 119.5, 0)
	var open := Vector3(0, 120, 0)
	player.global_position = open + Vector3(0, 1.2, 0)

	var e: Soldier = enemies[0]
	var ep := open + Vector3(0, 0, -25)
	# 这一条测的是"单兵能不能打中玩家"，先摘掉小队，
	# 否则命中与否会取决于小队当前是压制组还是跃进组（跃进组按纪律不射击）
	e.squad = null
	e.accuracy = 1.0
	e.global_position = ep
	e.look_at(Vector3(open.x, ep.y + 1.0, open.z), Vector3.UP)
	e.state = Soldier.AIState.IDLE
	await get_tree().create_timer(1.0).timeout
	check(e.state == Soldier.AIState.COMBAT, "AI 发现玩家后进入交战", "state=%d" % e.state)

	var shots := [0]
	var shot_cb := func(_s: Node, _f: Vector3, _t: Vector3, _h: bool): shots[0] += 1
	EventBus.shot_fired.connect(shot_cb)
	var hp_before := player.health + player.armor
	await get_tree().create_timer(4.0).timeout
	EventBus.shot_fired.disconnect(shot_cb)
	check(shots[0] > 0, "AI 真的开枪了", "%d 发" % shots[0])
	# 诊断：直接从敌人眼睛打一条射线到玩家，看命中什么
	var from := e.global_position + Vector3(0, 1.45, 0)
	var to := player.global_position + Vector3(0, 1.1, 0)
	var dq := PhysicsRayQueryParameters3D.create(from, to, 1 | 2 | 4, [e.get_rid()])
	var dhit := e.get_world_3d().direct_space_state.intersect_ray(dq)
	print("    [诊断] 敌人->玩家射线: ", dhit.get("collider", "无"), " 玩家layer=", player.collision_layer,
		" 距离=", from.distance_to(to))
	check(player.health + player.armor < hp_before, "AI 能对玩家造成伤害",
		"%.0f -> %.0f" % [hp_before, player.health + player.armor])
	# 后续检查不让随机交火改变测试前提；倒地必须先真正救起。
	for n in get_tree().get_nodes_in_group("combatant"):
		if n is Soldier:
			n.set_physics_process(false)
	if player.state == Player.State.DOWNED:
		player.revive(100)

	# ③ 据点推进：清空目标据点周围敌人，把玩家放进去
	var target: Outpost = null
	for o in world.outposts:
		if not o.is_owned_by_player():
			target = o
			break
	check(target != null, "找到可争夺据点", target.display_name if target else "无")
	if target != null:
		player.health = 100.0
		player.armor = 60.0
		player.global_position = target.global_position + Vector3(0, 2.0, 0)
		# 清掉圈内的守军，否则进度不会涨
		for n in get_tree().get_nodes_in_group("combatant"):
			if n is Soldier and n.faction in ["opfor", "rival"] and n.global_position.distance_to(target.global_position) < target.radius + 5.0:
				(n as Soldier).take_damage(9999.0, n.global_position, player)
		var p0 := target.progress
		await get_tree().create_timer(3.0).timeout
		check(target.progress > p0, "玩家在圈内推进控制进度",
			"%.0f%% -> %.0f%%" % [p0, target.progress])

		# 直接把进度顶满，验证易主与事件
		var captured := [false]
		var cb := func(o: Node, _f: String): captured[0] = true
		EventBus.outpost_captured.connect(cb)
		target.progress = 99.5
		await get_tree().create_timer(1.0).timeout
		check(target.is_owned_by_player(), "进度满后据点易主")
		check(captured[0], "触发 outpost_captured 事件")
		EventBus.outpost_captured.disconnect(cb)

	# ④ 小队系统：编组、共享情报
	var squads: Array = main._squads
	check(squads.size() >= 6, "关卡里编成了多个小队", "%d 个" % squads.size())
	var opfor_now := get_tree().get_nodes_in_group("opfor")
	var in_squad := 0
	for n in opfor_now:
		if n.squad != null:
			in_squad += 1
	check(in_squad >= int(opfor_now.size() * 0.8), "敌方基本都编入了小队",
		"%d/%d" % [in_squad, opfor_now.size()])

	var q = null
	for squad in squads:
		if squad.faction == "opfor" and not squad.is_broken() and squad.size() >= 2:
			q = squad
			break
	var contact := player.global_position
	q.report_contact(contact, player)
	check(q.has_contact, "小队收到接触报告")
	check(q.state == Squad.State.CONTACT or q.state == Squad.State.ASSAULT,
		"小队进入接触/突击状态", q.status_text())

	var far_member = null
	for m in q.members:
		if is_instance_valid(m) and m.is_alive():
			far_member = m
			break
	if far_member != null:
		far_member.global_position = Vector3(700, world.terrain.height_at(700, 700) + 1, 700)
		far_member.state = Soldier.AIState.PATROL
		far_member._target = null
		far_member.set_physics_process(true)
		await get_tree().create_timer(0.5).timeout
		check(far_member.state == Soldier.AIState.SEARCH, "无视野队员转入搜索")
		check(far_member._last_seen.distance_to(contact) < 1.0,
			"搜索目标 = 队里报的接触点")
		far_member.set_physics_process(false)

	# ⑤ 撤离流程：呼叫直升机 -> 降落 -> 登机 -> 结算事件
	main._mission_state = "extract"
	main._call_extraction()
	check(main.heli != null, "直升机已派出")
	if main.heli != null:
		await get_tree().create_timer(16.0).timeout
		check(main.heli.state == "landed", "直升机完成降落", main.heli.state)
		var done := [false]
		var dcb := func(_c: int, _x: int): done[0] = true
		EventBus.mission_completed.connect(dcb)
		main.heli.interact(player)
		await get_tree().create_timer(0.3).timeout
		check(done[0], "登机触发结算")
		EventBus.mission_completed.disconnect(dcb)

	# ⑤ 结算
	var before_credits := GameState.credits
	GameState.in_raid = true
	GameState.end_raid(true, 1500)
	check(GameState.credits == before_credits + 1500, "撤离结算加信用点",
		"%d -> %d" % [before_credits, GameState.credits])

	print("\n=== 集成结果: %d 通过 / %d 失败 ===" % [_pass, _fail])
	if _fail > 0:
		print("❌ INTEGRATION FAILED")
		get_tree().quit(1)
	else:
		print("✅ INTEGRATION PASSED")
		get_tree().quit(0)


func check(cond: bool, label: String, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("  ✅ ", label, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  ❌ ", label, ("  " + detail) if detail != "" else "")
