import bpy,json,re
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1]
ids=re.findall(r'^\s*"(SM_Wep_[^"]+)": \{',(ROOT/'src/data/item_db.gd').read_text(encoding='utf-8'),re.M)
result={}
for name in ids:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(ROOT/'assets/models/weapons'/(name+'.glb')))
    parts=[]
    for o in bpy.context.scene.objects:
        if o.type=='MESH':
            points=[o.matrix_world @ v.co for v in o.data.vertices]
            parts.append({'name':o.name,'lo':[round(min(v[i] for v in points),4) for i in range(3)],'hi':[round(max(v[i] for v in points),4) for i in range(3)]})
    result[name]=parts
(ROOT/'_shots/source_weapon_parts.json').write_text(json.dumps(result,indent=1),encoding='utf-8')
print('INSPECTED',len(result),flush=True)
