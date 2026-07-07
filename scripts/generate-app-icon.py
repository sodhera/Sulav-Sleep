#!/usr/bin/env python3
"""Generate the SleepBlock sloth artwork from the sleeping-sloth stock vector.

The source artwork (see CREDITS.md) is a purple-background cartoon EPS. This
script re-renders it and remaps its flat palette to the Warm Pixel Night
system from DESIGN.md, producing two deliverables:

1. **App icon** (light/dark/tinted 1024px, into AppIcon.appiconset): amber
   sloth, gold ZZZ, cool ink pillow, over a skyTop -> background night
   gradient with a faint warm lamp glow.
2. **Night sloth** (transparent PNG, into NightSloth.imageset): the sleep
   screen's centerpiece — the same sloth banked down to the ember palette
   (only ember pixels may be lit on that screen), pillow reduced to deep
   warm coals, static ZZZ erased because the app animates its own.

Usage:
    python3 scripts/generate-app-icon.py /path/to/sloth.eps

Requires: ghostscript (`brew install ghostscript`), Pillow, numpy.
"""
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image, ImageOps

REPO = Path(__file__).resolve().parent.parent
ICONSET = REPO / "ios/SulavSleep/Images.xcassets/AppIcon.appiconset"
SLOTHSET = REPO / "ios/SulavSleep/Images.xcassets/NightSloth.imageset"

# Source flat palette -> Warm Pixel Night target (None = handled specially)
BG = (0xA4, 0xA4, 0xF4)          # purple sky -> night gradient + lamp glow
WHITE = (0xFF, 0xFF, 0xFF)       # split: ZZZ -> gold, pillow -> ink
PALETTE = {
    BG: None,
    WHITE: None,
    (0x39, 0x01, 0x76): (0x07, 0x10, 0x19),  # outlines -> near-black navy
    (0xD4, 0x95, 0x68): (0xF4, 0xA2, 0x61),  # body -> amber
    (0xFF, 0xD8, 0xB5): (0xFB, 0xDF, 0xAE),  # face/belly -> warm cream
    (0xB5, 0x77, 0x6B): (0xE0, 0x85, 0x4E),  # mid shade -> ember
    (0x8A, 0x49, 0x46): (0x8C, 0x4B, 0x26),  # eye patches -> deep warm brown
    (0x7A, 0x3B, 0x50): (0x6B, 0x34, 0x18),  # darkest shade
    (0xD7, 0xAD, 0xA8): (0xF7, 0xC2, 0x89),  # body highlight -> light amber
    (0xED, 0xD3, 0xC1): (0xF2, 0xDC, 0xB4),  # claws -> cream gold
    (0xEE, 0xD6, 0xC4): (0xF2, 0xDC, 0xB4),
    (0xD7, 0xCC, 0xE4): (0xC6, 0xCD, 0xD9),  # pillow shade -> cool grey
    (0xB7, 0xA3, 0xCE): (0x9F, 0xA9, 0xBB),  # pillow deep shade
}
GOLD = (0xE9, 0xC4, 0x6A)
INK = (0xF5, 0xF5, 0xF2)
SKY_TOP = (0x0C, 0x17, 0x28)     # SleepColor.skyTop
NIGHT = (0x08, 0x11, 0x1E)       # SleepColor.background
AMBER = (0xF4, 0xA2, 0x61)

# The sleep screen's sloth: the same regions banked down to the ember family
# (SleepColor.ember/emberDim/emberGlow/emberDeep) — a sloth lit by dying
# coals. The pillow drops to deep warm browns so the figure carries the
# light; outlines go near-black so the silhouette melts into the OLED dark.
EMBER_PALETTE = {
    BG: None,                                # transparent
    WHITE: (0x2A, 0x17, 0x10),               # pillow -> deep warm coals
    (0x39, 0x01, 0x76): (0x10, 0x07, 0x03),  # outlines -> near-black warm
    (0xD4, 0x95, 0x68): (0x9C, 0x55, 0x30),  # body -> emberDim
    (0xFF, 0xD8, 0xB5): (0xC8, 0x7B, 0x45),  # face/belly -> lit ember
    (0xB5, 0x77, 0x6B): (0x7A, 0x3A, 0x16),  # mid shade -> emberGlow
    (0x8A, 0x49, 0x46): (0x4A, 0x20, 0x08),  # eye patches -> emberDeep
    (0x7A, 0x3B, 0x50): (0x35, 0x18, 0x04),  # darkest shade
    (0xD7, 0xAD, 0xA8): (0xB0, 0x69, 0x3C),  # body highlight
    (0xED, 0xD3, 0xC1): (0xA8, 0x62, 0x38),  # claws
    (0xEE, 0xD6, 0xC4): (0xA8, 0x62, 0x38),
    (0xD7, 0xCC, 0xE4): (0x22, 0x12, 0x08),  # pillow shade
    (0xB7, 0xA3, 0xCE): (0x1B, 0x0E, 0x06),  # pillow deep shade
}


def render_eps(eps: Path, px: int = 4096) -> Image.Image:
    with tempfile.NamedTemporaryFile(suffix=".png") as tmp:
        # Probe the EPS bounding box to pick the dpi that yields ~px output.
        probe = subprocess.run(
            ["gs", "-q", "-dNOPAUSE", "-dBATCH", "-sDEVICE=bbox", str(eps)],
            capture_output=True, text=True,
        )
        import re
        m = re.search(r"%%HiResBoundingBox: [\d.]+ [\d.]+ ([\d.]+)", probe.stderr)
        width_pt = float(m.group(1)) if m else 4000.0
        dpi = px * 72.0 / width_pt
        subprocess.run(
            ["gs", "-dNOPAUSE", "-dBATCH", "-sDEVICE=png16m", f"-r{dpi:.2f}",
             "-dEPSCrop", f"-sOutputFile={tmp.name}", str(eps)],
            check=True, capture_output=True,
        )
        return Image.open(tmp.name).convert("RGB")


