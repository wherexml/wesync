#!/usr/bin/env python3
"""Rasterize the checked-in SVG artwork deterministically using macOS tools."""
from pathlib import Path
import hashlib
import json
import subprocess

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / "Resources/Brand"


def run(*args):
    subprocess.run(args, check=True, stdout=subprocess.DEVNULL)


def main():
    iconset = DEST / "GreenBubbles.iconset"
    iconset.mkdir(parents=True, exist_ok=True)
    source = ROOT / "assets/greenbubbles-icon.svg"
    for size in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            pixels = str(size * scale)
            suffix = "@2x" if scale == 2 else ""
            run("/usr/bin/sips", "-s", "format", "png", "-z", pixels, pixels,
                str(source), "--out", str(iconset / f"icon_{size}x{size}{suffix}.png"))
    run("/usr/bin/iconutil", "-c", "icns", str(iconset), "-o", str(DEST / "GreenBubbles.icns"))
    for pixels, name in ((22, "GreenBubbles-menubar.png"), (44, "GreenBubbles-menubar@2x.png"),
                         (44, "GreenBubbles-black.png")):
        run("/usr/bin/sips", "-s", "format", "png", "-z", str(pixels), str(pixels),
            str(ROOT / "assets/greenbubbles-menubar.svg"), "--out", str(DEST / name))
    sources = ("greenbubbles-twin-bots.svg", "greenbubbles-icon.svg", "greenbubbles-menubar.svg")
    (DEST / "generation.json").write_text(json.dumps({
        "tool": "macOS sips and iconutil; exact SVG rasterization, no AI redraw",
        "sourceArtwork": "User-provided 01-twin-bots.svg, preserved as greenbubbles-twin-bots.svg",
        "product": "Original green paths on a white rounded square, transparent outer corners",
        "menuBar": "Black alpha template, transparent background and eyes; 22pt at 1x and 2x",
        "regenerate": "python3 scripts/generate-brand-assets.py",
        "sources": {name: hashlib.sha256((ROOT / "assets" / name).read_bytes()).hexdigest()
                    for name in sources},
    }, indent=2) + "\n")


if __name__ == "__main__":
    main()
