#!/usr/bin/env python3
"""Compose App Store screenshots from raw simulator captures.

Raw captures from a pool iPhone 17 Pro are 1206x2622. The App Store 6.9-inch
(`APP_IPHONE_67`) set wants 1320x2868 RGB with no alpha, so each frame is laid
onto a canvas of that size under a caption band.

The captions carry the acquisition story the SERP cannot: what the app is, who
it is for, and what it refuses to do. `docs/positioning.md` §2 is explicit that
this is where the three audiences pay off, since one product page has to speak
to lifters, GLP-1 users, and post-bariatric patients at once.

    python3 scripts/build-screenshots.py <raw-capture-dir>

Raw captures are kept beside the composed assets for design review.
"""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

CANVAS = (1320, 2868)
DEEP = (230, 74, 33)
AMBER = (250, 140, 33)
INK = (17, 17, 19)
MUTED = (110, 110, 118)

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "fastlane" / "screenshots" / "en-US"

# (raw filename, headline, subhead). Order is the App Store order, and the
# first three have to stand alone because they can surface in search results.
FRAMES = [
    ("shot-today.png", "How many grams left.", "One number. No calorie counting."),
    ("shot-sources.png", "Counts what you already log.", "Reads protein from Apple Health, and shows you which app wrote it."),
    ("shot-history.png", "Every day, against your target.", "See the week you actually had."),
    ("shot-paywall.png", "Reading is free.", "Protein+ adds logging from your wrist."),
]

FONT_CANDIDATES = [
    "/System/Library/Fonts/SFNS.ttf",
    "/System/Library/Fonts/Helvetica.ttc",
    "/Library/Fonts/Arial.ttf",
]


def load_font(size: int, bold: bool) -> ImageFont.FreeTypeFont:
    for path in FONT_CANDIDATES:
        if Path(path).exists():
            try:
                font = ImageFont.truetype(path, size)
                if bold:
                    try:
                        font.set_variation_by_name("Bold")
                    except Exception:
                        pass
                return font
            except Exception:
                continue
    return ImageFont.load_default()


def wrap(draw: ImageDraw.ImageDraw, text: str, font, max_width: int) -> list[str]:
    words, lines, current = text.split(), [], ""
    for word in words:
        trial = f"{current} {word}".strip()
        if draw.textlength(trial, font=font) <= max_width:
            current = trial
        else:
            if current:
                lines.append(current)
            current = word
    if current:
        lines.append(current)
    return lines


def compose(raw: Path, headline: str, subhead: str) -> Image.Image:
    canvas = Image.new("RGB", CANVAS, (255, 255, 255))
    draw = ImageDraw.Draw(canvas)

    # Warm wash behind the caption so the band reads as part of the brand
    # rather than a white letterbox.
    band_height = 560
    for y in range(band_height):
        t = y / band_height
        colour = tuple(int(round(255 + (c - 255) * (0.10 * (1 - t)))) for c in AMBER)
        draw.line([(0, y), (CANVAS[0], y)], fill=colour)

    title_font = load_font(78, bold=True)
    sub_font = load_font(46, bold=False)
    margin = 96
    max_width = CANVAS[0] - margin * 2

    y = 150
    for line in wrap(draw, headline, title_font, max_width):
        draw.text((margin, y), line, font=title_font, fill=INK)
        y += 94
    y += 16
    for line in wrap(draw, subhead, sub_font, max_width):
        draw.text((margin, y), line, font=sub_font, fill=MUTED)
        y += 60

    shot = Image.open(raw).convert("RGB")
    top = band_height - 40
    available_height = CANVAS[1] - top - 56
    available_width = CANVAS[0] - margin * 2
    # Fit by whichever axis binds, so the device frame is never cropped through
    # the tab bar — a half-cut control reads as a broken screenshot.
    scale = min(available_width / shot.width, available_height / shot.height)
    shot = shot.resize((int(shot.width * scale), int(shot.height * scale)), Image.LANCZOS)

    rounded = Image.new("L", shot.size, 0)
    ImageDraw.Draw(rounded).rounded_rectangle([0, 0, shot.width, shot.height], radius=52, fill=255)
    canvas.paste(shot, ((CANVAS[0] - shot.width) // 2, top), rounded)

    return canvas


def main() -> None:
    raw_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "Screenshots" / "raw"
    OUT.mkdir(parents=True, exist_ok=True)
    for index, (name, headline, subhead) in enumerate(FRAMES, start=1):
        raw = raw_dir / name
        if not raw.exists():
            print(f"skip {name}: not found in {raw_dir}")
            continue
        image = compose(raw, headline, subhead)
        out = OUT / f"{index}_APP_IPHONE_67_{name.replace('shot-', '')}"
        image.save(out)
        print(f"wrote {out.relative_to(ROOT)} ({image.width}x{image.height})")


if __name__ == "__main__":
    main()
