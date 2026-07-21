import Foundation
import DeviceActivity
import FamilyControls

// Shared between the app and the SulavSleepMonitor DeviceActivityMonitor
// extension. Kept free of SwiftUI/ManagedSettings-UI so both targets compile.

let sleepActivityName = DeviceActivityName("sulav.sleep.schedule")
let sleepEventName = DeviceActivityEvent.Name("sulav.sleep.maxDuration")

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
}
