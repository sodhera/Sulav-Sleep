import Foundation
#if canImport(AuthenticationServices)
import AuthenticationServices
#endif
#if canImport(CryptoKit)
import CryptoKit
#endif
import Auth

// MARK: - Provider protocol (so the store can be tested with a mock)

/// Account auth, independent of the app's local sleep data. Mirrors
/// `SleepHealthProviding`'s shape so `SleepStore` can be tested the same way.
protocol AuthProviding {
    /// The signed-in account, if a session is already restored/valid. `nil`
    /// until the initial check completes.
    var currentAccount: AppAccount? { get async }

    func signInWithApple(idToken: String, nonce: String) async throws -> AppAccount
    func signInWithGoogle() async throws -> AppAccount
    func signUp(email: String, password: String) async throws -> AppAccount
    func signIn(email: String, password: String) async throws -> AppAccount
    func signOut() async
}

enum SulavAuth {
    /// The real Supabase-backed client when `Config.xcconfig` has real
    /// values, otherwise a no-op client so the app still builds/runs (auth
    /// calls just fail) for anyone who hasn't wired up credentials yet. See
    /// `docs/auth-setup.md`.
    static func makeDefault() -> AuthProviding {
        guard let url = SupabaseConfig.url, let anonKey = SupabaseConfig.anonKey else {
            AppLog.app.notice("Supabase config missing — auth screen will show errors until Config.xcconfig is set up")
            return DisabledAuthClient()
        }
        return SupabaseAuthClient(url: url, anonKey: anonKey)
    }
}

/// No-op provider used when Supabase credentials aren't configured yet.
struct DisabledAuthClient: AuthProviding {
    var currentAccount: AppAccount? { get async { nil } }
    func signInWithApple(idToken: String, nonce: String) async throws -> AppAccount { throw AuthError.unknown("Sign-in isn't configured yet.") }
    func signInWithGoogle() async throws -> AppAccount { throw AuthError.unknown("Sign-in isn't configured yet.") }
    func signUp(email: String, password: String) async throws -> AppAccount { throw AuthError.unknown("Sign-in isn't configured yet.") }
    func signIn(email: String, password: String) async throws -> AppAccount { throw AuthError.unknown("Sign-in isn't configured yet.") }
    func signOut() async {}
}

// MARK: - Config

enum SupabaseConfig {
    static var url: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
              !raw.isEmpty, !raw.hasPrefix("your-"), raw.hasPrefix("http")
        else { return nil }
        return URL(string: raw)
    }

    static var anonKey: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
              !raw.isEmpty, !raw.hasPrefix("your-")
        else { return nil }
        return raw
    }
}

// MARK: - Real Supabase implementation

final class SupabaseAuthClient: AuthProviding {
    private let client: AuthClient

    var currentAccount: AppAccount? {
        get async {
            guard let session = try? await client.session else { return nil }
            return Self.account(from: session)
        }
    }

    init(url: URL, anonKey: String) {
        // Keychain-backed local storage, so session tokens are never written
        // into our own UserDefaults blob.
        client = AuthClient(
            url: url.appendingPathComponent("auth/v1"),
            headers: ["apikey": anonKey],
            localStorage: AuthClient.Configuration.defaultLocalStorage
        )
    }

    func signInWithApple(idToken: String, nonce: String) async throws -> AppAccount {
        do {
            let session = try await client.signInWithIdToken(
                credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce)
            )
            AppLog.app.info("Signed in with Apple")
            return Self.account(from: session)
        } catch {
            throw Self.mapError(error)
        }
    }

    @MainActor
    func signInWithGoogle() async throws -> AppAccount {
        do {
            let session = try await client.signInWithOAuth(
                provider: .google,
                redirectTo: URL(string: "sleepblock://auth-callback")
            ) { url in
                try await Self.presentOAuthSession(url: url)
            }
            AppLog.app.info("Signed in with Google")
            return Self.account(from: session)
        } catch {
            throw Self.mapError(error)
        }
    }

    func signUp(email: String, password: String) async throws -> AppAccount {
        do {
            let response = try await client.signUp(email: email, password: password)
            guard let session = response.session else {
                // Email confirmation required by the Supabase project settings.
                throw AuthError.unknown("Check your email to confirm your account, then sign in.")
            }
            AppLog.app.info("Signed up with email")
            return Self.account(from: session)
        } catch let authError as AuthError {
            throw authError
        } catch {
            throw Self.mapError(error)
        }
    }

    func signIn(email: String, password: String) async throws -> AppAccount {
        do {
            let session = try await client.signIn(email: email, password: password)
            AppLog.app.info("Signed in with email")
            return Self.account(from: session)
        } catch {
            throw Self.mapError(error)
        }
    }

    func signOut() async {
        try? await client.signOut()
        AppLog.app.info("Signed out")
    }

    private static func account(from session: Session) -> AppAccount {
        let provider = session.user.appMetadata["provider"]?.stringValue
        return AppAccount(
            id: session.user.id.uuidString,
            email: session.user.email,
            provider: AuthProvider(rawValue: provider ?? "email") ?? .email
        )
    }

    private static func mapError(_ error: Error) -> AuthError {
        if let urlError = error as? URLError { return urlError.code == .cancelled ? .cancelled : .network }
        let text = error.localizedDescription.lowercased()
        if text.contains("invalid") || text.contains("credentials") { return .invalidCredentials }
        return .unknown(error.localizedDescription)
    }

    #if canImport(AuthenticationServices)
    @MainActor
    private static func presentOAuthSession(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "sleepblock") { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(throwing: AuthError.cancelled)
                }
            }
            session.presentationContextProvider = OAuthPresentationContextProvider.shared
            session.prefersEphemeralWebBrowserSession = true
            session.start()
        }
    }
    #endif
}

#if canImport(AuthenticationServices)
/// Anchors the OAuth sheet to the app's key window. A tiny singleton since
/// `ASWebAuthenticationSession` needs the context provider to outlive the
/// session start call.
final class OAuthPresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = OAuthPresentationContextProvider()

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if canImport(UIKit)
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
        #else
        ASPresentationAnchor()
        #endif
    }
}
#endif

// MARK: - Apple Sign In nonce helper

#if canImport(CryptoKit)
enum AppleSignInNonce {
    /// Standard Apple sample-code nonce generation: a random raw nonce sent
    /// with the request, whose SHA256 hash is what Apple signs. Supabase
    /// verifies the raw nonce against Apple's signed hash server-side.
    static func randomNonce(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        precondition(status == errSecSuccess)

        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(randomBytes.map { charset[Int($0) % charset.count] })
    }

    static func sha256(_ input: String) -> String {
        let hashed = SHA256.hash(data: Data(input.utf8))
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
}
#endif
