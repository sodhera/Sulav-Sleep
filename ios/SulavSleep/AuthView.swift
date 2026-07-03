import SwiftUI
import AuthenticationServices

/// Which single-purpose account screen this is. The two are never linked to
/// each other — the user picks a path on the welcome screen, so there is no
/// "already have an account?" cross-link on either. `.signUp` is the final step
/// of the sign-up flow; `.signIn` is the standalone returning-user path.
enum AuthIntent {
    case signUp
    case signIn
}

/// Standalone account screen used for the sign-in path (from welcome, with a
/// back chevron) and the post-sign-out gate (no back — a returning user at the
/// root). The sign-up flow embeds `AuthMethodsView` directly instead so it can
/// carry the questionnaire's progress bar and back button.
struct AuthView: View {
    @Bindable var store: SleepStore
    var intent: AuthIntent = .signIn
    /// Back to the welcome screen, when this screen was reached from it.
    var onBack: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            if let onBack {
                HStack {
                    GlassBackButton {
                        Haptics.soft()
                        Keyboard.dismiss()
                        onBack()
                    }
                    Spacer()
                }
                .padding(.horizontal, SleepSpacing.xxl)
                .padding(.top, SleepSpacing.md)
            }

            AuthMethodsView(store: store, intent: intent)
        }
        .safeAreaPadding(.top)
        .safeAreaPadding(.bottom)
    }
}

/// The account methods themselves: native Sign in with Apple, Google via a web
/// OAuth sheet, and manual email/password. Single-purpose — the mode is fixed
/// by `intent`, with no sign-up/sign-in toggle. Rendered standalone by
/// `AuthView` and embedded as the final step of the sign-up questionnaire.
struct AuthMethodsView: View {
    @Bindable var store: SleepStore
    let intent: AuthIntent

    @State private var showEmailForm = false
    @State private var email = ""
    @State private var password = ""
    @State private var appleNonce: String?
    @FocusState private var focusedField: Field?

    private enum Field { case email, password }

    private var title: String {
        intent == .signIn ? "Welcome back" : "Save your sleep plan"
    }

    private var subtitle: String {
        intent == .signIn
            ? "Sign in to pick up where you left off."
            : "Create a free account so your plan and your nights follow you across devices."
    }

    private var emailActionTitle: String {
        intent == .signIn ? "Sign in" : "Create account"
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: SleepSpacing.md) {
                Text(title)
                    .font(SleepFont.hero(30))
                    .foregroundStyle(SleepColor.ink)
                Text(subtitle)
                    .font(SleepFont.body(16))
                    .foregroundStyle(SleepColor.dim)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .frame(maxWidth: 300)
            }
            .padding(.horizontal, SleepSpacing.xxl)

            Spacer()

