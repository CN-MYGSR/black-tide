"""Pack the existing roughness into albedo alpha, preserving decoded RGB pixels."""
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1] / "assets/textures/environment"
for name in ["Grass001", "Ground109", "Rock030", "Ground054"]:
    color = Image.open(ROOT / name / "Color.jpg").convert("RGBA")
    roughness = Image.open(ROOT / name / "Roughness.jpg").convert("RGB").getchannel("R")
    assert color.size == roughness.size
    color.putalpha(roughness)
    target = ROOT / name / "ColorRoughness.png"
    color.save(target, optimize=True)
    restored = Image.open(target)
    assert restored.tobytes() == color.tobytes()
    print(name, color.size, target.stat().st_size)
