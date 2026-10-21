"""Atlas the operator's opaque surfaces without changing its mesh, skin or rig."""
from copy import deepcopy
from io import BytesIO
import json
import hashlib
from pathlib import Path
import struct

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/models/characters/BT_Operator.glb"
TARGET = SOURCE.with_name("BT_Operator_Batched.glb")
DTYPES = {5121: "u1", 5123: "<u2", 5125: "<u4", 5126: "<f4"}
WIDTHS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}
PAD = 8


def main():
    file = SOURCE.read_bytes()
    length = struct.unpack_from("<I", file, 12)[0]
    source = json.loads(file[20:20 + length])
    binary = file[28 + length:]
    assert not source.get("animations") and len(source["meshes"]) == 1

    def array(index):
        accessor = source["accessors"][index]
        assert "sparse" not in accessor and not accessor.get("normalized")
        view = source["bufferViews"][accessor["bufferView"]]
        dtype = np.dtype(DTYPES[accessor["componentType"]])
        width = WIDTHS[accessor["type"]]
        return np.ndarray((accessor["count"], width), dtype=dtype, buffer=binary,
                          offset=view.get("byteOffset", 0) + accessor.get("byteOffset", 0),
                          strides=(view.get("byteStride", width * dtype.itemsize), dtype.itemsize)).copy()

    def image(texture):
        entry = source["textures"][texture["index"]]
        index = entry.get("source", entry.get("extensions", {}).get("EXT_texture_webp", {}).get("source"))
        item = source["images"][index]
        view = source["bufferViews"][item["bufferView"]]
        return Image.open(BytesIO(binary[view["byteOffset"]:view["byteOffset"] + view["byteLength"]])).convert("RGBA")

    def sample(texture, size, default):
        if texture is None:
            return np.broadcast_to(np.array(default, dtype=np.float32), (size, size, 4)).copy()
        return np.asarray(image(texture).resize((size, size), Image.Resampling.LANCZOS), dtype=np.float32) / 255

    def color_factor(pixels, factor):
        rgb = pixels[..., :3]
        linear = np.where(rgb <= .04045, rgb / 12.92, ((rgb + .055) / 1.055) ** 2.4)
        linear *= np.array(factor[:3], dtype=np.float32)
        pixels[..., :3] = np.where(linear <= .0031308, linear * 12.92, 1.055 * np.maximum(linear, 0) ** (1 / 2.4) - .055)
        pixels[..., 3] *= factor[3] if len(factor) == 4 else 1
        return pixels

    opaque = [i for i, material in enumerate(source["materials"]) if material.get("alphaMode", "OPAQUE") == "OPAQUE"]
    placements = {}
    x = y = row_height = 0
    atlas_width = 4096
    for index in opaque:
        material = source["materials"][index]
        pbr = material.get("pbrMetallicRoughness", {})
        textures = [material.get("normalTexture"), material.get("emissiveTexture"), pbr.get("baseColorTexture"), pbr.get("metallicRoughnessTexture")]
        size = max([max(image(t).size) for t in textures if t] or [16])
        if x + size + PAD * 2 > atlas_width:
            x, y, row_height = 0, y + row_height, 0
        placements[index] = (x + PAD, y + PAD, size)
        x += size + PAD * 2
        row_height = max(row_height, size + PAD * 2)
    atlas_height = y + row_height
    atlases = {name: Image.new("RGBA", (atlas_width, atlas_height)) for name in ["color", "normal", "surface", "emission"]}
    for index, (x, y, size) in placements.items():
        material = source["materials"][index]
        pbr = material.get("pbrMetallicRoughness", {})
        color = color_factor(sample(pbr.get("baseColorTexture"), size, [1, 1, 1, 1]), pbr.get("baseColorFactor", [1, 1, 1, 1]))
        normal = sample(material.get("normalTexture"), size, [.5, .5, 1, 1])
        surface = sample(pbr.get("metallicRoughnessTexture"), size, [1, 1, 1, 1])
        surface[..., 1] *= pbr.get("roughnessFactor", 1)
        surface[..., 2] *= pbr.get("metallicFactor", 1)
        specular = material.get("extensions", {}).get("KHR_materials_specular", {})
        surface[..., 3] = sample(specular.get("specularTexture"), size, [1, 1, 1, 1])[..., 3] * specular.get("specularFactor", 1)
        emission = color_factor(sample(material.get("emissiveTexture"), size, [1, 1, 1, 1]), material.get("emissiveFactor", [0, 0, 0]))
        for name, pixels in [("color", color), ("normal", normal), ("surface", surface), ("emission", emission)]:
            padded = np.pad(np.uint8(np.clip(pixels, 0, 1) * 255 + .5), ((PAD, PAD), (PAD, PAD), (0, 0)), mode="wrap")
            atlases[name].paste(Image.fromarray(padded), (x - PAD, y - PAD))

    doc = deepcopy(source)
    for key in ["extensionsRequired", "extensionsUsed"]:
        if key in doc:
            doc[key] = [name for name in doc[key] if name != "EXT_texture_webp"]
    doc.update(accessors=[], bufferViews=[], images=[], textures=[], samplers=[{"magFilter": 9729, "minFilter": 9987, "wrapS": 33071, "wrapT": 33071}])
    output = bytearray()

    def view(data):
        output.extend(b"\0" * (-len(output) % 4))
        index = len(doc["bufferViews"])
        doc["bufferViews"].append({"buffer": 0, "byteOffset": len(output), "byteLength": len(data)})
        output.extend(data)
        return index

    def accessor(values, component, kind):
        values = np.ascontiguousarray(values, dtype=DTYPES[component])
        item = {"bufferView": view(values.tobytes()), "componentType": component, "count": len(values), "type": kind}
        if kind == "VEC3":
            item.update(min=values.min(axis=0).tolist(), max=values.max(axis=0).tolist())
        doc["accessors"].append(item)
        return len(doc["accessors"]) - 1

    for skin in doc["skins"]:
        skin["inverseBindMatrices"] = accessor(array(skin["inverseBindMatrices"]), 5126, "MAT4")
    for name, atlas in atlases.items():
        encoded = BytesIO()
        atlas.save(encoded, format="WEBP", lossless=True, method=4)
        doc["images"].append({"bufferView": view(encoded.getvalue()), "mimeType": "image/webp", "name": "BT_OperatorAtlas_" + name})
        doc["textures"].append({"extensions": {"EXT_texture_webp": {"source": len(doc["images"]) - 1}}, "sampler": 0})
    doc.setdefault("extensionsUsed", []).append("EXT_texture_webp")
    doc.setdefault("extensionsRequired", []).append("EXT_texture_webp")
    doc["materials"] = [{"name": "BT_OperatorAtlas", "doubleSided": True,
        "pbrMetallicRoughness": {"baseColorTexture": {"index": 0}, "metallicRoughnessTexture": {"index": 2}},
        "normalTexture": {"index": 1}, "emissiveFactor": [1, 1, 1], "emissiveTexture": {"index": 3}}]
    groups = {0: []}
    for primitive in source["meshes"][0]["primitives"]:
        material = primitive["material"]
        if material in opaque:
            groups[0].append(primitive)
        else:
            doc["materials"].append(deepcopy(source["materials"][material]))
            assert not any("Texture" in key for key in doc["materials"][-1])
            groups[len(doc["materials"]) - 1] = [primitive]
    primitives = []
    original_triangles = 0
    for material, group in groups.items():
        attributes = {name: [] for name in group[0]["attributes"]}
        indices = []
        count = 0
        for primitive in group:
            values = {name: array(index) for name, index in primitive["attributes"].items()}
            if material == 0:
                uv = values["TEXCOORD_0"]
                assert uv.min() >= -.005 and uv.max() <= 1.005
                x, y, size = placements[primitive["material"]]
                values["TEXCOORD_0"] = (uv * size + [x, y]) / [atlas_width, atlas_height]
            index = array(primitive["indices"])
            original_triangles += len(index) // 3
            assert int(index.max()) < len(values["POSITION"])
            indices.append(index.astype(np.uint32) + count)
            for name in attributes:
                attributes[name].append(values[name])
            count += len(values["POSITION"])
        result = {"material": material, "mode": 4, "attributes": {}}
        for name, parts in attributes.items():
            original = source["accessors"][group[0]["attributes"][name]]
            result["attributes"][name] = accessor(np.concatenate(parts), original["componentType"], original["type"])
        result["indices"] = accessor(np.concatenate(indices), 5125, "SCALAR")
        primitives.append(result)
    doc["meshes"][0]["primitives"] = primitives
    assert original_triangles == sum(len(array(p["indices"])) // 3 for p in source["meshes"][0]["primitives"])
    doc["buffers"] = [{"byteLength": len(output)}]
    encoded = json.dumps(doc, separators=(",", ":")).encode()
    encoded += b" " * (-len(encoded) % 4)
    output.extend(b"\0" * (-len(output) % 4))
    TARGET.write_bytes(struct.pack("<III", 0x46546C67, 2, 28 + len(encoded) + len(output)) + struct.pack("<II", len(encoded), 0x4E4F534A) + encoded + struct.pack("<II", len(output), 0x004E4942) + output)
    metadata_path = ROOT / "assets/data/model_meta.json"
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    metadata["BT_Operator_Batched"] = deepcopy(metadata["BT_Operator"])
    metadata["BT_Operator_Batched"]["source_sha256"] = hashlib.sha256(file).hexdigest()
    metadata_path.write_text(json.dumps(metadata, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(f"Operator: 19 -> {len(primitives)} surfaces; {original_triangles} triangles; atlas {atlas_width}x{atlas_height}; {TARGET.stat().st_size} bytes")


if __name__ == "__main__":
    main()
