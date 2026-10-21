"""Prepare the credited CC0 effects from downloaded source packs using FFmpeg."""
from array import array
from pathlib import Path
import argparse
import hashlib
import json
import subprocess
import sys
import wave
import zipfile

ROOT = Path(__file__).resolve().parents[1] / "assets" / "audio"


def prepare(name, source, seconds=None):
    result = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", "pipe:0", "-f", "f32le", "-ac", "1", "-ar", "22050", "pipe:1"],
        input=source, stdout=subprocess.PIPE, check=True,
    )
    samples = array("f")
    samples.frombytes(result.stdout)
    if sys.byteorder != "little":
        samples.byteswap()
    peak = max(abs(v) for v in samples)
    assert peak > 0.001, f"Silent source: {name}"
    onset = next(i for i, value in enumerate(samples) if abs(value) > peak * 0.12)
    start = max(0, onset - 220)
    end = min(len(samples), start + int(seconds * 22050)) if seconds else len(samples)
    samples = samples[start:end]
    # Keep the onset, fade the tail, and normalize to the same headroom as other effects.
    gain = 0.79 / max(abs(v) for v in samples)
    pcm = array("h", (int(max(-1, min(1, value * gain)) * min(1, i / 25, (len(samples) - 1 - i) / 220) * 32767) for i, value in enumerate(samples)))
    if sys.byteorder != "little":
        pcm.byteswap()
    output = ROOT / f"{name}.wav"
    with wave.open(str(output), "wb") as target:
        target.setparams((1, 2, 22050, 0, "NONE", "not compressed"))
        target.writeframes(pcm.tobytes())
    return {"source_sha256": hashlib.sha256(source).hexdigest(), "prepared_sha256": hashlib.sha256(output.read_bytes()).hexdigest()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("sources", type=Path, help="Directory containing extracted firearms/, rpg.zip, ui.zip and reload.wav")
    args = parser.parse_args()
    ROOT.mkdir(parents=True, exist_ok=True)
    provenance = {}
    guns = {"rifle": ("AR-15/D_24P.wav", 0.42), "pistol": ("1911/A_34P.wav", 0.38), "shotgun": ("Mossberg/N_26P.wav", 0.7)}
    for name, (member, duration) in guns.items():
        source = args.sources / "firearms" / "Prepared SFX Library" / member
        provenance[name] = {"pack": "The Free Firearm Sound Library", "member": member, **prepare(name, source.read_bytes(), duration)}
    provenance["reload"] = {"pack": "Gun reload sounds / SpringySpringo", "member": "assaultriflereload1_0.wav", **prepare("reload", (args.sources / "reload.wav").read_bytes(), 1.6)}
    for archive, selections in {"rpg": {"step": "footstep01.ogg"}, "ui": {"click": "click_003.ogg", "success": "confirmation_002.ogg", "failure": "error_004.ogg"}}.items():
        with zipfile.ZipFile(args.sources / f"{archive}.zip") as pack:
            (ROOT / f"LICENSE-Kenney-{archive}.txt").write_bytes(pack.read("License.txt"))
            for name, member in selections.items():
                provenance[name] = {"pack": f"Kenney {archive}", "member": member, **prepare(name, pack.read(f"Audio/{member}"))}
    (ROOT / "sources.json").write_text(json.dumps(provenance, indent=2) + "\n", encoding="utf-8")
    print(f"Prepared {len(provenance)} CC0 sound effects")


if __name__ == "__main__":
    main()
