# Development

Sulav Sleep is a native iOS SwiftUI app. The old Expo/React Native source was
removed during the Swift migration; `ios/SulavSleep.xcodeproj` is the source of
truth.

## Requirements

- Xcode 26.5 or newer.
- An iOS 26 simulator for the full Liquid Glass appearance.
- iOS 17 is the minimum deployment target. Earlier iOS is intentionally out of
  scope because the app uses Swift Observation, App Intents, and iOS 16-era
  HealthKit sleep-stage APIs.

## Run on iOS Simulator

```sh
./scripts/run-ios-simulator.sh
```

Defaults: `iPhone 17 Pro`, scheme `SulavSleep`, `Debug`, derived data in
`ios/build/DerivedData`. Override the device with `IOS_SIMULATOR_DEVICE`.

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

## Tests

The `SulavSleep` scheme runs two test targets. Run everything with:

```sh
xcodebuild \
  -project ios/SulavSleep.xcodeproj \
  -scheme SulavSleep \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath ios/build/DerivedData \
  test
```

Filter with `-only-testing:SulavSleepTests` or `-only-testing:SulavSleepUITests`.

- **SulavSleepTests** (Swift Testing) — pure/unit coverage:
  - `SleepMathTests`: sleep-window (incl. past-midnight) and score math.
  - `SleepNightBuilderTests`: grouping Health samples into nights and the
    overlap-safe union-minutes calculation.
  - `SleepMergeTests`: local vs. HealthKit dedupe (Health wins per night).
  - `SleepFormattingTests`: duration/clock formatting and minute round-trips.
  - `SleepStoreTests`: onboarding (no seeded data), sleep/wake, streak, Health
    enable/deny/disable, reset, and persistence round-trips. Uses
    `MockHealthService` and an isolated in-memory `UserDefaults` suite
    (`TestSupport.swift`).
  - `AuthTests`: sign-in with each provider, manual sign-up/sign-in, sign-out,
    error surfacing, session-restore, and `AppAccount` persistence
    round-trips. Uses `MockAuthClient` (`Auth/MockAuthClient.swift`).
- **SulavSleepUITests** (XCUITest) — onboarding → auth → Home, Sleep → Wake,
  and log-a-night → Reports (`AuthUITests`, `OnboardingUITests`,
  `SleepFlowUITests`). The app wipes persisted state when launched with
  `-uitest-reset`, and swaps in `MockAuthClient` when launched with
  `-uitest-mock-auth` so UI runs are deterministic and never hit the network.

## Tracing

`Log.swift` centralizes observability:

- `AppLog` — category-scoped `os.Logger`s (`app`, `store`, `health`, `ui`,
  `scene`, `intents`). Stream them from the Simulator with:
  ```sh
  xcrun simctl spawn booted log stream --predicate 'subsystem == "com.anonymous.sulav-sleep"'
  ```
- `AppSignpost` — `OSSignposter`s for Instruments. `OSSignposter.measure`
  wraps operations in signpost intervals; the HealthKit import is traced as
  `ImportHealthKit`, visible in the Points of Interest / Time Profiler
  instruments. Log lines avoid PII (counts and durations, never the name).

## Architecture

- `SleepStore.swift`: observable app state and user actions; also holds
  `SleepPersistence` (UserDefaults JSON, keys `sulav.profile.v1`,
  `sulav.sessions.v1`, `sulav.active.v1`), the pure `SleepMerge` (local/Health
  dedupe), and `SleepMath`. User-visible state mutates immediately; in normal app
  runs persistence and side effects are deferred one main-queue turn so button
  taps can render their transition before JSON/UserDefaults or Screen Time work.
  Tests keep persistence synchronous for deterministic assertions.
- `SleepModels.swift`: profile, sessions (`SleepSource` tagged), active session,
  tabs, sheet IDs, and `HealthSyncState`. Codable is decode-safe for records
  written before newer fields existed.
- `SleepHealthKit.swift`: `SleepHealthProviding` protocol, the real
  `HealthKitService`, a `DisabledHealthService` no-op, the `SleepHealth`
  factory, and the pure `SleepNightBuilder`.
