class_name ItemDB
extends RefCounted
## 全部装备数据：武器 / 配件 / 护甲 / 头盔 / 夜视仪 / 涂装。
##
## 名字全部用现实装备名。模型是 POLYGON 的低模，只能"长得像"，
## 但口径、射速、弹匣、射击模式这些数值是按真枪来的。

# ---------------------------------------------------------------- 武器
## fire_mode: auto 全自动 / semi 半自动 / burst 三连发
const WEAPONS := {
	# ---------- 美械 / NATO ----------
	"SM_Wep_Preset_A_Rifle_01": {
		"label": "M4A1 卡宾枪", "short": "M4A1", "caliber": "5.56×45mm", "origin": "us",
		"fire_mode": "auto", "damage": 26.0, "rpm": 700.0, "mag": 30, "reserve": 210,
		"spread_hip": 2.6, "spread_ads": 0.35, "recoil": 1.5, "recoil_h": 0.5,
		"range": 300.0, "reload": 2.1, "zoom": 26.0, "falloff": 0.55, "price": 0,
	},
	"SM_Wep_Preset_A_Rifle_02": {
		"label": "M16A4 步枪", "short": "M16A4", "caliber": "5.56×45mm", "origin": "us",
		"fire_mode": "burst", "burst": 3, "damage": 28.0, "rpm": 800.0, "mag": 30, "reserve": 210,
		"spread_hip": 2.2, "spread_ads": 0.28, "recoil": 1.4, "recoil_h": 0.4,
		"range": 340.0, "reload": 2.3, "zoom": 24.0, "falloff": 0.5, "price": 2400,
	},
	"SM_Wep_Preset_A_Rifle_03": {
		"label": "HK416 突击步枪", "short": "HK416", "caliber": "5.56×45mm", "origin": "us",
		"fire_mode": "auto", "damage": 27.0, "rpm": 850.0, "mag": 30, "reserve": 210,
		"spread_hip": 2.4, "spread_ads": 0.3, "recoil": 1.3, "recoil_h": 0.42,
		"range": 320.0, "reload": 2.0, "zoom": 26.0, "falloff": 0.52, "price": 3800,
	},
	"SM_Wep_Preset_A_Complex_01": {
		"label": "Mk18 MOD1 近战卡宾", "short": "Mk18", "caliber": "5.56×45mm", "origin": "us",
		"fire_mode": "auto", "damage": 25.0, "rpm": 800.0, "mag": 30, "reserve": 180,
		"spread_hip": 2.8, "spread_ads": 0.4, "recoil": 1.6, "recoil_h": 0.55,
		"range": 220.0, "reload": 1.9, "zoom": 26.0, "falloff": 0.62, "price": 2600,
	},
	"SM_Wep_Preset_A_SMG_01": {
		"label": "MP5A3 冲锋枪", "short": "MP5A3", "caliber": "9×19mm", "origin": "us",
		"fire_mode": "auto", "damage": 19.0, "rpm": 800.0, "mag": 30, "reserve": 240,
		"spread_hip": 3.0, "spread_ads": 0.55, "recoil": 1.0, "recoil_h": 0.4,
		"range": 150.0, "reload": 1.8, "zoom": 22.0, "falloff": 0.7, "price": 1200,
	},
	"SM_Wep_Preset_A_Heavy_01": {
		"label": "M249 SAW 班用机枪", "short": "M249", "caliber": "5.56×45mm", "origin": "us",
		"fire_mode": "auto", "damage": 24.0, "rpm": 750.0, "mag": 100, "reserve": 300,
		"spread_hip": 5.0, "spread_ads": 0.9, "recoil": 2.0, "recoil_h": 0.8,
		"range": 320.0, "reload": 4.6, "zoom": 24.0, "falloff": 0.5, "price": 4200,
	},
	"SM_Wep_Preset_A_Sniper_01": {
		"label": "M24 SWS 狙击步枪", "short": "M24", "caliber": "7.62×51mm", "origin": "us",
		"fire_mode": "semi", "damage": 92.0, "rpm": 50.0, "mag": 5, "reserve": 40,
		"spread_hip": 8.0, "spread_ads": 0.05, "recoil": 4.5, "recoil_h": 0.9,
		"range": 700.0, "reload": 3.2, "zoom": 12.0, "falloff": 0.15, "price": 3600,
	},
	"SM_Wep_MachineGun_USA_01": {
		"label": "M60E4 通用机枪", "short": "M60E4", "caliber": "7.62×51mm", "origin": "us",
		"fire_mode": "auto", "damage": 34.0, "rpm": 600.0, "mag": 100, "reserve": 300,
		"spread_hip": 6.0, "spread_ads": 1.1, "recoil": 2.8, "recoil_h": 1.0,
		"range": 360.0, "reload": 5.2, "zoom": 24.0, "falloff": 0.45, "price": 4600,
	},
	"SM_Wep_Pistol_01": {
		"label": "M9 手枪", "short": "M9", "caliber": "9×19mm", "origin": "us",
		"fire_mode": "semi", "damage": 22.0, "rpm": 300.0, "mag": 15, "reserve": 90,
		"spread_hip": 2.2, "spread_ads": 0.8, "recoil": 1.6, "recoil_h": 0.6,
		"range": 90.0, "reload": 1.6, "zoom": 28.0, "falloff": 0.6, "price": 0,
	},
	"SM_Wep_Pistol_Metal_01": {
		"label": "M1911A1 手枪", "short": "M1911", "caliber": ".45 ACP", "origin": "us",
		"fire_mode": "semi", "damage": 32.0, "rpm": 260.0, "mag": 7, "reserve": 56,
		"spread_hip": 2.4, "spread_ads": 0.9, "recoil": 2.2, "recoil_h": 0.8,
		"range": 80.0, "reload": 1.8, "zoom": 28.0, "falloff": 0.65, "price": 600,
	},
	"SM_Wep_Shotgun_01": {
		"label": "M870 泵动霰弹枪", "short": "M870", "caliber": "12 Gauge", "origin": "us",
		"fire_mode": "semi", "damage": 16.0, "rpm": 75.0, "mag": 7, "reserve": 42,
		"spread_hip": 6.5, "spread_ads": 4.5, "recoil": 3.2, "recoil_h": 1.1,
		"range": 45.0, "reload": 2.8, "zoom": 30.0, "falloff": 0.85, "pellets": 8, "price": 1500,
	},
	"SM_Wep_RocketLauncher_01": {
		"label": "M72 LAW 火箭筒", "short": "M72", "caliber": "66mm", "origin": "us",
		"fire_mode": "semi", "damage": 180.0, "rpm": 20.0, "mag": 1, "reserve": 2,
		"spread_hip": 3.0, "spread_ads": 1.0, "recoil": 6.0, "recoil_h": 1.5,
		"range": 200.0, "reload": 4.0, "zoom": 30.0, "falloff": 0.3, "price": 5200,
	},

	# ---------- 俄械 ----------
	"SM_Wep_Preset_B_Rifle_01": {
		"label": "AK-74M 突击步枪", "short": "AK-74M", "caliber": "5.45×39mm", "origin": "ru",
		"fire_mode": "auto", "damage": 25.0, "rpm": 650.0, "mag": 30, "reserve": 210,
		"spread_hip": 2.9, "spread_ads": 0.45, "recoil": 1.8, "recoil_h": 0.6,
		"range": 300.0, "reload": 2.4, "zoom": 26.0, "falloff": 0.55, "price": 1800,
	},
	"SM_Wep_Preset_B_Rifle_02": {
		"label": "AKM 突击步枪", "short": "AKM", "caliber": "7.62×39mm", "origin": "ru",
		"fire_mode": "auto", "damage": 33.0, "rpm": 600.0, "mag": 30, "reserve": 180,
		"spread_hip": 3.6, "spread_ads": 0.6, "recoil": 2.6, "recoil_h": 0.9,
		"range": 280.0, "reload": 2.6, "zoom": 26.0, "falloff": 0.5, "price": 1600,
	},
	"SM_Wep_Preset_B_Rifle_03": {
		"label": "AK-12 突击步枪", "short": "AK-12", "caliber": "5.45×39mm", "origin": "ru",
		"fire_mode": "burst", "burst": 3, "damage": 26.0, "rpm": 700.0, "mag": 30, "reserve": 210,
		"spread_hip": 2.6, "spread_ads": 0.38, "recoil": 1.7, "recoil_h": 0.55,
		"range": 310.0, "reload": 2.2, "zoom": 26.0, "falloff": 0.52, "price": 3000,
	},
	"SM_Wep_Preset_B_Complex_01": {
		"label": "AK-105 短突击步枪", "short": "AK-105", "caliber": "5.45×39mm", "origin": "ru",
		"fire_mode": "auto", "damage": 24.0, "rpm": 650.0, "mag": 30, "reserve": 180,
		"spread_hip": 3.1, "spread_ads": 0.5, "recoil": 1.9, "recoil_h": 0.65,
		"range": 240.0, "reload": 2.3, "zoom": 26.0, "falloff": 0.6, "price": 2000,
	},
	"SM_Wep_Preset_B_SMG_01": {
		"label": "PP-19-01 勇士冲锋枪", "short": "PP-19", "caliber": "9×19mm", "origin": "ru",
		"fire_mode": "auto", "damage": 20.0, "rpm": 750.0, "mag": 30, "reserve": 240,
		"spread_hip": 3.1, "spread_ads": 0.6, "recoil": 1.1, "recoil_h": 0.45,
		"range": 140.0, "reload": 2.0, "zoom": 22.0, "falloff": 0.72, "price": 1300,
	},
	"SM_Wep_Preset_B_Heavy_01": {
		"label": "PKM 通用机枪", "short": "PKM", "caliber": "7.62×54mmR", "origin": "ru",
		"fire_mode": "auto", "damage": 36.0, "rpm": 650.0, "mag": 100, "reserve": 300,
		"spread_hip": 6.0, "spread_ads": 1.1, "recoil": 3.0, "recoil_h": 1.1,
		"range": 380.0, "reload": 5.4, "zoom": 24.0, "falloff": 0.45, "price": 4400,
	},
	"SM_Wep_Preset_B_Sniper_01": {
		"label": "SVD 德拉贡诺夫", "short": "SVD", "caliber": "7.62×54mmR", "origin": "ru",
		"fire_mode": "semi", "damage": 80.0, "rpm": 60.0, "mag": 10, "reserve": 60,
		"spread_hip": 7.5, "spread_ads": 0.08, "recoil": 4.2, "recoil_h": 0.9,
		"range": 650.0, "reload": 3.0, "zoom": 12.0, "falloff": 0.18, "price": 3400,
	},
	"SM_Wep_Rifle_01": {
		"label": "AK-47 突击步枪", "short": "AK-47", "caliber": "7.62×39mm", "origin": "ru",
		"fire_mode": "auto", "damage": 35.0, "rpm": 600.0, "mag": 30, "reserve": 180,
		"spread_hip": 4.0, "spread_ads": 0.7, "recoil": 2.9, "recoil_h": 1.0,
		"range": 260.0, "reload": 2.7, "zoom": 26.0, "falloff": 0.5, "price": 1400,
	},
	"SM_Wep_Sniper_01": {
		"label": "SVD-S 短管狙击枪", "short": "SVD-S", "caliber": "7.62×54mmR", "origin": "ru",
		"fire_mode": "semi", "damage": 78.0, "rpm": 62.0, "mag": 10, "reserve": 60,
		"spread_hip": 7.0, "spread_ads": 0.1, "recoil": 4.0, "recoil_h": 0.85,
		"range": 560.0, "reload": 2.9, "zoom": 14.0, "falloff": 0.2, "price": 3200,
	},
	"SM_Wep_Pistol_Small_01": {
		"label": "PM 马卡洛夫手枪", "short": "PM", "caliber": "9×18mm", "origin": "ru",
		"fire_mode": "semi", "damage": 18.0, "rpm": 320.0, "mag": 8, "reserve": 48,
		"spread_hip": 2.6, "spread_ads": 0.9, "recoil": 1.4, "recoil_h": 0.5,
		"range": 70.0, "reload": 1.5, "zoom": 28.0, "falloff": 0.7, "price": 300,
	},
	"SM_Wep_MachineGun_Bandit_01": {
		"label": "RPK-74 轻机枪", "short": "RPK-74", "caliber": "5.45×39mm", "origin": "ru",
		"fire_mode": "auto", "damage": 27.0, "rpm": 600.0, "mag": 45, "reserve": 270,
		"spread_hip": 4.6, "spread_ads": 0.85, "recoil": 2.2, "recoil_h": 0.8,
		"range": 330.0, "reload": 3.4, "zoom": 24.0, "falloff": 0.5, "price": 2800,
	},
	"SM_Wep_RPG_01": {
		"label": "RPG-7 火箭筒", "short": "RPG-7", "caliber": "85mm", "origin": "ru",
		"fire_mode": "semi", "damage": 200.0, "rpm": 18.0, "mag": 1, "reserve": 3,
		"spread_hip": 3.5, "spread_ads": 1.2, "recoil": 6.5, "recoil_h": 1.6,
		"range": 220.0, "reload": 4.5, "zoom": 30.0, "falloff": 0.3, "price": 5600,
	},
}


