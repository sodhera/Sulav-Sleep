import Foundation

// Data shared between the app and the widget extension via an App Group.
// This file is a member of BOTH targets. Keep it dependency-free (Foundation
// only) so it compiles in the extension.

struct WidgetNight: Codable, Identifiable {
    var end: Date
    var durationMinutes: Int

    var id: Date { end }
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
    var updated: Date

    var isEmpty: Bool { nights.isEmpty }

    /// Empty state used before any real night exists (honest — no fake data).
    static let empty = SleepWidgetSummary(
        nights: [], latestDurationMinutes: nil,
        streak: 0, targetMinutes: 480,
        bedtimeMinutes: nil, wakeMinutes: nil, asleepSince: nil,
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
