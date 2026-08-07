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

### Preview the Settings subscription status

The **Subscription** group in Settings is fed by `store.subscriptionStatus`,
which is nil in dev mode (no RevenueCat key, no real subscription) — so the
group hides on the Simulator by default. A DEBUG-only launch argument injects a
sample trial (6 days left, renewing) so the row can be seen and screenshotted:

```sh
xcrun simctl launch booted com.sulav.sleepblock -review-subscription
```

Like `-review-paywall`, the arg is compiled only under `DEBUG`. Against a real
RevenueCat key the status is live, so the arg is ignored (dev mode only).

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

### Preview the "you already have an account" gate

`ExistingAccountWelcomeView` needs a second sign-up run against an Apple or
Google identity that is *already* registered — which the simulator can't
stage. A DEBUG-only launch argument renders it directly:

```sh
xcrun simctl launch booted com.sulav.sleepblock -review-existing-account
```

It reads the live store, so which of the two one-line copy variants you get
follows this install's state: the reassuring one when `isOnboarded`, the
"let's set your schedule up next" one when not.

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

## Shipping a release

Version lives in **`CFBundleShortVersionString` in five `Info.plist` files** —
the app plus `SulavSleepWidget`, `SulavSleepMonitor`, `SulavSleepShieldAction`,
`SulavSleepShieldConfig`. Not in `MARKETING_VERSION`, which the pbxproj still
carries at `1.0` and which nothing reads; don't be misled by it. **All five must
match** or App Store Connect rejects the upload with a bundle-version mismatch.

```sh
for p in ios/SulavSleep ios/SulavSleepWidget ios/SulavSleepMonitor \
         ios/SulavSleepShieldAction ios/SulavSleepShieldConfig; do
  plutil -replace CFBundleShortVersionString -string "1.2" "$p/Info.plist"
done
```

Which number to move:

- **Previous version is live on the App Store** → raise the version string
  (1.1 → 1.2). `CFBundleVersion` may restart at 1, since build numbers only
  have to be unique *within* a version string.
- **Previous version uploaded but not released** (in review, rejected, or in
  TestFlight) → keep the version string, raise `CFBundleVersion`. Apple rejects
  a duplicate build number for a version it has already seen.

Before archiving, check the Release configuration actually builds — Debug skips
the `Guard Release Secrets` phase, which fails the build when `Config.xcconfig`
is missing (an empty `REVENUECAT_API_KEY` silently disables the paywall and
grants everyone Pro, so a keyless Release must never ship):

```sh
xcodebuild -project ios/SulavSleep.xcodeproj -scheme SulavSleep \
  -configuration Release -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
```

Then in Xcode: destination **Any iOS Device (arm64)** → Product → Archive →
Distribute App → App Store Connect. A Simulator destination greys out Archive.

