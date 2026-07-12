import Foundation

enum AppTab: String, CaseIterable, Identifiable, Codable {
    case home
    case profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .profile: "Profile"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .profile: "person.crop.circle"
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
    /// Whether the chosen apps actually block during sleep. On by default —
    /// choosing apps is the commitment — and the Blocked apps screen's toggle
    /// is the explicit override for nights the user wants the phone open
    /// without discarding the selection. Deliberately a *new* key (the retired
    /// `lockdownEnabled` doubled as an authorization snapshot and went stale),
    /// so every existing profile decodes to "on".
    var blockDuringSleep: Bool
    /// Max hours the lockdown stays active even if "Wake up" isn't tapped.
    var lockdownMaxHours: Int
    /// What the user said gets between them and good sleep, captured during
    /// sign-up onboarding (raw values of `SleepStruggle`). Kept for future
    /// personalization; empty when the user skipped the question.
    var sleepStruggles: [String]
    /// The apps the user said eat their night, captured during sign-up
    /// onboarding (raw values of `TimeSinkApp`). Deliberately *names*, not a
    /// `FamilyActivitySelection` — the system picker needs Screen Time
    /// authorization, and a permission sheet mid-sign-up is friction (same
    /// rule as Apple Health). This answer personalizes the paywall and future
    /// copy; the real lockdown selection is still made in Blocked apps.
    /// Empty when the user skipped the question.
    var timeSinkApps: [String]
    /// Whether the user has dismissed the "connect Apple Health" prompt shown
    /// on Profile. Apple Health is no longer part of onboarding — it's offered
    /// later, in-app, and this stops that prompt from reappearing once waved
    /// off. Connecting via the Profile toggle still works regardless.
    var healthPromptDismissed: Bool

    init(
        name: String, bedtime: Int, wakeTime: Int, onboarded: Bool,
        healthSyncEnabled: Bool = false, blockDuringSleep: Bool = true, lockdownMaxHours: Int = 6,
        sleepStruggles: [String] = [], timeSinkApps: [String] = [], healthPromptDismissed: Bool = false
    ) {
        self.name = name
        self.bedtime = bedtime
        self.wakeTime = wakeTime
        self.onboarded = onboarded
        self.healthSyncEnabled = healthSyncEnabled
        self.blockDuringSleep = blockDuringSleep
        self.lockdownMaxHours = lockdownMaxHours
        self.sleepStruggles = sleepStruggles
        self.timeSinkApps = timeSinkApps
        self.healthPromptDismissed = healthPromptDismissed
    }

    // Decode-safe: records written before these fields existed default sensibly.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        bedtime = try c.decode(Int.self, forKey: .bedtime)
        wakeTime = try c.decode(Int.self, forKey: .wakeTime)
        onboarded = try c.decode(Bool.self, forKey: .onboarded)
        healthSyncEnabled = try c.decodeIfPresent(Bool.self, forKey: .healthSyncEnabled) ?? false
        blockDuringSleep = try c.decodeIfPresent(Bool.self, forKey: .blockDuringSleep) ?? true
        lockdownMaxHours = try c.decodeIfPresent(Int.self, forKey: .lockdownMaxHours) ?? 6
        sleepStruggles = try c.decodeIfPresent([String].self, forKey: .sleepStruggles) ?? []
        timeSinkApps = try c.decodeIfPresent([String].self, forKey: .timeSinkApps) ?? []
        healthPromptDismissed = try c.decodeIfPresent(Bool.self, forKey: .healthPromptDismissed) ?? false
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

/// The onboarding "which apps eat your night?" options — the usual suspects
/// someone is still inside at 1am. Names, not Screen Time tokens (see
/// `Profile.timeSinkApps`): this is a soft, no-permission question whose
/// answers personalize the paywall and later nudge the real Blocked apps
/// selection.
enum TimeSinkApp: String, CaseIterable, Identifiable {
    case instagram
    case tiktok
    case youtube
    case x
    case reddit
    case snapchat
    case games
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .instagram: "Instagram"
        case .tiktok: "TikTok"
        case .youtube: "YouTube"
        case .x: "X"
        case .reddit: "Reddit"
        case .snapchat: "Snapchat"
        case .games: "Games"
        case .other: "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .instagram: "camera"
        case .tiktok: "music.note"
        case .youtube: "play.rectangle"
        case .x: "at"
        case .reddit: "bubble.left.and.bubble.right"
        case .snapchat: "bolt"
        case .games: "gamecontroller"
        case .other: "ellipsis"
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
    var source: SleepSource

    init(id: String, start: Date, end: Date, durationMinutes: Int, source: SleepSource = .local) {
        self.id = id
        self.start = start
        self.end = end
        self.durationMinutes = durationMinutes
        self.source = source
    }

    // Decode-safe: records written before `source` existed default to `.local`.
    // Records written while the retired 0–100 sleep score existed carry a
    // `score` key; the decoder simply ignores it — duration is the app's only
    // metric.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        start = try c.decode(Date.self, forKey: .start)
        end = try c.decode(Date.self, forKey: .end)
        durationMinutes = try c.decode(Int.self, forKey: .durationMinutes)
        source = try c.decodeIfPresent(SleepSource.self, forKey: .source) ?? .local
    }
}

struct ActiveSleepSession: Codable, Equatable {
    var start: Date
}

/// Authorization state for the Apple Health connection, surfaced to the UI.
enum HealthSyncState: Equatable {
    case unavailable   // HealthKit not present on this device
    case notConnected  // available but user hasn't connected
    case connected     // authorization granted / requested
}
