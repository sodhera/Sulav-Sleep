import Foundation

enum AppTab: String, CaseIterable, Identifiable, Codable {
    case home
    case reports

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .reports: "Reports"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .reports: "chart.bar.xaxis"
        }
    }
}

struct Profile: Codable, Equatable {
    var name: String
    var bedtime: Int
    var wakeTime: Int
    var onboarded: Bool
}

struct SleepSession: Identifiable, Codable, Equatable {
    var id: String
    var start: Date
    var end: Date
    var durationMinutes: Int
    var score: Int
}

struct ActiveSleepSession: Codable, Equatable {
    var start: Date
}

enum PresentedSheet: String, Identifiable {
    case schedule
    case settings

    var id: String { rawValue }
}

