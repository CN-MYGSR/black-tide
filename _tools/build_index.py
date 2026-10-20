"""建立 unitypackage 的 GUID -> 路径索引，并解析 prefab 里"模型 -> 材质"、"材质 -> 贴图"的对应关系。

材质到贴图走 .mat 里的 _MainTex guid 解析，完全确定，不靠命名猜测。

输出: _build/asset_index.json
"""
import gzip
import json
import os
import re
import sys
import tarfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "_source", "polygon_military")
OUT = os.path.join(ROOT, "_build", "asset_index.json")

MAT_BLOCK_RE = re.compile(r"m_Materials:\s*\n((?:\s*-\s*\{fileID: 2100000, guid: ([0-9a-f]+), type: 2\}\s*\n)+)")
MESH_RE = re.compile(r"m_Mesh: \{fileID: \d+, guid: ([0-9a-f]+), type: 3\}")
MAINTEX_RE = re.compile(r"_MainTex:\s*\n\s*m_Texture: \{fileID: \d+, guid: ([0-9a-f]+)")
BUMP_RE = re.compile(r"_BumpMap:\s*\n\s*m_Texture: \{fileID: \d+, guid: ([0-9a-f]+)")


def main():
    pkg = sys.argv[1]
    fh = open(pkg, "rb")
    tar = tarfile.open(fileobj=gzip.GzipFile(fileobj=fh), mode="r:")
    guid2path = {}
    for member in tar:
        if member.name.endswith("/pathname"):
            raw = tar.extractfile(member).read().decode("utf-8", "replace")
            guid2path[member.name.split("/")[0]] = raw.split("\n")[0].strip()

    # 1) 材质 -> 贴图（_MainTex）
    mat_atlas = {}
    mat_dir = os.path.join(SRC, "Assets", "PolygonMilitary", "Materials")
    for base, _dirs, files in os.walk(mat_dir):
        for fn in files:
            if not fn.endswith(".mat"):
                continue
            with open(os.path.join(base, fn), "r", encoding="utf-8", errors="replace") as f:
                text = f.read()
            name = os.path.splitext(fn)[0]
            m = MAINTEX_RE.search(text)
            tex = os.path.basename(guid2path.get(m.group(1), "")) if m else ""
            mat_atlas[name] = tex or None

    # 2) prefab -> 模型用到的材质
    prefab_dir = os.path.join(SRC, "Assets", "PolygonMilitary", "Prefabs")
    model_materials = {}
    for base, _dirs, files in os.walk(prefab_dir):
        for fn in files:
            if not fn.endswith(".prefab"):
                continue
            with open(os.path.join(base, fn), "r", encoding="utf-8", errors="replace") as f:
                text = f.read()
            meshes = MESH_RE.findall(text)
            if not meshes:
                continue
            fbx = os.path.basename(guid2path.get(meshes[0], ""))
            if not fbx:
                continue
            names = []
            for _blk, g in MAT_BLOCK_RE.findall(text):
                p = guid2path.get(g)
                if p:
                    n = os.path.splitext(os.path.basename(p))[0]
                    if n not in names:
                        names.append(n)
            slot = model_materials.setdefault(fbx, [])
            for n in names:
                if n not in slot:
                    slot.append(n)

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(
            {
                "guid2path": guid2path,
                "model_materials": model_materials,
                "mat_atlas": mat_atlas,
            },
            f,
            ensure_ascii=False,
            indent=1,
        )

    resolved = sum(1 for v in mat_atlas.values() if v)
    print("models:", len(model_materials), "materials:", len(mat_atlas), "with texture:", resolved)
    for k, v in sorted(mat_atlas.items()):
        print("  ", k, "->", v)


if __name__ == "__main__":
    main()