- `SleepScreenTime.swift`: `ScreenTimeControlling` protocol + `ScreenTimeService`
  (FamilyControls auth + ManagedSettings shield) and `LockdownSettingsView`
  (FamilyActivityPicker). Device-only; `.unavailable` no-op on Simulator.
- `SleepWidgetShared.swift`: App Group summary types + read/write, shared with
  the widget target.
- `SleepModeView.swift`: immersive black/red sleep-mode takeover.
- `RootView.swift`: single `RootScreen` enum (`onboarding` / `authLoading` /
  `auth` / `main`) drives which top-level screen shows, with one animation
  trigger for the crossfade between them. Entering `.main` is a hard cut
  (`.transaction { $0.disablesAnimations = true }`), not animated — see
  "Authentication" below for why.
- `AuthView.swift`: the post-onboarding sign-up/sign-in screen (Apple,
  Google, manual email/password).
- `Auth/AuthModels.swift`, `Auth/SupabaseAuthClient.swift`,
  `Auth/MockAuthClient.swift`: `AuthProviding` protocol (mirrors
  `SleepHealthProviding`), the real Supabase-backed client, and the test
  double. See "Authentication" below.
- `HomeView.swift`: greeting, schedule, Sleep Now, active sleeping state, wake
  logging, last-night summary, empty states, Health import indicator.
- `ReportsView.swift`: weekly chart, averages, history with source badges,
  empty state.
- `OnboardingView.swift`: intro, name, bedtime, wake, and the Apple Health
  connect step. It renders only the active onboarding step and owns the shared
  lightweight `TimeAdjuster`, used instead of UIKit `DatePicker`/wheel controls
  to avoid first-use hitches during transitions. The intro step pre-warms the
  UIKit keyboard stack with a hidden `UITextField`, and the name step
  auto-focuses after the transition so the first keyboard appearance is absorbed
  into the step change without stopping the background animation.
- `Sheets.swift`: schedule editor and settings (name, schedule, Health toggle,
  reset).
- `LiquidGlass.swift`: native Liquid Glass wrappers with material fallbacks.
- `SleepBackground.swift`: Core Animation pixel-night scene. It keeps the pixel
  city in separate scrolling/parallaxed depth planes and uses system
  motion-effect parallax instead of CoreMotion polling. Because native `TabView`
  content is opaque, `MainShellView` renders one background inside each tab; the
  scrolling layers use the same global Core Animation phase so switching between
  Home and Reports does not restart the skyline. Dragging empty background space
  manually drives the same depth offsets for Simulator inspection, where real
  tilt is not available.
- `SleepAssetCache.swift`: launch-time decode cache for the pixel city layers so
  the first interactive onboarding steps do not pay image decode cost.
- `SleepTheme.swift`: palette, spacing, radius, typography, `Haptics`.
- `SleepFormatting.swift`: date/time/duration formatting.
- `SleepIntents.swift`: App Intents (start sleep, open app).
- `Log.swift`: logging + signpost tracing.

## Product mechanics

- First launch shows onboarding: intro, name, bedtime, wake, Apple Health,
  then sign-up/sign-in (see "Authentication").
- **No seeding.** History is empty until the user logs a real night or Apple
  Health has real sleep to import.
- `Sleep Now` writes an active session; `Wake up` logs duration + score, clears
  active, and (if Health is connected) writes the night to Apple Health.
- Reports/Home show a deduplicated merge of local + Health nights.
- Schedule/name edits persist immediately. Reset clears everything.

## Authentication

Onboarding is followed by a sign-up/sign-in gate (Apple, Google, manual
email/password), backed by a real Supabase project. Sleep data itself stays
local-first (per `product-brief.md`) — this only adds account identity on top.
See `docs/auth-setup.md` for the one-time external setup (Supabase project,
Apple Developer capability, Google Cloud OAuth client).

