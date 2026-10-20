class_name HUD
extends Control
## 全部用 _draw 画的 HUD：准星、血条、弹药、罗盘、小地图、提示、倒地遮罩。
## 不走 .tscn —— 少一个场景文件，改布局只改代码，也不会被编辑器改坏。

var player: Player
var world: WorldRoot

var _notifications: Array = []      ## [{text, t}]
var _hit_t: float = 0.0
var _hit_kind: String = ""
var _damage_flash: float = 0.0
var _objective_main: String = ""
var _objective_sub: String = ""
var _banner: String = ""
var _banner_t: float = 0.0
var _debrief: Dictionary = {}
var _show_debrief: bool = false

var font: Font


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = ThemeDB.fallback_font
	EventBus.notify.connect(_on_notify)
	EventBus.hitmarker.connect(_on_hitmarker)
	EventBus.player_damaged.connect(_on_damaged)
	EventBus.objective_changed.connect(_on_objective)
	EventBus.mission_completed.connect(_on_completed)
	EventBus.mission_failed.connect(_on_failed)


func _on_notify(text: String) -> void:
	_notifications.append({"text": text, "t": 4.0})
	if _notifications.size() > 5:
		_notifications.pop_front()


func _on_hitmarker(kind: String) -> void:
	_hit_t = 0.18
	_hit_kind = kind


func _on_damaged(_amount: float, _src: Node) -> void:
	_damage_flash = 1.0


func _on_objective(main: String, detail: String) -> void:
	_objective_main = main
	_objective_sub = detail


func _on_completed(credits: int, xp: int) -> void:
	_show_debrief = true
	_debrief = {"ok": true, "credits": credits, "xp": xp, "kills": GameState.raid_kills}


func _on_failed(reason: String) -> void:
	_show_debrief = true
	_debrief = {"ok": false, "reason": reason, "kills": GameState.raid_kills}


func _process(delta: float) -> void:
	for n in _notifications:
		n["t"] -= delta
	_notifications = _notifications.filter(func(n): return n["t"] > 0.0)
	_hit_t = maxf(0.0, _hit_t - delta)
	_damage_flash = maxf(0.0, _damage_flash - delta * 1.6)
	_banner_t = maxf(0.0, _banner_t - delta)
	queue_redraw()


func _draw() -> void:
	if player == null:
		return
	_draw_vignette()
	_draw_crosshair()
	_draw_health()
	_draw_ammo()
	_draw_compass()
	_draw_minimap()
	_draw_objective()
	_draw_notifications()
	_draw_prompt()
	_draw_downed()
	if _show_debrief:
		_draw_debrief()


