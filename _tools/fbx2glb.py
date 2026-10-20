"""Blender 无头转换：Unity FBX -> glTF/GLB，并把 Synty 材质重挂到图集贴图。

用法:
  blender --background --python fbx2glb.py -- <in.fbx> <out.glb> <texture_dir>
"""
import os
import sys

import bpy


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


# Synty 材质名 -> 图集文件名（按名字后缀 A/B/C 与编号对应）
def atlas_for(mat_name):
    n = mat_name.lower()
    if "land_vehicle" in n:
        if "burnt" in n:
            return "Land_Vehicle_Master_Burnt_01.png"
        if n.endswith("_02"):
            return "Land_Vehicle_Master_02.png"
        if n.endswith("_03"):
            return "Land_Vehicle_Master_03.png"
        return "Land_Vehicle_Master_01.png"
    if "air_vehicle" in n:
        if "burnt" in n:
            return "Air_Vehicle_Burnt.png"
        return "Air_Vehicle_Master_01.png"
    if "glass" in n:
        return None
    if "tank_track" in n:
        return "PolygonMilitary_Tank_Tracks.png"
    for i in ("01", "02", "03", "04"):
        if "_mat_%s" % i in n or "mat_%s" % i in n:
            for s in ("a", "b", "c"):
                if n.endswith("_" + s):
                    return "PolygonMilitary_Texture_%s_%s.png" % (i, s.upper())
    return None


def main():
    argv = sys.argv[sys.argv.index("--") + 1:]
    src, dst, texdir = argv[0], argv[1], argv[2]

    clear_scene()
    bpy.ops.import_scene.fbx(filepath=src)

    mats = []
    for obj in bpy.context.scene.objects:
        if obj.type != "MESH":
            continue
        for slot in obj.material_slots:
            if slot.material and slot.material not in mats:
                mats.append(slot.material)

    info = []
    for m in mats:
        info.append(m.name)
        atlas = atlas_for(m.name)
        if not atlas:
            continue
        path = os.path.join(texdir, atlas)
        if not os.path.exists(path):
            continue
        m.use_nodes = True
        nt = m.node_tree
        bsdf = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
        if bsdf is None:
            continue
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = bpy.data.images.load(path, check_existing=True)
        tex.location = (-500, 300)
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        # Synty 贴图本身就是平涂，关掉高光更接近原版观感
        if "Roughness" in bsdf.inputs:
            bsdf.inputs["Roughness"].default_value = 0.75
        if "Metallic" in bsdf.inputs:
            bsdf.inputs["Metallic"].default_value = 0.0

    dims = []
    for obj in bpy.context.scene.objects:
        if obj.type == "MESH":
            dims.append(tuple(round(v, 3) for v in obj.dimensions))

    os.makedirs(os.path.dirname(dst), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=dst,
        export_format="GLB",
        use_selection=False,
        export_apply=True,
        export_yup=True,
    )
    print("MATS:", info)
    print("DIMS:", dims[:8])
    print("OK:", dst, os.path.getsize(dst))


main()
