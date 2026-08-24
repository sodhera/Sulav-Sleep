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
    /// The target bedtime the app holds the user to — the Home countdown,
    /// lockdown window, and widgets all key off this. Captured during sign-up
    /// as the time they want to go to bed.
    var bedtime: Int
    /// The target wake time (see `bedtime`).
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
    // A `lockdownMaxHours` lived here — the "Unlock anyway after Nh" valve.
    // Removed with the valve itself: the lockdown is anchored to the sleep
    // session now, so there is no hour to configure. Old profiles carrying the
    // key still decode; the extra key is simply ignored.
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
    /// The outcomes selected during sign-up, encoded by `SleepGoal` into this
    /// legacy string field. A single old raw value and a comma-delimited set
    /// both decode, so the goal question can be multi-select without breaking
    /// the existing local/cloud schema. Feeds future personalization.
    var primaryGoal: String
    /// How long they said the phone keeps them up after they're already in
    /// bed (raw value of `LateNightPhoneTime`). The plan summary turns this
    /// into the "time to win back each week" number. Empty when unanswered.
    var lateNightPhone: String
    /// How they said they usually wake up (raw value of `WakeFeeling`).
    /// Captured for future personalization; the question itself is the
    /// emotional anchor of the sign-up flow. Empty when unanswered.
    var wakeFeeling: String
    /// The user's own reasons for wanting this, in their own words — what the
    /// shield shows someone reaching for a blocked app at 1am.
    ///
    /// Deliberately *not* collected during sign-up. Asked cold, this question
    /// produces a slogan ("I want better sleep"), and a slogan on the shield is
    /// indistinguishable from the app's own copy. The honest version arrives
    /// after a rough morning or right after a night they caved, which is when
    /// `shouldPromptForReason` asks. Empty until then; the shield falls back to
    /// its written copy. See `SleepLockdownSelection.reasonsKey`.
    var lockReasons: [String]
    /// Opt-in strictness: no snooze, and a longer wait on the slow door.
    ///
    /// Off by default and never turned on by the app. A restriction someone
    /// chose is respected; the same restriction imposed is resented, and
    /// resentment is what uninstalls the app.
    var hardMode: Bool

    init(
        name: String, bedtime: Int, wakeTime: Int, onboarded: Bool,
        healthSyncEnabled: Bool = false, blockDuringSleep: Bool = true,
        sleepStruggles: [String] = [], timeSinkApps: [String] = [], healthPromptDismissed: Bool = false,
        primaryGoal: String = "", lateNightPhone: String = "", wakeFeeling: String = "",
        lockReasons: [String] = [], hardMode: Bool = false
    ) {
        self.name = name
        self.bedtime = bedtime
        self.wakeTime = wakeTime
        self.onboarded = onboarded
        self.healthSyncEnabled = healthSyncEnabled
        self.blockDuringSleep = blockDuringSleep
        self.sleepStruggles = sleepStruggles
        self.timeSinkApps = timeSinkApps
        self.healthPromptDismissed = healthPromptDismissed
        self.primaryGoal = primaryGoal
        self.lateNightPhone = lateNightPhone
        self.wakeFeeling = wakeFeeling
        self.lockReasons = lockReasons
        self.hardMode = hardMode
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
        sleepStruggles = try c.decodeIfPresent([String].self, forKey: .sleepStruggles) ?? []
        timeSinkApps = try c.decodeIfPresent([String].self, forKey: .timeSinkApps) ?? []
        healthPromptDismissed = try c.decodeIfPresent(Bool.self, forKey: .healthPromptDismissed) ?? false
        primaryGoal = try c.decodeIfPresent(String.self, forKey: .primaryGoal) ?? ""
        lateNightPhone = try c.decodeIfPresent(String.self, forKey: .lateNightPhone) ?? ""
        wakeFeeling = try c.decodeIfPresent(String.self, forKey: .wakeFeeling) ?? ""
        lockReasons = try c.decodeIfPresent([String].self, forKey: .lockReasons) ?? []
        hardMode = try c.decodeIfPresent(Bool.self, forKey: .hardMode) ?? false
    }
}

/// One night's reach attempts, kept so the morning mirror can show a week
/// rather than only last night.
///
/// Recorded as raw timestamps rather than a count, because the *shape* is the
/// insight — "six times, all between 12:40 and 1:10" tells someone something
/// about themselves that "six times" does not.
struct ReachNight: Identifiable, Codable, Equatable {
    /// Start of the sleep day this belongs to, matching `SleepMerge.key`.
    var day: Date
    var attempts: [Date]

    var id: Date { day }
    var count: Int { attempts.count }
    var first: Date? { attempts.min() }
    var last: Date? { attempts.max() }
}

