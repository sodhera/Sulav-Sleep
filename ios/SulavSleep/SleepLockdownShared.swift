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

