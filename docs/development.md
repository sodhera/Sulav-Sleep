# Development

## Run on iOS Simulator

```sh
npm install
npm run ios
```

Expo will start Metro and open the app in the iOS Simulator through Expo Go when available.

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