/// Everything the sign-up questionnaire collects, handed to
/// `SleepStore.completeOnboarding` in one piece so the flow's closure
/// doesn't grow a positional parameter per question. Enum-backed answers
/// travel as raw values (same rule as `Profile.sleepStruggles`).
struct OnboardingAnswers {
    var name: String
    var bedtime: Int
    var wakeTime: Int
    var struggles: [String] = []
    var timeSinks: [String] = []
    var goals: String = ""
    var lateNightPhone: String = ""
    var wakeFeeling: String = ""
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

/// The onboarding outcomes. The screen is multi-select; storage stays a single
/// string for compatibility with the existing Supabase `goal` text column.
enum SleepGoal: String, CaseIterable, Identifiable, Hashable {
    case fallAsleepEarlier
    case wakeUpRested
    case lessPhoneAtNight
    case consistentSchedule

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fallAsleepEarlier: "Fall asleep earlier"
        case .wakeUpRested: "Wake up with more energy"
        case .lessPhoneAtNight: "Break the late-night phone habit"
        case .consistentSchedule: "Keep a consistent schedule"
        }
    }

    var systemImage: String {
        switch self {
        case .fallAsleepEarlier: "moon.stars"
        case .wakeUpRested: "sunrise"
        case .lessPhoneAtNight: "iphone.slash"
        case .consistentSchedule: "calendar"
        }
    }

    /// Stable, backward-compatible representation for the existing string
    /// field. Earlier profiles contain one raw value; newer ones contain the
    /// authored selection order joined by commas.
    static func storageValue(for goals: Set<SleepGoal>) -> String {
        allCases.filter(goals.contains).map(\.rawValue).joined(separator: ",")
    }

    static func values(from storageValue: String) -> [SleepGoal] {
        storageValue.split(separator: ",").compactMap { SleepGoal(rawValue: String($0)) }
    }
}

/// The onboarding "how long does your phone keep you up?" options. The point
/// of the question is the *number*: `weeklyMinutes` is what the plan summary
/// shows as time to win back, which is the app's whole pitch made personal.
enum LateNightPhoneTime: String, CaseIterable, Identifiable {
    case quarterHour
    case halfHour
    case hour
    case twoPlus

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quarterHour: "15 minutes or less"
        case .halfHour: "About 30 minutes"
        case .hour: "About an hour"
        case .twoPlus: "2 hours or more"
        }
    }

    var systemImage: String {
        switch self {
        case .quarterHour: "hourglass.bottomhalf.filled"
        case .halfHour: "hourglass"
        case .hour: "hourglass.tophalf.filled"
        case .twoPlus: "infinity"
        }
    }

    /// A conservative nightly estimate, used only for the weekly math.
    var nightlyMinutes: Int {
        switch self {
        case .quarterHour: 15
        case .halfHour: 30
        case .hour: 60
        case .twoPlus: 120
        }
    }

    var weeklyMinutes: Int { nightlyMinutes * 7 }
}

/// The onboarding "how do you usually wake up?" options. Single-select.
/// Stored for personalization, but the question earns its step by making the
/// user *say* the mornings are rough right before the plan reveal.
enum WakeFeeling: String, CaseIterable, Identifiable {
    case groggy
    case tired
    case okay
    case rested

    var id: String { rawValue }

    var title: String {
        switch self {
        case .groggy: "Groggy"
        case .tired: "Still tired"
        case .okay: "Okay"
        case .rested: "Rested"
        }
    }

    var systemImage: String {
        switch self {
        case .groggy: "cloud.fog"
        case .tired: "battery.25percent"
        case .okay: "circle.lefthalf.filled"
        case .rested: "sun.max"
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

/// The morning card's whole payload, assembled by `SleepStore.wakeUp()` the
/// moment a night is logged and cleared when the card is dismissed.
///
/// Deliberately **never persisted**: this is a moment, not a record. Killing
/// the app with the card up and relaunching lands on Home, which is the right
/// answer — "Good morning" three hours later, or after a cold boot, would be
/// the app talking about a night the user has already moved on from. The
/// record itself lives in `sessions` and is on Home's last-night strip and
/// the Profile chart the second the card is gone.
struct WakeSummary: Equatable {
    /// The night just logged — its `start`/`end` are the card's window line.
    var session: SleepSession
    /// The streak *including* this night, i.e. the one Home is about to show.
    var streak: SleepStreak
}

/// Authorization state for the Apple Health connection, surfaced to the UI.
enum HealthSyncState: Equatable {
    case unavailable   // HealthKit not present on this device
    case notConnected  // available but user hasn't connected
    case connected     // authorization granted / requested
}
