extends Control
## 主菜单：主页 / 军械库（改枪）/ 装备 / 载具 / 设置
##
## 全部用代码搭 UI，不依赖 .tscn —— 改布局只改这一处，也不会被编辑器改坏。

const BG := Color(0.07, 0.08, 0.10)
const PANEL := Color(0.11, 0.12, 0.15)
const CARD := Color(0.15, 0.16, 0.20)
const CARD_HI := Color(0.20, 0.22, 0.27)
const ACCENT := Color(0.92, 0.72, 0.28)
const TEXT := Color(0.88, 0.89, 0.86)
const DIM := Color(0.58, 0.60, 0.58)
const GOOD := Color(0.55, 0.82, 0.55)
const BAD := Color(0.88, 0.42, 0.38)

var _tab: int = 0
var _content: Control
var _credits_label: Label
var _tabs: Array[Button] = []
var _preview: SubViewport
var _preview_model: Node3D
var _selected_weapon: String = ""


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_selected_weapon = Loadout.primary
	_build_shell()
	_switch_tab(0)


# ---------------------------------------------------------------- 外框
func _build_shell() -> void:
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# 顶部标题条
	var top := ColorRect.new()
	top.color = Color(0.05, 0.06, 0.08)
	top.position = Vector2.ZERO
	top.size = Vector2(1600, 74)
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	add_child(top)

	var title := _mk_label("黑潮行动", 30, ACCENT)
	title.position = Vector2(36, 16)
	add_child(title)
	var sub := _mk_label("OPERATION BLACK TIDE", 12, DIM)
	sub.position = Vector2(38, 50)
	add_child(sub)

	_credits_label = _mk_label("", 20, GOOD)
	_credits_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_credits_label.position = Vector2(-320, 24)
	_credits_label.size = Vector2(280, 30)
	_credits_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_credits_label)

	# 左侧导航
	var side := VBoxContainer.new()
	side.position = Vector2(36, 110)
	side.size = Vector2(230, 700)
	side.add_theme_constant_override("separation", 10)
	add_child(side)

	var names := ["主页", "军械库", "装备", "载具", "设置"]
	for i in names.size():
		var b := _mk_button(names[i], 20)
		b.custom_minimum_size = Vector2(230, 54)
		b.pressed.connect(_switch_tab.bind(i))
		side.add_child(b)
		_tabs.append(b)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 24)
	side.add_child(spacer)

	var start := _mk_button("开始行动", 24)
	start.custom_minimum_size = Vector2(230, 64)
	start.add_theme_color_override("font_color", ACCENT)
	start.pressed.connect(_on_start)
	side.add_child(start)

	var quit := _mk_button("退出", 16)
	quit.custom_minimum_size = Vector2(230, 44)
	quit.pressed.connect(func(): get_tree().quit())
	side.add_child(quit)

	# 内容区
	_content = Control.new()
	_content.position = Vector2(300, 100)
	_content.size = Vector2(1260, 760)
	_content.set_anchors_preset(Control.PRESET_FULL_RECT)
	_content.offset_left = 300
	_content.offset_top = 100
	_content.offset_right = -40
	_content.offset_bottom = -30
	add_child(_content)

	_refresh_credits()


func _refresh_credits() -> void:
	_credits_label.text = "信用点  %d" % GameState.credits


