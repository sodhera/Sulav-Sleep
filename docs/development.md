# Development

SleepBlock is a native iOS SwiftUI app. The old Expo/React Native source was
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

The project currently ships **no test targets** — the `SulavSleepTests`
(Swift Testing) and `SulavSleepUITests` (XCUITest) targets were removed to keep
the build/CI loop fast, so `xcodebuild ... test` has nothing to run.

The app-side test seams were removed too: `MockAuthClient`, the `-uitest-reset`
/ `-uitest-mock-auth` launch arguments, and the `AppEnvironment.isTesting`
gates are gone, so the app always takes its real code paths (widget refresh,
Live Activities, async persistence). `SleepStore.init` still accepts optional
`persistence` / `health` / `screenTime` / `auth` dependencies, so a future test
target can inject fakes without new hooks.

## Tracing

`Log.swift` centralizes observability:

- `AppLog` — category-scoped `os.Logger`s (`app`, `store`, `health`, `ui`,
  `scene`, `intents`). Stream them from the Simulator with:
  ```sh
  xcrun simctl spawn booted log stream --predicate 'subsystem == "com.sulav.sleepblock"'
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
- `RootView.swift`: single `RootScreen` enum (`authLoading` / `onboarding` /
  `auth` / `main`) drives which top-level screen shows, with one animation
  trigger for the crossfade between them. Auth readiness is checked first so
  the onboarding gate knows whether to open on welcome or on the post-sign-in
  quick setup. Entering `.main` is a hard cut
  (`.transaction { $0.disablesAnimations = true }`), not animated — see
  "Authentication" below for why.
- `AuthView.swift`: account methods (Apple, Google, manual email/password),
  split into `AuthMethodsView` (the buttons + email form, single-purpose — the
  mode is fixed by `AuthIntent`, no sign-up/sign-in toggle) and a thin
  `AuthView` wrapper that adds an optional back chevron and safe-area padding.
  `AuthMethodsView` is used two ways: embedded as the final step of the sign-up
  questionnaire (`.signUp`, "Save your sleep plan"), and standalone via
  `AuthView` for the returning-user sign-in path from welcome and the
  post-sign-out gate (`.signIn`, "Welcome back"). The two paths never link to
  each other.
- `Auth/AuthModels.swift`, `Auth/SupabaseAuthClient.swift`,
  `Auth/MockAuthClient.swift`: `AuthProviding` protocol (mirrors
  `SleepHealthProviding`), the real Supabase-backed client, and the test
  double. See "Authentication" below.
- `HomeView.swift`: greeting, schedule, Sleep Now, active sleeping state, wake
  logging, last-night summary, empty states, Health import indicator.
- `ProfileView.swift`: the Profile tab — the app's single "about you" surface.
  Identity (editable name, account email), the sleep record (weekly chart,
  averages, recent nights with source badges, an "All nights" pushed page when
  history exceeds seven), and settings as full pushed pages inside the tab's
  `NavigationStack`: Sleep schedule (`ScheduleScreen`), Blocked apps
  (`BlockedAppsScreen`, in `SleepScreenTime.swift`), plus the Apple Health
  toggle and a quiet Sign out. There is deliberately no "reset all data" action.
  Shared scaffolding lives here too: `SceneScreen` (night scene + transparent
  scroll, system nav bar hidden) and `SubpageHeader` (glass back chevron +
  editorial title, same chrome as onboarding). Also hosts `HealthConnectCard` —
  the dismissable "connect Apple Health" prompt shown when
  `store.shouldPromptHealthConnect` (available, not connected, not waved off).
  This is where Health is offered now that onboarding no longer asks; "Connect"
  calls `enableHealthSync`, the ✕ calls `dismissHealthPrompt` (persisted via
  `Profile.healthPromptDismissed`).
- `OnboardingView.swift`: `OnboardingGateView`, the whole pre-app gate. A
  welcome screen offers two independent paths — "Get started" runs the sign-up
  flow (`OnboardingQuestionsView`: name, sleep struggles, bedtime, wake with a
  live sleep-window readout, and — as the final step — the account creation,
  embedding `AuthMethodsView`); "I already have an account" goes straight to a
  standalone `AuthView` (`.signIn`), followed by the same questions as a quick
  setup when the device has no profile. The two paths are never linked. Apple
  Health is not part of onboarding — it's offered later on Profile (see
  `HealthConnectCard`). `OnboardingQuestionsView` builds its step list
  dynamically: the account step is appended only when the user is not already
  signed in (captured once via `includesAccount`), so it appears on the sign-up
  path but is dropped on the post-sign-in quick setup, where the wake-time
  question becomes the final step (its button reads "Finish" and commits). The
  profile is *not* committed until the account step's auth succeeds — an
  `onChange(store.isAuthenticated)` inside the questionnaire fires
  `completeOnboarding`, so the gate stays mounted (progress bar + back chevron
  intact) through account creation and "back" from it returns to the wake step.
  Navigation is array-index based so the conditional final step is handled
  uniformly. The questionnaire renders only the active step
  (directional slide transitions, thin amber progress bar, glass back chevron)
  and owns the shared lightweight `TimeAdjuster`, used instead of UIKit
  `DatePicker`/wheel controls to avoid first-use hitches during transitions.
  The keyboard is pre-warmed with a hidden `UITextField` only while routing to
  the questionnaire (whose name step auto-focuses), so no phantom keyboard
  flashes on the welcome or account screens. Struggle answers persist to
  `Profile.sleepStruggles` for future personalization.
- `LiquidGlass.swift`: native Liquid Glass wrappers with material fallbacks.
- `SleepBackground.swift`: Core Animation pixel-night scene. It keeps the pixel
  city in separate scrolling/parallaxed depth planes and uses system
  motion-effect parallax instead of CoreMotion polling. Because native `TabView`
  content is opaque, `MainShellView` renders one background inside each tab; the
  scrolling layers use the same global Core Animation phase so switching between
  Home and Profile (or pushing a Profile sub-page, each of which embeds its own
  scene) does not restart the skyline. The view is
  non-interactive (`isUserInteractionEnabled = false`) — it never reacts to
  touch and can't intercept input meant for the UI above it; depth parallax
  comes from the device-tilt motion effect only.
- `SleepAssetCache.swift`: launch-time decode cache for the pixel city layers so
  the first interactive onboarding steps do not pay image decode cost.
- `SleepTheme.swift`: palette, spacing, radius, typography, `Haptics`.
- `SleepFormatting.swift`: date/time/duration formatting.
- `SleepIntents.swift`: App Intents (start sleep, open app).
- `Log.swift`: logging + signpost tracing.

## Product mechanics

- First launch shows the welcome screen with two independent paths. Sign-up:
  name, sleep struggles, bedtime, wake, then account creation as the final step
  of the same flow (progress bar + back throughout) — the questions come first
  deliberately, since users who have invested in a few answers complete sign-up
  at a higher rate, and the profile is committed only once that final account
  step succeeds. Sign-in: a standalone screen, then the same questions as a
  quick setup if the device has no profile (see "Authentication"). The two paths
  do not cross-link; the choice is made on the welcome screen.
- **Apple Health is offered in-app, not during onboarding.** A dismissable
  prompt card sits at the top of Profile until the user connects (or waves it
  off); the Profile settings section keeps the toggle. This avoids a system
  permission sheet interrupting sign-up and puts the ask where sleep data is
  shown.
- **No seeding.** History is empty until the user logs a real night or Apple
  Health has real sleep to import.
- `Sleep Now` writes an active session; `Wake up` logs duration + score, clears
  active, and (if Health is connected) writes the night to Apple Health.
- Profile/Home show a deduplicated merge of local + Health nights.
- Schedule/name edits persist immediately. There is no in-app "reset all data"
  action — sign out is the only account-level exit, and it keeps the local
  profile so signing back in skips the questionnaire.

## Authentication

The account methods (Apple, Google, manual email/password) are backed by a real
Supabase project. On the sign-up path they are the final step of the
questionnaire; on the sign-in path they are a standalone screen from welcome
(and the screen an onboarded-but-signed-out user lands on at the root). Sleep
data itself stays local-first (per `product-brief.md`) — this only adds account
identity on top.
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
- **Authorization gotcha:** `HKHealthStore.requestAuthorization` returns *success*
  merely for presenting the sheet — it returns without error even on "Don't
  Allow", and never reveals *read* grants (privacy). So we do **not** treat a
  clean return as connected; `requestAuthorization()` checks the *share* (write)
  status (`authorizationStatus(for:)`), which HealthKit does expose, and only
  reports connected on `.sharingAuthorized`. Write access is legitimately needed
  anyway (two-way sync writes nights to Health). `isAccessDenied` surfaces
  `.sharingDenied`; once denied, iOS won't re-prompt, so `store.connectHealth()`
  opens system Settings instead of silently no-op'ing. The Settings toggle and
  the Profile `HealthConnectCard` both derive from the real state, so a denial
  never leaves the toggle stuck on.
- In the Simulator, add sleep data in the Health app to see imported nights.

## Liquid Glass rules

- Native `glassEffect` on iOS 26+, `.ultraThinMaterial` fallback otherwise.
- `LiquidGlass.swift` is the only glass compatibility wrapper.
- Interactive glass for tappable controls only.

## Widget & App Group

- `SulavSleepWidgetExtension` (WidgetKit) is embedded in the app and shares data
  via App Group `group.com.sulav.sleepblock`. `SleepWidgetShared.swift`
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
- `OpenSleepHomeIntent`: opens SleepBlock.
- `SulavSleepShortcuts`: exposes both to Shortcuts/Siri/Spotlight.
