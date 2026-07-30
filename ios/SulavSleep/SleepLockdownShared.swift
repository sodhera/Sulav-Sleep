import Foundation
import DeviceActivity
import FamilyControls

// Shared between the app and the SulavSleepMonitor DeviceActivityMonitor
// extension. Kept free of SwiftUI/ManagedSettings-UI so both targets compile.

let sleepActivityName = DeviceActivityName("sulav.sleep.schedule")

/// Legacy usage-threshold event for the max-hours cap. No longer registered —
/// see `sleepCapActivityName` for the wall-clock replacement — but the monitor
/// still answers it, because installs that registered it before the fix keep it
/// until something naturally reschedules `sleepActivityName`.
let sleepEventName = DeviceActivityEvent.Name("sulav.sleep.maxDuration")

/// The "Unlock anyway after Nh" safety valve: a one-shot activity whose
/// *start*, N hours after the user taps Sleep Now, clears the shield.
///
/// Wall clock, not a usage threshold. The cap exists for the morning where the
/// app is never reopened to call `wakeUp()`, and it has to hold for a session
/// started outside the bedtime→wake window (an afternoon nap), where no
/// `intervalDidEnd` is coming for hours. A `DeviceActivityEvent` cannot express
/// that: it meters *screen time in the blocked apps*, and shielded apps accrue
/// none, so the old threshold-based cap could sit at zero all night and never
/// fire.
///
/// Registered by the app from `startLockdown`, which runs with the app in the
/// foreground — the one moment we can rely on scheduling actually sticking.
let sleepCapActivityName = DeviceActivityName("sulav.sleep.cap")

/// A second, short-lived activity used purely to re-arm the shield after a
/// "5 more minutes" snooze. Separate from `sleepActivityName` so its interval
/// callbacks can't be mistaken for bedtime/wake — its start re-applies the
/// shield without resetting the night's snooze allowance, and its end is a
/// no-op rather than "wake up, clear everything".
let sleepSnoozeActivityName = DeviceActivityName("sulav.sleep.snooze")

/// Usage-threshold events that re-arm the shield after a snooze, registered on
/// `sleepActivityName` up front by `scheduleLockdown`.
///
/// This is the *primary* re-arm, and the only link in the chain that fires
/// while the user is still inside the blocked app. It works because shielded
/// apps accrue no screen time: within a lockdown window the only way to spend
/// minutes in a blocked app is during a snooze, so cumulative usage of
/// `snoozeMinutes`, `2 × snoozeMinutes`, … lands exactly at the end of the
/// first, second, … snooze. Pre-registering them from the app also avoids
/// asking a shield-action extension — which is torn down the moment it answers
/// the button tap — to register anything at all.
///
/// One event per snooze the window allows, thresholds cumulative because
/// DeviceActivity meters usage from the interval start, not from the last
/// event.
let sleepSnoozeEventNames: [DeviceActivityEvent.Name] = (1...SleepLockdownSelection.snoozeLimit)
    .map { DeviceActivityEvent.Name("sulav.sleep.snoozeUsed.\($0)") }

/// Cumulative usage threshold for the nth snooze (1-based).
func sleepSnoozeThreshold(forSnooze n: Int) -> DateComponents {
    DateComponents(minute: SleepLockdownSelection.snoozeMinutes * n)
}

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
