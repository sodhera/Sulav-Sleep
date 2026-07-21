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
        guard activity == sleepActivityName else { return }
        applyShield()
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
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
        let selection = SleepLockdownSelection.decode(
            SleepLockdownSelection.groupDefaults()?.data(forKey: SleepLockdownSelection.selectionKey)
        )
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty
            ? nil
            : .specific(selection.categoryTokens)
        SleepLockdownSelection.setPhase(.presleep)
    }

    private func clearShield() {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        SleepLockdownSelection.clearPhase()
    }
}
