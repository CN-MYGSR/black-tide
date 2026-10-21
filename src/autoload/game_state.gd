extends Node
## 存档 / 进度 / 运行时全局状态。
## 只放"跨场景需要活着"的东西，关卡内的临时状态交给各个节点自己管。

const SAVE_PATH := "user://profile.json"

# ---- 长期进度 ----
var credits: int = 2500
var xp: int = 0
var level: int = 1
var raids_survived: int = 0
var raids_lost: int = 0
var kills_total: int = 0
var loadout_weapon: String = "SM_Wep_Preset_A_Rifle_01"
var unlocked_weapons: Array[String] = [
	"SM_Wep_Preset_A_Rifle_01",
	"SM_Wep_Preset_B_SMG_01",
	"SM_Wep_Sniper_01",
	"SM_Wep_Shotgun_01",
	"SM_Wep_Pistol_01",
]

# ---- 本局状态 ----
var in_raid: bool = false
var raid_loot: int = 0
var raid_kills: int = 0
var raid_time: float = 0.0
var mission: Dictionary = {}
var difficulty: float = 1.0
var last_raid: Dictionary = {}
var saved_armory: Dictionary = {}

# ---- 设置 ----
var mouse_sensitivity: float = 0.0022
var invert_y: bool = false
var master_volume: float = 0.8
var resolution: Vector2i = Vector2i(1600, 900)
var display_mode: int = 0            ## 0 窗口化 / 1 无边框全屏 / 2 全屏
var graphics_quality: int = 0        ## 0 高品质 / 1 均衡 / 2 性能
var save_pending: bool = false
var _save_retry_t: float = 0.0

const KILL_REWARD := 30              ## 击杀一个敌人的信用点（撤离时结算）


func _ready() -> void:
	_setup_input()
	load_profile()
	apply_audio()
	apply_display()
	apply_graphics()
	get_tree().auto_accept_quit = false


func apply_audio() -> void:
	var bus := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_mute(bus, master_volume <= 0.001)
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(0.0001, master_volume)))


func apply_display() -> void:
	match display_mode:
		1:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		2:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		_:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_size(resolution)


func _process(delta: float) -> void:
	if in_raid:
		raid_time += delta
	if save_pending:
		_save_retry_t -= delta
		if _save_retry_t <= 0.0:
			_save_retry_t = 2.0
			if save_profile():
				EventBus.notify.emit("进度已保存")


func queue_save(delay: float = 0.25) -> void:
	save_pending = true
	_save_retry_t = delay


func request_quit() -> bool:
	if save_pending and not save_profile():
		EventBus.notify.emit("进度尚未保存，退出已取消；恢复磁盘写入后会自动重试")
		return false
	get_tree().quit()
	return true


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		request_quit()


func apply_graphics() -> void:
	var viewport := get_viewport()
	viewport.msaa_3d = [Viewport.MSAA_4X, Viewport.MSAA_2X, Viewport.MSAA_DISABLED][graphics_quality]
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	viewport.mesh_lod_threshold = [1.0, 1.5, 2.5][graphics_quality]
	RenderingServer.directional_shadow_atlas_set_size([4096, 2048, 1024][graphics_quality], true)
	var world_env := get_tree().get_first_node_in_group("world_env") as WorldEnvironment
	if world_env != null:
		world_env.environment.ssao_enabled = graphics_quality < 2
		world_env.environment.glow_enabled = graphics_quality == 0
		var sun := world_env.get_parent().get_node_or_null("Sun") as DirectionalLight3D
		if sun != null:
			sun.directional_shadow_max_distance = [220.0, 160.0, 100.0][graphics_quality]
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if graphics_quality == 0 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS


# ---------------------------------------------------------------- 输入表
## 输入映射写代码里，而不是 project.godot 里那一大坨 InputEventKey。
func _setup_input() -> void:
	_bind_keys("move_forward", [KEY_W])
	_bind_keys("move_back", [KEY_S])
	_bind_keys("move_left", [KEY_A])
	_bind_keys("move_right", [KEY_D])
	_bind_keys("jump", [KEY_SPACE])
	_bind_keys("sprint", [KEY_SHIFT])
	_bind_keys("crouch", [KEY_CTRL, KEY_C])
	_bind_keys("reload", [KEY_R])
	_bind_keys("interact", [KEY_F])
	_bind_keys("use_bandage", [KEY_4])
	_bind_keys("use_dressing", [KEY_5])
	_bind_keys("use_vitamins", [KEY_6])
	_bind_keys("toggle_view", [KEY_V])
	_bind_keys("toggle_map", [KEY_M])
	_bind_keys("slot_primary", [KEY_1])
	_bind_keys("slot_secondary", [KEY_2])
	_bind_keys("call_extract", [KEY_G])
	_bind_keys("toggle_nvg", [KEY_N])
	_bind_mouse("fire", MOUSE_BUTTON_LEFT)
	_bind_mouse("aim", MOUSE_BUTTON_RIGHT)


func _bind_keys(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


func _bind_mouse(action: String, button: int) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)


# ---------------------------------------------------------------- 存档
func load_profile() -> void:
	# Do not overwrite an unsaved settlement with an older disk snapshot.
	if save_pending:
		return
	var data: Dictionary = {}
	for path in [SAVE_PATH, SAVE_PATH + ".bak"]:
		if not FileAccess.file_exists(path):
			continue
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		var json := JSON.new()
		if json.parse(f.get_as_text()) == OK and profile_valid(json.data):
			data = json.data
			break
	if data.is_empty():
		return
	saved_armory = data.get("armory", {}) if data.get("armory") is Dictionary else {}
	credits = int(data.get("credits", credits))
	xp = int(data.get("xp", xp))
	level = int(data.get("level", level))
	raids_survived = int(data.get("raids_survived", 0))
	raids_lost = int(data.get("raids_lost", 0))
	kills_total = int(data.get("kills_total", 0))
	loadout_weapon = str(data.get("loadout_weapon", loadout_weapon))
	master_volume = float(data.get("master_volume", master_volume))
	var r: Array = data.get("resolution", [resolution.x, resolution.y])
	if r.size() >= 2:
		resolution = Vector2i(int(r[0]), int(r[1]))
	display_mode = int(data.get("display_mode", display_mode))
	graphics_quality = int(data.get("graphics_quality", graphics_quality))


