"""Generate four original feedback/engine effects; leave downloaded CC0 files intact."""
from array import array
from pathlib import Path
import math
import random
import wave

RATE = 22050
ROOT = Path(__file__).resolve().parents[1] / "assets" / "audio"
rng = random.Random(20261021)


def render(name, seconds, sample):
    values = [sample(i / RATE) for i in range(int(RATE * seconds))]
    # Remove DC and leave headroom for overlapping effects.
    mean = sum(values) / len(values)
    peak = max(abs(v - mean) for v in values) or 1
    pcm = array("h", (int(max(-1, min(1, (v - mean) / peak)) * 26000) for v in values))
    if __import__("sys").byteorder != "little":
        pcm.byteswap()
    with wave.open(str(ROOT / f"{name}.wav"), "wb") as output:
        output.setparams((1, 2, RATE, 0, "NONE", "not compressed"))
        output.writeframes(pcm.tobytes())


def noise():
    return rng.uniform(-1, 1)


def main():
    ROOT.mkdir(parents=True, exist_ok=True)
    render("hurt", 0.24, lambda t: min(1, t * 300) * math.exp(-t * 20) * (noise() * 0.4 + math.sin(math.tau * 78 * t)))
    render("hit", 0.075, lambda t: math.exp(-t * 70) * (math.sin(math.tau * 1700 * t) + noise() * 0.25) * min(1, t * 1500))
    for name, rotor in [("engine", False), ("helicopter", True)]:
        def sample(t):
            pulse = (0.5 + 0.5 * math.sin(math.tau * (12 if rotor else 30) * t)) ** (3 if rotor else 1)
            body = sum(math.sin(math.tau * f * t) * gain for f, gain in [(60, 0.7), (120, 0.3), (240, 0.1)])
            return (body * 0.5 + noise() * (0.55 if rotor else 0.15)) * (0.25 + pulse * 0.75) * min(1, t * 150, (2 - t) * 150)
        render(name, 2, sample)
    print(f"Generated four mono PCM effects in {ROOT}")


if __name__ == "__main__":
    main()
