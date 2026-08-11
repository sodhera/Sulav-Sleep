import Foundation

// The streak rule, kept in one dependency-free file (Foundation only, no
// `SleepSession`, no SwiftUI) so it can be compiled and tested on its own —
// see `ios/SulavSleepTests/SleepStreakTests.swift` and
// `scripts/test-streak.sh`. `SleepStore.streak` is the only adapter: it turns
// the merged history into a set of sleep days and hands it here.

/// Whether the flame is burning or about to go out.
enum SleepStreakState: Equatable {
    /// The most recent night that was due got logged.
    case alive
    /// Exactly one due night was missed. The run survives, but tonight has to
    /// land or it resets — this is the state the UI renders as a dimmed,
    /// hollow flame.
    case dying
}

struct SleepStreak: Equatable {
    /// Nights that counted. A missed night never increments this, even when
    /// the run survives it, so the number only ever means nights slept.
    var count: Int
    var state: SleepStreakState

    /// No live run. `.alive` because the state is only meaningful alongside a
    /// non-zero count, and "dying with nothing to lose" would be a lie.
    static let none = SleepStreak(count: 0, state: .alive)

    var isDying: Bool { state == .dying }
    /// Whether there is a flame to draw at all.
    var isVisible: Bool { count > 0 }
}

/// A streak behaves like a streak: miss one night and it's dying, miss the
/// next and it's gone.
///
/// **What counts as a night.** Any logged sleep of at least
/// `minimumNightMinutes`. Deliberately *not* the ≥85%-of-target bar the old
/// streak used: at an eight-hour target that bar is 6h48m, so someone
/// averaging six hours — exactly the person this app is for — could never hold
/// a streak at all and would see nothing but a zero. Duration already has
/// three honest homes (the hero, the chart, the target chip); the flame's job
/// is showing up, not grading. The 30-minute floor is only there to keep an
/// accidental five-minute session or an aborted nap from passing as a night.
///
/// **When a night is missed.** Sleep days are keyed by the morning you woke
/// (`SleepMerge.key`), so having no record for today is the *normal* state
/// every evening — you haven't slept yet. Judging it then would show everyone
/// a dying streak nightly. Instead a day only becomes due once the clock
/// passes its wake time plus `dueGraceMinutes`, which is late enough that a
/// lie-in or a slow Health sync isn't mistaken for a miss.
///
/// **Nothing is stored.** The result is recomputed from history on every read.
/// That matters more under a hard reset than it did under the old forgiving
/// rule: a Health night that syncs a day late fills its own gap and the run
/// comes back by itself, where a persisted counter would have been zeroed for
/// good.
enum SleepStreakRule {
    /// Shortest logged sleep that counts as a night.
    static let minimumNightMinutes = 30

    /// How long after wake time a missing night stops being "not yet" and
    /// starts being "missed". Two hours absorbs a lie-in and a late Health
    /// sync; much more and the warning arrives too late to act on.
    static let dueGraceMinutes = 120

    /// Hard stop on the day walk. Long enough that no real run reaches it,
    /// short enough that a corrupt date can't spin the loop.
    static let scanLimit = 400

    static func qualifies(durationMinutes: Int) -> Bool {
        durationMinutes >= minimumNightMinutes
    }

    /// The most recent sleep day we're willing to call missed.
    ///
    /// Today, once its wake time plus grace has passed; otherwise yesterday.
    /// With no wake time on file (signed out, pre-onboarding) today is never
    /// judged — the same benefit of the doubt the old rule gave.
    static func lastDueDay(now: Date, wakeMinutes: Int?, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        guard let wakeMinutes,
              let due = calendar.date(byAdding: .minute, value: wakeMinutes + dueGraceMinutes, to: today)
        else { return yesterday }
        return now >= due ? today : yesterday
    }

    /// Walk back a day at a time from the newest day worth judging, counting
    /// nights until two misses land in a row.
    ///
    /// - Parameter days: sleep days holding a qualifying night, as
    ///   `startOfDay` keys. A set, because at most one night can belong to a
    ///   day by the time `SleepMerge` is done with it.
    static func streak(
        days: Set<Date>,
        now: Date,
        wakeMinutes: Int?,
        calendar: Calendar = .current
    ) -> SleepStreak {
        guard let newest = days.max() else { return .none }

        // A night logged past the due day — woke at 2am, or Health backfilled
        // ahead of the grace — still counts the moment it lands, so the head
        // of the walk is whichever is later.
        let due = lastDueDay(now: now, wakeMinutes: wakeMinutes, calendar: calendar)
        var day = max(due, newest)

        var count = 0
        var consecutiveMisses = 0
        var missedMostRecent = false
        var counting = false

        for _ in 0..<scanLimit {
            if days.contains(day) {
                count += 1
                consecutiveMisses = 0
                counting = true
            } else {
                consecutiveMisses += 1
                // A miss before the first counted night is a miss at the head
                // of the run — the one the user can still fix tonight. Two of
                // those and the loop breaks below with nothing counted, which
                // is the reset.
                if !counting { missedMostRecent = true }
                if consecutiveMisses >= 2 { break }
            }
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }

        guard count > 0 else { return .none }
        return SleepStreak(count: count, state: missedMostRecent ? .dying : .alive)
    }
}
