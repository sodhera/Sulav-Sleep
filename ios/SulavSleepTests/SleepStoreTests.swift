import Foundation
import Testing
@testable import SulavSleep

@MainActor
struct SleepStoreTests {
    @Test func onboardingCreatesProfileWithNoSeededData() {
        let store = TestFactory.makeStore()
        store.completeOnboarding(name: "Ada", bedtime: 22 * 60, wakeTime: 6 * 60, connectHealth: false)

        #expect(store.isOnboarded)
        #expect(store.profile?.name == "Ada")
        // The whole point of "no dummy data": history is empty until a real night.
        #expect(store.sessions.isEmpty)
        #expect(store.displaySessions.isEmpty)
        #expect(store.latestSession == nil)
    }

    @Test func blankNameFallsBackToFriend() {
        let store = TestFactory.makeStore()
        store.completeOnboarding(name: "   ", bedtime: 22 * 60, wakeTime: 6 * 60, connectHealth: false)
        #expect(store.profile?.name == "Friend")
    }

    @Test func startSleepCreatesActiveSession() {
        let store = TestFactory.makeStore()
        store.completeOnboarding(name: "Ada", bedtime: 22 * 60, wakeTime: 6 * 60, connectHealth: false)
        store.startSleep()
        #expect(store.activeSession != nil)
    }

    @Test func wakeUpLogsALocalNightAndClearsActive() {
        let store = TestFactory.makeStore()
        store.completeOnboarding(name: "Ada", bedtime: 22 * 60, wakeTime: 6 * 60, connectHealth: false)
        store.activeSession = ActiveSleepSession(start: Date().addingTimeInterval(-8 * 3600))
        store.wakeUp()

        #expect(store.activeSession == nil)
        #expect(store.sessions.count == 1)
        #expect(store.sessions.first?.source == .local)
        #expect((store.sessions.first?.durationMinutes ?? 0) >= 470) // ~8h
    }

    @Test func streakCountsConsecutiveHighScores() {
        let store = TestFactory.makeStore()
        store.completeOnboarding(name: "Ada", bedtime: 22 * 60, wakeTime: 6 * 60, connectHealth: false)
        store.sessions = [
            TestFactory.session(endingDaysAgo: 3, durationMinutes: 300, score: 60), // breaks streak
            TestFactory.session(endingDaysAgo: 2, durationMinutes: 470, score: 90),
            TestFactory.session(endingDaysAgo: 1, durationMinutes: 480, score: 92),
        ]
        #expect(store.onTrackStreak == 2)
    }

    @Test func enablingHealthSyncImportsNights() async {
        let nights = [
            TestFactory.session(endingDaysAgo: 2, durationMinutes: 420, score: 85, source: .healthKit),
            TestFactory.session(endingDaysAgo: 1, durationMinutes: 450, score: 88, source: .healthKit),
        ]
        let mock = MockHealthService(nights: nights)
        let store = TestFactory.makeStore(health: mock)
        store.completeOnboarding(name: "Ada", bedtime: 22 * 60, wakeTime: 6 * 60, connectHealth: false)

        await store.enableHealthSync()

        #expect(store.profile?.healthSyncEnabled == true)
        #expect(mock.authorizeCallCount == 1)
        #expect(store.importedHealthSessions.count == 2)
        #expect(store.displaySessions.count == 2)
        #expect(store.healthSyncState == .connected)
    }

    @Test func deniedHealthAuthorizationLeavesSyncOff() async {
        let mock = MockHealthService(authorizeResult: false, nights: [])
        let store = TestFactory.makeStore(health: mock)
        store.completeOnboarding(name: "Ada", bedtime: 22 * 60, wakeTime: 6 * 60, connectHealth: false)

        await store.enableHealthSync()

        #expect(store.profile?.healthSyncEnabled == false)
        #expect(store.importedHealthSessions.isEmpty)
    }

    @Test func alreadyDeniedHealthAccessSkipsRepromptAndStaysOff() async {
        // Once the OS has recorded a denial, re-requesting silently no-ops, so
        // connectHealth must route to Settings instead of asking again — and it
        // must never flip sync on.
        let mock = MockHealthService(accessDenied: true)
        let store = TestFactory.makeStore(health: mock)
        store.completeOnboarding(name: "Ada", bedtime: 22 * 60, wakeTime: 6 * 60, connectHealth: false)

        #expect(store.healthAccessDenied == true)

        await store.connectHealth()

        #expect(mock.authorizeCallCount == 0)
        #expect(store.profile?.healthSyncEnabled == false)
        #expect(store.healthSyncState == .notConnected)
    }

    @Test func disablingHealthClearsImportedNights() async {
        let mock = MockHealthService(nights: [
            TestFactory.session(endingDaysAgo: 1, durationMinutes: 450, score: 88, source: .healthKit)
        ])
        let store = TestFactory.makeStore(health: mock)
        store.completeOnboarding(name: "Ada", bedtime: 22 * 60, wakeTime: 6 * 60, connectHealth: false)
        await store.enableHealthSync()
        #expect(store.importedHealthSessions.count == 1)

        store.disableHealthSync()
        #expect(store.importedHealthSessions.isEmpty)
        #expect(store.profile?.healthSyncEnabled == false)
    }

    @Test func unavailableHealthReportsUnavailableState() {
        let store = TestFactory.makeStore(health: MockHealthService(available: false))
        store.completeOnboarding(name: "Ada", bedtime: 22 * 60, wakeTime: 6 * 60, connectHealth: false)
        #expect(store.healthSyncState == .unavailable)
    }

    @Test func resetClearsEverything() {
        let store = TestFactory.makeStore()
        store.completeOnboarding(name: "Ada", bedtime: 22 * 60, wakeTime: 6 * 60, connectHealth: false)
        store.sessions = [TestFactory.session(endingDaysAgo: 1, durationMinutes: 450, score: 88)]
        store.resetAll()

        #expect(store.profile == nil)
        #expect(store.sessions.isEmpty)
        #expect(store.importedHealthSessions.isEmpty)
        #expect(!store.isOnboarded)
    }

    @Test func persistenceRoundTripsAcrossStores() {
        let suite = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let persistence = SleepPersistence(defaults: defaults)

        let first = SleepStore(persistence: persistence, health: MockHealthService())
        first.completeOnboarding(name: "Ada", bedtime: 21 * 60, wakeTime: 5 * 60, connectHealth: false)

        let second = SleepStore(persistence: persistence, health: MockHealthService())
        #expect(second.profile?.name == "Ada")
        #expect(second.profile?.bedtime == 21 * 60)
    }
}