def classify(arr: np.ndarray, keys: list) -> np.ndarray:
    """Nearest source-palette color per pixel (chunked to bound memory)."""
    src = np.array(keys, dtype=np.int32)
    h, w, _ = arr.shape
    idx = np.empty((h, w), dtype=np.uint8)
    for y0 in range(0, h, 256):
        chunk = arr[y0:y0 + 256]
        d = ((chunk[:, :, None, :] - src[None, None, :, :]) ** 2).sum(-1)
        idx[y0:y0 + 256] = d.argmin(-1).astype(np.uint8)
    return idx


def remap(img: Image.Image) -> Image.Image:
    arr = np.asarray(img).astype(np.int32)
    h, w, _ = arr.shape
    idx = classify(arr, list(PALETTE.keys()))

    out = np.zeros((h, w, 3), dtype=np.float32)

    # Background: vertical night gradient + radial lamp glow + amber floor glow
    yy = np.linspace(0.0, 1.0, h, dtype=np.float32)[:, None]
    grad = np.empty((h, w, 3), dtype=np.float32)
    for c in range(3):
        grad[:, :, c] = SKY_TOP[c] + (NIGHT[c] - SKY_TOP[c]) * yy
    xx = np.linspace(0.0, 1.0, w, dtype=np.float32)[None, :]
    r = np.sqrt((xx - 0.52) ** 2 + (yy - 0.58) ** 2)
    glow = np.clip(1.0 - r / 0.52, 0.0, 1.0) ** 2 * 0.22
    floor = np.clip((yy - 0.72) / 0.28, 0.0, 1.0) ** 2 * 0.10
    warm = np.clip(glow + floor, 0.0, 0.30)[:, :, None]
    bgcol = grad * (1 - warm) + np.array(AMBER, dtype=np.float32) * warm

    for k, key in enumerate(PALETTE):
        m = idx == k
        if key == BG:
            out[m] = bgcol[m]
        elif key == WHITE:
            zzz = m & (np.arange(h)[:, None] < int(0.45 * h))
            out[zzz] = np.array(GOLD, dtype=np.float32)
            out[m & ~zzz] = np.array(INK, dtype=np.float32)
        else:
            out[m] = np.array(PALETTE[key], dtype=np.float32)

    icon = Image.fromarray(out.clip(0, 255).astype(np.uint8))
    # Tighten framing: crop to 92% square centered on the figure
    side = int(0.92 * min(w, h))
    cx, cy = int(0.512 * w), int(0.505 * h)
    x0 = min(max(cx - side // 2, 0), w - side)
    y0 = min(max(cy - side // 2, 0), h - side)
    icon = icon.crop((x0, y0, x0 + side, y0 + side))
    return icon.resize((1024, 1024), Image.LANCZOS)


def night_sloth(img: Image.Image) -> Image.Image:
    arr = np.asarray(img).astype(np.int32)
    h, w, _ = arr.shape
    keys = list(EMBER_PALETTE.keys())
    idx = classify(arr, keys)

    out = np.zeros((h, w, 4), dtype=np.uint8)
    for k, key in enumerate(keys):
        if EMBER_PALETTE[key] is None:
            continue
        r, g, b = EMBER_PALETTE[key]
        out[idx == k] = (r, g, b, 255)

    # Erase the baked ZZZ (upper-left corner): the app animates its own.
    # Bounds hug the ZZZ bbox — the sloth's forehead starts at ~0.28w.
    out[: int(0.40 * h), : int(0.265 * w)] = 0

    # Tight crop to the figure with a small margin.
    ys, xs = np.nonzero(out[:, :, 3])
    pad = int(0.02 * w)
    box = (
        max(int(xs.min()) - pad, 0), max(int(ys.min()) - pad, 0),
        min(int(xs.max()) + pad, w), min(int(ys.max()) + pad, h),
    )
    fig = Image.fromarray(out).crop(box)
    return fig.resize((1200, round(fig.height * 1200 / fig.width)), Image.LANCZOS)


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    hires = render_eps(Path(sys.argv[1]))

    icon = remap(hires)
    icon.save(ICONSET / "App-Icon-1024x1024@1x.png")
    # Dark appearance reuses the night art; tinted is the grayscale render.
    icon.save(ICONSET / "App-Icon-Dark-1024x1024@1x.png")
    tinted = ImageOps.autocontrast(ImageOps.grayscale(icon), cutoff=1)
    tinted.convert("RGB").save(ICONSET / "App-Icon-Tinted-1024x1024@1x.png")
    print(f"wrote 3 icon variants to {ICONSET}")

    SLOTHSET.mkdir(exist_ok=True)
    night_sloth(hires).save(SLOTHSET / "night-sloth.png")
    (SLOTHSET / "Contents.json").write_text(
        '{\n  "images" : [\n    {\n      "filename" : "night-sloth.png",\n'
        '      "idiom" : "universal"\n    }\n  ],\n  "info" : {\n'
        '    "author" : "xcode",\n    "version" : 1\n  }\n}\n'
    )
    print(f"wrote night sloth to {SLOTHSET}")


if __name__ == "__main__":
    main()
