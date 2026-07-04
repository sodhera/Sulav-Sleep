# SleepBlock Design System — Warm Pixel Night

SleepBlock should feel like looking out the window of a warm apartment over a
quiet city night while an old pixel-art game runs in the background. It is a
bedside instrument, not a wellness dashboard. The interface exists to help
someone put the phone down at night, so it stays low-stimulation, legible, and
direct about the commitment window.

The mood blends four references: **Anthropic's Claude interface, Eastward,
Coffee Talk, and quiet Tokyo night pixel art**. The pixel aesthetic lives in the
*environment* (the background scene), never in the usability layer. The UI
itself is minimal, editorial, and built on native iOS **Liquid Glass**.

> Note on history: earlier iterations used a purple "Lullaby" night sky. That
> direction is retired. The current system is warm amber against deep navy, with
> **no purple, no neon, no saturated/cyberpunk blues**.

## The scene (background)

The background is a living scene, not a flat color, composited in
`SleepBackground.swift`. Everything keeps moving even when the phone is
perfectly still; motion should read as ambient city depth, not software. If a user
consciously notices an animation, it is too strong.

The **base** is a real pixel-art night city (CraftPix, OGA-BY 3.0 — see
`CREDITS.md`): sky, moon, stars, clouds, and a warm-lit skyline. We do not
hand-draw the pixel art. It is warm-tinted (saturation pulled down, amber/ember
overlay) and darkened with a deep-navy scrim so UI text stays legible.

The runtime scene keeps real depth planes instead of baking the whole image into
a video. `SleepBackground.swift` composes separate sky/skyline layers, each
slightly oversized, independently scrolling, and independently moved by
`UIInterpolatingMotionEffect`. The sky barely moves; the front skyline moves
most.

The city, sky, clouds, moon, warm windows, slow layer drift, and depth parallax
carry the scene without extra visual noise or foreground weather effects. The
scene is purely ambient and never reacts to touch — depth parallax comes from
the device-tilt motion effect only, so the background can't shift under a tap or
intercept input meant for the UI above it.

The immersive sleep screen (`SleepModeView`) does **not** use this scene — it is
true OLED black (`Color.black`, no glow, no gradient) with only the ember-red
timer text for night vision. It opens straight into the minimal, collapsed
state (bare timer, "Tap to wake"); tapping the screen reveals the controls.

The whole scene runs through **Core Animation** layers, so SwiftUI does not run
a per-frame render loop. The native `TabView` host is opaque, so Home and
Profile each keep an in-tab scene (Profile's pushed sub-pages embed their own);
their layer clocks are synchronized to the same global animation phase so tab
switching and pushes do not reset the skyline motion. Onboarding keeps the
scene active through the keyboard transition.

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
supported iOS. It should look like slightly fogged night-window glass: light
blur, subtle transparency, warm reflection, thin border — never
heavy frosted glass.

- Interactive glass only on tappable/focusable elements.
- Capsules for buttons and the bottom nav; continuous rounded rectangles for
  sheets and compact time adjusters.
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

## Navigation & structure

Two tabs, each with exactly one job:

- **Home — go to bed.** Greeting, bedtime countdown, Sleep Now, last night's
  duration/score/streak. Nothing else: no settings affordance, no data dumps.
  The screen someone sees at 11pm must not offer anything to fiddle with.
- **Profile — everything about you.** Identity (editable name, account email)
  and the sleep record (weekly chart, averages, recent nights, an "All nights"
  page once history grows). A gear in the top-right opens Settings; the body
  itself stays a clean identity + record, with no configuration mixed in.

Settings live in a **full-screen cover** opened from the Profile gear — not a
half-height sheet (the throwaway-decision affordance the app deliberately
avoids) and not inline rows on Profile. Inside, it carries its own
`NavigationStack`, so Sleep schedule and Blocked apps push as full pages with
the onboarding chrome (round glass back chevron, left-aligned editorial title,
supporting line). The cover is dismissed by a glass ✕ in its top-right. The
only true sheet left in the app is Apple's own `FamilyActivityPicker`.

There is deliberately **no "reset all data" action**. A destructive escape
hatch sitting among everyday settings invites disaster and signals distrust of
the app's own record. Sign out is the only account-level exit, and it keeps
the local profile.

### Legibility over the scene

Text sits directly on the living pixel scene, whose lit windows are
high-contrast and can swallow light type where it crosses them. Every
scene-bearing screen therefore layers a `SceneReadabilityScrim` *between* the
background and the content: a full-bleed vertical gradient that stays clear
through the upper sky (moon and clouds untouched) and fades to ~80% deep-navy
by the bottom, where the busy skyline and most screen text live. Because it has
no edges or corners it reads as atmospheric haze, never a card, and it never
intercepts touches. Prefer this shared scrim over per-element text shadows or
darkening the whole scene.

## Layout & containers

8pt grid (`4…40`), 24pt screen margins, 32–40 section gaps, ≥44pt touch targets,
58–64pt primary/secondary actions. Cards are rare — use containers only for
functional clusters (sheets, pickers, tappable controls) and never nest cards.
Most content is cardless: the schedule is open text, summaries are separated by a
single hairline, history uses divided rows.

## Onboarding & auth

Two independent paths from a type-led welcome screen (kicker, brand hero,
tagline, no artwork in the UI layer): a primary "Get started" and a quiet "I
already have an account". The two paths are never linked to each other — the
choice is made here, so neither downstream screen carries an "already have an
account?" cross-link. Someone who picks wrong just backs out to welcome.

Sign-up runs the questionnaire *before* asking for an account — people who have
answered a few personal questions complete sign-up at a higher rate — and the
account step is the *final step of that same flow*: it carries the same progress
bar (now full) and back chevron as every other question, framed as saving the
plan they just made. The profile is only committed once that step's auth
succeeds, so "back" from it returns to the wake-time question like any other.

Onboarding stays short: name, sleep struggles, bedtime, wake, account. Apple
Health is deliberately *not* asked here — a system permission sheet mid-sign-up
is friction, and the ask lands better in context. Instead a warm, dismissable
glass card on Profile (`HealthConnectCard`) invites the connection where the
sleep data actually lives; it persists until connected or waved off, and the
Profile settings section still has the toggle.

Questionnaire chrome: a 3pt amber-gradient progress capsule between a round
glass back chevron and a matching spacer, editorial left-aligned questions
(small-caps kicker → 28pt title → dim supporting line → control), and
directional slide+fade step transitions (~280ms). Multi-select answers use
full-width capsule glass rows — muted icon, ink label, trailing circle that
fills amber when selected. No text "Back" buttons; the chevron is the only way
back. The sign-in screen ("Welcome back") is a single standalone screen with
the same chevron (back to welcome) and provider layout, so both paths read as
one system.

Provider stack: three buttons that read as one set — equal 58pt height and one
shared SF label (20pt medium). Apple and Google are the two branded providers on
matching white pills (Apple's `apple.logo`; the official multicolor Google "G"
mark — never a generic globe or a hand-drawn logo). Email is the quiet glass
path with an ink envelope. The amber→gold gradient is reserved for the app's
*own* primary actions, so it is deliberately never used on a third-party
provider button. Each button names the action being taken: "Sign up with …" in
the sign-up flow, "Sign in with …" on the returning-user ("Welcome back") path.

Signing out returns to the welcome screen, not a bare sign-in wall — the same
type-led choice a first-time visitor sees. A signed-out user's local profile is
retained, so if they sign back in the app goes straight to the main screen with
no repeat questionnaire; picking "Get started" re-runs it only if they choose to.

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
