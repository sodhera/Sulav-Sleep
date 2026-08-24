import Foundation

// Tests for `WakeCelebration`. Plain assertions rather than XCTest so they run
// without an Xcode test target — `scripts/test-wake-celebration.sh` compiles
// this file together with `ios/SulavSleep/SleepWakeCelebration.swift` and runs
// it. That works only because SleepWakeCelebration.swift is deliberately
// dependency-free; keep it that way and these keep running.
//
// What's actually being guarded here is *honesty*, not wording: a line must
// never claim a clean night on a night that wasn't guarded, never congratulate
// a three-hour night, and never reshuffle between two reads of the same
// morning. The exact sentences are free to change; these assertions are
// written against the claim each one makes.

@main
enum SleepWakeCelebrationTests {

    // MARK: - Harness

    static var failures = 0
    static var checks = 0

    static func expect(_ actual: String, _ expected: String, _ what: String) {
        checks += 1
        if actual == expected {
            print("  ok   \(what)")
        } else {
            failures += 1
            print("  FAIL \(what)\n         expected \(expected)\n         got      \(actual)")
        }
    }

    static func expect(_ condition: Bool, _ what: String) {
        checks += 1
        if condition {
            print("  ok   \(what)")
        } else {
            failures += 1
            print("  FAIL \(what)")
        }
    }

    // MARK: - Fixture

    static let target = 8 * 60

    /// An ordinary six-hour night with nothing special about it, which each
    /// test then bends in exactly one direction.
    static func night(
        minutes: Int = 6 * 60,
        target: Int = target,
        streak: Int = 3,
        first: Bool = false,
        reaches: Int? = nil,
        variant: Int = 0
    ) -> WakeNight {
        WakeNight(
            durationMinutes: minutes,
            targetMinutes: target,
            streak: streak,
            isFirstNight: first,
            reaches: reaches,
            variant: variant
        )
    }

    static func line(_ night: WakeNight) -> String { WakeCelebration.line(for: night) }

    // MARK: - Tests

    /// The first night outranks everything, including a clean night and a
    /// full window — it can only be said once.
    static func firstNightWinsOutright() {
        expect(
            line(night(minutes: 9 * 60, streak: 1, first: true, reaches: 0)),
            "Your first night is on the record.",
            "first night outranks every other tier"
        )
    }

    /// Round numbers get their own sentence, and they beat duration.
    static func milestonesBeatDuration() {
        expect(line(night(minutes: 9 * 60, streak: 7)).hasPrefix("Seven nights"), "7 is a milestone")
        expect(line(night(streak: 30)).hasPrefix("Thirty nights"), "30 is a milestone")
        expect(line(night(streak: 300)) == "300 nights in a row.", "every hundred is a milestone")
        expect(WakeCelebration.isMilestone(0) == false, "zero is not a milestone")
        expect(WakeCelebration.isMilestone(6) == false, "6 is not a milestone")
    }

    /// The honesty guard: `nil` reaches means the shield was never up, and an
    /// unguarded night must not be handed the clean-night line.
    static func onlyAGuardedNightCanBeClean() {
        let clean = line(night(reaches: 0))
        expect(clean.contains("reach") || clean.contains("block"), "0 reaches on a guarded night is celebrated")

        let unguarded = line(night(reaches: nil))
        expect(
            !unguarded.contains("reach") && !unguarded.contains("block"),
            "a night with no shield never claims a clean night"
        )

        let reached = line(night(reaches: 4))
        expect(
            !reached.contains("without reaching"),
            "a night they did reach never claims a clean night"
        )
    }

    /// Sleeping the whole planned window is worth saying; the reach line
    /// still outranks it, since not reaching is the harder thing.
    static func fullWindowIsNamed() {
        let full = line(night(minutes: 8 * 60))
        expect(full.contains("window") || full.contains("planned"), "target met is named")
        expect(
            line(night(minutes: 8 * 60, reaches: 0)) != full,
            "a clean night outranks a full window"
        )
    }

    /// A long night counts as long even when the user's own window is longer
    /// — the person whose schedule says nine hours and who slept seven and a
    /// half had a good night, and the card should say so.
    static func longNightCountsUnderAGenerousTarget() {
        let long = line(night(minutes: 7 * 60 + 30, target: 9 * 60))
        expect(long.contains("long") || long.contains("proper"), "7h30m under a 9h window is still long")
    }

    /// No shaming, ever: a short night is logged warmly and points forward.
    static func shortNightsAreNeverScolded() {
        let short = line(night(minutes: 3 * 60, streak: 1))
        expect(short.contains("Tonight"), "a short night points at tonight")
        expect(
            !short.lowercased().contains("only") && !short.contains("!"),
            "a short night carries no scolding and no exclamation mark"
        )
    }

    /// A run gets named when nothing bigger happened, and never at 1 (which
    /// is not a run — it's tonight).
    static func streaksAreNamedFromTwo() {
        expect(line(night(minutes: 6 * 60, streak: 4)).contains("4"), "a run of 4 is named")
        let single = line(night(minutes: 6 * 60, streak: 1))
        expect(single == "Another night on the record." || single == "That's another one logged.",
               "a streak of 1 falls through to the plain line")
    }

    /// Same night, same line — the card must not reword itself when the view
    /// redraws, and the variant is what keeps that true.
    static func aVariantIsStableAndInRange() {
        let a = line(night(variant: 12))
        let b = line(night(variant: 12))
        expect(a, b, "the same variant yields the same line")
        // Anything a calendar can hand over, including nonsense, must land
        // on a real line rather than trapping.
        for variant in [-9, -1, 0, 1, 366, Int.max] {
            expect(!line(night(variant: variant)).isEmpty, "variant \(variant) yields a line")
        }
    }

    static func aLineIsAlwaysProduced() {
        for minutes in [1, 29, 30, 200, 480, 900] {
            for streak in [0, 1, 2, 7, 99] {
                for reaches in [nil, 0, 3] as [Int?] {
                    let text = line(night(minutes: minutes, streak: streak, reaches: reaches))
                    expect(!text.isEmpty, "line for \(minutes)m / streak \(streak) / reaches \(String(describing: reaches))")
                }
            }
        }
    }

    // MARK: - Entry

    static func main() {
        print("WakeCelebration")
        firstNightWinsOutright()
        milestonesBeatDuration()
        onlyAGuardedNightCanBeClean()
        fullWindowIsNamed()
        longNightCountsUnderAGenerousTarget()
        shortNightsAreNeverScolded()
        streaksAreNamedFromTwo()
        aVariantIsStableAndInRange()
        aLineIsAlwaysProduced()

        print("\n\(checks - failures)/\(checks) passed")
        if failures > 0 { exit(1) }
    }
}