Screen Time, the shield, and its snooze cannot be exercised before this point —
they are device-only (see "Sleep lockdown build specifics"), so anything
touching `SulavSleepShield*` needs a TestFlight or development build on real
hardware to have been verified at all.

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
  "All nights" pushed page when history exceeds seven). Every night's row
  carries its **window** (`SleepWindowLine`: moon + `session.start` → sun +
  `session.end`) under the date; `SummaryBand`, straight under the name, is
  the screen's one stat block — Avg sleep / To bed / Up over a caption
  carrying scope and streak. Both read fields
  `SleepSession` has always persisted — they were simply never displayed.
  All averages come from `SleepStats.averages(of:last:)` over
  `SleepStats.recentWindow` (7) nights, so nothing on the screen can drift
  onto a different window. Clock averages use
  `SleepStats.meanMinuteOfDay`, a **circular** mean — see its doc comment and
  DESIGN.md; a plain average of bedtimes straddling midnight lands at noon.
  A gear in the
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
  once revealed), with the sloth and status text centered in the full flexible
  content region, before crossfading to the personalized summary; its "I'm
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
  would flash a phantom keyboard. The presented prewarm is also deferred
  ~80ms off the tap frame (`DispatchQueue.main.asyncAfter` in `setRoute`) so
  the keyboard commit doesn't stack onto the questionnaire's first build in
  the same frame — the residual "Get started" hitch — while still finishing
  under the 280ms transition and before the name step's 320ms autofocus.
  Struggle answers persist to `Profile.sleepStruggles` for future
  personalization. The list-question rows (`OptionRow`, `TimeSinkChip`) keep
  their glass content *constant* and paint selection entirely in an
  opacity-faded overlay above the glass (amber ring + amber twins of the icon
  and trailing glyph, geometry-matched to the base label): changing any pixel
  inside `glassEffect` content — the earlier icon/checkmark color+symbol swap
  — re-rendered the glass on every tap, the same lag family as toggling the
  glass tint, so selecting an option felt sluggish; an overlay fade is a pure
  composite.
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
- `SleepAssetCache.swift`: launch-time decode cache for the big scene bitmaps
  so the first interactive onboarding steps do not pay image-decode cost at
  interaction time (`UIImage(named:)` defers the decode to first draw). The
  prewarm list is **phase-derived**: the six city depth planes are named
  `CityPhase.rawValue + cityLayerNames[i]` (e.g. `NightCitySkyBase`,
  `DayCityClouds`), matching `citySpecs` in `SleepBackground.swift`, plus the
  current phase's brand-mark sloth (`HomeSloth{phase}Blink`) and `SplashSloth`.
  A fixed night-only list would decode art a day/dusk open never draws and
  miss the layers actually shown; misses fall through to an on-demand decode
  that is then cached (e.g. the next phase's set at a boundary crossfade), so
  every name is decoded at most once per run. `SlothBrandMark`
  (`OnboardingView.swift`) draws its sloth through this cache so the
  questionnaire-header mark isn't decoding a 1200×720 PNG inside the
  "Get started" transition.
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
- **Sleep days.** A night belongs to **the day you woke up** — `SleepMerge.key`
  is `startOfDay(session.end)`, so a Fri 23:00 → Sat 07:00 night is Saturday's.
  Crossing midnight changes nothing; only `end` is read. This matches Apple
  Health/Oura/Whoop and the moment the app is actually read (you wake, open it,
  today's column holds the sleep you just got).
  `SleepMerge.key` is the *only* day rule — every view calls it rather than
  re-deriving one. It used to shift back 12h while the views bucketed on plain
  `startOfDay(end)`, and the disagreement let a ≥45-min afternoon nap (which
  clears `SleepNightBuilder.minimumNightMinutes`) share a chart column with the
  night you woke from that morning and silently overwrite it — an 8h night
  rendered as a 1h bar, Home called the nap "Last night", the streak reset.
- `SleepMerge.merge` therefore returns **at most one session per sleep day**.
  Collisions resolve by *longest wins*, with Health breaking ties. Longest,
  not source precedence: "Health wins" is right for one night recorded twice
  (Health measured it; the local record is button-press timing) but wrong for
  two genuinely different events, and it failed when the night was local and
  the nap came from Health. Every display surface inherits this invariant —
  none of them dedupe again.
- `onTrackStreak` counts consecutive on-track nights on *consecutive sleep
  days*, and the run must reach today or yesterday to still be live (yesterday
  because tonight's sleep hasn't happened yet). Before the day check it counted
  qualifying records regardless of gaps, so a good night in June plus a good
  night in July read as a streak of 2.
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
  `createdAt`/`lastSignInAt` — GoTrue has no explicit flag for this grant type).
  There is no way to refuse up front: the check is only possible *after* the
  grant has already issued a session. So the app does the next honest thing —
  `SleepStore.showsExistingAccountWelcome` (set in `performAuth`, which now
  takes the calling screen's `AuthIntent`) makes `RootView` hold on
  `ExistingAccountWelcomeView` until the user acknowledges it, and
  `OnboardingQuestionsView` never calls `finish()`, so the just-answered
  questionnaire is discarded rather than written over the profile that account
  already has. Acknowledging resumes normal routing: Main when the profile
  restored, or a freshly-mounted quick setup (`includesAccount == false`, since
  `store` is authenticated by then) when the account genuinely has no profile.
  The flag is raised *before* `adoptSignedInAccount` assigns `account` —
  assigning it is what flips `isAuthenticated` — or Main flashes up first.
  Manual email/password can't reach any of this: a duplicate `signUp` either
  gets Supabase's no-session anti-enumeration response or an explicit
  `user_already_exists` error, never a session, so it fails inline on the
  account step with "That email already has an account…" and the user signs in
  with their real password instead.
  `-review-existing-account` renders the screen against the live store (the
  copy variant follows `isOnboarded` and the account's provider).
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
- **Cloud sync** (`SleepCloudService.swift`): profiles and sleep sessions are
  persisted to two Supabase Postgres tables (`profiles`, `sleep_sessions`),
  both protected by RLS policies scoped to `auth.uid()`. The app uses the
  `Supabase` umbrella product (not just `Auth`), so the shared
  `SupabaseClient` handles automatic JWT injection for all PostgREST queries.
  - *Profile sync*: `SleepStore.syncCloudProfile()` upserts to the `profiles`
    table after every profile-shaping change (onboarding, name, schedule).
    On restore (fresh device/reinstall), `restoreSession` fetches from the
    table first; if empty, falls back to legacy `sleep_profile` auth metadata
    for pre-migration accounts and migrates the data to the table. The
    **sign-in** path (`adoptSignedInAccount`) does the same fetch and
    deliberately `await`s it — bounded to 5s — *before* assigning `account`.
    See "Never route a returning user through onboarding" below.
  - *Session sync*: `wakeUp()` fire-and-forget upserts the new session to
    `sleep_sessions`, and `syncCloudSessions()` reconciles in **both**
    directions at launch, after sign-in, and after quick setup: it merges down
    whatever the table holds that this device lacks (`SleepMerge`, same
    night-dedup as the Health merge, local wins on conflict) and pushes up
    every locally-sourced night whose id the table is missing. The push half
    is what makes the backup honest — `wakeUp`'s upsert has no retry, so a
    night logged offline reached the table only if that one call happened to
    succeed.
  - *Migration*: on the first launch after the cloud sync update, an existing
    local profile is seeded to the `profiles` table (tracked by
    `sulav.cloudMigrated.v1`, **marked only when the upsert succeeds** — it
    used to be marked unconditionally, so a single offline launch retired the
    seed permanently). Sessions are not part of this one-shot: the two-way
    reconcile above covers them on every launch. Legacy auth metadata is still
    readable but no longer written; new data goes straight to the tables.
  - *Timestamps*: `sleep_sessions.started_at`/`ended_at` are written as ISO
    8601 with fractional seconds, but Postgres trims trailing zeros and omits
    the fraction entirely on a whole second, and `ISO8601DateFormatter` returns
    `nil` when `.withFractionalSeconds` and the string disagree in either
    direction. `SessionRow.date(from:)` therefore tries both formatters — a
    row that decodes but fails to parse is a night silently vanishing from the
    user's history, so `fetchSessions` also logs any it had to drop.
  - *Offline-first*: all cloud calls are best-effort fire-and-forget. The local
    device is always the source of truth. Cloud is a durable backup that
    enables cross-device profile restore and survives device loss.
  - Device-bound settings (Health sync, Screen Time lockdown, prompt
    dismissals) deliberately do **not** sync — they hinge on per-device
    permission grants.
  - SQL migration: `supabase/migrations/001_create_tables.sql` — must be
    run in the Supabase SQL Editor or via `supabase db push` before the
    feature goes live.
- **Never route a returning user through onboarding** (the "my nights are
  gone" bug, fixed after a real report). Three separate mistakes lined up:
  1. `adoptSignedInAccount` assigned `account` — which flips
     `isAuthenticated` — while the cloud-profile fetch was still running in a
     detached `Task`. Every gate that keys off the sign-in (`RootView`,
     `OnboardingGateView.onChange`, `OnboardingQuestionsView.onChange`) read
     `profile == nil` in that same state change, so *every* account whose
     profile lives in the `profiles` table rather than legacy auth metadata
     was treated as a stranger and shown quick setup. The fetch is now
     awaited, bounded, before `account` is set.
  2. `completeOnboarding` cleared `sessions`, `importedHealthSessions` and
     `activeSession` on the reasoning that a fresh sign-up starts empty. True
     — but quick setup runs the same function for a *returning* user, so
     finishing it destroyed the nights the cloud restore had just merged in.
     It now writes only the fields the questions asked about, onto a copy of
     the existing profile. The two cases that must genuinely start clean have
     always done their own wipe: `adoptSignedInAccount` (different account on
     a shared device) and `finalizeAccountDeletion`.
  3. Nothing re-pushed a night whose original upsert failed, so the cloud copy
     could legitimately be missing history the device still had — see *Session
     sync* above.
  The blast radius was worst on reinstall, where local data is gone and the
  cloud copy is the only one left. Android carried mistake 2 as well
  (`data/SleepStore.kt`) and is fixed the same way; it has no session table
  yet, so 1 and 3 don't apply there.
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
  authenticated call fails — is the standard one. Net effect: nothing on the
  launch *path* blocks on the network. The cloud work it kicks off — the
  session reconcile, and the one-shot profile seed/restore — is all
  backgrounded and best-effort, so an offline launch is indistinguishable
  from an online one until the data lands.
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

## Offline behavior and the entitlement grace period

The app is offline-first and stays fully usable without a network, for as
long as you like:

- **Launch and identity** never touch the network — `currentAccount` reads the
  Keychain session directly and deliberately skips a token refresh (see the
  comment there), so a cold launch offline lands straight in the app.
- **Everything that is the product** is local: logging a night, waking, the
  streak, the record chart and history, the schedule, Screen Time lockdown,
  widgets, Live Activities, HealthKit.
- **Cloud sync** (`CloudSyncing`) is best-effort and swallows failures; local
  is the source of truth and it catches up on the next launch/foreground.
- **The update gate** fails open (see below).
- **The feature board** is the one screen that needs a network, and it says so
  rather than breaking anything else.

### The one thing that could lock a paying user out

Entitlement comes from RevenueCat's cached `CustomerInfo`, and `isActive` is
computed against the expiry date *inside that cache*. Offline you stay
entitled until that date passes — but once it does, the cache itself reports
not-entitled, `needsPaywall` flips true, and **both purchase and restore need
a network to clear it**. That's a locked door with no key on the inside, in an
app that otherwise works perfectly offline. It bites a monthly subscriber who
is offline across their renewal date; an annual subscriber is fine for the
year.

`SleepStore.isWithinOfflineGrace` is the fix: **2 days**
(`offlineGraceWindow`) measured from `SleepPersistence.lastEntitledAt`, which
is rewritten every time RevenueCat confirms an active entitlement.

**It is not a free trial extension.** Grace applies only when the
not-entitled verdict came from *stale* CustomerInfo. `SubscriptionProviding.
start`'s third argument is RevenueCat's `requestDate` — when the server
actually answered — and anything inside `authoritativeWindow` (10 min) counts
as the server's own word, which skips grace entirely. So a user who genuinely
cancels while online hits the paywall immediately with no extra days; only
someone we *cannot reach* gets the reprieve.

`lastEntitledAt` is cleared on sign-out and in `reset()`, so grace belongs to
the account that earned it and never transfers to whoever signs in next on a
shared device.

**Also worth enabling, separately:** App Store Connect's own **Billing Grace
Period** (Subscriptions → the group → Billing Grace Period). That covers a
different failure — a *payment* that fails at renewal while the user is
online — and keeps them entitled while Apple retries. The two together cover
both "we can't reach the server" and "their card bounced".

## App update gate

Server-driven version handling — the standard production pattern (Spotify,
banking apps): one remote-config row per platform (`app_config`, migration
004) that the client compares its own `CFBundleShortVersionString` against on
launch and every foreground. All of it lives in
`ios/SulavSleep/SleepUpdateGate.swift`.

**Why this exists.** Shipping an update doesn't reach anyone by itself: iOS
auto-updates most users silently, users who disabled that may never update,
and Apple provides **no API** telling a running app that a newer version
exists. That was harmless while the app was local-first. It isn't now — the
feature board couples the client to the Supabase schema, and we already saw
the failure mode (a client selecting `author_name` before migration 003
existed hard-failed the board). Without a gate, a stranded old client just
shows broken screens with no way to tell the user why.

### The two tiers

| Condition | Effect |
|---|---|
| installed < `min_supported_version` | **Forced gate** — full-screen, non-dismissible `UpdateRequiredView`, mounted by RootView. For releases where old clients are genuinely broken. |
| installed < `latest_version` | **Soft nudge** — dismissible `UpdateNudgeCard` on Profile, once per version. The old build still works. |

### Rules that are load-bearing

- **Fail open.** A failed fetch, missing row, or unparseable version never
  blocks anyone — only a *successfully fetched* config can set
  `updateRequired`. A network hiccup is not an outdated app. Verified: with
  the table absent the fetch errors and the app goes straight to Home.
- **The gate never outranks sleep mode.** Its RootView branch sits *after*
  the `activeSession` branch, so an active night keeps wake/cancel and the
  lockdown teardown reachable — the same rule the paywall follows.
- **The gate needs `AppStoreLink.isConfigured`.** A blocking screen whose
  Update button can't open the store is worse than no gate.
- **Version compare** is component-wise integer on dotted strings
  (`AppVersion.isOlder`). Non-numeric components read as 0, so a malformed
  server value blocks nobody.
- Fetches are throttled to once an hour in memory (so a cold launch always
  checks) — *except* while the gate is up, when every foreground re-checks so
  a mistaken bump reverted in the SQL editor lifts the gate without a
  reinstall. Failed fetches don't start the throttle, so they retry.

### Release checklist — order matters

1. Ship the new build and **wait until it is actually live** on the App Store.
   Confirm: `curl -s 'https://itunes.apple.com/lookup?id=6787030239' | grep -o '"version":"[^"]*"'`.
2. Only then set `latest_version` to the new version (turns on the nudge).
3. Bump `min_supported_version` **only** if old clients are actually broken
   (e.g. you shipped a migration they can't read), and **never** before step 1
   — a gate whose Update button has nothing to install is a trap with no exit.
4. Optionally set `update_message` to state the reason; the gate falls back to
   generic copy when it's null.

```sql
update public.app_config
   set latest_version = '1.1', min_supported_version = '1.1',
       update_message = 'This version can''t read your sleep record anymore.'
 where platform = 'ios';
```

To preview the gate without touching the server, launch with
`-review-update-gate` (DEBUG only, alongside `-review-paywall`,
`-review-screentime-primer` and `-review-existing-account`).

## App Store review prompt

Two paths, deliberately using different mechanisms.

**Before shipping:** set `AppStoreLink.appID` in `SleepStore.swift` to the
numeric id from App Store Connect. It's empty by default and the Settings
"Rate SleepBlock" row **hides itself** until it's set — a placeholder id opens
the App Store to a nonexistent app ("App Not Available"), which is worse than
no row.

### You cannot detect whether someone reviewed

iOS provides no callback from `requestReview()` and no "has this user rated"
API — deliberately, so developers can't treat reviewers differently. So "don't
ask again if they reviewed" is **not implementable in our code**. What the gate
actually does is re-ask after a cooldown without knowing the outcome. Two
system behaviors keep that from becoming nagging:

- iOS won't re-show the prompt to someone who already rated the current
  version, so the "they already reviewed" case is handled *by the OS*.
- iOS caps the prompt at three appearances per 365 days whatever we ask for.
  `SleepStore.maxReviewAsks` is matched to that number so we never spend a
  request the system would have swallowed anyway.

### The automatic prompt

`HomeView.maybeAskForReview()` calls `@Environment(\.requestReview)` three
seconds after Home appears, when `SleepStore.shouldRequestReview` passes:
≥ `reviewMinimumNights` (2) logged nights, no active session, under the
lifetime cap, and ≥ `reviewCooldown` (7 days) since the last ask. Counters live
in `SleepPersistence` (`reviewAskCount`, `lastReviewAsk`) — container-backed
like the Screen Time primer, and **not** cleared by `reset()`, since signing
out isn't a licence to start asking again.

It fires on **Home, not at wake-up**. Waking is the obvious success moment and
the wrong one: the user is half-awake and trying to start their day. The delay
keeps it from racing the notification permission sheet, and the gate is
re-checked after the sleep in case a night started meanwhile.

### The Settings row

Opens the App Store write-review URL (`?action=write-review`) rather than
calling `requestReview()`. A deliberate tap must always do something visible,
and `requestReview` frequently shows nothing by design — acceptable for an
ambient prompt, not for a button someone pressed on purpose.

### Don't add a pre-prompt

The "Do you like the app? → Yes → prompt / No → email us" pattern filters
negative reviewers, violates App Store guidelines, and is the specific thing
that makes review requests feel manipulative.

## Feature request board

Settings → Feedback → **Request a feature** (`FeatureRequestsScreen` in
`ios/SulavSleep/SleepFeatureRequests.swift`). Model, network layer, screen
state, and views all live in that one file, the same way
`SleepScreenTime.swift` contains FamilyControls.

### The public board is OFF — `FeatureRequestFlags.showsPublicBoard = false`

The screen currently ships as a **submit-only suggestion box**: the composer
posts to the same table, and nobody sees anybody else's words. The board —
other people's requests, the vote controls, "Most wanted" — is written,
working, and flagged off.

**Why.** App Store Guideline 1.2 requires an app that *displays*
user-generated content to provide a way to filter objectionable material, a
mechanism to report it, a way to block abusive users, and published contact
info. The board has none of those and attaches real names to posts, so
shipping it is a rejection risk. A form that displays nothing to anyone raises
none of that.

**To turn it back on**, build the moderation UI first — at minimum a
per-request "Report" action and a way to block an author — then flip the flag.
The database side is already done: `status = 'hidden'` drops a row from every
client read, so taking content down is one UPDATE.

With the flag off the screen also **skips the fetch entirely** (no board, no
reason to risk a "couldn't load" alert) and shows an explicit "Request sent"
confirmation, because the list a new request used to land in isn't there — a
submit that empties a field and says nothing reads as a failure.

When the flag is on, a signed-in user sees the top 50 requests ranked by
score, upvotes/downvotes them, and posts their own.

**Setup — this feature needs migrations 002 and 003.** Run
`supabase/migrations/002_feature_requests.sql` and
`003_feature_request_author_name.sql` (SQL Editor or `supabase db push`).
Without 002 the tables don't exist; without 003 the board query fails outright,
because the select names `author_name` explicitly. That hard dependency is
deliberate — the resilient alternative, `select *`, would ship every other
user's `author_id` to every client.

### Why this is not part of `CloudSyncing`

`CloudSyncing` is best-effort background sync of the user's *own* record: every
call swallows its error, because the device is the source of truth and a failed
sync must never interrupt anyone. The board inverts both properties — the
server is the only source of truth, and a submit that fails silently leaves a
user believing they were heard when they weren't. So `FeatureRequestBoarding`
throws, and the screen surfaces failures in an alert.

### Security model (read this before changing the SQL)

This is the app's **first cross-user data**. Every table in migration 001 is
`auth.uid() = <owner>` and nothing else, so the board's rules are deliberately
stricter than they look:

- **Request text** is readable by any signed-in user; rows with
  `status = 'hidden'` are filtered out. That's the moderation lever — hiding
  abusive content is an `UPDATE`, never a `DELETE`.
- **Individual votes are private.** The votes table's policy is own-rows-only,
  so "who downvoted me" is unanswerable by design. The only public signal is
  the aggregate `score`.
- **`score` is not user-writable.** There is deliberately *no* UPDATE policy on
  `feature_requests`; the column is moved solely by the SECURITY DEFINER
  trigger `sync_feature_request_score()` on the votes table. A naive "users
  manage own rows" policy would have let anyone set their own request to 9999.
  If you ever add an UPDATE policy, exclude `score` or you reopen this.
- **Inserts are pinned** to `auth.uid() = author_id` with `score = 0` and
  `status = 'open'` enforced in the `WITH CHECK`, so a request can't be born
  popular or pre-approved.
- **Spam guard**: `check_feature_request_quota()` caps a user at 5 requests per
  rolling day and raises a human-readable message the client passes through.
- **Account deletion cascades.** The delete-account flow promises to remove the
  user's data from our servers, so `author_id` is `ON DELETE CASCADE` — their
  posts (and the votes on them) go too.
- **Author names are copied, not joined** (migration 003). Joining
  `profiles.name` would need a SELECT policy letting anyone read other users'
  profile rows — and that table also holds bedtime, struggles, goals and
  onboarding answers, so opening it to read one column would expose all of
  them, for every user, including people who never posted. Instead a
  `BEFORE INSERT` trigger stamps the poster's current profile name onto the
  row. Two consequences, both intended: the name is **not client-supplied**
  (so nobody can post under someone else's name by hitting PostgREST
  directly), and a later rename does **not** rewrite old posts, so the board
  and Settings can legitimately disagree.

### Transient network failures

Votes intermittently failed with `NSURLErrorNetworkConnectionLost` while the
identical tap succeeded a second later — URLSession reusing a keep-alive
connection the server had already closed. `retryingDroppedConnection` retries
those once, after a 250 ms beat.

It wraps the board read and both vote writes, which are **idempotent**: the
vote upsert and delete are keyed by `(request_id, user_id)` and the read is a
plain select, so running either twice is indistinguishable from once.
`submit` deliberately does *not* use it — if the connection dropped after the
server committed the insert, a retry would post the same idea twice.

### Client behavior

- **Votes are optimistic**: the row updates on tap and rolls back if the write
  fails, because a spinner on a one-tap gesture reads as broken. **Submits are
  not** — they await the server, since the user needs to know their words
  landed. A successful post is inserted at the top of the local list regardless
  of score, so the action visibly did something on a busy board.
- **Submit is idempotent, and therefore retried.** It originally wasn't
  retried at all, because a plain insert isn't safe to repeat — if the
  connection dies *after* the server commits, a retry posts the idea twice.
  The client now generates the row's `id` as an idempotency key, so the retry
  is safe: either the first attempt never landed (the insert succeeds) or it
  did (the insert fails on the primary key, which *proves* it worked, so the
  row is read back and reported as success). This matters because
  `NSURLErrorNetworkConnectionLost` on a first tap is common enough to hit
  routinely, and with the board hidden, posting is the screen's only job.
- **Limits live in `FeatureRequestLimits`** — `maxTitle` (140) mirrors
  migration 002's `feature_requests_title_length` check; change one and you
  must change the other or the server starts rejecting text the client
  accepted. The composer clamps typing at `maxTitle` on the way *in* (a
  `Binding` that `prefix`es the value), so the draft can never violate the
  constraint and `canSubmit` needs no upper bound.
- **Paging**: the board shows `pageSize` (5) requests, then a "Show N more"
  button that reveals another page. Server ordering (`score desc,
  created_at desc`) means the first page is genuinely the most wanted. A
  button rather than infinite scroll is deliberate — the board is something
  you skim and leave.
- **Card expansion**: collapsed cards clamp the title to `collapsedLines` (2)
  with `reservesSpace: true`, which is what gives every card the same standing
  height regardless of title length. Truncation is *measured*, not guessed
  from character count: an invisible unclamped copy of the text renders behind
  the visible one and the two heights are compared via `ClampedTitleHeight` /
  `NaturalTitleHeight` preference keys. That's the only reliable way to ask
  SwiftUI whether it actually clipped, and it's why a short request never
  grows a pointless "See more". `refreshExpandability()` bails while expanded,
  since the heights match by definition then and recomputing would delete the
  "See less" button mid-use.
- Tapping the arrow you already chose retracts the vote (writes 0 → deletes the
  row), so a mis-tap is always recoverable.
- `PostgresDate.parse` trims fractional seconds to three digits before
  `ISO8601DateFormatter` sees them. PostgREST returns microsecond precision,
  which the formatter rejects outright even with `.withFractionalSeconds`.

### Not yet built

Posting is anonymous on screen (no author is displayed), and there is **no
in-app report/block flow**. If this board ships to the App Store, Guideline 1.2
(user-generated content) expects a report mechanism, a block-abusive-users
path, and a published contact — see the note in `DESIGN.md`.

## Subscription (RevenueCat)

SleepBlock is a subscription app with a **hard paywall + free trial**: after
the sign-up questionnaire commits (or a returning unsubscribed user signs in),
`RootView` shows `PaywallView` instead of Main — no ✕, no skip. The primary
action starts the App Store free-trial intro offer on the annual plan;
starting the trial or subscribing is the only way in.

Code map (all behind the app's usual protocol seam):

- `SleepSubscription.swift` — `SubscriptionProviding` +
  `RevenueCatSubscriptionService`. Streams `CustomerInfo` → both an
  `EntitlementState` (`unknown` / `entitled` / `notEntitled`, the paywall
  gate's answer) and a display-only `SubscriptionStatus?` (tier, `willRenew`,
  `expirationDate`, best-effort `isAnnual`) for the Settings status row —
  deliberately kept apart so enriching what's *shown* never disturbs the
  three-state answer the gate compares. Also maps the current offering's
  packages to SDK-free `SleepPlan` values, runs purchase/restore, presents the
  App Store management sheet (`manageSubscriptions` → `showManageSubscriptions`),
  and links the RevenueCat identity to the Supabase account id on sign-in/out
  (`logIn`/`logOut`) so a subscription follows the user across devices.
- `SleepStore` — `entitlement`, `subscriptionStatus`, `needsPaywall` (signed
  in + onboarded + *resolved* not-entitled), and `fetchPlans`/`purchase`/
  `restorePurchases`/`manageSubscriptions` intents.
- `PaywallView.swift` — the screen (see DESIGN.md "Paywall").
- `ProfileView.swift` — the **Subscription** group in `SettingsModal`
  (`SubscriptionStatusRow` + Manage subscription), hidden when
  `subscriptionStatus` is nil (dev mode / unresolved). See DESIGN.md
  "Navigation & structure".
- `scripts/generate-subscription-icon.py` — generates the status row's
  `SubscriptionSloth.imageset` (gold "medallion" sloth head). It derives from
  the committed `HomeSlothNightAwake` PNG, so — unlike `generate-app-icon.py` —
  it needs **no source EPS**; re-run it if the base sloth art changes.
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
3. **Release builds refuse to ship without keys**: the app target's first
   build phase ("Guard Release Secrets" in `project.pbxproj`) fails any
   Release build where `REVENUECAT_API_KEY`, `SUPABASE_URL`, or
   `SUPABASE_ANON_KEY` is empty — dev mode in a Release archive would
   silently disable the paywall (everyone entitled) and break auth. Debug
   builds are exempt, keeping the zero-setup dev mode above.

One-time external setup (dashboards):

1. **App Store Connect** — create the subscription group and two
   auto-renewable products (suggested ids `sleepblock.pro.annual`,
   `sleepblock.pro.monthly`), with a **7-day free trial intro offer on the
   annual** product (the paywall CTA derives "Start N nights free" from the
   product's intro offer, so the trial length lives in ASC, not code).
2. **RevenueCat** — create the project + Apple app, import the products,
   create entitlement **`SleepBlock Pro`** (must match
   `SleepSubscription.entitlementID` exactly) attached to both products, and a **current Offering** containing
   an `$rc_annual` and `$rc_monthly` package. The paywall renders whatever
   the current offering carries — plans, prices, and trial all come from the
   dashboard.
3. Put the app's public Apple API key in `Config.xcconfig`.

Testing purchases: real transactions need a device + sandbox Apple ID (or
TestFlight). In the Simulator the usual route is a StoreKit configuration
file synced from App Store Connect (Xcode scheme → Options → StoreKit
Configuration) once the products exist in ASC; RevenueCat picks it up
automatically.

### App User ID case (gotcha)

The RevenueCat App User ID is the Supabase `auth.users.id`, and it **must be
lowercase**. Postgres serves the UUID lowercase, but Swift's
`UUID.uuidString` renders it uppercase, so `SupabaseAuthClient.account(from:)`
lowercases it explicitly. RevenueCat treats the App User ID as an opaque,
case-sensitive string: without that call the SDK identifies as
`AADE23E7-…` while the dashboard customer is `aade23e7-…`, silently forking
every account into two customer records. The symptom is a granted entitlement
that never reaches the device — the user sits on the hard paywall while the
dashboard insists they are `Active`.

To check what a Simulator build is actually identifying as, read the SDK's
own defaults out of the app container (no code change, no rebuild):

```bash
plutil -p "$(xcrun simctl get_app_container booted com.sulav.sleepblock data)/Library/Preferences/com.revenuecat.user_defaults.plist"
```

`com.revenuecat.userdefaults.appUserID.new` is the live ID, and the
`purchaserInfo.<id>` blob is the cached `CustomerInfo` — decode it to see
whether `subscriber.entitlements` is actually empty.

Two related traps when a dashboard grant "doesn't work":

- A dashboard grant is **not pushed** to the device. `customerInfoStream`
  only emits when the SDK refetches (configure, or foreground with a stale
  cache), so force-quit and relaunch after granting.
- **Restore purchases cannot help in the Simulator.** There is no App Store
  receipt without a StoreKit configuration file, so `restorePurchases()`
  throws and the paywall shows "Couldn't reach the App Store to restore."

Because the account id is also the key for `lastAccountID` and the
cloud-migration marker, both comparisons are case-insensitive — an install
predating the lowercasing holds the uppercase id, and an exact compare would
read the same user as a different one and wipe their local profile and
nights on first launch after upgrading.

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
- **Two-phase blocking**: The `DeviceActivityMonitor` extension now applies the
  shield at `intervalDidStart` (bedtime) in the **pre-sleep** phase, not just
  clears it at `intervalDidEnd`. The phase (`presleep` / `active`) is stored in
  App Group defaults (`sulav.lock.phase`) and read by the shield extensions:
  - *Pre-sleep*: title "Time for bed", primary "Sleep Now" (fires a local
    notification with `sleepblock://sleep`), secondary "5 more minutes".
  - *Active*: title "Time to sleep", primary "Good night" (closes).
  `startLockdown()` writes `active`; `endLockdown()` and the monitor's
  `intervalDidEnd` / `eventDidReachThreshold` clear it.
- **Snooze ("5 more minutes")** — pre-sleep only, twice per lockdown window.
  State lives in App Group defaults beside the phase (`SleepLockdownSelection`):
  `sulav.lock.bedtimeMinutes` (mirrored by `scheduleLockdown` so the shield can
  say how late it is), `sulav.lock.snoozeCount`, `sulav.lock.snoozeUntil`.
  The allowance resets in the monitor's `applyShield()` at interval start, so
  it matches the night exactly — no date math, and midnight-crossing windows
  work for free.

  `ShieldActionResponse` has no "allow for N minutes", so the action extension
  drops the shield off `ManagedSettingsStore` itself. Nothing in an extension
  can run a timer, so the block's return trip has **four** chances, in order
  of reliability:
  1. **Usage threshold** — `eventDidReachThreshold` for one of
     `sleepSnoozeEventNames`. These are `DeviceActivityEvent`s registered on
     `sleepActivityName` up front by `scheduleLockdown`, at cumulative
     thresholds of `snoozeMinutes × 1…snoozeLimit` (5 and 10 minutes) over the
     same tokens the shield covers. It works because *shielded apps accrue no
     screen time*: inside a lockdown window the only way to spend minutes in a
     blocked app is during a snooze, so 5 minutes of usage lands exactly at the
     end of the first snooze and 10 at the end of the second. This is the only
     link that fires **while the user is still inside the app**, and it needs
     nothing from the doomed shield-action process.
  2. `SulavSleepMonitor` receives `intervalDidStart` for `sleepSnoozeActivityName`
     and re-applies. That activity's `intervalDidEnd` is a deliberate no-op —
     treating it as wake time would unshield the rest of the night. This is the
     wall-clock path, and it covers the snooze that gets *put down* rather than
     spent: an idle phone accrues no usage, so (1) never fires.
  3. A `sulav.sleep.snooze-over` local notification scheduled at the expiry
     ("Five minutes are up", carrying `sleepblock://sleep`). It doesn't
     re-shield by itself, but it reaches someone who is still scrolling and its
     tap drives (4). Cancelled by `startLockdown`, `endLockdown`, and
     `reapplyShieldIfSnoozeExpired` so a stale nudge can't fire.
  4. `ScreenTimeService.reapplyShieldIfSnoozeExpired()`, called from
     `SleepStore.reload()` on every foreground.

  (Plus the backstop of the next scheduled `intervalDidStart` at the following
  bedtime.)

  DeviceActivity rejects intervals under 15 minutes, so the (2) re-arm schedule
  runs from the snooze expiry to +20 min; only its *start* is meaningful. Its
  components carry the **full date** (`year…second`), not a bare
  `hour`/`minute`: a `repeats: false` schedule has no recurrence to pin a
  time-of-day to, and one built from hour/minute alone never fired — that was
  the original bug where a snooze ran out and the shield stayed down for the
  rest of the night. Scheduling from inside an extension is still the flakiest
  link, which is why (1) no longer depends on it. The shield-action target needs
  `com.apple.developer.family-controls` for `DeviceActivityCenter`; it is
  present in `-device.entitlements` only, so this path exists on device builds
  and is inert on the Simulator.

  `reapplyAfterSnooze()` guards only on "inside a lockdown window"
  (`currentPhase() != nil`). Inside one, re-shielding is always the safe
  direction, so a threshold that arrives with no snooze outstanding is allowed
  to put the shield back; outside one there is nothing to re-arm. It never
  touches `snoozeCount` — resetting the spent count there would hand out an
  unlimited supply.

- **"Unlock anyway after Nh"** (`Profile.lockdownMaxHours`, default 6) — the
  safety valve for the morning where the app is never reopened to tap wake. It
  is `sleepCapActivityName`: a one-shot DeviceActivity whose *interval start*,
  N hours after the user taps Sleep Now, runs the monitor's `clearShield()`. Its
  interval end is a no-op (the `intervalDidEnd` guard admits only
  `sleepActivityName`); the 20-minute tail is just DeviceActivity's 15-minute
  interval floor, and the components carry the full date for the same
  `repeats: false` reason as the snooze re-arm.

  Anchored to the **session**, not to bedtime, and armed by
  `startLockdown(maxHours:)` — from the app, in the foreground, the one moment
  scheduling reliably sticks. Session-anchored because the shield can be applied
  outside the bedtime→wake window (an afternoon nap), and there no
  `intervalDidEnd` is coming for hours; that is exactly the runaway the cap
  exists to stop. Retired by `endLockdown()` and by the monitor's
  `clearShield()`, so a stale cap can't fire partway through a later night.

  It was previously a `DeviceActivityEvent` on `sleepActivityName` with
  `threshold: DateComponents(hour: maxHours)` — and it could never fire, for the
  same reason the snooze threshold *does*: shielded apps accrue no screen time,
  so the meter sat near zero all night. `sleepEventName` is no longer registered;
  the monitor still answers it so installs that armed it before the fix behave
  sanely until something naturally reschedules the window.

  Consequence worth knowing: the cap now genuinely bites. With the default 6h
  and a longer bedtime→wake window, the shield lifts 6h after Sleep Now rather
  than at wake time. That is what the stepper has always promised ("lifts it
  early if the cap is reached"), but it is new *behaviour* — before the fix the
  shield always ran to wake time.

  `setLockdownMaxHours` deliberately does **not** reschedule the bedtime window
  any more: the window no longer depends on the cap, and re-registering
  `sleepActivityName` mid-night would re-fire `intervalDidStart` →
  `applyShield()` → `resetSnoozes()`, quietly handing out a fresh snooze
  allowance. A changed cap applies to the next session.

- **Mid-window edits are held, not applied** (`rescheduleLockdown`). The lock's
  own settings used to be live-editable while the lock was in force, which made
  the shield escapable from the UI. The exploit window is the **pre-sleep**
  phase: the shield is up but there is no `activeSession`, so `RootView` hands
  the user the full app, Profile included. Two ways out, both through sanctioned
  code paths:

  1. `saveSchedule` rescheduled immediately, so moving wake time to a few
     minutes out made the monitor's `intervalDidEnd` fire and `clearShield()`
     for the rest of the night.
  2. *Any* save re-registered `sleepActivityName` mid-window, re-firing
     `intervalDidStart` → `resetSnoozes()`. Nudge bedtime by a minute, save,
     collect two more "5 more minutes", repeat — an unlimited supply, the exact
     hazard `setLockdownMaxHours` was already written to avoid.

  `rescheduleLockdown` now refuses to register while the window is running and
  `reload()` (every foreground) retries, so a held change lands once the window
  closes. The retry is unconditional and idempotent — it self-defers — so there
  is no flag to persist and nothing is lost if the app is killed in between.

  Deferral keys off **both** `currentPhase() != nil` and `isInsideLockdownWindow`.
  The phase alone misses a real gap: after the cap fires, the phase is cleared
  while the clock is still inside the window, and re-registering there would
  re-fire `intervalDidStart` and put the shield straight back — silently undoing
  the one sanctioned way out.

  Second lock on the same door: the monitor calls
  `resetSnoozesForNewWindow()` instead of `resetSnoozes()`. The allowance is
  keyed to the window's start date (`snoozeWindowKey`) rather than to the fact of
  `intervalDidStart` firing, which is *not* once-per-night. `windowStart` looks
  back a day when today's bedtime hasn't passed yet, so one midnight-crossing
  night yields one anchor from either side of 00:00. With no mirrored bedtime to
  identify a window it falls back to resetting — the forgiving direction.

  Not yet closed, and deliberately out of scope here: `setBlockingEnabled(false)`
  and clearing the app selection still call `endLockdown()` outright. Closing
  those is the staged-edit ("only tightens") work — see the roadmap.

- **The slow door** (`SleepLockdownSelection.doorRequestedKey`). An
  always-available exit that costs 60 seconds (180 in hard mode) rather than
  being refused. First tap writes a timestamp and unlocks nothing; the shield
  rendered on the user's *next* attempt offers the real unlock, good for 10
  minutes.

  Two steps by necessity as much as design: a shield action extension is torn
  down the instant it answers a tap and cannot run a timer, but
  `ShieldConfigProvider` is asked for a fresh configuration on every attempt —
  so the user's own second attempt is the clock. No new activity to register.

  It lapses through the same layers as a snooze: `reapplyAfterSnooze` in the
  monitor (which now clears the door too) and
  `reapplyShieldIfSnoozeExpired` on app foreground, both keyed off
  `doorHasExpired()`. It re-uses `sleepSnoozeActivityName` for the wall-clock
  re-arm — same shape of grant, same corrective action, one fewer thing to lose.

  Unlike the snooze it is **not rationed**: an exit that can be exhausted is a
  dead end with extra steps, and the exit someone takes from a dead end is
  deleting the app — which takes the blocking with it, permanently. The wait is
  what keeps it from being a plain off switch.

  `currentEscape()` is the single resolver for what the secondary button means,
  read by both the extension that draws the label and the one that answers the
  tap, so the two can't disagree.

- **Reach attempts.** `ShieldConfigProvider.makeConfig` calls `recordReach()`,
  appending a timestamp to the App Group log (debounced 5s — the system can ask
  for a configuration more than once per launch, and an inflated count would
  make the morning mirror a lie; capped at 500 entries so a jetsam-constrained
  extension can't grow it without bound).

  The extension can only append — it has no idea when a night ends — so
  `SleepStore.harvestReachLog()` does the filing on every foreground, moving
  closed nights into `reachNights` (local only, 30-night rolling window) and
  leaving the still-running window's tail in place. The log is cleared when a
  window *opens*, never when it closes, because the morning mirror reads it
  long after the shield is gone.

  `lockReasons`, `hardMode` and `reachNights` are deliberately **not** synced to
  `CloudProfile` — see the note in `SleepStore`. Syncing any of them needs a
  `supabase/` migration, so it should be a decision, not drift.

- **Evening check-in.** A repeating `UNCalendarNotificationTrigger` an hour
  before bedtime (`scheduleEveningCheckIn`, re-registered idempotently on every
  `reload()` and on `saveSchedule`), carrying `sleepblock://tonight`. Soundless
  on purpose. Fire-and-forget: a user who denied notifications never sees it,
  and nothing depends on it arriving.
- The Shield Action API cannot open the host app, so the pre-sleep "Sleep Now"
  button posts a local notification with the deep link — tapping the
  notification opens the app on the sleep confirmation panel
  (`SleepAppDelegate` handles the notification tap via
  `UNUserNotificationCenterDelegate`). Provisional notification authorization
  (no prompt) is requested at launch.

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
