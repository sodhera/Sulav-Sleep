# SleepBlock Product Brief

SleepBlock is a bedtime commitment app. The native iOS version focuses on a
calm nightly loop: choose a sleep schedule, start a sleep session, wake up, and
review the rhythm of recent nights — using **real data only**.

## Current product

- A welcome screen offers two independent paths. **Sign up**: a questionnaire
  (name, what gets in the way of sleep, which apps keep you up, usual bedtime,
  usual wake time) whose final step is account creation, framed as saving the
  plan — questions come first because invested users sign up at a higher rate,
  and the account step carries the same progress bar and back button as the
  rest of the flow. **Sign in**: a standalone screen (Apple, Google, or manual
  email/password), then the same questions as a quick setup on a device with
  no profile. The two paths don't cross-link — you choose on the welcome
  screen.
- **SleepBlock is a subscription.** Right after the questionnaire commits, a
  hard paywall (RevenueCat; annual with a 7-day free trial, or monthly) is the
  only door into the app — placed there deliberately, at the moment of highest
  intent, when the user has just articulated what breaks their sleep and which
  apps eat their night. The paywall answers with those exact apps. There is no
  free tier: a behavior-change app has to let people *feel* the fix, so the
  trial gives the whole product for a week rather than a crippled subset
  forever. (An unconfigured build — no RevenueCat key — runs without the
  paywall for development.)
- Apple Health is offered *after* onboarding, via a dismissable prompt card at
  the top of Profile (which also keeps the toggle), rather than interrupting
  sign-up with a permission sheet.
- Home is a pure "go to bed" screen: greeting, bedtime countdown, `Sleep Now`,
  and a last-night summary (duration, color-coded score, streak) — or an honest
  empty state when nothing has been logged yet.
- Active sleep mode hides navigation, shows elapsed time, and offers a single
  `Wake up` action.
- Profile is everything about the user: editable name and account email, a
  seven-night chart, average duration/score, and a history list where each
  night is tagged by source (in-app vs. Apple Health; empty until there is real
  data). A gear in its top-right opens a full-screen Settings cover: sleep
  schedule, blocked apps (Screen Time selection), Apple Health sync, and sign
  out. There is no "reset all data" action.

## No dummy data

There is no seeded/sample history. The app shows only:

1. nights the user logs in-app with Sleep Now / Wake up, and
2. real sleep imported from Apple Health (if connected).

The two are merged and de-duplicated per night, so a night written to Health is
never double counted.

## Storage & sync

Local-first, with optional two-way Apple Health sync. Accounts (Supabase
Auth) exist alongside this purely as an identity gate — sleep data itself is
not synced to a server today.

- Local: UserDefaults-backed JSON, keys `sulav.profile.v1`,
  `sulav.sessions.v1`, `sulav.active.v1`, `sulav.account.v1`.
- Apple Health: reads sleep history and writes logged nights via
  `HKCategoryType(.sleepAnalysis)`. Entirely optional — if the user declines or
  the device lacks HealthKit, the app works fully from local logging.
- Accounts: Sign in with Apple, Google, or email/password via Supabase Auth,
  required once after onboarding. The session token lives in the Keychain;
  see `docs/development.md` and `docs/auth-setup.md`.

## Native direction

SwiftUI-first. Native iOS is the right base for the system-level integrations
the product leans on: HealthKit, App Intents, Shortcuts, Liquid Glass, and later
widgets and Screen Time-style permissions.

Platform reality: iOS does not let an app silently toggle Accessibility Color
Filters or block other apps without user-controlled system permissions. Any
future enforcement work must live behind native platform capabilities and be
documented before implementation.

The next major direction is **sleep enforcement**: after logging sleep, the phone
becomes nearly useless (user-selected apps shielded) until wake or a set number
of hours — plus a home-screen widget with a sleep graph and score. Both are
planned in detail in `docs/roadmap-lockdown-and-widget.md` (Screen Time /
Family Controls + WidgetKit, with their platform constraints).

## Visual direction — Warm Pixel Night

The app should feel like a warm apartment window over a quiet city night (see
`DESIGN.md`): a living, layered pixel night scene behind a minimal, editorial
Liquid Glass interface. Warm amber indoor light against deep navy; no purple, no
neon. Low stimulation at night, sparse during active sleep, and legible under a
red night tint.
