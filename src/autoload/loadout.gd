extends Node
## 军械库：谁买了什么、当前装什么、涂装、载具，以及买卖逻辑。
## 单独一个 autoload，是因为主菜单和战斗场景都要读它。

const SAVE_PATH := "user://armory.json"

## 已拥有
var owned_weapons: Array[String] = []
var owned_attachments: Dictionary = {}   ## slot -> Array[String]
var owned_armor: Array[String] = []
var owned_helmets: Array[String] = []
var owned_nvg: Array[String] = []
var owned_camos: Array[String] = []
var owned_vehicles: Array[String] = []

## 当前装备
var primary: String = "SM_Wep_Preset_A_Rifle_01"
var secondary: String = "SM_Wep_Pistol_01"
var attachments: Dictionary = {
	"optic": "iron", "muzzle": "none", "grip": "none", "mag": "std", "stock": "std",
}
var armor: String = "none"
var helmet: String = "none"
var nvg: String = "none"
var camo: String = "factory"
var vehicle: String = "none"


func _ready() -> void:
	_reset_defaults()
	load_data()


func _reset_defaults() -> void:
	owned_weapons = ["SM_Wep_Preset_A_Rifle_01", "SM_Wep_Pistol_01"]
	owned_armor = ["none"]
	owned_helmets = ["none"]
	owned_nvg = ["none"]
	owned_camos = ["factory"]
	owned_vehicles = ["none"]
	owned_attachments = {}
	for slot in ItemDB.ATTACHMENTS.keys():
		var items: Dictionary = ItemDB.ATTACHMENTS[slot]["items"]
		var free: Array[String] = []
		for id in items.keys():
			if int(items[id].get("price", 0)) == 0:
				free.append(str(id))
		owned_attachments[slot] = free


# ---------------------------------------------------------------- 查询
func has_weapon(id: String) -> bool:
	return owned_weapons.has(id)


func has_attachment(slot: String, id: String) -> bool:
	var arr: Array = owned_attachments.get(slot, [])
	return arr.has(id)


func has_any(category: String, id: String) -> bool:
	match category:
		"armor":
			return owned_armor.has(id)
		"helmet":
			return owned_helmets.has(id)
		"nvg":
			return owned_nvg.has(id)
		"camo":
			return owned_camos.has(id)
		"vehicle":
			return owned_vehicles.has(id)
	return false


func resolved_primary() -> Dictionary:
	return ItemDB.resolve(primary, attachments)


func resolved_secondary() -> Dictionary:
	return ItemDB.resolve(secondary, {})


func armor_value() -> float:
	var a: Dictionary = ItemDB.ARMOR.get(armor, {})
	var h: Dictionary = ItemDB.HELMET.get(helmet, {})
	return float(a.get("armor", 0.0)) + float(h.get("armor", 0.0))


func speed_mult() -> float:
	var a: Dictionary = ItemDB.ARMOR.get(armor, {})
	return float(a.get("speed_mult", 1.0))


func camo_color() -> Color:
	return ItemDB.CAMO.get(camo, {}).get("color", Color.WHITE)


func nvg_gain() -> float:
	return float(ItemDB.NVG.get(nvg, {}).get("gain", 0.0))


# ---------------------------------------------------------------- 购买
## 返回 {ok: bool, msg: String}
func buy(category: String, id: String) -> Dictionary:
	if not _valid_item(category, id):
		return {"ok": false, "msg": "无效的物品"}
	if _owned(category, id):
		return {"ok": false, "msg": "已经拥有了"}
	var price := _price(category, id)
	if GameState.credits < price:
		return {"ok": false, "msg": "信用点不足（还差 %d）" % (price - GameState.credits)}
	var before := to_data().duplicate(true)
	GameState.credits -= price
	_grant(category, id)
	if not save_data():
		GameState.credits += price
		apply_data(before)
		return {"ok": false, "msg": "存档失败，购买已取消，信用点未扣除"}
	return {"ok": true, "msg": "已购买 %s（-%d）" % [_label(category, id), price]}


func _valid_item(category: String, id: String) -> bool:
	if category == "weapon":
		return ItemDB.WEAPONS.has(id)
	if category == "attachment":
		var parts := id.split(":")
		return parts.size() == 2 and not ItemDB.attachment(parts[0], parts[1]).is_empty()
	var tables := {"armor": ItemDB.ARMOR, "helmet": ItemDB.HELMET,
		"nvg": ItemDB.NVG, "camo": ItemDB.CAMO, "vehicle": ItemDB.VEHICLES}
	return tables.has(category) and tables[category].has(id)


func _owned(category: String, id: String) -> bool:
	match category:
		"weapon":
			return owned_weapons.has(id)
		"attachment":
			var parts := id.split(":")
			return has_attachment(parts[0], parts[1])
		_:
			return has_any(category, id)


