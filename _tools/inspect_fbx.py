import sys, bpy
argv = sys.argv[sys.argv.index("--")+1:]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=argv[0])
print("=== OBJECTS ===")
for o in bpy.context.scene.objects:
    print(o.type, o.name, "parent=", o.parent.name if o.parent else None,
          "dims=", tuple(round(v,3) for v in o.dimensions))
for o in bpy.context.scene.objects:
    if o.type == "ARMATURE":
        print("BONES:", len(o.data.bones))
        print([b.name for b in o.data.bones][:60])
print("ACTIONS:", [a.name for a in bpy.data.actions])
