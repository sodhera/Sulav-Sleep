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
// **Interval end** (wake time) / **event threshold** (max-hours cap): clears
// the shield and the phase, whether or not the user ever started a session.
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
        }
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        // Only the bedtime→wake window ends the lockdown. The snooze activity's
        // end is deliberately a no-op: it exists only for its *start*, and
        // treating it as "wake time" would unshield the rest of the night.
        guard activity == sleepActivityName else { return }
        clearShield()
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        guard event == sleepEventName else { return }
        clearShield()
    }

    /// Applies the shield at bedtime in the pre-sleep phase. The user hasn't
    /// tapped Sleep Now yet, so the shield copy nudges them toward the app.
    private func applyShield() {
        shieldSelectedApps()
        SleepLockdownSelection.setPhase(.presleep)
        // A new night, a fresh allowance. Tying the reset to the interval
        // start rather than a calendar date means it lines up exactly with the
        // lockdown window, including one that crosses midnight.
        SleepLockdownSelection.resetSnoozes()
    }

    /// Re-arms the shield when a snooze expires. Deliberately leaves the phase
    /// and the spent-snooze count alone: the user is still in the same window,
    /// and resetting the count here would hand out an unlimited supply.
    private func reapplyAfterSnooze() {
        guard SleepLockdownSelection.currentPhase() != nil else { return }
        shieldSelectedApps()
        SleepLockdownSelection.clearSnoozeWindow()
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
    }
}
