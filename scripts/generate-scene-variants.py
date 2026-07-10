#!/usr/bin/env python3
"""Generate day and dusk variants of the pixel city scene layers.

The checked-in Night* layers (from the CraftPix night-city pack, see
CREDITS.md) are the source of truth; this script derives the Day* and Dusk*
imagesets from them so the Home scene can follow the user's day:

- **Day**: sky lifted to a hazy daylight blue (stars and moon healed away, a
  pale pixel sun drawn in), skylines lightened into cool haze with depth
  (far = hazier), and window lights turned off (warm pixels -> cool glass).
- **Dusk**: golden hour — deep blue up top through dusty rose into an ember
  horizon (never neon purple: the violet->rose corridor is desaturated by
  hue), clouds catch warm light, silhouettes sink into deep dusk navy, and
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


def split_sky(rgba: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Split a sky into (static base, scrolling clouds). The base keeps the
    gradient plus celestial bodies (sun/moon/stars) — which must NOT scroll —
    and heals cloud pixels to the row's sky color; the clouds layer keeps
    only cloud pixels on transparency."""
    rgb, alpha = rgba[:, :, :3], rgba[:, :, 3]
    hsv = to_hsv(rgb)
    h, w, _ = rgb.shape
    celestial = (hsv[:, :, 2] > 0.70) & (hsv[:, :, 1] < 0.5)

    base = rgb.copy()
    clouds = np.zeros((h, w, 4), dtype=np.float32)
    for y in range(h):
        row = rgb[y]
        med = np.median(row, axis=0)
        dev = np.abs(row - med).sum(-1)
        cloud = (dev > 0.05) & ~celestial[y]
        if cloud.any():
            clouds[y, cloud, :3] = row[cloud]
            clouds[y, cloud, 3] = alpha[y, cloud]
            base[y][cloud] = med
    return np.dstack([base, alpha]), clouds


def heal_celestial(rgba: np.ndarray) -> np.ndarray:
    """Heal stars + moon: bright, low-saturation outliers become the median
    sky color of their row (the day sky has neither)."""
    rgb, alpha = rgba[:, :, :3].copy(), rgba[:, :, 3]
    hsv = to_hsv(rgb)
    celestial = (hsv[:, :, 2] > 0.70) & (hsv[:, :, 1] < 0.5)
    for y in range(rgb.shape[0]):
        row = celestial[y]
        if row.any() and (~row).any():
            rgb[y][row] = np.median(rgb[y][~row], axis=0)
    return np.dstack([rgb, alpha])


def day_lift(rgba: np.ndarray) -> np.ndarray:
    """The daylight colorway: softer hue, much lighter, less saturated.
    Applied to base and clouds separately (the split happens on the
    high-contrast night art, where clouds are still detectable)."""
    hsv = to_hsv(rgba[:, :, :3])
    hsv[:, :, 0] = hsv[:, :, 0] * 0.35 + 0.565 * 0.65          # toward ~204 deg
    hsv[:, :, 1] *= 0.52
    hsv[:, :, 2] = 1.0 - (1.0 - hsv[:, :, 2]) * 0.34
    return np.dstack([to_rgb(hsv), rgba[:, :, 3]])


def sun_sprite() -> np.ndarray:
    """A standalone pixel-sun sprite (CitySun imageset). It is NOT baked
    into the sky: the readability veil would turn any warm disc olive, so
    the SwiftUI layer draws this sprite *above* the veil during the day —
    unveiled, warm, and static by construction (the sky base never
    scrolls, and neither does UI chrome). Hard pixels only; the renderer
    shows it with interpolation(.none)."""
    size = 32
    out = np.zeros((size, size, 4), dtype=np.float32)
    yy, xx = np.ogrid[:size, :size]
    d = np.sqrt((xx - size / 2 + 0.5) ** 2 + (yy - size / 2 + 0.5) ** 2)
    disc = d <= size * 0.42
    out[disc, :3] = np.array([1.0, 0.93, 0.72])
    out[disc, 3] = 1.0
    return out


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


def dusk_sky(rgba: np.ndarray) -> np.ndarray:
    rgb, alpha = rgba[:, :, :3], rgba[:, :, 3]
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
    target_h = (0.63 * (1 - t) + 1.05 * t) % 1.0
    warmth = 0.18 + 0.62 * t ** 1.3 + 0.12 * (hsv[:, :, 2] > 0.5)
    warmth = np.clip(warmth, 0, 0.9)
    # Blend hues on the circle: move each pixel toward target the short way.
    dh = (target_h - hsv[:, :, 0] + 0.5) % 1.0 - 0.5
    hsv[:, :, 0] = (hsv[:, :, 0] + dh * warmth) % 1.0
    # Dusty, never electric: the path from blue to ember necessarily
    # crosses the violet->rose corridor, so saturation dips wherever a
    # pixel actually *landed* in that corridor — keyed to hue, not height.
    # (An earlier height-keyed sine dip recovered exactly where the ramp
    # was hottest pink, which is how the sky went neon magenta.) Ember at
    # the horizon (h >= ~0.985, wrapping past red) keeps its saturation.
    # The dip is feathered on both hue edges — a boolean corridor cut a
    # hard seam across the sky where rows crossed the threshold.
    h_after = hsv[:, :, 0]
    rise = np.clip((h_after - 0.64) / 0.08, 0, 1)
    fall = np.clip((0.985 - h_after) / 0.05, 0, 1)
    corridor = (rise * rise * (3 - 2 * rise)) * (fall * fall * (3 - 2 * fall))
    hsv[:, :, 1] *= 1 - 0.55 * corridor
    # A gentle height-based envelope still calms the transition band.
    s_env = 0.8 - 0.3 * np.sin(np.pi * t) ** 2 + 0.3 * t
    hsv[:, :, 1] = np.clip(hsv[:, :, 1] * s_env, 0, 0.72)
    hsv[:, :, 2] = np.clip(hsv[:, :, 2] * (0.9 + 0.38 * t), 0, 1)
    return np.dstack([to_rgb(hsv), alpha])


def dusk_skyline(rgb: np.ndarray, alpha: np.ndarray) -> np.ndarray:
    hsv = to_hsv(rgb)
    windows = warm_mask(hsv)

    # Silhouettes sink into deep dusk navy — never violet (0.75 is pure
    # purple, the banned identity); lit windows glow a touch warmer/brighter.
    hsv[:, :, 0] = np.where(windows, hsv[:, :, 0], hsv[:, :, 0] * 0.6 + 0.65 * 0.4)
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
            # Split the *night* sky first (clouds are only detectable on the
            # high-contrast original), then apply each phase's colorway to
            # base and clouds separately. The base is static — celestial
            # bodies must not scroll — and the clouds drift past it.
            base, clouds = split_sky(np.dstack([rgb, alpha]))
            write_imageset("NightCitySkyBase", base)
            write_imageset("NightCityClouds", clouds)
            write_imageset("DayCitySkyBase", day_lift(heal_celestial(base)))
            write_imageset("CitySun", sun_sprite())
            write_imageset("DayCityClouds", day_lift(clouds))
            write_imageset("DuskCitySkyBase", dusk_sky(base))
            write_imageset("DuskCityClouds", dusk_sky(clouds))
        else:
            write_imageset(f"Day{layer}", day_skyline(rgb, alpha, DAY_LIFT[layer]))
            write_imageset(f"Dusk{layer}", dusk_skyline(rgb, alpha))
    print(f"wrote Day*/Dusk* variants + split skies to {XCASSETS}")


if __name__ == "__main__":
    main()
