#!/usr/bin/env python3
"""Derive the widget extension's sloth assets from the app's.

The widget extension ships its own lean asset catalog
(ios/SulavSleepWidget/WidgetAssets.xcassets) instead of compiling the app's
Images.xcassets, which would drag the full pixel-art city into the appex.
The only art the widgets need is the sloth in its three poses, and those are
just downscaled copies of the imagesets `generate-app-icon.py` writes:

    HomeSlothAwake  — daytime pose (before bed)
    HomeSlothDrowsy — heavy-lidded pose (near / past bedtime)
    NightSloth      — ember pose (asleep, on OLED black)

Run this after re-running generate-app-icon.py so the two catalogs never
drift:

    python3 scripts/generate-widget-assets.py

Requires: Pillow.
"""
from pathlib import Path

from PIL import Image

REPO = Path(__file__).resolve().parent.parent
APP_XCASSETS = REPO / "ios/SulavSleep/Images.xcassets"
WIDGET_XCASSETS = REPO / "ios/SulavSleepWidget/WidgetAssets.xcassets"

# The largest widget render is the large family's asleep centerpiece
# (~200pt wide -> 600px @3x); 720px keeps every use sharp with headroom.
WIDGET_WIDTH = 720

SLOTHS = ["HomeSlothAwake", "HomeSlothDrowsy", "NightSloth"]


def write_imageset(name: str, image: Image.Image) -> None:
    folder = WIDGET_XCASSETS / f"{name}.imageset"
    folder.mkdir(parents=True, exist_ok=True)
    filename = f"{name}.png"
    image.save(folder / filename)
    (folder / "Contents.json").write_text(
        '{\n  "images" : [\n    {\n      "filename" : "' + filename + '",\n'
        '      "idiom" : "universal"\n    }\n  ],\n  "info" : {\n'
        '    "author" : "xcode",\n    "version" : 1\n  }\n}\n'
    )


def main() -> None:
    WIDGET_XCASSETS.mkdir(parents=True, exist_ok=True)
    contents = WIDGET_XCASSETS / "Contents.json"
    if not contents.exists():
        contents.write_text(
            '{\n  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  }\n}\n'
        )

    for name in SLOTHS:
        source = APP_XCASSETS / f"{name}.imageset" / f"{name}.png"
        image = Image.open(source)
        height = round(image.height * WIDGET_WIDTH / image.width)
        write_imageset(name, image.resize((WIDGET_WIDTH, height), Image.LANCZOS))
        print(f"wrote {name} ({WIDGET_WIDTH}x{height}) to {WIDGET_XCASSETS}")


if __name__ == "__main__":
    main()
