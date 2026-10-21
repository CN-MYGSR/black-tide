"""Verify batching preserves every triangle, skin, node and non-UV attribute."""
import hashlib
import json
from pathlib import Path
import struct
import numpy as np

ROOT = Path(__file__).resolve().parents[1]

def read(name):
    raw = (ROOT / "assets/models/characters" / (name + ".glb")).read_bytes()
    length = struct.unpack_from("<I", raw, 12)[0]
    doc = json.loads(raw[20:20 + length])
    binary = raw[28 + length:]
    def array(index):
        a = doc["accessors"][index]
        v = doc["bufferViews"][a["bufferView"]]
        dtype = np.dtype({5121: "u1", 5123: "<u2", 5125: "<u4", 5126: "<f4"}[a["componentType"]])
        width = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}[a["type"]]
        return np.ndarray((a["count"], width), dtype=dtype, buffer=binary,
            offset=v.get("byteOffset", 0) + a.get("byteOffset", 0),
            strides=(v.get("byteStride", width * dtype.itemsize), dtype.itemsize))
    return raw, doc, array

raw, source, sa = read("BT_Operator")
_, batch, ba = read("BT_Operator_Batched")
meta = json.loads((ROOT / "assets/data/model_meta.json").read_text(encoding="utf-8"))
assert hashlib.sha256(raw).hexdigest() == meta["BT_Operator_Batched"]["source_sha256"], "Rebuild stale batch"
assert source["nodes"] == batch["nodes"]
for old, new in zip(source["skins"], batch["skins"], strict=True):
    assert old["joints"] == new["joints"]
    np.testing.assert_array_equal(sa(old["inverseBindMatrices"]), ba(new["inverseBindMatrices"]))
groups = [[], []]
for primitive in source["meshes"][0]["primitives"]:
    material = source["materials"][primitive["material"]]
    groups[int(material.get("alphaMode", "OPAQUE") != "OPAQUE")].append(primitive)
triangles = 0
for group, result in zip(groups, batch["meshes"][0]["primitives"], strict=True):
    offset = 0
    indices = []
    for primitive in group:
        indices.append(sa(primitive["indices"]).astype(np.uint32) + offset)
        offset += len(sa(primitive["attributes"]["POSITION"]))
    np.testing.assert_array_equal(np.concatenate(indices), ba(result["indices"]))
    triangles += len(ba(result["indices"])) // 3
    for name in result["attributes"]:
        if name != "TEXCOORD_0":
            np.testing.assert_array_equal(np.concatenate([sa(p["attributes"][name]) for p in group]), ba(result["attributes"][name]))
print(f"BATCH_PASSED: {triangles} triangles, all nodes, skin weights and rest matrices preserved")
