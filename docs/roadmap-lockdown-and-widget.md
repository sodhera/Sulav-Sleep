# Roadmap: Sleep Lockdown + Home-Screen Widget

This documents the two big features so we build them right. The product is
evolving from a passive sleep *log* into a sleep-*enforcement* habit tool: when
you log sleep, the phone becomes (nearly) useless until you wake or a set number
of hours pass — plus a widget that shows your sleep graph and score.

Status: **largely implemented** (see "What's built" below). The widget ships and
works in the Simulator. The Screen Time lockdown is fully coded and wired;
real enforcement runs on a device once Apple grants the Family Controls
capability.

## What's built

- **Home-screen widget** — `SulavSleepWidgetExtension` (WidgetKit): small
  (last score + mini bars) and medium (7-night bar graph + avg + streak),
  reading a compact summary from the App Group `group.com.sulav.sleepblock`.
  `SleepStore` publishes the summary and reloads timelines on every change.
- **Sleep lockdown** — `SleepScreenTime.swift`: `ScreenTimeService`
  (FamilyControls `AuthorizationCenter` + `ManagedSettings` shield), a
  `FamilyActivityPicker` UI (`LockdownSettingsView`), and wiring so
  `startSleep()` shields the chosen apps and `wakeUp()`/`cancelSleep()` clear
  them. The `com.apple.developer.family-controls` entitlement is applied to
  **device builds only** (via `SulavSleep-device.entitlements` and a
  `CODE_SIGN_ENTITLEMENTS[sdk=iphoneos*]` build setting), so the Simulator keeps
  building/testing/running; on the Simulator the service reports `.unavailable`
  and every call is a no-op.

- **Scheduled/background enforcement** — `SulavSleepMonitor` (DeviceActivityMonitor
  extension) is a clear-only safety net: it never applies the shield (only
  `startSleep()` -> `ScreenTimeService.startLockdown()` does, when the
  user taps Sleep Now), and it clears at the scheduled wake time **only when no
  session is running** — a session's shield ends with the session, never on a
  clock. The user-set max-hours cap is retired. It is the safety net for the
  window that shielded at bedtime and was never slept through — with no session
  to end, nothing else would lift it. Reads the
  App-Group-stored app selection via `SleepLockdownShared.swift`. The
  bedtime→wake window is scheduled via `ScreenTimeService.scheduleLockdown`
  whenever lockdown is enabled or the schedule/selection changes. (Historical:
  a cap was a separate one-shot activity (`sleepCapActivityName`) armed per
  session, counting wall-clock hours from Sleep Now. It is retired — the shield
  now ends with the session, never on a clock. See `docs/development.md`.)
- **Live Activity** — `SleepActivityAttributes` + `SleepLiveActivity` (app side,
  starts/ends the activity) and `SulavSleepLiveActivity` (widget-side Lock
  Screen + Dynamic Island view) show the live elapsed-sleep timer without
  polling, via `Text(timerInterval:)`.

## What's still to do

- Request the Family Controls capability from Apple for the dev account (needed
  for real enforcement on device; everything else is code-complete).

- ~~**Staged edits ("only tightens")**~~ — **closed by gating instead.** The two
  doors this item tracked (the "Block while you sleep" toggle and clearing the
  app selection, both of which called `endLockdown()` on the spot) are shut:
  the Blocked apps surface is closed for as long as the lock holds —
  `SleepStore.lockdownSettingsLocked`, i.e. a running session or a live shield
  phase. Neither entry point pushes, the screen itself renders a locked panel if
  it was already open, and the store refuses both writes. See
  "The lockdown settings close while the lockdown holds" in
  `docs/development.md`.

  Gating won over staging on cost and honesty. Staging needed a
  `pendingLockdownEdit` blob on `Profile`, a merge rule per field, and UI copy
  for "saved, takes effect tomorrow" — a lot of machinery whose best case is
  a change the user made and cannot see. A closed screen with a date on it says
  the same thing in one line and cannot silently evaporate.

  The same gate now covers **Sleep schedule** and **the reasons** as well — the
  schedule because a held edit that reports success is its own kind of lie, the
  reasons because clearing them mid-night disarms the shield's argument without
  touching the shield.

  What staging would still buy, if it's ever wanted: **tightening** mid-window
  (adding apps, a later wake) currently waits for the window to close along
  with everything else. That direction is always safe to apply immediately, so
  it stays a legitimate follow-up — with the same two constraints as before:
  the slow door stays the single sanctioned exit, no staged edit may interfere
  with a running session, and when anything is ambiguous, fail toward
  *unlocking*.

  Known next exploit, tracked separately: moving the **device clock** past wake
  time ends the window. Mitigation is a monotonic reference (boot uptime) taken
  at window start, cross-checked against Supabase server time on next sync.

  Worth stating plainly: none of this is airtight. Deleting the app or revoking
  Screen Time in Settings drops the shield, and that is Apple's design. The goal
  is making the escape cost more than the scroll is worth for the wavering
  majority, not defeating a determined user.

---

_Original plan follows._

---

## Feature 1 — Sleep lockdown (Screen Time / Family Controls)

### Goal
After the user taps "Sleep Now", shield the user's distracting apps for the
sleep window (default until wake, or N user-specified hours), so the phone is
effectively useless except for essentials. The shield is deliberately
**never** applied automatically at the scheduled bedtime — only an explicit
user action starts it; the background schedule exists solely to clear it.

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
3. **DeviceActivityMonitor app extension** (new target): clear-only safety net —
   clears the shield at `intervalDidEnd` (wake time) when no session is
   running, so an unslept window still lifts if the app isn't foregrounded. Does
   *not* apply the shield at `intervalDidStart`; only `startLockdown()` does.
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
1. **App Group** (`group.com.sulav.sleepblock`) shared between the app and
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
