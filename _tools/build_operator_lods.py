"""Append Blender-decimated meshes; keep the original glTF skin and close mesh byte-exact."""
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import struct

import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector
from mathutils.bvhtree import BVHTree

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'assets/models/characters/BT_Operator_Batched.glb'
TARGET = SOURCE.with_name('BT_Operator_LOD.glb')
TYPES = {5121: 'u1', 5123: '<u2', 5125: '<u4', 5126: '<f4'}
WIDTHS = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}


def main():
    raw = SOURCE.read_bytes()
    length = struct.unpack_from('<I', raw, 12)[0]
    source = json.loads(raw[20:20 + length])
    binary = raw[28 + length:]
    assert len(source['meshes']) == 1 and not source.get('animations')
    doc = deepcopy(source)
    output = bytearray(binary)

    def array(index):
        a = source['accessors'][index]
        assert 'sparse' not in a and not a.get('normalized')
        v = source['bufferViews'][a['bufferView']]
        dtype = np.dtype(TYPES[a['componentType']])
        width = WIDTHS[a['type']]
        return np.ndarray((a['count'], width), dtype=dtype, buffer=binary,
            offset=v.get('byteOffset', 0) + a.get('byteOffset', 0),
            strides=(v.get('byteStride', width * dtype.itemsize), dtype.itemsize)).copy()

    def accessor(values, component, kind):
        values = np.ascontiguousarray(values, dtype=TYPES[component])
        output.extend(b'\0' * (-len(output) % 4))
        doc['bufferViews'].append({'buffer': 0, 'byteOffset': len(output), 'byteLength': values.nbytes})
        output.extend(values.tobytes())
        item = {'bufferView': len(doc['bufferViews']) - 1, 'componentType': component,
                'count': len(values), 'type': kind}
        if kind == 'VEC3':
            item.update(min=values.min(axis=0).tolist(), max=values.max(axis=0).tolist())
        doc['accessors'].append(item)
        return len(doc['accessors']) - 1

    world = {}
    def visit(index, parent):
        node = source['nodes'][index]
        if 'matrix' in node:
            local = Matrix(np.array(node['matrix']).reshape(4, 4).T.tolist())
        else:
            x, y, z, w = node.get('rotation', [0, 0, 0, 1])
            local = Matrix.LocRotScale(Vector(node.get('translation', [0, 0, 0])),
                Quaternion((w, x, y, z)), Vector(node.get('scale', [1, 1, 1])))
        world[index] = parent @ local
        for child in node.get('children', []):
            visit(child, world[index])
    for index in source['scenes'][source.get('scene', 0)]['nodes']:
        visit(index, Matrix.Identity(4))
    skin = source['skins'][0]
    bind = array(skin['inverseBindMatrices']).reshape(-1, 4, 4).transpose(0, 2, 1)
    matrices = np.stack([np.array(world[i]) for i in skin['joints']]) @ bind

    def blended(joints, weights):
        return (matrices[joints] * weights[:, :, None, None]).sum(axis=1)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version = 0
    mesh_node = next(i for i, n in enumerate(doc['nodes']) if 'mesh' in n)
    doc['nodes'][mesh_node]['name'] = 'BT_Operator_Close'
    counts = [sum(len(array(p['indices'])) // 3 for p in source['meshes'][0]['primitives'])]
    for level, ratio in [('Mid', .24), ('Far', .07)]:
        primitives = []
        level_points = []
        for primitive in source['meshes'][0]['primitives']:
            attrs = {name: array(index) for name, index in primitive['attributes'].items()}
            assert set(attrs) == {'POSITION', 'NORMAL', 'TEXCOORD_0', 'JOINTS_0', 'WEIGHTS_0'}
            indices = array(primitive['indices']).reshape(-1, 3)
            mesh = bpy.data.meshes.new(level)
            # Collapse in the visible rest pose: interpolated weights change bind-space shape.
            vectors = np.column_stack([attrs['POSITION'], np.ones(len(attrs['POSITION']))])
            rest = np.einsum('nij,nj->ni', blended(attrs['JOINTS_0'], attrs['WEIGHTS_0']), vectors)
            mesh.from_pydata(rest[:, :3].tolist(), [], indices.tolist())
            surface = BVHTree.FromPolygons(rest[:, :3].tolist(), indices.tolist(), all_triangles=True)
            uv = mesh.uv_layers.new()
            for loop in mesh.loops:
                uv.data[loop.index].uv = attrs['TEXCOORD_0'][loop.vertex_index]
            for face in mesh.polygons:
                face.use_smooth = True
            obj = bpy.data.objects.new('BT_Operator_' + level, mesh)
            bpy.context.collection.objects.link(obj)
            for joint in range(len(source['skins'][0]['joints'])):
                group = obj.vertex_groups.new(name=str(joint))
                for vertex, (joints, weights) in enumerate(zip(attrs['JOINTS_0'], attrs['WEIGHTS_0'])):
                    weight = float(weights[joints == joint].sum())
                    if weight > 0:
                        group.add([vertex], weight, 'REPLACE')
            bpy.context.view_layer.objects.active = obj
            modifier = obj.modifiers.new('Distance geometry budget', 'DECIMATE')
            modifier.ratio = ratio
            modifier.use_collapse_triangulate = True
            bpy.ops.object.modifier_apply(modifier=modifier.name)
            mesh = obj.data
            # Quadric collapse can overshoot helmet edges; project back onto the original surface.
            for vertex in mesh.vertices:
                vertex.co = surface.find_nearest(vertex.co)[0]
            mesh.update()
            mesh.calc_loop_triangles()
            loops = [i for triangle in mesh.loop_triangles for i in triangle.loops]
            vertices = [mesh.loops[i].vertex_index for i in loops]
            joints = np.zeros((len(mesh.vertices), 4), dtype=np.uint16)
            weights = np.zeros((len(mesh.vertices), 4), dtype=np.float32)
            for vertex in mesh.vertices:
                influences = sorted(vertex.groups, key=lambda g: g.weight, reverse=True)[:4]
                for slot, group in enumerate(influences):
                    joints[vertex.index, slot] = group.group
                    weights[vertex.index, slot] = group.weight
            assert np.all(weights.sum(axis=1) > 0)
            weights /= weights.sum(axis=1, keepdims=True)
            skin_matrices = blended(joints, weights)
            vectors = np.array([(*v.co, 1) for v in mesh.vertices])
            level_points.append(vectors[:, :3])
            positions = np.linalg.solve(skin_matrices, vectors[:, :, None])[:, :3, 0]
            normals = np.array([mesh.corner_normals[i].vector[:] for i in loops])
            normals = np.einsum('nji,nj->ni', skin_matrices[vertices, :3, :3], normals)
            normals /= np.maximum(np.linalg.norm(normals, axis=1, keepdims=True), 1e-10)
            values = {'POSITION': (positions[vertices], 5126, 'VEC3'),
                      'NORMAL': (normals, 5126, 'VEC3'),
                      'TEXCOORD_0': (np.array([mesh.uv_layers.active.data[i].uv[:] for i in loops]), 5126, 'VEC2'),
                      'JOINTS_0': (joints[vertices], 5123, 'VEC4'),
                      'WEIGHTS_0': (weights[vertices], 5126, 'VEC4')}
            result = deepcopy(primitive)
            result['attributes'] = {name: accessor(*value) for name, value in values.items()}
            result['indices'] = accessor(np.arange(len(loops)), 5125, 'SCALAR')
            primitives.append(result)
        points = np.concatenate(level_points)
        assert 1.79 < np.ptp(points[:, 1]) < 1.81, (level, np.ptp(points[:, 1]))
        counts.append(sum(doc['accessors'][p['indices']]['count'] // 3 for p in primitives))
        doc['meshes'].append({'name': 'BT_Operator_' + level, 'primitives': primitives})
        node = deepcopy(source['nodes'][mesh_node])
        node.update(name='BT_Operator_' + level, mesh=len(doc['meshes']) - 1)
        index = len(doc['nodes'])
        doc['nodes'].append(node)
        for parent in doc['nodes'][:index] + doc['scenes']:
            for key in ['children', 'nodes']:
                if mesh_node in parent.get(key, []):
                    parent[key].append(index)
    assert counts[1] < counts[0] * .3 and counts[2] < counts[0] * .1, counts
    assert doc['skins'] == source['skins'] and doc['meshes'][0] == source['meshes'][0]
    assert output[:len(binary)] == binary
    doc['buffers'][0]['byteLength'] = len(output)
    encoded = json.dumps(doc, separators=(',', ':')).encode()
    encoded += b' ' * (-len(encoded) % 4)
    output.extend(b'\0' * (-len(output) % 4))
    result = struct.pack('<4sII', b'glTF', 2, 28 + len(encoded) + len(output))
    result += struct.pack('<I4s', len(encoded), b'JSON') + encoded
    result += struct.pack('<I4s', len(output), b'BIN\0') + output
    pending = TARGET.with_suffix('.glb.tmp')
    pending.write_bytes(result)
    pending.replace(TARGET)
    meta_path = ROOT / 'assets/data/model_meta.json'
    meta = json.loads(meta_path.read_text(encoding='utf-8'))
    meta['BT_Operator_LOD'] = {**meta['BT_Operator_Batched'], 'lod_tris': counts,
        'source_sha256': hashlib.sha256(raw).hexdigest()}
    meta_path.write_text(json.dumps(meta, ensure_ascii=False, indent=1) + '\n', encoding='utf-8')
    print('OPERATOR_LOD', counts, 'original skin / close geometry preserved', flush=True)


if __name__ == '__main__':
    main()
