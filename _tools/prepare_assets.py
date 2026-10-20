"""把转换结果整理进 Godot 项目：贴图、材质表、模型元数据。

输出:
  assets/textures/*            用到的图集
  assets/data/material_map.json  材质名 -> {tex, mode}
  assets/data/model_meta.json    模型名 -> {category, size(godot), tris}
"""
import json
import os
import shutil

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC_TEX = os.path.join(ROOT, "_source", "polygon_military", "Assets", "PolygonMilitary", "Textures")
DST_TEX = os.path.join(ROOT, "assets", "textures")
DATA = os.path.join(ROOT, "assets", "data")

SCISSOR_HINT = ("alpha", "netting", "mesh_cover", "fence", "wire", "camo")


def mode_for(mat_name, tex_name):
    n = (mat_name or "").lower()
    t = (tex_name or "").lower()
    if "glass" in n:
        return "glass"
    if any(h in t for h in SCISSOR_HINT):
        return "scissor"
    return "opaque"


def main():
    meta = json.load(open(os.path.join(ROOT, "_build", "model_meta.json"), encoding="utf-8"))
    index = json.load(open(os.path.join(ROOT, "_build", "asset_index.json"), encoding="utf-8"))
    mat_atlas = index["mat_atlas"]

    used = sorted({m for v in meta.values() for m in v["materials"]})
    os.makedirs(DST_TEX, exist_ok=True)
    os.makedirs(DATA, exist_ok=True)

    tex_index = {}
    for base, _dirs, files in os.walk(SRC_TEX):
        for f in files:
            tex_index.setdefault(f, os.path.join(base, f))

    material_map = {}
    copied = []
    for mat in used:
        tex = mat_atlas.get(mat)
        if tex and tex in tex_index:
            shutil.copyfile(tex_index[tex], os.path.join(DST_TEX, tex))
            copied.append(tex)
        else:
            tex = None
        material_map[mat] = {"tex": tex, "mode": mode_for(mat, tex)}

    out_meta = {}
    for name, v in meta.items():
        bx, by, bz = v["bbox"]  # Blender: x 宽, y 深, z 高
        out_meta[name] = {
            "category": v["category"],
            "size": [round(bx, 3), round(bz, 3), round(by, 3)],  # Godot: x 宽, y 高, z 深
            "tris": v["tris"],
        }

    json.dump(material_map, open(os.path.join(DATA, "material_map.json"), "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)
    json.dump(out_meta, open(os.path.join(DATA, "model_meta.json"), "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)
    print("materials", len(material_map), "textures copied", len(set(copied)))
    for k, v in material_map.items():
        print("  ", k, v)


if __name__ == "__main__":
    main()
