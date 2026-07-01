import Foundation
import Observation
import WidgetKit

@Observable
final class SleepStore {
    /// Nights the user logged in-app. Local source of truth, always persisted.
    var sessions: [SleepSession] = []
    /// Nights imported from Apple Health. Refreshed at runtime, never persisted.
    var importedHealthSessions: [SleepSession] = []
    var profile: Profile?
    var activeSession: ActiveSleepSession?
    var selectedTab: AppTab = .home
    var isImportingHealth = false

    private let persistence: SleepPersistence
    private let health: SleepHealthProviding
    private let screenTime: ScreenTimeControlling

    init(
        persistence: SleepPersistence = .shared,
        health: SleepHealthProviding? = nil,
        screenTime: ScreenTimeControlling? = nil
    ) {
        self.persistence = persistence
        self.health = health ?? SleepHealth.makeDefault()
        self.screenTime = screenTime ?? SleepScreenTime.makeDefault()
        // UI tests launch with a clean slate so onboarding is deterministic.
        if CommandLine.arguments.contains("-uitest-reset") {
            persistence.reset()
        }
        reload()
    }

    // MARK: - Derived state

    var isOnboarded: Bool { profile?.onboarded == true }

    /// The single, deduplicated history shown across the app. Health wins over a
    /// local record for the same night so a night we wrote to Health isn't
    /// counted twice. See `SleepMerge`.
    var displaySessions: [SleepSession] {
        SleepMerge.merge(local: sessions, health: importedHealthSessions)
    }

    var latestSession: SleepSession? { displaySessions.last }

    var targetMinutes: Int {
        guard let profile else { return 8 * 60 }
        return SleepMath.windowMinutes(bedtime: profile.bedtime, wakeTime: profile.wakeTime)
    }

    var onTrackStreak: Int {
        var streak = 0
        for session in displaySessions.reversed() {
            guard session.score >= 80 else { break }
            streak += 1
        }
        return streak
    }

    var healthSyncState: HealthSyncState {
        guard health.isAvailable else { return .unavailable }
        return profile?.healthSyncEnabled == true ? .connected : .notConnected
    }

    var screenTimeState: ScreenTimeState { screenTime.authorizationState() }
    var lockdownEnabled: Bool { profile?.lockdownEnabled == true }
    var lockdownMaxHours: Int { profile?.lockdownMaxHours ?? 6 }

    // MARK: - Lifecycle

    func reload() {
        let snapshot = persistence.load()
        profile = snapshot.profile
        sessions = snapshot.sessions
        activeSession = snapshot.activeSession
        updateWidget()
    }

    /// Publish a compact summary to the App Group and refresh the home-screen
    /// widget. Called on every change to displayed history.
    private func updateWidget() {
        guard !AppEnvironment.isTesting else { return }
        let recent = Array(displaySessions.suffix(7)).map {
            WidgetNight(end: $0.end, durationMinutes: $0.durationMinutes, score: $0.score)
        }
        let summary = SleepWidgetSummary(
            nights: recent,
            latestScore: latestSession?.score,
            latestDurationMinutes: latestSession?.durationMinutes,
            streak: onTrackStreak,
            targetMinutes: targetMinutes,
            updated: Date()
        )
        SleepWidgetStore.save(summary)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Called when the app becomes active. Pulls fresh nights from Health if the
    /// user has connected it.
    @MainActor
    func refreshHealthIfEnabled() async {
        guard profile?.healthSyncEnabled == true else { return }
        await refreshHealth()
    }

    // MARK: - Onboarding

    func completeOnboarding(name: String, bedtime: Int, wakeTime: Int, connectHealth: Bool) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        profile = Profile(
            name: trimmed.isEmpty ? "Friend" : trimmed,
            bedtime: bedtime,
            wakeTime: wakeTime,
            onboarded: true,
            healthSyncEnabled: false
        )
        // No seeding: the history is empty until the user logs a real night or
        // connects Apple Health.
        sessions = []
        importedHealthSessions = []
        activeSession = nil
        persist()
        AppLog.store.info("Onboarding complete (connectHealth=\(connectHealth))")
        if connectHealth {
            Task { await enableHealthSync() }
        }
    }

