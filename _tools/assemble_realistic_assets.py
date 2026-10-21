"""Adapt free, attributed assets in Blender to Black Tide's rig / weapon interfaces.

Sources and licences: art/black_tide_remodel/THIRD_PARTY_ASSETS.md.
No gameplay stats or saved equipment IDs are changed.
"""
import json
import math
import os
from pathlib import Path
import shutil
import sys
import time

import bpy
from mathutils import Matrix, Quaternion, Vector

ROOT=Path(__file__).resolve().parents[1]
ART=ROOT/'art/black_tide_remodel'
REF=ART/'reference/free_assets'
MODELS=ROOT/'assets/models'
META=ROOT/'assets/data/model_meta.json'


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0


def clean_helpers():
    for o in list(bpy.context.scene.objects):
        if o.name.startswith('SpareMagazine'):
            bpy.data.objects.remove(o,do_unlink=True)
            continue
        if o.type=='MESH' and o.name.startswith('Icosphere') and not any(m.type=='ARMATURE' for m in o.modifiers):
            bpy.data.objects.remove(o,do_unlink=True)


def pack_materials():
    for m in bpy.data.materials:
        if not m.name.startswith('BT_') and not m.get('bt_shared_atlas'):
            m.name='BT_Real_'+m.name
    for im in bpy.data.images:
        if im.source=='FILE' and im.has_data:
            im.file_format='PNG'
            im.filepath_raw=str(ART/(im.name.replace('/','_').replace('\\','_')+'.png'))
            im.pack()


def scene_bounds(objects):
    dg=bpy.context.evaluated_depsgraph_get()
    points=[]
    for o in objects:
        if o.type=='MESH':
            ev=o.evaluated_get(dg)
            points.extend(ev.matrix_world @ v.co for v in ev.data.vertices)
    assert points
    lo=Vector(tuple(min(v[i] for v in points) for i in range(3)))
    hi=Vector(tuple(max(v[i] for v in points) for i in range(3)))
    return lo,hi


def register(name,category,objects):
    lo,hi=scene_bounds(objects)
    size=hi-lo
    tris=sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in objects if o.type=='MESH')
    meta=json.loads(META.read_text(encoding='utf-8'))
    meta[name]={'category':category,'size':[round(size.x,4),round(size.z,4),round(size.y,4)],'tris':tris}
    META.write_text(json.dumps(meta,ensure_ascii=False,indent=1)+'\n',encoding='utf-8')
    print('REAL_ASSET',name,'tris',tris,'size',list(size),flush=True)
    return meta[name]


def export(name,category,animations=False):
    path=MODELS/category/(name+'.glb')
    path.parent.mkdir(parents=True,exist_ok=True)
    stage=ART/'staging'/(name+'.glb')
    stage.parent.mkdir(parents=True,exist_ok=True)
    pack_materials()
    bpy.ops.export_scene.gltf(filepath=str(stage),export_format='GLB',
        export_yup=True,export_animations=animations,export_animation_mode='NLA_TRACKS',
        export_merge_animation='NLA_TRACK',export_frame_range=True,export_frame_step=1,
        export_bake_animation=True,export_extras=True,export_image_format='AUTO',
        export_def_bones=False)
    pending=path.with_suffix('.glb.tmp')
    shutil.copy2(stage,pending)
    for attempt in range(20):
        try:
            os.replace(pending,path)
            break
        except PermissionError:
            if attempt==19: raise
            time.sleep(.5)
    register(name,category,list(bpy.context.scene.objects))


def point_distance(p,a,b):
    d=b-a
    t=max(0,min(1,(p-a).dot(d)/max(1e-9,d.length_squared)))
    return (p-(a+t*d)).length


def rotate_world(arm,bone_name,axis,angle):
    b=arm.pose.bones[bone_name]
    axis=(arm.matrix_world.to_3x3() @ b.matrix.to_3x3()).inverted() @ Vector(axis)
    b.rotation_mode='QUATERNION'
    b.rotation_quaternion=b.rotation_quaternion @ Quaternion(axis,angle)
    bpy.context.view_layer.update()


