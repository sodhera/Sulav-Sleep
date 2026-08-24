import Foundation

// The copy engine behind the morning card (`SleepWakeSummaryView`), kept in
// one dependency-free file (Foundation only, no SwiftUI, no `SleepSession`)
// so it compiles and runs on its own — see
// `ios/SulavSleepTests/SleepWakeCelebrationTests.swift` and
// `scripts/test-wake-celebration.sh`. `SleepStore.wakeUp()` is the only
// adapter: it turns the night it just logged into a `WakeNight` and hands it
// here.
//
// Why a rule and not a random cheer: the app's one non-negotiable is that it
// never claims something that isn't true (DESIGN.md, "What to avoid"). A
// canned "Great job!" after three hours of sleep is a lie the user can see
// through, and a surface that lies once is one they stop reading. So every
// line below states a *fact about this night* — a first night, a streak that
// hit a round number, a night nobody reached for their phone, a window slept
// end to end — and warmth comes from the tone, never from inflation.

/// Everything the morning card knows about the night that just ended.
///
/// A plain value with no app types in it, so the rule stays testable without
/// a simulator. `SleepStore` fills it in at wake.
struct WakeNight: Equatable {
    /// The night just logged.
    var durationMinutes: Int
    /// The user's own bedtime→wake window, i.e. the night they planned.
    var targetMinutes: Int
    /// The streak *including* this night — the card is shown after the night
    /// is logged, so this is the number the user will see on Home.
    var streak: Int
    /// Whether this is the first night this account has ever recorded.
    var isFirstNight: Bool
    /// Reaches for a blocked app during the session, or `nil` when apps
    /// weren't blocked last night at all. `nil` and `0` mean very different
    /// things here: only a night that was actually guarded can be called a
    /// clean one, so an unguarded night must never win the "you didn't reach
    /// once" line it did nothing to earn.
    var reaches: Int?
    /// Which wording to use where a tier offers more than one. Derived from
    /// the date (`SleepStore` passes the day of the year), so the line is
    /// stable for the whole morning — it must not reshuffle when the view
    /// redraws — while still varying night to night.
    var variant: Int

    init(
        durationMinutes: Int,
        targetMinutes: Int,
        streak: Int,
        isFirstNight: Bool,
        reaches: Int?,
        variant: Int = 0
    ) {
        self.durationMinutes = durationMinutes
        self.targetMinutes = targetMinutes
        self.streak = streak
        self.isFirstNight = isFirstNight
        self.reaches = reaches
        self.variant = variant
    }
}

/// The one line of warm copy under the morning card's duration.
enum WakeCelebration {
    /// At or over this, the night is worth calling long on its own — even
    /// when the user's own window is longer still. Someone whose schedule
    /// says nine hours and who slept seven and a half had a good night.
    static let longNightMinutes = 7 * 60

    /// Under this, the card stops congratulating and starts being kind. The
    /// line still logs the night without a word of blame — the reach mirror's
    /// rule (DESIGN.md, "The morning mirror") applies to every morning
    /// surface: mirror, never judge.
    static let shortNightMinutes = 5 * 60

    /// Streak lengths that get their own sentence. Round human numbers, not a
    /// formula — a week, a fortnight, a month — plus every hundred after.
    static let milestones: Set<Int> = [7, 14, 30, 50, 100, 200, 365]

    static func isMilestone(_ streak: Int) -> Bool {
        streak > 0 && (milestones.contains(streak) || streak % 100 == 0)
    }

    /// The line for this night. First matching tier wins, most specific
    /// first: a thing that happened *once* (a first night, a milestone) beats
    /// a thing that happens often (a good duration).
    static func line(for night: WakeNight) -> String {
        // Once ever. Nothing else about a first night is as worth saying as
        // the fact that it's the first.
        if night.isFirstNight {
            return "Your first night is on the record."
        }

        // A round number the user has been watching climb.
        if isMilestone(night.streak) {
            return milestoneLine(night.streak)
        }

        // A guarded night nobody tested. Only reachable when the shield was
        // actually up (see `WakeNight.reaches`).
        if night.reaches == 0 {
            return pick([
                "A whole night without reaching for your phone.",
                "Not one reach for a blocked app last night.",
                "The block held all night — you never tested it.",
            ], night.variant)
        }

        // The night they planned, slept.
        if night.durationMinutes >= night.targetMinutes {
            return pick([
                "You slept the whole window you set for yourself.",
                "Bedtime to wake, the full night you planned.",
            ], night.variant)
        }

        // Long by any measure, even if their own window is longer.
        if night.durationMinutes >= longNightMinutes {
            return pick([
                "A long, full night.",
                "That's a proper night's sleep.",
            ], night.variant)
        }

        // No headline fact, but a run worth naming.
        if night.streak >= 2 {
            return pick([
                "\(night.streak) nights in a row.",
                "That's \(night.streak) in a row now.",
            ], night.variant)
        }

        // Short. Warm, honest, and pointedly forward-looking: the next night
        // is the only one they can still do anything about.
        if night.durationMinutes < shortNightMinutes {
            return pick([
                "A short one — on the record all the same. Tonight's the next.",
                "Not a long night, but it counts. Tonight's the next one.",
            ], night.variant)
        }

        return pick([
            "Another night on the record.",
            "That's another one logged.",
        ], night.variant)
    }

    /// Milestones get spelled-out words up to a month — "Seven nights" reads
    /// like an occasion where "7 nights" reads like a data point — and digits
    /// past it, where the number itself is the point.
    private static func milestoneLine(_ streak: Int) -> String {
        switch streak {
        case 7: return "Seven nights in a row. That's a full week."
        case 14: return "Two straight weeks of nights."
        case 30: return "Thirty nights in a row. A month of showing up."
        case 50: return "Fifty nights. Half of a hundred."
        case 100: return "One hundred nights in a row. Sit with that one."
        case 365: return "A year of nights, unbroken."
        default: return "\(streak) nights in a row."
        }
    }

    /// Rotates through a tier's wordings without ever indexing out of range —
    /// `variant` arrives from a calendar and is allowed to be anything.
    private static func pick(_ options: [String], _ variant: Int) -> String {
        guard !options.isEmpty else { return "" }
        let index = ((variant % options.count) + options.count) % options.count
        return options[index]
    }
}