# ---------------------------------------------------------------- 配件
## 每个槽位选一个；mods 是乘算/加算修正
const ATTACHMENTS := {
	"optic": {
		"label": "瞄具",
		"items": {
			"iron": {"label": "机械瞄具", "price": 0, "mods": {}},
			"eotech": {"label": "EOTech 552 全息", "price": 450,
				"mods": {"spread_mult": 0.88, "zoom": 22.0}},
			"t2": {"label": "Aimpoint T2 红点", "price": 600,
				"mods": {"spread_mult": 0.84, "zoom": 20.0, "ads_speed": 1.15}},
			"acog": {"label": "ACOG TA31 4×32", "price": 900,
				"mods": {"spread_mult": 0.78, "zoom": 14.0, "ads_speed": 0.85}},
		},
	},
	"muzzle": {
		"label": "枪口",
		"items": {
			"none": {"label": "标准枪口", "price": 0, "mods": {}},
			"comp": {"label": "战术补偿器", "price": 380,
				"mods": {"recoil_mult": 0.78, "spread_mult": 0.95}},
			"suppressor": {"label": "消音器", "price": 750,
				"mods": {"recoil_mult": 0.88, "damage_mult": 0.93, "range_mult": 0.9}},
		},
	},
	"grip": {
		"label": "握把",
		"items": {
			"none": {"label": "标准护木", "price": 0, "mods": {}},
			"vertical": {"label": "垂直握把", "price": 320,
				"mods": {"recoil_mult": 0.84}},
			"laser": {"label": "PEQ-15 激光指示", "price": 520,
				"mods": {"spread_hip_mult": 0.7}},
		},
	},
	"mag": {
		"label": "弹匣",
		"items": {
			"std": {"label": "标准弹匣", "price": 0, "mods": {}},
			"ext": {"label": "扩容弹匣", "price": 400,
				"mods": {"mag_add": 10, "reload_mult": 1.2}},
			"fast": {"label": "快拔弹匣", "price": 460,
				"mods": {"reload_mult": 0.78}},
		},
	},
	"stock": {
		"label": "枪托",
		"items": {
			"std": {"label": "标准枪托", "price": 0, "mods": {}},
			"tactical": {"label": "战术枪托", "price": 360,
				"mods": {"recoil_mult": 0.8, "ads_speed": 0.9}},
			"light": {"label": "轻量化枪托", "price": 340,
				"mods": {"ads_speed": 1.2, "recoil_mult": 1.08}},
		},
	},
}


