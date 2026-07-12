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

### Capture the subscription review screenshot

App Store Connect asks for a private review screenshot of the in-app purchase
screen before live subscription metadata may be available. Debug builds expose
a deterministic version of the real SwiftUI paywall with representative plans:

```sh
xcrun simctl launch booted com.sulav.sleepblock -review-paywall
xcrun simctl io booted screenshot /tmp/SleepBlock-Paywall-Review.png
```

The route and its plan data are compiled only under `DEBUG`; Release builds
always use RevenueCat and cannot activate it. The representative prices mirror
the launch configuration ($59.99 annual / $5.99 monthly) and should be updated
before capture if App Store Connect pricing changes. The screenshot is review
evidence only and must not be used as a public App Store marketing screenshot.

### Preview the Screen Time primer

The permission primer (`ScreenTimePrimerView` — the mock-dialog gate between
the paywall and Main) never fires on the simulator, where Family Controls
reports `.unavailable`. A DEBUG-only launch argument renders it
deterministically:

```sh
xcrun simctl launch booted com.sulav.sleepblock -review-screentime-primer
```

Its CTA resolves "denied" on the simulator and falls through to the normal
root. On a real device the gate shows once per install (marker
`sulav.screenTimePrimer.v1`, container-backed so a reinstall re-primes; see
`SleepStore.needsScreenTimePrimer`).

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

## Swift package dependencies

The app links Supabase's `Auth` product and RevenueCat's `RevenueCat` product
through Swift Package Manager. The Xcode project is the source of truth for
both package declarations. The project and the compatibility workspace each
have a checked-in `Package.resolved`; keep the two lockfiles identical so the
same dependency graph is used whether a developer opens
`SulavSleep.xcodeproj` or `SulavSleep.xcworkspace`.

If Xcode reports `Missing package product 'Auth'` or `Missing package product
'RevenueCat'`, resolve the graph from the repository root before changing the
target's Frameworks list:

```sh
xcodebuild \
  -resolvePackageDependencies \
  -workspace ios/SulavSleep.xcworkspace \
  -scheme SulavSleep \
  -derivedDataPath ios/build/DerivedData
```

