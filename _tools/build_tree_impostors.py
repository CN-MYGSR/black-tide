"""Blender: render complete CC0 trees into crossed far-distance impostors."""
import bpy
import json
import math
from pathlib import Path
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[1]
records = json.loads((ROOT / "art/environment/model_build.json").read_text())
for asset, name, height in [("island_tree_01", "tree_a", 12.0), ("island_tree_02", "tree_b", 10.0)]:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    bpy.ops.import_scene.gltf(filepath=str(ROOT / "_source/environment_models" / asset / f"{asset}_1k.gltf"))
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    points = [o.matrix_world @ Vector(c) for o in meshes for c in o.bound_box]
    low = Vector(tuple(min(p[i] for p in points) for i in range(3)))
    high = Vector(tuple(max(p[i] for p in points) for i in range(3)))
    center = Vector(((low.x + high.x) / 2, (low.y + high.y) / 2, low.z))
    scale = height / (high.z - low.z)
    for obj in meshes:
        transform = obj.matrix_world.copy()
        for v in obj.data.vertices:
            v.co = (transform @ v.co - center) * scale
        obj.parent = None
        obj.matrix_world = Matrix.Identity(4)
    width = max(high.x - low.x, high.y - low.y) * scale * 1.12
    image_height = max(height * 1.12, width)
    size = image_height
    target = Vector((0, 0, height / 2))
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    preferences = bpy.context.preferences.addons["cycles"].preferences
    try:
        preferences.compute_device_type = "OPTIX"
        preferences.get_devices()
        for device in preferences.devices:
            device.use = device.type == "OPTIX"
        if any(device.use for device in preferences.devices):
            scene.cycles.device = "GPU"
    except TypeError:
        pass
    scene.cycles.samples = 16
    scene.cycles.use_denoising = True
    scene.render.resolution_x = 1024
    scene.render.resolution_y = 1024
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "Standard"
    scene.world.use_nodes = True
    scene.world.node_tree.nodes["Background"].inputs[0].default_value = (0.65, 0.72, 0.8, 1)
    scene.world.node_tree.nodes["Background"].inputs[1].default_value = 0.65
    light = bpy.data.lights.new("Sun", "SUN")
    light.energy = 2.0
    sun = bpy.data.objects.new("Sun", light)
    bpy.context.collection.objects.link(sun)
    sun.rotation_euler = (math.radians(35), math.radians(-20), math.radians(-35))
    camera = bpy.data.objects.new("ImpostorCamera", bpy.data.cameras.new("ImpostorCamera"))
    bpy.context.collection.objects.link(camera)
    scene.camera = camera
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = size
    folder = ROOT / "assets/models/environment_hd" / asset
    images = []
    for index, position in enumerate([(0, -40, height / 2), (40, 0, height / 2)]):
        camera.location = position
        camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = str(folder / f"{name}_impostor_{index}.png")
        bpy.ops.render.render(write_still=True)
        images.append(scene.render.filepath)
    for obj in meshes:
        bpy.data.objects.remove(obj, do_unlink=True)
    cards = []
    for index, path in enumerate(images):
        material = bpy.data.materials.new(f"{name}_impostor_{index}")
        material.use_nodes = True
        material.use_backface_culling = False
        nodes = material.node_tree.nodes
        shader = nodes.get("Principled BSDF")
        tex = nodes.new("ShaderNodeTexImage")
        tex.image = bpy.data.images.load(path, check_existing=True)
        material.node_tree.links.new(tex.outputs["Color"], shader.inputs["Base Color"])
        material.node_tree.links.new(tex.outputs["Alpha"], shader.inputs["Alpha"])
        material.surface_render_method = "DITHERED"
        bpy.ops.mesh.primitive_plane_add(size=size, location=(0, 0, height / 2))
        card = bpy.context.object
        card.name = name + "_impostor"
        card.rotation_euler = (math.pi / 2, 0, index * math.pi / 2)
        card.data.materials.append(material)
        cards.append(card)
    bpy.ops.object.select_all(action="DESELECT")
    for card in cards:
        card.select_set(True)
    bpy.context.view_layer.objects.active = cards[0]
    bpy.ops.object.join()
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    path = folder / f"{name}_far.gltf"
    bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLTF_SEPARATE", use_selection=True,
        export_animations=False, export_cameras=False, export_lights=False, export_yup=True)
    record = next(r for r in records if r["name"] == name and r["lod"] == "far")
    record.update(triangles=4, height_m=round(size, 3), technique="crossed_tree_impostor")
    print("IMPOSTOR_OK", asset, flush=True)
(ROOT / "art/environment/model_build.json").write_text(json.dumps(records, indent=2), encoding="utf-8")
