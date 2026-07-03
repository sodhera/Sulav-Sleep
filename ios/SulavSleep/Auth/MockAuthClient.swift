import Foundation

/// Deterministic, in-memory auth stand-in used by unit tests and by UI tests
/// launched with `-uitest-mock-auth` so neither ever hits the network.
final class MockAuthClient: AuthProviding {
    var account: AppAccount?
    var errorToThrow: AuthError?

    private(set) var signInWithAppleCallCount = 0
    private(set) var signInWithGoogleCallCount = 0
    private(set) var signUpCallCount = 0
    private(set) var signInCallCount = 0
    private(set) var signOutCallCount = 0

    init(account: AppAccount? = nil, errorToThrow: AuthError? = nil) {
        self.account = account
        self.errorToThrow = errorToThrow
    }

    var currentAccount: AppAccount? { get async { account } }

    func signInWithApple(idToken: String, nonce: String) async throws -> AppAccount {
        signInWithAppleCallCount += 1
        return try resolve(provider: .apple)
    }

    func signInWithGoogle() async throws -> AppAccount {
        signInWithGoogleCallCount += 1
        return try resolve(provider: .google)
    }

    func signUp(email: String, password: String) async throws -> AppAccount {
        signUpCallCount += 1
        return try resolve(provider: .email, email: email)
    }

    func signIn(email: String, password: String) async throws -> AppAccount {
        signInCallCount += 1
        return try resolve(provider: .email, email: email)
    }

    func signOut() async {
        signOutCallCount += 1
        account = nil
    }

    private func resolve(provider: AuthProvider, email: String? = nil) throws -> AppAccount {
        if let errorToThrow { throw errorToThrow }
        let resolved = AppAccount(id: "mock-\(provider.rawValue)", email: email, provider: provider)
        account = resolved
        return resolved
    }
}
