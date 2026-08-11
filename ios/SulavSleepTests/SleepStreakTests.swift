import Foundation

// Tests for `SleepStreakRule`. Plain assertions rather than XCTest so they run
// without an Xcode test target — `scripts/test-streak.sh` compiles this file
// together with `ios/SulavSleep/SleepStreak.swift` and runs it. That works
// only because SleepStreak.swift is deliberately dependency-free; keep it that
// way and these keep running.

@main
enum SleepStreakTests {

    // MARK: - Harness

    static var failures = 0
    static var checks = 0

    static func expect(_ actual: SleepStreak, _ expected: SleepStreak, _ what: String) {
        checks += 1
        if actual == expected {
            print("  ok   \(what)")
        } else {
            failures += 1
            print("  FAIL \(what)\n         expected \(expected)\n         got      \(actual)")
        }
    }

    // MARK: - Fixture

    /// Fixed UTC calendar and a fixed "today" so the suite can't drift with the
    /// machine's clock or zone.
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    static let wake = 7 * 60   // 07:00
    static let today = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_750_000_000))

    /// `daysAgo: 0` is today. Sleep days are keyed by the morning you woke.
    static func day(_ daysAgo: Int) -> Date {
        calendar.date(byAdding: .day, value: -daysAgo, to: today)!
    }

    static func days(_ offsets: [Int]) -> Set<Date> {
        Set(offsets.map(day))
    }

    /// A clock reading on `today`, so tests can sit either side of the due moment.
    static func clock(hour: Int, minute: Int = 0) -> Date {
        calendar.date(byAdding: .minute, value: hour * 60 + minute, to: today)!
    }

    static func streak(_ offsets: [Int], at now: Date, wakeMinutes: Int? = wake) -> SleepStreak {
        SleepStreakRule.streak(days: days(offsets), now: now, wakeMinutes: wakeMinutes, calendar: calendar)
    }

    static func alive(_ n: Int) -> SleepStreak { SleepStreak(count: n, state: .alive) }
    static func dying(_ n: Int) -> SleepStreak { SleepStreak(count: n, state: .dying) }

    // MARK: - Suite

    static func main() {
        counting()
        theEveningProblem()
        dyingAndReset()
        interiorGaps()
        mostRecentDayIsForgivable()
        qualifyingNights()
        backfill()

        print("\n\(checks - failures)/\(checks) passed")
        if failures > 0 {
            print("\(failures) FAILED")
            exit(1)
        }
    }

    static func counting() {
        print("counting")
        expect(streak([], at: clock(hour: 12)), .none,
               "no history at all is no streak")
        expect(streak([0], at: clock(hour: 12)), alive(1),
               "one night logged this morning is a streak of 1")
        expect(streak(Array(0...4), at: clock(hour: 12)), alive(5),
               "five nights in a row count 5")
        expect(streak(Array(0...39), at: clock(hour: 12)), alive(40),
               "long runs count every night")
    }

    /// Tonight's sleep hasn't happened yet, so having no record for today
    /// before wake-time-plus-grace must read as normal, not as a miss.
    /// Otherwise every user sees a dying streak every evening.
    static func theEveningProblem() {
        print("\nthe evening problem")
        // `day(0)` is *this* morning's wake — i.e. last night. Logging it and
        // then sitting at 22:00 is the ordinary evening: tonight hasn't been
        // slept yet and must not read as a miss.
        expect(streak(Array(0...9), at: clock(hour: 22)), alive(10),
               "at 22:00 having logged last night, tonight is not judged yet")
        expect(streak(Array(1...10), at: clock(hour: 3)), alive(10),
               "at 03:00, still inside the night, today is not yet due")
        expect(streak(Array(1...10), at: clock(hour: 7, minute: 30)), alive(10),
               "at 07:30, inside the grace window, today is not yet due")
        expect(streak(Array(1...10), at: clock(hour: 9, minute: 1)), dying(10),
               "at 09:01, past wake + 2h grace, an unlogged today is a miss")
        expect(streak(Array(1...10), at: clock(hour: 12), wakeMinutes: nil), alive(10),
               "with no wake time on file today is never judged")
    }

    static func dyingAndReset() {
        print("\ndying and reset")
        expect(streak(Array(1...20), at: clock(hour: 12)), dying(20),
               "one missed night: streak survives, dying, count unchanged")
        expect(streak(Array(2...20), at: clock(hour: 12)), .none,
               "two missed nights in a row: reset to zero")
        expect(streak(Array(2...20), at: clock(hour: 3)), dying(19),
               "the same gaps mid-night: only one is due yet, so still dying")
        expect(streak([0] + Array(2...20), at: clock(hour: 12)), alive(20),
               "logging tonight revives a dying streak")
    }

    /// The head rule and the interior rule are the same rule: two in a row ends it.
    static func interiorGaps() {
        print("\ninterior gaps")
        expect(streak([0, 1, 2, 4, 5, 6], at: clock(hour: 12)), alive(6),
               "a single gap mid-run survives and does not increment")
        expect(streak([0, 1, 2, 5, 6, 7], at: clock(hour: 12)), alive(3),
               "two gaps mid-run end the run there")
        expect(streak([0, 2, 4, 6, 8], at: clock(hour: 12)), alive(5),
               "every-other-night still counts as a run under this rule")
    }

    /// Regression. The previous implementation guarded forgiveness with
    /// `streak > 0`, which is never true on the first day examined, so the
    /// most recent day could never be forgiven — a short night today zeroed a
    /// 40-night flame while logging nothing at all preserved it. The head must
    /// be treated like any other day.
    static func mostRecentDayIsForgivable() {
        print("\nregression: most recent day is forgivable")
        let longRun = Array(1...40)
        expect(streak(longRun, at: clock(hour: 12)), dying(40),
               "a 40-night run with today unlogged is dying, not zero")
        expect(streak(longRun, at: clock(hour: 6)), alive(40),
               "and before wake time it is not even dying")
    }

    /// The 30-minute floor is a junk filter, not a quality bar: a short-but-real
    /// night keeps the flame, an accidental session does not.
    static func qualifyingNights() {
        print("\nwhat counts as a night")
        let qualifies = SleepStreakRule.qualifies(durationMinutes:)
        for (minutes, want) in [(0, false), (29, false), (30, true), (240, true), (480, true)] {
            checks += 1
            if qualifies(minutes) == want {
                print("  ok   \(minutes)m qualifies == \(want)")
            } else {
                failures += 1
                print("  FAIL \(minutes)m qualifies should be \(want)")
            }
        }
    }

    /// Stateless recomputation is what makes a late Health sync recoverable.
    static func backfill() {
        print("\nbackfill")
        expect(streak(Array(2...20), at: clock(hour: 12)), .none,
               "two missing days reads as reset...")
        expect(streak(Array(1...20), at: clock(hour: 12)), dying(20),
               "...and filling one of them by sync brings the run straight back")
    }
}
