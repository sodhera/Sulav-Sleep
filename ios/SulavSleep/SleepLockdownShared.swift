import Foundation
import DeviceActivity
import FamilyControls

// Shared between the app and the SulavSleepMonitor DeviceActivityMonitor
// extension. Kept free of SwiftUI/ManagedSettings-UI so both targets compile.
//
// Only the parts that genuinely need DeviceActivity or FamilyControls live
// here. The App Group keys and the pure logic around them are in
// `SleepLockdownKeys.swift`, which imports Foundation alone so the two shield
// extensions can compile it too — see that file for why that matters.

let sleepActivityName = DeviceActivityName("sulav.sleep.schedule")

/// Legacy usage-threshold event for the max-hours cap. No longer registered —
/// see `sleepCapActivityName` for the wall-clock replacement — but the monitor
/// still answers it, because installs that registered it before the fix keep it
/// until something naturally reschedules `sleepActivityName`.
let sleepEventName = DeviceActivityEvent.Name("sulav.sleep.maxDuration")

/// **Retired.** Was the "Unlock anyway after Nh" valve: a one-shot activity
/// whose start, N hours after Sleep Now, dropped the shield whether or not the
/// user had woken.
///
/// Nothing arms it any more. A block that expires on a timer is not a block —
/// someone who tapped Sleep Now at 11pm and reached for the phone at 3am found
/// the apps open again, which is the exact moment the promise was supposed to
/// hold. The lockdown now ends when the *session* ends: hold-to-wake, or
/// cancel. The escape that remains is the slow door on the shield itself,
/// which costs a deliberate wait every time rather than arriving on its own.
///
/// The name survives for two jobs, both migration: `endLockdown` and the
/// monitor stop monitoring it, retiring caps armed by builds that predate this
/// change, and the monitor still answers one that fires first — under the
/// current rule, so it cannot cut a running session short.
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

// MARK: - Selection coding

// The one piece of the App Group contract that needs FamilyControls, so it
// can't live alongside the keys in `SleepLockdownKeys.swift`. Neither shield
// extension decodes the selection — the monitor and the app do the shielding.
extension SleepLockdownSelection {
    static func decode(_ data: Data?) -> FamilyActivitySelection {
        guard let data, let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else {
            return FamilyActivitySelection()
        }
        return selection
    }

    static func encode(_ selection: FamilyActivitySelection) -> Data? {
        try? JSONEncoder().encode(selection)
    }
}