# ---------------------------------------------------------------- 基础控件
func _mk_label(text: String, size: int, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _mk_button(text: String, size: int = 16) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", ACCENT)
	b.add_theme_stylebox_override("normal", _sb(CARD))
	b.add_theme_stylebox_override("hover", _sb(CARD_HI))
	b.add_theme_stylebox_override("pressed", _sb(PANEL))
	b.add_theme_stylebox_override("disabled", _sb(PANEL))
	return b


func _sb(color: Color, border: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(6)
	if border > 0:
		s.set_border_width_all(border)
		s.border_color = ACCENT
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


func _clear() -> void:
	for c in _content.get_children():
		c.queue_free()
	_preview = null
	_preview_model = null


func _card(parent: Control, height: float = 74.0) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(0, height)
	p.add_theme_stylebox_override("panel", _sb(CARD))
	if parent != null:
		parent.add_child(p)
	return p


func _switch_tab(i: int) -> void:
	_tab = i
	for k in _tabs.size():
		_tabs[k].add_theme_color_override("font_color", ACCENT if k == i else TEXT)
	_clear()
	match i:
		0:
			_build_home()
		1:
			_build_armory()
		2:
			_build_gear()
		3:
			_build_vehicles()
		4:
			_build_settings()
	_refresh_credits()


# ---------------------------------------------------------------- 主页
func _build_home() -> void:
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.add_theme_constant_override("separation", 18)
	_content.add_child(v)

	v.add_child(_mk_label("行动准备", 28, TEXT))
	v.add_child(_mk_label("从铁砧前线基地出发，夺取敌方据点，然后呼叫直升机撤离。", 15, DIM))

	var info := _card(v, 210)
	var ib := VBoxContainer.new()
	ib.add_theme_constant_override("separation", 8)
	info.add_child(ib)

	var w: Dictionary = Loadout.resolved_primary()
	ib.add_child(_mk_label("主武器    %s   %s   %s" % [
		str(w.get("label", "?")), str(w.get("caliber", "")), _mode_text(str(w.get("fire_mode", "")))], 16))
	ib.add_child(_mk_label("副武器    %s" % str(ItemDB.weapon(Loadout.secondary).get("label", "?")), 16))
	ib.add_child(_mk_label("护甲      %s  +  %s   （护甲值 %d）" % [
		str(ItemDB.ARMOR.get(Loadout.armor, {}).get("label", "无")),
		str(ItemDB.HELMET.get(Loadout.helmet, {}).get("label", "无")),
		int(Loadout.armor_value())], 16))
	ib.add_child(_mk_label("夜视      %s" % str(ItemDB.NVG.get(Loadout.nvg, {}).get("label", "无")), 16))
	ib.add_child(_mk_label("载具      %s" % str(ItemDB.VEHICLES.get(Loadout.vehicle, {}).get("label", "不配车")), 16))
	ib.add_child(_mk_label("涂装      %s" % str(ItemDB.CAMO.get(Loadout.camo, {}).get("label", "原厂灰")), 16))

	v.add_child(_mk_label("提示：击杀敌人 +30 信用点，完成任务并撤离可获得 1200+ 信用点。", 14, DIM))


func _mode_text(mode: String) -> String:
	match mode:
		"auto":
			return "全自动"
		"semi":
			return "半自动"
		"burst":
			return "三连发"
	return mode


# ---------------------------------------------------------------- 军械库
func _build_armory() -> void:
	var root := HBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 18)
	_content.add_child(root)

	# 左：武器列表
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(560, 0)
	left.add_theme_constant_override("separation", 6)
	root.add_child(left)
	left.add_child(_mk_label("武器", 22, TEXT))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)

	for origin in [["us", "美械 / NATO"], ["ru", "俄械"]]:
		var head := _mk_label(str(origin[1]), 15, ACCENT)
		list.add_child(head)
		for id in ItemDB.weapon_ids_by_origin(str(origin[0])):
			list.add_child(_weapon_row(id))

	# 右：预览 + 配件
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	root.add_child(right)

	right.add_child(_make_preview())
	right.add_child(_mk_label("配件", 20, TEXT))
	for slot in ItemDB.ATTACHMENTS.keys():
		right.add_child(_attachment_row(str(slot)))


func _weapon_row(id: String) -> Control:
	var w: Dictionary = ItemDB.weapon(id)
	var owned := Loadout.has_weapon(id)
	var equipped := Loadout.primary == id
	var p := _card(null, 62)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	p.add_child(h)

	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var name_col := GOOD if equipped else TEXT
	v.add_child(_mk_label(str(w.get("label", id)), 17, name_col))
	v.add_child(_mk_label("%s · %s · %d 发 · 伤害 %.0f" % [
		str(w.get("caliber", "")), _mode_text(str(w.get("fire_mode", ""))),
		int(w.get("mag", 0)), float(w.get("damage", 0))], 12, DIM))

	var btn := _mk_button("", 14)
	btn.custom_minimum_size = Vector2(110, 40)
	if equipped:
		btn.text = "已装备"
		btn.disabled = true
	elif owned:
		btn.text = "装备"
		btn.pressed.connect(func():
			Loadout.equip_weapon(0, id)
			_selected_weapon = id
			_switch_tab(1)
		)
	else:
		btn.text = "%d 购买" % int(w.get("price", 0))
		btn.pressed.connect(func():
			var r := Loadout.buy("weapon", id)
			_toast(str(r["msg"]))
			_switch_tab(1)
		)
	h.add_child(btn)
	return p


