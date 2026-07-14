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
and no paywall gates (there is no paywall at all yet, see the parity map).

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
- Profile: stat band, 7-night bar rhythm, recent nights, settings (rename,
  schedule steppers, sign out, delete account). Honest data only — no
  seeded history.

Deferred to phase 2 (each is its own project):

- **App blocking.** Android has no Screen Time shield equivalent; the plan
  is UsageStats/`UsageEvents` detection + an overlay (or Accessibility
  Service), which is Play-policy sensitive and needs its own design pass.
  Until then the sleep confirmation states "No apps blocked tonight".
- **Paywall.** RevenueCat purchases-android + Google Play products. The
  BuildConfig key is already plumbed; entitlement currently resolves
  "entitled" (dev-mode policy).
- **Google sign-in** (Credential Manager), Health Connect import, home-screen
  widgets, the pixel-art living scene, the sloth brand art (launcher icon is
  a placeholder crescent — export real art via the iOS
  `scripts/generate-app-icon.py` pipeline), Material haptics pass.

## Design language

See DESIGN.md (Warm Pixel Night). Android renders the sanctioned fallback
grammar rather than Liquid Glass: translucent deep-navy surfaces with
hairline borders over the widgets' minimal night gradient (`skyTop →
background` + faint amber floor glow). Palette and type scale are ported
1:1 in `ui/theme/SleepTheme.kt`.
