# Sulav Sleep Product Brief

Sulav Sleep is a bedtime commitment app. The native iOS version focuses on a
calm nightly loop: choose a sleep schedule, start a sleep session, wake up, and
review the rhythm of recent nights — using **real data only**.

## Current product

- Onboarding collects name, usual bedtime, usual wake time, and offers to
  connect Apple Health.
- Home shows a greeting, tonight's schedule, `Sleep Now`, `Set Bedtime`, and a
  last-night summary (duration, color-coded score, streak) — or an honest empty
  state when nothing has been logged yet.
- Active sleep mode hides navigation, shows elapsed time, and offers a single
  `Wake up` action.
- Reports shows a seven-night chart, average duration/score, and a history list
  where each night is tagged by source (in-app vs. Apple Health). Empty until
  there is real data.
- Settings edits name and schedule, toggles Apple Health sync, or resets data.

## No dummy data

There is no seeded/sample history. The app shows only:

1. nights the user logs in-app with Sleep Now / Wake up, and
2. real sleep imported from Apple Health (if connected).

The two are merged and de-duplicated per night, so a night written to Health is
never double counted.

## Storage & sync

Local-first, with optional two-way Apple Health sync.

- Local: UserDefaults-backed JSON, keys `sulav.profile.v1`,
  `sulav.sessions.v1`, `sulav.active.v1`.
- Apple Health: reads sleep history and writes logged nights via
  `HKCategoryType(.sleepAnalysis)`. Entirely optional — if the user declines or
  the device lacks HealthKit, the app works fully from local logging.

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
