import DeviceActivity
import ManagedSettings
import Foundation

// DeviceActivityMonitor extension: a safety net around the sleep shield that
// the app applies directly (SleepStore.startSleep -> ScreenTimeService.startLockdown)
// when the user taps Sleep Now. This extension never *applies* the shield — it
// only clears it at the scheduled wake time or once the user-specified max
// duration is reached, in case the app never runs wakeUp() (e.g. it's not
// reopened in the morning). Reads the same App Group state the app writes
// (SleepLockdownShared.swift).

final class SulavSleepMonitor: DeviceActivityMonitor {
    private let store = ManagedSettingsStore()

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

    private func clearShield() {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
    }
}
