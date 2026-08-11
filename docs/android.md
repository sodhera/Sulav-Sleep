# SleepBlock for Android

Native Kotlin + Jetpack Compose app in `android/`, sharing the iOS app's
Supabase backend. Started July 2026 as a **core-MVP port** of the SwiftUI app
(`ios/` remains the flagship and the richer client).

## Why native (and not KMP/Flutter)

Chosen deliberately: the iOS app is pure SwiftUI with deep Apple-framework
coupling (Screen Time, HealthKit, Live Activities), so the Android
equivalents (UsageStats, Health Connect, widgets) also want native APIs.
Two thin native apps over one shared backend beat a shared-code layer that
would have to be retrofitted onto the finished iOS app.

## Building & running

```bash
cd android
./gradlew assembleDebug          # APK at app/build/outputs/apk/debug/
./gradlew installDebug           # install on a running device/emulator
```

- Gradle runs on Android Studio's bundled JBR 21 (`org.gradle.java.home` in
  `gradle.properties`) because the system Homebrew JDK (25) is newer than
  this Gradle/AGP pair supports.
- SDK location comes from `android/local.properties` (machine-specific,
  gitignored): `sdk.dir=/Users/<you>/Library/Android/sdk`.
- Emulator: `emulator -avd <name>` then `./gradlew installDebug`.

### Service keys

Copy `android/secrets.properties.example` → `android/secrets.properties`
(gitignored) and fill in the same Supabase values as `ios/Config.xcconfig`.
Missing/placeholder values put the app in **dev mode** — identical policy to
the unconfigured iOS build: auth surfaces a friendly "not configured" error,
and nothing is locked (an unconfigured RevenueCat key resolves `ENTITLED` at
init, so the paywall never appears — see "The lock").

## Architecture

One module (`app`), one activity, no navigation library — routing mirrors the
iOS `RootView` as a state machine in `MainActivity.kt`:

| iOS | Android |
| --- | --- |
| `SleepModels.swift` | `data/SleepModels.kt` |
| `SleepStore.swift` (@Observable) | `data/SleepStore.kt` (`AndroidViewModel` + Compose state) |
| `SleepPersistence` (UserDefaults + Codable JSON) | `data/SleepPersistence.kt` (SharedPreferences + kotlinx.serialization) |
| `SupabaseAuthClient.swift` (supabase-swift) | `auth/SupabaseAuthClient.kt` (hand-rolled GoTrue REST over OkHttp) |
| `RootView.swift` | `MainActivity.kt` `RootScreen` |
| `OnboardingView.swift` / `AuthView.swift` | `ui/onboarding/OnboardingFlow.kt` |
| `HomeView.swift` + `SleepConfirmationPanel.swift` | `ui/home/HomeScreen.kt` |
| `SleepModeView.swift` | `ui/sleep/SleepModeScreen.kt` |
| `ProfileView.swift` (+ Settings cover) | `ui/profile/ProfileScreen.kt` |
| `PaywallView.swift` | `ui/paywall/PaywallScreen.kt` |
| `SleepTheme.swift` / `LiquidGlass.swift` | `ui/theme/SleepTheme.kt` |

The GoTrue client is deliberately hand-rolled: the app touches a tiny auth
surface (email sign-up/sign-in, refresh-token rotation, user-metadata profile
sync, sign-out, the `delete-account` Edge Function), and a full SDK isn't
worth the dependency. Tokens live in app-private SharedPreferences.

### Cross-device profile sync

The cloud profile is the **same `sleep_profile` JSON in Supabase auth user
metadata** the iOS client reads/writes (`bedtime_minutes`, `wake_minutes`,
`struggles`, `time_sinks`, `goal`, `late_night_phone`, `wake_feeling`), so an
account onboarded on iPhone restores its plan on Android and vice versa. The
same shared-device rules apply: a different account signing in wipes the
previous user's local data; a returning user with a cloud copy skips
onboarding.

## Parity map (MVP vs phase 2)

Shipped in the MVP:

