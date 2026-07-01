# Development

Sulav Sleep is now a native iOS SwiftUI app. The old Expo/React Native source was removed during the Swift migration; `ios/SulavSleep.xcodeproj` is the source of truth.

## Requirements

- Xcode 26.5 or newer.
- An iOS 26 simulator for the full Liquid Glass appearance.
- iOS 17 is the minimum deployment target. Earlier iOS versions are intentionally out of scope because the app uses Swift Observation and App Intents-era system APIs.

## Run on iOS Simulator

```sh
./scripts/run-ios-simulator.sh
```

Defaults:

- Simulator: `iPhone 17 Pro`
- Scheme: `SulavSleep`
- Configuration: `Debug`
- Derived data: `ios/build/DerivedData`

Override the simulator:

```sh
IOS_SIMULATOR_DEVICE="iPhone 17 Pro Max" ./scripts/run-ios-simulator.sh
```

## Build without launching

```sh
xcodebuild \
  -project ios/SulavSleep.xcodeproj \
  -scheme SulavSleep \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath ios/build/DerivedData \
  build
```

## Architecture

- `SleepStore.swift`: observable app state and user actions.
- `SleepModels.swift`: profile, sessions, active sleep session, tabs, and sheet IDs.
- `SleepPersistence.swift` is folded into `SleepStore.swift`; persistence is UserDefaults-backed JSON using the original storage keys: `sulav.profile.v1`, `sulav.sessions.v1`, and `sulav.active.v1`.
- `SleepMath`: target-window and score calculations ported from the React prototype.
- `RootView.swift`: onboarding gate, tab shell, and bottom navigation.
- `HomeView.swift`: greeting, schedule, Sleep Now, active sleeping state, wake logging, and last-night summary.
- `ReportsView.swift`: weekly wave chart, averages, and history list.
- `Sheets.swift`: schedule editor and settings/reset sheet.
- `LiquidGlass.swift`: native Liquid Glass wrappers with material fallbacks.
- `SleepBackground.swift`: native animated night-sky background.
- `SleepIntents.swift`: App Intents shortcuts for starting sleep and opening the app.

## Product Mechanics

- First launch shows onboarding: intro, name, bedtime, and wake time.
- Completing onboarding seeds a handful of plausible sessions so Reports is meaningful on day one.
- `Sleep Now` writes an active session.
- `Wake up` logs duration and score, clears the active session, and returns the app to the normal Home state.
- Schedule and name edits are persisted immediately.
- Reset clears profile, sessions, and active sleep state.

## Liquid Glass Rules

- Use native `glassEffect` APIs when available on iOS 26+.
- Keep `LiquidGlass.swift` as the only compatibility wrapper for glass styling.
- Interactive glass is for tappable controls only.
- Earlier iOS fallback is `.ultraThinMaterial` with the same shape and spacing.

## App Intents

The first App Intents surface is intentionally narrow:

- `StartSleepIntent`: starts a sleep session without opening the app.
- `OpenSleepHomeIntent`: opens Sulav Sleep.
- `SulavSleepShortcuts`: exposes both actions to Shortcuts/Siri/Spotlight-compatible system surfaces.

If more intents are added, prefer actions with clear outside-the-app value rather than mirroring every screen.

