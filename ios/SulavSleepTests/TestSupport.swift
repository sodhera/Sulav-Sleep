import Foundation
@testable import SulavSleep

/// Deterministic, in-memory HealthKit stand-in for store tests.
final class MockHealthService: SleepHealthProviding {
    var available: Bool
    var authorizeResult: Bool
    var accessDenied: Bool
    var nights: [SleepSession]

    private(set) var saved: [SleepSession] = []
    private(set) var authorizeCallCount = 0
    private(set) var fetchCallCount = 0

    init(available: Bool = true, authorizeResult: Bool = true, accessDenied: Bool = false, nights: [SleepSession] = []) {
        self.available = available
        self.authorizeResult = authorizeResult
        self.accessDenied = accessDenied
        self.nights = nights
    }

    var isAvailable: Bool { available }
    var isAccessDenied: Bool { accessDenied }

    func requestAuthorization() async -> Bool {
        authorizeCallCount += 1
        return authorizeResult
    }

    func fetchNights(days: Int, targetMinutes: Int) async -> [SleepSession] {
        fetchCallCount += 1
        return nights
    }

    func save(session: SleepSession) async {
        saved.append(session)
    }
}

enum TestFactory {
    /// A fresh store backed by an isolated UserDefaults suite so tests never
    /// touch real persisted state or each other.
    static func makeStore(
        health: SleepHealthProviding = MockHealthService(),
        auth: AuthProviding = MockAuthClient()
    ) -> SleepStore {
        let suite = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return SleepStore(persistence: SleepPersistence(defaults: defaults), health: health, auth: auth)
    }

    static func session(
        endingDaysAgo days: Int,
        durationMinutes: Int,
        score: Int,
        source: SleepSource = .local,
        now: Date = Date()
    ) -> SleepSession {
        let end = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
        let start = end.addingTimeInterval(TimeInterval(-durationMinutes * 60))
        return SleepSession(
            id: "\(source)-\(days)-\(Int(end.timeIntervalSince1970))",
            start: start,
            end: end,
            durationMinutes: durationMinutes,
            score: score,
            source: source
        )
    }
}
