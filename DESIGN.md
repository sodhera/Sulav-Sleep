# Sulav Sleep Design System

Sulav Sleep should feel like a warm bedside instrument, not a generic wellness dashboard. The interface exists to help someone stop using the phone at night, so the UI must be low-stimulation, legible under a red tint, and direct about the commitment window.

## Research References

- Apple Human Interface Guidelines, Color: https://developer.apple.com/design/human-interface-guidelines/color
- Apple Human Interface Guidelines, Buttons: https://developer.apple.com/design/human-interface-guidelines/buttons
- Material 3, Color: https://m3.material.io/styles/color/overview
- Material 3, Motion: https://m3.material.io/styles/motion/overview
- Material 3, Buttons: https://m3.material.io/components/buttons/overview
- Sleep Cycle: https://sleepcycle.com/
- RISE Science: https://www.risescience.com/

## Product Mood

The design direction is "Lullaby" — a dreamy deep-indigo night sky with a soft crescent moon nestled in clouds. Friendly, rounded, a little magical. Adapted from the reference sleep-tracker shot the team chose as the north star (deep indigo + violet/magenta, Montserrat type, crescent-moon-in-clouds illustration, smooth weekly wave chart).

- Deep indigo night sky with soft violet blobs.
- A crescent moon in fluffy clouds with faint orbit rings — the emotional centre, the "art that makes you feel good about sleeping."
- Stars scattered behind the moon.
- Two clear actions (Sleep Now + Set Bedtime) as friendly pills.
- Glassy statistic cards (Quality / Duration) and a smooth weekly-sleep wave chart give the data a calm, dreamy presentation.

## Palette — "Lullaby"

Deep indigo night with violet→magenta accents, taken directly from the reference. Anchors: `#291965` / `#533EA8` / `#943EC3`.

- Background gradient: `#2A1C66 → #191038`, with faint violet blobs (`#3E2A8A`, `#7A33B0`).
- Hero widget gradient: `#332176 → #241858` (night sky).
- Quality card: magenta gradient `#A24BE0 → #7E3CC2`.
- Duration card: purple gradient `#5B45B8 → #3E2D8C`.
- Ink: white `#FFFFFF`, plus `rgba(255,255,255, .74 / .52 / .30)` for dim/quiet/faint.
- Glass surfaces: `rgba(255,255,255,0.06)` fill, `rgba(255,255,255,0.10)` border.
- Moon: `#F4F1FF → #D9D2F7`.

Reasoning:

