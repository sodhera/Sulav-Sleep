#!/usr/bin/env python3
"""
Generate Play Store feature graphic (1024x500 px) for SleepBlock.
Built programmatically — zero distortion.
"""

import random
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter

REPO     = Path(__file__).resolve().parent.parent
ICON_SRC = REPO / "ios/SulavSleep/Images.xcassets/AppIcon.appiconset/App-Icon-1024x1024@1x.png"
OUT      = REPO / "playstore_feature_graphic.png"

FONT_BOLD    = "/System/Library/Fonts/SFCompactRounded.ttf"
FONT_REGULAR = "/System/Library/Fonts/SFNSRounded.ttf"

W, H  = 1024, 500
BG    = (8,   17,  30)
AMBER = (244, 162, 97)
GOLD  = (233, 196, 106)
INK   = (245, 245, 242)
DIM   = (183, 189, 199)

canvas = Image.new("RGB", (W, H), BG)
draw   = ImageDraw.Draw(canvas)

# ── Sky gradient ───────────────────────────────────────────────────────────
for y in range(H):
    t = y / H
    draw.line([(0, y), (W, y)], fill=(
        int(BG[0] + t * 7),
        int(BG[1] + t * 5),
        int(BG[2] + t * 12),
    ))

# ── Stars (upper-right quadrant only, away from text & sloth) ─────────────
rng = random.Random(42)
for _ in range(80):
    sx = rng.randint(460, W - 15)
    sy = rng.randint(8, 210)
    br = rng.randint(120, 215)
    r  = rng.choice([1, 1, 1, 2])
    draw.ellipse([sx - r, sy - r, sx + r, sy + r], fill=(br, br, br))

# ── Moon (upper-right, clear of sloth ZZZ zone) ───────────────────────────
MX, MY, MR = 895, 68, 40
# glow
glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
gd   = ImageDraw.Draw(glow)
for ri in range(MR + 50, MR, -1):
    a = int(20 * (1 - (ri - MR) / 50))
    gd.ellipse([MX - ri, MY - ri, MX + ri, MY + ri], fill=(215, 205, 165, a))
blurred = glow.filter(ImageFilter.GaussianBlur(16))
canvas.paste(blurred.convert("RGB"), mask=blurred.split()[3])
draw.ellipse([MX - MR, MY - MR, MX + MR, MY + MR], fill=(218, 214, 196))

# ── City skyline ──────────────────────────────────────────────────────────
# Taller buildings with solid fills first, then windows on top
GROUND_Y  = H - 10   # ground line
CITY_DARK = (11, 19, 33)
WIN_C     = (200, 128, 48)

buildings = [
    # (x, w, h_from_ground)
    (0,  48, 110),(48, 28, 80),(76, 38,128),(114,24, 92),(138,58,152),
    (196,22, 68),(218,48,118),(266,32, 96),(298,44,138),(342,26, 74),
    (368,52,108),(420,28, 84),(448,62,162),(510,22, 64),(532,44,112),
    (576,30, 88),(606,54,148),(660,24, 72),(684,58,128),(742,32, 98),
    (774,50,140),(824,22, 68),(846,46,118),(892,28, 84),(920,52,106),
    (972,52, 78),
]

