import DeviceActivity
import ManagedSettings
import FamilyControls
import Foundation

// DeviceActivityMonitor extension: manages the scheduled sleep shield window.
//
// **Interval start** (bedtime arrives): applies the shield to the user's chosen
// apps/categories and writes `LockdownPhase.presleep` so the shield UI shows
// the "Time for bed — Sleep Now" treatment. If the user then opens SleepBlock
// and taps Sleep Now, the main app's `startLockdown()` overwrites the phase to
// `.active` and the next shield render shows the firm "Time to sleep" copy.
//
// **Interval end** (wake time): clears the shield and the phase — but *only if
// no sleep session is running*. A session in progress outranks the clock: the
// block is a promise made to someone who tapped Sleep Now, and it lifts when
// they hold the wake button, not when a timer says the night should be over.
// The wake-time clear survives for the case it is actually needed — a window
// that shielded at bedtime and was never slept through — where there is no
// session to end and nothing else would ever lift it.
//
// This extension runs in its own sandboxed process. It shares state with the
// main app and the shield extensions via the App Group defaults
// (`SleepLockdownShared.swift`).

final class SulavSleepMonitor: DeviceActivityMonitor {
    private let store = ManagedSettingsStore()

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        if activity == sleepActivityName {
            applyShield()
        } else if activity == sleepSnoozeActivityName {
            // A "5 more minutes" grant just ran out — put the shield back.
            reapplyAfterSnooze()
        } else if activity == sleepCapActivityName {
            // Retired: the app no longer arms this. Installs that armed one
            // before the change still carry it until it fires, so answer it —
            // but under the current rule, which means it can no longer cut a
            // running session short. See `sleepCapActivityName`.
            endWindowUnlessSleeping()
            DeviceActivityCenter().stopMonitoring([sleepCapActivityName])
        }
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        // Only the bedtime→wake window ends the lockdown. The snooze and cap
        // activities' ends are deliberately no-ops: they exist only for their
        // *start*, and treating either as "wake time" would be wrong — for the
        // snooze it would unshield the rest of the night.
        guard activity == sleepActivityName else { return }
        endWindowUnlessSleeping()
    }

    /// Wake time arrived. Clear the shield unless the user is still in a sleep
    /// session — the session outranks the clock, and only `wakeUp()` (or
    /// `cancelSleep()`) ends it.
    ///
    /// The phase is the whole test. `.active` is written by the app's
    /// `startLockdown()` at Sleep Now and cleared by `endLockdown()`, so it is
    /// exactly "a session is running" as seen from this sandboxed process,
    /// which has no access to the app's own session record.
    ///
    /// `.presleep` — shielded at bedtime, never slept — clears as it always
    /// did. That case has no session to finish, so without this it would leave
    /// the apps blocked with nothing on any schedule to lift them.
    private func endWindowUnlessSleeping() {
        guard SleepLockdownSelection.currentPhase() != .active else {
            // The window is over as far as the schedule is concerned, so its
            // timed helpers have nothing left to do — but the shield stays.
            DeviceActivityCenter().stopMonitoring([sleepSnoozeActivityName, sleepCapActivityName])
            return
        }
        clearShield()
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        if event == sleepEventName {
            // Legacy max-hours threshold, no longer registered. Installs that
            // armed it before the cap became wall-clock still carry it, so it
            // is still answered — but through the same guard as every other
            // timed path, since a stale event from two rules ago must not be
            // the one thing that can still unblock a sleeping user.
            endWindowUnlessSleeping()
        } else if sleepSnoozeEventNames.contains(event) {
            // A snooze's worth of usage has been spent in the blocked apps —
            // the most dependable signal we get, and the only one that arrives
            // while the user is still holding the app open.
            reapplyAfterSnooze()
        }
    }

    /// Applies the shield at bedtime in the pre-sleep phase. The user hasn't
    /// tapped Sleep Now yet, so the shield copy nudges them toward the app.
    private func applyShield() {
        shieldSelectedApps()
        SleepLockdownSelection.setPhase(.presleep)
        // A new night: fresh snooze allowance, empty reach log, shut door — but
        // only if this really is a new night. `intervalDidStart` is not
        // once-per-window: re-registering the activity while its interval is
        // running fires it again, and resetting unconditionally here turned
        // that into an unlimited snooze supply. See `beginWindowIfNew`.
        SleepLockdownSelection.beginWindowIfNew()
    }

    /// Re-arms the shield when a snooze runs out, from either trigger: the
    /// wall-clock `sleepSnoozeActivityName` interval or a usage threshold.
    /// Deliberately leaves the phase and the spent-snooze count alone: the user
    /// is still in the same window, and resetting the count here would hand out
    /// an unlimited supply.
    ///
    /// The phase guard is the whole safety check — outside a lockdown window
    /// there is nothing to re-arm. Inside one, re-shielding is always the safe
    /// direction, so a threshold that fires without a snooze outstanding (usage
    /// banked before the shield landed, say) is allowed to put the shield back.
    private func reapplyAfterSnooze() {
        guard SleepLockdownSelection.currentPhase() != nil else { return }
        shieldSelectedApps()
        SleepLockdownSelection.clearSnoozeWindow()
        // The slow door shares this re-arm: it is the same shape of grant (the
        // shield lifted for a fixed span) and re-shielding is the same action,
        // so there is no second activity to register or lose.
        SleepLockdownSelection.clearDoor()
        // Whichever trigger lost the race, its schedule has nothing left to do.
        DeviceActivityCenter().stopMonitoring([sleepSnoozeActivityName])
    }

    private func shieldSelectedApps() {
        let selection = SleepLockdownSelection.decode(
            SleepLockdownSelection.groupDefaults()?.data(forKey: SleepLockdownSelection.selectionKey)
        )
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty
            ? nil
            : .specific(selection.categoryTokens)
    }

    private func clearShield() {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        SleepLockdownSelection.clearPhase()
        SleepLockdownSelection.resetSnoozes()
        SleepLockdownSelection.clearDoor()
        // The reach log deliberately survives the night — the morning mirror
        // reads it after the shield is long gone, and the app clears it when it
        // has been harvested into history.
        // The night is over however we got here, so neither timed activity has
        // anything left to do. Retiring the cap matters most: left armed, it
        // would fire partway through a later night and drop that shield.
        DeviceActivityCenter().stopMonitoring([sleepSnoozeActivityName, sleepCapActivityName])
    }
}
