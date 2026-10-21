"""Calibrate existing weapon geometry to the same grip contract as the free rigs."""
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
import bpy,bmesh
from mathutils import Matrix,Vector
from assemble_realistic_assets import ART,ROOT,MODELS,export,pack_materials,add_grip_markers,animate_reload,set_world_rotation

# Blender coordinates in the original POLYGON model: x right, -y muzzle, z up.
# Firing web, support palm, iron-sight point (optical glass takes precedence).
FITS={
 'SM_Wep_Preset_A_Rifle_02':((0,.015,.065),(0,-.36,.055),None),
 'SM_Wep_Preset_A_Complex_01':((0,.015,.065),(0,-.34,.035),None),
 'SM_Wep_Preset_A_SMG_01':((0,.015,.065),(0,-.30,.055),None),
 'SM_Wep_Preset_A_Heavy_01':((0,.015,.065),(0,-.42,.055),None),
 'SM_Wep_Preset_A_Sniper_01':((0,.015,.065),(0,-.42,.055),None),
 'SM_Wep_MachineGun_USA_01':((0,.015,.065),(0,-.40,.060),(0,-.04,.18)),
 'SM_Wep_Pistol_01':((0,.020,.030),(0,.020,.030),(0,.035,.084)),
 'SM_Wep_Shotgun_01':((0,.015,.045),(0,-.38,.025),(0,-.04,.130)),
 'SM_Wep_RocketLauncher_01':((0,.18,-.055),(0,-.20,-.075),(.12,.18,.125)),
 'SM_Wep_Preset_B_Complex_01':((0,.015,.065),(0,-.39,.055),None),
 'SM_Wep_Preset_B_SMG_01':((0,.015,.065),(0,-.31,.055),None),
 'SM_Wep_Preset_B_Heavy_01':((0,.015,.065),(0,-.42,.055),(0,-.04,.17)),
 'SM_Wep_Preset_B_Sniper_01':((0,.015,.065),(0,-.39,.055),None),
 'SM_Wep_Sniper_01':((0,.015,.035),(0,-.40,.005),(0,-.04,.120)),
 'SM_Wep_Pistol_Small_01':((0,.020,.025),(0,.020,.025),(0,.030,.080)),
 'SM_Wep_MachineGun_Bandit_01':((0,.015,.065),(0,-.39,.050),(0,-.04,.17)),
 'SM_Wep_RPG_01':((0,.015,.035),(0,-.22,.030),(0,.218,.22)),
}

def open_base(pistol=False):
    bpy.ops.wm.open_mainfile(filepath=str(ART/('BT_FP_M1911.blend' if pistol else 'BT_FP_M4.blend')))
    bpy.context.preferences.filepaths.save_version=0
    bpy.context.scene.frame_set(0)
    arm=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
    meshes=[o for o in bpy.context.scene.objects if o.type=='MESH' and 'FPArms' in o.name]
    arm.animation_data_clear()
    arm_world=arm.matrix_world.copy()
    mesh_world={o:o.matrix_world.copy() for o in meshes}
    arm.parent=None; arm.matrix_world=arm_world
    for o in meshes:
        o.parent=arm; o.matrix_world=mesh_world[o]
    for o in list(bpy.context.scene.objects):
        if o not in [arm,*meshes]: bpy.data.objects.remove(o,do_unlink=True)
    return arm,meshes

def bind_pose(arm,meshes):
    for obj in meshes:
        bpy.context.view_layer.objects.active=obj
        for mod in list(obj.modifiers):
            if mod.type=='ARMATURE': bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.context.view_layer.objects.active=arm
    bpy.ops.object.mode_set(mode='POSE'); bpy.ops.pose.armature_apply(selected=False); bpy.ops.object.mode_set(mode='OBJECT')
    for obj in meshes:
        mod=obj.modifiers.new('Fitted hand contact','ARMATURE'); mod.object=arm

def fit_left(arm,desired):
    upper=arm.pose.bones['UpArm_L']; fore=arm.pose.bones['Forearm_L']; hand=arm.pose.bones['Hand_L']
    ctrl=arm.pose.bones['IK_Hand_Cntrl_L']
    s=(arm.matrix_world@upper.matrix).translation; e=(arm.matrix_world@fore.matrix).translation
    w=arm.matrix_world@hand.head
    a=(e-s).length; b=(w-e).length
    d=(desired-s).length
    assert d<a+b-.001,('Unreachable support grip',d,a+b)
    direction=(desired-s).normalized(); along=(a*a-b*b+d*d)/(2*d)
    height=max(0,a*a-along*along)**.5
    pole=e-s; pole-=direction*pole.dot(direction)
    elbow=s+direction*along+pole.normalized()*height
    wrist_local=(arm.matrix_world@fore.matrix).inverted()@w
    set_world_rotation(arm,upper,(e-s).rotation_difference(elbow-s))
    fore_world=arm.matrix_world@fore.matrix
    set_world_rotation(arm,fore,(fore_world@wrist_local-elbow).rotation_difference(desired-elbow))
    xf=arm.matrix_world@ctrl.matrix; xf.translation+=desired-w
    ctrl.matrix=arm.matrix_world.inverted()@xf
    bpy.context.view_layer.update()

