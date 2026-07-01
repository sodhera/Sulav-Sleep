# Sulav Sleep Design System

Sulav Sleep should feel like a warm bedside instrument, not a generic wellness dashboard. The interface exists to help someone stop using the phone at night, so the UI must be low-stimulation, legible under a red tint, and direct about the commitment window.

## Native Design Direction

The app is now a SwiftUI iOS app with native Liquid Glass. The previous React Native implementation established the "Lullaby" direction; the Swift migration keeps the product shape while making iOS system materials and interactions the default.

## Product Mood

"Lullaby" is a dreamy deep-indigo night sky with a crescent moon, clouds, stars, and mountains. The scene is the background, not a card. Content floats on top with minimal containers, open text, and hairline dividers.

Motion should stay calm:

- Stars gently twinkle.
- Clouds drift slowly.
- State changes fade and lift over roughly 260-320 ms.
- Press states scale subtly.

## Structure

- Onboarding: intro, name, usual sleep time, usual wake time.
- Home: greeting, tonight's schedule, `Sleep Now`, `Set Bedtime`, last-night summary, and streak.
- Active sleep: elapsed timer, sleep start time, short reassurance, and `Wake up`.
- Reports: weekly wave chart, averages, and history rows.
- Bottom navigation: Home and Reports only; hidden while sleeping and during onboarding.
- Settings sheet: name, schedule, reset.

## Palette

The native palette preserves the React prototype's Lullaby anchors:

- Background gradient: `#2A1C66 -> #241858 -> #170F36`
- Indigo: `#291965`
- Purple: `#533EA8`
- Magenta: `#943EC3`
- Moon: `#F4F1FF`
- White ink: `#FFFFFF`
- Dim ink: white at 74%
- Quiet ink: white at 52%
- Faint ink: white at 30%
- Hairline: white at 10%
- Glass fill: white at 6%

Reasoning:

- The violet night reads dreamy and gentle rather than clinical.
- White primary controls pop cleanly on indigo.
- Native glass provides depth without heavy cards.

## Typography

Use rounded system typography in SwiftUI:

- Hero: `.system(..., weight: .black, design: .rounded)`
- Titles: `.bold` rounded
- Body: `.medium` rounded
- Labels: `.semibold` rounded

Montserrat was appropriate in the Expo prototype, but the native SwiftUI app should lean into iOS system typography unless a custom font becomes product-critical again.

## Layout

Use the 8pt grid:

- `4`, `8`, `12`, `16`, `20`, `24`, `32`, `40`
- Screen margins: `24`
- Major section gaps: `32-40`
- Touch targets: at least `44`
- Primary/secondary actions: about `58-64` tall

## Liquid Glass

All glass behavior is centralized in `ios/SulavSleep/LiquidGlass.swift`.

Rules:

- Use native `glassEffect` on iOS 26+.
- Use `.ultraThinMaterial` fallback for earlier supported iOS versions.
- Use interactive glass only on tappable/focusable elements.
- Keep shapes consistent: capsules for buttons and bottom nav, continuous rounded rectangles for sheets and pickers.
- Do not create custom blur stacks when a native glass/material surface fits.

## Containers

Cards are rare. Use containers only for functional clusters like sheets, time pickers, and tappable controls. Do not put cards inside cards.

Most content should remain cardless:

- Schedule is open text.
- Last-night summary is separated by one hairline.
- Reports history uses divided rows.

## Red-Filter Safety

- Use contrast and hierarchy before hue.
- Avoid blue-only controls.
- Pair colored states with text.
- Keep body copy short and high contrast.
- Use large numerals and clear position for time/score.

## What To Avoid

- Generic wellness card stacks.
- Bright white screens.
- Blue-heavy UI as the main identity.
- Decorative elements that do not support sleep state.
- Tiny tap targets.
- Long educational copy in the nighttime flow.
- Bouncy or reward-like animation.

