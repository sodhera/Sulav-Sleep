import Foundation
import Supabase

// MARK: - Protocol (testable)

/// Cloud persistence for profiles and sleep sessions. Mirrors the shape of
/// `AuthProviding` and `SleepHealthProviding` so `SleepStore` can be tested
/// with a mock cloud layer.
///
/// All calls are best-effort: failures log, never crash. The local device
/// remains the source of truth; the cloud is a durable backup that survives
/// device loss and enables cross-device restore.
protocol CloudSyncing: Sendable {
    /// Fetch the user's profile from the `profiles` table.
    func fetchProfile(userId: String) async -> CloudProfile?
    /// Upsert the user's profile into the `profiles` table. Returns whether
    /// the write actually landed, so one-shot callers can retry next launch
    /// instead of retiring themselves on a failure they never saw.
    @discardableResult
    func upsertProfile(_ profile: CloudProfile, userId: String) async -> Bool
    /// Fetch all sleep sessions for the user from the `sleep_sessions` table.
    func fetchSessions(userId: String) async -> [SleepSession]
    /// Upsert one or more sessions into the `sleep_sessions` table. Returns
    /// whether the write landed (see `upsertProfile`).
    @discardableResult
    func upsertSessions(_ sessions: [SleepSession], userId: String) async -> Bool
}

// MARK: - Factory

enum SleepCloud {
    /// Returns the real Supabase-backed cloud service if a shared client
    /// exists, otherwise a no-op stub. Called after `SulavAuth.makeDefault()`
    /// which creates the shared client.
    static func makeDefault() -> CloudSyncing {
        guard let client = SulavAuth.sharedClient else {
            return DisabledCloudService()
        }
        return SupabaseCloudService(client: client)
    }
}

// MARK: - Cloud profile model

/// The table-backed profile model. Maps directly to/from the `profiles`
/// table columns. Device-bound fields (healthSyncEnabled, blockDuringSleep,
/// healthPromptDismissed) deliberately stay local — they hinge on per-device
/// permission grants.
struct CloudProfile: Codable, Equatable, Sendable {
    var name: String
    var bedtime: Int
    var wakeTime: Int
    var onboarded: Bool
    var struggles: [String]
    var timeSinks: [String]
    var goal: String
    var lateNightPhone: String
    var wakeFeeling: String

    /// Build from a local `Profile`. Returns nil when onboarding isn't done.
    init?(profile: Profile?) {
        guard let profile, profile.onboarded else { return nil }
        self.name = profile.name
        self.bedtime = profile.bedtime
        self.wakeTime = profile.wakeTime
        self.onboarded = profile.onboarded
        self.struggles = profile.sleepStruggles
        self.timeSinks = profile.timeSinkApps
        self.goal = profile.primaryGoal
        self.lateNightPhone = profile.lateNightPhone
        self.wakeFeeling = profile.wakeFeeling
    }

    init(
        name: String, bedtime: Int, wakeTime: Int, onboarded: Bool,
        struggles: [String] = [], timeSinks: [String] = [],
        goal: String = "", lateNightPhone: String = "", wakeFeeling: String = ""
    ) {
        self.name = name
        self.bedtime = bedtime
        self.wakeTime = wakeTime
        self.onboarded = onboarded
        self.struggles = struggles
        self.timeSinks = timeSinks
        self.goal = goal
        self.lateNightPhone = lateNightPhone
        self.wakeFeeling = wakeFeeling
    }

    /// Convert to a local `Profile`, filling in device-bound defaults.
    var asLocalProfile: Profile {
        Profile(
            name: name,
            bedtime: bedtime,
            wakeTime: wakeTime,
            onboarded: onboarded,
            sleepStruggles: struggles,
            timeSinkApps: timeSinks,
            primaryGoal: goal,
            lateNightPhone: lateNightPhone,
            wakeFeeling: wakeFeeling
        )
    }

    /// Build from a legacy `RemoteProfile` (auth metadata migration path).
    init(from remote: RemoteProfile) {
        self.name = remote.name
        self.bedtime = remote.bedtime
        self.wakeTime = remote.wakeTime
        self.onboarded = true  // RemoteProfile only exists for onboarded users
        self.struggles = remote.sleepStruggles
        self.timeSinks = remote.timeSinkApps
        self.goal = remote.primaryGoal
        self.lateNightPhone = remote.lateNightPhone
        self.wakeFeeling = remote.wakeFeeling
    }

    // MARK: - Table row coding (snake_case columns)

    enum CodingKeys: String, CodingKey {
        case name, bedtime, onboarded, struggles, goal
        case wakeTime = "wake_time"
        case timeSinks = "time_sinks"
        case lateNightPhone = "late_night_phone"
        case wakeFeeling = "wake_feeling"
    }
}

// MARK: - Table row models (PostgREST encoding/decoding)

