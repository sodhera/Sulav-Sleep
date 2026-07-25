import Foundation
import DeviceActivity
import FamilyControls

// Shared between the app and the SulavSleepMonitor DeviceActivityMonitor
// extension. Kept free of SwiftUI/ManagedSettings-UI so both targets compile.

let sleepActivityName = DeviceActivityName("sulav.sleep.schedule")
let sleepEventName = DeviceActivityEvent.Name("sulav.sleep.maxDuration")

/// A second, short-lived activity used purely to re-arm the shield after a
/// "5 more minutes" snooze. Separate from `sleepActivityName` so its interval
/// callbacks can't be mistaken for bedtime/wake — its start re-applies the
/// shield without resetting the night's snooze allowance, and its end is a
/// no-op rather than "wake up, clear everything".
let sleepSnoozeActivityName = DeviceActivityName("sulav.sleep.snooze")

/// Which blocking phase is active, communicated via App Group UserDefaults so
/// the shield configuration and shield action extensions (which run in separate
/// sandboxed processes) can tailor their UI.
///
/// - `presleep`: Bedtime has arrived but the user hasn't tapped Sleep Now.
///   The shield nudges the user toward the app ("Time for bed — Sleep Now").
/// - `active`: The user tapped Sleep Now and a sleep session is running.
///   The shield is the firm lockdown ("Time to sleep — Good night").
///
/// Written by `ScreenTimeService` and `SulavSleepMonitor`; read by
/// `ShieldConfigProvider` and `ShieldActionHandler`.
enum LockdownPhase: String {
    case presleep
    case active
}

enum SleepLockdownSelection {
    static let selectionKey = "sulav.lock.selection.v1"
    /// App Group key for the current lockdown phase (see `LockdownPhase`).
    static let phaseKey = "sulav.lock.phase"

    static func decode(_ data: Data?) -> FamilyActivitySelection {
        guard let data, let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else {
            return FamilyActivitySelection()
        }
        return selection
    }

    static func encode(_ selection: FamilyActivitySelection) -> Data? {
        try? JSONEncoder().encode(selection)
    }

    static func groupDefaults() -> UserDefaults? {
        UserDefaults(suiteName: SleepWidgetStore.appGroup)
    }

    // MARK: - Phase helpers

    static func currentPhase() -> LockdownPhase? {
        guard let raw = groupDefaults()?.string(forKey: phaseKey) else { return nil }
        return LockdownPhase(rawValue: raw)
    }

    static func setPhase(_ phase: LockdownPhase) {
        groupDefaults()?.set(phase.rawValue, forKey: phaseKey)
    }

    static func clearPhase() {
        groupDefaults()?.removeObject(forKey: phaseKey)
    }

    // MARK: - Snooze ("5 more minutes")

    /// Bedtime as minutes-from-midnight, so the shield can tell the user how
    /// far past it they are. The shield extensions can't reach the app's
    /// profile, so the scheduler mirrors it here.
    static let bedtimeKey = "sulav.lock.bedtimeMinutes"
    /// When the current snooze expires (`timeIntervalSince1970`). Absent when
    /// no snooze is running.
    static let snoozeUntilKey = "sulav.lock.snoozeUntil"
    /// Snoozes already spent in this lockdown window.
    static let snoozeCountKey = "sulav.lock.snoozeCount"

    /// Minutes granted per snooze, and how many a single lockdown window
    /// allows. Capped because an uncapped snooze is an off switch with extra
    /// steps — the whole point is that the escape hatch runs out.
    static let snoozeMinutes = 5
    static let snoozeLimit = 2

    static func setBedtimeMinutes(_ minutes: Int) {
        groupDefaults()?.set(minutes, forKey: bedtimeKey)
    }

    static func bedtimeMinutes() -> Int? {
        groupDefaults()?.object(forKey: bedtimeKey) as? Int
    }

    static func snoozesSpent() -> Int {
        groupDefaults()?.integer(forKey: snoozeCountKey) ?? 0
    }

    static var snoozeAvailable: Bool { snoozesSpent() < snoozeLimit }

    /// Spends one snooze and returns when it expires. Caller is responsible
    /// for actually lifting the shield and arranging the re-arm.
    @discardableResult
    static func consumeSnooze(now: Date = Date()) -> Date {
        let until = now.addingTimeInterval(Double(snoozeMinutes) * 60)
        groupDefaults()?.set(snoozesSpent() + 1, forKey: snoozeCountKey)
        groupDefaults()?.set(until.timeIntervalSince1970, forKey: snoozeUntilKey)
        return until
    }

    static func snoozeUntil() -> Date? {
        guard let raw = groupDefaults()?.object(forKey: snoozeUntilKey) as? Double else { return nil }
        return Date(timeIntervalSince1970: raw)
    }

    /// True when a snooze was granted and its time is up — the shield should
    /// be back on. Checked defensively by the app and the monitor, because the
    /// timed re-arm is the least reliable link in the chain.
    static func snoozeHasExpired(now: Date = Date()) -> Bool {
        guard let until = snoozeUntil() else { return false }
        return now >= until
    }

    /// Ends the current snooze without touching the spent count.
    static func clearSnoozeWindow() {
        groupDefaults()?.removeObject(forKey: snoozeUntilKey)
    }

    /// Fresh allowance — called when a lockdown window opens at bedtime.
    static func resetSnoozes() {
        groupDefaults()?.removeObject(forKey: snoozeCountKey)
        clearSnoozeWindow()
    }
}
