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
        case .home: "house"
        case .reports: "chart.xyaxis.line"
        }
    }
}

struct Profile: Codable, Equatable {
    var name: String
    var bedtime: Int
    var wakeTime: Int
    var onboarded: Bool
    /// Whether the user has opted into two-way Apple Health sync.
    var healthSyncEnabled: Bool
    /// Whether the user has enabled Screen Time app-lockdown while asleep.
    var lockdownEnabled: Bool
    /// Max hours the lockdown stays active even if "Wake up" isn't tapped.
    var lockdownMaxHours: Int
    /// What the user said gets between them and good sleep, captured during
    /// sign-up onboarding (raw values of `SleepStruggle`). Kept for future
    /// personalization; empty when the user skipped the question.
    var sleepStruggles: [String]

    init(
        name: String, bedtime: Int, wakeTime: Int, onboarded: Bool,
        healthSyncEnabled: Bool = false, lockdownEnabled: Bool = false, lockdownMaxHours: Int = 6,
        sleepStruggles: [String] = []
    ) {
        self.name = name
        self.bedtime = bedtime
        self.wakeTime = wakeTime
        self.onboarded = onboarded
        self.healthSyncEnabled = healthSyncEnabled
        self.lockdownEnabled = lockdownEnabled
        self.lockdownMaxHours = lockdownMaxHours
        self.sleepStruggles = sleepStruggles
    }

    // Decode-safe: records written before these fields existed default sensibly.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        bedtime = try c.decode(Int.self, forKey: .bedtime)
        wakeTime = try c.decode(Int.self, forKey: .wakeTime)
        onboarded = try c.decode(Bool.self, forKey: .onboarded)
        healthSyncEnabled = try c.decodeIfPresent(Bool.self, forKey: .healthSyncEnabled) ?? false
        lockdownEnabled = try c.decodeIfPresent(Bool.self, forKey: .lockdownEnabled) ?? false
        lockdownMaxHours = try c.decodeIfPresent(Int.self, forKey: .lockdownMaxHours) ?? 6
        sleepStruggles = try c.decodeIfPresent([String].self, forKey: .sleepStruggles) ?? []
    }
}

/// The onboarding "what's getting in the way of your sleep?" options. The
/// question exists both to tailor future features and because answering a few
/// personal questions before the account step measurably improves sign-up
/// completion.
enum SleepStruggle: String, CaseIterable, Identifiable {
    case phoneInBed
    case fallingAsleep
    case wakingAtNight
    case inconsistentSchedule
    case wakingTired

    var id: String { rawValue }

    var title: String {
        switch self {
        case .phoneInBed: "Phone in bed"
        case .fallingAsleep: "Trouble falling asleep"
        case .wakingAtNight: "Waking up at night"
        case .inconsistentSchedule: "Inconsistent schedule"
        case .wakingTired: "Waking up tired"
        }
    }

    var systemImage: String {
        switch self {
        case .phoneInBed: "iphone.radiowaves.left.and.right"
        case .fallingAsleep: "moon.zzz"
        case .wakingAtNight: "eye"
        case .inconsistentSchedule: "calendar.badge.exclamationmark"
        case .wakingTired: "battery.25percent"
        }
    }
}

/// Where a logged night came from. Used to dedupe local vs. HealthKit records.
enum SleepSource: String, Codable {
    case local
    case healthKit
}

struct SleepSession: Identifiable, Codable, Equatable {
    var id: String
    var start: Date
    var end: Date
    var durationMinutes: Int
    var score: Int
    var source: SleepSource

    init(id: String, start: Date, end: Date, durationMinutes: Int, score: Int, source: SleepSource = .local) {
        self.id = id
        self.start = start
        self.end = end
        self.durationMinutes = durationMinutes
        self.score = score
        self.source = source
    }

    // Decode-safe: records written before `source` existed default to `.local`.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        start = try c.decode(Date.self, forKey: .start)
        end = try c.decode(Date.self, forKey: .end)
        durationMinutes = try c.decode(Int.self, forKey: .durationMinutes)
        score = try c.decode(Int.self, forKey: .score)
        source = try c.decodeIfPresent(SleepSource.self, forKey: .source) ?? .local
    }
}

struct ActiveSleepSession: Codable, Equatable {
    var start: Date
}

enum PresentedSheet: String, Identifiable {
    case schedule
    case settings
    case lockdown

    var id: String { rawValue }
}

/// Authorization state for the Apple Health connection, surfaced to the UI.
enum HealthSyncState: Equatable {
    case unavailable   // HealthKit not present on this device
    case notConnected  // available but user hasn't connected
    case connected     // authorization granted / requested
}
