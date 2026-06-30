# Development

## Run on iOS Simulator

```sh
npm install
npm run ios
```

The iOS script copies the project to `/tmp/sulav-sleep-tracker-run` before launching. This avoids Expo/RN native build scripts that currently split the checked-out folder name at the space in `Sulav-Sleep Tracker`.

The script also disables React Native prebuilt core for the local simulator build because CocoaPods can fail to validate `React-Core-prebuilt` in this environment with a missing `source` attribute.

## Run locally without launching a simulator

```sh
npm start
```

## Prototype scope

The current app is a single-screen Expo prototype. It has no backend, no persistent storage, and no native app-blocking implementation yet. State resets when the app reloads.

## UI rules

- Read `DESIGN.md` before changing UI. It defines the research-backed palette, layout, motion, containers, and control choices.
- Use warm dark surfaces and rounded continuous corners.
- Avoid sharp white screens, blue-heavy UI, and color-only state indicators.
- Make charts and scores readable under red tint by using text, shape, line weight, and position in addition to color.
- Keep Wind Down mode intentionally sparse: reading, journaling, alarm, and emergency actions only.

## Current design implementation

The current simulator prototype uses a single "Sleep Gate" hero instead of a generic dashboard. It shows the active bedtime phase, commitment metric, lock progress, allowed app shelf, morning capture, and weekly rhythm chart.

The UI uses `expo-linear-gradient` for warm dark depth, `expo-haptics` for native-feeling button feedback, and `react-native-safe-area-context` so scrolled content does not slide under the Dynamic Island/status area. Keep these dependencies unless the design system changes deliberately.