def build_operator():
    reset()
    bpy.ops.import_scene.gltf(filepath=str(REF/'modern_soldier.glb'))
    meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
    # Weapon-specific closed gloves are fitted at runtime using measured wrist frames.
    for obj in list(meshes):
        if obj.name.split('_')[-1]=='Part01':
            meshes.remove(obj); bpy.data.objects.remove(obj,do_unlink=True)
    lo,hi=scene_bounds(meshes)
    unit=1.8/(hi.z-lo.z)
    normalize=Matrix.Scale(unit,4) @ Matrix.Translation(Vector((0,0,-lo.z)))
    # Flatten the static source's object transforms before skinning it.
    for o in meshes:
        xf=normalize @ o.matrix_world
        o.parent=None; o.matrix_world=Matrix.Identity(4)
        o.data.transform(xf)
        if len(o.data.polygons)>1500:
            bpy.context.view_layer.objects.active=o
            dec=o.modifiers.new('Realtime geometry budget','DECIMATE')
            dec.ratio=.27
            dec.use_collapse_triangulate=True
            bpy.ops.object.modifier_apply(modifier=dec.name)
    data=bpy.data.armatures.new('BT_OperatorSkeleton')
    arm=bpy.data.objects.new('BT_OperatorRig',data)
    bpy.context.collection.objects.link(arm)
    arm.scale=(.01,.01,.01)
    bpy.context.view_layer.objects.active=arm; arm.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    segments={
        'Root':((0,0,0),(0,0,.12),None),
        'Hips':((0,.018,.86),(0,.018,.98),'Root'),
        'Spine_01':((0,.018,.98),(0,.018,1.18),'Hips'),
        'Spine_02':((0,.018,1.18),(0,.015,1.41),'Spine_01'),
        'Neck':((0,.015,1.41),(0,.015,1.535),'Spine_02'),
        'Head':((0,.015,1.535),(0,.015,1.78),'Neck'),
    }
    for s,side in [(1,'L'),(-1,'R')]:
        segments.update({
            'Clavicle_'+side:((s*.065,.015,1.415),(s*.19,.012,1.415),'Spine_02'),
            'Shoulder_'+side:((s*.19,.012,1.415),(s*.345,-.005,1.20),'Clavicle_'+side),
            'Elbow_'+side:((s*.345,-.005,1.20),(s*.447,-.045,1.047),'Shoulder_'+side),
            'Hand_'+side:((s*.447,-.045,1.047),(s*.49,-.075,.95),'Elbow_'+side),
            'UpperLeg_'+side:((s*.093,.02,.85),(s*.112,.005,.465),'Hips'),
            'LowerLeg_'+side:((s*.112,.005,.465),(s*.121,.025,.09),'UpperLeg_'+side),
            'Ankle_'+side:((s*.121,.025,.09),(s*.121,-.075,.035),'LowerLeg_'+side),
            'Toes_'+side:((s*.121,-.075,.035),(s*.121,-.15,.035),'Ankle_'+side),
        })
    for name,(a,b,parent) in segments.items():
        bone=data.edit_bones.new(name)
        bone.head=Vector(a)*100; bone.tail=Vector(b)*100
        if parent: bone.parent=data.edit_bones[parent]
    bpy.ops.object.mode_set(mode='OBJECT')
    for o in meshes:
        groups={name:o.vertex_groups.new(name=name) for name in segments}
        part=o.name.split('_')[-1]
        for v in o.data.vertices:
            p=v.co
            if part in ['Part13','Part15','Part16','Part19','Part20','Part21','Part23']:
                weights={'Head':1.0}
            elif part=='Part01':
                weights={'Hand_L' if p.x>0 else 'Hand_R':1.0}
            elif part in ['Part07','Part08']:
                weights={'Ankle_L' if p.x>0 else 'Ankle_R':1.0}
            elif part in ['Part02','Part03','Part05','Part06','Part09','Part10','Part24']:
                weights={'Spine_02':1.0}
            elif part in ['Part04','Part17','Part18','Part25']:
                weights={'Hips':1.0}
            elif part=='Part14':
                weights={'UpperLeg_R':1.0}
            else:
                # Distance to anatomical segments, restricted to one body side.
                side='L' if p.x>=0 else 'R'
                candidates=['Hips','Spine_01','Spine_02','Neck','Head']
                if p.z>.92 and abs(p.x)>.16:
                    candidates+=['Shoulder_'+side,'Elbow_'+side,'Hand_'+side]
                if p.z<.94:
                    candidates+=['UpperLeg_'+side,'LowerLeg_'+side,'Ankle_'+side]
                distances=sorted((point_distance(p,Vector(segments[n][0]),Vector(segments[n][1])),n) for n in candidates)
                near=distances[:2]
                raw=[1/max(.015,d)**4 for d,n in near]
                weights={n:w/sum(raw) for (_,n),w in zip(near,raw)}
            assert abs(sum(weights.values())-1)<1e-5
            for n,w in weights.items(): groups[n].add([v.index],w,'REPLACE')
        mod=o.modifiers.new('Black Tide skin','ARMATURE'); mod.object=arm
    # The game animator starts from a T-pose; preserve the source's natural proportions.
    for s,side in [(1,'L'),(-1,'R')]:
        b=arm.pose.bones['Shoulder_'+side]
        direction=b.tail-b.head
        rotate_world(arm,b.name,(0,1,0),-s*math.atan2(-direction.z,abs(direction.x)))
        b=arm.pose.bones['Elbow_'+side]
        direction=b.tail-b.head
        rotate_world(arm,b.name,(0,1,0),-s*math.atan2(-direction.z,abs(direction.x)))
    for o in meshes:
        bpy.context.view_layer.objects.active=o
        bpy.ops.object.modifier_apply(modifier='Black Tide skin')
    bpy.context.view_layer.objects.active=arm
    bpy.ops.object.mode_set(mode='POSE')
    bpy.ops.pose.armature_apply(selected=False)
    bpy.ops.object.mode_set(mode='OBJECT')
    bpy.ops.object.select_all(action='DESELECT')
    for o in meshes: o.select_set(True)
    bpy.context.view_layer.objects.active=meshes[0]
    bpy.ops.object.join()
    mesh=bpy.context.object; mesh.name='BT_Operator'
    mesh.parent=arm; mesh.matrix_parent_inverse=arm.matrix_world.inverted()
    mod=mesh.modifiers.new('Game skeleton','ARMATURE'); mod.object=arm
    for o in list(bpy.context.scene.objects):
        if o not in [mesh,arm]: bpy.data.objects.remove(o,do_unlink=True)
    arm['bt_realistic']=True
    pack_materials()
    bpy.context.view_layer.update()
    lo,hi=scene_bounds([mesh])
    assert 1.72<hi.z-lo.z<1.9,(lo,hi)
    bpy.ops.wm.save_as_mainfile(filepath=str(ART/'BT_Operator.blend'))
    export('BT_Operator','characters')


