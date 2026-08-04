#!/usr/bin/env python3
"""Rasterize the locked GY wordmark (native/installer/assets/gy-tray-icon.svg)
into a macOS .iconset. The SVG is two absolute-coordinate paths (M/C/H/V/L/Z)
on a 256 canvas with transform translate(4 48) scale(1.58); we sample the
cubic beziers and fill polygons with PIL at 4x supersampling."""
import re
from pathlib import Path
from PIL import Image, ImageDraw

CANVAS = 256
SS = 4  # supersample factor


def cubic(p0, p1, p2, p3, n=64):
    pts = []
    for i in range(1, n + 1):
        t = i / n
        mt = 1 - t
        x = mt**3 * p0[0] + 3 * mt**2 * t * p1[0] + 3 * mt * t**2 * p2[0] + t**3 * p3[0]
        y = mt**3 * p0[1] + 3 * mt**2 * t * p1[1] + 3 * mt * t**2 * p2[1] + t**3 * p3[1]
        pts.append((x, y))
    return pts


def parse_path(d):
    tokens = re.findall(r"[MC HVLZmc hl vz]|-?\d+(?:\.\d+)?".replace(" ", ""), d)
    pts, i, cur = [], 0, (0, 0)
    start = None
    while i < len(tokens):
        cmd = tokens[i]
        i += 1
        if cmd == "M":
            cur = (float(tokens[i]), float(tokens[i + 1])); i += 2
            pts.append(cur); start = cur
        elif cmd == "C":
            p1 = (float(tokens[i]), float(tokens[i + 1]))
            p2 = (float(tokens[i + 2]), float(tokens[i + 3]))
            p3 = (float(tokens[i + 4]), float(tokens[i + 5])); i += 6
            seg = cubic(cur, p1, p2, p3)
            pts.extend(seg); cur = p3
        elif cmd == "L":
            cur = (float(tokens[i]), float(tokens[i + 1])); i += 2
            pts.append(cur)
        elif cmd == "H":
            cur = (float(tokens[i]), cur[1]); i += 1
            pts.append(cur)
        elif cmd == "V":
            cur = (cur[0], float(tokens[i])); i += 1
            pts.append(cur)
        elif cmd == "Z":
            if start: pts.append(start)
    return pts


G_PATH = ("M72 26C65 18 54 13 40 13C21 13 8 28 8 50C8 72 21 87 40 87"
          "C56 87 68 77 72 63V52H40V66H57C54 72 48 74 40 74C28 74 21 64 21 50"
          "C21 36 28 26 40 26C49 26 56 31 60 37L72 26Z")
Y_PATH = "M80 15H94L114 50L134 15H148L121 60V87H107V60L80 15Z"


def render(size):
    img = Image.new("RGBA", (size * SS, size * SS), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    k = size * SS / CANVAS
    # macOS systemGray (#8E8E93) rounded square, matching platform icons;
    # white GY wordmark on top (brand glyph unchanged, background only).
    radius = int(size * SS * 0.2237)  # platform icon corner ratio
    draw.rounded_rectangle([0, 0, size * SS - 1, size * SS - 1],
                           radius=radius, fill=(142, 142, 147, 255))
    for d in (G_PATH, Y_PATH):
        poly = [((x * 1.58 + 4) * k, (y * 1.58 + 48) * k) for x, y in parse_path(d)]
        draw.polygon(poly, fill=(255, 255, 255, 255))
    return img.resize((size, size), Image.LANCZOS)


def main():
    root = Path(__file__).resolve().parent.parent
    iconset = root / "build" / "AppIcon.iconset"
    iconset.mkdir(parents=True, exist_ok=True)
    for base in (16, 32, 128, 256, 512):
        for scale, suffix in ((1, ""), (2, "@2x")):
            px = base * scale
            name = f"icon_{base}x{base}{suffix}.png"
            render(px).save(iconset / name)
    print(f"iconset written: {iconset}")


if __name__ == "__main__":
    main()