    // MARK: - Sleep loop

    func startSleep() {
        let start = Date()
        activeSession = ActiveSleepSession(start: start)
        selectedTab = .home
        persist(refreshWidget: false)
        if profile?.lockdownEnabled == true { screenTime.startLockdown() }
        if !AppEnvironment.isTesting {
            Task { SleepLiveActivity.start(startDate: start) }
        }
        AppLog.store.info("Sleep session started")
    }

    /// Leave the sleep screen without logging a night — for someone who opened
    /// it to peek or tapped Sleep Now by mistake.
    func cancelSleep() {
        activeSession = nil
        screenTime.endLockdown()
        if !AppEnvironment.isTesting { SleepLiveActivity.end() }
        persist(refreshWidget: false)
        AppLog.store.info("Sleep session canceled (not logged)")
    }

    func wakeUp() {
        guard let activeSession else { return }
        let end = Date()
        let minutes = max(1, Int((end.timeIntervalSince(activeSession.start) / 60).rounded()))
        let session = SleepSession(
            id: "s-\(Int(end.timeIntervalSince1970))",
            start: activeSession.start,
            end: end,
            durationMinutes: minutes,
            score: SleepMath.score(durationMinutes: minutes, targetMinutes: targetMinutes),
            source: .local
        )
        sessions.append(session)
        self.activeSession = nil
        screenTime.endLockdown()
        if !AppEnvironment.isTesting { SleepLiveActivity.end() }
        persist()
        AppLog.store.info("Logged night: \(minutes)m, score \(session.score)")

        if profile?.healthSyncEnabled == true {
            Task {
                await health.save(session: session)
                await refreshHealth()
            }
        }
    }

    // MARK: - Health sync

    @MainActor
    func enableHealthSync() async {
        guard health.isAvailable else {
            AppLog.health.notice("HealthKit unavailable on this device")
            return
        }
        let granted = await health.requestAuthorization()
        guard var profile else { return }
        profile.healthSyncEnabled = granted
        self.profile = profile
        persist()
        if granted {
            await refreshHealth()
        }
    }

    func disableHealthSync() {
        guard var profile else { return }
        profile.healthSyncEnabled = false
        self.profile = profile
        importedHealthSessions = []
        persist()
        AppLog.store.info("Health sync disabled")
    }

    // MARK: - Sleep lockdown (Screen Time)

    @MainActor
    func enableLockdown() async {
        let granted = await screenTime.requestAuthorization()
        guard var profile else { return }
        profile.lockdownEnabled = granted
        self.profile = profile
        persist()
        if granted { rescheduleLockdown() }
        AppLog.store.info("Sleep lockdown \(granted ? "enabled" : "denied")")
    }

    func disableLockdown() {
        guard var profile else { return }
        profile.lockdownEnabled = false
        self.profile = profile
        screenTime.endLockdown()
        screenTime.cancelScheduledLockdown()
        persist()
        AppLog.store.info("Sleep lockdown disabled")
    }

    func setLockdownMaxHours(_ hours: Int) {
        guard var profile else { return }
        profile.lockdownMaxHours = hours
        self.profile = profile
        persist()
        if profile.lockdownEnabled { rescheduleLockdown() }
    }

    /// Opaque encoded app selection for the lockdown picker UI.
    func appSelectionData() -> Data? { screenTime.selectionData() }
    func saveAppSelection(_ data: Data) {
        screenTime.saveSelection(data: data)
        if profile?.lockdownEnabled == true { rescheduleLockdown() }
    }

    /// Re-registers the scheduled bedtime->wake DeviceActivityMonitor window so
    /// the shield applies/clears even if the app isn't open.
    private func rescheduleLockdown() {
        guard let profile, profile.lockdownEnabled else { return }
        screenTime.scheduleLockdown(
            bedtimeMinutes: profile.bedtime,
            wakeMinutes: profile.wakeTime,
            maxHours: profile.lockdownMaxHours
        )
    }

