#!/usr/bin/env python3
"""Generate day and dusk variants of the pixel city scene layers.

The checked-in Night* layers (from the CraftPix night-city pack, see
CREDITS.md) are the source of truth; this script derives the Day* and Dusk*
imagesets from them so the Home scene can follow the user's day:

- **Day**: sky lifted to a hazy daylight blue (stars and moon healed away, a
  pale pixel sun drawn in), skylines lightened into cool haze with depth
  (far = hazier), and window lights turned off (warm pixels -> cool glass).
- **Dusk**: golden hour — the sky blends toward violet up top and ember at
  the horizon, clouds catch warm light, silhouettes deepen slightly, and
  the window lights stay on and glow a touch warmer.

Night is untouched. Run after any change to the night layers:

    python3 scripts/generate-scene-variants.py
"""
import json
from pathlib import Path

import numpy as np
from PIL import Image

REPO = Path(__file__).resolve().parent.parent
XCASSETS = REPO / "ios/SulavSleep/Images.xcassets"

LAYERS = ["CitySky", "CityFarSkyline", "CityMidSkyline", "CityNearSkyline", "CityFrontSkyline"]
# Haze strength per layer for day (far planes dissolve into the sky more).
DAY_LIFT = {"CityFarSkyline": 0.62, "CityMidSkyline": 0.54,
            "CityNearSkyline": 0.46, "CityFrontSkyline": 0.40}


def load(name: str) -> tuple[np.ndarray, np.ndarray]:
    path = next((XCASSETS / f"Night{name}.imageset").glob("*.png"))
    im = Image.open(path).convert("RGBA")
    arr = np.asarray(im).astype(np.float32) / 255.0
    return arr[:, :, :3], arr[:, :, 3]


def to_hsv(rgb: np.ndarray) -> np.ndarray:
    im = Image.fromarray((rgb * 255).astype(np.uint8), "RGB").convert("HSV")
    return np.asarray(im).astype(np.float32) / 255.0


def to_rgb(hsv: np.ndarray) -> np.ndarray:
    im = Image.fromarray((hsv.clip(0, 1) * 255).astype(np.uint8), "HSV").convert("RGB")
    return np.asarray(im).astype(np.float32) / 255.0


def warm_mask(hsv: np.ndarray) -> np.ndarray:
    """Lit-window pixels: warm hue, saturated enough to not be grey."""
    h, s = hsv[:, :, 0], hsv[:, :, 1]
    return ((h < 0.22) | (h > 0.93)) & (s > 0.25)


def day_sky(rgb: np.ndarray, alpha: np.ndarray) -> np.ndarray:
    hsv = to_hsv(rgb)
    h, w, _ = hsv.shape

    # Heal stars + moon: bright, low-saturation outliers become the median
    # sky color of their row.
    celestial = (hsv[:, :, 2] > 0.72) & (hsv[:, :, 1] < 0.5)
    out = hsv.copy()
    for y in range(h):
        row = celestial[y]
        if row.any() and (~row).any():
            med = np.median(hsv[y][~row], axis=0)
            out[y][row] = med

    # Lift to daylight: softer hue, much lighter, less saturated.
    out[:, :, 0] = out[:, :, 0] * 0.35 + 0.565 * 0.65          # toward ~204 deg
    out[:, :, 1] *= 0.52
    out[:, :, 2] = 1.0 - (1.0 - out[:, :, 2]) * 0.34

    rgb_out = to_rgb(out)

    # A pale pixel sun with a soft circular glow. Placed low enough to clear
    # the status bar / Dynamic Island once the layer is stretched full-bleed.
    yy, xx = np.ogrid[:h, :w]
    cx, cy, r = int(0.70 * w), int(0.17 * h), max(3, h // 54)
    d = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2)
    sun_color = np.array([1.0, 0.96, 0.84])
    glow = np.clip(1.0 - (d - r) / (1.6 * r), 0.0, 1.0) * 0.30
    rgb_out = rgb_out * (1 - glow[:, :, None]) + sun_color * glow[:, :, None]
    rgb_out[d <= r] = sun_color
    return np.dstack([rgb_out, alpha])


