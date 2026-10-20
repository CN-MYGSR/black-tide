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

# ---- 设置 ----
var mouse_sensitivity: float = 0.0022
var invert_y: bool = false
var master_volume: float = 0.8
var resolution: Vector2i = Vector2i(1600, 900)
var display_mode: int = 0            ## 0 窗口化 / 1 无边框全屏 / 2 全屏

const KILL_REWARD := 30              ## 击杀一个敌人的信用点（撤离时结算）


func _ready() -> void:
	_setup_input()
	load_profile()
	apply_audio()
	apply_display()


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
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return
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


func save_profile() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"credits": credits,
		"xp": xp,
		"level": level,
		"raids_survived": raids_survived,
		"raids_lost": raids_lost,
		"kills_total": kills_total,
		"loadout_weapon": loadout_weapon,
		"master_volume": master_volume,
		"resolution": [resolution.x, resolution.y],
		"display_mode": display_mode,
	}, "\t"))


# ---------------------------------------------------------------- 奖励
func add_xp(amount: int) -> void:
	xp += amount
	var need := level * 1000
	while xp >= need:
		xp -= need
		level += 1
		need = level * 1000


func end_raid(survived: bool, credits_gained: int) -> void:
	in_raid = false
	if survived:
		raids_survived += 1
		credits += credits_gained
		add_xp(int(credits_gained * 0.6))
	else:
		raids_lost += 1
		credits = int(credits * 0.75)
	raid_loot = 0
	raid_kills = 0
	raid_time = 0.0
	save_profile()
