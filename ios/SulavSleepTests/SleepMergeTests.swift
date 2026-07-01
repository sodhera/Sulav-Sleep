import Foundation
import Testing
@testable import SulavSleep

struct SleepMergeTests {
    @Test func healthWinsForTheSameNight() {
        let local = TestFactory.session(endingDaysAgo: 1, durationMinutes: 400, score: 80, source: .local)
        // Same night, ends ~10 minutes later — should dedupe to the Health record.
        let health = SleepSession(
            id: "hk-x",
            start: local.start,
            end: local.end.addingTimeInterval(600),
            durationMinutes: 415,
            score: 84,
            source: .healthKit
        )
        let merged = SleepMerge.merge(local: [local], health: [health])
        #expect(merged.count == 1)
        #expect(merged.first?.source == .healthKit)
    }

    @Test func distinctNightsAreKept() {
        let n1 = TestFactory.session(endingDaysAgo: 1, durationMinutes: 400, score: 80, source: .local)
        let n2 = TestFactory.session(endingDaysAgo: 2, durationMinutes: 420, score: 85, source: .healthKit)
        let merged = SleepMerge.merge(local: [n1], health: [n2])
        #expect(merged.count == 2)
    }

    @Test func resultIsSortedByEndAscending() {
        let older = TestFactory.session(endingDaysAgo: 3, durationMinutes: 400, score: 80)
        let newer = TestFactory.session(endingDaysAgo: 1, durationMinutes: 420, score: 85)
        let merged = SleepMerge.merge(local: [newer, older], health: [])
        #expect(merged.first?.end == older.end)
        #expect(merged.last?.end == newer.end)
    }

    @Test func emptyInputsProduceEmptyResult() {
        #expect(SleepMerge.merge(local: [], health: []).isEmpty)
    }
}