def set_world_rotation(arm,bone,q):
    p=arm.matrix_world @ bone.matrix
    bone.matrix=arm.matrix_world.inverted() @ Matrix.LocRotScale(p.translation,q @ p.to_quaternion(),p.to_scale())
    bpy.context.view_layer.update()


def fit_viewmodel_arms(arm,grip_world,source):
    """Keep the wrists on the gun, but move the shoulder cutoffs behind the eye."""
    normalize=Matrix.Scale(.5,4) @ Matrix.Rotation(math.pi,4,'Z') @ Matrix.Translation(-grip_world)
    if source in ['m4a1','ak47']:
        # The source thumb arches backwards; wrap its two joints around the grip instead.
        for name,target in [('Bone_R.021',(.022,-.008,-.013)),('Bone_R.022',(.015,-.035,-.025))]:
            bone=arm.pose.bones[name]
            head=arm.matrix_world @ bone.head
            tail=arm.matrix_world @ bone.tail
            desired=normalize.inverted() @ Vector(target)
            set_world_rotation(arm,bone,(tail-head).rotation_difference(desired-head))
    if source in ['m4a1','ak47']:
        wrist=normalize @ (arm.matrix_world @ arm.pose.bones['Hand_L'].head)
        for name,offset in [('Bone_L.014',(-.085,-.100,.014)),('Bone_L.015',(-.081,-.079,.029)),
                            ('Bone_L.018',(-.081,-.094,-.011)),('Bone_L.019',(-.081,-.080,.003))]:
            bone=arm.pose.bones[name]
            head=arm.matrix_world @ bone.head; tail=arm.matrix_world @ bone.tail
            desired=normalize.inverted() @ (wrist+Vector(offset))
            set_world_rotation(arm,bone,(tail-head).rotation_difference(desired-head))
    for obj in list(bpy.context.scene.objects):
        if obj.type=='MESH' and 'FPArms' in obj.name:
            bpy.context.view_layer.objects.active=obj
            # These unused source expressions are not part of the exported hand animation.
            if obj.data.shape_keys:
                assert all(abs(k.value)<1e-6 for k in obj.data.shape_keys.key_blocks[1:])
                obj.shape_key_clear()
            for mod in list(obj.modifiers):
                if mod.type=='ARMATURE': bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.context.view_layer.objects.active=arm
    bpy.ops.object.mode_set(mode='POSE')
    bpy.ops.pose.armature_apply(selected=False)
    bpy.ops.object.mode_set(mode='OBJECT')
    fits={}
    for side,shoulder,new_elbow in [('L',(.40,.38,-.29),(.29,.02,-.21)),('R',(-.12,.38,-.27),(-.27,.22,-.24))]:
        head=arm.matrix_world @ arm.data.bones['UpArm_'+side].head_local
        elbow=arm.matrix_world @ arm.data.bones['Forearm_'+side].head_local
        wrist=arm.matrix_world @ arm.data.bones['Hand_'+side].head_local
        new_wrist=wrist+Vector((0,0,.07 if source=='ak47' and side=='L' else 0))
        fits[side]=(head,elbow,wrist,normalize.inverted() @ Vector(shoulder),normalize.inverted() @ Vector(new_elbow),new_wrist)
    def fraction(p,a,b):
        return max(0,min(1,(p-a).dot(b-a)/(b-a).length_squared))
    for obj in bpy.context.scene.objects:
        if obj.type!='MESH' or 'FPArms' not in obj.name: continue
        names={g.index:g.name for g in obj.vertex_groups}
        for vertex in obj.data.vertices:
            p=obj.matrix_world @ vertex.co
            shift=Vector()
            for side,(head,elbow,wrist,new_head,new_elbow,new_wrist) in fits.items():
                upper_weight=sum(g.weight for g in vertex.groups if names[g.group] in ['UpArm_'+side,'Arm_'+side])
                hand_weight=sum(g.weight for g in vertex.groups if names[g.group]=='Hand_'+side or names[g.group].startswith('Bone_'+side+'.'))
                fore_groups=[g for g in vertex.groups if names[g.group]=='Forearm_'+side or (names[g.group].startswith('BoneTwist_') and names[g.group].endswith('.'+side))]
                fore_weight=sum(g.weight for g in fore_groups)
                u=fraction(p,head,elbow); t=fraction(p,elbow,wrist)
                shift+=upper_weight*((new_head-head).lerp(new_elbow-elbow,u))
                shift+=fore_weight*(new_elbow-elbow).lerp(new_wrist-wrist,t)
                shift+=hand_weight*(new_wrist-wrist)
                # Fuller cloth sleeves, tapering to the unchanged glove at the wrist.
                axis=wrist-elbow
                radial=p-(elbow+axis*t)
                shift+=fore_weight*radial*(.45*math.sin(math.pi*t))
                if fore_weight>0 and t>.70:
                    blend=min(1,(t-.70)/.20); blend=blend*blend*(3-2*blend)
                    for group in fore_groups:
                        obj.vertex_groups[group.group].add([vertex.index],group.weight*(1-blend),'REPLACE')
                    hand_group=obj.vertex_groups['Hand_'+side]
                    previous=next((g.weight for g in vertex.groups if g.group==hand_group.index),0)
                    hand_group.add([vertex.index],previous+fore_weight*blend,'REPLACE')
            vertex.co=obj.matrix_world.inverted() @ (p+shift)
    bpy.context.view_layer.objects.active=arm
    bpy.ops.object.mode_set(mode='EDIT')
    for side,(head,elbow,wrist,new_head,new_elbow,new_wrist) in fits.items():
        for bone in arm.data.edit_bones:
            if bone.name=='UpArm_'+side:
                bone.head=arm.matrix_world.inverted() @ new_head
                bone.tail=arm.matrix_world.inverted() @ new_elbow
            elif bone.name=='Forearm_'+side or (bone.name.startswith('BoneTwist_') and bone.name.endswith('.'+side)):
                for attr in ['head','tail']:
                    p=arm.matrix_world @ getattr(bone,attr)
                    p+=(new_elbow-elbow).lerp(new_wrist-wrist,fraction(p,elbow,wrist))
                    setattr(bone,attr,arm.matrix_world.inverted() @ p)
            elif bone.name in ['Hand_'+side,'IK_Hand_Cntrl_'+side] or bone.name.startswith('Bone_'+side+'.'):
                delta=arm.matrix_world.inverted().to_3x3() @ (new_wrist-wrist)
                bone.head+=delta; bone.tail+=delta
    bpy.ops.object.mode_set(mode='OBJECT')
    for obj in bpy.context.scene.objects:
        if obj.type=='MESH' and 'FPArms' in obj.name:
            mod=obj.modifiers.new('Fitted viewmodel skin','ARMATURE'); mod.object=arm


