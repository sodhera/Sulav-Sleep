#!/usr/bin/env python3
"""Generate the golden-sloth chip for the Settings subscription row.

Unlike `generate-app-icon.py`, this needs no source EPS — it derives from the
already-committed Home sloth PNG, so anyone can re-run it. The brand sloth is
lounging and wide (built for the Home hero at 48-120pt); at a 30pt settings
chip the full figure would be an unreadable smudge. So we:

1. Crop to the **head** — the most recognizable part — so the figure fills a
   square instead of lying across it.
2. Recolor to a **gold medallion**: map luminance onto a dark->mid->highlight
   gold ramp, which keeps the face relief (eyes, muzzle, patches) legible at
   chip size instead of flattening to a silhouette the way a flat template
   tint would. This is the "make our sloth golden" ask, done so it survives
   small.

Output: `SubscriptionSloth.imageset` (transparent PNG). The Settings row draws
it inside the same soft tinted chip as every other `GlassRowIcon`, so the row
still scans with its siblings.

Usage:
    python3 scripts/generate-subscription-icon.py

Requires: Pillow, numpy.
"""
from pathlib import Path

import numpy as np
from PIL import Image

REPO = Path(__file__).resolve().parent.parent
XCASSETS = REPO / "ios/SulavSleep/Images.xcassets"
# The night-lit awake sloth is the warmest, most alert source pose — the best
# base for a crowned "your plan is active" mark.
SRC = XCASSETS / "HomeSlothNightAwake.imageset/HomeSlothNightAwake.png"

# Gold medallion ramp (shadow -> body -> highlight), all in the warm gold band.
GOLD_DARK = (0x38, 0x27, 0x09)
GOLD_MID = (0xCB, 0x95, 0x3C)
GOLD_HI = (0xF7, 0xDE, 0x90)

RENDER = 300  # asset side in px — ample for a 30-60pt chip at @3x


def gold_ramp(lum: np.ndarray) -> np.ndarray:
    """Map 0..1 luminance onto the two-segment gold ramp."""
    l = lum[..., None]
    lo = np.array(GOLD_DARK, np.float32)
    mid = np.array(GOLD_MID, np.float32)
    hi = np.array(GOLD_HI, np.float32)
    below = l < 0.5
    return np.where(below, lo + (mid - lo) * (l / 0.5),
                    mid + (hi - mid) * ((l - 0.5) / 0.5))


def main() -> None:
    img = Image.open(SRC).convert("RGBA")
    arr = np.asarray(img)
    ys, xs = np.nonzero(arr[:, :, 3])
    x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
    w, h = x1 - x0, y1 - y0

    # Head square: the face + tucked paws sit in the left ~54% of the figure.
    hx1 = x0 + int(0.54 * w)
    hy1 = y0 + int(0.92 * h)
    side = max(hx1 - x0, hy1 - y0)
    cx = (x0 + hx1) // 2
    cy = (y0 + hy1) // 2
    sx0 = max(cx - side // 2, 0)
    sy0 = max(cy - side // 2, 0)
    head = img.crop((sx0, sy0, sx0 + side, sy0 + side))

    # Colorize by luminance, preserving the source alpha.
    h_arr = np.asarray(head).astype(np.float32)
    lum = (0.299 * h_arr[:, :, 0] + 0.587 * h_arr[:, :, 1] + 0.114 * h_arr[:, :, 2]) / 255.0
    gold = gold_ramp(np.clip(lum, 0, 1))
    rgba = np.dstack([gold, h_arr[:, :, 3:4]]).astype(np.uint8)
    gsloth = Image.fromarray(rgba, "RGBA")

    # Even margin so the head breathes inside the chip (the row draws the
    # image nearly chip-sized, so the padding lives in the asset), re-squared.
    pad = int(0.13 * max(gsloth.size))
    cs = max(gsloth.width, gsloth.height) + pad * 2
    square = Image.new("RGBA", (cs, cs), (0, 0, 0, 0))
    square.paste(gsloth, ((cs - gsloth.width) // 2, (cs - gsloth.height) // 2), gsloth)

    final = square.resize((RENDER, RENDER), Image.LANCZOS)
    folder = XCASSETS / "SubscriptionSloth.imageset"
    folder.mkdir(exist_ok=True)
    final.save(folder / "SubscriptionSloth.png")
    (folder / "Contents.json").write_text(
        '{\n  "images" : [\n    {\n      "filename" : "SubscriptionSloth.png",\n'
        '      "idiom" : "universal"\n    }\n  ],\n  "info" : {\n'
        '    "author" : "xcode",\n    "version" : 1\n  }\n}\n'
    )
    print(f"wrote SubscriptionSloth.imageset to {folder}")


if __name__ == "__main__":
    main()
