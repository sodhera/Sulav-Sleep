import Foundation

/// How the signed-in account authenticated. Purely informational — Supabase
/// treats all three the same way once we have a session.
enum AuthProvider: String, Codable {
    case apple
    case google
    case email
}

/// The non-secret slice of a Supabase user we keep around locally for display
/// (name/email on the auth screen, etc). The actual session token lives in
/// the Keychain, managed by `supabase-swift` — this struct never holds one.
struct AppAccount: Codable, Equatable {
    var id: String
    var email: String?
    var provider: AuthProvider

    // Decode-safe, matching the pattern used by `Profile`/`SleepSession` so a
    // future new field doesn't break existing persisted accounts.
    init(id: String, email: String?, provider: AuthProvider) {
        self.id = id
        self.email = email
        self.provider = provider
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        email = try c.decodeIfPresent(String.self, forKey: .email)
        provider = try c.decode(AuthProvider.self, forKey: .provider)
    }
}

/// What a successful sign-in/sign-up call resolved to, so callers can tell a
/// brand-new account from one that already existed (e.g. Apple/Google sign-in
/// silently matching an existing identity instead of creating a new user).
/// Carries the account's cloud profile (if it has one) so a returning user's
/// name/schedule can be restored without re-running onboarding.
struct AuthResult {
    var account: AppAccount
    var isNewAccount: Bool
    var remoteProfile: RemoteProfile?
}

/// The slice of `Profile` that follows the account across devices, stored in
/// Supabase auth user metadata (no separate table — see `docs/auth-setup.md`).
/// Device-bound settings (Health sync, Screen Time lockdown) deliberately stay
/// local: they hinge on per-device permissions that can't travel.
struct RemoteProfile: Codable, Equatable {
    var name: String
    var bedtime: Int
    var wakeTime: Int
    var currentBedtime: Int?
    var currentWakeTime: Int?
    var sleepStruggles: [String]
    var timeSinkApps: [String]
    var primaryGoal: String
    var lateNightPhone: String
    var wakeFeeling: String

    init(
        name: String, bedtime: Int, wakeTime: Int, sleepStruggles: [String], timeSinkApps: [String] = [],
        currentBedtime: Int? = nil, currentWakeTime: Int? = nil,
        primaryGoal: String = "", lateNightPhone: String = "", wakeFeeling: String = ""
    ) {
        self.name = name
        self.bedtime = bedtime
        self.wakeTime = wakeTime
        self.currentBedtime = currentBedtime
        self.currentWakeTime = currentWakeTime
        self.sleepStruggles = sleepStruggles
        self.timeSinkApps = timeSinkApps
        self.primaryGoal = primaryGoal
        self.lateNightPhone = lateNightPhone
        self.wakeFeeling = wakeFeeling
    }

    // Decode-safe: cloud copies written before the newer fields existed must
    // still restore (same pattern as `Profile`).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        bedtime = try c.decode(Int.self, forKey: .bedtime)
        wakeTime = try c.decode(Int.self, forKey: .wakeTime)
        currentBedtime = try c.decodeIfPresent(Int.self, forKey: .currentBedtime)
        currentWakeTime = try c.decodeIfPresent(Int.self, forKey: .currentWakeTime)
        sleepStruggles = try c.decodeIfPresent([String].self, forKey: .sleepStruggles) ?? []
        timeSinkApps = try c.decodeIfPresent([String].self, forKey: .timeSinkApps) ?? []
        primaryGoal = try c.decodeIfPresent(String.self, forKey: .primaryGoal) ?? ""
        lateNightPhone = try c.decodeIfPresent(String.self, forKey: .lateNightPhone) ?? ""
        wakeFeeling = try c.decodeIfPresent(String.self, forKey: .wakeFeeling) ?? ""
    }

    /// From an onboarded local profile. `nil` when there's nothing worth
    /// syncing yet (onboarding not finished).
    init?(profile: Profile?) {
        guard let profile, profile.onboarded else { return nil }
        self.init(
            name: profile.name,
            bedtime: profile.bedtime,
            wakeTime: profile.wakeTime,
            sleepStruggles: profile.sleepStruggles,
            timeSinkApps: profile.timeSinkApps,
            currentBedtime: profile.currentBedtime,
            currentWakeTime: profile.currentWakeTime,
            primaryGoal: profile.primaryGoal,
            lateNightPhone: profile.lateNightPhone,
            wakeFeeling: profile.wakeFeeling
        )
    }

    /// Expand back into a full local `Profile` on a fresh device. Device-bound
    /// settings start at their defaults (off) until re-granted here.
    var asLocalProfile: Profile {
        Profile(
            name: name,
            bedtime: bedtime,
            wakeTime: wakeTime,
            onboarded: true,
            currentBedtime: currentBedtime,
            currentWakeTime: currentWakeTime,
            sleepStruggles: sleepStruggles,
            timeSinkApps: timeSinkApps,
            primaryGoal: primaryGoal,
            lateNightPhone: lateNightPhone,
            wakeFeeling: wakeFeeling
        )
    }
}

/// Errors surfaced to the auth screen. Kept small and user-facing rather than
/// exposing raw SDK/network errors.
enum AuthError: Error, Equatable {
    case invalidCredentials
    case emailAlreadyRegistered
    case emailNotConfirmed
    /// Sign-up succeeded but the project requires email confirmation before a
    /// session exists. Informational, not a failure — the UI styles it as a
    /// notice rather than an error.
    case confirmationEmailSent
    case weakPassword(String)
    case rateLimited
    case network
    case cancelled
    case unknown(String)

    var message: String {
        switch self {
        case .invalidCredentials: "That email or password isn't right."
        case .emailAlreadyRegistered: "That email already has an account. Go back and choose \"I already have an account\" to sign in."
        case .emailNotConfirmed: "Confirm your email first — check your inbox for the confirmation link, then sign in."
        case .confirmationEmailSent: "Almost there — tap the confirmation link we just emailed you, then sign in."
        case .weakPassword(let detail): detail.isEmpty ? "That password is too weak. Try a longer one." : detail
        case .rateLimited: "Too many attempts. Wait a moment and try again."
        case .network: "Couldn't reach the network. Try again."
        case .cancelled: "Sign-in was cancelled."
        case .unknown(let detail): detail
        }
    }

    /// True for messages that are guidance about a normal next step (e.g. the
    /// confirmation email), so the UI can present them calmly instead of in
    /// the error color.
    var isNotice: Bool {
        self == .confirmationEmailSent
    }
}