# ---------------------------------------------------------------- 基础绘制
func _text(pos: Vector2, s: String, size: int, color: Color, align: int = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
	draw_string(font, pos, s, align, width, size, color)


func _bar(rect: Rect2, ratio: float, fill: Color, bg: Color) -> void:
	draw_rect(rect, bg)
	draw_rect(Rect2(rect.position, Vector2(rect.size.x * clampf(ratio, 0, 1), rect.size.y)), fill)


# ---------------------------------------------------------------- 元素
func _draw_vignette() -> void:
	var s := size
	if _damage_flash > 0.01:
		draw_rect(Rect2(Vector2.ZERO, s), Color(0.6, 0.05, 0.05, 0.25 * _damage_flash))
	if player.state == Player.State.DOWNED:
		draw_rect(Rect2(Vector2.ZERO, s), Color(0.45, 0.0, 0.0, 0.22))


func _draw_crosshair() -> void:
	var c := size * 0.5
	var gap := 5.0 + player.hud_spread() * 4.0
	var len := 9.0
	var col := Color(0.92, 0.95, 0.9, 0.85)
	col.a *= lerpf(1.0, 0.25, player.ads_blend())
	draw_line(c + Vector2(-gap - len, 0), c + Vector2(-gap, 0), col, 1.6)
	draw_line(c + Vector2(gap, 0), c + Vector2(gap + len, 0), col, 1.6)
	draw_line(c + Vector2(0, -gap - len), c + Vector2(0, -gap), col, 1.6)
	draw_line(c + Vector2(0, gap), c + Vector2(0, gap + len), col, 1.6)
	draw_circle(c, 1.2, col)

	if _hit_t > 0.0:
		var hc := Color(1, 0.85, 0.3) if _hit_kind == "head" else Color(1, 1, 1)
		hc.a = _hit_t / 0.18
		for i in 4:
			var a := PI * 0.25 + i * PI * 0.5
			var d := Vector2(cos(a), sin(a))
			draw_line(c + d * 6.0, c + d * 13.0, hc, 2.0)


func _draw_health() -> void:
	var s := size
	var x := 40.0
	var y := s.y - 118.0
	var w := 260.0

	_text(Vector2(x, y - 8), "生命", 13, Color(0.75, 0.78, 0.8))
	_bar(Rect2(x, y, w, 14), player.health / player.max_health, Color(0.78, 0.22, 0.18), Color(0, 0, 0, 0.45))
	_text(Vector2(x + w + 10, y + 12), "%d" % int(player.health), 15, Color(0.95, 0.95, 0.92))

	_text(Vector2(x, y + 30), "护甲", 13, Color(0.75, 0.78, 0.8))
	_bar(Rect2(x, y + 38, w, 10), player.armor / maxf(1.0, player.max_armor), Color(0.35, 0.55, 0.85), Color(0, 0, 0, 0.45))

	_text(Vector2(x, y + 66), "体力", 13, Color(0.75, 0.78, 0.8))
	_bar(Rect2(x, y + 74, w, 8), player.stamina / player.max_stamina, Color(0.72, 0.68, 0.25), Color(0, 0, 0, 0.45))

	var med_y := y + 96
	_text(Vector2(x, med_y), "绷带 x%d   敷料 x%d   维生素 x%d" % [player.meds["bandage"], player.meds["dressing"], player.meds["vitamins"]],
		13, Color(0.72, 0.76, 0.72))


func _draw_ammo() -> void:
	var s := size
	var def := player.current_def()
	var right := s.x - 40.0
	_text(Vector2(right - 220, s.y - 96), str(def["label"]), 15, Color(0.85, 0.86, 0.84), HORIZONTAL_ALIGNMENT_RIGHT, 220)
	var mag := "%d" % player.ammo_mag
	var res := " / %d" % player.ammo_reserve
	_text(Vector2(right - 120, s.y - 52), mag, 40, Color(0.96, 0.96, 0.92), HORIZONTAL_ALIGNMENT_RIGHT, 120)
	_text(Vector2(right - 100, s.y - 54), res, 18, Color(0.7, 0.72, 0.7), HORIZONTAL_ALIGNMENT_LEFT, 100)
	if player.is_reloading():
		_text(Vector2(right - 220, s.y - 26), "换弹中…", 14, Color(0.95, 0.75, 0.3), HORIZONTAL_ALIGNMENT_RIGHT, 220)


func _draw_compass() -> void:
	var s := size
	var cx := s.x * 0.5
	var w := 420.0
	var y := 34.0
	draw_rect(Rect2(cx - w * 0.5, y - 14, w, 28), Color(0, 0, 0, 0.28))
	var heading := fposmod(-rad_to_deg(player.rotation.y), 360.0)
	var px_per_deg := w / 120.0
	for d in range(-60, 61, 5):
		var deg := fposmod(heading + d, 360.0)
		var x := cx + d * px_per_deg
		var major := int(deg) % 45 == 0
		var hh := 8.0 if major else 4.0
		draw_line(Vector2(x, y + 12 - hh), Vector2(x, y + 12), Color(0.9, 0.9, 0.85, 0.8), 1.5)
		if major:
			_text(Vector2(x - 12, y - 2), _compass_label(int(round(deg))), 13, Color(0.92, 0.92, 0.88), HORIZONTAL_ALIGNMENT_CENTER, 24)
	draw_line(Vector2(cx, y + 8), Vector2(cx, y + 18), Color(1, 0.85, 0.35), 2.0)


func _compass_label(deg: int) -> String:
	var d := fposmod(float(deg), 360.0)
	if d < 22.5 or d >= 337.5:
		return "N"
	if d < 67.5:
		return "NE"
	if d < 112.5:
		return "E"
	if d < 157.5:
		return "SE"
	if d < 202.5:
		return "S"
	if d < 247.5:
		return "SW"
	if d < 292.5:
		return "W"
	return "NW"


func _draw_minimap() -> void:
	if world == null:
		return
	var s := size
	var r := 96.0
	var c := Vector2(s.x - r - 34.0, r + 44.0)
	draw_circle(c, r, Color(0.06, 0.08, 0.07, 0.55))
	draw_arc(c, r, 0, TAU, 48, Color(0.85, 0.85, 0.8, 0.5), 1.5)

	var scale := 0.105
	var ppos := Vector2(player.global_position.x, player.global_position.z)
	for poi in world.pois:
		var rel: Vector2 = (poi["pos"] - ppos) * scale
		if rel.length() > r - 6.0:
			rel = rel.normalized() * (r - 6.0)
		var col := Color(0.8, 0.3, 0.25)
		if str(poi["faction"]) == "blufor":
			col = Color(0.35, 0.6, 0.95)
		draw_circle(c + rel, 3.5, col)

	for o in world.outposts:
		var rel: Vector2 = (Vector2(o.global_position.x, o.global_position.z) - ppos) * scale
		if rel.length() > r - 4.0:
			continue
		if o.progress > 0.0:
			draw_arc(c + rel, 7.0, -PI * 0.5, -PI * 0.5 + TAU * (o.progress / 100.0), 16, Color(0.95, 0.8, 0.25), 2.0)

	# 玩家朝向箭头
	var yaw := player.rotation.y
	var fwd := Vector2(-sin(yaw), -cos(yaw))
	var right := Vector2(-fwd.y, fwd.x)
	var tip := c + fwd * 8.0
	var l := c - fwd * 5.0 + right * 5.0
	var rr := c - fwd * 5.0 - right * 5.0
	draw_colored_polygon(PackedVector2Array([tip, l, rr]), Color(0.98, 0.95, 0.8))
	_text(Vector2(c.x - 30, c.y + r + 18), "N ↑", 12, Color(0.7, 0.74, 0.7), HORIZONTAL_ALIGNMENT_CENTER, 60)


func _draw_objective() -> void:
	if _objective_main == "":
		return
	draw_rect(Rect2(34, 26, 340, 62), Color(0, 0, 0, 0.32))
	_text(Vector2(46, 50), _objective_main, 17, Color(0.95, 0.92, 0.82))
	_text(Vector2(46, 74), _objective_sub, 13, Color(0.72, 0.76, 0.72))


func _draw_notifications() -> void:
	var y := size.y * 0.5 + 120.0
	for n in _notifications:
		var a: float = clampf(n["t"] / 1.2, 0.0, 1.0)
		_text(Vector2(size.x * 0.5 - 220, y), str(n["text"]), 15, Color(0.95, 0.93, 0.85, a),
			HORIZONTAL_ALIGNMENT_CENTER, 440)
		y += 24.0


func _draw_prompt() -> void:
	var p := player.interact_prompt()
	if p == "":
		return
	_text(Vector2(size.x * 0.5 - 120, size.y * 0.5 + 70), p, 16, Color(1, 0.92, 0.6),
		HORIZONTAL_ALIGNMENT_CENTER, 240)


func _draw_downed() -> void:
	if player.state != Player.State.DOWNED:
		return
	var s := size
	_text(Vector2(s.x * 0.5 - 200, s.y * 0.5 + 130), "倒地  失血 %.0fs" % player.bleed_time, 26,
		Color(0.95, 0.35, 0.3), HORIZONTAL_ALIGNMENT_CENTER, 400)
	_text(Vector2(s.x * 0.5 - 200, s.y * 0.5 + 158), "按住 空格 延缓失血", 15,
		Color(0.85, 0.8, 0.75), HORIZONTAL_ALIGNMENT_CENTER, 400)


func _draw_debrief() -> void:
	var s := size
	draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, 0.72))
	var cx := s.x * 0.5
	var y := s.y * 0.5 - 90.0
	if bool(_debrief.get("ok", false)):
		_text(Vector2(cx - 260, y), "撤离成功", 44, Color(0.85, 0.9, 0.75), HORIZONTAL_ALIGNMENT_CENTER, 520)
		_text(Vector2(cx - 260, y + 56), "信用点 +%d      经验 +%d      击杀 %d" % [
			int(_debrief["credits"]), int(_debrief["xp"]), int(_debrief["kills"])], 20,
			Color(0.9, 0.9, 0.85), HORIZONTAL_ALIGNMENT_CENTER, 520)
	else:
		_text(Vector2(cx - 260, y), "行动失败", 44, Color(0.85, 0.35, 0.3), HORIZONTAL_ALIGNMENT_CENTER, 520)
		_text(Vector2(cx - 260, y + 56), str(_debrief.get("reason", "")), 20,
			Color(0.9, 0.85, 0.82), HORIZONTAL_ALIGNMENT_CENTER, 520)
	_text(Vector2(cx - 260, y + 120), "按 回车 返回基地", 16, Color(0.75, 0.78, 0.75),
		HORIZONTAL_ALIGNMENT_CENTER, 520)
