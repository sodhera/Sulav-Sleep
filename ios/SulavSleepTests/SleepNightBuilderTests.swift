import Foundation
import Testing
@testable import SulavSleep

struct SleepNightBuilderTests {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func iv(_ startMin: Double, _ endMin: Double) -> SleepInterval {
        SleepInterval(start: base.addingTimeInterval(startMin * 60), end: base.addingTimeInterval(endMin * 60))
    }

    @Test func contiguousSegmentsBecomeOneNight() {
        let nights = SleepNightBuilder.nights(
            from: [iv(0, 120), iv(120, 300)],
            targetMinutes: 480
        )
        #expect(nights.count == 1)
        #expect(nights.first?.durationMinutes == 300)
        #expect(nights.first?.source == .healthKit)
    }

    @Test func overlappingSegmentsAreNotDoubleCounted() {
        let minutes = SleepNightBuilder.unionMinutes(of: [iv(0, 180), iv(60, 240)])
        #expect(minutes == 240)
    }

    @Test func largeGapSplitsIntoTwoNights() {
        // First night 0-120 min, then a 5h gap, then 180 more minutes.
        let nights = SleepNightBuilder.nights(
            from: [iv(0, 120), iv(420, 600)],
            targetMinutes: 480
        )
        #expect(nights.count == 2)
    }

    @Test func shortNapsAreDropped() {
        let nights = SleepNightBuilder.nights(from: [iv(0, 30)], targetMinutes: 480)
        #expect(nights.isEmpty)
    }

    @Test func emptyInputProducesNoNights() {
        #expect(SleepNightBuilder.nights(from: [], targetMinutes: 480).isEmpty)
    }

    @Test func nightsAreSortedByEnd() {
        let nights = SleepNightBuilder.nights(
            from: [iv(1_440, 1_800), iv(0, 300)], // second night first in the array
            targetMinutes: 480
        )
        #expect(nights.count == 2)
        #expect((nights[0].end) < (nights[1].end))
    }
}