def animate_reload(arm,magazine,grip,cls,canonical=False):
    arm.animation_data_clear()
    for b in arm.pose.bones: b.rotation_mode='QUATERNION'
    base={b.name:b.matrix_basis.copy() for b in arm.pose.bones}
    ctrl=arm.pose.bones.get('IK_Hand_Cntrl_L')
    upper=arm.pose.bones.get('UpArm_L'); fore=arm.pose.bones.get('Forearm_L')
    hand=arm.pose.bones.get('Hand_L')
    if not all([ctrl,upper,fore,hand]) or magazine is None:
        return
    bpy.context.view_layer.update()
    start=arm.matrix_world @ hand.matrix
    original_ctrl=arm.matrix_world @ ctrl.matrix
    s0=(arm.matrix_world @ upper.matrix).translation
    e0=(arm.matrix_world @ fore.matrix).translation
    w0=start.translation
    a=(e0-s0).length; b=(w0-e0).length
    wrist_local=(arm.matrix_world @ fore.matrix).inverted() @ w0
    mag_base=magazine.matrix_world.copy()
    def offset(x,y,z):
        return Vector((-.5*x,-.5*y,.5*z)) if canonical else Vector((x,y,z))
    mag_target=mag_base.translation+offset(-.11,-.05,-.22)
    keys=[(0,w0),(10,mag_target),(24,mag_target+offset(-.04,0,-.12)),
          (37,mag_target+offset(-.16,-.04,-.18)),(53,mag_target+offset(0,0,-.08)),
          (62,mag_target),(78,w0),(90,w0)]
    arm.animation_data_create()
    act=bpy.data.actions.new('Reload'); arm.animation_data.action=act
    mag_original_location=magazine.location.copy()
    mag_action=bpy.data.actions.new('Reload_Magazine')
    magazine.animation_data_create(); magazine.animation_data.action=mag_action
    for frame in range(91):
        for name,xf in base.items(): arm.pose.bones[name].matrix_basis=xf
        bpy.context.view_layer.update()
        for i in range(len(keys)-1):
            if keys[i][0]<=frame<=keys[i+1][0]:
                t=(frame-keys[i][0])/(keys[i+1][0]-keys[i][0]); t=t*t*(3-2*t)
                desired=keys[i][1].lerp(keys[i+1][1],t); break
        direction=(desired-s0).normalized(); distance=min((desired-s0).length,a+b-.001)
        along=(a*a-b*b+distance*distance)/(2*max(.001,distance))
        height=math.sqrt(max(0,a*a-along*along))
        pole=e0-s0; pole-=direction*pole.dot(direction)
        if pole.length<.001: pole=Vector((-1,0,-1))
        elbow=s0+direction*along+pole.normalized()*height
        set_world_rotation(arm,upper,(e0-s0).rotation_difference(elbow-s0))
        fore_world=arm.matrix_world @ fore.matrix
        wrist_now=fore_world @ wrist_local
        set_world_rotation(arm,fore,(wrist_now-elbow).rotation_difference(desired-elbow))
        ctrl_world=original_ctrl.copy(); ctrl_world.translation+=desired-w0
        ctrl.matrix=arm.matrix_world.inverted() @ ctrl_world
        bpy.context.view_layer.update()
        set_world_rotation(arm,hand,(w0-e0).rotation_difference(desired-elbow))
        for bone in arm.pose.bones:
            bone.keyframe_insert('location',frame=frame,group=bone.name)
            bone.keyframe_insert('rotation_quaternion',frame=frame,group=bone.name)
            bone.keyframe_insert('scale',frame=frame,group=bone.name)
        if 10<=frame<=62:
            hand_world=arm.matrix_world @ hand.matrix
            if frame==10: mag_grasp=hand_world.inverted() @ mag_base
            magazine.matrix_world=hand_world @ mag_grasp
        else: magazine.matrix_world=mag_base
        magazine.keyframe_insert('location',frame=frame)
        magazine.rotation_mode='QUATERNION'
        magazine.keyframe_insert('rotation_quaternion',frame=frame)
    for obj,action in [(arm,act),(magazine,mag_action)]:
        obj.animation_data.action=None
        track=obj.animation_data.nla_tracks.new(); track.name='Reload'
        strip=track.strips.new('Reload',0,action); strip.action_frame_start=0; strip.action_frame_end=90
    bpy.context.scene.render.fps=30
    bpy.context.scene.frame_start=0; bpy.context.scene.frame_end=90
    bpy.context.scene.frame_set(0)


