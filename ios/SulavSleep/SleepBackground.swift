import SwiftUI

/// Lighting bands retained for the time-aware Home sloth and greeting.
enum CityPhase: String {
    case day = "Day"
    case dusk = "Dusk"
    case night = "Night"

    static func current(_ date: Date = Date()) -> CityPhase {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<17: return .day
        case 17..<22: return .dusk
        default: return .night
        }
    }
}

/// Shared app backdrop: the same star field, grain, and ember horizon as setup.
/// Keep the default setup depth so everyday screens have its readable navy sky.
/// Active sleep mode deliberately owns a separate, true-black surface.
struct SleepBackground: View {
    var body: some View {
        OnboardingStage()
    }
}
