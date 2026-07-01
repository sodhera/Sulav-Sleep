import Foundation
import DeviceActivity
import FamilyControls

// Shared between the app and the SulavSleepMonitor DeviceActivityMonitor
// extension. Kept free of SwiftUI/ManagedSettings-UI so both targets compile.

let sleepActivityName = DeviceActivityName("sulav.sleep.schedule")
let sleepEventName = DeviceActivityEvent.Name("sulav.sleep.maxDuration")

enum SleepLockdownSelection {
    static let selectionKey = "sulav.lock.selection.v1"

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
}