def export_hand(pistol,side):
    arm,meshes=open_base(pistol)
    hand_world=arm.matrix_world@arm.pose.bones['Hand_'+side].matrix
    origin=Vector((0,0,0)) if pistol or side=='R' else Vector((0,-.29,-.025))
    for obj in meshes:
        bpy.context.view_layer.objects.active=obj
        for mod in list(obj.modifiers):
            if mod.type=='ARMATURE': bpy.ops.object.modifier_apply(modifier=mod.name)
        groups={g.index:g.name for g in obj.vertex_groups}
        keep=[sum(g.weight for g in v.groups if groups[g.group]=='Hand_'+side or groups[g.group].startswith('Bone_'+side+'.'))>.45 for v in obj.data.vertices]
        bm=bmesh.new(); bm.from_mesh(obj.data); bm.verts.ensure_lookup_table()
        bmesh.ops.delete(bm,geom=[v for v in bm.verts if not keep[v.index]],context='VERTS')
        bm.to_mesh(obj.data); bm.free()
        world=obj.matrix_world.copy(); obj.parent=None; obj.matrix_world=Matrix.Identity(4)
        obj.data.transform(Matrix.Translation(-origin)@world)
        obj.name='BT_ClosedGlove_'+side
    bpy.data.objects.remove(arm,do_unlink=True)
    marker=bpy.data.objects.new('BT_Wrist',None); bpy.context.collection.objects.link(marker)
    wrist=Matrix.Translation(-origin)@hand_world
    marker.matrix_world=Matrix.LocRotScale(wrist.translation,wrist.to_quaternion(),Vector((1,1,1)))
    for obj in meshes:
        obj.name='BT_Glove_Close'
        low=obj.copy(); low.data=obj.data.copy(); bpy.context.collection.objects.link(low)
        low.name='BT_Glove_Far'
        bpy.context.view_layer.objects.active=low
        dec=low.modifiers.new('Distant glove budget','DECIMATE'); dec.ratio=.18
        bpy.ops.object.modifier_apply(modifier=dec.name)
    name='BT_Hand_'+side+('_Pistol' if pistol else '_Rifle')
    export(name,'viewmodels')

def build_fitted(name):
    pistol='Pistol' in name
    arm,meshes=open_base(pistol)
    before=set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=str(MODELS/'weapons'/(name+'.glb')))
    imported=[o for o in bpy.context.scene.objects if o not in before]
    right,left,iron=FITS[name]
    normalize=Matrix.Scale(.7,4)@Matrix.Translation(-Vector(right))
    gun=bpy.data.objects.new('Gun_'+name,None); bpy.context.collection.objects.link(gun)
    gun_parts=[]
    for obj in imported:
        if obj.type=='MESH':
            world=normalize@obj.matrix_world
            obj.parent=gun; obj.matrix_world=Matrix.Identity(4); obj.data.transform(world)
            for material in obj.data.materials:
                if material: material['bt_shared_atlas']=True
            gun_parts.append(obj)
    for obj in imported:
        if obj.type!='MESH': bpy.data.objects.remove(obj,do_unlink=True)
    palm=normalize@Vector(left)
    old_palm=Vector() if pistol else Vector((0,-.29,-.025))
    wrist=arm.matrix_world@arm.pose.bones['Hand_L'].head
    fit_left(arm,wrist+palm-old_palm)
    bind_pose(arm,meshes)
    left_godot=(palm.x,palm.z,-palm.y)
    add_grip_markers(gun,left_godot)
    glass=next((o for o in gun_parts if 'Sight_Glass' in o.name and 'RailCanted' not in o.name),None)
    if glass:
        points=[glass.matrix_world@Vector(p) for p in glass.bound_box]
        point=Vector(((min(p.x for p in points)+max(p.x for p in points))*.5,
                      max(p.y for p in points),(min(p.z for p in points)+max(p.z for p in points))*.5))
    else: point=normalize@Vector(iron)
    sight=bpy.data.objects.new('BT_AimAnchor',None); bpy.context.collection.objects.link(sight)
    sight.parent=gun; sight.matrix_world=Matrix.Translation(point)
    pack_materials()
    bpy.ops.wm.save_as_mainfile(filepath=str(ART/('BT_FP_'+name+'.blend')))
    # World models contain only the gun and contact markers.
    bpy.ops.object.select_all(action='DESELECT'); gun.select_set(True)
    for obj in gun.children_recursive: obj.select_set(True)
    out=MODELS/'weapons'/('BT_Fitted_'+name+'.glb')
    bpy.ops.export_scene.gltf(filepath=str(out),export_format='GLB',use_selection=True,export_animations=False,export_extras=True)
    from assemble_realistic_assets import register
    register('BT_Fitted_'+name,'weapons',gun_parts)
    magazine=next((o for o in gun_parts if '_Mag' in o.name and 'MachineGun_USA_Handle' not in o.name),None)
    animate_reload(arm,magazine,None,name,canonical=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(ART/('BT_FP_'+name+'.blend')))
    export('BT_FP_'+name,'viewmodels',magazine is not None)

if __name__=='__main__':
    mode=sys.argv[-1]
    if mode=='hands':
        for pistol in [False,True]:
            for side in ['R','L']: export_hand(pistol,side)
    elif mode=='all':
        for name in FITS: build_fitted(name)
    elif mode in FITS: build_fitted(mode)
    else: raise SystemExit('Use hands, all, or a weapon ID')