            if let message = store.authErrorMessage {
                Text(message)
                    .font(SleepFont.body(14))
                    .foregroundStyle(SleepColor.danger)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, SleepSpacing.xxl)
                    .padding(.bottom, SleepSpacing.md)
            }

            Group {
                if showEmailForm {
                    emailForm
                } else {
                    providerButtons
                }
            }
            .padding(.horizontal, SleepSpacing.xxl)
            .padding(.bottom, SleepSpacing.xxl)
        }
        .frame(maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.22), value: showEmailForm)
    }

    // MARK: - Provider choice

    @ViewBuilder
    private var providerButtons: some View {
        VStack(spacing: SleepSpacing.md) {
            SignInWithAppleButton(intent == .signIn ? .signIn : .signUp) { request in
                request.requestedScopes = [.email, .fullName]
                let nonce = AppleSignInNonce.randomNonce()
                appleNonce = nonce
                request.nonce = AppleSignInNonce.sha256(nonce)
            } onCompletion: { result in
                handleAppleCompletion(result)
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 58)
            .cornerRadius(SleepRadius.pill / 2)
            .opacity(store.isAuthenticating ? 0.5 : 1)
            .overlay {
                if store.isAuthenticating {
                    ProgressView()
                        .tint(.black)
                }
            }
            .disabled(store.isAuthenticating)

            LiquidPrimaryButton(title: "Continue with Google", systemImage: "globe") {
                Haptics.soft()
                store.authErrorMessage = nil
                Task { await store.signInWithGoogle() }
            }
            .disabled(store.isAuthenticating)

            LiquidSecondaryButton(title: "Continue with email", systemImage: "envelope") {
                Haptics.soft()
                store.authErrorMessage = nil
                withAnimation(.easeInOut(duration: 0.22)) { showEmailForm = true }
            }
            .disabled(store.isAuthenticating)
        }
    }

    // MARK: - Manual email

    @ViewBuilder
    private var emailForm: some View {
        VStack(spacing: SleepSpacing.lg) {
            VStack(spacing: SleepSpacing.md) {
                TextField("Email", text: $email)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .keyboardType(.emailAddress)
                    // See the password field below: paired with a non-.email
                    // content type here too, since iOS pairs the preceding
                    // field as "username" when deciding to offer the Save
                    // Password prompt.
                    .textContentType(AppEnvironment.isTesting ? .oneTimeCode : .emailAddress)
                    .submitLabel(.next)
                    .font(SleepFont.body(17))
                    .foregroundStyle(SleepColor.ink)
                    .tint(SleepColor.amber)
                    .padding(.vertical, SleepSpacing.md)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(SleepColor.hairline).frame(height: 1)
                    }
                    .focused($focusedField, equals: .email)
                    .onSubmit { focusedField = .password }
                    .accessibilityLabel("Email")

                SecureField("Password", text: $password)
                    .submitLabel(.go)
                    // In UI tests, a real password field triggers iOS's
                    // native "Save Password?" AutoFill sheet, which is a
                    // separate-process system overlay that can't be
                    // reliably dismissed from XCUITest and covers the app.
                    // `.oneTimeCode` opts out of that prompt without
                    // affecting the real content type users see.
                    .textContentType(AppEnvironment.isTesting ? .oneTimeCode : (intent == .signIn ? .password : .newPassword))
                    .font(SleepFont.body(17))
                    .foregroundStyle(SleepColor.ink)
                    .tint(SleepColor.amber)
                    .padding(.vertical, SleepSpacing.md)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(SleepColor.hairline).frame(height: 1)
                    }
                    .focused($focusedField, equals: .password)
                    .onSubmit(submitEmailForm)
                    .accessibilityLabel("Password")
            }

            LiquidPrimaryButton(title: emailActionTitle, systemImage: "arrow.right") {
                submitEmailForm()
            }
            .accessibilityIdentifier("authSubmit")
            .disabled(store.isAuthenticating || !isEmailFormValid)

            if store.isAuthenticating {
                ProgressView().tint(SleepColor.amber)
            }

            Button("Back") {
                Keyboard.dismiss()
                store.authErrorMessage = nil
                withAnimation(.easeInOut(duration: 0.22)) { showEmailForm = false }
            }
            .font(SleepFont.body(15))
            .foregroundStyle(SleepColor.muted)
            .frame(height: 44)
        }
    }

    private var isEmailFormValid: Bool {
        email.contains("@") && email.contains(".") && password.count >= 6
    }

    private func submitEmailForm() {
        guard isEmailFormValid else { return }
        Keyboard.dismiss()
        Haptics.soft()
        let email = self.email
        let password = self.password
        switch intent {
        case .signUp:
            Task { await store.signUpEmail(email: email, password: password) }
        case .signIn:
            Task { await store.signInEmail(email: email, password: password) }
        }
    }

    private func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8),
                  let nonce = appleNonce
            else { return }
            store.authErrorMessage = nil
            Task { await store.signInWithApple(idToken: idToken, nonce: nonce) }
        case .failure(let error):
            let nsError = error as NSError
            // User cancelling the sheet isn't an error worth surfacing.
            guard nsError.code != ASAuthorizationError.canceled.rawValue else { return }
            store.authErrorMessage = AuthError.unknown(error.localizedDescription).message
        }
    }
}
