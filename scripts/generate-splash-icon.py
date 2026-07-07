#!/usr/bin/env python3
"""Generate the launch-screen splash icon from the shipped app icon.

The launch storyboard (`ios/SulavSleep/SplashScreen.storyboard`) shows the
app icon centered on the `background` navy (#08111E) — the standard iOS
"icon on brand color" splash. iOS gives the real home-screen icon its
rounded mask automatically, but a launch storyboard just draws a flat PNG,
so this script bakes the familiar rounded-icon shape in: it takes the
generated 1024px icon from AppIcon.appiconset (see
`scripts/generate-app-icon.py` — always regenerate the icon first if the
art changed) and emits SplashIcon.imageset at 180pt @1x/2x/3x with the
iOS icon corner radius (~22.37% of the side) and transparency outside it.

Usage:
    python3 scripts/generate-splash-icon.py

Requires: Pillow.
"""
from pathlib import Path

from PIL import Image, ImageDraw

REPO = Path(__file__).resolve().parent.parent
ICON = REPO / "ios/SulavSleep/Images.xcassets/AppIcon.appiconset/App-Icon-1024x1024@1x.png"
SPLASHSET = REPO / "ios/SulavSleep/Images.xcassets/SplashIcon.imageset"

POINT_SIZE = 180          # matches the storyboard's width/height constraints
CORNER_FRACTION = 0.2237  # iOS icon corner radius as a fraction of the side
SUPERSAMPLE = 4           # draw the mask oversized for smooth anti-aliasing


def rounded(icon: Image.Image, px: int) -> Image.Image:
    out = icon.resize((px, px), Image.LANCZOS).convert("RGBA")
    big = px * SUPERSAMPLE
    mask = Image.new("L", (big, big), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, big - 1, big - 1), radius=round(big * CORNER_FRACTION), fill=255
    )
    out.putalpha(mask.resize((px, px), Image.LANCZOS))
    return out


def main() -> None:
    icon = Image.open(ICON)
    SPLASHSET.mkdir(exist_ok=True)
    for scale in (1, 2, 3):
        rounded(icon, POINT_SIZE * scale).save(SPLASHSET / f"splash-icon@{scale}x.png")
    (SPLASHSET / "Contents.json").write_text(
        '{\n  "images" : [\n'
        + ",\n".join(
            '    {\n'
            f'      "filename" : "splash-icon@{scale}x.png",\n'
            '      "idiom" : "universal",\n'
            f'      "scale" : "{scale}x"\n'
            '    }'
            for scale in (1, 2, 3)
        )
        + '\n  ],\n  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  }\n}\n'
    )
    print(f"wrote splash icon (3 scales) to {SPLASHSET}")


if __name__ == "__main__":
    main()