- Welcome → 10-step questionnaire (name, goal, struggles, time-sink apps,
  phone time, wake feeling, bedtime, wake, plan reveal, account step) with
  the same investment-arc rules (multi-selects allow zero; single-selects
  require a choice; plan reveal's build beat is sticky).
- Email auth against the shared Supabase project, including the two-tone
  error/notice rule and the delete-account flow (typed "delete" confirm).
- Sleep loop: Home countdown → slide-to-sleep confirmation → OLED sleep
  screen (hold-to-wake 1.2s / tap back-to-sleep / hold-to-cancel 0.8s) →
  logged night. Duration is the only metric; ≥85%-of-target streak.
- A night belongs to **the day you woke up**, matching iOS `SleepMerge.key`.
  `onTrackStreak` requires consecutive sleep days and a run reaching today or
  yesterday, and collapses multiple sessions on one day by longest-wins — iOS
  gets that collapse from its local+Health merge, which Android has no
  equivalent of until Health Connect lands. Both platforms must agree here:
  sessions sync through Supabase, so a date-blind streak showed the same user
  different numbers depending on which phone they opened.
- Profile: stat band, 7-night bar rhythm, recent nights, settings (rename,
  schedule steppers, sign out, delete account). Honest data only — no
  seeded history.

Shipped in phase 2 (July 2026):

- **App blocking** (`blocking/`). Android has no Screen Time shield API, so
  blocking is *usage-access polling + a shield the app presents itself*:
  `SleepLockdownService` (a specialUse foreground service, running only
  while a session is active) polls `UsageEvents` every second for the
  foreground app and launches `ShieldActivity` — night sloth, "Time to
  sleep", one "Good night" exit — over anything on the blocked list.
  Holding SYSTEM_ALERT_WINDOW exempts the service from background-launch
  restrictions. The Blocked apps screen (Settings → Sleep) carries the
  "Block while you sleep" toggle, deep-links to the two special-permission
  grants (usage access, display over other apps), and lists launcher apps
  via a manifest `<queries>` filter (no QUERY_ALL_PACKAGES).
  `willLockDuringSleep` = toggle ∧ live permissions ∧ non-empty selection.
  *Honest limitation vs iOS:* enforcement is app-level, not OS-level — a
  determined user can revoke the permissions or force-stop the app; there
  is no scheduled DeviceActivityMonitor equivalent, so the shield only
  guards while a session runs.
- **Real sloth art.** `scripts/generate-android-assets.py` (run after
  `generate-app-icon.py`) ports the iOS art: adaptive launcher icon
  (foreground + Android 13 monochrome) and the in-app sloth marks
  (welcome/paywall brand, Home awake/drowsy, sleep screen + shield night
  sloth).
- **Home-screen widget** (`widget/SleepWidget.kt`, Glance): the small
  "tonight" tile — BEDTIME + hero clock + awake sloth; ember sleep face
  with "since" while a night runs; "Set a schedule" empty state. Refreshed
  on every persistence write and every 30 minutes.
- **Paywall** (`ui/paywall/`, `subscription/`). RevenueCat purchases-android
  behind the same three-state entitlement gate as iOS (`UNKNOWN` never
  gates; unconfigured key = dev mode, entitled at init). A **soft paywall
  around one action** — see "The lock" below; an active night always
  outranks it. Needs `REVENUECAT_API_KEY` + Play Console products
  (entitlement id `pro`) to go live; terms/privacy footer links land with
  the Play listing.
- **Google sign-in** (`auth/GoogleCredential.kt`): Credential Manager →
  Google ID token → Supabase `id_token` grant. The provider buttons render
  only when `GOOGLE_WEB_CLIENT_ID` (the *web* client id Supabase is
  configured with) is set in secrets.properties.

Shipped in the July 2026 polish pass:

- **The living pixel city** (`ui/theme/SleepScene.kt`): the iOS scene's
  layers (sky, clouds, four skylines) ported by the asset script, drawn
  nearest-neighbor with a slow shared-phase parallax drift, following the
  day/dusk/night bands with a crossfade at the boundary, under the same
  readability-scrim rules. The sleep screen stays OLED black; widgets keep
  the flat gradient.
- **Haptics** (`ui/theme/Haptics.kt`): the knock on every shared button,
  wheel-detent ticks, the slide-to-sleep eight-detent ratchet + success,
  and the hold buttons' five-detent ratchet — wired centrally so call
  sites can't forget.
- **Blocking-permission primer** (`ui/onboarding/BlockingPrimerScreen.kt`):
  the last gate before Main — a two-grant checklist with live status that
  deep-links into system Settings, auto-completing when both grants land;
  "Not now" always works, one-shot per install.
- **Subscription status in Settings**: tier + renewal readout off
  RevenueCat's entitlement (trial/pro/won't-renew tones) + Manage
  subscription → the Play subscriptions page. Hidden when there's no
  status (dev mode) — never a faked plan.
- **Review switches** (`data/DebugFlags.kt`, debug builds only) — the
  Android `-review-*`:
  `adb shell am start -n com.sulav.sleepblock/.MainActivity --ez review-paywall true`
  puts the app in the **locked** state with sample plans: the first-run
  paywall on launch, and behind its ✕ the locked Main (Sleep Now raises the
  cover, Settings shows "Unlock SleepBlock"). The flag also ignores the
  stored dismissal marker, so the full-screen route renders on every launch
  and stays screenshottable. `--ez review-subscription true` injects a
  sample trial into the Settings status row.
- **The brand mark alive** (`ui/theme/SlothBrandMark.kt`): the rising gold
  z's on welcome, sign-in, the plan build beat, and the paywall.

Still deferred (phase 3):

