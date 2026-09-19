#!/usr/bin/env python3
"""Render the onboarding stage's sky as a static image for the launch screen.

A launch storyboard cannot run code, so the stars it shows have to be baked.
This reproduces `OnboardingStage` (OnboardingExperience.swift) as closely as a
still can: the same five-stop sky, the same seeded star field through the same
LCG and splitmix64 seeding, the same crown-weighted distribution and descent
falloff, and the same ember horizon. Keep the constants here in step with that
file, or the launch screen will hand over to a different sky than the one the
app draws a frame later.

The stars are frozen at their mid-twinkle value, which is what Reduce Motion
shows in the app too.

Usage: python3 scripts/generate-splash-stars.py
"""
from __future__ import annotations

import math
import struct
import zlib
from pathlib import Path

W, H = 1290, 2796           # iPhone 15/16 Pro Max, scaled down by aspect fill
MASK = (1 << 64) - 1

# --- The same generator as StageRandom, including the splitmix64 finalizer ---


class StageRandom:
    def __init__(self, seed: int) -> None:
        self.state = seed & MASK

    def next(self) -> float:
        self.state = (self.state * 6_364_136_223_846_793_005 + 1_442_695_040_888_963_407) & MASK
        return ((self.state >> 11) & 0xFFFF_FFFF) / 0x1_0000_0000


def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def hex_rgb(value: int) -> tuple[float, float, float]:
    return ((value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF)


# Sky stops, matching OnboardingStage.sky at depth 0 (welcome's end of the ramp).
STOPS = [
    (0.00, hex_rgb(0x16243E)),
    (0.28, hex_rgb(0x101B2F)),
    (0.56, hex_rgb(0x0B1424)),
    (0.80, hex_rgb(0x080F1C)),
    (1.00, hex_rgb(0x050A14)),
]
EMBER = hex_rgb(0xE0854E)
AMBER = hex_rgb(0xF4A261)
GOLD = hex_rgb(0xE9C46A)


def sky_at(y: float) -> list[float]:
    for (p0, c0), (p1, c1) in zip(STOPS, STOPS[1:]):
        if y <= p1:
            t = 0 if p1 == p0 else (y - p0) / (p1 - p0)
            return [lerp(c0[i], c1[i], t) for i in range(3)]
    return list(STOPS[-1][1])


def build() -> bytearray:
    rows = bytearray()
    # Horizon: a wide, shallow ember wash anchored just below the frame.
    hx, hy = W / 2, H * 0.99
    rx, ry = W * 1.3, W * 1.3 * 0.3
    intensity = 0.46

    for py in range(H):
        rows.append(0)  # PNG filter byte: none
        sky = sky_at(py / (H - 1))
        for px in range(W):
            # Start from the sky every pixel. An earlier version screened the
            # horizon into the shared scanline list, so each pixel inherited
            # every blend to its left and the bottom of the image saturated to
            # white — the classic "accumulating into the accumulator" bug.
            r, g, b = sky
            dx = (px - hx) / rx
            dy = (py - hy) / ry
            d = math.hypot(dx, dy)
            if d < 1:
                # Same three-stop falloff as the app's radial gradient.
                if d < 0.38:
                    tint, a = EMBER, intensity * (1 - d / 0.38 * 0.5)
                elif d < 0.66:
                    tint, a = AMBER, intensity * 0.5 * (1 - (d - 0.38) / 0.28)
                else:
                    tint, a = GOLD, intensity * 0.16 * (1 - (d - 0.66) / 0.34)
                a = max(0.0, min(1.0, a))
                # `.screen`, as in the app.
                r, g, b = (
                    255 - (255 - base) * (255 - c * a) / 255
                    for base, c in zip((r, g, b), tint)
                )
            rows += bytes((int(max(0, min(255, r))),
                           int(max(0, min(255, g))),
                           int(max(0, min(255, b)))))
    return rows


def draw_stars(buf: bytearray) -> None:
    """Crown-weighted, descent-faded, frozen mid-twinkle. Mirrors StarField."""
    random = StageRandom(0x5EEDBED)
    ceiling = H * 0.48
    lift = 0.85                      # depth 0
    for _ in range(42):
        t = pow(random.next(), 1.6)
        brightness = random.next()
        x = random.next() * W
        y = t * ceiling
        radius = (0.6 + brightness * 1.6) * (W / 393)   # pt -> px
        alpha_base = 0.30 + brightness * 0.62
        warm = random.next() < 0.22
        haloed = brightness > 0.55
        random.next(); random.next(); random.next(); random.next(); random.next()

        descent = pow(1 - t, 1.25)
        alpha = min(alpha_base * lift * descent, 0.95)
        if alpha <= 0.01:
            continue
        tint = GOLD if warm else (255.0, 255.0, 255.0)

        if haloed:
            blot(buf, x, y, radius * 3.1, tint, alpha * 0.42, soft=True)
        blot(buf, x, y, radius, tint, alpha, soft=False)


def blot(buf: bytearray, cx: float, cy: float, r: float,
         tint: tuple[float, float, float], alpha: float, soft: bool) -> None:
    x0, x1 = max(0, int(cx - r) - 1), min(W - 1, int(cx + r) + 1)
    y0, y1 = max(0, int(cy - r) - 1), min(H - 1, int(cy + r) + 1)
    for py in range(y0, y1 + 1):
        stride = py * (W * 3 + 1) + 1
        for px in range(x0, x1 + 1):
            d = math.hypot(px - cx, py - cy)
            if d > r:
                continue
            a = alpha * (1 - d / r) if soft else alpha * min(1.0, (r - d) * 2)
            if a <= 0:
                continue
            o = stride + px * 3
            for i in range(3):
                buf[o + i] = int(max(0, min(255, buf[o + i] * (1 - a) + tint[i] * a)))


def write_png(path: Path, buf: bytes) -> None:
    def chunk(tag: bytes, data: bytes) -> bytes:
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    header = struct.pack(">IIBBBBB", W, H, 8, 2, 0, 0, 0)
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(bytes(buf), 9))
        + chunk(b"IEND", b"")
    )


def main() -> None:
    out = Path(__file__).resolve().parent.parent / "ios/SulavSleep/Images.xcassets/SplashSky.imageset"
    out.mkdir(parents=True, exist_ok=True)
    buf = build()
    draw_stars(buf)
    write_png(out / "SplashSky.png", buf)
    (out / "Contents.json").write_text(
        '{\n  "images" : [\n'
        '    { "filename" : "SplashSky.png", "idiom" : "universal", "scale" : "1x" },\n'
        '    { "idiom" : "universal", "scale" : "2x" },\n'
        '    { "idiom" : "universal", "scale" : "3x" }\n'
        '  ],\n  "info" : { "author" : "xcode", "version" : 1 }\n}\n'
    )
    print(f"wrote {out/'SplashSky.png'}  ({W}x{H})")


if __name__ == "__main__":
    main()
