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

The immersive sleep screen (`SleepModeView`) does **not** use this scene — it
is true OLED black (`Color.black`; only ember pixels are ever lit). **Ember
is not a separate color identity**: it is the app's indoor amber banked down
to coals — same warm hue family (`ember #E0854E`, `emberDim`, `emberGlow`,
`emberDeep`), deeper and dimmer, so sleep mode reads as "the apartment lamp
turned down for the night" while staying warm, long-wavelength, and kind to
night vision. No crimson, no salmon. The screen is the night-side sibling of
Home's bedtime ring: a thin 270° **ember night ring** (faint track,
deep→bright ember fill, small glowing tip) fills from sleep start toward the
scheduled wake time, with an "ASLEEP" kicker, the elapsed timer, and a small
sunrise-glyph wake target at its center — "how far into the night am I" at
half-asleep glance distance. Oversleeping simply holds the ring full. It
opens straight into this collapsed instrument; the "Tap to wake" hint
breathes very slowly at the bottom, and tapping the dark toggles the
controls in and out.

Sleep-mode controls follow one grammar: **deliberate exits are held,
harmless returns are taps.** Entering sleep took a deliberate slide, so
ending the night is *Hold to wake* — a 1.2s press-and-hold capsule that
needs zero precision from a half-asleep hand and cannot fire from a stray
tap: a rigid tap answers the press, heavy ticks ratchet up while a deep
ember fill sweeps the capsule, and a double heavy knock + success lands at
completion (released early, the fill sighs back with a soft tap). *Back to
sleep* is a plain tap — it costs nothing. *Hold to cancel* (drops the
lockdown, logs no night) is the same hold mechanic, quieter and shorter
(0.8s). There is no single-tap way out of a night.

*Hold to wake* and *Back to sleep* share one footprint (58pt, the app's
standard action height) so they read as two ways to leave the same screen —
but never the same weight. Hold to wake carries a banked-coal resting tint
under its fill, a warm border, and an ember glow shadow, so it reads warm
and primary even before it's touched; Back to sleep stays flat, cool glass
with a neutral hairline and dimmer ember text, so it reads as the free
option at a glance, without needing to read either label.

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
- **The glass owns its chrome.** Never paint a manual `Capsule().fill(…)` or
  hairline `stroke` on top of a `.liquidGlass()` surface — on iOS 26 that
  mutes the real material into a flat tinted panel. The pre-26 fallback
  draws its own hairline (and honors the `tint` parameter as a wash over the
  material), so call sites add strokes only when they carry *meaning* (the
  amber selection ring on onboarding's struggle rows) or *branding* (the
  white provider pills, which are deliberately not glass).
- **Touch-driven controls drive their reaction from a custom `ButtonStyle`,
  not a plain button.** Interactive Liquid Glass alone is not enough: a
  `.buttonStyle(.plain)` button + a bare `.glassEffect(.interactive())` on
  its label *looks* interactive but feels dead, because the plain button's
  gesture recognizer swallows the touch and the glass never receives the
  press. The fix is a `ButtonStyle` that owns `configuration.isPressed`, so
  it can guarantee a visible reaction — a springy scale (jelly squish) —
  layered on top of the `.interactive()` glass. The scale reacts everywhere
  (including where the OS doesn't render the glass's own deformation); the
  glass adds the real material morph on device. Two styles do this:
  `GlassCircleButtonStyle` (icon buttons) and `GlassCapsuleButtonStyle`
  (action buttons). Note the behavioral truth: **buttons squish-and-settle
  on press; they do not stretch to follow a dragging finger** — that
  gel-follow belongs only to genuinely draggable controls (the slide-to-sleep
  knob), not tap targets.
- Primary button (`LiquidPrimaryButton`, e.g. Sleep Now): an amber-tinted
  interactive glass capsule (`GlassCapsuleButtonStyle` with an amber tint),
  deep-navy ink, soft amber glow, 58pt tall. The bright amber tint keeps it
  the brightest control so it never melts into the pixel skyline (it reads as
  translucent amber *glass*, not a solid pill). The amber→gold gradient
  capsule survives only as the pre-26 fallback.
- Secondary button (`LiquidSecondaryButton`): the same capsule style with no
  tint, ink text; subtle material capsule pre-26.