# ---------------------------------------------------------------- 护甲
const ARMOR := {
	"none": {"label": "无护甲", "price": 0, "armor": 0.0, "speed_mult": 1.0, "class": "—"},
	"pasgt": {"label": "PASGT 防弹背心", "price": 800, "armor": 35.0,
		"speed_mult": 0.98, "class": "NIJ II"},
	"iba": {"label": "IBA 拦截者防弹衣", "price": 1800, "armor": 60.0,
		"speed_mult": 0.95, "class": "NIJ IIIA"},
	"cpc": {"label": "Crye CPC 战术携板背心", "price": 3200, "armor": 90.0,
		"speed_mult": 0.92, "class": "NIJ IV"},
	"6b45": {"label": "6B45 防弹衣", "price": 2200, "armor": 75.0,
		"speed_mult": 0.93, "class": "GOST 5"},
}

const HELMET := {
	"none": {"label": "无头盔", "price": 0, "armor": 0.0},
	"pasgt_h": {"label": "PASGT 头盔", "price": 400, "armor": 12.0},
	"fast": {"label": "FAST MT 战术头盔", "price": 1200, "armor": 20.0},
	"6b47": {"label": "6B47 头盔", "price": 900, "armor": 18.0},
}

const NVG := {
	"none": {"label": "无夜视设备", "price": 0, "gain": 0.0},
	"pvs14": {"label": "AN/PVS-14 单目夜视仪", "price": 2400, "gain": 1.0},
	"pvs31": {"label": "AN/PVS-31 双目夜视仪", "price": 4800, "gain": 1.6},
}