- **Session cloud sync.** Android syncs the *profile* only (through the
  `sleep_profile` user-metadata key); it never reads or writes the
  `sleep_sessions` table iOS uses. Logged nights therefore live on the
  device alone and do not survive a reinstall, and the same account shows
  different history on the two platforms. The parity-map note above about
  the streak rule ("sessions sync through Supabase") describes the intent,
  not today's behaviour. Port `SleepCloudService.swift`'s two-way
  `syncCloudSessions` reconcile when this lands.
- Health Connect import, richer widget family (medium/large with the
  7-night bars), day/dusk scene tilt parallax (drift only for now),
  Play Store listing (terms/privacy URLs).

Questionnaire notes: the schedule steps use a snapping wheel picker
(`ui/theme/WheelTimePicker.kt`, 5-minute steps), and every step requires an
interaction before Next enables (see the DESIGN.md Android note). The
sign-in screen mirrors iOS "Welcome back": brand hero + provider stack
(Google pill with the real "G" from the iOS asset, quiet glass email path
that reveals the form in place; back unwinds form → providers → welcome).

## The lock (soft paywall)

Ported from iOS in August 2026 (`feat(paywall): let people in, lock the
night`). The paywall is **not** a wall around the app: it is a lock on one
action. A locked user gets the whole of Main — Home with its countdown and
sloth, the record, the schedule, settings — and is stopped at exactly one
place, **starting a night**. Everything the app *shows* is free, everything
it *does* is the subscription. See DESIGN.md ("Paywall") and the
"Subscription (RevenueCat)" section of `docs/development.md` for the iOS
originals; this section covers only what differs.

Three states, easy to confuse — all on `data/SleepStore.kt`, mirroring iOS:

| | meaning | drives |
| --- | --- | --- |
| `isLocked` | signed in + onboarded + *resolved* `NOT_ENTITLED` | the lock on `startSleep` and every path to it; hides the blocking primer; swaps the Settings group |
| `needsPaywall` | `isLocked` **and** this install has never closed the paywall | the first-run full-screen route in `RootScreen` |
| `showPaywall` | someone reached for the lock | the dismissible cover over `MainScreen` |

`PaywallScreen` takes an `onClose` because the two presentations close
differently: the first-run route records the dismissal (`dismissPaywall()` →
`SleepPersistence.paywallDismissed`, per install, *not* cleared by `reset()`);
the cover just lowers itself. A successful purchase or restore calls it too,
or the cover would stay parked over the app the user just paid for.

The lock's enforcement points, all funnelling through
`presentPaywallIfLocked()` so the paywall explains itself rather than a
control going dead:

- `ui/home/HomeScreen.kt` — Sleep Now raises the paywall instead of the
  confirmation panel. Nothing is greyed out: the button keeps its name and
  its full amber weight, because a disabled button answers no questions.
- `ui/profile/ProfileScreen.kt` — an "Unlock SleepBlock" row replaces the
  Subscription status group while locked.
- `SleepStore.startSleep()` — a final guard, so a future caller that forgets
  to ask still can't start a night.

Android differences from the iOS model, both deliberate:

- **No deep-link enforcement points, because there are no deep links.** iOS
  gates `sleepblock://sleep`, `://tonight` and `://winddown` (widget capsule,
  shield action, Siri intent, bedtime notifications). The Glance widget only
  ever opens `MainActivity` and the shield's "Good night" goes to the
  launcher, so today the slide-to-sleep panel is the only route into
  `startSleep()`. **When a widget action, notification, or Quick Settings
  tile lands, it must call `presentPaywallIfLocked()` first** — the
  `startSleep()` guard catches the mistake, but silently, and the point of
  funnelling is that the paywall sells rather than stands down.
- **No offline grace.** iOS exempts a subscriber whose cached entitlement
  lapsed while they were unreachable (`isWithinOfflineGrace`, a couple of
  days). Android has no equivalent yet; `UNKNOWN`-never-locks is the only
  fail-open bias here. Port it with the entitlement-refresh work.

The cover over Main is a full-screen `Dialog` (`usePlatformDefaultWidth =
false`), the same grammar as the Settings cover, rather than a bottom sheet —
this is the same screen as the first-run pitch and a half-height card would
sell the plan cards short. Its window is added after the Settings dialog's,
so "Unlock SleepBlock" lands the paywall *above* Settings; back-press closes
it, which is what a soft paywall should do. The blocking primer is shown to
subscribers only: usage access and overlay are the most alarming grants the
app asks for, and spending them on someone who cannot start a night yet asks
for the phone in exchange for a feature they can't reach.

## Design language

See DESIGN.md (Warm Pixel Night). Android renders the sanctioned fallback
grammar rather than Liquid Glass: translucent deep-navy surfaces with
hairline borders over the widgets' minimal night gradient (`skyTop →
background` + faint amber floor glow). Palette and type scale are ported
1:1 in `ui/theme/SleepTheme.kt`.
