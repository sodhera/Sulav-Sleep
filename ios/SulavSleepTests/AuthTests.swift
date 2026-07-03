import Foundation
import Testing
@testable import SulavSleep

@MainActor
struct AuthTests {
    @Test func signInWithAppleSetsAuthenticatedAccount() async {
        let store = TestFactory.makeStore(auth: MockAuthClient())
        await store.signInWithApple(idToken: "token", nonce: "nonce")

        #expect(store.isAuthenticated)
        #expect(store.account?.provider == .apple)
        #expect(store.authErrorMessage == nil)
    }

    @Test func signInWithGoogleSetsAuthenticatedAccount() async {
        let store = TestFactory.makeStore(auth: MockAuthClient())
        await store.signInWithGoogle()

        #expect(store.isAuthenticated)
        #expect(store.account?.provider == .google)
    }

    @Test func manualSignUpThenSignInBothSucceed() async {
        let store = TestFactory.makeStore(auth: MockAuthClient())
        await store.signUpEmail(email: "ada@example.com", password: "password123")

        #expect(store.isAuthenticated)
        #expect(store.account?.email == "ada@example.com")
        #expect(store.account?.provider == .email)

        await store.signOut()
        #expect(!store.isAuthenticated)

        await store.signInEmail(email: "ada@example.com", password: "password123")
        #expect(store.isAuthenticated)
    }

    @Test func manualSignInSurfacesInvalidCredentialsError() async {
        let mock = MockAuthClient(errorToThrow: .invalidCredentials)
        let store = TestFactory.makeStore(auth: mock)
        await store.signInEmail(email: "ada@example.com", password: "wrong")

        #expect(!store.isAuthenticated)
        #expect(store.authErrorMessage == AuthError.invalidCredentials.message)
    }

    @Test func signOutClearsAccountAndPersistence() async {
        let store = TestFactory.makeStore(auth: MockAuthClient())
        await store.signInWithApple(idToken: "token", nonce: "nonce")
        #expect(store.isAuthenticated)

        await store.signOut()
        #expect(!store.isAuthenticated)
        #expect(store.account == nil)
    }

    @Test func accountPersistsAcrossStoreInstancesForDisplay() {
        let suite = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let persistence = SleepPersistence(defaults: defaults)
        let account = AppAccount(id: "u-1", email: "ada@example.com", provider: .email)
        persistence.saveAccount(account)

        #expect(persistence.loadAccount() == account)
    }

    @Test func restoreSessionMarksAuthReadyEvenWithoutAnAccount() async {
        let store = TestFactory.makeStore(auth: MockAuthClient())
        await store.restoreSession()

        #expect(store.isAuthReady)
        #expect(!store.isAuthenticated)
    }

    @Test func restoreSessionPicksUpAnAlreadySignedInAccount() async {
        let account = AppAccount(id: "u-2", email: "ada@example.com", provider: .apple)
        let store = TestFactory.makeStore(auth: MockAuthClient(account: account))
        await store.restoreSession()

        #expect(store.isAuthReady)
        #expect(store.account == account)
    }
}