- The **slide-to-sleep knob** is real interactive Liquid Glass (bright amber
  tint), driven by a genuine `DragGesture`, with the track+knob in a
  `GlassEffectContainer`. Because it is a real drag control it *does* get the
  finger-follow morph as it slides — the app's showpiece liquid gesture.
  Pre-26 keeps the amber→gold gradient disc.
- Sibling glass shapes that read as one set (Home's two schedule chips, the
  onboarding struggle capsules, the slide track+knob) sit inside a
  **`LiquidGlassContainer`** (`GlassEffectContainer` on 26+, passthrough
  earlier) so nearby glass samples and blends together the way Apple
  intends. Wrap exactly one layout view.
- Do not build custom blur stacks when a native glass/material surface fits.
- Small circular icon actions (Profile's gear, the Settings sheet's close ✕,
  onboarding's back chevron) go through **`GlassIconButton`** — its
  `GlassCircleButtonStyle` pairs `.glassEffect(.regular.interactive(),
  in: .circle)` with a springy `isPressed` squish, so the circle visibly
  reacts to a press (the whole `size` circle is the glass region, so no
  content-inset math is needed). The Profile gear and the
  Settings close ✕ share one 56pt circle so the two read as one affordance;
  the onboarding chevron sits at 44pt — quieter, but never smaller than a
  comfortable target — and the questionnaire keeps its progress bar centered
  by mirroring the chevron with a hidden twin rather than a hardcoded spacer
  width.

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

- **Home — go to bed.** A near-wordless bedside instrument that never
  scrolls: no settings affordance, no data dumps, nothing to fiddle with at
  11pm. One centered column: an editorial small-caps greeting kicker over the
  hero name (the same kicker → title chrome as onboarding), then the
  **bedtime ring** — a 270° gauge arc (speedometer gap at the bottom) that
  fills gold→amber as the waking day runs from wake time toward bedtime, a
  glowing moon marker riding the arc tip, and the "Bedtime in" countdown
  numerals in the center. The dim track is drawn at 18% white opacity, not
  8% — Home's lit pixel-art sky gives it far less free contrast than the
  ember night ring's OLED black, and at low progress a short amber arc
  against a nearly-invisible track reads as a disconnected floating shape
  rather than "one ring, partially filled" (confirmed by pixel-measuring a
  real render: the arc's endpoints sit on the exact same circle as the
  track, so it was a legibility problem, not a geometry one). For a few
  hours after bedtime the ring sits full and amber and the numerals give
  way to a "Wind down" nudge (mirroring the small widget) instead of
  counting 20-odd hours to *tomorrow's* bedtime. Under the ring, two small
  non-interactive glass chips state tonight's
  window (moon + bedtime, sun + wake) — read-only; the schedule is edited in
  Settings. The Sleep Now capsule anchors low where a thumb rests, with last
  night as one quiet centered strip beneath it (`Last night 7h 20m · 82 ·
  🔥3`). With no history the strip renders nothing at all — no hairline, no
  empty-state copy; the pixel scene carries the space.
  Tapping "Sleep Now" does *not* start sleep immediately — the whole screen
  transitions to a **confirmation** that is deliberately near-wordless: a
  "Tonight" kicker, one hero gold number (the sleep you'd get sliding now),
  a one-line `of sleep · wake 6:30 AM` sub, a single compact glass row for
  the lockdown (lock glyph + the app icons themselves — icons over words; an
  open lock + "No apps blocked tonight" otherwise), and the iPhone-style
  **slide-to-sleep** capsule. The capsule is deliberately the brightest
  control in the app — it is the one thing to do on this screen, so it gets
  to look like it and must never melt into the pixel skyline. It reads as a
  *near-solid night rail*: tall (72pt), deep navy at ~90% opacity with an
  inner shadow so the knob visibly sits in something, rimmed in a warm amber
  gradient, and carrying its own resting amber glow plus a dark drop shadow
  to separate from the scene. The hint is bright ink with the classic
  slide-to-unlock shimmer (a gold band masked to the glyphs) beside three
  gold chevrons breathing in sequence toward the destination. The knob drags
  a warm light trail across the rail, its glow builds with progress, and at
  the completion threshold a gold "ready" ring blooms around it (with the
  heavy knock) while the rim brightens; on completion the moon glyph becomes
  `moon.zzz`. The confirmation *scrolls up* into view when
  Sleep Now is tapped and — on "Cancel" — *scrolls back down* the same way it
  arrived (Home slides in from the top behind it), never a fade in place.
  Sliding the knob across the full track starts the session. The slide gesture
  is what makes the commitment deliberate — the screen doesn't need paragraphs
  on top of it — and it's the one place haptics are deliberately *rich* rather
  than sparing: the knob ratchets through light detents that strengthen with
  progress, a firmer tap fires the moment it crosses the completion threshold
  ("let go now"), releasing short of it gives a soft acknowledging tap, and a
  success notification lands when the night begins.
- **Profile — everything about you.** Identity (name only, display-only — no
  pencil, no email; both are edited/shown in Settings so the body stays
  read-only), then a **stat band** straight under the name — Avg sleep, Avg
  score, Streak as three big numerals over tiny labels, the dashboard read of
  the record — then the tappable **"Blocked while you sleep"** block
  previewing the locked-app icons (opens the Blocked apps screen for
  changes), and the sleep record (weekly chart, recent nights, an "All
  nights" page once history grows). A gear in the top-right opens Settings;
  the body itself stays a clean identity + record, with no configuration
  mixed in.
  The blocked block is a section label over an **interactive glass row** —
  containers are reserved for tappable controls, and the glass is what says
  "you can press this"; plain floating text read as static copy. Before any
  apps are chosen it shows a warm lock glyph in a soft circle beside one
  short line ("Choose apps to block" — no explanatory copy; the row itself
  is the invitation); with a selection it previews the app icons. Empty
  states across Profile use that same glyph-row pattern (the sleep record
  opens with a moon-and-stars glyph and "No nights yet / Your record starts
  tonight.") — composed and warm, but never ghost charts or sample numbers:
  honest data only.

Settings live in a **collapsible full-height sheet** opened from the Profile
gear — presented at the `.large` detent with a drag indicator, so it rises as a
full-screen card that can be swiped down to collapse, and dismissed by a glass ✕
in its top-right. It is not a half-height sheet (the throwaway-decision
affordance the app avoids) and not inline rows on Profile. Inside, it carries
its own `NavigationStack`, so Sleep schedule and Blocked apps push as full pages
with the onboarding chrome (round glass back chevron, left-aligned editorial
title, supporting line). The body is three kicker-titled `GlassGroup`s —
**Profile** (editable Name: tap → rename alert; read-only account Email, no
chevron, middle-truncated — both live here, never on the Profile body),
**Sleep** (Schedule, Blocked apps, the Apple Health toggle — no explainer
sublines), and **Account** (Sign out in dim; Delete account faded beneath it —
a rare, irreversible exit that never competes for attention). The pixel-art
credit sits quietly at the very bottom. The only other sheet in the app is
Apple's own `FamilyActivityPicker`.

The **Blocked apps** page follows the same grammar: a one-line supporting
sentence under the title ("Locked from Sleep Now until you wake. Calls always
work."), then a single `GlassGroup` — an Apps row (value "None"/"N chosen" →
`FamilyActivityPicker`) and the "Unlock anyway after" safety stepper with its
amber hour value. The chosen apps render below the group as a system-drawn
**icon grid** (tokens are opaque, Apple draws them) — the user sees exactly
what locks, without a text list.

There is deliberately **no enable/disable toggle**. Choosing apps *is* the
commitment: whatever is selected always locks during sleep, and the only way
to turn blocking off is to remove the apps (clearing the selection tears down
the scheduled shield). A separate switch would be a second decision that just
restates the first, and a picked-but-disabled state invites the exact
"technically armed, actually off" confusion the app avoids. Screen Time
authorization is requested lazily — the first tap on the Apps row — because
the picker is useless without it and a granted request is what arms the
lockdown. `SleepStore.willLockDuringSleep` (authorized *and* at least one app
chosen) is the single source of truth for "are apps blocked" across Home, the
confirmation panel, and the profile preview.

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
Most *content* is cardless: summaries are separated by a single hairline,
history uses divided rows. *Controls* are the exception: settings surfaces
group their rows into **`GlassGroup`** containers (`LiquidGlass.swift`) — a
small-caps kicker above a glass rounded-rect holding `GlassRow`s divided by
hairlines. Each row leads with a `GlassRowIcon` chip (the SF symbol in a soft
rounded square tinted from its own color — amber for sleep things, dim/faint
for account exits) so rows scan by glyph first, then one short title and a
quiet trailing value/chevron. Rows name things, they never explain them: no
subtitle lines inside rows.

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
glass back chevron and a hidden twin of it (so the bar stays centered at
whatever size the system draws the button), editorial left-aligned questions
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
logged. The deliberate exceptions are the night's two commitment gestures,
which are the strongest, most forceful haptics in the app on purpose: the
**slide-to-sleep** knob (a rigid tap on grab, a heavy ratchet through eight
detents climbing from 70% to 100% intensity, a double heavy knock at the
completion threshold, a soft tap on a released spring-back, and the success
notification when the night begins) and the sleep screen's **hold buttons**
(rigid tap on press, a five-detent heavy ratchet at the same climbing
intensity while the ember fill sweeps, a double heavy knock at completion —
plus success when waking). Both ratchets deliberately run on the `heavy`
generator, not `medium`, so they read through a firm, half-asleep grip;
the double knock is the single strongest cue in the app, reserved for these
two moments. Entering and leaving a night should feel like moving something
with real weight.

## Widgets

Widgets live in `SulavSleepWidget.swift` and split one job across surfaces:

- **Small (home screen) — tonight.** A bedtime instrument, not a stats tile.
  Three states: before bed (moon glyph, "BEDTIME" caps label, hero clock time,
  a system-driven "in Xh Ym" countdown, and a quiet last-night line), past
  bedtime (amber "Past bedtime — wind down"), and asleep. The asleep state
  mirrors `SleepModeView`: true black container, ember timer, nothing else.
- **Medium — the morning glance.** Last night's score as the hero numeral
  (colored by the score rules below), duration, streak/average, and the
  7-night bar rhythm on the right, with a Sleep Now capsule anchoring the
  left column.
- **Large — both.** Stats + full-width bars with weekday initials, then a
  hairline and a single "tonight" footer line (bedtime countdown or asleep
  timer) with the Sleep Now capsule on its trailing side.
- **Lock-screen accessories** (circular / rectangular / inline) render in the
  system's vibrant material, so they use default foregrounds — no app palette.
  Circular is a score gauge (or a moon when asleep / no data); rectangular and
  inline lead with tonight's state.

Rules:

- Background is the *minimal night gradient* — `skyTop → background` with a
  ~10% amber floor glow. No pixel-art scene in widgets: at widget size the
  skyline reads as noise and fights legibility, and the flat gradient survives
  iOS dark/tinted home-screen rendering. Key glyphs and numerals are marked
  `widgetAccentable` for tinted mode.
- Score numerals keep the app's coloring: gold ≥ 80, ink 60–79, danger < 60 —
  always in a fixed position so the layout survives a night-shift tint.
- Bars: gold→amber capsules against a faint target hairline; the latest night
  is full-strength, earlier nights recede to ~60% so "last night" reads first.
  Each bar carries the hours slept that night as a 9pt navy-ink label set
  inside its *bottom* (the amber-fill/navy-ink pairing from the primary
  button) — bottom-anchored so every label sits on one shared baseline no
  matter the bar heights: "7.5h" on the large widget, whole-number "7" in the
  medium widget's narrower columns. Bars too short to hold the label drop it
  rather than overflow.
- Honest data only. A placed widget with no history shows "Log a night" /
  "Set a schedule" — never fake numbers. The one exception is the
  widget-gallery preview (`context.isPreview`), which shows sample content so
  the gallery isn't a blank tile.
- One action only: the **Sleep Now capsule** on medium/large (primary-button
  style — amber→gold gradient, navy ink, moon glyph) rides the
  `sleepblock://sleep` deep link, so a deliberate tap opens the app, starts
  the session, and lands on the sleep screen. It hides while asleep (an ember
  "Asleep" timer line takes its place). The widget *body* carries no
  `widgetURL` — a stray tap just opens the app and must never start a
  session.
- Timers and countdowns use system-driven `Text(_, style:)` so they tick
  without timeline churn; timeline entries exist only to flip states at the
  bedtime and wake boundaries.

## What to avoid

- Purple, neon, cyberpunk or blue-heavy identity.
- Generic wellness card stacks; bright white screens.
- Pixel icons inside the UI (pixel art is for the environment only).
- Decorative motion that doesn't support the sleep state.
- Long educational copy or tiny tap targets in the nighttime flow.