This refreshes an incomplete local checkout and updates the workspace lockfile
from the package references declared by the project. A successful resolution
must list both `Supabase` and `RevenueCat` under `Resolved source packages`.

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
  The tab body (`ProfileRootScreen`) is identity (editable name, account email)
  plus the sleep record (the `RecordBars` weekly chart — the widgets' 7-slot
  bar rhythm with a target hairline and hairline stubs for unlogged nights —
  averages, recent nights with source badges and trailing durations, an
  "All nights" pushed page when history exceeds seven). A gear in the
  top-right opens `SettingsModal` via `.fullScreenCover`; the body carries no
  configuration itself. `SettingsModal` is a full-screen cover with its own
  `NavigationStack`: Sleep schedule (`ScheduleScreen`), Blocked apps
  (`BlockedAppsScreen`, in `SleepScreenTime.swift`) push as full pages inside
  it, alongside the Apple Health toggle and a quiet Sign out (which dismisses
  the cover before `signOut` so it doesn't tear down as the root swaps to
  onboarding). There is deliberately no "reset all data" action. Shared
  scaffolding lives here too: `SceneScreen` (night scene + readability scrim +
  transparent scroll, system nav bar hidden) and `SubpageHeader` (glass back
  chevron + editorial title, same chrome as onboarding). Because `SceneScreen`
  hides the system nav bar, UIKit would normally disable the interactive
  edge-swipe-back gesture (it's tied to the visible bar); a global
  `UINavigationController: UIGestureRecognizerDelegate` extension in
  `AppDelegate.swift` re-points the `interactivePopGestureRecognizer` delegate
  so swipe-to-go-back works on every pushed page, while `gestureRecognizer`
  `ShouldBegin` still refuses to fire at a stack root. Also hosts
  `HealthConnectCard` — the dismissable "connect Apple Health" prompt shown when
  `store.shouldPromptHealthConnect` (available, not connected, not waved off).
  This is where Health is offered now that onboarding no longer asks; "Connect"
  calls `enableHealthSync`, the ✕ calls `dismissHealthPrompt` (persisted via
  `Profile.healthPromptDismissed`).
- `OnboardingView.swift`: `OnboardingGateView`, the whole pre-app gate. A
  welcome screen offers two independent paths — "Get started" runs the sign-up
  flow (`OnboardingQuestionsView`: name, goal, sleep struggles, time-sink
  apps, late-night phone time, wake feeling, bedtime, wake with a live
  sleep-window readout, the plan reveal, and — as the final step — the account
  creation, embedding `AuthMethodsView`); "I already have an account" goes
  straight to a standalone `AuthView` (`.signIn`), followed by the same
  questions as a quick setup when the device has no profile. The two paths are
  never linked. Apple Health is not part of onboarding — it's offered later on
  Profile (see `HealthConnectCard`). Single-select questions (goal, phone
  time, feeling — `SleepGoal`/`LateNightPhoneTime`/`WakeFeeling` in
  `SleepModels.swift`) gate Next until answered; multi-selects allow zero.
  The **plan step** (`PlanStep`) runs a ~1.8s "Building your sleep plan…"
  beat (`startPlanBuild`, cancelled if the user backs out mid-build, sticky
  once revealed) before crossfading to the personalized summary; its "I'm
  ready" CTA advances to the account step (or commits directly on the
  quick-setup path, where the plan step is the final one). All answers travel
  as one `OnboardingAnswers` value into `store.completeOnboarding`.
  `OnboardingQuestionsView` builds its step list dynamically: the account
  step is appended only when the user is not already signed in (captured once
  via `includesAccount`), so it appears on the sign-up path but is dropped on
  the post-sign-in quick setup. The profile is *not* committed until the
  account step's auth succeeds — an `onChange(store.isAuthenticated)` inside
  the questionnaire fires `completeOnboarding`, so the gate stays mounted
  (progress bar + back chevron intact) through account creation and "back"
  from it returns to the plan step. Navigation is array-index based so the
  conditional final step is handled uniformly. The questionnaire renders only the active step
  (directional slide transitions, thin amber progress bar, glass back chevron),
  top-anchors the prompt 32pt below that header, vertically centers the answer
  controls in the remaining flexible region, and keeps the action pinned at
  the bottom. The centering spacers collapse when a tall answer group needs
  room. The questionnaire also owns the shared lightweight `TimeAdjuster`,
  used instead of UIKit
  `DatePicker`/wheel controls to avoid first-use hitches during transitions.
  The keyboard is pre-warmed in two stages: a flash-free framework load while
  the onboarding gate idles (`Keyboard.warmFrameworks()` — become + resign
  first responder in the same runloop turn, so nothing presents), then the
  real presented prewarm (`Keyboard.prewarm()`) only while routing to the
  questionnaire, masked by the transition into the auto-focusing name step.
  One stage alone wasn't enough: prewarming only at the "Get started" tap ran
  the whole keyboard cold path during the route transition (visible jank,
  first keystrokes lagging), and a presented prewarm on the welcome screen
  would flash a phantom keyboard. Struggle answers persist to
  `Profile.sleepStruggles` for future personalization.
