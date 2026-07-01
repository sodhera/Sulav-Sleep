import DeviceActivity
import ManagedSettings
import Foundation

// DeviceActivityMonitor extension: applies/clears the sleep shield on the
// scheduled bedtime->wake interval even if the app isn't foregrounded, and lifts
// it early if the user-specified max duration is reached. Reads the same
// App Group state the app writes (SleepLockdownShared.swift).

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

    private func applyShield() {
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
    }
}
