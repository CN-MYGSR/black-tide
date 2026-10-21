"""Download verified CC0 Poly Haven sources for the environment conversion."""
import concurrent.futures
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ("island_tree_01", "island_tree_02", "wild_rooibos_bush",
          "grass_bermuda_01", "grass_medium_01", "fern_02", "rock_moss_set_01", "rock_09")


def fetch(asset):
    folder = ROOT / "_source/environment_models" / asset
    folder.mkdir(parents=True, exist_ok=True)
    response = subprocess.check_output(["curl.exe", "--fail", "--silent", "--show-error",
                                        "--max-time", "60", f"https://api.polyhaven.com/files/{asset}"])
    package = json.loads(response)["gltf"]["1k"]["gltf"]
    files = {f"{asset}_1k.gltf": package, **package["include"]}
    records = []
    for name, info in files.items():
        path = folder / name
        path.parent.mkdir(parents=True, exist_ok=True)
        if not path.exists() or hashlib.md5(path.read_bytes()).hexdigest() != info["md5"]:
            partial = path.with_suffix(path.suffix + ".partial")
            subprocess.run(["curl.exe", "--fail", "--location", "--retry", "2", "--max-time", "180",
                            "--silent", "--show-error", "--output", str(partial), info["url"]], check=True)
            assert hashlib.md5(partial.read_bytes()).hexdigest() == info["md5"], name
            partial.replace(path)
        records.append({"path": path.relative_to(ROOT).as_posix(), "url": info["url"],
                        "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
    print(f"MODEL_SOURCE_OK {asset}", flush=True)
    return {"id": asset, "source": f"https://polyhaven.com/a/{asset}", "files": records}


if __name__ == "__main__":
    (ROOT / "_source").mkdir(exist_ok=True)
    (ROOT / "_source/.gdignore").touch()
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        records = list(pool.map(fetch, ASSETS))
    assert len(records) == len(ASSETS)
    (ROOT / "art/environment/model_sources.json").write_text(json.dumps({
        "license": "CC0-1.0", "license_url": "https://polyhaven.com/license",
        "assets": records}, indent=2), encoding="utf-8")
