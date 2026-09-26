#!/usr/bin/env python3
"""Genereert de statische Daytr8-iconen uit dezelfde geometrie als
`Daytr8EightShape` (kader 100 x 140).

Statisch = kleuren van het standaardthema "Donker" (ThemePalette.donker):
achtergrond #17191D, accent #5AB0FF.

Gebruik: python3 Branding/generate_icons.py   (vereist Pillow)
"""
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
BACKGROUND = (0x17, 0x19, 0x1D)
ACCENT = (0x5A, 0xB0, 0xFF)

# (x, y, w, h, radius, afgeronde hoeken (lb, rb, ro, lo)) in het 100 x 140-kader.
# De twee scherpe hoeken — linksboven en rechtsonder — zijn het kenmerk van
# het logo; de gaten zijn volledig afgerond.
ROUND = (True, True, True, True)
OUTER = [(8, 0, 84, 66, 30, (False, True, True, True)), (0, 58, 100, 82, 36, (True, True, False, True))]
HOLES = [(32, 22, 36, 22, 11, ROUND), (28, 82, 44, 36, 18, ROUND)]
SUPERSAMPLE = 4


def eight_mask(height: int) -> Image.Image:
    """Alfamasker van de "8" met de gegeven hoogte (anti-aliased)."""
    scale = height * SUPERSAMPLE / 140
    width = round(100 * scale)
    mask = Image.new("L", (width, round(140 * scale)), 0)
    draw = ImageDraw.Draw(mask)

    def box(spec, fill):
        x, y, w, h, r, corners = spec
        draw.rounded_rectangle(
            [x * scale, y * scale, (x + w) * scale - 1, (y + h) * scale - 1],
            radius=min(r, w / 2, h / 2) * scale,
            fill=fill,
            corners=corners,
        )

    for spec in OUTER:
        box(spec, 255)
    for spec in HOLES:
        box(spec, 0)
    return mask.resize((round(width / SUPERSAMPLE), height), Image.LANCZOS)


def icon(size: int, eight_fraction: float = 0.62, background=BACKGROUND, transparent=False) -> Image.Image:
    """Vierkant icoon: de "8" gecentreerd op een effen achtergrond."""
    mode = "RGBA" if transparent else "RGB"
    base = Image.new(mode, (size, size), (0, 0, 0, 0) if transparent else background)
    mask = eight_mask(max(1, round(size * eight_fraction)))
    color = Image.new(mode, mask.size, ACCENT + ((255,) if transparent else ()))
    base.paste(color, ((size - mask.width) // 2, (size - mask.height) // 2), mask)
    return base


def main():
    assets = ROOT / "TradeJournal/Resources/Assets.xcassets"

    # App-icoon (iOS 17: één 1024-bestand, zonder transparantie).
    icon(1024).save(assets / "AppIcon.appiconset/AppIcon-1024.png")

    # Launch screen: alleen de "8", transparant op LaunchBackground.
    launch = assets / "LaunchLogo.imageset"
    launch.mkdir(exist_ok=True)
    for factor in (1, 2, 3):
        mask = eight_mask(64 * factor)
        image = Image.new("RGBA", mask.size, (0, 0, 0, 0))
        image.paste(Image.new("RGBA", mask.size, ACCENT + (255,)), (0, 0), mask)
        image.save(launch / f"LaunchLogo@{factor}x.png")

    # Favicons en web-iconen.
    web = ROOT / "Branding"
    for size in (16, 32, 48):
        icon(size, eight_fraction=0.78).save(web / f"favicon-{size}.png")
    icon(48, eight_fraction=0.78).save(web / "favicon.ico", sizes=[(16, 16), (32, 32), (48, 48)])
    icon(180).save(web / "apple-touch-icon.png")
    icon(192).save(web / "icon-192.png")
    icon(512).save(web / "icon-512.png")


if __name__ == "__main__":
    main()
