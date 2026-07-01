import Foundation
import Observation

@Observable
final class SleepStore {
    var profile: Profile?
    var sessions: [SleepSession] = []
    var activeSession: ActiveSleepSession?
    var selectedTab: AppTab = .home

    private let persistence: SleepPersistence

    init(persistence: SleepPersistence = .shared) {
        self.persistence = persistence
        reload()
    }

    var isOnboarded: Bool {
        profile?.onboarded == true
    }

    var latestSession: SleepSession? {
        sessions.last
    }

    var targetMinutes: Int {
        guard let profile else { return 8 * 60 }
        return SleepMath.windowMinutes(bedtime: profile.bedtime, wakeTime: profile.wakeTime)
    }

    var onTrackStreak: Int {
        var streak = 0
        for session in sessions.reversed() {
            guard session.score >= 80 else { break }
            streak += 1
        }
        return streak
    }

    func reload() {
        let snapshot = persistence.load()
        profile = snapshot.profile
        sessions = snapshot.sessions
        activeSession = snapshot.activeSession
    }

    func completeOnboarding(name: String, bedtime: Int, wakeTime: Int) {
        let nextProfile = Profile(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Friend" : name,
            bedtime: bedtime,
            wakeTime: wakeTime,
            onboarded: true
        )
        profile = nextProfile
        sessions = SleepSeed.sessions(targetMinutes: SleepMath.windowMinutes(bedtime: bedtime, wakeTime: wakeTime), now: Date())
        activeSession = nil
        persist()
    }

    func startSleep() {
        activeSession = ActiveSleepSession(start: Date())
        selectedTab = .home
        persist()
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
            score: SleepMath.score(durationMinutes: minutes, targetMinutes: targetMinutes)
        )
        sessions.append(session)
        self.activeSession = nil
        persist()
    }

    func saveSchedule(bedtime: Int, wakeTime: Int) {
        guard var profile else { return }
        profile.bedtime = bedtime
        profile.wakeTime = wakeTime
        self.profile = profile
        persist()
    }

    func saveName(_ name: String) {
        guard var profile else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        profile.name = trimmed
        self.profile = profile
        persist()
    }

    func resetAll() {
        profile = nil
        sessions = []
        activeSession = nil
        selectedTab = .home
        persistence.reset()
    }

    private func persist() {
        persistence.save(
            SleepSnapshot(
                profile: profile,
                sessions: sessions,
                activeSession: activeSession
            )
        )
    }
}

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

enum SleepMath {
    static func windowMinutes(bedtime: Int, wakeTime: Int) -> Int {
        var diff = wakeTime - bedtime
        if diff <= 0 {
            diff += 1_440
        }
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

enum SleepSeed {
    static func sessions(targetMinutes: Int, now: Date) -> [SleepSession] {
        [430, 468, 384, 502, 410, 451].enumerated().map { index, duration in
            let daysAgo = 6 - index
            let end = Calendar.current.date(byAdding: .day, value: -daysAgo, to: now) ?? now
            let adjustedEnd = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: end) ?? end
            let start = adjustedEnd.addingTimeInterval(TimeInterval(-duration * 60))
            return SleepSession(
                id: "seed-\(index)",
                start: start,
                end: adjustedEnd,
                durationMinutes: duration,
                score: SleepMath.score(durationMinutes: duration, targetMinutes: targetMinutes)
            )
        }
    }
}