- The violet/magenta night reads as dreamy and gentle rather than clinical.
- White pill buttons (the reference's "Start/Stop tracking") pop cleanly on indigo and feel friendly.
- Glassy translucent cards over a soft-blob background give depth without heavy borders.

- Base: `#15111B`, `#1B1622` (deep plum-black)
- Ink (warm off-whites, never sharp white): cream `#F4E9DC`, warm `#C9B3A0`, quiet `#8E7C70`
- Dusk accents: clay `#D98E6E`, peach `#E9B488`, gold `#E6C089`
- Surfaces: card `#221A29`, raised `#2A2230`
- Lines: `#322839`, `#271F2E`
- Moon / sky gradient stops: sky runs `#221A30 → #352741 → #5A3F4E → #92604F → #C9885F` (deep plum to clay horizon); moon `#F7EAD7`

Reasoning:

- A real twilight has a cool deep sky AND a warm horizon. That duality is the whole identity — it reads as the moment of *settling down*, not a flat dark dashboard.
- Warm dusk tones are emotionally cozier than the cold indigo/amber that every AI sleep app defaults to.
- Everything is low-contrast and warm so it stays comfortable at night and under a red filter.
- One peach accent (`#E9B488`) carries every highlight — score, today's bar, primary action — for a single, coherent voice.

## Typography

**Montserrat**, matching the reference exactly. A geometric, friendly sans loaded as a real custom font via `expo-font` + `@expo-google-fonts/montserrat` (this required adding the native modules and rebuilding the iOS app — see Mechanism note below).

Weights in use: `400 Regular`, `500 Medium`, `600 SemiBold`, `700 Bold`, `800 ExtraBold`.

Scale:

- Hero greeting ("Good night"): 28, ExtraBold.
- Date / section headers: 13–22, Bold (section labels ALL-CAPS, +1 letterspacing).
- Stat values: 26, Bold.
- Body / controls: 15–16, Medium / SemiBold / Bold.
- Captions: 11–14, Medium.

Reasoning:

- Montserrat's circular geometry is the friendly, dreamy voice in the reference; nothing built into iOS matches it, so it's worth bundling.
- ExtraBold only for the single hero greeting; everything else stays lighter so one focal point leads.

## Mechanism note — native dependencies

This direction needs two native modules beyond the Expo defaults:

- `react-native-svg` — the crescent-moon-in-clouds illustration (crescent via an SVG mask, clouds from circles, faint orbit ellipses) and the smooth gradient-filled weekly wave chart (Catmull-Rom → bezier `Path`).
- `expo-font` + `@expo-google-fonts/montserrat` — the Montserrat typeface.

Adding them requires a native rebuild (`expo prebuild` + `pod install` + build), which the `scripts/run-ios-simulator.sh` wrapper handles. **`pod install` needs a UTF-8 locale** — run with `LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8` or CocoaPods crashes with an `ASCII-8BIT` normalization error.

## Layout And Spacing

Strict 8pt grid (Apple HIG). Tokens:

- `4`, `8`, `12`, `16`, `20`, `24`, `32`, `40`

Rules:

- Screen margins: `24`. Major section gaps: `32`. Intra-cluster gaps: `8–16`.
- Touch targets ≥ `44`; primary/secondary actions `64` tall.
- Generous breathing room is the point — emptiness is calming.

Structure (top to bottom):

- Header: serif "Good evening" greeting + date, with a small moon chip.
- `DuskWidget`: the emotional centre — a dusk scene (gradient sky, stars, low glowing moon, soft ridge) with last-night duration, an italic quality line, the score, and a seven-night rhythm graph laid over a ground-haze veil.
- Actions: `Sleep Now` (warm peach gradient, the commitment) and `Set Bedtime` (quiet surface, value on the right).
- Stats: two cozy cards — average bedtime and on-time streak.
- Settings: a single grouped list (lock duration, wind-down reminder, morning unlock, allowed apps).

Reasoning:

- The widget IS the product premise and the art — one beautiful image you want to return to, not a stack of identical cards.
- The scene is restrained on purpose: one moon, a few stars, a soft ridge. The previous build's dozen cartoon mountain shapes read as vibecoded; restraint reads as designed.
- Only two actions, exactly as the product calls for. Everything else collapses into the settings list.

## Containers

Corners are continuous and soft:

- Small: `14`
- Medium: `18`
- Large: `24`
- Hero/widget: `32`
- Pills: `999`

Rules:

- Cards are only for functional clusters: the widget, stat cards, the settings group.
- Do not nest cards inside cards.
- Settings use one grouped container with hairline dividers, not a row of separate cards.

## Buttons And Controls

- Primary (`Sleep Now`): warm peach→clay gradient fill, deep-brown text, `64` tall, two-line label with a moon glyph. It is the cosy commitment, so it glows.
- Secondary (`Set Bedtime`): warm card surface, soft border, label left + peach value right, `64` tall.
- Settings rows: ≥ `52` tall, hairline dividers, peach chevron.

Reasoning:

- One warm gradient action anchors the eye and feels inviting rather than clinical.
- Hierarchy is carried by fill vs. surface, following Apple's guidance on a single clear primary action.

## Motion And Feedback

Motion is intentionally small:

- Phase changes fade and lift in over 260-320 ms.
- Press states scale to `0.98-0.99` and reduce opacity.
- Selection uses light haptics through `expo-haptics`.

Reasoning:

- The app should never feel exciting at night.
- Motion confirms state changes without rewarding phone interaction.
- Haptics help the app feel native in the iOS Simulator and later on device.

## Red-Filter Safety

The UI must work when iOS Color Filters are configured as a red tint or Android night filters are enabled:

- Use contrast and hierarchy before hue.
- Avoid blue-only links or controls.
- Pair every colored state with text.
- Keep body copy short and high contrast.
- Use big numerals and clear positions for time/score.

## What To Avoid

- Generic wellness card stacks.
- Blue/purple gradients as the main identity.
- Overly bright white backgrounds.
- Decorative illustrations that do not explain sleep state.
- Tiny tap targets.
- Long educational copy inside the nighttime flow.
- Animations that feel playful, bouncy, or rewarding.