- `LiquidGlass.swift`: native Liquid Glass wrappers with material fallbacks.
- `SleepBackground.swift`: Core Animation pixel-night scene, plus
  `SceneReadabilityScrim` — a full-bleed vertical gradient (clear through the
  upper sky, fading to ~80% deep-navy at the bottom) layered between the scene
  and UI content so light text stays legible over the lit skyline. It keeps the
  pixel city in separate scrolling/parallaxed depth planes and uses system
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
- `SleepTheme.swift`: palette, spacing, radius, typography, `Haptics`, and
  `RisingZs` — the animated rising-z chain (the icon's ZZZ, alive),
  parameterized by color and scale. It runs full-size in emberDim on the
  sleep screen (`SleepModeView`) and in gold on `SlothBrandMark`
  (`OnboardingView.swift` — app target only, since the mark needs `CityPhase`
  and the Home sloth art), the brand mark shown on the welcome screen, the
  standalone "Welcome back" sign-in screen, and the questionnaire header's
  top-right (hidden chevron-twin) slot.
- `SleepFormatting.swift`: date/time/duration formatting.
- `SleepIntents.swift`: App Intents (start sleep, open app).
- `Log.swift`: logging + signpost tracing.

## Product mechanics

- First launch shows the welcome screen with two independent paths. Sign-up:
  name, goal, sleep struggles, time-sink apps, late-night phone time, wake
  feeling, bedtime, wake, the plan reveal, then account creation as the final
  step of the same flow (progress bar + back throughout) — the questions come
  first deliberately, since users who have invested in a few answers complete
  sign-up at a higher rate; the plan reveal turns those answers into a
  personalized summary the account step then "saves" and the paywall unlocks;
  and the profile is committed only once that final account step succeeds.
  Sign-in: a standalone screen, then the same questions as a quick setup if
  the device has no profile (see "Authentication"). The two paths do not
  cross-link; the choice is made on the welcome screen.
- **The time-sink question** ("Which apps keep you up?") collects app *names*
  (`TimeSinkApp` raw values on `Profile.timeSinkApps`), deliberately not a
  `FamilyActivitySelection` — the system picker needs Screen Time
  authorization, and a permission sheet mid-sign-up is friction (the same rule
  that keeps Apple Health out of onboarding). The answer personalizes the
  paywall's lock line; the real lockdown selection is still made on the
  Blocked apps screen.
- **SleepBlock is a subscription app.** After onboarding, a hard paywall (see
  "Subscription (RevenueCat)") stands between the questionnaire and Main.
- **The Screen Time primer** (`ScreenTimePrimerView`, SleepScreenTime.swift)
  is the last gate before Main once the entitlement resolves: a mock of the
  iOS permission dialog with an amber "Tap Allow" arrow, whose CTA fires the
  real `AuthorizationCenter` request and, when granted, chains straight into
  the `FamilyActivityPicker`. One-shot **per install** — the seen-marker
  (`sulav.screenTimePrimer.v1`) lives in the wiped-on-delete container, so a
  reinstall (where iOS dropped the authorization) primes again. It completes
  on grant, deny, or "Not now"; the Blocked apps screen stays the fixup path.
  `SleepStore.needsScreenTimePrimer` gates it in `RootView` (the store also
  mirrors the marker observably, since live `authorizationStatus` reads are
  invisible to `@Observable` tracking).
- **Apple Health is offered in-app, not during onboarding.** A dismissable
  prompt card sits at the top of Profile until the user connects (or waves it
  off); the Profile settings section keeps the toggle. This avoids a system
  permission sheet interrupting sign-up and puts the ask where sleep data is
  shown.
- **No seeding.** History is empty until the user logs a real night or Apple
  Health has real sleep to import.
- `Sleep Now` writes an active session; `Wake up` logs the duration, clears
  active, and (if Health is connected) writes the night to Apple Health.
  Duration is the app's only metric — the 0–100 sleep score is retired
  (old records' `score` keys are ignored on decode; "on track" for the
  streak now means ≥85% of the sleep target).
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

- **Reusing an already-registered email/identity on the sign-up path**: Apple
  and Google don't distinguish sign-up from sign-in server-side —
  `signInWithIdToken`/`signInWithOAuth` find-or-create by provider identity, so
  reusing an existing Apple/Google account on "Get started" silently signs the
  user into their *existing* account instead of erroring. `SupabaseAuthClient`
  detects this (`AuthResult.isNewAccount`, comparing the Supabase user's
  `createdAt`/`lastSignInAt` — GoTrue has no explicit flag for this grant type)
  and `OnboardingQuestionsView` discards the just-answered questionnaire in
  that case rather than overwriting the original profile with it
  (`onExistingAccountNeedsSetup`, `SleepStore.lastSignInWasNewAccount`). If the
  device has no local profile at all (fresh device/reinstall) *and* the account
  has no cloud profile to restore (see "Cloud profile sync"), it falls back to
  the same no-account-step quick setup used on the sign-in path, by remounting
  `OnboardingQuestionsView` (`OnboardingGateView`'s `questionsInstanceID`).
  Manual email/password can't do this silently — a duplicate `signUp` either
  gets Supabase's no-session anti-enumeration response or an explicit
  `user_already_exists` error, never a session, so the answers are already
  discarded there with no extra handling needed; the user has to sign in with
  their real password instead.
- **Apple** — native `ASAuthorizationAppleIDProvider` (presented programmatically,
  not via `SignInWithAppleButton`, so the button can be app-styled) →
  Supabase's `signInWithIdToken`. No Supabase-side Apple config needed. The
  `AppleSignInCoordinator` retains **both the `ASAuthorizationController` and
  itself** until the delegate fires; `ASAuthorizationController` does not keep
  itself alive between `performRequests()` and its callback, so without this an
  already-authorized Apple ID (which skips the consent sheet and resolves fast)
  could deallocate mid-flow and leave the button spinning forever with no
  callback.
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
- **Cloud profile sync**: the onboarding profile (name, schedule, struggles —
  `RemoteProfile`, the account-portable slice of `Profile`) is mirrored into
  Supabase **auth user metadata** under the `sleep_profile` key: no separate
  table, no RLS policy, nothing new to configure. It's pushed best-effort by
  `SleepStore.syncRemoteProfile()` after onboarding and name/schedule edits,
  and restored by `adoptSignedInAccount` on sign-in (and by `restoreSession`
  at launch, capped at 5s) whenever the device has no local profile — this is
  what lets a returning user sign in after a reinstall and land straight in
  the app instead of re-answering the questionnaire. Local-first still holds:
  when both copies exist, the device's wins; accounts predating sync get their
  cloud copy seeded on first sign-in. The launch-time backfill (seeding a
  missing cloud copy for an already-signed-in device) runs in a background
  task and is remembered per account once the cloud copy is confirmed
  (`sulav.cloudSeedChecked.v1`, cleared by `reset()`), so it doesn't re-query
  Supabase at every app open — the app stays fully offline on a routine
  launch. Device-bound settings (Health sync,
  Screen Time lockdown, prompt dismissals) deliberately do **not** sync — they
  hinge on per-device permission grants. Sleep *history* doesn't sync either
  (per `product-brief.md`).
- **Shared-device account switch**: `sulav.lastAccountID.v1` records who signed
  in last and — unlike the cached `AppAccount` — survives sign-out, so
  `adoptSignedInAccount` can tell a returning user (local data kept) from a
  *different* account signing in (previous user's profile and nights wiped
  before the new profile is hydrated). It is cleared by `reset()` (account
  deletion), since there's no previous user left to protect.
- **Offline-first launch**: `currentAccount` reads identity straight from the
  stored Keychain session and never touches the network. Launch is gated on
  this check (`RootView` shows a neutral state until `isAuthReady`), and going
  through `client.session` instead would block every cold open on a
  token-refresh round-trip (Supabase access tokens expire hourly), which is
  exactly the "app takes ages to load" failure mode. An expired access token
  is fine — identity doesn't change when a token expires; the SDK refreshes it
  on the next authenticated call — and airplane-mode launches keep working.
  The trade-off — a server-side-revoked session stays "signed in" until an
  authenticated call fails — is the standard one. Net effect: a normal launch
  makes **zero** network requests (the only exceptions are the one-time
  restore/seed paths under "Cloud profile sync").
- **Error surfacing**: `SupabaseAuthClient.mapError` translates GoTrue's
  structured `ErrorCode`s (invalid credentials, email exists, unconfirmed
  email, weak password, rate limit) into user-facing `AuthError` cases instead
  of sniffing message strings. `AuthError.confirmationEmailSent` (email
  sign-up when the project requires confirmation) is a *notice*, not a
  failure: `SleepStore.authMessageIsNotice` flags it and `AuthMethodsView`
  renders it amber instead of red.
- **Reset on reinstall**: iOS wipes the app container on delete but keeps
  Keychain items, so a surviving Supabase session would otherwise silently sign
  a user back in on a "fresh" install — dropping them onto the nameless
  quick-setup instead of the welcome screen. `SleepStore.restoreSession` guards
  on a launch marker (`sulav.hasLaunched.v1`, stored in the wiped container):
  when it's absent (first launch after install), it clears the stale session
  via `AuthProviding.clearLocalSession()` before restoring, then plants the
  marker. `clearLocalSession` uses Supabase's `.local` sign-out scope — a
  local-only Keychain clear with **no** server round-trip, so it can't stall
  launch on a slow/missing network (unlike the global `signOut()` used for a
  user-initiated sign-out). The marker is deliberately **not** cleared by
  `SleepPersistence.reset()`: an in-app sign-out is not a reinstall.
- **UI test AutoFill gotcha**: a real `SecureField` triggers iOS's native
  "Save Password?" sheet, which is a separate-process system overlay that
  covers the app and can't be reliably dismissed via
  `addUIInterruptionMonitor`. `AuthView`'s email/password fields use
  `.textContentType(.oneTimeCode)` when `AppEnvironment.isTesting` to opt out
  of that prompt in test builds only — production users still get the native
  save-password experience.

## Subscription (RevenueCat)

SleepBlock is a subscription app with a **hard paywall + free trial**: after
the sign-up questionnaire commits (or a returning unsubscribed user signs in),
`RootView` shows `PaywallView` instead of Main — no ✕, no skip. The primary
action starts the App Store free-trial intro offer on the annual plan;
starting the trial or subscribing is the only way in.

Code map (all behind the app's usual protocol seam):

- `SleepSubscription.swift` — `SubscriptionProviding` +
  `RevenueCatSubscriptionService`. Streams `CustomerInfo` →
  `EntitlementState` (`unknown` / `entitled` / `notEntitled`), maps the
  current offering's packages to SDK-free `SleepPlan` values, runs
  purchase/restore, and links the RevenueCat identity to the Supabase
  account id on sign-in/out (`logIn`/`logOut`) so a subscription follows the
  user across devices.
- `SleepStore` — `entitlement`, `needsPaywall` (signed in + onboarded +
  *resolved* not-entitled), and `fetchPlans`/`purchase`/`restorePurchases`
  intents for the paywall.
- `PaywallView.swift` — the screen (see DESIGN.md "Paywall").
- `RootView` — the gate. It never acts on `.unknown`: it holds the splash
  while the entitlement resolves (RevenueCat replays its cached
  `CustomerInfo` immediately, so this is normally instant — subscribers
  resolve offline too), capped at 4s, after which unknown **fails open** to
  Main; locking a paying user out over a network hiccup is worse than one
  free session. The sleep-mode overlay outranks the paywall, so an active
  night's wake/cancel (and the Screen Time shield teardown) stay reachable
  regardless of subscription state.

Configuration — the same plumbing as the Supabase keys:

1. `REVENUECAT_API_KEY` in the gitignored `ios/SulavSleep/Config.xcconfig`
   (declared empty in the committed `Secrets.xcconfig`, exposed through
   `Info.plist`). It's RevenueCat's *public* Apple App Store SDK key
   (`appl_…`) — client-safe, like the Supabase anon key.
2. **An empty key is dev mode**: `isConfigured == false`, the store resolves
   `.entitled` at init, and the paywall never shows — the Simulator and fresh
   clones run with zero setup.

One-time external setup (dashboards):

1. **App Store Connect** — create the subscription group and two
   auto-renewable products (suggested ids `sleepblock.pro.annual`,
   `sleepblock.pro.monthly`), with a **7-day free trial intro offer on the
   annual** product (the paywall CTA derives "Start N nights free" from the
   product's intro offer, so the trial length lives in ASC, not code).
2. **RevenueCat** — create the project + Apple app, import the products,
   create entitlement **`pro`** (the id `SleepSubscription.entitlementID`
   checks) attached to both products, and a **current Offering** containing
   an `$rc_annual` and `$rc_monthly` package. The paywall renders whatever
   the current offering carries — plans, prices, and trial all come from the
   dashboard.
3. Put the app's public Apple API key in `Config.xcconfig`.

Testing purchases: real transactions need a device + sandbox Apple ID (or
TestFlight). In the Simulator the usual route is a StoreKit configuration
file synced from App Store Connect (Xcode scheme → Options → StoreKit
Configuration) once the products exist in ASC; RevenueCat picks it up
automatically.

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
  The fallback honors the same `tint` parameter as a wash over the material.
- `LiquidGlass.swift` is the only glass compatibility wrapper.
- Interactive glass for tappable controls only.
- Never paint manual capsule fills or border strokes on top of a glass
  surface — the glass owns its chrome on 26+, and the fallback draws its own
  hairline. Strokes at call sites are reserved for meaning (selection) or
  branding (the white provider pills, which are not glass).
- Touch-driven `Button`s drive their press reaction from a custom `ButtonStyle`
  that owns `configuration.isPressed`, NOT a `.buttonStyle(.plain)` button
  with a bare `.glassEffect(.interactive())` (the plain button swallows the
  touch, so the glass never sees the press and the control feels dead). The
  style layers a springy `isPressed` scale (guaranteed visible reaction) on
  top of interactive Liquid Glass (real material morph on device):
  `GlassCircleButtonStyle` for `GlassIconButton`, `GlassCapsuleButtonStyle`
  (internal, in `LiquidGlass.swift`) for `LiquidPrimaryButton` (amber tint),
  `LiquidSecondaryButton` (no tint), and sleep mode's "Back to sleep" (no
  tint). The hand-drawn `LiquidButtonStyle` is the pre-26 fallback only.
  Controls that aren't a `Button` — `SlideToSleepButton`'s knob and
  `EmberHoldButton`'s "Hold to wake", both driven by a manual `DragGesture` —
  apply `.glassEffect(.interactive())` directly instead, since their own
  gesture state (`isHolding`/drag offset) already guarantees the reaction the
  same way `isPressed` does for a `ButtonStyle`.
- Buttons squish-and-settle on press; only genuine drag controls
  (`SlideToSleepButton`'s knob) get the finger-follow morph. `EmberHoldButton`
  keeps its ratchet-driven scale for the same reason.
- A `glassEffect` must be applied to an already-*sized* shape (frame set
  before the modifier, or the shape passed to `in:` matches the intended
  size) — applying it to a flexible/unsized shape renders as a displaced,
  bright-rimmed "ghost" echo of the control (hit this on the slide-to-sleep
  knob: the fix was framing the circle before `.glassEffect`, and dropping
  the `GlassEffectContainer` around the track+knob since the track isn't
  glass and the container was only producing the echo).
- Sibling glass shapes that read as one set are wrapped in
  `LiquidGlassContainer` (`GlassEffectContainer` on 26+) so their glass
  blends: Home's schedule chips, onboarding's struggle rows. Don't wrap a
  glass control together with a non-glass sibling (see the ghost-echo note
  above) — only sibling glass shapes benefit.
- `GlassIconButton`'s glass region is the full `size` circle (no content
  inset math). Sizes: 56pt gear/close, 44pt back chevron.
- `EmberHoldButton`'s non-prominent case ("Hold to cancel") is deliberately
  chromeless — no glass, no fill — so it reads as a quiet text link. Don't
  add glass there; it would fight the "rare, irreversible exit" language in
  DESIGN.md.

## Widget & App Group

- `SulavSleepWidgetExtension` (WidgetKit) is embedded in the app and shares data
  via App Group `group.com.sulav.sleepblock`. `SleepWidgetShared.swift`
  (the summary types + read/write) is a member of both targets.
- Families: home-screen small (tonight: bedtime countdown → past-bedtime →
  asleep), medium (last night's duration + 7-night bars), large (bars +
  tonight footer), and lock-screen accessories (circular/rectangular/inline). The sloth mascot
  carries tonight's state on every home-screen family (awake / drowsy /
  ember-asleep), and while a session runs all three families switch to one
  shared OLED-black "sleep face". See the "Widgets" section of `DESIGN.md`
  for the visual rules.
- The extension has its own asset catalog,
  `SulavSleepWidget/WidgetAssets.xcassets`, holding only the three sloth
  poses at widget scale (720px). It is generated, never hand-edited, by
  `scripts/generate-widget-assets.py`, which downscales the app's
  `HomeSlothAwake`/`HomeSlothDrowsy`/`NightSloth` imagesets — re-run it after
  `scripts/generate-app-icon.py` so the catalogs stay in sync. The app's
  `Images.xcassets` is deliberately *not* a member of the widget target
  (it would compile the whole pixel-art city into the appex).
- `SleepWidgetSummary` carries `bedtimeMinutes`/`wakeMinutes`/`asleepSince`/
  `isSignedIn` on top of the history fields; all are optionals, so summaries
  written before they existed still decode (key stays `v1`; readers treat a
  missing `isSignedIn` as signed in). `SleepStore.startSleep()` and
  `cancelSleep()` refresh the widget so the asleep state flips immediately;
  `signOut()` and sign-in (`adoptSignedInAccount`) refresh it so the action
  capsule flips between "Sleep Now" and "Sign in".
- Deep links: `sleepblock://sleep` (widget capsule) does
  **not** start a session — `SulavSleepApp.onOpenURL` opens Home's
  slide-to-sleep confirmation by setting `SleepStore.showSleepConfirmation`
  (guarded by authenticated + onboarded + no active session; the slide
  gesture is the only way a night begins). `sleepblock://signin` (the
  widget's signed-out capsule) is deliberately unhandled — opening the app
  lands on the welcome screen.
- Awake, the provider emits at most three entries (now + the drowsy boundary
  90 min before bedtime + next bedtime) and relies on system-driven
  `Text(_, style: .timer/.relative)` for ticking text; the app pushes reloads
  on real changes. The 90-minute drowsy lead mirrors `HomeSloth.drowsyLead`
  (`TonightState.drowsyLeadMinutes`) so the app and widget sloths get heavy
  eyelids together.
- Asleep, the provider emits a two-hour window of **minute entries** aligned
  to `asleepSince`, so the sleep face's ZZZ chain (`SlothZzz`) steps one z
  per minute — WidgetKit cannot animate, but entries within one timeline are
  free. `.atEnd` extends the night two hours at a time (a handful of
  budgeted reloads per night), and the app's wake-up reload ends the face.
- `SleepStore` writes the summary and calls `WidgetCenter.reloadAllTimelines()`
  on every history change (via `persist()` → `updateWidgetSoon()`). A historical
  note: an `AppEnvironment.isTesting` guard used to skip this under XCTest; that
  guard no longer exists in the code.

## Sleep lockdown build specifics

- Screen Time needs `com.apple.developer.family-controls`, which is applied to
  **device builds only** via `SulavSleep-device.entitlements` and the
  `CODE_SIGN_ENTITLEMENTS[sdk=iphoneos*]` build setting. The base
  `SulavSleep.entitlements` (Simulator) has HealthKit + App Group only, so the
  Simulator builds, tests, and runs normally.
- To enable real enforcement: request the Family Controls capability for the dev
  account, then build/run on a device. See `docs/roadmap-lockdown-and-widget.md`.
- The shield overlay's look lives in `SulavSleepShieldConfig/ShieldConfigProvider.swift`
  (see the "Shield overlay" section of `DESIGN.md`). The system renders the
  shield from a static `ShieldConfiguration`; the animated brand mark is an
  animated `UIImage` — ~38 pre-rendered frames of the `RisingZs` cycle
  (keyframe constants duplicated from `SleepTheme.swift`; change one, change
  both) composited over the extension's own `ShieldSloth.png` (a 480px `sips`
  downscale of `HomeSlothNightBlink`, bundled because extensions can't read
  the app's asset catalog). Keep the frame count / canvas size modest: shield
  config extensions have a small jetsam limit, and an OOM-killed extension
  silently falls back to Apple's generic gray shield. Shields only render on
  device (Family Controls), so verify composition changes with a quick AppKit
  port of the drawing code if needed — the math is plain CoreGraphics.
- Both shield buttons can only `.close` (`ShieldActionHandler.swift` — the
  Shield Action API cannot open the host app), so the shield shows a single
  "Good night" button; don't add copy that promises navigation.

## App Intents

- `StartSleepIntent` ("Sleep Now"): opens the app on Home's slide-to-sleep
  confirmation (`openAppWhenRun` + a `.sleepConfirmationRequested`
  notification the app scene observes). It deliberately does *not* start a
  session — the slide gesture is the only way a night begins, on every
  surface: in-app button, widget capsule, and Siri alike.
  (Historical note: it used to write an active session straight into the
  App Group without opening the app.)
- `OpenSleepHomeIntent`: opens SleepBlock.
- `SulavSleepShortcuts`: exposes both to Shortcuts/Siri/Spotlight.

## Launch screen (splash)

The splash is a two-stage handoff:

1. `SplashScreen.storyboard` (wired via `UILaunchStoryboardName`) shows the
   sloth-on-pillow figure — `SplashSloth.imageset`, the icon's colorway on a
   *transparent* background (1200×720, emitted by
   `scripts/generate-app-icon.py` alongside the icon) — at 200×120pt,
   centered flush on `SleepColor.background` (#08111E). No rounded icon
   rectangle. Launch storyboards are static snapshots; nothing here can
   animate.
2. `LaunchSplashView` (RootView.swift) is the `.authLoading` screen: the
   same asset at the same 200pt width and screen-center position on the same
   flat navy, so the storyboard → SwiftUI handoff is invisible. The *only*
   thing that changes at handoff is the gold `RisingZs` chain starting —
   nothing else may appear (an earlier revision faded in the brand halo
   here, and it read as a second splash screen popping in).
   `RootView.splashHold` (1.5s) keeps the splash up past auth readiness so
   the first z is visible before the crossfade; the sleep-mode overlay
   branch bypasses the hold entirely.

Handoff invariants — each of these, broken, is a visible jump:

- `LaunchSplashView.width` must equal the storyboard's SPLASH-ICON width
  constraint (200pt).
- `LaunchSplashView` must keep `.ignoresSafeArea()` on its whole stack and
  must not be centered inside any safe-area-inset container: the storyboard
  centers on the full screen, while SwiftUI's default safe-area layout sinks
  a centered image ~13pt lower (status-bar inset > home-indicator inset).
  This was measured, not theorized: pre-fix the figure sat 42px (@3x) below
  the storyboard position.

Simulator gotcha: iOS caches a rendered snapshot of the launch screen
(SplashBoard), and a long-lived simulator can keep showing a stale blank
snapshot even across reinstalls, SpringBoard restarts, and reboots. If a
launch-screen change doesn't show up, verify on a freshly booted simulator (or
erase the simulator); real devices regenerate the snapshot on install. The
bundle can be sanity-checked directly: `SplashScreen.storyboardc` should be in
the app, and `assetutil --info <app>/Assets.car` should list `SplashSloth`.
