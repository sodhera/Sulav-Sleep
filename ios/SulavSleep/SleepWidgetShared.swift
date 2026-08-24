import Foundation

// Data shared between the app and the widget extension via an App Group.
// This file is a member of BOTH targets. Keep it dependency-free (Foundation
// only) so it compiles in the extension.

struct WidgetNight: Codable, Identifiable {
    var end: Date
    var durationMinutes: Int

    var id: Date { end }
}

/// Which day a night belongs to: **the day you woke up**.
///
/// Lives here because this file is a member of both targets, and the rule has
/// to be identical on both — the widget chart and the app chart are the same
/// chart in two sizes, and they'd drift the moment each computed its own.
/// `SleepMerge.key` in the app delegates to this. See DESIGN.md.
enum SleepDay {
    static func key(for end: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: end)
    }
}

struct SleepWidgetSummary: Codable {
    var nights: [WidgetNight]          // most recent last, up to 7
    var latestDurationMinutes: Int?
    var streak: Int
    var targetMinutes: Int
    // Tonight's schedule + live state, so widgets can show a bedtime countdown
    // and flip into the asleep look. All optional: absent for signed-out /
    // pre-onboarding users and for summaries written before these existed
    // (synthesized Codable uses decodeIfPresent for optionals, so the v1 key
    // still decodes).
    var bedtimeMinutes: Int?
    var wakeMinutes: Int?
    var asleepSince: Date?
    /// Whether an account is signed in — the widget swaps its Sleep Now
    /// capsule for a "Sign in" one when this is false. Optional for
    /// decode-compat with older summaries; readers treat absent as signed in
    /// (the app rewrites the summary on its first run after updating).
    var isSignedIn: Bool?
    /// Whether the streak is one missed night from resetting, so the widget
    /// can draw the same hollow flame Home does. Optional for decode-compat
    /// with older summaries; absent reads as a healthy streak, which is what
    /// the previous rule could only ever produce.
    var streakIsDying: Bool?
    var updated: Date

    var isEmpty: Bool { nights.isEmpty }

    /// Mean duration across the nights this summary carries.
    ///
    /// The stats widgets lead with this rather than last night's figure.
    /// `latestDurationMinutes` is nil whenever the most recent night isn't
    /// today's or yesterday's, so a hero built on it blanked out on exactly
    /// the mornings someone forgot to log — the tile went empty while the
    /// chart beside it still showed a week of bars. An average is present
    /// whenever any history is.
    ///
    /// Deliberately the last N *logged nights*, not the last N calendar days:
    /// `nights` is `displaySessions.suffix(7)`, the same window and the same
    /// rule as `SleepStats.averages` behind Profile's summary band, so the
    /// widget and the app can never quote two different averages. Callers
    /// name the sample size (`nights.count`) rather than claiming seven.
    var averageMinutes: Int? {
        guard !nights.isEmpty else { return nil }
        return nights.reduce(0) { $0 + $1.durationMinutes } / nights.count
    }

    /// Empty state used before any real night exists (honest — no fake data).
    /// `isSignedIn: false` because this only renders when the app has never
    /// written a summary — i.e. nobody has signed in on this install.
    static let empty = SleepWidgetSummary(
        nights: [], latestDurationMinutes: nil,
        streak: 0, targetMinutes: 480,
        bedtimeMinutes: nil, wakeMinutes: nil, asleepSince: nil,
        isSignedIn: false, streakIsDying: false,
        updated: Date(timeIntervalSince1970: 0)
    )
}

/// Read/write the widget summary in the shared App Group container.
enum SleepWidgetStore {
    static let appGroup = "group.com.sulav.sleepblock"
    static let key = "sulav.widget.summary.v1"

    private static var encoder: JSONEncoder {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }
    private static var decoder: JSONDecoder {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }

    static func save(_ summary: SleepWidgetSummary) {
        guard let defaults = UserDefaults(suiteName: appGroup),
              let data = try? encoder.encode(summary) else { return }
        defaults.set(data, forKey: key)
    }

    static func load() -> SleepWidgetSummary? {
        guard let defaults = UserDefaults(suiteName: appGroup),
              let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(SleepWidgetSummary.self, from: data)
    }
}
