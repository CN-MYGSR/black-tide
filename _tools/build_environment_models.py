"""Blender: convert Poly Haven sources to bounded, textured near/far game meshes."""
import bpy
import bmesh
import json
import random
import sys
from pathlib import Path
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/models/environment_hd"
SPECS = {
    "island_tree_01": [(0, "tree_a", 12.0, 150000, 3000)],
    "island_tree_02": [(0, "tree_b", 10.0, 150000, 3000)],
    "wild_rooibos_bush": [(0, "bush_a", 1.6, 3500, 500), (1, "bush_b", 1.1, 2500, 350)],
    "grass_bermuda_01": [(9, "grass_a", 0.32, 500, 120), (12, "grass_b", 0.42, 500, 120)],
    "grass_medium_01": [(0, "grass_c", 0.65, 850, 200)],
    "fern_02": [(0, "fern", 0.8, 1800, 350)],
    "rock_moss_set_01": [(0, "rock_a", 1.8, 2200, 350), (2, "rock_b", 1.1, 1800, 300),
                         (3, "rock_c", 2.4, 2200, 350)],
    "rock_09": [(0, "rock_d", 1.6, 2200, 350)],
}


def triangles(obj):
    obj.data.calc_loop_triangles()
    return len(obj.data.loop_triangles)


def thin_disconnected_cards(obj, budget):
    """Decimation cannot collapse detached twig cards; thin whole cards for far LOD."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    remaining = set(bm.faces)
    islands = []
    while remaining:
        first = remaining.pop()
        island, stack = [first], [first]
        while stack:
            for vert in stack.pop().verts:
                for face in vert.link_faces:
                    if face in remaining:
                        remaining.remove(face)
                        island.append(face)
                        stack.append(face)
        islands.append(island)
    random.Random(491).shuffle(islands)
    count, discard = 0, []
    for island in islands:
        size = sum(len(f.verts) - 2 for f in island)
        if count + size <= budget:
            count += size
        else:
            discard.extend(island)
    assert count > 0, (obj.name, budget)
    bmesh.ops.delete(bm, geom=discard, context="FACES")
    bm.to_mesh(obj.data)
    bm.free()


trees_only = "--trees-only" in sys.argv
manifest = ROOT / "art/environment/model_build.json"
records = [r for r in json.loads(manifest.read_text()) if not r["source"].startswith("island_tree_")] if trees_only else []
for asset, specs in SPECS.items():
    if trees_only and not asset.startswith("island_tree_"):
        continue
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    bpy.ops.import_scene.gltf(filepath=str(ROOT / "_source/environment_models" / asset / f"{asset}_1k.gltf"))
    originals = sorted([o for o in bpy.context.scene.objects if o.type == "MESH"], key=lambda o: o.name)
    for index, name, height, near_budget, far_budget in specs:
        source = originals[index]
        for lod, budget in [("near", near_budget), ("far", far_budget)]:
            bpy.ops.object.select_all(action="DESELECT")
            obj = source.copy()
            obj.data = source.data.copy()
            bpy.context.collection.objects.link(obj)
            obj.select_set(True)
            bpy.context.view_layer.objects.active = obj
            bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
            points = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
            low = Vector(tuple(min(p[i] for p in points) for i in range(3)))
            high = Vector(tuple(max(p[i] for p in points) for i in range(3)))
            center = Vector(((low.x + high.x) / 2, (low.y + high.y) / 2, low.z))
            scale = height / max(high.z - low.z, 0.01)
            for vert in obj.data.vertices:
                vert.co = (obj.matrix_world @ vert.co - center) * scale
            obj.parent = None
            obj.matrix_world = Matrix.Identity(4)
            # Reduce separate materials independently, retaining leafy crowns over dense scanned bark.
            bpy.ops.mesh.separate(type="MATERIAL")
            parts = list(bpy.context.selected_objects)
            print("SOURCE", asset, name, [(p.active_material.name if p.active_material else "", triangles(p)) for p in parts], flush=True)
            weights = []
            for part in parts:
                material = part.active_material
                leaf = material is not None and "leav" in material.name.lower()
                weights.append(0.68 if leaf else 0.32 / max(len(parts) - 1, 1))
            total_weight = sum(weights)
            for part, weight in zip(parts, weights):
                bpy.context.view_layer.objects.active = part
                count = triangles(part)
                target = max(32, int(budget * weight / total_weight))
                if count > target:
                    modifier = part.modifiers.new("Game budget", "DECIMATE")
                    modifier.ratio = target / count
                    modifier.use_collapse_triangulate = True
                    bpy.ops.object.modifier_apply(modifier=modifier.name)
                    if triangles(part) > target * 1.05:
                        thin_disconnected_cards(part, target)
                for poly in part.data.polygons:
                    poly.use_smooth = True
            bpy.context.view_layer.objects.active = parts[0]
            bpy.ops.object.join()
            obj = bpy.context.object
            obj.name = name + "_" + lod
            # Alpha clipping keeps plant cards in the opaque depth/shadow path in Godot.
            for material in obj.data.materials:
                material.use_backface_culling = False
                material.diffuse_color[3] = 1.0
            folder = OUT / asset
            folder.mkdir(parents=True, exist_ok=True)
            path = folder / f"{name}_{lod}.gltf"
            bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLTF_SEPARATE",
                use_selection=True, export_animations=False, export_cameras=False,
                export_lights=False, export_yup=True, export_image_format="AUTO")
            count = triangles(obj)
            assert 0 < count <= budget * 1.1, (name, count, budget)
            assert abs(obj.dimensions.z - height) < height * 0.2, (name, obj.dimensions.z, height)
            record = {"name": name, "lod": lod, "source": asset, "triangles": count,
                      "height_m": round(obj.dimensions.z, 3), "path": path.relative_to(ROOT).as_posix()}
            records.append(record)
            print("EXPORT_OK", record, flush=True)
            bpy.ops.object.delete()
assert len(records) == sum(len(s) for s in SPECS.values()) * 2
(ROOT / "art/environment/model_build.json").write_text(json.dumps(records, indent=2), encoding="utf-8")
