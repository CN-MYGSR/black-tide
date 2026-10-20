"""Blender 批量转换：Unity FBX -> 几何 GLB（不内嵌贴图），并输出模型尺寸元数据。

设计取舍：
  * 贴图不写进 GLB —— 400+ 个模型共用同一张 2048 图集，
    内嵌会让显存里出现几百份同样的图集。这里只导出几何 + 材质名，
    材质由 Godot 侧 AssetLib 按名字统一挂共享 StandardMaterial3D。
  * 材质名统一成 Unity 里那套命名（PolygonMilitary_Mat_01_A / __glass__），
    这样 Godot 侧就能"按名字查图集"，不需要人工对表。

用法:
  blender --background --python batch_convert.py -- <manifest.json> <index.json> <out_dir> <meta.json>
"""
import json
import os
import sys

import bpy


def purge():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for block in (bpy.data.meshes, bpy.data.materials, bpy.data.armatures, bpy.data.actions):
        for item in list(block):
            block.remove(item)


def is_glass(name):
    n = name.lower()
    return "glass" in n or "transp" in n or "alpha" in n


def world_bbox():
    xs, ys, zs = [], [], []
    for obj in bpy.context.scene.objects:
        if obj.type != "MESH":
            continue
        mw = obj.matrix_world
        for corner in obj.bound_box:
            v = mw @ __import__("mathutils").Vector(corner)
            xs.append(v.x)
            ys.append(v.y)
            zs.append(v.z)
    if not xs:
        return [0, 0, 0]
    return [round(max(xs) - min(xs), 3), round(max(ys) - min(ys), 3), round(max(zs) - min(zs), 3)]


def main():
    argv = sys.argv[sys.argv.index("--") + 1:]
    manifest_path, index_path, out_dir, meta_path = argv[:4]

    manifest = json.load(open(manifest_path, encoding="utf-8"))
    index = json.load(open(index_path, encoding="utf-8"))
    model_materials = index["model_materials"]
    models_dir = os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        "_source", "polygon_military", "Assets", "PolygonMilitary", "Models",
    )

    meta = {}
    done = 0
    for entry in manifest:
        src = os.path.join(models_dir, entry["src"])
        if not os.path.exists(src):
            print("MISSING", src)
            continue
        out = os.path.join(out_dir, entry["category"], entry["name"] + ".glb")
        os.makedirs(os.path.dirname(out), exist_ok=True)

        purge()
        bpy.ops.import_scene.fbx(filepath=src)

        # 只保留目标网格（角色 FBX 里塞了 30 多套人）
        target_mesh = entry.get("mesh")
        if target_mesh:
            for obj in list(bpy.data.objects):
                if obj.type == "MESH" and obj.name != target_mesh:
                    bpy.data.objects.remove(obj, do_unlink=True)

        # 材质名归一
        mats = model_materials.get(entry["src"], [])
        primary = next((m for m in mats if not is_glass(m)), "PolygonMilitary_Mat_01_A")
        for slot_obj in bpy.context.scene.objects:
            if slot_obj.type != "MESH":
                continue
            for slot in slot_obj.material_slots:
                mat = slot.material
                if mat is None:
                    continue
                mat.name = "__glass__" if is_glass(mat.name) else primary
                mat.use_nodes = True
                bsdf = next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
                if bsdf:
                    bsdf.inputs["Base Color"].default_value = (1, 1, 1, 1)
                    if "Roughness" in bsdf.inputs:
                        bsdf.inputs["Roughness"].default_value = 0.8
                    if "Metallic" in bsdf.inputs:
                        bsdf.inputs["Metallic"].default_value = 0.0
                    if "Alpha" in bsdf.inputs and mat.name == "__glass__":
                        bsdf.inputs["Alpha"].default_value = 0.35

        tris = 0
        for obj in bpy.context.scene.objects:
            if obj.type == "MESH":
                obj.data.calc_loop_triangles()
                tris += len(obj.data.loop_triangles)

        bpy.ops.export_scene.gltf(
            filepath=out,
            export_format="GLB",
            use_selection=False,
            export_apply=True,
            export_yup=True,
            export_animations=False,
            export_image_format="NONE",
            export_materials="EXPORT",
        )

        meta[entry["name"]] = {
            "category": entry["category"],
            "bbox": world_bbox(),
            "tris": tris,
            "materials": sorted({("__glass__" if is_glass(m) else primary) for m in (mats or [primary])}),
            "bytes": os.path.getsize(out),
        }
        done += 1
        if done % 25 == 0:
            print("progress", done, "/", len(manifest))

    with open(meta_path, "w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=False, indent=1)
    print("DONE", done)


main()
