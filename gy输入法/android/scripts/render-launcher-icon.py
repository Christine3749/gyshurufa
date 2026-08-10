#!/usr/bin/env python3
"""Render GY Android launcher adaptive-icon layers from the locked VI tokens.

GY_VISUAL_IDENTITY.md §5: deep-ink tile (#111318) + white "GY", glyph width ~86%
of the small-size safe zone. For adaptive icons (108dp canvas, 66dp safe circle)
we render "GY" at ~58% of canvas width so it stays inside every OEM mask shape.

Regenerate: python android/scripts/render-launcher-icon.py
Outputs: app/src/main/res/mipmap-{mdpi..xxxhdpi}/ic_launcher_{background,foreground}.png
"""

from __future__ import annotations

import os
from pathlib import Path

import matplotlib
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / "app" / "src" / "main" / "res"
FONT = Path(os.path.dirname(matplotlib.__file__)) / "mpl-data" / "fonts" / "ttf" / "DejaVuSans-Bold.ttf"

INK = (0x11, 0x13, 0x18, 0xFF)  # GY Ink #111318
WHITE = (0xFF, 0xFF, 0xFF, 0xFF)

# Adaptive-icon layer edge in px per density (108dp canvas).
DENSITIES = {
    "mdpi": 108,
    "hdpi": 162,
    "xhdpi": 216,
    "xxhdpi": 324,
    "xxxhdpi": 432,
}

SUPERSAMPLE = 4


def render_background(size: int) -> Image.Image:
    img = Image.new("RGBA", (size, size), INK)
    return img


def render_foreground(size: int) -> Image.Image:
    big = size * SUPERSAMPLE
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    target_width = big * 0.58
    font_size = int(big * 0.60)
    font = ImageFont.truetype(str(FONT), font_size)
    bbox = draw.textbbox((0, 0), "GY", font=font)
    glyph_w = bbox[2] - bbox[0]
    if glyph_w > target_width:
        font_size = int(font_size * target_width / glyph_w)
        font = ImageFont.truetype(str(FONT), font_size)
        bbox = draw.textbbox((0, 0), "GY", font=font)
        glyph_w = bbox[2] - bbox[0]
    glyph_h = bbox[3] - bbox[1]

    x = (big - glyph_w) / 2 - bbox[0]
    y = (big - glyph_h) / 2 - bbox[1]
    draw.text((x, y), "GY", font=font, fill=WHITE)

    return img.resize((size, size), Image.LANCZOS)


def main() -> None:
    if not FONT.is_file():
        raise SystemExit(f"font not found: {FONT}")
    for density, size in DENSITIES.items():
        out_dir = RES / f"mipmap-{density}"
        out_dir.mkdir(parents=True, exist_ok=True)
        render_background(size).save(out_dir / "ic_launcher_background.png")
        render_foreground(size).save(out_dir / "ic_launcher_foreground.png")
        print(f"{density}: {size}px background+foreground written")
    print("launcher icons rendered from VI tokens (ink tile + white GY)")


if __name__ == "__main__":
    main()