static func profile_valid(data: Variant) -> bool:
	if not data is Dictionary or data.is_empty():
		return false
	for key in ["credits", "xp", "level", "raids_survived", "raids_lost", "kills_total", "display_mode", "graphics_quality"]:
		if data.has(key):
			var value: Variant = data[key]
			if not (value is int or value is float) or not is_finite(float(value)) or value < 0 or value > 9007199254740991 or floor(float(value)) != float(value):
				return false
	if data.get("level", 1) < 1 or data.get("display_mode", 0) > 2 or data.get("graphics_quality", 0) > 2:
		return false
	if data.has("loadout_weapon") and (not data["loadout_weapon"] is String or not ItemDB.WEAPONS.has(data["loadout_weapon"])):
		return false
	if data.has("master_volume"):
		var volume: Variant = data["master_volume"]
		if not (volume is int or volume is float) or not is_finite(float(volume)) or volume < 0 or volume > 1:
			return false
	if data.has("resolution"):
		var size: Variant = data["resolution"]
		if not size is Array or size.size() != 2:
			return false
		for value in size:
			if not (value is int or value is float) or not is_finite(float(value)) or value < 320 or value > 16384 or floor(float(value)) != float(value):
				return false
	if data.has("armory"):
		if not data["armory"] is Dictionary:
			return false
		var armory: Dictionary = data["armory"]
		var tables := {"owned_weapons": ItemDB.WEAPONS, "owned_armor": ItemDB.ARMOR,
			"owned_helmets": ItemDB.HELMET, "owned_nvg": ItemDB.NVG, "owned_camos": ItemDB.CAMO, "owned_vehicles": ItemDB.VEHICLES}
		for key in tables:
			if armory.has(key):
				if not armory[key] is Array:
					return false
				for id in armory[key]:
					if not id is String or not tables[key].has(id):
						return false
		var equipped := {"primary": ItemDB.WEAPONS, "secondary": ItemDB.WEAPONS, "armor": ItemDB.ARMOR, "helmet": ItemDB.HELMET, "nvg": ItemDB.NVG, "camo": ItemDB.CAMO, "vehicle": ItemDB.VEHICLES}
		for key in equipped:
			var table: Dictionary = equipped[key]
			if armory.has(key) and (not armory[key] is String or not table.has(armory[key])):
				return false
		for key in ["attachments", "owned_attachments"]:
			if not armory.get(key, {}) is Dictionary:
				return false
			for slot in armory.get(key, {}):
				if not ItemDB.ATTACHMENTS.has(slot):
					return false
				var ids: Variant = armory[key][slot]
				if key == "owned_attachments" and not ids is Array:
					return false
				for id in (ids if key == "owned_attachments" else [ids]):
					if not id is String or not ItemDB.ATTACHMENTS[slot]["items"].has(id):
						return false
	return true


func save_profile() -> bool:
	var armory := get_node_or_null("/root/Loadout")
	var data := {
		"credits": credits, "xp": xp, "level": level,
		"raids_survived": raids_survived, "raids_lost": raids_lost,
		"kills_total": kills_total, "loadout_weapon": loadout_weapon,
		"master_volume": master_volume,
		"resolution": [resolution.x, resolution.y], "display_mode": display_mode,
		"graphics_quality": graphics_quality,
		"armory": armory.to_data() if armory != null else saved_armory,
	}
	var temp := SAVE_PATH + ".tmp"
	var f := FileAccess.open(temp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.flush()
	var error := f.get_error()
	f.close()
	if error != OK:
		return false
	# 保留上一份可用存档，原文件在临时文件完整写好前不动。
	if FileAccess.file_exists(SAVE_PATH):
		var previous := JSON.new()
		var valid := previous.parse(FileAccess.get_file_as_string(SAVE_PATH)) == OK and profile_valid(previous.data)
		if valid and DirAccess.copy_absolute(SAVE_PATH, SAVE_PATH + ".bak") != OK:
			return false
	if DirAccess.rename_absolute(temp, SAVE_PATH) != OK:
		return false
	saved_armory = data["armory"].duplicate(true)
	save_pending = false
	return true


# ---------------------------------------------------------------- 奖励
func add_xp(amount: int) -> void:
	xp += amount
	var need := level * 1000
	while xp >= need:
		xp -= need
		level += 1
		need = level * 1000


func xp_for_credits(amount: int) -> int:
	return int(amount * 0.6)


func end_raid(survived: bool, credits_gained: int) -> bool:
	if not in_raid:
		return false
	in_raid = false
	last_raid = {"ok": survived, "credits": credits_gained if survived else 0,
		"xp": xp_for_credits(credits_gained) if survived else 0, "kills": raid_kills}
	if survived:
		raids_survived += 1
		credits += credits_gained
		add_xp(last_raid["xp"])
	else:
		raids_lost += 1
		credits = int(credits * 0.75)
	raid_loot = 0
	raid_kills = 0
	raid_time = 0.0
	if not save_profile():
		queue_save(2.0)
		EventBus.notify.emit("存档失败，本次结算尚未写入磁盘，请勿退出")
	return true