/// Row shape for upserts into the `profiles` table. Includes the `id` column.
private struct ProfileRow: Encodable {
    let id: String
    let name: String
    let bedtime: Int
    let wake_time: Int
    let onboarded: Bool
    let struggles: [String]
    let time_sinks: [String]
    let goal: String
    let late_night_phone: String
    let wake_feeling: String

    init(userId: String, profile: CloudProfile) {
        self.id = userId
        self.name = profile.name
        self.bedtime = profile.bedtime
        self.wake_time = profile.wakeTime
        self.onboarded = profile.onboarded
        self.struggles = profile.struggles
        self.time_sinks = profile.timeSinks
        self.goal = profile.goal
        self.late_night_phone = profile.lateNightPhone
        self.wake_feeling = profile.wakeFeeling
    }
}

/// Row shape for the `sleep_sessions` table.
private struct SessionRow: Codable {
    let id: String
    let user_id: String
    let started_at: String   // ISO 8601
    let ended_at: String     // ISO 8601
    let duration_minutes: Int
    let source: String

    init(userId: String, session: SleepSession) {
        self.id = session.id
        self.user_id = userId
        self.started_at = Self.isoFractional.string(from: session.start)
        self.ended_at = Self.isoFractional.string(from: session.end)
        self.duration_minutes = session.durationMinutes
        self.source = session.source.rawValue
    }

    var asSleepSession: SleepSession? {
        guard let start = Self.date(from: started_at),
              let end = Self.date(from: ended_at) else { return nil }
        return SleepSession(
            id: id,
            start: start,
            end: end,
            durationMinutes: duration_minutes,
            source: SleepSource(rawValue: source) ?? .local
        )
    }

    /// Parses a `timestamptz` as PostgREST renders it. Two formatters, not
    /// one, because Postgres trims trailing zeros from the fractional part and
    /// omits it entirely on a whole second — and `ISO8601DateFormatter` with
    /// `.withFractionalSeconds` returns nil for a string with no fraction,
    /// while the same formatter *without* the option returns nil for one that
    /// has it. A single formatter therefore drops a real subset of rows, and a
    /// dropped row reads to the user as a night that was never saved.
    static func date(from raw: String) -> Date? {
        isoFractional.date(from: raw) ?? isoWhole.date(from: raw)
    }

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoWhole: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}

// MARK: - Disabled (no Supabase config)

/// No-op client used when Supabase credentials aren't configured.
struct DisabledCloudService: CloudSyncing {
    func fetchProfile(userId: String) async -> CloudProfile? { nil }
    func upsertProfile(_ profile: CloudProfile, userId: String) async -> Bool { false }
    func fetchSessions(userId: String) async -> [SleepSession] { [] }
    func upsertSessions(_ sessions: [SleepSession], userId: String) async -> Bool { false }
}

// MARK: - Real Supabase implementation

/// Uses the shared `SupabaseClient` (created by `SulavAuth.makeDefault()`)
/// so every PostgREST query automatically carries the user's JWT.
final class SupabaseCloudService: CloudSyncing, @unchecked Sendable {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    // MARK: - Profile

    func fetchProfile(userId: String) async -> CloudProfile? {
        do {
            let rows: [CloudProfile] = try await client
                .from("profiles")
                .select()
                .eq("id", value: userId)
                .limit(1)
                .execute()
                .value
            return rows.first
        } catch {
            AppLog.app.error("Cloud: fetch profile failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    @discardableResult
    func upsertProfile(_ profile: CloudProfile, userId: String) async -> Bool {
        let row = ProfileRow(userId: userId, profile: profile)
        do {
            try await client
                .from("profiles")
                .upsert(row, onConflict: "id")
                .execute()
            AppLog.app.info("Cloud: profile upserted")
            return true
        } catch {
            AppLog.app.error("Cloud: upsert profile failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    // MARK: - Sessions

    func fetchSessions(userId: String) async -> [SleepSession] {
        do {
            let rows: [SessionRow] = try await client
                .from("sleep_sessions")
                .select()
                .eq("user_id", value: userId)
                .order("ended_at", ascending: false)
                .execute()
                .value
            let sessions = rows.compactMap(\.asSleepSession)
            // A row that survives JSON decoding but not date parsing is
            // history silently vanishing, so it is worth a line in the log.
            if sessions.count != rows.count {
                AppLog.app.error("Cloud: dropped \(rows.count - sessions.count) unparseable session row(s)")
            }
            return sessions
        } catch {
            AppLog.app.error("Cloud: fetch sessions failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    @discardableResult
    func upsertSessions(_ sessions: [SleepSession], userId: String) async -> Bool {
        guard !sessions.isEmpty else { return true }
        let rows = sessions.map { SessionRow(userId: userId, session: $0) }
        do {
            try await client
                .from("sleep_sessions")
                .upsert(rows, onConflict: "user_id,id")
                .execute()
            AppLog.app.info("Cloud: upserted \(sessions.count) session(s)")
            return true
        } catch {
            AppLog.app.error("Cloud: upsert sessions failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
