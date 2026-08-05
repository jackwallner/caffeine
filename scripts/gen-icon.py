#!/usr/bin/env python3
"""Protein Tracker app icon: the grams-left ring, three-quarters closed.

Fleet design language (soft diagonal gradient, one confident white glyph,
generous negative space) applied to this app's actual hero: the ring that says
how much protein is left. Deliberately not a dumbbell, a steak, or a shaker —
the icon is the number's container, which is what the product is.
"""
import os

from PIL import Image, ImageDraw, ImageFilter

S = 1024
SS = 4          # supersample factor
W = S * SS

DEEP = (230, 74, 33)    # Theme.proteinDeep
AMBER = (250, 140, 33)  # Theme.protein

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def gradient(w):
    """Diagonal top-left deep orange -> bottom-right amber."""
    img = Image.new("RGB", (w, w))
    px = img.load()
    for y in range(w):
        for x in range(w):
            t = (x + y) / (2 * (w - 1))
            px[x, y] = lerp(DEEP, AMBER, t)
    return img


def build(size, ring_fraction=0.78):
    img = gradient(W)
    overlay = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)

    margin = W * 0.235
    box = (margin, margin, W - margin, W - margin)
    stroke = int(W * 0.085)

    # Track: the part of the day still to eat, held back so the filled arc
    # carries the weight at small sizes.
    draw.arc(box, start=0, end=360, fill=(255, 255, 255, 70), width=stroke)

    # Progress: starts at 12 o'clock and sweeps clockwise, exactly as the ring
    # in the app does.
    sweep = 360 * ring_fraction
    draw.arc(box, start=-90, end=-90 + sweep, fill=(255, 255, 255, 255), width=stroke)

    # Rounded cap at the leading edge so the arc doesn't end on a hard chop.
    cx, cy = W / 2, W / 2
    radius = (W - 2 * margin) / 2
    import math
    angle = math.radians(-90 + sweep)
    ex, ey = cx + radius * math.cos(angle), cy + radius * math.sin(angle)
    r = stroke / 2
    draw.ellipse((ex - r, ey - r, ex + r, ey + r), fill=(255, 255, 255, 255))
    sx, sy = cx, cy - radius
    draw.ellipse((sx - r, sy - r, sx + r, sy + r), fill=(255, 255, 255, 255))

    img = Image.alpha_composite(img.convert("RGBA"), overlay)

    # A whisper of inner shadow under the ring gives the glyph some lift
    # without turning it into a skeuomorphic badge.
    shadow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    sdraw = ImageDraw.Draw(shadow)
    sdraw.arc(
        (box[0] + W * 0.006, box[1] + W * 0.008, box[2] + W * 0.006, box[3] + W * 0.008),
        start=-90, end=-90 + sweep, fill=(120, 40, 10, 60), width=stroke,
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(W * 0.006))
    img = Image.alpha_composite(shadow, img)

    return img.convert("RGB").resize((size, size), Image.LANCZOS)


def main():
    targets = [
        (os.path.join(ROOT, "Protein/Assets.xcassets/AppIcon.appiconset/icon_1024.png"), 1024),
        (os.path.join(ROOT, "ProteinWatch/Assets.xcassets/AppIcon.appiconset/icon_1024.png"), 1024),
        (os.path.join(ROOT, "Protein/Assets.xcassets/OnboardingMark.imageset/onboarding_mark.png"), 512),
    ]
    for path, size in targets:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        build(size).save(path)
        print(f"wrote {path} ({size}x{size})")


if __name__ == "__main__":
    main()