func _attachment_row(slot: String) -> Control:
	var meta: Dictionary = ItemDB.ATTACHMENTS[slot]
	var p := _card(null, 56)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	p.add_child(h)

	var lbl := _mk_label(str(meta["label"]), 14, DIM)
	lbl.custom_minimum_size = Vector2(64, 0)
	h.add_child(lbl)

	var opt := OptionButton.new()
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opt.add_theme_font_size_override("font_size", 14)
	var items: Dictionary = meta["items"]
	var keys: Array = items.keys()
	var cur_idx := 0
	for i in keys.size():
		var aid := str(keys[i])
		var owned := Loadout.has_attachment(slot, aid)
		var price := int(items[aid].get("price", 0))
		opt.add_item("%s%s" % [str(items[aid]["label"]), "" if owned else "   [%d]" % price], i)
		if str(Loadout.attachments.get(slot, "")) == aid:
			cur_idx = i
	opt.selected = cur_idx
	opt.item_selected.connect(func(idx: int):
		var aid := str(keys[idx])
		if Loadout.has_attachment(slot, aid):
			Loadout.equip_attachment(slot, aid)
			_toast("已装备 %s" % ItemDB.attachment_label(slot, aid))
			_switch_tab(1)
		else:
			var r := Loadout.buy("attachment", "%s:%s" % [slot, aid])
			_toast(str(r["msg"]))
			if bool(r["ok"]):
				Loadout.equip_attachment(slot, aid)
			_switch_tab(1)
	)
	h.add_child(opt)
	return p


func _make_preview() -> Control:
	var holder := SubViewportContainer.new()
	holder.custom_minimum_size = Vector2(0, 300)
	holder.stretch = true

	var vp := SubViewport.new()
	vp.size = Vector2i(560, 300)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	holder.add_child(vp)
	_preview = vp

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.72, 0.78)
	e.ambient_light_energy = 1.1
	env.environment = e
	vp.add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 40, 0)
	sun.light_energy = 1.6
	vp.add_child(sun)

	_preview_model = AssetLib.spawn(_selected_weapon, vp, Vector3.ZERO, 0.0, true)
	if _preview_model != null:
		AssetLib.apply_tint(_preview_model, Loadout.camo_color())

	# 按模型真实包围盒取景 + 居中（枪的轴心不在几何中心）
	var box := _node_aabb(_preview_model)
	var sz := box.size
	if _preview_model != null:
		_preview_model.position = -box.get_center()
	var longest: float = maxf(sz.x, maxf(sz.y, sz.z))
	if longest < 0.2:
		longest = 1.0
	var dist := maxf(1.1, longest * 1.35)

	var cam := Camera3D.new()
	cam.fov = 42.0
	vp.add_child(cam)
	# 枪的长轴在 Z 上，相机固定在 +Z 会正对枪口 —— 把模型先转 90°，从侧面看
	cam.look_at_from_position(Vector3(0.05, dist * 0.22, dist), Vector3.ZERO, Vector3.UP)
	cam.current = true
	if _preview_model != null:
		_preview_model.rotation_degrees.y = 90.0
	return holder


func _process(delta: float) -> void:
	if _preview_model != null:
		_preview_model.rotation_degrees.y += delta * 22.0