def day_skyline(rgb: np.ndarray, alpha: np.ndarray, lift: float) -> np.ndarray:
    hsv = to_hsv(rgb)
    windows = warm_mask(hsv)

    # Buildings: cool haze — lighter with distance, desaturated, sky-hued.
    hsv[:, :, 0] = hsv[:, :, 0] * 0.5 + 0.58 * 0.5
    hsv[:, :, 1] *= 0.45
    hsv[:, :, 2] = 1.0 - (1.0 - hsv[:, :, 2]) * (1.0 - lift)

    # Windows off: warm light becomes slightly-darker cool glass.
    hsv[:, :, 0][windows] = 0.58
    hsv[:, :, 1][windows] = 0.22
    hsv[:, :, 2][windows] = np.clip(hsv[:, :, 2][windows] * 0.82, 0, 1)
    return np.dstack([to_rgb(hsv), alpha])


def dusk_sky(rgb: np.ndarray, alpha: np.ndarray) -> np.ndarray:
    hsv = to_hsv(rgb)
    h, w, _ = hsv.shape
    # Ramp reaches full warmth at the *visible* horizon (~62% down the sky
    # layer) — everything below that is hidden behind the skylines.
    t = (np.clip(np.linspace(0, 1, h, dtype=np.float32) / 0.62, 0, 1) ** 1.4)[:, None]

    # Hue: deep dusk blue up top sliding to ember at the horizon; clouds
    # (lighter pixels) catch the warmth hardest. The blend wraps blue ->
    # red -> orange (1.03 = 0.03 mod 1) so it never passes through green,
    # and the warmth curve keeps the upper sky calm — this must read as
    # golden hour, not the banned neon purple.
    target_h = (0.66 * (1 - t) + 1.05 * t) % 1.0
    warmth = 0.18 + 0.62 * t ** 1.3 + 0.12 * (hsv[:, :, 2] > 0.5)
    warmth = np.clip(warmth, 0, 0.9)
    # Blend hues on the circle: move each pixel toward target the short way.
    dh = (target_h - hsv[:, :, 0] + 0.5) % 1.0 - 0.5
    hsv[:, :, 0] = (hsv[:, :, 0] + dh * warmth) % 1.0
    # Saturation dips through the middle of the ramp — golden hour's
    # blue->peach transition is dusty, never electric magenta.
    s_env = 0.8 - 0.5 * np.sin(np.pi * t) ** 2 + 0.3 * t
    hsv[:, :, 1] = np.clip(hsv[:, :, 1] * s_env, 0, 0.72)
    hsv[:, :, 2] = np.clip(hsv[:, :, 2] * (0.9 + 0.38 * t), 0, 1)
    return np.dstack([to_rgb(hsv), alpha])


def dusk_skyline(rgb: np.ndarray, alpha: np.ndarray) -> np.ndarray:
    hsv = to_hsv(rgb)
    windows = warm_mask(hsv)

    # Silhouettes sink into violet; lit windows glow a touch warmer/brighter.
    hsv[:, :, 0] = np.where(windows, hsv[:, :, 0], hsv[:, :, 0] * 0.6 + 0.75 * 0.4)
    hsv[:, :, 1] = np.where(windows, np.clip(hsv[:, :, 1] * 1.1, 0, 1), hsv[:, :, 1] * 0.9)
    hsv[:, :, 2] = np.where(windows, np.clip(hsv[:, :, 2] * 1.12, 0, 1), hsv[:, :, 2] * 0.9)
    return np.dstack([to_rgb(hsv), alpha])


def write_imageset(name: str, arr: np.ndarray) -> None:
    folder = XCASSETS / f"{name}.imageset"
    folder.mkdir(exist_ok=True)
    Image.fromarray((arr.clip(0, 1) * 255).astype(np.uint8), "RGBA").save(folder / f"{name}.png")
    (folder / "Contents.json").write_text(json.dumps({
        "images": [{"filename": f"{name}.png", "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
    }, indent=2) + "\n")


def main() -> None:
    for layer in LAYERS:
        rgb, alpha = load(layer)
        if layer == "CitySky":
            write_imageset(f"Day{layer}", day_sky(rgb, alpha))
            write_imageset(f"Dusk{layer}", dusk_sky(rgb, alpha))
        else:
            write_imageset(f"Day{layer}", day_skyline(rgb, alpha, DAY_LIFT[layer]))
            write_imageset(f"Dusk{layer}", dusk_skyline(rgb, alpha))
    print(f"wrote Day*/Dusk* variants for {len(LAYERS)} layers to {XCASSETS}")


if __name__ == "__main__":
    main()
