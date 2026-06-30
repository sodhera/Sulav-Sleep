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

- Use warm dark surfaces and rounded continuous corners.
- Avoid sharp white screens, blue-heavy UI, and color-only state indicators.
- Make charts and scores readable under red tint by using text, shape, line weight, and position in addition to color.
- Keep Wind Down mode intentionally sparse: reading, journaling, alarm, and emergency actions only.