# ---------------------------------------------------------------- 装备
func _build_gear() -> void:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_content.add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)
	scroll.add_child(v)

	_gear_group(v, "护甲", "armor", ItemDB.ARMOR)
	_gear_group(v, "头盔", "helmet", ItemDB.HELMET)
	_gear_group(v, "夜视设备", "nvg", ItemDB.NVG)

	v.add_child(_mk_label("涂装", 20, TEXT))
	var colors := HBoxContainer.new()
	colors.add_theme_constant_override("separation", 10)
	v.add_child(colors)
	for cid in ItemDB.CAMO.keys():
		var c: Dictionary = ItemDB.CAMO[cid]
		var b := _mk_button("%s%s" % [str(c["label"]), "" if Loadout.has_any("camo", str(cid)) else "  [%d]" % int(c["price"])], 14)
		b.custom_minimum_size = Vector2(160, 48)
		var col: Color = c["color"]
		b.add_theme_stylebox_override("normal", _sb(Color(col.r * 0.5, col.g * 0.5, col.b * 0.5)))
		b.pressed.connect(func():
			if Loadout.has_any("camo", str(cid)):
				Loadout.equip_simple("camo", str(cid))
				_toast("涂装：%s" % str(c["label"]))
			else:
				var r := Loadout.buy("camo", str(cid))
				_toast(str(r["msg"]))
				if bool(r["ok"]):
					Loadout.equip_simple("camo", str(cid))
			_switch_tab(2)
		)
		colors.add_child(b)


func _gear_group(parent: Control, title: String, category: String, table: Dictionary) -> void:
	parent.add_child(_mk_label(title, 20, TEXT))
	for id in table.keys():
		var it: Dictionary = table[id]
		var owned := Loadout.has_any(category, id)
		var equipped := str(Loadout.get(category)) == str(id)
		var p := _card(parent, 58)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 12)
		p.add_child(h)

		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(v)
		v.add_child(_mk_label(str(it["label"]), 16, GOOD if equipped else TEXT))
		var sub := ""
		if category == "armor":
			sub = "防护等级 %s · 护甲 +%d · 移速 ×%.2f" % [
				str(it.get("class", "—")), int(it.get("armor", 0)), float(it.get("speed_mult", 1.0))]
		elif category == "nvg":
			sub = "夜视增益 ×%.1f · 按 N 开关" % float(it.get("gain", 0.0))
		else:
			sub = "护甲 +%d" % int(it.get("armor", 0))
		v.add_child(_mk_label(sub, 12, DIM))

		var btn := _mk_button("", 14)
		btn.custom_minimum_size = Vector2(110, 38)
		if equipped:
			btn.text = "已装备"
			btn.disabled = true
		elif owned:
			btn.text = "装备"
			btn.pressed.connect(func():
				Loadout.equip_simple(category, str(id))
				_switch_tab(2)
			)
		else:
			btn.text = "%d 购买" % int(it.get("price", 0))
			btn.pressed.connect(func():
				var r := Loadout.buy(category, str(id))
				_toast(str(r["msg"]))
				if bool(r["ok"]):
					Loadout.equip_simple(category, str(id))
				_switch_tab(2)
			)
		h.add_child(btn)


# ---------------------------------------------------------------- 载具
func _build_vehicles() -> void:
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.add_theme_constant_override("separation", 8)
	_content.add_child(v)
	v.add_child(_mk_label("载具", 22, TEXT))
	v.add_child(_mk_label("买下来后会停在铁砧基地的停机坪/停车场，靠近按 F 上车。", 13, DIM))

	for id in ItemDB.VEHICLES.keys():
		var it: Dictionary = ItemDB.VEHICLES[id]
		var owned := Loadout.has_any("vehicle", str(id))
		var equipped := Loadout.vehicle == str(id)
		var p := _card(v, 74)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 12)
		p.add_child(h)

		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(col)
		col.add_child(_mk_label(str(it["label"]), 17, GOOD if equipped else TEXT))
		var kind := "空中" if str(it.get("kind", "")) == "air" else ("地面" if str(it.get("kind", "")) == "ground" else "—")
		col.add_child(_mk_label("%s · 速度 %.0f · 装甲 %.0f · %d 座" % [
			kind, float(it.get("speed", 0)), float(it.get("armor", 0)), int(it.get("seats", 0))], 12, DIM))
		if it.has("desc"):
			col.add_child(_mk_label(str(it["desc"]), 12, DIM))

		var btn := _mk_button("", 14)
		btn.custom_minimum_size = Vector2(110, 38)
		if equipped:
			btn.text = "已选中"
			btn.disabled = true
		elif owned:
			btn.text = "选用"
			btn.pressed.connect(func():
				Loadout.equip_simple("vehicle", str(id))
				_switch_tab(3)
			)
		else:
			btn.text = "%d 购买" % int(it.get("price", 0))
			btn.pressed.connect(func():
				var r := Loadout.buy("vehicle", str(id))
				_toast(str(r["msg"]))
				if bool(r["ok"]):
					Loadout.equip_simple("vehicle", str(id))
				_switch_tab(3)
			)
		h.add_child(btn)


