#!/usr/bin/env python3
"""Port the SleepBlock sloth artwork into the Android app's resources.

Run *after* scripts/generate-app-icon.py so the iOS catalog is current —
this script only copies/derives from the PNGs that pipeline emits, so the
two platforms can never drift apart:

1. **Adaptive launcher icon** (mipmap-*dpi/ic_launcher_foreground.png):
   the transparent SplashSloth figure centered in the adaptive icon's
   66/108 safe zone, over the existing night-gradient background drawable.
   A monochrome layer (mipmap-*dpi/ic_launcher_monochrome.png) is derived
   from the figure's alpha for Android 13+ themed icons.
2. **In-app marks** (drawable-nodpi/): the night sloths for the welcome
   brand mark, Home's state figure, and the sleep screen's centerpiece.

Usage:
    python3 scripts/generate-android-assets.py

Requires: Pillow.
"""
from pathlib import Path

from PIL import Image

REPO = Path(__file__).resolve().parent.parent
XCASSETS = REPO / "ios/SulavSleep/Images.xcassets"
RES = REPO / "android/app/src/main/res"

# dp -> px per density bucket for the 108dp adaptive icon canvas.
DENSITIES = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
ADAPTIVE_DP = 108
SAFE_DP = 66  # the circle the launcher is guaranteed to show

# imageset PNG -> Android drawable name
IN_APP_MARKS = {
    "SplashSloth": "sloth_brand",              # icon colorway, transparent bg
    "NightSloth": "sloth_night",               # ember colorway (sleep screen)
    "HomeSlothNightAwake": "sloth_home_awake",
    "HomeSlothNightDrowsy": "sloth_home_drowsy",
    "HomeSlothNightBlink": "sloth_home_blink",
}

# The living-scene layers (pixel art, copied verbatim — the app upscales
# with nearest-neighbor so the pixels stay crisp).
SCENE_PHASES = {"Night": "night", "Dusk": "dusk", "Day": "day"}
SCENE_LAYERS = {
    "SkyBase": "sky",
    "Clouds": "clouds",
    "FarSkyline": "far",
    "MidSkyline": "mid",
    "NearSkyline": "near",
    "FrontSkyline": "front",
}


def imageset_png(name: str) -> Image.Image:
    path = XCASSETS / f"{name}.imageset" / f"{name}.png"
    return Image.open(path).convert("RGBA")


def emit_launcher_foreground() -> None:
    figure = imageset_png("SplashSloth")
    bbox = figure.getbbox()
    figure = figure.crop(bbox)

    for bucket, scale in DENSITIES.items():
        canvas_px = round(ADAPTIVE_DP * scale)
        safe_px = round(SAFE_DP * scale)
        canvas = Image.new("RGBA", (canvas_px, canvas_px), (0, 0, 0, 0))
        # Fit the figure into ~92% of the safe zone, centered.
        target = round(safe_px * 0.92)
        w, h = figure.size
        ratio = min(target / w, target / h)
        fig = figure.resize((round(w * ratio), round(h * ratio)), Image.LANCZOS)
        fx = (canvas_px - fig.width) // 2
        fy = (canvas_px - fig.height) // 2
        canvas.paste(fig, (fx, fy), fig)

        out_dir = RES / f"mipmap-{bucket}"
        out_dir.mkdir(parents=True, exist_ok=True)
        canvas.save(out_dir / "ic_launcher_foreground.png")

        # Monochrome themed-icon layer: the figure's alpha as solid white.
        mono = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
        white = Image.new("RGBA", canvas.size, (255, 255, 255, 255))
        mono.paste(white, (0, 0), canvas.getchannel("A"))
        mono.save(out_dir / "ic_launcher_monochrome.png")
    print(f"launcher foreground + monochrome emitted for {len(DENSITIES)} densities")


def emit_in_app_marks() -> None:
    out_dir = RES / "drawable-nodpi"
    out_dir.mkdir(parents=True, exist_ok=True)
    for imageset, drawable in IN_APP_MARKS.items():
        img = imageset_png(imageset)
        # Cap the long edge at 1024px — plenty for in-app rendering.
        long_edge = max(img.size)
        if long_edge > 1024:
            ratio = 1024 / long_edge
            img = img.resize(
                (round(img.width * ratio), round(img.height * ratio)), Image.LANCZOS
            )
        img.save(out_dir / f"{drawable}.png")
        print(f"{imageset} -> drawable-nodpi/{drawable}.png {img.size}")


def emit_scene_layers() -> None:
    out_dir = RES / "drawable-nodpi"
    out_dir.mkdir(parents=True, exist_ok=True)
    for phase, phase_slug in SCENE_PHASES.items():
        for layer, layer_slug in SCENE_LAYERS.items():
            imageset = XCASSETS / f"{phase}City{layer}.imageset"
            png = next(imageset.glob("*.png"))
            img = Image.open(png).convert("RGBA")
            img.save(out_dir / f"city_{phase_slug}_{layer_slug}.png")
    print(f"scene layers emitted ({len(SCENE_PHASES) * len(SCENE_LAYERS)})")


if __name__ == "__main__":
    emit_launcher_foreground()
    emit_in_app_marks()
    emit_scene_layers()
