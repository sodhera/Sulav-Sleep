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

/// Errors surfaced to the auth screen. Kept small and user-facing rather than
/// exposing raw SDK/network errors.
enum AuthError: Error, Equatable {
    case invalidCredentials
    case network
    case cancelled
    case unknown(String)

    var message: String {
        switch self {
        case .invalidCredentials: "That email or password isn't right."
        case .network: "Couldn't reach the network. Try again."
        case .cancelled: "Sign-in was cancelled."
        case .unknown(let detail): detail
        }
    }
}