## 载具：买下来后会停在基地里，靠近按 F 上车
const VEHICLES := {
	"none": {"label": "不配车", "price": 0, "model": "", "kind": "none",
		"speed": 0.0, "armor": 0.0, "seats": 0},
	"SM_Veh_SUV_01": {"label": "民用 SUV", "price": 900, "kind": "ground",
		"speed": 22.0, "armor": 0.0, "seats": 4,
		"desc": "跑得快，但一枪就穿。适合赶路。"},
	"SM_Veh_Pickup_Technical_01": {"label": "武装皮卡（Technical）", "price": 2200, "kind": "ground",
		"speed": 19.0, "armor": 20.0, "seats": 3,
		"desc": "货斗带机枪架，便宜耐造。"},
	"SM_Veh_Light_Armored_Car_01": {"label": "轻型装甲车", "price": 4200, "kind": "ground",
		"speed": 17.0, "armor": 60.0, "seats": 4,
		"desc": "挡得住步枪弹。"},
	"SM_Veh_APC_01": {"label": "装甲运兵车", "price": 7000, "kind": "ground",
		"speed": 14.0, "armor": 120.0, "seats": 8,
		"desc": "移动堡垒，慢。"},
	"SM_Veh_Helicopter_Transport_01": {"label": "UH-60 运输直升机", "price": 14000, "kind": "air",
		"speed": 38.0, "armor": 40.0, "seats": 8,
		"desc": "能飞越整张地图。W/S 升降，A/D 转向。"},
	"SM_Veh_Helicopter_Attack_01": {"label": "AH-64 武装直升机", "price": 22000, "kind": "air",
		"speed": 45.0, "armor": 70.0, "seats": 2,
		"desc": "更快更硬，但只有两个座位。"},
}


