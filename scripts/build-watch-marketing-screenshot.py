#!/usr/bin/env python3
"""Build the App Store screenshot that sells the wrist experience.

The phone is a real Today capture and the watch face is the on-device
complication capture. They are composed into one 6.9-inch iPhone listing
image so the wrist experience is visible from the iPhone screenshot set.

    python3 scripts/build-watch-marketing-screenshot.py
"""
from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageOps

CANVAS = (1320, 2868)
INK = (17, 17, 19)
ORANGE = (255, 126, 30)
MUTED = (116, 116, 122)

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "fastlane" / "screenshots" / "en-US" / "5_APP_IPHONE_67_watch.png"
BACKDROP = ROOT / "scripts" / "assets" / "screenshot-backdrop.png"
PHONE = ROOT / "Screenshots" / "raw" / "shot-today.png"
WATCH = ROOT / "fastlane" / "screenshots" / "en-US" / "9_APP_WATCH_SERIES_10_complication.png"

FONT_CANDIDATES = [
    "/System/Library/Fonts/SFNS.ttf",
    "/System/Library/Fonts/Helvetica.ttc",
    "/Library/Fonts/Arial.ttf",
]


def load_font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
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


def add_shadow(canvas: Image.Image, image: Image.Image, position: tuple[int, int], radius: int = 32) -> None:
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    shadow_box = Image.new("RGBA", image.size, (0, 0, 0, 74))
    shadow.paste(shadow_box, position, shadow_box)
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius))
    canvas.alpha_composite(shadow)


def rounded_image(image: Image.Image, radius: int) -> Image.Image:
    mask = Image.new("L", image.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, image.width - 1, image.height - 1), radius=radius, fill=255)
    result = Image.new("RGBA", image.size, (255, 255, 255, 0))
    result.paste(image.convert("RGB"), (0, 0), mask)
    return result


def draw_watch(canvas: Image.Image, face: Image.Image, position: tuple[int, int]) -> None:
    face = face.resize((430, 513), Image.Resampling.LANCZOS)
    x, y = position
    case = (x - 18, y - 18, x + face.width + 18, y + face.height + 18)
    strap_x = x + 88
    strap_width = 254

    strap = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    strap_draw = ImageDraw.Draw(strap)
    strap_draw.rounded_rectangle(
        (strap_x, y - 178, strap_x + strap_width, y + 58),
        radius=38,
        fill=(28, 28, 30, 255),
    )
    strap_draw.rounded_rectangle(
        (strap_x, y + face.height - 58, strap_x + strap_width, y + face.height + 178),
        radius=38,
        fill=(28, 28, 30, 255),
    )
    canvas.alpha_composite(strap)

    case_layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    case_draw = ImageDraw.Draw(case_layer)
    case_draw.rounded_rectangle(case, radius=92, fill=(12, 12, 14, 255), outline=(78, 78, 82, 255), width=5)
    canvas.alpha_composite(case_layer)
    canvas.alpha_composite(rounded_image(face, 84), (x, y))


def main() -> None:
    backdrop = Image.open(BACKDROP).convert("RGB")
    canvas = ImageOps.fit(backdrop, CANVAS, method=Image.Resampling.LANCZOS)
    canvas = Image.blend(canvas, Image.new("RGB", CANVAS, "white"), 0.28).convert("RGBA")
    draw = ImageDraw.Draw(canvas)

    title_font = load_font(82, bold=True)
    subtitle_font = load_font(38)
    label_font = load_font(27, bold=True)
    caption_font = load_font(36)

    draw.text((96, 116), "Protein. On your wrist.", font=title_font, fill=INK)
    draw.text((100, 246), "Your live target, one glance away.", font=subtitle_font, fill=ORANGE)

    phone = Image.open(PHONE).convert("RGB")
    phone_width = 820
    phone = phone.resize((phone_width, round(phone.height * phone_width / phone.width)), Image.Resampling.LANCZOS)
    phone = rounded_image(phone, 58)
    phone_position = (78, 590)
    add_shadow(canvas, phone, phone_position, radius=36)
    canvas.alpha_composite(phone, phone_position)

    watch = Image.open(WATCH).convert("RGB")
    watch_position = (790, 1570)
    shadow_size = (466, 870)
    watch_shadow = Image.new("RGBA", shadow_size, (0, 0, 0, 0))
    ImageDraw.Draw(watch_shadow).rounded_rectangle((18, 168, 448, 681), radius=92, fill=(0, 0, 0, 82))
    watch_shadow = watch_shadow.filter(ImageFilter.GaussianBlur(32))
    canvas.alpha_composite(watch_shadow, (watch_position[0] - 18, watch_position[1] - 178))
    draw_watch(canvas, watch, watch_position)

    badge_x, badge_y = 770, 1262
    badge_width, badge_height = 468, 66
    draw.rounded_rectangle(
        (badge_x, badge_y, badge_x + badge_width, badge_y + badge_height),
        radius=33,
        fill=ORANGE,
    )
    badge = "LIVE COMPLICATION"
    badge_box = draw.textbbox((0, 0), badge, font=label_font)
    badge_text_width = badge_box[2] - badge_box[0]
    draw.text(
        (badge_x + (badge_width - badge_text_width) / 2, badge_y + 17),
        badge,
        font=label_font,
        fill="white",
    )
    line_start = (badge_x + badge_width // 2, badge_y + badge_height)
    line_end = (watch_position[0] + 330, watch_position[1] + 197)
    draw.line((line_start, line_end), fill=ORANGE, width=5)
    draw.ellipse((line_end[0] - 9, line_end[1] - 9, line_end[0] + 9, line_end[1] + 9), fill=ORANGE)

    caption = "Track on your phone. Glance on your watch."
    draw.text((96, 2546), caption, font=caption_font, fill=INK)
    draw.text((100, 2612), "124 g, right on the face.", font=subtitle_font, fill=MUTED)

    canvas.convert("RGB").save(OUT, format="PNG")
    print(f"wrote {OUT.relative_to(ROOT)} ({CANVAS[0]}x{CANVAS[1]})")


if __name__ == "__main__":
    main()
