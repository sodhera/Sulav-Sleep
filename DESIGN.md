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

The design direction is "sleep gate cockpit":

- Calm, dark, warm, and almost physical.
- One strong instrument panel for bedtime status.
- Sparse controls because too many nighttime choices defeat the product.
- Data shown as a ritual and accountability system, not decorative analytics.

Sleep Cycle validates the score/routine framing: duration, quality, and consistency should be visible as a simple trend. RISE validates a darker, more instrument-like sleep surface with a strong hero metric. Apple and Material both push clear hierarchy, large touch targets, semantic color, and restrained motion.

## Palette

The app avoids sharp white, saturated blue, and purple-heavy wellness gradients. The current palette is:

- Background: `#0E0B0E`, `#151014`, `#120D0C`
- Text: `#FFF5E9`, `#D7C4B3`, `#A99383`
- Surfaces: `#201819`, `#2A201F`, `#352722`
- Lines: `#5B473D`, `#3B2F2D`
- Accents: amber `#F3BA63`, ember `#E56E50`, rose `#D49483`, moss `#9AAA86`, danger `#F08A71`

Reasoning:

- Warm dark neutrals reduce glare and remain appropriate when iOS Color Filters or Android night filters are active.
- Amber/ember/rose support a red-filter environment better than blue or purple accents.
- Moss is used only for morning/recovery so color still carries meaning without making the screen one-note.
- State never relies on hue alone; labels, progress, layout, and line weight also communicate status.

## Typography

The prototype uses platform-available fonts:

- `Avenir Next` for display and body text on iOS Simulator.
- `Menlo` for clock, score, and duration numerals.

Scale:

- Hero title: 36 / 41, heavy.
- Section title: 18-19 / 23-24, heavy.
- Body: 14-16 / 20-23.
- Small labels: 11-13, uppercase only for short status labels.

Reasoning:

- Large numerals make bedtime, lock duration, and score instantly scannable.
- Monospaced numerals prevent score/time jitter.
- Letter spacing stays at `0` for native legibility.

## Layout And Spacing

Spacing tokens:

- `6`, `10`, `16`, `22`, `30`, `42`

Structure:

- Header: product name, bedtime target, red-filter-safe status.
- Phase control: one segmented control, not scattered navigation.
- Hero: one dominant `SleepGate` panel with title, copy, metric ring, and progress line.
- Actions: primary commitment action plus a quiet color-filter guide.
- Mechanism: clear timeline for 9:30 PM, 10:30 PM, and 4:30 AM.
- Contextual panels: allowed apps during Wind Down/Sleep Lock, morning capture during Morning.
- Score: simple weekly bar rhythm.

Reasoning:

- The first viewport must show the product premise immediately: bedtime target plus lock state.
- The hero panel prevents the screen from becoming a stack of identical cards.
- The timeline explains mechanism without forcing the user through settings text at night.
- Panels use generous gaps and larger rows because nighttime tap accuracy is worse.

## Containers

Corners are continuous and soft:

- Small: `14`
- Medium: `20`
- Large: `28`
- Hero: `38`
- Pills: `999`

Rules:

- Cards are only for functional clusters: hero, timeline, allowed app rows, morning capture, score.
- Do not nest cards inside cards.
- Avoid bordered white cards and marketing-style floating sections.
- Row targets are at least 44 px high; major actions are 54 px high.

## Buttons And Controls

Buttons:

- Primary: amber fill, black text, 54 px minimum height.
- Quiet: warm surface fill, light text, soft border.
- Danger: muted ember surface and danger border for night-opening logs.
- Segmented phase control: pill container with a filled active tab.
- Morning check-in chips: pill controls with selected state by fill, border, and text contrast.

Reasoning:

- Button choices follow Apple and Material guidance: clear affordance, sufficient hit area, semantic hierarchy.
- Primary action color is warm and visible under red tint.
- The night-opening action is visually serious without becoming alarm-red at bedtime.

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
