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

> Platforms: this document is written against the flagship iOS app. The
> Android port (`android/`, see `docs/android.md`) follows the same palette,
> type scale, structure, and copy rules, but renders the *fallback* glass
> grammar (translucent deep-navy surfaces + hairline borders) over the
> widgets' minimal night gradient — Liquid Glass and the living pixel scene
> are iOS-only until the scene is ported.

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

**The city follows the user's day** (`CityPhase`: day 5–17, dusk 17–22, night
22–5 — the same bands as the greeting copy, so "Good afternoon" is never said
over a midnight sky). *Day*: hazy daylight blue, stars and moon healed away, a
stationary pale pixel sun, windows off (warm pixels remapped to cool glass),
street glows and the amber wash disabled, the scene scrim eased so daylight
reads. *Dusk*: golden hour — deep blue into dusty rose into an ember horizon
(never neon purple; the saturation deliberately dips through the pink band),
windows lit. *Night*: the original art, untouched — still the app's core
identity. Day and dusk layers are **generated, never hand-edited**, from the
night layers by `scripts/generate-scene-variants.py`; the view crossfades
between phases at the minute the clock crosses a boundary. The sky is two
planes: a **static base** (gradient + moon/stars — celestial bodies must not
scroll) and a **clouds layer** drifting past it; the split happens on the
high-contrast night art, then each phase's colorway is applied to both. The
day sun is a hard-pixel sprite (`CitySun`) drawn by the readability veil
*above* itself — a warm disc under the day veil turns olive, so the sun gets
the same above-the-veil privilege the moon gets from night's clear upper
stops — and it is static by construction. Home's sloth wears
the same light (`HomeSloth{Day,Dusk,Night}{Awake,Drowsy,Blink}`), and blinks
every few jittered seconds — a pixel-aligned closed-eye frame flashed for
120ms, a hard cut like a cartoon blink should be (suppressed, along with the
breath, under Reduce Motion). Because the whole ink system was designed
against a dark night stage, the readability veil is also phase-aware: day
and dusk get a full-height veil (deepest in the text bands) so grey muted
text, white-opacity quiet/faint, and gold heroes keep their contrast on the
brighter skies; night keeps its clear upper sky. Section-label kickers are
`dim` with a soft navy shadow — small quiet caps get no free contrast from
a bright sky, and the shadow travels with the text across all phases.

