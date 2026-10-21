"""解包 .unitypackage (gzip tar, GUID/asset + GUID/pathname) 到目标目录。

用法: python extract_unitypackage.py <pkg> <outdir> [ext1,ext2,...]
"""
import gzip
import os
import sys
import tarfile
from pathlib import Path, PureWindowsPath


def main() -> int:
    pkg = sys.argv[1]
    out = sys.argv[2]
    keep = None
    if len(sys.argv) > 3:
        keep = {e.strip().lower() for e in sys.argv[3].split(",") if e.strip()}

    os.makedirs(out, exist_ok=True)
    output_root = Path(out).resolve()
    fh = open(pkg, "rb")
    tar = tarfile.open(fileobj=gzip.GzipFile(fileobj=fh), mode="r:")

    guid2path = {}
    for member in tar:
        if member.name.endswith("/pathname"):
            guid = member.name.split("/")[0]
            raw = tar.extractfile(member).read().decode("utf-8", "replace")
            # pathname 尾部带有 "\n<size>" 之类的附加行，只取第一行
            src_path = raw.split("\n")[0].strip().replace("\\", "/")
            dest = (output_root / src_path).resolve()
            if PureWindowsPath(src_path).drive or src_path.startswith("/") or not dest.is_relative_to(output_root) or dest == output_root:
                raise ValueError(f"unsafe asset path: {src_path!r}")
            guid2path[guid] = dest

    fh.seek(0)
    tar = tarfile.open(fileobj=gzip.GzipFile(fileobj=fh), mode="r:")
    count = 0
    for member in tar:
        parts = member.name.split("/")
        if len(parts) != 2 or parts[1] != "asset":
            continue
        src_path = guid2path.get(parts[0])
        if not src_path:
            continue
        ext = os.path.splitext(src_path)[1].lower()
        if keep is not None and ext not in keep:
            continue
        dest = src_path
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        with open(dest, "wb") as w:
            w.write(tar.extractfile(member).read())
        count += 1
    print("extracted", count)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
