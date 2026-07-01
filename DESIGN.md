# Sulav Sleep Design System — Rainy Pixel Night

Sulav Sleep should feel like looking out the window of a warm apartment on a
rainy evening while an old pixel-art game runs quietly in the background. It is a
bedside instrument, not a wellness dashboard. The interface exists to help
someone put the phone down at night, so it stays low-stimulation, legible, and
direct about the commitment window.

The mood blends four references: **Anthropic's Claude interface, Eastward,
Coffee Talk, and rainy Tokyo pixel art**. The pixel aesthetic lives in the
*environment* (the background scene), never in the usability layer. The UI
itself is minimal, editorial, and built on native iOS **Liquid Glass**.

> Note on history: earlier iterations used a purple "Lullaby" night sky. That
> direction is retired. The current system is warm amber against deep navy, with
> **no purple, no neon, no saturated/cyberpunk blues**.

## The scene (background)

The background is a living scene, not a flat color, built from six independent
parallax layers in `SleepBackground.swift`. Everything keeps moving even when
the phone is perfectly still; motion should read as weather, not software. If a
user consciously notices an animation, it is too strong.

Layers, back to front, with their parallax travel (px):

1. **Sky** (2px) — deep navy gradient, twinkling stars, slow clouds, warm moon.
2. **Distant city** (5px) — pixel skyline with tiny windows that flicker warm.
3. **Street glow** (10px) — soft orange bloom near the horizon, pulsing ±5%.
4. **Rain** (8px) — three depths: small/slow/faint, medium, and occasional
   bright close drops. Never perfectly vertical; some drops fade halfway.
5. **Foreground window** (14px) — frame vignette, condensation speckle, droplets
   sliding down the glass, a very faint diagonal reflection.
6. **Atmosphere** (6px) — faint drifting dust for depth.

Parallax comes from the gyroscope (`CoreMotion`), low-pass filtered so it eases
naturally with no snapping. When device motion is unavailable (e.g. Simulator) a
drag gesture drives it instead, and the continuous animation carries the scene.
Layers are overscanned (`scaleEffect(1.12)`) so parallax never reveals an edge.
The whole scene renders in a single `TimelineView` at ~30fps.

## Palette

| Token | Hex | Use |
| --- | --- | --- |
| `background` | `#08111E` | deepest night |
| `navy` | `#111827` | deep navy surfaces / sheets |
| `card` | `#18212F` | raised surface (rare) |
| `amber` | `#F4A261` | primary accent (indoor light) |
| `gold` | `#E9C46A` | secondary accent, good scores |
| `danger` | `#D96C75` | destructive, poor scores |
| `ink` | `#F5F5F2` | primary text |
| `dim` | `#B7BDC7` | secondary text |
| `muted` | `#7A8795` | tertiary/labels |
| `hairline` | white @ 6% | dividers |
| `border` | white @ 5% | glass borders |

Reasoning: the warm amber reads as indoor lighting against a cold night, which
is calming rather than clinical. Colored states are always paired with text and
position (score numerals change color *and* stay in a fixed spot) so the UI
survives a red night-shift tint.

## Liquid Glass

Centralized in `LiquidGlass.swift`. Native `glassEffect` on iOS 26+, with a
`.ultraThinMaterial` fallback (same shape + hairline border) on earlier
supported iOS. It should look like slightly fogged window glass on a rainy
night: light blur, subtle transparency, warm reflection, thin border — never
heavy frosted glass.

- Interactive glass only on tappable/focusable elements.
- Capsules for buttons and the bottom nav; continuous rounded rectangles for
  sheets and pickers.
- Primary button: amber→gold gradient fill, deep-navy ink, soft amber glow.
- Secondary button: subtle glass, ink text, hairline border.
- Do not build custom blur stacks when a native glass/material surface fits.

## Typography

Editorial neo-grotesk feel: generous spacing, light visual weight, highly
readable, calm. We use native **San Francisco** (`.default` design) rather than
bundling Inter — SF is Apple's own grotesk, keeps the app dependency-free, and
reads as award-grade native. Weights stay light; `.semibold` is reserved for
hero moments. Small-caps section labels use open `.tracking`.

- Hero (name, timer): `SleepFont.hero` — semibold.
- Titles / values: `SleepFont.title` — medium.
- Body: `SleepFont.body` — regular, ~1.5–1.6 line height for long copy.
- Labels / caps: `SleepFont.label` — medium, tracked via `.sectionLabel()`.

## Layout & containers

8pt grid (`4…40`), 24pt screen margins, 32–40 section gaps, ≥44pt touch targets,
58–64pt primary/secondary actions. Cards are rare — use containers only for
functional clusters (sheets, pickers, tappable controls) and never nest cards.
Most content is cardless: the schedule is open text, summaries are separated by a
single hairline, history uses divided rows.

## Motion

State changes fade/lift over ~260–320ms; presses scale subtly (~0.98). Nothing
bouncy or reward-like. Haptics (`Haptics`) are gentle and sparing: a soft tap
entering/leaving sleep and on nav, a success notification when a night is
logged.

## What to avoid

- Purple, neon, cyberpunk or blue-heavy identity.
- Generic wellness card stacks; bright white screens.
- Pixel icons inside the UI (pixel art is for the environment only).
- Decorative motion that doesn't support the sleep state.
- Long educational copy or tiny tap targets in the nighttime flow.