def build_viewmodel(source,key,body_name,arms_name):
    reset()
    bpy.ops.import_scene.gltf(filepath=str(REF/(source+'.glb')))
    clean_helpers()
    arm=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
    arm.animation_data_clear()
    bpy.context.view_layer.update()
    grip=bpy.data.objects.get('GripR')
    assert grip is not None
    grip_world=grip.matrix_world.translation.copy()
    fit_viewmodel_arms(arm,grip_world,source)
    mag=bpy.data.objects.get('Magazine')
    animate_reload(arm,mag,grip,source)
    # Use the firing grip as origin; all old world weapons face Godot +Z.
    normalize=Matrix.Scale(.5,4) @ Matrix.Rotation(math.pi,4,'Z') @ Matrix.Translation(-grip_world)
    roots=[o for o in bpy.context.scene.objects if o.parent is None]
    for o in roots: o.matrix_world=normalize @ o.matrix_world
    bpy.context.view_layer.update()
    gun=next(o for o in bpy.context.scene.objects if o.name.startswith('Gun_'))
    add_grip_markers(gun,(0,0,0) if source=='m1911' else ((0,.012,.32) if source=='ak47' else (0,-.025,.29)))
    marker=bpy.data.objects.new('BT_AimAnchor',None)
    bpy.context.collection.objects.link(marker)
    marker.parent=gun
    rear=bpy.data.objects.get('RearIronSight')
    if rear:
        marker.matrix_world=rear.matrix_world.copy()
        sight=bpy.data.objects.get('RearIronSightGeometry') or bpy.data.objects.get('RearIronGeometry')
        if sight:
            pts=[sight.matrix_world @ Vector(p) for p in sight.bound_box]
            xf=marker.matrix_world.copy()
            if source=='m4a1': xf.translation.x-=.0035
            xf.translation.z=max(p.z for p in pts)-.006
            marker.matrix_world=xf
    else:
        # Pistols' rear notch is just above and behind the firing grip.
        marker.matrix_world=normalize @ Matrix.Translation(grip_world+Vector((0,0,.12)))
    for o in bpy.context.scene.objects:
        if o.type=='MESH' and 'FPArms' not in o.name:
            if len(o.data.polygons)>24000:
                bpy.context.view_layer.objects.active=o
                dec=o.modifiers.new('Realtime viewmodel budget','DECIMATE'); dec.ratio=.65
                bpy.ops.object.modifier_apply(modifier=dec.name)
    pack_materials()
    bpy.ops.wm.save_as_mainfile(filepath=str(ART/(key+'.blend')))
    export(key,'viewmodels',True)
    # Keep an arms-only version for weapons without a matching free gun model.
    fp_arms=[o for o in bpy.context.scene.objects if o.type=='MESH' and 'FPArms' in o.name]
    assert fp_arms
    gun_children=set([gun,*gun.children_recursive,marker])
    saved=[]
    for o in gun_children:
        if o.type=='MESH': saved.append((o,o.hide_render)); o.hide_render=True
    # Excluding objects is safer than editing the original imported hierarchy.
    bpy.ops.object.select_all(action='DESELECT')
    arm.select_set(True)
    for o in fp_arms: o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(MODELS/'viewmodels'/(arms_name+'.glb')),
        export_format='GLB',use_selection=True,export_animations=True,export_animation_mode='NLA_TRACKS',
        export_merge_animation='NLA_TRACK',export_frame_range=True,export_image_format='AUTO',export_def_bones=False)
    register(arms_name,'viewmodels',fp_arms)
    for o,state in saved: o.hide_render=state
    # The same actual gun is used in the armoury and in third person, without arms.
    for o in list(bpy.context.scene.objects):
        if o==arm or o in fp_arms:
            bpy.data.objects.remove(o,do_unlink=True)
    for o in bpy.context.scene.objects: o.animation_data_clear()
    export(body_name,'weapons')


def add_grip_markers(parent,left):
    for name,point in [('BT_GripR',(0,0,0)),('BT_GripL',left)]:
        marker=bpy.data.objects.new(name,None)
        bpy.context.collection.objects.link(marker)
        marker.parent=parent
        marker.matrix_world=Matrix.Translation(Vector((point[0],-point[2],point[1])))


if __name__=='__main__':
    which=sys.argv[-1]
    (MODELS/'viewmodels').mkdir(parents=True,exist_ok=True)
    if which=='operator': build_operator()
    elif which=='m4': build_viewmodel('m4a1','BT_FP_M4','BT_M4A1','BT_Arms_Rifle')
    elif which=='ak': build_viewmodel('ak47','BT_FP_AK','BT_AK47','BT_Arms_AK')
    elif which=='pistol': build_viewmodel('m1911','BT_FP_M1911','BT_M1911','BT_Arms_Pistol')
    else: raise SystemExit('Expected operator, m4, ak or pistol')
