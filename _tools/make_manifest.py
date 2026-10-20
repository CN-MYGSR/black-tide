"""生成转换清单 _build/manifest.json：挑出游戏要用的模型子集。

规则：
  - 建筑 / 环境 / 载具 / 武器 全量
  - 道具按关键词白名单
  - 角色从 Characters.fbx 里按网格拆分
"""
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODELS = os.path.join(ROOT, "_source", "polygon_military", "Assets", "PolygonMilitary", "Models")
OUT = os.path.join(ROOT, "_build", "manifest.json")

PROP_KEYWORDS = [
    "AmmoBox", "Ammo_Bullet_Cases", "Barrel", "Barrier", "Crate", "Cardboard", "Sack",
    "Slatbox", "Gunlocker", "Gunrack", "WeaponCase", "MedicalBox", "Medic_IV", "Medical_Shelf",
    "Bed_Medical", "Bed_Stretcher", "Bed_Military", "Bed_SleepingBag", "Locker", "Cabinet",
    "Desk", "Chair", "Table", "Stool", "Shelf", "Shelves", "Generator", "Fuel_Bladder",
    "GasCan", "Gastank", "PowerBox", "Powerline", "Powerpole", "LightPole", "Street_Light",
    "Light_Portable", "Fence", "RazorWire", "Road_Barrier", "Runway_Barrier", "Runway_Light",
    "Tire", "Pallet", "Ladder", "Cone", "Sign_", "Briefing_Board", "Radio", "Satellite_Dish",
    "Satelite_Dish", "Mobile_Radar", "Aerial", "Antenna", "IED", "Mine", "Mortar_Shell",
    "Missle", "Shell", "TentPole", "WaterTank", "Pipeline_Tank", "Wood_Plinth",
    "Vehicle_Debris", "Rubble", "DebrisPile", "BloodPool", "Gaspump", "Drone_Control",
    "Fridge", "Wardrobe", "Pipe", "Cable", "WireSpool", "Wire_Pole", "Lamp", "Basket",
    "Bomb_C4", "C4", "Claymore", "Flashbang", "Grenade",
]

CHARACTERS = [
    "SM_Chr_Soldier_Male_01",
    "SM_Chr_Soldier_Male_02",
    "SM_Chr_Soldier_Female_01",
    "SM_Chr_Insurgent_Male_01",
    "SM_Chr_Insurgent_Male_02",
    "SM_Chr_Insurgent_Male_03",
    "SM_Chr_Insurgent_Male_04",
    "SM_Chr_Leader_Male_01",
    "SM_Chr_Ghillie_Male_01",
    "SM_Chr_Civilian_Male_01",
    "SM_Chr_Civilian_Female_01",
    "SM_Chr_Pilot_Male_01",
]


def category(name):
    if name.startswith("SM_Bld_"):
        return "buildings"
    if name.startswith("SM_Env_"):
        return "environment"
    if name.startswith("SM_Veh_"):
        return "vehicles"
    if name.startswith("SM_Wep_"):
        return "weapons"
    if name.startswith("SM_Prop_"):
        return "props"
    return "misc"


def main():
    files = sorted(f for f in os.listdir(MODELS) if f.lower().endswith(".fbx"))
    entries = []
    for f in files:
        stem = os.path.splitext(f)[0]
        cat = category(stem)
        if cat == "misc":
            continue
        if cat == "props" and not any(k.lower() in stem.lower() for k in PROP_KEYWORDS):
            continue
        if cat == "vehicles" and "Attach" in stem:
            continue
        if cat == "weapons" and ("Mod_" in stem or "Crosshair" in stem):
            continue
        entries.append({"src": f, "name": stem, "category": cat, "mesh": None})

    char_src = "Characters.fbx"
    for c in CHARACTERS:
        entries.append({"src": char_src, "name": c, "category": "characters", "mesh": c})

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as fp:
        json.dump(entries, fp, ensure_ascii=False, indent=1)

    stat = {}
    for e in entries:
        stat[e["category"]] = stat.get(e["category"], 0) + 1
    print("total", len(entries), stat)


if __name__ == "__main__":
    main()