func _grant(category: String, id: String) -> void:
	match category:
		"weapon":
			owned_weapons.append(id)
		"attachment":
			var parts := id.split(":")
			var slot := parts[0]
			if not owned_attachments.has(slot):
				owned_attachments[slot] = []
			(owned_attachments[slot] as Array).append(parts[1])
		"armor":
			owned_armor.append(id)
		"helmet":
			owned_helmets.append(id)
		"nvg":
			owned_nvg.append(id)
		"camo":
			owned_camos.append(id)
		"vehicle":
			owned_vehicles.append(id)


func _price(category: String, id: String) -> int:
	match category:
		"weapon":
			return int(ItemDB.weapon(id).get("price", 0))
		"attachment":
			var parts := id.split(":")
			return int(ItemDB.attachment(parts[0], parts[1]).get("price", 0))
		"armor":
			return int(ItemDB.ARMOR.get(id, {}).get("price", 0))
		"helmet":
			return int(ItemDB.HELMET.get(id, {}).get("price", 0))
		"nvg":
			return int(ItemDB.NVG.get(id, {}).get("price", 0))
		"camo":
			return int(ItemDB.CAMO.get(id, {}).get("price", 0))
		"vehicle":
			return int(ItemDB.VEHICLES.get(id, {}).get("price", 0))
	return 0


func _label(category: String, id: String) -> String:
	match category:
		"weapon":
			return str(ItemDB.weapon(id).get("label", id))
		"attachment":
			var parts := id.split(":")
			return ItemDB.attachment_label(parts[0], parts[1])
		"armor":
			return str(ItemDB.ARMOR.get(id, {}).get("label", id))
		"helmet":
			return str(ItemDB.HELMET.get(id, {}).get("label", id))
		"nvg":
			return str(ItemDB.NVG.get(id, {}).get("label", id))
		"camo":
			return str(ItemDB.CAMO.get(id, {}).get("label", id))
		"vehicle":
			return str(ItemDB.VEHICLES.get(id, {}).get("label", id))
	return id


# ---------------------------------------------------------------- 装备
func equip_weapon(slot: int, id: String) -> void:
	if not owned_weapons.has(id):
		return
	if slot == 0:
		primary = id
	else:
		secondary = id
	save_data()


func equip_attachment(slot: String, id: String) -> void:
	if not has_attachment(slot, id):
		return
	attachments[slot] = id
	save_data()


func equip_simple(category: String, id: String) -> void:
	if not has_any(category, id):
		return
	match category:
		"armor":
			armor = id
		"helmet":
			helmet = id
		"nvg":
			nvg = id
		"camo":
			camo = id
		"vehicle":
			vehicle = id
	save_data()


# ---------------------------------------------------------------- 存档
func save_data() -> bool:
	var ok := GameState.save_profile()
	if not ok:
		EventBus.notify.emit("军械库存档失败，请检查磁盘和存档目录")
	return ok


func to_data() -> Dictionary:
	return {
		"owned_weapons": owned_weapons,
		"owned_attachments": owned_attachments,
		"owned_armor": owned_armor,
		"owned_helmets": owned_helmets,
		"owned_nvg": owned_nvg,
		"owned_camos": owned_camos,
		"owned_vehicles": owned_vehicles,
		"primary": primary,
		"secondary": secondary,
		"attachments": attachments,
		"armor": armor,
		"helmet": helmet,
		"nvg": nvg,
		"camo": camo,
		"vehicle": vehicle,
	}


func load_data() -> void:
	if not GameState.saved_armory.is_empty():
		apply_data(GameState.saved_armory)
		return
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	if typeof(d) != TYPE_DICTIONARY:
		return
	apply_data(d)


func apply_data(d: Dictionary) -> void:
	owned_weapons = _arr(d.get("owned_weapons", owned_weapons))
	owned_armor = _arr(d.get("owned_armor", owned_armor))
	owned_helmets = _arr(d.get("owned_helmets", owned_helmets))
	owned_nvg = _arr(d.get("owned_nvg", owned_nvg))
	owned_camos = _arr(d.get("owned_camos", owned_camos))
	owned_vehicles = _arr(d.get("owned_vehicles", owned_vehicles))
	var oa: Variant = d.get("owned_attachments", {})
	if typeof(oa) == TYPE_DICTIONARY:
		owned_attachments = oa
	primary = str(d.get("primary", primary))
	secondary = str(d.get("secondary", secondary))
	var at: Variant = d.get("attachments", {})
	if typeof(at) == TYPE_DICTIONARY:
		for k in at.keys():
			attachments[str(k)] = str(at[k])
	armor = str(d.get("armor", armor))
	helmet = str(d.get("helmet", helmet))
	nvg = str(d.get("nvg", nvg))
	camo = str(d.get("camo", camo))
	vehicle = str(d.get("vehicle", vehicle))


func _arr(v: Variant) -> Array[String]:
	var out: Array[String] = []
	if typeof(v) == TYPE_ARRAY:
		for x in v:
			out.append(str(x))
	return out