- **Apple** — native `ASAuthorizationAppleIDProvider` / `SignInWithAppleButton`
  → Supabase's `signInWithIdToken`. No Supabase-side Apple config needed.
- **Google** — Supabase's OAuth web flow (`ASWebAuthenticationSession`), not
  the Google SDK. Avoids a second SPM dependency and a
  `GoogleService-Info.plist`; opens a system sheet instead of app-switching to
  the native Google app.
- **Manual** — Supabase email/password (`signUp`/`signIn`).
- **Config**: `Config.xcconfig` (gitignored; copy from
  `Config.xcconfig.example`) holds `SUPABASE_URL`/`SUPABASE_ANON_KEY`, pulled
  in via `Secrets.xcconfig` (committed, `#include?`s `Config.xcconfig` so the
  project still builds without it — auth calls just fail until it exists) and
  exposed to the app through `Info.plist` build-setting substitution, read at
  runtime by `SupabaseConfig` in `Auth/SupabaseAuthClient.swift`.
- **Session storage**: `supabase-swift`'s `AuthClient` stores the real session
  token in the Keychain by default. `SleepStore` only persists the non-secret
  `AppAccount` (id/email/provider) to the same UserDefaults-JSON pattern as
  everything else (key `sulav.account.v1`), purely for optimistic UI paint
  before the async Keychain session-restore check (`SleepStore.restoreSession`)
  completes.
- **UI test AutoFill gotcha**: a real `SecureField` triggers iOS's native
  "Save Password?" sheet, which is a separate-process system overlay that
  covers the app and can't be reliably dismissed via
  `addUIInterruptionMonitor`. `AuthView`'s email/password fields use
  `.textContentType(.oneTimeCode)` when `AppEnvironment.isTesting` to opt out
  of that prompt in test builds only — production users still get the native
  save-password experience.

## HealthKit

- Entitlement `com.apple.developer.healthkit` + `NSHealth{Share,Update}Usage`
  strings in `Info.plist`.
- Reads/writes `HKCategoryType(.sleepAnalysis)`. Reading sums the `asleep*`
  stages into per-night union minutes; writing stores `asleepUnspecified`.
- The app is fully functional if Health is denied or unavailable — local logging
  is always the fallback, which is why `HealthKitService` sits behind a protocol
  with a `DisabledHealthService` and a `MockHealthService` (tests).
- In the Simulator, add sleep data in the Health app to see imported nights.

## Liquid Glass rules

- Native `glassEffect` on iOS 26+, `.ultraThinMaterial` fallback otherwise.
- `LiquidGlass.swift` is the only glass compatibility wrapper.
- Interactive glass for tappable controls only.

## Widget & App Group

- `SulavSleepWidgetExtension` (WidgetKit) is embedded in the app and shares data
  via App Group `group.com.anonymous.sulav-sleep`. `SleepWidgetShared.swift`
  (the summary types + read/write) is a member of both targets.
- `SleepStore` writes the summary and calls `WidgetCenter.reloadAllTimelines()`
  on every history change — **except under tests**. WidgetKit reloads / App
  Group writes stall the XCTest-monitored app launch, so `updateWidget()` is
  guarded by `AppEnvironment.isTesting` (set for the unit-test host env and the
  `-uitest-reset` UI-test arg). Real runs are unaffected.

## Sleep lockdown build specifics

- Screen Time needs `com.apple.developer.family-controls`, which is applied to
  **device builds only** via `SulavSleep-device.entitlements` and the
  `CODE_SIGN_ENTITLEMENTS[sdk=iphoneos*]` build setting. The base
  `SulavSleep.entitlements` (Simulator) has HealthKit + App Group only, so the
  Simulator builds, tests, and runs normally.
- To enable real enforcement: request the Family Controls capability for the dev
  account, then build/run on a device. See `docs/roadmap-lockdown-and-widget.md`.

## App Intents

- `StartSleepIntent`: starts a session without opening the app.
- `OpenSleepHomeIntent`: opens Sulav Sleep.
- `SulavSleepShortcuts`: exposes both to Shortcuts/Siri/Spotlight.
