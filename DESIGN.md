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

The design direction is "night landscape" — standing outside on a clear night looking at a mountain range under a crescent moon:

- Deep indigo-black sky with a layered mountain silhouette.
- A crescent moon with warm amber glow halos.
- Stars scattered across the top half of the art widget.
- Two clear primary actions (Set Bedtime + Sleep Now) as the only controls.
- Sparse settings below — no dashboards, no phase switchers.

The art widget IS the UI. It communicates sleep state through the imagery, not through status chips or progress rings.

## Palette — "Dusk"

The identity is the last warm light at the horizon bleeding up into deep night. A cool deep-plum sky meets a warm clay/peach horizon glow with a soft moon resting low. The cosiness lives in the *warmth at the edges*, never in cold indigo or generic amber.

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

A deliberate editorial pairing using platform-available iOS fonts (no custom-font native build required):

- `Hoefler Text` — display serif. Carries warmth and personality: greeting, hero duration, the italic sleep-quality line, section titles. The italic ("Restful and unbroken") is a signature touch.
- `Avenir Next` — humanist UI sans for controls, labels, body, and small numerals where legibility leads.

Scale:

- Hero duration: 52 / 56, serif, weight 500 (light and airy, never heavy).
- Greeting / section serif: 19–28, weight 500–600.
- Body / control labels: 15–17, sans, 600–800.
- Captions: 11–14; ALL-CAPS letterspacing used sparingly (only `SCORE` and one or two labels).

Reasoning:

- Light-weight large serif numerals feel calm. Heavy bold numerals (the previous build) read as loud and clinical — the opposite of bedtime.
- The serif gives the app an unmistakable identity; the sans keeps the operating controls crisp.
- Tabular numerals on metrics prevent score/time jitter.

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
