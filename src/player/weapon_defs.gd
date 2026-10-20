class_name WeaponDefs
extends RefCounted
## 武器数值表。模型名直接用转换后的资产名，方便"换模型即换枪"。

const DATA := {
	"SM_Wep_Preset_A_Rifle_01": {
		"label": "AR-15 突击步枪", "short": "AR-15", "damage": 26.0, "rpm": 640.0,
		"mag": 30, "reserve": 180, "spread_hip": 2.6, "spread_ads": 0.35,
		"recoil": 1.5, "recoil_h": 0.5, "range": 260.0, "auto": true,
		"reload": 2.2, "zoom": 26.0, "falloff": 0.55,
	},
	"SM_Wep_Preset_B_SMG_01": {
		"label": "MP5 冲锋枪", "short": "MP5", "damage": 19.0, "rpm": 800.0,
		"mag": 30, "reserve": 210, "spread_hip": 3.4, "spread_ads": 0.6,
		"recoil": 1.1, "recoil_h": 0.45, "range": 140.0, "auto": true,
		"reload": 1.9, "zoom": 22.0, "falloff": 0.7,
	},
	"SM_Wep_Sniper_01": {
		"label": "M24 狙击步枪", "short": "M24", "damage": 92.0, "rpm": 48.0,
		"mag": 5, "reserve": 40, "spread_hip": 8.0, "spread_ads": 0.05,
		"recoil": 4.5, "recoil_h": 0.9, "range": 600.0, "auto": false,
		"reload": 3.2, "zoom": 12.0, "falloff": 0.15,
	},
	"SM_Wep_Shotgun_01": {
		"label": "M870 霰弹枪", "short": "M870", "damage": 16.0, "rpm": 75.0,
		"mag": 7, "reserve": 42, "spread_hip": 6.5, "spread_ads": 4.5,
		"recoil": 3.2, "recoil_h": 1.1, "range": 45.0, "auto": false,
		"reload": 2.8, "zoom": 30.0, "falloff": 0.85, "pellets": 8,
	},
	"SM_Wep_Pistol_01": {
		"label": "M9 手枪", "short": "M9", "damage": 22.0, "rpm": 300.0,
		"mag": 15, "reserve": 90, "spread_hip": 2.2, "spread_ads": 0.8,
		"recoil": 1.6, "recoil_h": 0.6, "range": 90.0, "auto": false,
		"reload": 1.6, "zoom": 28.0, "falloff": 0.6,
	},
	"SM_Wep_Preset_A_Heavy_01": {
		"label": "M249 班用机枪", "short": "M249", "damage": 24.0, "rpm": 750.0,
		"mag": 100, "reserve": 300, "spread_hip": 5.0, "spread_ads": 0.9,
		"recoil": 2.0, "recoil_h": 0.8, "range": 300.0, "auto": true,
		"reload": 4.6, "zoom": 24.0, "falloff": 0.5,
	},
}


static func get_def(id: String) -> Dictionary:
	if DATA.has(id):
		return DATA[id]
	return DATA["SM_Wep_Preset_A_Rifle_01"]