    @MainActor
    func refreshHealth() async {
        guard health.isAvailable, profile?.healthSyncEnabled == true else { return }
        isImportingHealth = true
        defer { isImportingHealth = false }
        importedHealthSessions = await health.fetchNights(days: 30, targetMinutes: targetMinutes)
        AppLog.store.info("Display history now \(self.displaySessions.count) night(s)")
        updateWidget()
    }

    // MARK: - Profile edits

    func saveSchedule(bedtime: Int, wakeTime: Int) {
        guard var profile else { return }
        profile.bedtime = bedtime
        profile.wakeTime = wakeTime
        self.profile = profile
        persist()
        rescheduleLockdown()
    }

    func saveName(_ name: String) {
        guard var profile else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        profile.name = trimmed
        self.profile = profile
        persist(refreshWidget: false)
    }

    func resetAll() {
        profile = nil
        sessions = []
        importedHealthSessions = []
        activeSession = nil
        selectedTab = .home
        persistence.reset()
        updateWidget()
        AppLog.store.info("All data reset")
    }

    private func persist(refreshWidget: Bool = true) {
        persistence.save(
            SleepSnapshot(profile: profile, sessions: sessions, activeSession: activeSession)
        )
        if refreshWidget {
            updateWidget()
        }
    }
}

// MARK: - History merge (pure, testable)

enum SleepMerge {
    static func merge(
        local: [SleepSession],
        health: [SleepSession],
        calendar: Calendar = .current
    ) -> [SleepSession] {
        var byNight: [Date: SleepSession] = [:]
        for session in local {
            byNight[key(for: session.end, calendar: calendar)] = session
        }
        for session in health {
            byNight[key(for: session.end, calendar: calendar)] = session // Health wins
        }
        return byNight.values.sorted { $0.end < $1.end }
    }

    /// A stable per-night key. Shifting back 12h keeps early-morning wake times
    /// grouped with the evening they belong to.
    static func key(for end: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: end.addingTimeInterval(-12 * 3600))
    }
}

// MARK: - Persistence

struct SleepSnapshot: Codable {
    var profile: Profile?
    var sessions: [SleepSession]
    var activeSession: ActiveSleepSession?
}

struct SleepPersistence {
    static let shared = SleepPersistence()

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private let profileKey = "sulav.profile.v1"
    private let sessionsKey = "sulav.sessions.v1"
    private let activeKey = "sulav.active.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() -> SleepSnapshot {
        SleepSnapshot(
            profile: decode(Profile.self, forKey: profileKey),
            sessions: decode([SleepSession].self, forKey: sessionsKey) ?? [],
            activeSession: decode(ActiveSleepSession.self, forKey: activeKey)
        )
    }

    func save(_ snapshot: SleepSnapshot) {
        encode(snapshot.profile, forKey: profileKey)
        encode(snapshot.sessions, forKey: sessionsKey)
        encode(snapshot.activeSession, forKey: activeKey)
    }

    func reset() {
        defaults.removeObject(forKey: profileKey)
        defaults.removeObject(forKey: sessionsKey)
        defaults.removeObject(forKey: activeKey)
    }

    func startSleepFromIntent() {
        encode(ActiveSleepSession(start: Date()), forKey: activeKey)
    }

    private func decode<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private func encode<T: Encodable>(_ value: T?, forKey key: String) {
        guard let value, let data = try? encoder.encode(value) else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(data, forKey: key)
    }
}

// MARK: - Sleep math (pure, testable)

enum SleepMath {
    static func windowMinutes(bedtime: Int, wakeTime: Int) -> Int {
        var diff = wakeTime - bedtime
        if diff <= 0 { diff += 1_440 }
        return diff
    }

    static func score(durationMinutes: Int, targetMinutes: Int) -> Int {
        let ratio = Double(durationMinutes) / Double(max(targetMinutes, 1))
        let raw: Double
        if ratio >= 1 {
            raw = 92 + min(8, (ratio - 1) * 30)
        } else {
            raw = 100 - (1 - ratio) * 140
        }
        return max(40, min(100, Int(raw.rounded())))
    }
}
