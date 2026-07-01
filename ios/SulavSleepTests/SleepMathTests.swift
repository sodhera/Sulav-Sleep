import Testing
@testable import SulavSleep

struct SleepMathTests {
    @Test func windowSpanningMidnight() {
        // 10pm -> 6am should be 8 hours.
        #expect(SleepMath.windowMinutes(bedtime: 22 * 60, wakeTime: 6 * 60) == 480)
    }

    @Test func windowSameDay() {
        #expect(SleepMath.windowMinutes(bedtime: 60, wakeTime: 480) == 420)
    }

    @Test func windowEqualTimesIsFullDay() {
        #expect(SleepMath.windowMinutes(bedtime: 8 * 60, wakeTime: 8 * 60) == 1_440)
    }

    @Test func scoreAtTargetIsNinetyTwo() {
        #expect(SleepMath.score(durationMinutes: 480, targetMinutes: 480) == 92)
    }

    @Test func scoreOverTargetClampsToHundred() {
        #expect(SleepMath.score(durationMinutes: 700, targetMinutes: 480) == 100)
    }

    @Test func scoreWellUnderTargetClampsToFloor() {
        #expect(SleepMath.score(durationMinutes: 240, targetMinutes: 480) == 40)
    }

    @Test func scoreSlightlyUnderTarget() {
        // ratio 0.75 -> 100 - 0.25 * 140 = 65
        #expect(SleepMath.score(durationMinutes: 360, targetMinutes: 480) == 65)
    }
}