# ---------------------------------------------------------------- 设置
func _build_settings() -> void:
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.add_theme_constant_override("separation", 16)
	_content.add_child(v)
	v.add_child(_mk_label("设置", 22, TEXT))

	# 音量
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 16)
	v.add_child(row1)
	var vol_lbl := _mk_label("主音量", 16, TEXT)
	vol_lbl.custom_minimum_size = Vector2(120, 0)
	row1.add_child(vol_lbl)
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 1
	slider.value = GameState.master_volume * 100.0
	slider.custom_minimum_size = Vector2(360, 30)
	row1.add_child(slider)
	var vol_val := _mk_label("%d%%" % int(slider.value), 15, DIM)
	row1.add_child(vol_val)
	slider.value_changed.connect(func(val: float):
		GameState.master_volume = val / 100.0
		GameState.apply_audio()
		vol_val.text = "%d%%" % int(val)
	)

	# 分辨率
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 16)
	v.add_child(row2)
	var res_lbl := _mk_label("分辨率", 16, TEXT)
	res_lbl.custom_minimum_size = Vector2(120, 0)
	row2.add_child(res_lbl)
	var res_opt := OptionButton.new()
	res_opt.add_theme_font_size_override("font_size", 15)
	var modes := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440)]
	for i in modes.size():
		res_opt.add_item("%d × %d" % [modes[i].x, modes[i].y], i)
		if modes[i] == GameState.resolution:
			res_opt.selected = i
	res_opt.item_selected.connect(func(idx: int):
		GameState.resolution = modes[idx]
		GameState.apply_display()
	)
	row2.add_child(res_opt)

	# 显示模式
	var row3 := HBoxContainer.new()
	row3.add_theme_constant_override("separation", 16)
	v.add_child(row3)
	var mode_lbl := _mk_label("显示模式", 16, TEXT)
	mode_lbl.custom_minimum_size = Vector2(120, 0)
	row3.add_child(mode_lbl)
	var modes3 := [["窗口化", 0], ["无边框全屏", 1], ["全屏", 2]]
	for m in modes3:
		var b := _mk_button(str(m[0]), 15)
		b.custom_minimum_size = Vector2(150, 44)
		if GameState.display_mode == int(m[1]):
			b.add_theme_color_override("font_color", ACCENT)
		b.pressed.connect(func():
			GameState.display_mode = int(m[1])
			GameState.apply_display()
			_switch_tab(4)
		)
		row3.add_child(b)

	v.add_child(_mk_label("设置会自动保存。", 13, DIM))


# ---------------------------------------------------------------- 交互
func _toast(msg: String) -> void:
	if msg == "":
		return
	EventBus.notify.emit(msg)
	_refresh_credits()


func _on_start() -> void:
	GameState.save_profile()
	get_tree().change_scene_to_file("res://src/main.tscn")

func _node_aabb(root: Node) -> AABB:
	## 必须把父链的变换累积进来 —— GLB 根节点带 0.01 缩放，
	## 只用 mesh 自己的 transform 会得到厘米级的包围盒，模型会被推到 50 米外。
	var out := AABB()
	var first := true
	var stack: Array = [[root, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var item: Array = stack.pop_back()
		var n: Node = item[0]
		var xf: Transform3D = item[1]
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var a: AABB = xf * (n as MeshInstance3D).get_aabb()
			if first:
				out = a
				first = false
			else:
				out = out.merge(a)
		for c in n.get_children():
			var local: Transform3D = (c as Node3D).transform if c is Node3D else Transform3D.IDENTITY
			stack.append([c, xf * local])
	return out
