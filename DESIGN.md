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

  Under the sloth, one small glass capsule states tonight's
  window as the single fact it is — moon + bedtime → sun + wake — rather
  than two disconnected chips. Tapping it opens the schedule editor as a
  sheet (the same page Settings pushes). **While tonight's block is running
  it goes read-only** — still the caption to the countdown, no longer a door
  — because the window behind the shield can't move mid-night; see
  *The lockdown settings close with the lockdown*. The Sleep Now capsule anchors low where a thumb rests — a touch
  lower than the free space alone would put it, deeper into reach — with
  last night as one quiet centered strip *beneath* it (`Last night 7h 30m`,
  duration only). Under the button, not above: the recap is the footnote to
  the action, never a step on the way to it. The strip only appears when the
  newest night can honestly be called "last night" — it ended this morning
  or yesterday; older records are stale and never wear that label. With no
  history (or only stale history) the strip renders nothing at all — no
  hairline, no empty-state copy; the pixel scene carries the space. (Same
  recency gate feeds the widget's morning glance, so it never shows
  weeks-old hours as last night's.)

  The top corners hold Home's only two chips, a **balanced pair** in the
  empty band beside the greeting: the **streak** top-left (glass capsule,
  flame + bare count, tap → Profile where the record lives) and the
  **sleep-partners** button top-right (glass circle, `person.2`, tap → the
  partners sheet). Your run on one side, your people on the other — both
  44pt glass so the top edge reads as one row, and both are *status at the
  edges*: the flame used to ride the last-night strip, which crowded the
  center column with a third fact.

  **The streak chip shows zero.** Hiding it would be the honest-data
  reflex, but a `0` sitting where a number is meant to grow is the one
  thing on Home that asks for tonight — the invitation is worth more than
  the empty corner. It just never *celebrates* nothing: zero wears the same
  **hollow muted flame** as a dying run, so only a live streak earns the
  filled gold. One glyph throughout, and the fill is the only thing that
  moves. (The partner button still hides in dev mode.)
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

  The **source glyph** beside the date marks *only* the exception: a
  `heart.fill` when the night came from Apple Health, and nothing at all when
  it was logged in the app. It used to be a moon in that second case, which
  meant a glyph on essentially every row of the list — a mark that never
  varies reports nothing, and seven of them down a column is the same
  repeating chrome the window line's moon/sun pair was cut for. Reserved for
  the minority case it is information: this night came from somewhere else.

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
  > everything it said. **Duration is the app's only metric.** The streak
  > briefly inherited the score's bar (≥85% of the sleep target, the same
  > line as "score ≥ 80"); it no longer does — see [The streak](#the-streak),
  > where the flame measures showing up and duration is left to the surfaces
  > that already carry it.
  The blocked block is an **interactive glass row** with no kicker over it —
  containers are reserved for tappable controls, and the glass is what says
  "you can press this"; plain floating text read as static copy. Instead of
  an all-caps label announcing it, the card names itself in every state:
  before any apps are chosen it shows a warm lock glyph in a soft circle
  beside one short line ("Choose apps to block" — no explanatory copy; the
  row itself is the invitation); with a selection it previews the icons —
  **apps and categories both**, since categories carry system icons too —
  captioned "Blocked while you sleep" (the retired kicker's sentence, now
  spoken quietly inside the card); with a selection but blocking toggled off
  it shows a muted open lock and "App blocking is off"; on the simulator,
  "Blocking needs a real iPhone". **While tonight's block is actually
  running** — a session, or the pre-sleep shield — the card keeps the icons
  (what's blocked is the reassurance it exists for) but stops being a door:
  the chevron becomes a small lock, the interactive glass goes flat, there is
  no push, and the caption reads "Locked until morning". Editing the lockdown
  from inside the lockdown was the way out of it; the settings close for as
  long as the lock holds, and the line names when they open rather than what
  is forbidden. Empty
  states across Profile use that same glyph-row pattern (the sleep record
  opens with a moon-and-stars glyph and "No nights yet / Your record starts
  tonight.") — composed and warm, but never ghost charts or sample numbers:
  honest data only.

  **Count apps and categories separately, everywhere** (`SleepScreenTime`'s
  `selectionCaption`/`selectionSummary`, shared so the two surfaces can't
  drift): a category is a whole shelf of apps the user never has to
  enumerate, so folding it into one total made "block all of Social" read as
  "1 chosen" — the same words as picking one app. The preview card previously
  went further and left categories out of the icon row entirely, standing in
  a bare **"+more"** for them; a category-only selection — the first thing
  the system picker offers — therefore rendered as the word "+more" beside
  nothing at all. Categories are drawn now, so "+more" is gone: overflow past
  six icons is a real count (`+3`), and the caption names a category
  selection outright ("1 category blocked while you sleep"). With apps alone
  the caption stays the plain sentence — the icons already say which apps,
  and a count would only restate them.

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
**Subscription** (the plan status, see below), **Sleep** (Schedule and Blocked
apps — both chevron-less and untappable while the block is running, reading
"Locked until morning", the same shape an unavailable Apple Health row takes —
and the Apple Health toggle, no explainer sublines), and **Account** (Sign
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

The **Subscription** group answers one question the paywall otherwise
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
by default)**, an Apps row (value "None" / "3 apps" / "1 category" / "3 apps,
1 category" → `FamilyActivityPicker`), and the Hard mode toggle. There is
deliberately **no "unlock anyway after N hours" stepper** — see
[The block ends with the session](#the-block-ends-with-the-session). The
selection renders below the group as a system-drawn **icon grid** (tokens are opaque, Apple draws them) — the user
sees exactly what locks, without a text list.

#### The lockdown settings close with the lockdown

**Every surface that governs the block closes while the block is running** —
this page, Sleep schedule, and the reasons — for a session or for the pre-sleep
shield alike. No route pushes: the Profile card, both Settings rows, Home's
schedule capsule, and Home's morning-mirror line all stop opening. If a page is
already open when the shield comes up, its controls are replaced by one shared
panel — a lock glyph, "Locked until morning", and a sentence of why — and the
system picker, if it is up, comes down with it. Each page's supporting line
under the title changes to say the night is running.

The controls are *removed*, not greyed out: a disabled toggle is still an
invitation to keep trying, and none of these has a legitimate use before
morning. The shared line names **when it opens again** rather than what is
forbidden — the answer to "why can't I tap this" is a time, not a rule.

Only this page was ever an escape (the toggle plus an emptied picker were a
two-tap way out of the night, the same principle as the retired hours stepper).
The schedule joins it for honesty — its edits are held until the window closes,
so a save that looked like it worked was a lie — and the reasons because they
are the block's whole argument at 1am, and the self that wants them deleted is
the one they were written for. Changes made in daylight are ordinary settings;
the way out *during* a lock is the slow door, a wait the user chooses, never a
switch.

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
is the one reassurance they actually want — their plan and nights are intact —
in **one line**. An earlier draft also named the provider and spelled out that
the answers they just gave weren't saved over anything; at five lines of
subtext it read as an apology, and the title plus "instead" already carries
the fate of those answers. When the account has no profile to restore, that
line promises setup instead — never reassurance the next screen will
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
the questionnaire's closing beat: it appears between the account step and
Main, on the same living scene as onboarding. It is a **soft paywall** — a
quiet ✕ in the top-right corner closes it — softened further by honesty:
the terms line under the button leads with the real billed price and says
"cancel anytime". It only ever renders off a *resolved* not-entitled
answer (never a loading guess), and an unconfigured dev build never shows it.

**What the ✕ buys, and what it doesn't.** Closing the paywall drops the
user into the whole app: Home with its countdown and sloth, the record,
the schedule, settings. What they cannot do is **start a night** — Sleep
Now raises the paywall instead of the confirmation panel, and so does every
back door that leads to the same place (the widget capsule, the shield
action, the Siri intent, the wind-down and evening-check-in deep links).
The rule is worth stating plainly because it decides every future
question of this shape: *everything the app shows is free, everything it
does is the subscription.* The lock lives on `SleepStore.isLocked`, with
`startSleep()` itself carrying a final guard so no future caller can route
around it.

Nothing is greyed out. Sleep Now keeps its own name, its moon, and its full
amber weight for a locked user, because a disabled button answers no
questions — the paywall does. The first-run dismissal is remembered per
install (`sulav.paywallDismissed.v1`), so the full-screen pitch is a
one-time landing rather than a wall re-hit on every cold launch; afterwards
the plans stay reachable from Sleep Now and from a "Unlock SleepBlock" row
in Settings, where prices belong. On the paywall itself the ✕ is present
from the first frame — never hidden, never delayed — since a paywall that
conceals its exit reads as a trap long before it reads as a tactic.

> Note on history: this was a **hard** paywall — no ✕, no "not now",
> subscribing the only way past onboarding. It was softened deliberately:
> the wall converted the people it caught, but it turned away everyone who
> wanted to see the thing before paying for it, and the app has plenty to
> show. The lock moved from the door to the one action worth paying for.

The screen is deliberately spare: it earns its keep by asking
one question, not by pitching. The hero is the brand mark over a small
tracked small-caps **"SLEEPBLOCK"** signature — the two form one brand
lockup, the wordmark deliberately quiet (label weight, `dim`, letter-
spaced) so it reads as the app's own kicker grammar and never competes
with the headline; when it matched the headline's size and weight the two
read as twin headlines with no hierarchy. Beneath the lockup sits **one
headline and nothing else** — no other kicker, no subtitle, no feature
list — set as the screen's hero (semibold, `ink`, the largest type on the
screen): "Unlock SleepBlock to build a sleep routine that sticks." It
pitches the app and carries **no price and no trial copy at all** — see
"The billed amount leads" below. The whole hero (mark + wordmark +
headline) floats between two flexible spacers so it sits in the upper
third rather than jammed under the status bar, while the same lower spacer
keeps the plan cards and CTA anchored low — cardless space, not a wall of
copy, carries the gap on any device height.

One headline overrides it: a user whose **referral free nights have run
out** (see "Sleep partner & referral") gets a loss-aversion line instead of
a cold pitch — "Keep your 12-night streak with Maya going", naming the
streak and the partner they built over the free month. The trial badge,
CTA, and terms line still carry the mechanics underneath; only the
emotional line changes. It appears only when there's a streak to lose — a
user who redeemed but never slept falls back to the normal pitch, never an
empty "keep your 0-night streak going". This is the conversion moment the
whole free-nights model rests on, so it gets the honest, specific hook.

> Note on history: the paywall previously opened with a "Your plan" kicker,
> a fixed "Lock your nights in" headline, a two-line subtitle personalizing
> the user's chosen apps, and — before that — three glyph-led feature
> lines. Each was retired in turn: the feature lines repeated the plan
> cards, the fixed headline repeated across both plans regardless of which
> was selected, and the personalized subtitle was the last static line
> once the headline itself started doing that job dynamically. The headline
> then went *dynamic per plan* — the trial plan read "Start your 7-nights
> FREE trial to continue" — and that was reverted in Aug 2026 by the
> 3.1.2(c) rejection: a free-trial line at 30pt is a pricing element
> outranking every price on the screen. The headline is fixed again, and
> price-free.

### The billed amount leads

**Every pricing element on this screen ranks below the amount the user is
actually charged.** This is App Store Guideline 3.1.2(c), and the 1.4
submission was rejected under it: the annual card led with a large
"$5.00/mo" over a quiet "$59.99 billed annually", and the hero headline sold
the free trial in 30pt type. Calculated pricing (a monthly equivalent, a
savings percentage) and free-trial copy are *subordinate elements* —
smaller, dimmer, and lower than the billed amount — and any future change
here has to preserve that order.

The hierarchy, concretely:

1. **The billed amount** — the card's trailing price, `title(19)` in `ink`,
   the largest and brightest thing on the card, and always the real charge
   for that plan's own period ("$59.99/yr", "$5.99/mo"). Never a derived
   figure.
2. **The plan name** — `label(17)`, "Yearly" / "Monthly".
3. **The derived line** — `body(13)` in `muted`, annual card only:
   "$5.00/mo equivalent · save 17%". The equivalent comes from the product's
   own price formatter so the two cards can never mix currency styles; the
   percentage is computed from the fetched plans' real prices
   (`SleepPlan.priceValue`, arithmetic-only, never displayed) so it always
   tracks whatever RevenueCat returns.
4. **The trial** — never card text: an amber capsule **badge** on the annual
   card's top edge ("7 NIGHTS FREE", `label(11)`, the primary button's
   amber-on-navy colors), plus the CTA and the subordinate terms line.

The two plan cards are interactive glass rounded-rects in one
`LiquidGlassContainer`. Selection keeps the onboarding grammar (constant
tint, amber ring + filled trailing circle), the unselected card dims to
~55% so the chosen plan reads first, and annual is preselected. The CTA is
the standard `LiquidPrimaryButton` ("Start 7 nights free", derived from the
product's real intro offer). Beneath it the **terms line** repeats the same
ranking as a two-row stack: the full charge first — "$59.99 per year",
`label(15)` in `ink` — then the trial and cancel note under it in `body(12)`
`muted` ("Starts after your 7-night free trial · cancel anytime"). The
footer is three quiet
text links (Restore purchases · Terms · Privacy) over a soft navy floor
gradient. Failures and notices reuse the auth screen's two-tone rule:
`danger` for real failures, `amber` for normal next steps ("No subscription
to restore on this Apple ID."). Loading and offline states stay composed —
spinner with a quiet line, or a wifi-slash glyph row with a glass "Try
again" — never a broken sheet.

The ✕ itself is the app's standard `GlassIconButton`, one size down (40pt,
15pt glyph, `muted`) and floated over the scroll at the top-right rather
than given a row of its own — the header is a centered brand lockup, and a
row for the close would push the whole pitch down a line on every device.
Top-right is where this app's other closes live (the settings sheet), and
it leaves the opposite corner to onboarding's back chevron, which this
screen follows.

Below the terms line sits one more quiet door: **"Have a referral
code?"** in the footer's type, opening the shared redeem sheet (see "Sleep
partner & referral"). It is deliberately the least prominent thing on the
screen — for the person holding a friend's code it beats every plan above
it, but for everyone else it answers a question they weren't asked. It
hides once the account has redeemed (one code each) and in dev mode.

One structural rule: the sleep-mode overlay always outranks the paywall.
An active night keeps *Hold to wake* / cancel — and with them the Screen
Time shield teardown — reachable no matter what the subscription state
resolves to. The app never traps a user inside a lockdown behind a
purchase screen.

## Sleep partner & referral

**Two separate features** (spec: `docs/roadmap-partner-referral.md`), and
keeping them separate is the whole design. They were fused once — the only
way to get a partner was to redeem someone's referral code — which capped
everyone at one partner and left two already-paid friends unable to
connect at all. Now:

- **Referral** is a growth code: share it, a new friend gets 30 free
  nights, you bank a free month when they subscribe. Transactional, no
  relationship, no data shared. You'd post it anywhere.
- **Sleep partner** is a mutual, ongoing relationship: you each see the
  other's streak and schedule. Built by sending someone a **partner invite
  link**, unrelated to any code, available to anyone regardless of
  subscription. Multiple partners, capped at 10.

The intents are orthogonal — refer a coworker without sharing your sleep;
partner with a friend who already pays, no free month in play — so they
never share a control or a code.

### Referral surfaces

The referral lives in two quiet places, both pointed at the *growth* code:
the paywall's "Have a referral code?" link (redeem side) and Settings'
**Refer a friend** row (share side, a **gift** glyph — never `person.2`,
which is the partner button now). The row pushes `InviteFriendScreen`
(`SubpageHeader` + `SceneScreen`, like every settings sub-page): one
benefit row — "**30 nights free, for both of you**", detail "Theirs starts
the night they join. Yours lands when they subscribe." — the code in a
tracked glass field, one amber **Share referral** button (a `ShareLink`
styled like `LiquidPrimaryButton`), and the joined/subscribed count once
nonzero. The **redeem sheet** (`ReferralRedeemSheet`, `.medium`) is one
hero-type code field and a CTA; the server does every check and speaks the
error copy in `danger` tone. All of this is pure "free month" now — no
partnership language survives here.

### Sleep Partners screen

The partner half has its own home, reached from a **Home top-right button**
(`person.2`, the one affordance Home carries besides Sleep Now — floated
top-trailing so it never disturbs the centered instrument). It opens
`SleepPartnersScreen` as a large sheet:

- **The list** — one glass card per partner, two lines:
  - **Line one** is the person: an amber **monogram** on warm glass, their
    name, and the **streak** as a warm-glass chip pinned top-right —
    Home's flame rule exactly (filled amber alive / hollow muted dying).
    The streak takes the position the eye lands on because it's the number
    this screen exists for: knowing they'll see a broken streak.
  - **Line two** is the night, in Home's own grammar: moon → sun with the
    schedule, then `·` and the average duration, all in one quiet dim row.

  This replaced a three-column `STREAK / SCHEDULE / AVG SLEEP` band. That
  band gave the schedule a third of the width, where `11:10 PM – 7:05 AM`
  wrapped onto two lines and left cards ragged and tall, and it shouted
  the same three uppercase labels down every card in the stack. The
  numbers are identical; only the frame changed.

  A partner who has never synced shows the honest empty line, never zeroed
  stats. What's shown is *all* that's shared — derived numbers over the
  last seven nights, never raw sessions. **Unlink** lives behind a
  trailing `ellipsis` menu (destructive role) and still lands on the
  confirm alert — it was a text button sitting where a primary action
  sits, repeating a destructive word on every card, which is loud for
  something this rare. Unlinking stays unilateral, immediate, either side.
- **Adding someone** — two ways, both codes:
  1. **Show my code** (amber primary) — a 6-character pairing code on its
     own `.medium` sheet, set at 38pt with wide tracking because this
     string gets *read aloud*, not scanned. Alphabet is 005's, no
     `0/O/1/I/L`. One use, 24 hours. The sheet polls while it's up and
     confirms in place the moment someone claims it, so the sender never
     has to ask "did it work?". A **Send it** share button carries the
     App Store link *and* the code, which is the whole point: that message
     works for a friend who doesn't have the app yet.
  2. **Enter a friend's code** (glass secondary) — the twin of
     `ReferralRedeemSheet`, pointed at partnership. Server owns every
     check and all error copy.

  The `sleepblock://` invite link this screen shipped with is **gone from
  the UI**. It only resolves for someone who *already has the app* —
  there's no associated-domains entitlement, so no Universal Link and no
  App Store fallback, and most messengers won't even make a custom-scheme
  string tappable, so it often arrives as dead grey text. A typed code
  needs none of that to survive an install, and it works across a room,
  which is how sleep partners usually pair. Two controls that do the same
  job, one of which silently fails for anyone without the app, is a worse
  screen than one that works.

  Links already handed out still connect — `AppDelegate` still routes
  them and the accept path is untouched — the app just stops minting new
  ones.

  Both sheets are one `sheet(item:)` on an enum, never two stacked
  `sheet(isPresented:)` — SwiftUI honors only one and still *builds* the
  other's content, which fired the code mint before anyone asked for a code.
- **Empty state** — "Sleep better together", the accountability pitch.

**No permanent per-user ID.** A fixed, guessable handle would force back
the accept/decline step this design deleted, and it can't be taken back
once it leaks — while what a partner sees (bed and wake time) is a
schedule of when someone's home is empty. Pairing codes stay one-use and
24-hour so auto-confirm remains honest. The one thing codes need that
links never did is server-side rate limiting on redemption, since a live
6-character space is guessable in a way a 96-bit token isn't.

A tapped `sleepblock://partner/<token>` link routes through `AppDelegate`
to the store, which accepts it (connecting both accounts directly — both
consented, so no confirm step) or stashes it until a fresh-install friend
signs up, then raises this screen with a one-shot confirmation ("You're
now sleep partners with Maya"). Safety without a confirm step rests on the
token being single-use and 7-day-expiring, plus instant unlink.

### The free-nights ending (referral, conversion)

Two mechanics catch the end of a referral's free nights — length was never
the conversion lever, this moment is:

- **Ending nudge** — in the last three nights, Profile grows a dismissible
  warm-glass nudge (Health-card grammar) titled by the countdown ("2 free
  nights left" / "Last free night") and naming what's at stake, with a
  **See plans** button. The heads-up *before* the wall.
- **Expiry headline** — once the nights lapse, the paywall leads with the
  loss-aversion line (see "Paywall"): "Keep your 12-night streak going",
  naming a partner only when there's exactly one. The catch *at* the wall.

### Deliberately absent (v1)

Partner push notifications, and any free-text between partners. The partner
screen is quiet accountability — knowing they'll see the broken streak —
not a chat app. The only thing that ever crosses accounts is a display
name and four derived numbers.

## Screen Time primer

The last gate before Main (`ScreenTimePrimerView`, SleepScreenTime.swift),
shown **only to subscribers**: SleepBlock is an app-blocking app, and this
is where blocking gets its teeth — asked at peak commitment, right after
the user paid, never mid-sign-up (the Health rule). A locked user skips it
entirely. Family Controls is the most alarming permission the app asks
for, and spending it on someone who cannot start a night yet asks them to
hand over their phone for a feature they can't reach. The centerpiece is a
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
- **Medium — the morning glance.** The **recent average** as the hero
  numeral in the top-left corner, with its own caps caption naming the sample ("AVG · 7 NIGHTS", "AVG · 4 NIGHTS", or "LAST NIGHT"
  when one night is all there is), and the 7-night bar rhythm on the right. Along the bottom runs a band reading left→right as **figure,
  instrument, action**: the sloth anchoring the corner, the bedtime countdown
  centred where the eye crosses between them, and the Sleep Now capsule
  closing it. The countdown earns the middle because it is the only live
  thing on an otherwise retrospective tile.
  The hero **used to be last night's duration, and it blanked out.** The app
  only calls a night "last night" when it ended today or yesterday, so on any
  morning you forgot to log — or any afternoon two days on — the tile lost its
  number and showed a lone 11pt kicker beside a chart still full of bars. A
  stats tile whose headline can vanish while it still has data to show is
  broken, and no copy fixes it: the honest repair is a figure that exists
  whenever any night does. The average also describes the *same stretch of
  time* as the chart beside it, which a single night never did.
  The caption **names its own sample size** rather than claiming a flat
  "7-day average" over a week holding four nights — the same honesty rule and
  the same last-N-*logged*-nights window as Profile's summary band ("Avg
  sleep · last 4 nights"), so the two surfaces can't quote different numbers.
  With exactly one night on record both drop the average language and say
  "last night", because an average of one is a claim about a week that isn't
  there.
  Last night keeps its place on the tile without a numeral: the newest logged
  bar is the only one at full strength. And still **no streak line** — medium
  was carrying six things at once and the streak was the least load-bearing of
  them; dropping it lets the hero and the chart breathe. The streak shows on
  large.
- **Large — the record + tonight.** The same recent-average hero at the top,
  with the streak in the tile's **top-right corner** (**flame glyph + the bare count**, no "on
  track" — a flame beside a number already reads as a streak, and the words
  were the longest string in the header for the least information; the
  spelled-out phrasing survives as the VoiceOver label, and the flame hollows
  to muted grey when the streak is dying, per [The streak](#the-streak)),
  with the same sample
  caption stacked under the numeral medium stacks it under, then full-width
  bars that **grow with the tile up to a ceiling, with the slack left as air
  above the chart so the bars sit on their own hairline** — a fixed chart height left a hand's width of dead space
  above the footer on tall phones and would clip the footer on short ones (the
  large family runs ~311pt to ~382pt tall), but letting the chart eat every
  spare point was worse: past about half its own width a bar chart stops
  reading as a week's rhythm and starts reading as seven towers, and a sparse
  week turns into a lot of vertical drama for "you missed Tuesday" — with weekday initials and
  in-bar hour labels (so last night's own figure is still printed, on its
  bar), then a hairline and a **mini-Home
  footer** anchored to the bottom edge: the sloth as tonight's figure, the
  tonight block, and the Sleep Now capsule on the trailing side — the same
  figure→instrument→action order medium reads in. The block is **label over
  numerals, centred in the band** the sloth and the capsule leave behind —
  exactly where medium sets its countdown, so the two tiles read alike: a
  quiet "Bedtime in" (or "Past bedtime") with the interval on its own line
  beneath, ink before bedtime and amber after. Leading-aligned it sat hard
  against the sloth with all the slack pooled on the capsule side, which read
  as a layout accident rather than as the middle element of figure →
  instrument → action. As one running line the label
  and the value fought for a width the footer doesn't have — the sloth and
  the capsule take theirs first — and the figure truncated mid-glyph; split,
  the interval owns a line and can be larger than it was when it had to
  share. Text only, no moon glyphs; the sloth *is* the glyph. Past bedtime
  now leads with the label rather than the shield's number-first phrasing:
  one shape per slot beats one phrasing per app when the two states swap in
  place.
  Large previously opened straight onto the bars, on the reasoning that the
  rightmost full-strength bar *was* last night so a numeral would repeat it.
  (It then led with last night's numeral, and inherited the blanking problem
  described under medium.)
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
- **The moon-glyph "SLEEP" kicker is an empty-state mark, not a header.**
  It used to sit on top of medium and large in every state, and with data on
  the tile it labelled nothing: the hero carries its own caption, the chart
  carries the subject, and the whole position above is that the sloth makes a
  widget recognizably SleepBlock *without a logo badge* — so the kicker was
  spending the one corner the numeral wants on a repeat of the app's name
  (which iOS prints under the tile in the gallery and in edit mode anyway).
  It now appears only where there is no numeral to label and no chart to read:
  the stats families' empty state, and small's no-schedule state. On large,
  losing the header row moved the streak flame up into the tile's top-right
  corner, on the **hero caption's baseline**: it belongs to the record as a
  whole rather than annotating the average it sits beside, and it no longer
  needs a rule of its own to hold it. Aligned to the *top* of that row instead
  it aligned to a line box rather than to a letter — a 34pt numeral carries
  ascender space above its cap, so the flame floated higher than the figure
  beside it and read as stuck to the ceiling. On the caption's baseline the two
  small figures pair off, kicker left and streak right, and the hero owns the
  line above them alone. The flame itself is **re-derived on the
  tile** from the nights it draws, rather than read from a count the app stored
  at write time: a widget showing no streak while its own chart plainly shows
  last night logged is telling two stories at once, and the chart is the one
  the eye believes.
- **Empty is a promise, never a blank.** The stats families have exactly two
  no-data faces, and both name the thing that will appear once there is data:
  signed out, "Sign in to start / Your nights and averages live here." beside
  the Sign in capsule; signed in with nothing logged, "No nights yet / Log
  tonight and your average lands here." The copy lives in one place
  (`StatsEmptyCopy`) so medium and large can't tell two stories about the same
  nothing, and it sits **where the hero numeral would**, top-aligned under the
  kicker that only this state wears — the room below it is the chart's, and reading as empty-and-waiting
  is the point.
- **Lock-screen accessories** (circular / rectangular / inline) render in the
  system's vibrant material at tiny sizes, so they use default foregrounds
  and SF symbols — no app palette, no sloth (at 20pt the figure would blur
  into mush). Circular is a duration-vs-target gauge with last night's hours
  in the middle (or a moon when asleep / no data — it stays last-night-only,
  because an average drawn against the same ring would look identical to a
  night with no way to tell them apart); rectangular and inline lead with
  tonight's state — "Bedtime" over "in 1h 44m", "Bed in 1h 44m" — and their
  supporting record line falls back from "Slept 7h 20m" to "4-night avg
  7h 05m" when last night is missing, the same never-blank rule the
  home-screen families follow.
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
- Title: **"5h 48m until your alarm"** — the countdown takes the bold slot, and
  "Time for bed" steps down to the subtitle. `ShieldConfiguration.Label`
  carries a string and a colour and nothing else, so a phrase *inside* the
  subtitle cannot be emphasised; putting the number in the title is the only
  way to give it weight. It earns that weight — it is the one thing on the
  screen the user doesn't already know, and the only part that changes as the
  night runs on.
- This replaced **"18 minutes past bedtime"**, and the swap is the point. Time
  past bedtime is a scolding about a decision already made; time until the
  alarm is a fact about the pain arriving in the morning. Someone standing at
  a block screen at 1am has fully priced in that they are up late — what they
  have not done is the subtraction.
- Subtitle: **the user's own sentence**, when they have written one (see
  *Their own words* below). Otherwise "Time for bed." One short line either
  way. Nothing else belongs here: the user is looking at a block screen, so
  saying the app is blocked spends wrapped lines restating what they can see,
  and the buttons already state the options.
- Before any lockdown has been scheduled (wake time isn't in the App Group
  yet), the shield keeps its original pairing — title "Time for bed", subtitle
  "Put your phone down and head to bed."
- Primary button: **"Sleep Now"** (amber) — closes the shield and fires a
  local notification with the `sleepblock://sleep` deep link. Tapping the
  notification opens the app on the sleep confirmation panel. (The Shield
  Action API cannot directly launch the host app; the notification is the
  bridge.)
- Secondary button: **"5 more minutes"** (dim) while the night's snooze
  allowance lasts, then the slow door (below).

**Active sleep phase** (user tapped Sleep Now, session running):
- Title: the same alarm countdown, falling back to "Time to sleep".
- Subtitle: the user's own sentence, falling back to "This app is asleep until
  you wake."
- Primary button: **"Good night"** (amber) — dismisses the shield.
- Secondary button: the slow door only. Never a snooze.

### Their own words

The subtitle carries a sentence **the user wrote** about why they want this,
rotating to the next one on each reach of the night.

The app's own copy is the weakest possible voice for the 1am argument — it
reads as one more piece of software telling someone what to do, and there is
an obvious thing to be annoyed at. Their own sentence has nobody in it.

- **Three at most, 60 characters each.** The shield subtitle is one short line,
  so anything longer wraps badly or truncates — and the ceiling is doing
  double duty, because a tight limit produces the true sentence instead of a
  slogan.
- **Rotating, not fixed.** One line stops being visible after about a week, the
  same way a desktop wallpaper does. Rotation keeps it read rather than seen.
- **Never collected at sign-up.** Asked cold the answer is always a slogan
  ("I want better sleep"), and a slogan on the shield is indistinguishable
  from our copy. The app asks the morning after a night the user actually
  reached — the feeling is still available then. Until they write one, the
  shield falls back to its own copy; nothing is ever written for them.

### The snooze

`ShieldConfiguration` has exactly two button slots, so the escape hatch had to
displace something. It took the **secondary** slot, which previously held an
"OK" that only closed the shield — a dead control in the scarcer half of the
UI. It stays in the quiet slot deliberately: a shield whose loudest button is
"not yet" argues against itself, so amber keeps saying *Sleep Now* and the way
out is plain text underneath.

It exists **only in the pre-sleep phase**. Snoozing out of a session the user
deliberately started would make lockdown mean nothing. That boundary is what
makes offering a snooze before sleep safe rather than corrosive.

**Two per night, then gone** — and none at all in hard mode. Uncapped, "5 more
minutes" is an off switch with extra steps; the point is that it runs out. The
allowance resets when a genuinely new window opens, keyed to the window's start
date so a mid-night re-registration can't reissue it.

### The slow door

When the snooze is gone — or in the active phase, where there never was one —
the secondary slot offers **"I need 10 minutes"**. Tapping it does not unlock
anything. It starts a 60-second wait (180 in hard mode), and the shield the
user meets on their *next* attempt reads "Unlock 10 minutes" and opens.

This is the one place the design deliberately gives ground, and the reasoning
is retention, not leniency: **deleting SleepBlock is itself an escape hatch,
and the only one that can't be taken away.** A lockdown whose remaining exits
are "wait six hours" or "delete the app" pushes people toward the permanent
one. The door exists to be taken.

- **The wait is the mechanism.** A craving fades in about a minute. Most people
  put the phone down during it and never come back for the second tap; the
  ones who do come back get their ten minutes and keep the app.
- **Never rationed.** Unlike the snooze it doesn't run out — an exit that can
  be exhausted is a dead end with extra steps. It costs the wait every time,
  which is what keeps it from being a plain off switch.
- **Two taps, by necessity as much as design.** A shield action extension is
  torn down the instant it answers a tap and cannot run a timer. The shield is
  re-rendered on every attempt, so the user's own second attempt is the clock.
- The waiting label ("Unlocks in 43s") is `faint`, not `dim` — it is the one
  state where the control is informational and tapping does nothing.

### Reach attempts

Every render of the shield is one reach, logged to the App Group (debounced 5s,
since the system can ask for a configuration more than once per launch). It
costs nothing — the extension runs exactly when someone reaches — and it is the
only honest measure of whether any of this works.

Read back in the morning as a **mirror, never a judge**: "You reached for
Instagram 6 times last night — all between 12:40 and 1:10." No red, no
"failed", no streak-breaking. Most people genuinely don't know they do this,
and seeing it plainly moves behaviour further than any wall. The moment it
reads as a scolding, the app gets deleted.

When `startSleep()` calls `startLockdown()`, the phase flips from `presleep`
to `active`. The next time the shield renders, it picks up the new phase and
shows the firm lockdown copy. The phase clears when the session ends — see
below.

### The block ends with the session

**Nothing on a clock takes the shield down.** Once a session is running, the
apps stay blocked until the user holds the wake button (or cancels). Wake time
passing doesn't do it; no configurable cap does it, because there isn't one any
more.

There used to be an "Unlock anyway after Nh" stepper, defaulting to six hours.
It was framed as a safety valve, and it was really a snooze button with a long
fuse: the hour it fired was 3am, the hour the block was the entire point. A
block you know will expire is a block you can wait out, and waiting it out in
bed with the phone in your hand is the exact behaviour the app exists to
interrupt.

The escape that stays is the **slow door** on the shield — a wait the user
chooses, deliberately, every single time. That is a different thing from a
timer: it costs something at the moment of wanting, and most people never come
back for the second tap. An exit has to exist (the alternative someone reaches
for when there is none is deleting the app), but it should never arrive on its
own while they sleep.

**One exception, and it is not really one.** A window that shielded at bedtime
and was never slept through still clears at wake time. There is no session to
end there, so nothing else would ever lift it — that user simply didn't use the
app that night, and locking them out of their phone indefinitely for it would
be indefensible.

Because the shield can now outlive the alarm, the shield's countdown stops at
wake time rather than rolling over to tomorrow's: a ten-minute lie-in read as
"23h 50m until your alarm", which is true and lands as a threat. Past the
alarm it falls back to the written copy, which already says the honest thing —
asleep until you wake.

### Shared state

The phase is communicated via App Group UserDefaults (`sulav.lock.phase`),
readable by all four targets (main app, monitor, shield config, shield
action) — along with the schedule mirror, the user's reasons, the reach log,
and the door's state.

All of it lives in **`SleepLockdownKeys.swift`**, which imports Foundation and
nothing else so every target can compile it, including the jetsam-constrained
shield process that must not link FamilyControls. The extensions used to
hardcode their own copies of each key; that was survivable at five constants
and a liability at twenty, because a typo'd key string is a silent no-op rather
than a build error. Anything genuinely framework-dependent (the
`DeviceActivityName`s, the `FamilyActivitySelection` coding) stays in
`SleepLockdownShared.swift`, which only the app and the monitor compile.

What the secondary button *means* is resolved once, in
`SleepLockdownSelection.currentEscape()`, and read by both the extension that
draws the label and the one that answers the tap — so the words the user read
and the thing that happens can't drift apart.

The extension can't see the app's asset catalog, so it bundles its own
downsized copy of the night sloth (`ShieldSloth.png`, 480px, from
`HomeSlothNightBlink`). Frame budget stays modest on purpose: shield config
extensions live under a tight memory ceiling, and a killed extension falls
back to Apple's generic shield — the exact thing this exists to replace. The
mark always wears night light (never day/dusk): the shield only appears
during the blocking window.

## Commitment surfaces

Five in-app screens that exist to make people *want* to keep the plan, rather
than adding another lock. The governing belief: **deleting the app is the one
escape hatch that can't be taken away**, so past a certain point extra
restriction stops buying compliance and starts buying uninstalls. These are the
cheaper lever.

### The morning card

The screen between the night and the day. Hold to wake, and instead of the app
dropping you on Home with a row quietly added to a list, the OLED black lifts
into the morning scene and the night you just slept is on screen: the awake
sloth over **GOOD MORNING**, then one glass capsule led by the duration in the
same numerals the sleep screen was counting a second ago. The window actually
slept (*11:20 PM → 6:52 AM*) and the flame count, when a run is live, sit
beneath it as quiet context. **Start the day** is the only action.

Every other surface in this app spends itself on the moment someone is trying
to break the plan — the shield, the slow door, the wind-down. Nothing marked
the moment they kept it, and a habit whose finish line is invisible is one
people stop running at. This is the finish line.

- **Duration owns the glass.** The user is half awake and the first question
  is simply how long they slept. That number is the capsule's large,
  high-contrast hero; the actual start→wake window is secondary, and a live
  streak is tertiary. There is no generated congratulatory sentence competing
  with those facts. The card mirrors the night instead of interpreting it.
- **Only a real night gets a morning.** Under the streak's own 30-minute floor
  the card doesn't appear at all — "Good morning" over a four-minute mis-tap
  is the app congratulating itself.
- **Only the good news.** The flame appears when a run is live and is silent
  when it's dying or absent. Warnings have a home on Home; a warning handed to
  someone who just did the thing right is noise.
- **Light, not confetti.** The one celebratory effect is a warm bloom swelling
  behind the sloth over 0.9s — a sunrise, in the same amber that lights the
  rest of the app. No badges, no score, no burst. The reader is thirty seconds
  awake.
- **One exit, and it's a button.** No ✕ and no tap-anywhere: a half-awake hand
  shouldn't be able to lose the screen by brushing it. Equally, no auto-
  dismiss — a card that vanishes mid-glance is worse than one tap.
- **A moment, not a record.** Never persisted. Kill the app with the card up
  and you land on Home, because "Good morning" three hours later is the app
  talking about a night you've moved on from. The night itself is already on
  Home's last-night strip and the Profile chart.

### The morning mirror

One quiet line under Home's last-night strip — same slot, same restraint, the
part the duration can't say: *"Reached 6 times · 12:40 – 1:10"*.

The window is the insight, not the count. "Six times" says how often; "between
12:40 and 1:10" is where people recognise themselves. Most genuinely don't know
they do it.

- **Mirror, never judge.** `muted` text, no red, no card, no "failed", no
  exclamation mark. It sits at the same visual weight as the sleep duration
  beside it because it is the same kind of fact.
- **Silent on a clean night.** No hairline, no empty state — matching the strip
  above it. A triumphant "0 attempts!" would cheapen the nights that mattered.
- Tapping it opens the reason editor — **except while the block is
  running**, when the line stays as a report and the amber "Write why you're
  doing this" invitation is withheld. The reasons are what the shield is
  quoting back tonight, so they close with the rest of the lockdown settings,
  and inviting a sentence that can't be saved is worse than staying quiet.

### The reason editor

Where the user writes what the shield says back to them (see *Their own words*).
The screen is built to produce a true sentence rather than a slogan: a stem in
the placeholder ("I'll know this worked when…") instead of a blank box, a hard
60-character ceiling whose counter only appears in the last 15, and three slots
because the shield rotates. The app never writes or suggests one.

The invitation appears **the morning after a night they actually reached**, not
at sign-up — the mirror line grows an amber "Write why you're doing this" when
they have no reasons and last night had two or more reaches. Cold, the answer
is always a slogan; with the feeling still available, it isn't.

### The evening check-in

A soundless notification an hour before bedtime opens a full-screen review:
tonight's window, what locks, and their own reason read back.

Everything else in the lockdown argues with the 1am self, who didn't choose any
of this. This screen talks to the person who did — calm, hours from the
craving, agreeing to something still hypothetical. A constraint someone
accepted while calm is one they remember accepting.

- **No controls that weaken tonight.** It is a review, not a settings screen.
- **"Not tonight" changes nothing** — it's an acknowledgement, not an opt-out. A
  one-tap skip here would be the cleanest bypass in the app, handed over at the
  exact moment someone is most willing to use it later. The real off switch
  stays in Blocked apps, where it's a deliberate trip rather than a reflex.

### The wind-down

Two minutes of breathing — 4s in, 2s hold, 6s out, the long exhale taking half
the cycle because that's the part that settles someone. Concentric amber rings
swell and shrink with the breath; the instruction ("Breathe in" / "Hold" /
"Breathe out") and the scale are both derived from elapsed time, so the ring
and its label can't drift apart. Reduce Motion holds the rings still.

**Not Liquid Glass.** Glass is reserved for things the user can press, and this
is the one element in the app that is purely something to look at.

The gap it fills: blocking creates an empty moment, and an empty moment at 1am
is when people go hunting for a way around the lock. Every other surface asks
someone to *stop* doing something; this is the only one that offers something
to do instead.

- **The right-sized ask.** Someone reaching for Instagram is not ready to
  commit to a whole night — that's why they're reaching — so the
  slide-to-sleep is the wrong request. Two minutes is an easy yes, and it ends
  one tap from the real thing ("I'm ready" hands straight to the confirmation).
- **Two minutes, not ten.** A craving fades in about that long, and a wind-down
  long enough to feel like a chore is one people decline.
- **A quiet countdown, never a progress bar.** A filling bar turns settling
  down into a task with a finish line, which is the opposite of the point.
- Reached from the notification fired when a snooze runs out, and from
  `sleepblock://winddown`. That first one is the whole point: a person whose
  five minutes just expired is by definition not ready to sleep, and the old
  copy ("Tap to start your sleep session") was an easy refusal that sent them
  straight back to the app they came from.
- **Not offered on the sleep confirmation.** It was, briefly. That screen has
  exactly one job — the slide — and a second amber control beneath it split the
  ask in two. Someone who has already opened the confirmation is past needing
  to be eased in; the wind-down belongs where people are actually stuck.

### Hard mode

An opt-in toggle in Blocked apps: no snooze, and the slow door takes three
minutes instead of one. Off by default and never turned on by the app.

A restriction someone chose is respected; the same restriction imposed is
resented, and resentment is what uninstalls the app. Offering a real hard mode
is also how you serve the people who want more without punishing everyone else.

### The streak

**A streak behaves like a streak.** Miss one night and it's *dying*; miss the
next and it's gone. One state of warning, then the consequence — the model
every user already carries in from every other streak they've held, and one
that can be explained in a sentence. The rule it replaced (skip a miss, with
an allowance of `1 + streak / 7`) was gentler but unreadable: nobody could
have told you what it would do, so it couldn't motivate anything.

A dying streak keeps its count. The missed night never increments it, so the
number only ever means nights slept, and reviving it costs one night rather
than restarting from zero.

**What counts is showing up, not the score.** A night qualifies at **30
minutes or more** — not the old ≥85%-of-target bar. At an eight-hour target
that bar sat at 6h48m, which means someone averaging six hours, exactly the
person this app is for, could never hold a streak at all and would open the
app to a permanent zero. Duration already has three honest homes — the hero,
the chart, the target chip — and doesn't need a fourth that shames. The
30-minute floor is a junk filter for an accidental session or an aborted nap,
nothing more.

**Nothing is judged before it's due.** Sleep days are keyed by the morning you
woke, so having no record for today is the ordinary state of every evening —
you haven't slept yet. A day only becomes missable once its wake time plus two
hours has passed, which is late enough to absorb a lie-in or a slow Health
sync. Without that, every user would watch their streak start dying at dinner.

The count is recomputed from history on every read and never stored, so a
Health night that syncs a day late fills its own gap and the run comes back on
its own.

**How dying looks.** The filled gold flame becomes a **hollow flame in muted
grey** — same glyph, same count, same position, so nothing reflows on the day
it happens and the number still reads as the streak it always was. An outline
that has lost its fill says "going out" without warning copy, and without
`danger`, which stays reserved for things that are actually wrong. VoiceOver
carries the full sentence. Home and the large widget make the identical swap.

## Ad attribution

The app runs TikTok App Promotion campaigns, and the TikTok Business SDK
(`SleepTikTok.swift`) reports the funnel back so the campaign can bid for
subscribers instead of tappers: install and launch come free with the SDK, and
the app adds **registration**, **start trial**, and **subscribe** (the last two
carrying the plan's real price and currency).

**The app never asks for tracking permission.** There is no ATT prompt, so
there is no IDFA, and nothing the SDK sends links a person across other apps or
websites; attribution runs on Apple's SKAdNetwork, which needs no consent.
This is a deliberate trade, and the reasoning is the same one the rest of this
document keeps making: the prompt buys a modest lift in attribution accuracy
and costs a permission dialog planted in the middle of a first run that is
otherwise about sleep, plus a second App Review surface (Guideline 5.1.2) on
an app that has already been rejected once. A sleep app that opens by asking to
follow you around the internet is not the app this document describes.
Measurement is a business need; it does not get to be the user's problem.

The same "never fake it" rule the paywall follows applies here: a build with no
TikTok keys reports **nothing**, silently. Dev builds and the simulator are
therefore invisible to Events Manager, which is correct — they are not
installs.

## What to avoid

- Purple, neon, cyberpunk or blue-heavy identity.
- Generic wellness card stacks; bright white screens.
- Pixel icons inside the UI (pixel art is for the environment only).
- Decorative motion that doesn't support the sleep state.
- Long educational copy or tiny tap targets in the nighttime flow.
- Shaming the user for reaching. The reach data is a mirror; the moment it
  reads as a scolding it stops being something they want to look at.
- Dead ends. Every blocking surface keeps one exit, even if it costs a wait —
  the alternative someone reaches for when no exit exists is the uninstall.
