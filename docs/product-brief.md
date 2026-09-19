# SleepBlock Product Brief

SleepBlock is a bedtime commitment app. The native iOS version focuses on a
calm nightly loop: choose a sleep schedule, start a sleep session, wake up, and
review the rhythm of recent nights — using **real data only**.

## Current product

- Welcome offers Get started and independent Sign in paths. The iOS setup is
  **eleven beats**, alternating ask and reveal: in-bed time; wake time; a
  required phone-in-bed slider; a sleep calibration the app pre-fills from the
  first three answers; the AASM 7–9 hour recommendation band with the user's
  figure plotted on it; **the year of nights** (365 cells, the ones spent
  awake on a phone lit amber); a short narrative naming the phone, resolving
  into the night-goal choice; the plan; name; a looping shield demo titled
  with the user's own bedtime; and a two-second Hold to commit. Account
  creation follows commitment for signed-out users. Already authenticated
  users finish directly.
- **Three inputs derive everything.** In-bed, wake and phone-in-bed are the
  only figures asked for; the shortfall, the year-of-nights count and the plan
  are all unit conversions of those (`SleepDebt`, `SleepModels.swift`).
  Nothing is measured or modelled, and every reveal captions itself with the
  answer it came from. The recommendation floor is the bottom of the 7–9 band,
  not its middle, so no figure is overstated. See `DESIGN.md` → "Sign-up flow".
- Text chapters reveal letter by letter with stable word positions,
  alternating white/yellow lines, and short groups. The flow has exactly two
  controls — one primary button for every forward step, and the commitment
  hold — replacing an earlier mix of taps, a slide-to-continue capsule, and
  the hold.
- **One starry background throughout iOS.** Welcome, setup, Home, Profile,
  Settings, partners, paywalls, and wake summary share the sign-up stage's
  navy sky, sparse animated stars, grain, and low ember horizon. Setup deepens
  as it advances; regular screens use its initial depth. The legacy city is
  retired. Active sleep remains true OLED black for bedside use.
- The retired flow's symptom multi-select,
  desired-morning question, phone dial, and the 80-year "days in a life"
  figure are all gone — the last because an 80-year extrapolation is not a
  number the product can move, which is the test a hero figure has to pass.
- The demo is a simulator recreation of a TikTok tap, opening logo, progressive
  grayscale, then a SleepBlock shield. The page is titled "This is what
  {bedtime} looks like now." and answered **That's what I want**. It is not
  evidence of real TikTok blocking. Real permissions and app selection still
  happen through Apple's Screen Time flow.
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
- Setup saves an unfinished questionnaire locally, including the current step
  (`sulav.onboardingDraft.v2`; a v1 draft holds the retired answer set and is
  left to expire rather than half-restored). A restored draft never resumes
  past a missing required answer. Real app selection occurs in Apple’s system
  picker after permission.
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
`DESIGN.md`): a quiet starry night stage behind a minimal, editorial
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
settings do not override it. The privacy-policy source in `sodhera/orecci`
(commit `1e8b249`) describes automatic iOS events; verify its publication and
reconcile App Store privacy answers before distribution. Simulator QA sends no
product events.