The immersive sleep screen (`SleepModeView`) does **not** use this scene — it
is true OLED black (`Color.black`; only ember pixels are ever lit). **Ember
is not a separate color identity**: it is the app's indoor amber banked down
to coals — same warm hue family (`ember #E0854E`, `emberDim`, `emberGlow`,
`emberDeep`), deeper and dimmer, so sleep mode reads as "the apartment lamp
turned down for the night" while staying warm, long-wavelength, and kind to
night vision. No crimson, no salmon. The centerpiece is the **night sloth**
(`NightSloth.imageset`, generated by `scripts/generate-app-icon.py`): the
app icon's sloth banked down to the ember family — body `emberDim`, face lit
ember, pillow reduced to deep warm coals, outlines near-black so the
silhouette melts into the OLED dark — asleep on its pillow with a slow chain
of ember z's rising off its head, the icon's ZZZ alive: each z drifts up the
same diagonal, swells a touch, and fades before the next follows, staying
`emberDim` and quieter than the timer so it reads as breathing, not motion
(under Reduce Motion it freezes into the icon's static diagonal). Beneath
the sloth sit the "ASLEEP" kicker, the elapsed timer, and a small
sunrise-glyph wake target. The sloth is the *state* — the app visibly doing
its job — and the numbers are the *instrument*.

> Note on history: earlier iterations centered a 270° **ember night ring**
> (the night-side sibling of Home's since-retired bedtime ring) that filled
> from sleep start toward wake. It is retired: its one reading — how far
> into the night — is already carried by the elapsed timer and the wake
> line at half-asleep glance distance, arc precision is a
> daytime-dashboard value, and dropping ~270° of lit stroke leaves fewer
> ember pixels on the OLED.

The screen opens straight into this collapsed state; the "Tap to wake" hint
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
but never the same weight. Both are real interactive Liquid Glass on iOS 26+
(the hand-drawn capsules of earlier revisions survive only as the pre-26
fallback): Hold to wake is ember-tinted glass with an ember glow shadow, so
it reads warm and primary even before it's touched — since it's a manual
hold gesture rather than a `Button`, its press feedback comes from the
existing ratchet-driven scale, with the glass adding the real material morph
on top; Back to sleep is untinted, cool glass with dimmer ember text, so it
reads as the free option at a glance, without needing to read either label.
*Hold to cancel* stays deliberately chromeless — no glass, no fill — so it
reads as a quiet text link that all but disappears until pressed, matching
its role as a rare, irreversible exit (see "What to avoid").

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
| `gold` | `#E9C46A` | secondary accent, streak / highlights |
| `danger` | `#D96C75` | destructive actions |
| `ink` | `#F5F5F2` | primary text |
| `dim` | `#B7BDC7` | secondary text |
| `muted` | `#7A8795` | tertiary/labels |
| `hairline` | white @ 6% | dividers |
| `border` | white @ 5% | glass borders |

Reasoning: the warm amber reads as indoor lighting against a cold night, which
is calming rather than clinical. Colored states are always paired with text and
position (never color alone) so the UI survives a red night-shift tint.

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
  hero name (the same kicker → title chrome as onboarding), then the **home
  sloth** — the app's sloth lounging on a night-blue pillow in the amber
  colorway (`HomeSlothAwake` / `HomeSlothDrowsy`, generated with the icon by
  `scripts/generate-app-icon.py`, which redraws the eyes in class space) —
  over the "Bedtime in" countdown numerals. The sloth is the *state*: awake
  with round open eyes through the day, heavy-lidded once bedtime is within
  90 minutes or just past; the numerals are the *instrument*. The pillow is
  blue-tinted grey, not neutral, so the figure sits in the scene's air; a
  faint amber halo behind it carries the app's warm-light-against-cold-night
  story; and the sloth *breathes* — a barely-there 3.6s body swell anchored
  at the pillow (stilled under Reduce Motion), which keeps it a creature
  rather than a sticker while staying under the notice threshold.

  Past bedtime the countdown **turns around** rather than rolling over: the
  kicker reads **"Past bedtime"** and the same hero numerals count *up*, in
  amber. Rolling over answered a question nobody asked — telling someone who
  is up too late that tomorrow's bedtime is 20 hours away, when the fact that
  matters is how far past tonight's they are. (An earlier revision showed a
  wordless "Wind down" for four hours and then rolled over anyway; the number
  is the more useful thing, and it shouldn't stop halfway through the night.)
  It runs the **whole bedtime→wake window** — the same span the shield covers,
  so Home and the shield never describe one moment two ways. After wake time a
  forward countdown is genuinely correct, and it returns. The sloth stays
  drowsy throughout. The small widget still shows its own "Wind down" nudge.

  > Note on history: Home's hero was previously a 270° **bedtime ring**
  > (gold→amber fill over the waking day, a moon marker riding the tip, the
  > countdown in its center). Retired for the same reason as the sleep
  > screen's night ring: its real payload was the countdown numeral, day
  > progress is dashboard precision nobody reads at 11pm, and the sloth
  > tells the state warmer — while keeping the same one-glance answer.

  Under the sloth, one small non-interactive glass capsule states tonight's
  window as the single fact it is — moon + bedtime → sun + wake — rather
  than two disconnected chips; read-only, the schedule is edited in
  Settings. The Sleep Now capsule anchors low where a thumb rests, with last
  night as one quiet centered strip beneath it (`Last night 7h 20m · 82 ·
  🔥3`). The strip only appears when the newest night can honestly be called
  "last night" — it ended this morning or yesterday; older records are stale
  and never wear that label. With no history (or only stale history) the strip
  renders nothing at all — no hairline, no empty-state copy; the pixel scene
  carries the space. (Same recency gate feeds the widget's morning glance, so
  it never shows weeks-old hours as last night's.)
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
- **Profile — everything about you.** A one-line header — the editorial title
  "Profile" left, the Settings gear right — and then the record. **No name on
  this screen.** It used to headline the user's name (gear floating on a row
  above it), but Home already greets you by name in the same hero face, so the
  two tabs opened almost identically and a name never says *which screen*
  you're on. The title says where you are, the name stays in Settings where
  it's actually edited, and the header folds from two rows to one so the
  record starts higher. Title + trailing round glass button is the same header
  shape the Settings sheet and the pushed sub-pages use, so the gear and the
  sheet it opens read as one affordance. (This is a hero title, not the
  retired all-caps PROFILE kicker — see the kicker note below.)

  Then the **summary band**: one hero
  numeral and two quiet lines. "Avg sleep · last 7 nights" as a tiny label
  (the scope lives in the label, and counts the nights actually averaged),
  the average duration as the band's single big numeral, and beneath it the
  average bed/wake times as an arrowed window line
  ("11:28 PM → 7:43 AM"). That band is the
  whole dashboard read of the record, above the fold, before any chart.

  The band was previously three labeled numerals (Avg sleep / To bed / Up)
  over a scope-and-streak caption — eight pieces of text in three rows, which
  is a table, and even after earlier declutter passes it kept the top of the
  screen reading as overwhelming. One night's read has one headline: how
  long you slept. The clocks are the supporting fact, and the app already
  has a one-line grammar for a sleep window — the arrowed line the history
  rows draw — so the band borrows it and retires the "To bed"/"Up" labels
  entirely; the arrow says which end is which. The streak doesn't appear on
  Profile at all: it already headlines
  Home and every widget, and repeating it on the very next tab said the same
  thing twice.

  Then the tappable **blocked-apps** glass card
  previewing the locked-app icons (opens the Blocked apps screen for
  changes), and the sleep record (weekly chart, recent nights, an "All
  nights" page once history grows). A gear in the top-right opens Settings;
  the body itself stays a clean identity + record, with no configuration
  mixed in.

  **Profile is deliberately light on section labels.** The screen once ran
  five tracked all-caps kickers — PROFILE, LAST 7 NIGHTS, BLOCKED WHILE YOU
  SLEEP, YOUR SLEEP, RECENT NIGHTS — which is the loudest typographic device
  in the app, repeated down a single scroll until the screen read as noise.
  Two of them named things that named themselves and went first: "PROFILE"
  (at the time, the tab bar said Profile and the name said whose) and "YOUR
  SLEEP" (a
  chart of gold sleep bars under its own date-range caption, on a screen
  whose first block is the sleep average). The screen is titled "Profile"
  again now that the name is gone, but as a **hero title, not a kicker** —
  the objection was never to naming the screen, it was to a fifth piece of
  tracked small-caps competing down the scroll. One editorial title at the
  top is the app's standard chrome; a stack of shouting labels is not.
  "LAST 7 NIGHTS" folded into the
  summary band's label. "BLOCKED WHILE YOU SLEEP" went when the card learned
  to say what it is in every state (see the blocked block below). One
  remains — RECENT NIGHTS — labelling the one thing genuinely ambiguous
  without it: a list of dates that could be anything. The rule: a kicker
  earns its place only when the thing under it can't say what it is.

  The record chart is the **widgets' 7-night bar rhythm brought home** — one
  chart language on every surface. Exactly 7 fixed-width columns, **today
  rightmost** on the newest page: gold→amber capsules (latest full-strength,
  earlier nights
  receding to ~60%) against the quiet target hairline with ~15% headroom —
  the hairline is tagged with the goal itself ("8h", or "7h 45m" when the
  schedule isn't a round hour) on a small navy chip at
  its trailing end, so it reads as *your target* rather than an unlabeled
  rule — every bar's hours on the shared label plane (`BarHoursLabel` — navy inside
  the bar, gold above it, split at the bar's edge; see the widget bar rules),
  weekday initials under every slot (latest in amber). Nights not yet logged
  render as hairline stubs, so a young record honestly reads as a week
  filling in.

  The rightmost column is **today, not the last night logged.** Anchoring to
  the newest night made a missed night invisible: the window simply slid back
  a day, so the record looked identical whether you slept last night or not,
  and only gaps *between* two logged nights ever showed. Today-anchored, a
  missed night is the hairline stub it should be, and the chart agrees with
  the streak instead of contradicting it. The target chip reads in hours and
  minutes because it echoes a setting the user chose — decimal hours turned a
  round 10:45 PM → 6:30 AM schedule into "7.8h", which looks like a
  measurement rather than a decision. Bars keep decimals; a measured night
  genuinely is 8.9h.

  The chart is **swipeable by week.** The record is chunked into pages of
  seven days, boundaries anchored to today and stepping back in 7-day blocks
  (so the current week is always a full column set and older weeks fill in
  behind it). Empty older weeks are skipped, but the newest page is kept even
  when nothing is logged in it — "nothing this week" must read as an empty
  week, not as an older week silently presented as the current one. Laid
  oldest→newest left→right so the newest week shows by default and the user
  swipes right to walk back through history — the same "latest rightmost"
  spatial grammar as a single chart. Below sits an **Instagram-style dot
  indicator**: a fixed-width window of at most seven dots (amber for the
  current week, faint for the rest) that never grows however long the record
  runs — when more weeks are hidden past an edge, the one or two dots on that
  edge taper down to signal "more this way", so 15 weeks reads as cleanly as
  3. The strip doubles as a **scrubber** — press and drag it left/right to
  fast-forward or rewind through weeks (finger travel maps to weeks at a fixed
  step, with a soft tick as each new week lands), so reaching week 3 of 15 is
  one drag rather than fifteen swipes. The system's own page dots are
  suppressed because they clash with the bars and can do none of this. A
  record of seven nights or fewer stays a single plain chart with no pager
  chrome.
  Because the axis carries weekday initials but no dates, every page names its
  span in a faint centered caption — **"Jun 16 – Jun 22"** — and the newest
  page appends **"· N days ago"** once the newest logged night is ≥ 2 calendar
  days back, so a stale record reads as stale at a glance rather than
  masquerading as the current week. The caption names the **window**, not the
  span of nights inside it: a page is always seven days wide, so a lone night
  captioning a full week as a single date ("Jul 24") under-described what the
  columns were showing.

  > Note on history: the record chart was previously a smoothed amber
  > line-with-area. Retired: it clamped every night into a 4.5–9h band (a
  > 1-minute test night drew at the 4.5h floor — dishonest data) and
  > index-spread the logged nights across the full width, so two nights
  > became a flat full-width laser line. The bar rhythm shows sparse
  > records truthfully and matches the widgets.

  The **summary band** is one band, not two. It began as Avg sleep / Streak /
  Nights, then a hairline, a kicker, and To bed / Up beneath — five numerals
  across two rows at two sizes with two label treatments, which read as two
  competing tables rather than one summary and was the biggest single source
  of clutter on the screen. Collapsed to **three numerals sharing one scope,
  one size and one shape**, the block answers "how am I sleeping" in a single
  pass: how long you slept, when you went to bed, when you got up.

  Streak did not earn a hero numeral here. It is an all-time counter sitting
  under a seven-night heading — a scope mismatch inside one band — and it
  already headlines Home and every widget; it lives in the caption instead.
  Total nights logged is gone entirely: the "All N nights" link at the foot of
  the history already carries that number. **One supporting line, not two** —
  the scope and the streak share a single sentence-case caption below the
  numerals, where there used to be an uppercase kicker above them *and* a
  footnote below.

  The stats are 23pt, down from the old band's 26pt, because a clock time is a
  markedly wider string than a duration and three of them have to share the
  row. Labels carry no moon/sun glyphs: "To bed" and "Up" are unambiguous
  words, so the glyphs were decoration in the one block that most needed calm.
  (They have since been dropped from the history rows too — see the Recent
  nights note below. The arrow does the work.)

  The band first sat under the chart, beside the week it summarises, then
  moved above it. Up here "how am I sleeping" is one block above the fold, and
  the chart is left to be a chart rather than a thing with statistics stapled
  beneath.

  **All averages are scoped to the last 7 logged nights**
  (`SleepStats.recentWindow`). This is why Avg sleep is no longer all-time: an
  all-time mean stops moving once the record has any length, so a good week
  can't shift it and a bad one can't either — it stops being a number worth
  checking. Deliberately the last N *nights*, not the last N calendar days:
  for an unbroken record the two are identical, and where they differ (a
  sparse record) averaging the nights that exist beats averaging a window that
  is mostly empty. The caption counts the nights actually averaged ("Last 3
  nights" on a three-night record); captioning three as seven would claim four
  that don't exist.

  Clock averages are **circular means** — angles on a 24-hour dial, not plain
  minute counts. This is the whole ballgame for a bedtime: 11:50 PM and
  12:10 AM average to midnight, but `(1430 + 10) / 2` is 12:00 *noon*. A
  sleep app whose "average bedtime" reads 8 PM because the user sometimes
  crosses midnight is worse than useless. Durations stay a plain mean — they
  are magnitudes, not positions on a dial.

  **Recent nights** is a small-caps kicker (the same section-label grammar
  as everything else) over hairline-divided rows: date + source glyph on the
  left, **the night's window on a second line beneath it** ("11:31 PM →
  8:26 AM"), and the night's duration as the one trailing value in ink. No
  meters, no grades — duration is still the record's headline reading, and the
  window is a supporting fact, not a competing metric.

  **The window line carries no moon or sun.** It used to lead each clock with a
  glyph, on the reasoning that the glyphs were what said which end is which.
  The arrow already says it — a span reads left→right, and the earlier of two
  times either side of a "→" is obviously the bedtime — so the pair was two
  icons per line, four per row, restating the punctuation. Down a seven-row
  list that is the screen's densest chrome, in the line that has a duration to
  share its width with. The glyphs are gone from both places the line is drawn
  (history rows and the summary band's average window); Home's schedule capsule
  keeps its amber pair, where it is a single hero on an otherwise empty screen
  rather than a repeating list item.

  The row's trailing **source glyph** stays: it is `heart.fill` for a night
  imported from Apple Health and `moon.fill` for one logged in the app, so it
  reports where the data came from. That is information, not decoration — the
  distinction the moon/sun pair was failing to earn.

  The window line is `dim` over a soft navy shadow rather than `muted`, for
  the reason `StatBlock`'s label already is: the record scrolls over a living
  scene that runs from night through to a bright daytime sky, and mid-grey
  text vanishes into the day phase.

  > Note on history: rows showed date + duration only for the app's first
  > year, while `SleepSession` had carried `start` and `end` since the first
  > version. The record could tell you *how much* you slept but never *when* —
  > the half a schedule app is actually about. The times were always there;
  > only the row was missing.

  > Note on history: nights previously carried a 0–100 **sleep score** (a
  > duration-vs-target curve) colored gold/ink/danger, with a per-row score
  > meter, an "Avg score" stat, and score heroes on the widgets. The score
  > is retired app-wide: it was a second number derived from the first,
  > dressed as an insight — duration against the target already says
  > everything it said. **Duration is the app's only metric.** "On track"
  > (the streak) now means reaching ≥85% of the sleep target, the same bar
  > the score set at "score ≥ 80", so existing streaks carry over.
  The blocked block is an **interactive glass row** with no kicker over it —
  containers are reserved for tappable controls, and the glass is what says
  "you can press this"; plain floating text read as static copy. Instead of
  an all-caps label announcing it, the card names itself in every state:
  before any apps are chosen it shows a warm lock glyph in a soft circle
  beside one short line ("Choose apps to block" — no explanatory copy; the
  row itself is the invitation); with a selection it previews the app icons
  captioned "Blocked while you sleep" (the retired kicker's sentence, now
  spoken quietly inside the card); with a selection but blocking toggled off
  it shows a muted open lock and "App blocking is off"; on the simulator,
  "Blocking needs a real iPhone". Empty
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
title, supporting line). The body is four kicker-titled `GlassGroup`s —
**Profile** (editable Name: tap → rename alert; read-only account Email, no
chevron, middle-truncated — both live here, never on the Profile body),
**Subscription** (the plan status, see below), **Sleep** (Schedule, Blocked
apps, the Apple Health toggle — no explainer sublines), and **Account** (Sign
out in dim, alone in its group and confirmed by an alert before anything
happens), plus **Feedback** ("Request a feature", and "Rate SleepBlock" once
an App Store id is configured) sitting between
Sleep and Account — it is neither a setting nor a way out. The order reads
*who you are → what you're on → your sleep config → talk to us → account
exits*.

**Request a feature** is a pushed sub-page with the standard chrome (glass
back chevron, editorial title, supporting line). It is the app's only social
surface, and it is kept as quiet as one can be: a composer at the top ("Your
idea", a glass field, a character count, one primary **"Post request"**
button with **no glyph** — the words already say what it does, and a paper
plane was decoration on the one control that needed none), then
"Most wanted" — the board ranked by score. The field **stops accepting text**
at 140 characters rather than letting you overrun and disabling the button:
a field that quietly stops teaches the limit at the moment you meet it, where
a dead button leaves you deleting text to work out why. The counter turns
amber only once you're actually at the ceiling.

The board shows **five requests, then a "Show N more" button** — a button
rather than infinite scroll, because this is a thing you skim and leave, and
a list that grows under your thumb is the opposite of what the app is for.
Cards have a **standard height**: the request clamps to two lines with the
space for both always reserved, so a board of one-liners and paragraphs still
reads as an even stack. Anything longer earns a **"See more"** that expands
it in place (and "See less" to collapse). Whether the text is truly clipped
is measured, not guessed — a short request never grows a pointless
"See more". Each request is a glass card with
the vote control on the *left*, where the eye lands first, because the score
is the point of the board. The control stacks chevron / score / chevron
vertically so the number sits between the arrows and "up raises this" needs
no label, and **only the arrow you chose takes amber** — an unvoted row is
entirely quiet, so a long board never reads as a field of orange. Status
badges appear only for "Planned" and "Shipped"; an ordinary open request
carries no chrome. Under each request sits **who asked and when** — the name
in `dim` because it's the fact worth reading, the age after it in `faint` and
coarse ("now", "4h", "3d") since the board ranks by votes, not recency. Names
are the poster's profile name, snapshotted when they posted; someone with no
name set shows as "Someone". The empty state is the same warm-glyph pattern as the
rest of Profile ("Nothing here yet / Be the first to ask for something") —
never a ghost list of sample requests.

**The update gate** is the app's only blocking screen that isn't a gate you
can pass by acting (unlike the paywall or the Screen Time primer). It wears
the same root-gate chrome as those — night city, scrim, the brand sloth, an
editorial title, one primary button — because it *is* one of them, and a
screen that says "this app is broken" should still look like the app. There
is no dismiss, no "later", no fine print: by the time it shows, this build
genuinely doesn't work, and the only honest affordance is the fix. The reason
line comes from the server so it can name what broke without a release.

It sits **beneath sleep mode** in the root stack — an active night always
keeps wake/cancel and the lockdown teardown reachable, the same precedence
the paywall observes. Waking someone into a wall they can't dismiss, with
their apps still blocked, would be the worst thing this app could do.

The **soft nudge** ("update available") is the opposite register: the same
warm dismissible card as the Health invite, in the same Profile slot, once
per version. A newer build existing is not news worth interrupting anyone
for. There are deliberately no update badges anywhere else — not on the tab
bar, not on the gear, not on Settings rows.

**Asking for a review** is the one interruption the app permits itself, and it
is rationed accordingly: the system prompt appears on **Home**, never at
wake-up (the user is half-awake and starting their day — precisely the moment
this app exists not to intrude on), and only after two nights have actually
been logged. Asking sooner is asking a stranger for a favour. It repeats at
most twice more, a week apart, matching the ceiling iOS enforces anyway. The
Settings row is the path that always works and never interrupts, which makes
it the primary one; the prompt is the rare secondary. There is deliberately
**no "do you like the app?" pre-prompt** — filtering out unhappy users before
showing the rating sheet is against App Store guidelines and is the exact
move that makes review requests feel like a trick.

> **The board is currently switched off, and the screen ships as a
> submit-only suggestion box** (`FeatureRequestFlags.showsPublicBoard`).
> Everything above is built and works; none of it is shown. App Store
> Guideline 1.2 expects an app that *displays* user-generated content to carry
> a way to report objectionable posts, a way to block abusive users, and a
> published contact — and the board has none of those while now attaching real
> names to posts. A form that displays nothing to anyone raises none of it.
> The database side is ready (`status = 'hidden'` already removes a row from
> every client read); the reporting UI is what's missing. Build that, then
> flip the flag.
>
> With the board off, a successful post gets an explicit **"Request sent"**
> confirmation with a quiet "Send another" — the list a new request used to
> appear in isn't there, and a submit that empties a field and says nothing
> reads as a failure, not a success. **Delete account** is not a glass row at
all: it sits beneath the Account group as bare faded text — a rare,
irreversible exit that never competes for attention — and confirming it
requires typing "delete" into the alert before the destructive button
enables. The pixel-art
credit sits quietly at the very bottom. The only other sheet in the app is
Apple's own `FamilyActivityPicker`.

The **Subscription** group answers one question the hard paywall otherwise
leaves hanging once someone's in: *what am I on, and when does it change?* Its
first row is a **status readout, not a control** — so, like the plan reveal's
summary rows, it earns a dim detail line (the one place a settings row explains
rather than only naming): the **brand sloth turned to gold** — the "you're a
subscriber" mark — a tier title (**Free trial** / **SleepBlock Pro** / **Not
subscribed**), and beneath it the renewal fact — "6 days left · renews Jul 20,
2026" on a trial, "Yearly · Renews Jul 20, 2026" once paid (the date carries
the year, since a yearly renewal lands up to twelve months out). The gold-sloth
chip is generated by `scripts/generate-subscription-icon.py` — the lounging
Home sloth (built for 48–120pt) is a smudge at a 30pt chip, so the script crops
to the head and recolors it as a **gold medallion** (luminance → gold ramp,
which keeps the face legible where a flat template tint would flatten it to a
blob). It sits in the same soft tinted rounded square as every other
`GlassRowIcon`, so the row still scans with its siblings; the lapsed (**Not
subscribed**) state falls back to a muted glyph. The **"about to end"** case —
active but set to cancel — colors that detail line **amber** ("Ends Jul 20,
2026 · won't renew"): a calm heads-up, never `danger`, which stays reserved for
real failures (the auth/paywall two-tone rule).
Beneath the status sits one action, **Manage subscription**, which opens the
system-managed App Store sheet — the only sanctioned place to switch plans or
cancel, so the app never builds its own billing UI. The whole group **hides
when there's no status to show** — an unconfigured dev build, or before the
first entitlement fetch resolves — the same "never fake a plan" honesty the
paywall keeps in dev mode; the status is display-only (`SubscriptionStatus`,
read straight off RevenueCat's `EntitlementInfo`) and never touches the gate's
three-state entitlement answer.

The **Blocked apps** page follows the same grammar: a one-line supporting
sentence under the title ("Locked from Sleep Now until you wake. Calls always
work."), then a single `GlassGroup` — a **"Block while you sleep" toggle (on
by default)**, an Apps row (value "None"/"N chosen" → `FamilyActivityPicker`),
and the "Unlock anyway after" safety stepper with its amber hour value. The
chosen apps render below the group as a system-drawn **icon grid** (tokens are
opaque, Apple draws them) — the user sees exactly what locks, without a text
list.

Choosing apps is still the commitment — a fresh selection blocks tonight with
no extra step, because the toggle defaults to on. The toggle exists as the
explicit, visible override: a night the user wants the phone open shouldn't
cost them their selection. Off keeps the apps chosen but blocks nothing (the
profile preview says "Blocking is off", the settings row "Off", and the sleep
confirmation "No apps blocked tonight"), and clearing every app still tears
down the scheduled shield.

> Note on history: a mid-2026 revision removed the toggle entirely ("picking
> apps is the commitment"). That backfired: armed-ness lived in a stored flag
> that doubled as an authorization snapshot, which could go stale (profiles
> from the toggle era, a denied re-authorization) — leaving apps "chosen" on
> the settings page while Sleep Now said "No apps blocked tonight", with no
> control anywhere to fix it. The toggle returned as a real user decision,
> and armed-ness stopped being stored at all.

Screen Time authorization is requested lazily — the first tap on the Apps
row — because the picker is useless without it. It is never persisted:
`SleepStore.willLockDuringSleep` (toggle on *and* live Screen Time
authorization *and* at least one app chosen) is the single source of truth
for "are apps blocked" across Home, the confirmation panel, and the profile
preview.

There is deliberately **no "reset all data" action**. A destructive escape
hatch sitting among everyday settings invites disaster and signals distrust of
the app's own record. Sign out is the only account-level exit, and it keeps
the local profile. Both exits pause for confirmation: Sign out asks with a
plain alert, and Delete account demands the word "delete" typed back — friction
proportional to what each one destroys.

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

Two independent paths from a type-led welcome screen (brand mark, brand
hero, tagline — "Block apps and Log your sleep"; the old "Wind down nightly"
kicker is retired, the mark carries the mood now): a primary "Get started"
and a quiet "I already have an account". The two paths are never linked to
each other — the choice is made here, so neither downstream screen carries
an "already have an account?" cross-link. Someone who picks wrong just backs out to welcome.

The **brand mark** (`SlothBrandMark`, `OnboardingView.swift`) is the app icon
alive in the UI layer: the sleeping sloth — the home art's closed-eye frame,
wearing the scene's current light (`HomeSloth{Day,Dusk,Night}Blink`) over the
same warm halo that seats Home's sloth — with the icon's static gold ZZZ
replaced by the sleep screen's rising-z chain (`RisingZs`, now shared from
`SleepTheme.swift` and parameterized by color and scale: emberDim at full
size on the sleep screen, gold on the mark). It appears in exactly four
places: above the wordmark on the welcome screen, above the "Welcome back"
title on the standalone sign-in screen, small in the questionnaire
header's top-right corner — where it rides the hidden chevron-twin slot, so
the progress bar stays centered and the sign-up flow (including its account
step) stays branded without a second large mark — and atop the paywall,
the questionnaire's closing beat (see "Paywall"). Small marks keep
deliberately oversized z's — like the icon's ZZZ — so the animation stays
legible at corner sizes; under Reduce Motion the chain freezes into the
icon's static diagonal everywhere. The mark is decorative only: hidden from
accessibility, never a tap target.

The two hero placements obey a **geometry contract** (`BrandHeroGeometry`):
the gate *crossfades* welcome and the standalone sign-in screen into each
other, so the mark must land on exactly the same pixel on both — even a few
points of drift reads as the logo twitching or shrinking mid-fade. Both
screens center the same-shaped block (the hero mark, an `lg` gap, a
fixed-height text band) between a chevron-height header row (welcome renders
an invisible twin of sign-in's real chevron) and a fixed-height bottom band
(the provider stack's natural size; welcome bottom-aligns its two smaller
controls inside the same band). Anything that changes one screen's vertical
structure must change both.

> Note on history: the welcome screen was previously deliberately type-led
> with *no* artwork in the UI layer. The brand mark supersedes that — the
> sloth is the identity on every other surface (Home, widgets, sleep screen,
> the icon itself), and the pre-app gate was the one place the brand never
> showed its face.

Sign-up runs the questionnaire *before* asking for an account — people who have
answered a few personal questions complete sign-up at a higher rate — and the
account step is the *final step of that same flow*: it carries the same progress
bar (now full) and back chevron as every other question, framed as saving the
plan they just made. The profile is only committed once that step's auth
succeeds, so "back" from it returns to the plan reveal like any other.

**Signing up with an account you already have** gets its own full screen
(`ExistingAccountWelcomeView`) — hero mark, "You already have an account", one
paragraph, one primary button — on the same scene, outranking every other gate
so neither Main nor the setup questions can answer the question for the user.
It exists because the app *cannot* refuse up front the way the email path
does: Apple's and Google's Supabase grants are find-or-create, so by the time
the app knows the identity was registered, the session exists and the user is
signed in. The screen is therefore a statement, not a choice — there is no
"sign in instead" button, because that is what already happened, and no
"create a separate account", because the grant cannot. What it owes the user
is candour on the two things they will wonder: that their existing plan and
nights are intact, and that the nine answers they just gave were **not** saved
over them. When the account has no profile to restore, the second sentence
says so and promises setup instead — never reassurance the next screen will
contradict. The email path keeps its inline red message ("That email already
has an account…") since it can still fail before any session exists.

The questionnaire is an **investment arc**, not a form: who you are → what
you want → what's in the way → how bad it's gotten → your schedule → the plan
built from all of it. Ten steps: name, goal, sleep struggles, time-sink apps,
late-night phone time, wake feeling, bedtime, wake, **plan reveal**, account.
Every question either personalizes the plan summary/paywall or deepens the
user's stake in finishing; none is padding — the Cal AI-style long onboarding
works because each answer visibly *builds* something, and ten calm editorial
steps is the ceiling for this app's bedside-instrument voice. Apple Health is
deliberately *not* asked here — a system permission sheet mid-sign-up is
friction, and the ask lands better in context.

The two **schedule steps** are single-wheel and framed as the target the app
holds the user to — "When do you want to go to bed?" and "And when do you
want to wake up?" (the wake step carries a live sleep-window readout). That
target is the operative schedule: `profile.bedtime`/`wakeTime`, what the Home
countdown, the lockdown window, and the widgets all key off. (An earlier
revision asked ideal *and* current on each screen to manufacture a gap; it
was cut — the second wheel made the screen busy, and the plan reveal already
carries the motivation.)

Selection grammar splits by meaning: **multi-selects** (struggles, time-sink
apps) allow zero — an empty set is an honest answer — while **single-selects**
(goal, phone time, wake feeling) require a choice before Next enables, because
the plan speaks to the answer and there is no meaningful "skipped" reading.

> Android revision (July 2026): on Android, **every** questionnaire step
> holds Next until the user actually interacts — multi-selects require at
> least one choice, and the schedule wheels require a scroll. A deliberate
> product call (nobody should be able to tap through blank); if it proves
> out, iOS adopts the same rule and the paragraph above changes.
All list questions share one full-width capsule row (`OptionRow`; the
time-sink grid keeps its compact 2-column `TimeSinkChip` sibling).

The **plan reveal** is the questionnaire's closing beat before the account
step: ~1.8s of "Building your sleep plan…" — the brand sloth and status text
centered together in the full flexible region between the progress header and
the reserved bottom action, its rising z's the only motion, deliberately never
a spinner — resolving with a success haptic into a personalized summary in the editorial question chrome:
a `GlassGroup` of three facts (sleep window + nightly duration; **time to win
back each week**, computed from the phone-time answer × 7 and naming the
user's own apps; the stated goal). The build beat is sticky — backing in from
the account step shows the summary instantly; the pause is a first-arrival
moment, not a toll. Its CTA is **"I'm ready"** — the flow's one
micro-commitment, landing right before the account step asks to save the plan
and the paywall asks to unlock it. The summary rows are a data readout, not
settings rows, so they may carry a dim detail line (the one exception to
"rows never explain").

The **time-sink question** ("Which apps keep you up?") is the struggles
question pointed at the phone itself: eight usual suspects (Instagram,
TikTok, YouTube, X, Reddit, Snapchat, Streaming, Games) as a 2-column grid of
the same glass capsules — short app names fit two per row, and eight
full-width rows would overflow the screen — with the identical selection
grammar (constant glass tint, amber ring + icon + filled circle when chosen).
It asks for *names*, never the system `FamilyActivityPicker`: a Screen Time
permission sheet mid-sign-up is the same friction the Health rule exists to
avoid. The answers feed the paywall's lock line and later personalization;
the real lockdown selection still happens on the Blocked apps screen. Instead a warm, dismissable
glass card on Profile (`HealthConnectCard`) invites the connection where the
sleep data actually lives; it persists until connected or waved off, and the
Profile settings section still has the toggle.

Questionnaire chrome: a 3pt amber-gradient progress capsule between a round
glass back chevron and a hidden twin of it (so the bar stays centered at
whatever size the system draws the button — the twin's slot carries the small
brand mark, per above), editorial left-aligned questions
(28pt title → dim supporting line → control). The prompt is top-anchored 32pt
below the progress header so every step begins at one stable reading position;
the answer controls are independently centered in the remaining space between
that prompt and the bottom action, matching Cal AI's top-question / centered-
answer rhythm without borrowing its visual identity. The centering spacers
collapse for tall answer groups and compact screens. The bottom action remains
pinned to the safe-area band, independent of question height. Steps use
directional slide+fade step transitions (~280ms). Multi-select answers use
full-width capsule glass rows — muted icon, ink label, trailing circle that
fills amber when selected. No text "Back" buttons; the chevron is the only way
back. The sign-in screen ("Welcome back") is a single standalone screen with
the same chevron (back to welcome) and provider layout, so both paths read as
one system.

Text fields over the scene get real surfaces. The email form's two fields are
**glass field rows** (continuous rounded rects sharing one
`LiquidGlassContainer`), never bare hairline-underlined fields — the form sits
over the busiest band of the skyline, where a 6% underline and a default
placeholder simply vanish. Prompts use `quiet`, entered text is ink, and focus
is an amber ring (a stroke that carries *meaning*, per the glass rules). The
name question keeps its editorial underline — it's a lone hero field with the
keyboard up — but the idle rule is `faint`, not `hairline`, and its prompt is
`quiet` for the same reason.

Every onboarding/auth screen with a back chevron also honors a **left-edge
swipe back**. These flows are custom ZStack transitions, not a
`NavigationStack`, so the system pop gesture doesn't exist and the swipe is
hand-wired (`swipeBack` in `OnboardingView.swift`): a trigger, not a tracked
pop — releasing past the threshold runs the same slide the chevron runs. With
the email form open, the swipe unwinds to the provider stack first, then to
wherever the chevron leads. A swipe is a non-button cue, so it taps `soft`,
never the button knock.

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
A returning user on a *fresh install* also skips the questionnaire: their
profile is restored from the account's cloud copy during sign-in, so the
quick-setup questions only ever appear when there is genuinely nothing to
restore.

Auth messages above the provider stack come in two tones: failures ("that
password isn't right") in `danger` red, and guidance about a normal next step
("tap the confirmation link we emailed you") in `amber` — a calm nudge, not an
alarm. Never style an expected step as an error.

## Paywall

SleepBlock is a subscription app, and the paywall (`PaywallView.swift`) is
the questionnaire's closing beat: it appears once, between the account step
and Main, on the same living scene as onboarding. It is deliberately a
**hard paywall** — no ✕, no "not now" — softened by honesty: the primary
action starts the App Store free trial, so nobody pays blind, and the
renewal line under the button states the real price and "cancel anytime" in
quiet type. It only ever renders off a *resolved* not-entitled answer
(never a loading guess), and an unconfigured dev build never shows it.

The screen is deliberately spare: a hard paywall earns its keep by asking
one question, not by pitching. The hero is the brand mark over a small
tracked small-caps **"SLEEPBLOCK"** signature — the two form one brand
lockup, the wordmark deliberately quiet (label weight, `dim`, letter-
spaced) so it reads as the app's own kicker grammar and never competes
with the headline; when it matched the headline's size and weight the two
read as twin headlines with no hierarchy. Beneath the lockup sits **one
headline and nothing else** — no other kicker, no subtitle, no feature
list — set as the screen's hero (semibold, `ink`, the largest type on the
screen). That headline answers
*the plan currently selected* rather than narrating features: the trial
plan reads "Start your 7-nights FREE trial to continue," the no-trial plan
reads "Unlock SleepBlock to build a sleep routine that sticks." Switching
the plan card crossfades the headline, so the copy always matches the
button the user is about to press (the Cal AI paywall does the same swap
between its trial and no-trial screens). The whole hero (mark + wordmark +
headline) floats between two flexible spacers so it sits in the upper
third rather than jammed under the status bar, while the same lower spacer
keeps the plan cards and CTA anchored low — cardless space, not a wall of
copy, carries the gap on any device height.

> Note on history: the paywall previously opened with a "Your plan" kicker,
> a fixed "Lock your nights in" headline, a two-line subtitle personalizing
> the user's chosen apps, and — before that — three glyph-led feature
> lines. Each was retired in turn: the feature lines repeated the plan
> cards, the fixed headline repeated across both plans regardless of which
> was selected, and the personalized subtitle was the last static line
> once the headline itself started doing that job dynamically.

The two plan cards are interactive glass rounded-rects in one
`LiquidGlassContainer`, each carrying **one price fact**: the annual card's
trailing price is its monthly equivalent over a quiet "billed annually"
subline naming the full price; the monthly card is a single row, title and
price. Both prices read "…/mo", and the monthly equivalent comes from the
product's own price formatter so the two cards can never mix currency
styles. The annual card's own title states the deal instead of naming the
period — "Start for free & save 17%" (or "Save 17%" once the trial ends) —
computed from the two fetched plans' real prices (`SleepPlan.priceValue`,
arithmetic-only, never displayed) so the percentage always tracks whatever
RevenueCat actually returns; the monthly card keeps its plain "Monthly"
title. The trial is not card text — it rides the annual card's top edge as
an amber capsule **badge** ("7 NIGHTS FREE", the primary button's
amber-on-navy colors). Selection keeps the onboarding grammar (constant
tint, amber ring + filled trailing circle), the unselected card dims to
~55% so the chosen plan reads first, and annual is preselected. The CTA is
the standard `LiquidPrimaryButton` ("Start 7 nights free", derived from the
product's real intro offer), the renewal line beneath it restates the
selected plan's real terms in quiet type, and the footer is three quiet
text links (Restore purchases · Terms · Privacy) over a soft navy floor
gradient. Failures and notices reuse the auth screen's two-tone rule:
`danger` for real failures, `amber` for normal next steps ("No subscription
to restore on this Apple ID."). Loading and offline states stay composed —
spinner with a quiet line, or a wifi-slash glyph row with a glass "Try
again" — never a broken sheet.

One structural rule: the sleep-mode overlay always outranks the paywall.
An active night keeps *Hold to wake* / cancel — and with them the Screen
Time shield teardown — reachable no matter what the subscription state
resolves to. The app never traps a user inside a lockdown behind a
purchase screen.

## Screen Time primer

The last gate before Main (`ScreenTimePrimerView`, SleepScreenTime.swift),
after the paywall resolves: SleepBlock is an app-blocking app, and this is
where blocking gets its teeth — asked at peak commitment, right after the
user paid, never mid-sign-up (the Health rule). The centerpiece is a
**mock of the iOS permission dialog** with an amber arrow and "Tap Continue"
beneath its affirmative button — the primer pattern: the user decides to tap
Continue on *our* screen, so the real system sheet (fired by the primary
"Turn on app blocking" CTA) is a formality they've already rehearsed.

The mock is deliberately **not Liquid Glass** — it depicts iOS chrome, not
one of the app's own controls — a plain navy rounded-rect alert with an
hourglass glyph, the real request title, greeked body lines (rounded bars,
never fake legalese), and a Continue / Don't Allow button row. iOS makes
"Don't Allow" the highlighted default, so the affirmative "Continue" sits on
the **left** (grey) and the mock keeps the **system's blue** on the
right-hand "Don't Allow" — the amber arrow points to Continue. The primer's
whole job is pattern-matching against the sheet iOS is about to show, and
that blue is the one sanctioned exception to the no-blue-identity rule. The mock is decorative and hidden
from accessibility; the editorial headline above it ("Let SleepBlock put
your apps to sleep", with a one-line explainer ending in "Calls always
work.") carries the meaning. The arrow breathes a few points vertically
(stilled under Reduce Motion) — a guide, not a decoration.

Granting flows straight into the system `FamilyActivityPicker` while the
intent is hot — authorization alone shields nothing. The primer is
**one-shot per install, never per account**: its seen-marker lives in the
app container (wiped by deletion), so a delete-and-reinstall sign-in —
which silently drops the Screen Time authorization along with the app —
primes again, while normal launches never re-show it. It completes on
grant, deny, *or* the quiet "Not now": nobody gets trapped at a gate, and
the Blocked apps screen stays the always-available fixup path. On the
simulator Family Controls reports unavailable and the gate never fires;
the DEBUG launch argument `-review-screentime-primer` renders it
deterministically (same pattern as `-review-paywall`).

## Motion

State changes fade/lift over ~260–320ms; presses scale subtly (~0.98). Nothing
bouncy or reward-like — but haptics (`Haptics`) are deliberately **strong**:
every button in the app fires a single `heavy` knock on tap, no exceptions.
The knock is wired centrally into the shared components (`GlassIconButton`,
`LiquidPrimaryButton`, `LiquidSecondaryButton`) so call sites can't forget it,
and added by hand on raw buttons, alert buttons, toggles, steppers, and
NavigationLink rows (which are buttons to the finger). `soft` survives only
for non-button cues — a drag released short of its threshold, the sleep
screen's tap-anywhere reveal, the onboarding/auth edge-swipe back — and a
success notification still marks a night logged. The night's two commitment gestures remain the richest haptics: the
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

Widgets live in `SulavSleepWidget.swift`. The organizing idea: **the sloth is
the state, on every surface.** The app's mascot does on the home screen
exactly what it does in the app — awake through the day, heavy-lidded once
bedtime is within ~90 minutes or just past (the same drowsy lead as Home's
sloth), ember-lit on OLED black while asleep — so every widget is
recognizably SleepBlock at a glance *without a logo badge*, and the figure
carries real state the whole time. One sloth per widget, never two.

The surfaces split one job:

- **Small (home screen) — tonight.** A bedtime instrument, not a stats tile:
  text block top-leading (moon glyph + a "BEDTIME IN" / "PAST BEDTIME" caps
  kicker, then the **countdown as the hero numerals**, and nothing else), the
  sloth lounging bottom-trailing with its eyes matching the hour. The
  countdown is the whole instrument because the bedtime is a setting the user
  already knows, while "how long have I got" is what a glance is actually
  asking. Past bedtime it counts *up* in amber and the sloth goes drowsy —
  the same turn-around Home makes, rather than the wordless "Wind down" of
  earlier revisions.
  Small is tonight-only: the quiet last-night line of earlier revisions is
  retired — the record lives on medium/large, and the sloth earns the room.
- **Medium — the morning glance.** Last night's duration as the hero
  numeral under a moon-glyph "SLEEP" kicker, and the 7-night bar rhythm on
  the right. Along the bottom runs a band reading left→right as **figure,
  instrument, action**: the sloth anchoring the corner, the bedtime countdown
  centred where the eye crosses between them, and the Sleep Now capsule
  closing it. The countdown earns the middle because it is the only live
  thing on an otherwise retrospective tile.
  Deliberately no "Last night" label: the hero *is* last night. And
  deliberately **no streak or average line** — medium was carrying six things
  at once and the streak was the least load-bearing of them; dropping it lets
  the hero and the chart breathe. The streak still shows on large.
- **Large — the record + tonight.** The moon-glyph "SLEEP" header with the
  streak on its trailing side (**flame glyph + the bare count**, no "on
  track" — a flame beside a number already reads as a streak, and the words
  were the longest string in the header for the least information; the
  spelled-out phrasing survives as the VoiceOver label), then last night's
  duration as a hero numeral tagged "LAST NIGHT", tall full-width bars with
  weekday initials and in-bar hour labels, then a hairline and a **mini-Home
  footer** anchored to the bottom edge: the sloth as tonight's figure, the
  tonight block, and the Sleep Now capsule on the trailing side — the same
  figure→instrument→action order medium reads in. The block is **label over
  numerals**, matching medium's countdown so the two tiles read alike: a
  quiet "Bedtime in" (or "Past bedtime") with the interval on its own line
  beneath, ink before bedtime and amber after. As one running line the label
  and the value fought for a width the footer doesn't have — the sloth and
  the capsule take theirs first — and the figure truncated mid-glyph; split,
  the interval owns a line and can be larger than it was when it had to
  share. Text only, no moon glyphs; the sloth *is* the glyph. Past bedtime
  now leads with the label rather than the shield's number-first phrasing:
  one shape per slot beats one phrasing per app when the two states swap in
  place.
  Large previously opened straight onto the bars, on the reasoning that the
  rightmost full-strength bar *was* last night so a numeral would repeat it.
  Anchoring the grid to today broke that — the last column is empty whenever
  last night wasn't logged — and it left the top-left of the biggest widget
  carrying nothing but an 11pt kicker. Large should be a superset of medium,
  not a differently-shaped peer.
- **Asleep, every family sleeps.** While a session runs, small, medium, and
  large all wear the same *sleep face*: OLED black, the ember night sloth,
  the "ASLEEP" kicker, the system-driven elapsed timer, the "since" time,
  and a sunrise-glyph wake target (medium/large) — `SleepModeView` shrunk
  onto the home screen. The Sleep Now capsule and the stats disappear with
  the light: when the phone goes down for the night the widgets go dark with
  it, and the numbers return in the morning. Small and medium set the
  instrument beside the figure; large centers the figure like the sleep
  screen itself. The sloth carries the sleep screen's ZZZ, **stepping
  instead of drifting** (`SlothZzz`): WidgetKit renders static snapshots —
  nothing may animate — so the asleep timeline supplies minute entries and
  the ember chain grows one z per minute (each further up the diagonal,
  swelling and dimming like the app's), then starts over; iOS cross-fades
  each flip. Every glance can catch a different frame, so the widget reads
  as breathing without ever animating.
  Large's elapsed timer is explicitly **centre-aligned**
  (`multilineTextAlignment`), not merely placed in a centred stack. A
  `Text(_, style: .timer)` reserves the width of the widest value it will ever
  show and lays its digits out leading inside that reservation, so on the one
  family whose whole face is centred on the sloth the time visibly hung to the
  left of the kicker above it and the since/wake line below. A centred frame
  can't fix that — the reservation *is* the Text's width. Small and medium set
  the instrument beside the figure and stay leading, where the reservation
  never shows.
- **Lock-screen accessories** (circular / rectangular / inline) render in the
  system's vibrant material at tiny sizes, so they use default foregrounds
  and SF symbols — no app palette, no sloth (at 20pt the figure would blur
  into mush). Circular is a duration-vs-target gauge with last night's hours
  in the middle (or a moon when asleep / no data); rectangular and inline
  lead with tonight's state — "Bedtime" over "in 1h 44m", "Bed in 1h 44m".
- The **Live Activity** lock-screen banner leads with the ember night sloth
  beside the elapsed timer, so the lock screen is recognizably SleepBlock
  before a single word is read; the Dynamic Island stays SF-symbol-led at
  its tiny sizes.

Rules:

- The widget extension ships its own lean asset catalog
  (`SulavSleepWidget/WidgetAssets.xcassets`) holding just the three sloth
  poses, downscaled from the app's imagesets by
  `scripts/generate-widget-assets.py` — run it after
  `generate-app-icon.py` so the two catalogs never drift. The app's full
  catalog (pixel city and all) never compiles into the appex.
- Background is the *minimal night gradient* — `skyTop → background` with a
  ~10% amber floor glow that doubles as the lamp the sloth lounges under. No
  pixel-art scene in widgets: at widget size the skyline reads as noise and
  fights legibility, and the flat gradient survives iOS dark/tinted
  home-screen rendering. Key glyphs and numerals are marked
  `widgetAccentable` for tinted mode; the sloth renders desaturated on iOS
  18+ (`widgetAccentedRenderingMode(.desaturated)`) so it reads as a quiet
  figure instead of fighting the user's tint.
- **Tinted and Clear home screens are a second colour system, not a filter.**
  In `.accented` rendering iOS discards our colours entirely and paints two
  flat groups: whatever is marked `widgetAccentable()` in the tint's bright
  colour, everything else dimmed. Two consequences the app got wrong and now
  handles by branching on `\.widgetRenderingMode`:
  - **Never mark a filled shape and its own label accentable together.** They
    collapse to one flat colour and the label disappears. The Sleep Now capsule
    did exactly this — `widgetAccentable()` sat on the whole `Link`, so on a
    tinted home screen the button rendered as a blank pill. Now only the label
    joins the accent group, and the fill becomes a low-alpha wash plus a
    hairline border: **alpha survives accenting**, so the shape still reads as
    pressable while the bright label sits legibly on it. Full colour keeps the
    amber→gold gradient with deep-navy ink.
  - **A label that straddles an accentable fill loses its inside half.** The
    bar hour figures split navy-inside / gold-above at the bar's edge
    (`BarHoursLabel`), which needs the bar to be amber; flattened to one tint
    the inside half stops reading at 9pt. In accented mode the whole figure
    lifts clear of the bar instead — one colour, on the background, left out of
    the accent group so it renders in the dimmer plane while the bar keeps the
    tint.

  The general rule: **in accented mode, contrast can only come from group
  membership and alpha.** Any legibility that depends on one of our hues
  against another of our hues is gone, so design the accented branch as
  bright-on-dim, never dark-on-light.
- Duration is the only metric on every surface — the retired 0–100 score
  (see the Profile section's history note) never appears on a widget.
- Countdowns read **"35m" / "1h 44m" / "8h"**, rendered statically from the
  timeline entry's date, on *every* family including the lock-screen
  accessories. `Text(_, style: .relative)` looks like the obvious choice and
  self-updates, but under an hour it spells out seconds — "35 min, 32 sec" —
  which is too long for a hero numeral and visibly churns. The provider emits
  one entry a minute instead, which also lands every state flip (drowsy,
  bedtime, midnight's column shift, wake) within a minute for free.
- **The bedtime clock time appears on no widget.** Small, large, and the
  accessories all used to print it under (or beside) the countdown. It is a
  setting the user chose and it does not move; carrying it next to the one
  figure that *does* move meant every tonight block was two numerals deep
  where one would do. Only the interval survives. The clock time still shows
  where it's editable — Home and Schedule — and asleep surfaces keep their
  "since" and "wake" times, which are facts about the night, not the setting.
- Bars: **the same chart as Profile's, at widget size** — one grammar, one
  implementation shape, so the two can't drift. Gold→amber capsules against a
  faint target hairline tagged with the goal on a navy chip; the newest
  *logged* night is full-strength and earlier nights recede to ~60% so "last
  night" reads first. Note *logged*, not last column: the grid is anchored to
  today, so the final column is empty whenever last night wasn't logged, and
  keying the emphasis to it would dim every bar.
  The chart lays out **exactly 7 fixed-width columns on a date grid**, today
  rightmost, each night in the column for the day it belongs to
  (`SleepDay.key` — the day you woke up, shared by both targets). Days with no
  night render as the empty state's quiet hairline stubs, and weekday initials
  sit under *every* slot including the empty ones.
  Two things Profile's chart carries that the widget drops, because a 158pt
  tile is not a scrollable screen: the target line goes **bare, no goal chip**
  (the chip is wider than a widget column and lands on the very bars it is
  measuring), and **medium drops the hour figures** on the bars — at ~20pt
  columns they read as speckle, and the hero numeral beside the chart already
  gives last night. Medium's bars are a *rhythm*; large has room to be both.
  Earlier revisions right-packed the nights and lead-padded with blanks, which
  meant a skipped night left no gap — the bars just slid over, so a week with
  Tuesday missing looked identical to a week that began on Wednesday, and a
  missed *last* night was invisible entirely. The vertical scale carries ~15% headroom above
  the tallest value (usually the target), so the target hairline reads as a
  reference line *inside* the chart rather than a stray rule flush against
  its top edge.
  **Every bar carries its hours, on one shared horizontal plane** just above
  the chart floor (`BarHoursLabel` in `SleepTheme.swift`, shared with the
  Profile record chart): "7.5h" on the large widget, whole-number "7" in the
  medium widget's narrower columns. The bar either swallows the number,
  misses it, or catches it mid-glyph — and the number's color splits exactly
  at the bar's top edge, navy ink inside the amber bar, gold above it on the
  night, via two complementary masks. No fit-threshold guessing, and a short
  night never loses its figure.
- Honest data only. A placed widget with no history shows "Log a night" /
  "Set a schedule" — never fake numbers. The one exception is the
  widget-gallery preview (`context.isPreview`), which shows sample content so
  the gallery isn't a blank tile.
- One action only: the **action capsule** on medium/large (primary-button
  style — amber→gold gradient, navy ink). Signed in it reads "Sleep Now"
  (moon glyph) and rides the `sleepblock://sleep` deep link — which opens
  the app on **Home's slide-to-sleep confirmation**, never starts the
  session: no surface anywhere lets a single tap begin a night; the slide
  gesture stays the only way in. Signed out, the capsule reads "Sign in"
  (person glyph, `sleepblock://signin`) and simply opens the app on the
  welcome screen — a widget must never offer an action the app would refuse.
  The capsule disappears while asleep, along with everything else the sleep
  face doesn't carry. The widget *body* carries no `widgetURL` — a stray tap
  just opens the app.
- Timers and countdowns use system-driven `Text(_, style:)` so they tick
  without timeline churn; timeline entries exist only to flip states at the
  drowsy (bedtime − 90 min), bedtime, and wake boundaries.

## App icon

A sleeping sloth on a pillow (recolored stock vector — see `CREDITS.md`),
remapped from its original purple-cartoon palette into Warm Pixel Night: the
sloth in amber/ember with warm-cream face and deep-brown eye patches, gold
ZZZ, the pillow in cool ink so the warm figure reads against it, all over the
widgets' `skyTop → background` night gradient with a faint amber lamp glow
behind the figure — the same "warm indoor light against a cold night" story
as the app. Outlines are near-black navy, not the source purple; no purple
survives.

The icon ships in three appearances (light, dark, tinted). The night art *is*
the dark appearance, so light and dark share one image; tinted is its
grayscale render. All three are generated — never hand-edited — by
`scripts/generate-app-icon.py` from the source EPS, so palette changes can be
re-applied by re-running the script.

The **launch screen** (`SplashScreen.storyboard`) is the quietest possible
version of the same story: the icon's sloth-on-pillow figure — the icon
colorway on a transparent background (`SplashSloth.imageset`, emitted by
`scripts/generate-app-icon.py` so it can never drift from the shipped icon
art) — sitting flush on the flat `background` navy. No rounded icon
rectangle, no wordmark, no scene, no halo. A launch storyboard is a static
snapshot, so the moment the app takes over, `LaunchSplashView`
(RootView.swift) redraws the pixel-identical frame — same asset, same size,
same full-screen center — and the *only* thing that changes is the gold
rising z's (`RisingZs`) starting over the still art: their slow fade-in is
the reveal, and anything else appearing at handoff (even the brand halo)
reads as a second splash screen. The splash holds for a beat (~1.5s past
auth readiness) so the first z is actually seen before the crossfade to
welcome or Home. An active sleep session skips the hold — the sleep screen
always takes the display immediately.

## Shield overlay

The Screen Time shield (`ShieldConfigProvider.swift`, the
`SulavSleepShieldConfig` extension) is what a blocked app shows when the user
tries to open it during the blocking window — the one brand surface the user
meets at their weakest moment, so it speaks in the app's own voice, not
Apple's gray card. The system renders the shield itself from a static
`ShieldConfiguration`; the only expressive slot is the icon, so the icon *is*
the brand mark: the night sloth on its warm amber halo with the gold rising-z
chain alive above it, `RisingZs`' full 7.5-second cycle baked frame-by-frame
into an animated `UIImage` (the extension can't run SwiftUI — it pre-renders
~38 frames of the same keyframes at build-the-config time). The mark breathes
on the shield exactly like it does on the welcome screen.

### Two-phase blocking

Blocking starts automatically at the user's scheduled bedtime, **not** when
they tap Sleep Now. The `DeviceActivityMonitor` extension applies the shield
at interval start and writes a `LockdownPhase` to the App Group defaults, so
the shield extensions render the right copy:

**Pre-sleep phase** (bedtime arrives → user hasn't started a session):
- Title: "Time for bed"
- Title: **"18 minutes past bedtime"** — the lateness takes the bold slot, and
  "Time for bed" steps down to the subtitle. `ShieldConfiguration.Label`
  carries a string and a colour and nothing else, so a phrase *inside* the
  subtitle cannot be emphasised; putting the number in the title is the only
  way to give it weight. It earns that weight — it is the one thing on the
  screen the user doesn't already know, and the only part that changes as the
  night runs on.
- Subtitle: **"Time for bed."** One short line. Nothing else belongs here: the
  user is looking at a block screen, so saying the app is blocked spends
  wrapped lines restating what they can see, and the buttons already state the
  options.
- In the first minute, and before any lockdown has been scheduled (bedtime
  isn't in the App Group yet), the shield keeps its original pairing — title
  "Time for bed", subtitle "Put your phone down and head to bed." A bold
  "0 minutes past bedtime" is a worse sentence than the one it replaces.
- Primary button: **"Sleep Now"** (amber) — closes the shield and fires a
  local notification with the `sleepblock://sleep` deep link. Tapping the
  notification opens the app on the sleep confirmation panel. (The Shield
  Action API cannot directly launch the host app; the notification is the
  bridge.)
- Secondary button: **"5 more minutes"** (dim) — lifts the block for five
  minutes. Twice a night, then the button disappears.

**Active sleep phase** (user tapped Sleep Now, session running):
- Title: "Time to sleep"
- Subtitle: "This app is asleep until you wake. Head back to bed."
- Primary button: **"Good night"** (amber) — dismisses the shield.
- No secondary button.

### The snooze

`ShieldConfiguration` has exactly two button slots, so the escape hatch had to
displace something. It took the **secondary** slot, which previously held an
"OK" that only closed the shield — a dead control in the scarcer half of the
UI. It stays in the quiet slot deliberately: a shield whose loudest button is
"not yet" argues against itself, so amber keeps saying *Sleep Now* and the way
out is plain text underneath.

It exists **only in the pre-sleep phase**. Snoozing out of a session the user
deliberately started would make lockdown mean nothing, and `lockdownMaxHours`
is already the sanctioned exit from one. That boundary is what makes offering
a snooze before sleep safe rather than corrosive.

**Two per night, then gone.** Uncapped, "5 more minutes" is an off switch with
extra steps; the point is that it runs out. The allowance resets at the
lockdown window's interval start, which lines up exactly with the night —
including one crossing midnight — with no date arithmetic. Once spent, the
secondary label is dropped entirely rather than degrading to a dead "OK": the
active-phase shield already ships one button, so a single button is
established grammar here.

When `startSleep()` calls `startLockdown()`, the phase flips from `presleep`
to `active`. The next time the shield renders, it picks up the new phase and
shows the firm lockdown copy. At wake time (or max-hours cap), the monitor
clears both the shield and the phase.

### Shared state

The phase is communicated via App Group UserDefaults (`sulav.lock.phase`),
readable by all four targets (main app, monitor, shield config, shield
action). The shield extensions hardcode the App Group name and key because
they don't include `SleepLockdownShared.swift` in their target — keeping the
jetsam-constrained shield process lean.

The extension can't see the app's asset catalog, so it bundles its own
downsized copy of the night sloth (`ShieldSloth.png`, 480px, from
`HomeSlothNightBlink`). Frame budget stays modest on purpose: shield config
extensions live under a tight memory ceiling, and a killed extension falls
back to Apple's generic shield — the exact thing this exists to replace. The
mark always wears night light (never day/dusk): the shield only appears
during the blocking window.

## What to avoid

- Purple, neon, cyberpunk or blue-heavy identity.
- Generic wellness card stacks; bright white screens.
- Pixel icons inside the UI (pixel art is for the environment only).
- Decorative motion that doesn't support the sleep state.
- Long educational copy or tiny tap targets in the nighttime flow.