## 涂装：预设色，作用在武器/护甲的 albedo 上
const CAMO := {
	"factory": {"label": "原厂灰", "color": Color(1.0, 1.0, 1.0), "price": 0},
	"desert": {"label": "沙漠黄", "color": Color(0.78, 0.66, 0.44), "price": 300},
	"jungle": {"label": "丛林绿", "color": Color(0.42, 0.50, 0.34), "price": 300},
	"urban": {"label": "城市黑", "color": Color(0.30, 0.31, 0.33), "price": 300},
}


# ---------------------------------------------------------------- 查询
static func weapon(id: String) -> Dictionary:
	return WEAPONS.get(id, {})


static func weapon_ids_by_origin(origin: String) -> Array:
	var out: Array = []
	for k in WEAPONS.keys():
		if str(WEAPONS[k]["origin"]) == origin:
			out.append(k)
	return out


static func attachment(slot: String, id: String) -> Dictionary:
	var s: Dictionary = ATTACHMENTS.get(slot, {})
	var items: Dictionary = s.get("items", {})
	return items.get(id, {})


static func attachment_label(slot: String, id: String) -> String:
	return str(attachment(slot, id).get("label", id))


## 把基础武器 + 已装配件算成实际数值
static func resolve(weapon_id: String, atts: Dictionary) -> Dictionary:
	var base: Dictionary = weapon(weapon_id).duplicate(true)
	if base.is_empty():
		return base
	base["id"] = weapon_id
	var spread_mult := 1.0
	var spread_hip_mult := 1.0
	var recoil_mult := 1.0
	var damage_mult := 1.0
	var range_mult := 1.0
	var reload_mult := 1.0
	var ads_speed := 1.0
	var mag_add := 0
	var zoom_override := -1.0

	for slot in atts.keys():
		var item: Dictionary = attachment(str(slot), str(atts[slot]))
		var m: Dictionary = item.get("mods", {})
		spread_mult *= float(m.get("spread_mult", 1.0))
		spread_hip_mult *= float(m.get("spread_hip_mult", 1.0))
		recoil_mult *= float(m.get("recoil_mult", 1.0))
		damage_mult *= float(m.get("damage_mult", 1.0))
		range_mult *= float(m.get("range_mult", 1.0))
		reload_mult *= float(m.get("reload_mult", 1.0))
		ads_speed *= float(m.get("ads_speed", 1.0))
		mag_add += int(m.get("mag_add", 0))
		if m.has("zoom"):
			zoom_override = float(m["zoom"])

	base["spread_ads"] = float(base["spread_ads"]) * spread_mult
	base["spread_hip"] = float(base["spread_hip"]) * spread_mult * spread_hip_mult
	base["recoil"] = float(base["recoil"]) * recoil_mult
	base["recoil_h"] = float(base["recoil_h"]) * recoil_mult
	base["damage"] = float(base["damage"]) * damage_mult
	base["range"] = float(base["range"]) * range_mult
	base["reload"] = float(base["reload"]) * reload_mult
	base["mag"] = int(base["mag"]) + mag_add
	base["ads_speed"] = ads_speed
	if zoom_override > 0.0:
		base["zoom"] = zoom_override
	return base
