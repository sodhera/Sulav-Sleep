# SleepBlock Product Brief

SleepBlock is a bedtime commitment app. The native iOS version focuses on a
calm nightly loop: choose a sleep schedule, start a sleep session, wake up, and
review the rhythm of recent nights — using **real data only**.

## Current product

- Welcome offers Get started and independent Sign in paths. The iOS setup is
  now ten steps: name; a required 0–4+ hour bedtime-phone dial; four optional
  symptom selections; a personalized attention story ending in a night goal;
  desired morning; bedtime; wake time; encouragement; a looping "Protect your
  attention" iPhone demo; and a two-second Hold to commit. Text chapters reveal
  letter by letter with stable word positions, alternating white/yellow lines,
  short groups, and a slide labeled Continue. Account
  creation follows commitment for signed-out users. Already authenticated users
  finish directly. The former "your plan is ready" summary is removed.
- Setup always shows a starry midnight city with warm windows. Daily Home
  lighting remains phase-aware. Time-cost figures use exact dial minutes;
  lifetime days are explicitly an illustration at that daily rate over 80 years.
- The demo is a simulator recreation of a TikTok tap, opening logo, progressive
  grayscale, then a SleepBlock shield. The page asks "Are you ready to protect
  your mind against the enemy?" and answers **Yes**. It is not evidence of real TikTok blocking. Real
  permissions and app selection still happen through Apple's Screen Time flow.
- **SleepBlock is a subscription.** Right after the questionnaire commits, the
  paywall (RevenueCat; annual with a free trial, or monthly) appears at the
  moment of highest intent, after the user sets their target schedule. It is
  a **soft** paywall: a ✕ closes it and the user gets the whole app to look at. What they cannot do without subscribing is **start a
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
- Setup saves an unfinished questionnaire locally, including the current step.
  The retired app-name question has been removed. Real app selection occurs
  in Apple’s system picker after permission.
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

Local-first, with cloud backup for signed-in profiles and logged sleep sessions
through Supabase, plus optional two-way Apple Health sync. The device remains
the primary working copy; cloud sync lets a signed-in user restore their
schedule and logged nights on another device. Imported HealthKit sessions
remain device-local.

- Local: UserDefaults-backed JSON, keys `sulav.profile.v1`,
  `sulav.sessions.v1`, `sulav.active.v1`, `sulav.account.v1`.
- Apple Health: reads sleep history and writes logged nights via
  `HKCategoryType(.sleepAnalysis)`. Entirely optional — if the user declines or
  the device lacks HealthKit, the app works fully from local logging.
- Accounts: Sign in with Apple, Google, or email/password via Supabase Auth,
  required once after onboarding. The session token lives in the Keychain.
- Cloud: Supabase stores the completed profile and in-app sleep sessions under
  the authenticated account. See `SleepCloudService.swift` and
  `docs/development.md` for the sync and restore behavior.

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

## Conversion measurement

Named first-party analytics are always on in this local iOS revision, as requested
on September 17. The app records named setup screens and taps, authentication
outcomes, paywall actions, purchase results, Screen Time activation, and first
sleep use. The client never sends entered answers, selected app tokens, or sleep
records to the product-events table. RevenueCat webhook events separately mark
trials, payments, renewals, cancellations, and refunds for funnel analysis.
The new iOS setup has a fixed midnight design; the previous copy/scene variant
settings do not override it. Before distribution, reconcile the published
optional-analytics policy and App Store privacy answers. Simulator QA sends no
product events. No live policy change is included in this implementation.
