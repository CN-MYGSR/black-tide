"""Fetch the CC0 environment maps used by the game; archives stay outside exports."""
import concurrent.futures
import hashlib
import json
from pathlib import Path
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]
ASSETS = {
    "Grass001": "2K-JPG", "Rock030": "2K-JPG",
    "Ground054": "2K-JPG", "Concrete034": "1K-JPG",
    "Asphalt012": "2K-JPG", "WoodFloor051": "1K-JPG",
    "Ground109": "2K-JPG",
    "Fabric029": "1K-JPG", "Metal032": "1K-JPG",
}
MAPS = ("Color", "NormalGL", "Roughness")


def fetch(asset):
    package = f"{asset}_{ASSETS[asset]}.zip"
    url = f"https://ambientcg.com/get?file={package}"
    archive = ROOT / "_source/environment" / package
    archive.parent.mkdir(parents=True, exist_ok=True)
    if not archive.exists():
        partial = archive.with_suffix(".partial")
        subprocess.run(["curl.exe", "--fail", "--location", "--retry", "2",
                        "--max-time", "180", "--silent", "--show-error",
                        "--output", str(partial), url], check=True)
        # Validate before committing a download to the reusable cache.
        with zipfile.ZipFile(partial) as check:
            assert check.testzip() is None, package
        partial.replace(archive)
    output = ROOT / "assets/textures/environment" / asset
    output.mkdir(parents=True, exist_ok=True)
    files = []
    with zipfile.ZipFile(archive) as source:
        for kind in MAPS:
            name = f"{asset}_{ASSETS[asset]}_{kind}.jpg"
            data = source.read(name)
            target = output / f"{kind}.jpg"
            target.write_bytes(data)
            files.append({"path": target.relative_to(ROOT).as_posix(),
                          "sha256": hashlib.sha256(data).hexdigest()})
    print(f"OK {asset}: {len(files)} maps", flush=True)
    return {"id": asset, "package": package, "source": f"https://ambientcg.com/a/{asset}",
            "download": url, "archive_sha256": hashlib.sha256(archive.read_bytes()).hexdigest(),
            "files": files}


if __name__ == "__main__":
    (ROOT / "_source").mkdir(exist_ok=True)
    (ROOT / "_source/.gdignore").touch()
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        entries = list(pool.map(fetch, ASSETS))
    assert len(entries) == len(ASSETS) and all(len(e["files"]) == 3 for e in entries)
    target = ROOT / "art/environment"
    target.mkdir(parents=True, exist_ok=True)
    (target / "sources.json").write_text(json.dumps({
        "license": "CC0-1.0", "license_url": "https://docs.ambientcg.com/license/",
        "assets": entries}, indent=2), encoding="utf-8")
