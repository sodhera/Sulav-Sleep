# SleepBlock Product Brief

SleepBlock is a bedtime commitment app. The native iOS version focuses on a
calm nightly loop: choose a sleep schedule, start a sleep session, wake up, and
review the rhythm of recent nights — using **real data only**.

## Current product

- A welcome screen offers two independent paths. **Sign up**: a ten-step
  questionnaire building an investment arc — name, the one goal that matters
  most, what gets in the way of sleep, which apps keep you up, how long the
  phone keeps you up after you're in bed, how you wake up, the bedtime and
  wake time you want (the schedule the app then holds you to) — closing with
  a **plan reveal** ("Building your sleep plan…" resolving into a
  three-part summary: nightly sleep, time to win back per week, and the
  chosen goal, under an "I'm ready" commitment button)
  and, as the final step, account creation framed as saving that plan. Questions come first because invested users sign up at
  a higher rate; every question feeds the plan/paywall personalization, and
  the account step carries the same progress bar and back button as the rest
  of the flow. **Sign in**: a standalone screen (Apple, Google, or manual
  email/password), then the same questions as a quick setup on a device with
  no profile. The two paths don't cross-link — you choose on the welcome
  screen.
- **SleepBlock is a subscription.** Right after the questionnaire commits, the
  paywall (RevenueCat; annual with a free trial, or monthly) appears at the
  moment of highest intent, when the user has just articulated what breaks
  their sleep and which apps eat their night — the paywall answers with those
  exact apps. It is a **soft** paywall: a ✕ closes it and the user gets the
  whole app to look at. What they cannot do without subscribing is **start a
  night** — the one action the product exists to perform. Everything the app
  shows is free; everything it does is the subscription. (An unconfigured
  build — no RevenueCat key — runs unlocked for development.)
- **Growth is the sleep partner.** The referral and the partner feature are
  one program: invite a friend to *do this with you* — you see each other's
  streak and schedule (derived numbers only, mutual consent, either side can
  unlink) — and the invite carries the economics: they get 30 nights free
  instead of 7, and their first paid payment gives you a month free (a real
  App Store renewal extension, capped at six earned months a year). The ask
  is a relationship, not a coupon.
- After the paywall, a one-time **Screen Time primer** uses an interactive
  preview of the iOS permission dialog. Its Continue action requests the
  Family Controls authorization directly; Not now skips it, with no duplicate
  app CTA below the card. A grant flows straight into the system app picker.
  It is per-install: deleting the app and signing back in — which drops the
  authorization — shows it again, and the Blocked apps screen remains the
  fixup path.
- Apple Health is offered *after* onboarding, via a dismissable prompt card at
  the top of Profile (which also keeps the toggle), rather than interrupting
  sign-up with a permission sheet.
- Home is a pure "go to bed" screen: greeting, bedtime countdown, `Sleep Now`,
  and a last-night summary (duration and streak) — or an honest empty state
  when nothing has been logged yet. The streak rewards **showing up**, not
  sleeping well: any night of 30+ minutes keeps it, one missed night leaves it
  dying (a hollow flame), two in a row resets it. Whether you slept *enough*
  is the job of the duration hero, the chart, and the target chip.
- Active sleep mode hides navigation on true OLED black and leads with the
  sleeping sloth, elapsed time, and wake target. A quiet **Wake controls**
  prompt reveals three deliberately weighted choices: hold to wake and save,
  tap to return to sleep, or cancel without saving through an honest system
  confirmation. A qualifying night closes on a restrained morning summary:
  the sleep duration is the dominant value inside one glass surface, with the
  actual sleep window and live streak as supporting facts, then one **Start the
  day** action. A one-shot warm pixel sunrise supplies the celebration without
  adding congratulatory copy or looping confetti.
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