for bx, bw, bh in buildings:
    top = GROUND_Y - bh
    # building body
    draw.rectangle([bx, top, bx + bw, GROUND_Y], fill=CITY_DARK)
    # windows
    rng2 = random.Random(bx * 13 + bh)
    pad  = 5
    col_w, row_h = 13, 18
    cols = max(1, (bw - pad * 2) // col_w)
    rows = max(1, (bh - pad * 2) // row_h)
    for row in range(rows):
        for col in range(cols):
            if rng2.random() < 0.40:
                wx = bx + pad + col * col_w
                wy = top + pad + row * row_h
                if wx + 7 <= bx + bw - pad and wy + 9 <= GROUND_Y - pad:
                    draw.rectangle([wx, wy, wx + 6, wy + 8], fill=WIN_C)

# Horizon amber glow strip (over buildings)
for y in range(GROUND_Y - 70, GROUND_Y + 1):
    t   = (y - (GROUND_Y - 70)) / 70
    glo = int(28 * t)
    for x in range(W):
        px = canvas.getpixel((x, y))
        canvas.putpixel((x, y), (
            min(255, px[0] + glo),
            min(255, px[1] + int(glo * 0.4)),
            min(255, px[2]),
        ))

# ── Sloth — extracted from existing app icon ──────────────────────────────
icon  = Image.open(ICON_SRC).convert("RGB")
# Sloth occupies roughly rows 270-970, cols 60-980 of the 1024x1024 icon
sloth = icon.crop((55, 265, 985, 975))

SLOTH_H = 295
SLOTH_W = int(SLOTH_H * sloth.width / sloth.height)
sloth   = sloth.resize((SLOTH_W, SLOTH_H), Image.LANCZOS)

# Position: right side, vertically mid-to-lower so pillow base sits at ~370px
sx = W - SLOTH_W - 18
sy = H - SLOTH_H - 88   # leaves room for city skyline below
canvas.paste(sloth, (sx, sy))

# ── ZZZs (gold, diagonal above sloth's head — left-center of sloth area) ──
zdraw = ImageDraw.Draw(canvas)
# sloth head is roughly left-third of the sloth crop
head_cx = sx + int(SLOTH_W * 0.32)
head_cy = sy + int(SLOTH_H * 0.35)

for size, (ox, oy) in zip([24, 33, 44], [(-20, -50), (8, -88), (40, -135)]):
    zf = ImageFont.truetype(FONT_BOLD, size)
    zdraw.text((head_cx + ox + 2, head_cy + oy + 2), "z", font=zf, fill=(70, 48, 8))
    zdraw.text((head_cx + ox,     head_cy + oy),     "z", font=zf, fill=GOLD)

# ── Left-side text ────────────────────────────────────────────────────────
TX = 50

# Kicker
draw.text((TX, 42), "SLEEPBLOCK", font=ImageFont.truetype(FONT_BOLD, 18), fill=AMBER)

# Headline
h1f = ImageFont.truetype(FONT_BOLD, 72)
draw.text((TX, 74),  "Block the apps.", font=h1f, fill=INK)
draw.text((TX, 151), "Get the sleep.",  font=h1f, fill=INK)

# Subtitle
draw.text((TX, 240), "Put your phone down. Wake up rested.",
          font=ImageFont.truetype(FONT_REGULAR, 22), fill=DIM)

# ── Helper: draw a crescent moon shape ───────────────────────────────────
def draw_crescent(d, cx, cy, r, color, bg):
    """Draw a crescent moon: outer disc minus offset inner disc."""
    # outer full disc
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=color)
    # inner disc offset right+up to carve out crescent
    ox, oy = int(r * 0.42), int(r * -0.10)
    ir = int(r * 0.82)
    d.ellipse([cx + ox - ir, cy + oy - ir, cx + ox + ir, cy + oy + ir], fill=bg)

# Button
BX, BY, BW, BHT = TX, 282, 228, 50
draw.rounded_rectangle([BX, BY, BX + BW, BY + BHT], radius=25, fill=AMBER)
bf   = ImageFont.truetype(FONT_BOLD, 21)
lbl  = "Sleep Now"
bbox = draw.textbbox((0, 0), lbl, font=bf)
lw   = bbox[2] - bbox[0]
lh   = bbox[3] - bbox[1]
# centre text+icon together; icon is 18px wide + 6px gap
ICON_W = 18
GAP    = 7
total_w = lw + GAP + ICON_W
tx_start = BX + (BW - total_w) // 2
draw.text(
    (tx_start, BY + (BHT - lh) // 2 - 1),
    lbl, font=bf, fill=(28, 16, 4)
)
# crescent moon icon to the right of text
MCX = tx_start + lw + GAP + ICON_W // 2
MCY = BY + BHT // 2
draw_crescent(draw, MCX, MCY, r=9, color=(28, 16, 4), bg=AMBER)

# ── Save ──────────────────────────────────────────────────────────────────
canvas.save(str(OUT), "PNG")
print(f"✅ {OUT}  —  {canvas.size[0]}x{canvas.size[1]} px  /  {OUT.stat().st_size // 1024} KB")
