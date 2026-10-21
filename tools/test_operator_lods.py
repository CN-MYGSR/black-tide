"""Check original geometry/skin preservation and the posed size of every distance mesh."""
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import struct
import numpy as np

ROOT = Path(__file__).resolve().parents[1]


def read(name):
    raw = (ROOT / 'assets/models/characters' / (name + '.glb')).read_bytes()
    length = struct.unpack_from('<I', raw, 12)[0]
    doc = json.loads(raw[20:20 + length])
    binary = raw[28 + length:]
    def array(index):
        a = doc['accessors'][index]
        v = doc['bufferViews'][a['bufferView']]
        dtype = np.dtype({5121: 'u1', 5123: '<u2', 5125: '<u4', 5126: '<f4'}[a['componentType']])
        width = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}[a['type']]
        return np.ndarray((a['count'], width), dtype=dtype, buffer=binary,
            offset=v.get('byteOffset', 0) + a.get('byteOffset', 0),
            strides=(v.get('byteStride', width * dtype.itemsize), dtype.itemsize))
    return raw, doc, binary, array


def transforms(doc, posed):
    result = {}
    def visit(index, parent):
        node = doc['nodes'][index]
        if 'matrix' in node:
            local = np.array(node['matrix']).reshape(4, 4).T
        else:
            x, y, z, w = node.get('rotation', [0, 0, 0, 1])
            local = np.eye(4)
            local[:3, :3] = np.array([
                [1-2*(y*y+z*z), 2*(x*y-z*w), 2*(x*z+y*w)],
                [2*(x*y+z*w), 1-2*(x*x+z*z), 2*(y*z-x*w)],
                [2*(x*z-y*w), 2*(y*z+x*w), 1-2*(x*x+y*y)]]) @ np.diag(node.get('scale', [1, 1, 1]))
            local[:3, 3] = node.get('translation', [0, 0, 0])
        if posed and node.get('name') in ['Shoulder_L', 'Shoulder_R', 'UpperLeg_L']:
            angle = .5 if node['name'] == 'Shoulder_L' else -.4
            c, s = np.cos(angle), np.sin(angle)
            local = local @ np.array([[1, 0, 0, 0], [0, c, -s, 0], [0, s, c, 0], [0, 0, 0, 1]])
        result[index] = parent @ local
        for child in node.get('children', []):
            visit(child, result[index])
    for index in doc['scenes'][doc.get('scene', 0)]['nodes']:
        visit(index, np.eye(4))
    return result


raw, source, binary, sa = read('BT_Operator_Batched')
_, lod, lb, la = read('BT_Operator_LOD')
meta = json.loads((ROOT / 'assets/data/model_meta.json').read_text(encoding='utf-8'))['BT_Operator_LOD']
assert hashlib.sha256(raw).hexdigest() == meta['source_sha256'], 'Rebuild stale LOD'
assert lb[:len(binary)] == binary, 'Original binary changed'
assert lod['skins'] == source['skins']
assert lod['materials'] == source['materials']
assert lod['meshes'][0] == source['meshes'][0]
for old, new in zip(source['nodes'], lod['nodes']):
    new = deepcopy(new)
    if 'mesh' in old:
        new['name'] = old['name']
    if 'children' in new:
        new['children'] = [i for i in new['children'] if i < len(source['nodes'])]
    assert old == new, 'Node / rest transform changed'
skin = lod['skins'][0]
bind = la(skin['inverseBindMatrices']).reshape(-1, 4, 4).transpose(0, 2, 1)
for posed in [False, True]:
    world = transforms(lod, posed)
    matrices = np.stack([world[i] for i in skin['joints']]) @ bind
    bounds = []
    for level, mesh in enumerate(lod['meshes']):
        points = []
        triangles = 0
        for p in mesh['primitives']:
            attrs = {k: la(v) for k, v in p['attributes'].items()}
            vertices = attrs['POSITION']
            joints, weights = attrs['JOINTS_0'], attrs['WEIGHTS_0']
            assert all(np.isfinite(v).all() for v in attrs.values())
            assert np.all(weights >= 0) and joints.max() < len(bind)
            np.testing.assert_allclose(weights.sum(axis=1), 1, atol=1e-6)
            indices = la(p['indices'])[:, 0]
            assert indices.max() < len(vertices)
            triangles += len(indices) // 3
            vectors = np.column_stack([vertices, np.ones(len(vertices))])
            deformed = sum(np.einsum('nij,nj->ni', matrices[joints[:, i]], vectors) * weights[:, i, None] for i in range(4))
            points.append(deformed[indices, :3])
        assert triangles == meta['lod_tris'][level]
        points = np.concatenate(points)
        bounds.append(np.array([points.min(axis=0), points.max(axis=0)]))
        if not posed:
            height = np.ptp(points[:, 1])
            assert 1.79 < height < 1.81, (level, height)
        np.testing.assert_allclose(bounds[-1], bounds[0], atol=.035 if posed else .02)
        print('LOD_BOUNDS', 'posed' if posed else 'rest', level, np.round(bounds[-1], 5).tolist())
assert meta['lod_tris'][1] < meta['lod_tris'][0] * .3
assert meta['lod_tris'][2] < meta['lod_tris'][0] * .1
print('LOD_PASSED: exact close mesh / skeleton / skin / material, rest height and posed bounds at all distances')
