#!/usr/bin/env python3
"""Protein Tracker app icon: a grams-left ring around the unit itself.

Fleet design language (soft diagonal gradient, one confident white glyph,
generous negative space) applied to this app's actual hero: the ring that says
how much protein is left, with the `g` it is counting sitting inside it.
Deliberately not a dumbbell, a steak, or a shaker — the icon is the number's
container, which is what the product is.

The bare ring the icon used to be read as a loading spinner (or as Apple's own
Activity rings) at 60pt; the `g` is what makes it this app's ring at home-screen
size.
"""
import math
import os

from PIL import Image, ImageChops, ImageDraw, ImageFont, ImageOps

S = 1024
SS = 4          # supersample factor
W = S * SS

DEEP = (230, 74, 33)    # Theme.proteinDeep
AMBER = (250, 140, 33)  # Theme.protein

RING_FRACTION = 0.72    # how much of the day is eaten, in the icon's story
RING_RADIUS = 0.322     # centerline, as a fraction of the canvas
RING_STROKE = 0.060
GLYPH_SIZE = 0.42
TRACK_ALPHA = 100       # the part still to eat: present, not competing

SF_ROUNDED = "/System/Library/Fonts/SFNSRounded.ttf"

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)


def gradient(w):
    """Diagonal top-left deep orange -> bottom-right amber."""
    vertical = Image.linear_gradient("L").resize((w, w), Image.Resampling.BILINEAR)
    horizontal = vertical.rotate(90, expand=False)
    diagonal = ImageChops.add(horizontal, vertical, scale=2.0)
    return ImageOps.colorize(diagonal, DEEP, AMBER)


def stroked_arc(draw, cx, cy, r, stroke, start, end, fill, caps=True):
    """Arc whose *centerline* sits at radius `r`, with true round caps.

    PIL insets `width` from the bounding box, so the box has to be the outer
    edge (r + stroke/2) for the centerline to land on r. Drawing the caps at
    the outer radius instead — which is what this script used to do — pushes
    them half a stroke proud of the arc and reads as lumps.
    """
    outer = r + stroke / 2
    box = (cx - outer, cy - outer, cx + outer, cy + outer)
    draw.arc(box, start=start, end=end, fill=fill, width=int(stroke))
    if not caps:
        return
    for deg in (start, end):
        a = math.radians(deg)
        ex, ey = cx + r * math.cos(a), cy + r * math.sin(a)
        h = stroke / 2
        draw.ellipse((ex - h, ey - h, ex + h, ey + h), fill=fill)


def rounded_bold(size):
    font = ImageFont.truetype(SF_ROUNDED, int(size))
    font.set_variation_by_name("Bold")
    return font


def centered_text(draw, cx, cy, text, font, fill):
    left, top, right, bottom = draw.textbbox((0, 0), text, font=font)
    draw.text((cx - (left + right) / 2, cy - (top + bottom) / 2),
              text, font=font, fill=fill)


def build(size, ring_fraction=RING_FRACTION):
    img = gradient(W).convert("RGBA")
    overlay = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)

    cx = cy = W / 2
    radius, stroke = W * RING_RADIUS, W * RING_STROKE

    # Track: the part of the day still to eat, held back so the filled arc
    # carries the weight at small sizes.
    stroked_arc(draw, cx, cy, radius, stroke, 0, 360,
                (255, 255, 255, TRACK_ALPHA), caps=False)

    # Progress: starts at 12 o'clock and sweeps clockwise, exactly as the ring
    # in the app does.
    stroked_arc(draw, cx, cy, radius, stroke, -90, -90 + 360 * ring_fraction,
                (255, 255, 255, 255))

    centered_text(draw, cx, cy, "g", rounded_bold(W * GLYPH_SIZE),
                  (255, 255, 255, 255))

    img = Image.alpha_composite(img, overlay)
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
