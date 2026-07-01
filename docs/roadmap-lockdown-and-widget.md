# Roadmap: Sleep Lockdown + Home-Screen Widget

This documents the two big features so we build them right. The product is
evolving from a passive sleep *log* into a sleep-*enforcement* habit tool: when
you log sleep, the phone becomes (nearly) useless until you wake or a set number
of hours pass — plus a widget that shows your sleep graph and score.

Status: **planned**. Current app has the calm nightly loop, real HealthKit data,
and the immersive sleep-mode screen — but does **not** yet enforce anything.

---

## Feature 1 — Sleep lockdown (Screen Time / Family Controls)

### Goal
After "Sleep Now" (or at the scheduled bedtime), shield the user's distracting
apps for the sleep window (default until wake, or N user-specified hours), so the
phone is effectively useless except for essentials.

### Platform reality (must set expectations)
iOS does **not** let an app block other apps freely. The only sanctioned path is
Apple's **Screen Time API (Family Controls)**, and it has hard limits:

- Requires the **`com.apple.developer.family-controls`** entitlement, which
  Apple grants only after a request (a form, reviewed manually). There is a
  development mode for testing before approval.
- Works on a **real device only** — not in the Simulator.
- You cannot silently block "everything except emergency apps." You shield a
  **user-selected** set of apps/categories chosen via the system
  `FamilyActivityPicker` (their tokens are opaque and privacy-preserving — the
  app never learns which apps they are). Phone, Messages, and Emergency SOS
  remain available at the OS level regardless.
- Shielded apps show a system "blocked" screen; you can customize its text and a
  single action button, but you cannot fully replace the OS behavior.

So the honest framing for users: *"Pick the apps to lock during sleep. Calls and
emergencies always work."*

### Architecture
```
FamilyControls        AuthorizationCenter.shared.requestAuthorization(for: .individual)
ManagedSettings       ManagedSettingsStore().shield.applications = selection.applicationTokens
DeviceActivity        schedule bedtime→wake; DeviceActivityMonitor extension applies/clears shields
FamilyActivityPicker  SwiftUI picker → FamilyActivitySelection (persisted via App Group)
```

Components to add:

1. **Entitlement + capability**: add `com.apple.developer.family-controls` to
   `SulavSleep.entitlements`; request the capability from Apple.
2. **`ScreenTimeService`** (behind a protocol, like `SleepHealthProviding`):
   - `requestAuthorization()`
   - `startLockdown(until:)` → set `ManagedSettingsStore().shield.applications`
   - `endLockdown()` → clear the shield
   - a `FamilyActivitySelection` chosen by the user and stored in the App Group.
3. **DeviceActivityMonitor app extension** (new target): applies the shield at
   `intervalDidStart` (bedtime) and clears it at `intervalDidEnd` (wake time), so
   enforcement works even if the app isn't foregrounded. Also enforces the
   "N hours" cap.
4. **Wire into the sleep loop**: `startSleep()` → `startLockdown`; `wakeUp()` and
   the scheduled window end → `endLockdown`. `cancelSleep()` must also clear it.
5. **Settings UI**: a `FamilyActivityPicker` sheet ("Apps to lock during sleep")
   + a "lock for" duration control, plus an authorization/onboarding step.

### Constraints to honor
- `cancelSleep()` and `wakeUp()` must always be able to lift the shield (never
  trap the user).
- Respect an emergency escape (Apple provides Emergency SOS regardless; consider
  a deliberate, friction-ful "end early" that logs the break for the habit view).
- Everything degrades gracefully when authorization is denied — the app stays a
  working sleep log (today's behavior).

---

## Feature 2 — Home-screen widget (WidgetKit)

### Goal
A home-screen widget showing the last-7-nights sleep graph and the latest sleep
score, so the habit is visible without opening the app.

### Architecture
1. **App Group** (`group.com.anonymous.sulav-sleep`) shared between the app and
   the widget. Move the persisted snapshot (or a compact widget summary:
   last 7 durations + latest score + streak) into the shared container so the
   widget can read it. Update `SleepPersistence` to write to the App Group.
2. **Widget extension** (new target) with:
   - a `TimelineProvider` that reads the shared summary and refreshes on write
     (call `WidgetCenter.shared.reloadAllTimelines()` from the app after
     `wakeUp()` / Health import).
   - `systemSmall` (score + tiny sparkline) and `systemMedium` (7-night wave
     chart + averages), reusing the `WeeklyChart` drawing.
3. **Optional — Live Activity**: while asleep, a Dynamic Island / lock-screen
   Live Activity showing the elapsed timer and a "Wake up" deep link. Uses
   ActivityKit; complements sleep mode nicely.

### Constraints
- Widgets can't run arbitrary code on a schedule; refresh is budgeted. Push
  updates from the app on state changes and use a modest timeline cadence.
- Keep the shared summary tiny and Codable; don't put the whole history in the
  App Group if not needed.

---

## Suggested build order
1. App Group + move persistence into it (prereq for the widget). Low risk.
2. Widget extension (small + medium). Not entitlement-gated — ship first.
3. Live Activity for active sleep (optional, high delight).
4. Screen Time: request entitlement → `ScreenTimeService` + picker + auth UI →
   `DeviceActivityMonitor` extension → wire to the sleep loop. Test on device.

## New project pieces this will require
- Targets: `SulavSleepWidget` (WidgetKit), `SulavSleepMonitor`
  (DeviceActivityMonitor). Both need the App Group; the monitor needs
  Family Controls.
- Entitlements: App Group (app + both extensions), Family Controls (app +
  monitor).
- Info.plist: `NSFamilyControlsUsageDescription` (if prompting copy is needed).
