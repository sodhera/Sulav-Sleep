import SwiftUI
import AuthenticationServices

/// How the auth screen is framed. `.signUp` closes the sign-up questionnaire
/// ("save the plan you just made"); `.signIn` is the returning-user path from
/// the welcome screen. Both reach the same Supabase providers — the email form
/// keeps a toggle so nobody gets stuck on the wrong side.
enum AuthIntent {
    case signUp
    case signIn
}

/// Account step: native Sign in with Apple, Google via a web OAuth sheet, and
/// manual email/password. Mirrors the questionnaire's layout, spacing, and
/// animation so the two screens read as one continuous flow.
struct AuthView: View {
    @Bindable var store: SleepStore
    /// Back to the welcome screen, when this screen was reached from it.
    var onBack: (() -> Void)?

    /// Live framing, seeded from the caller's intent. A footer link flips it
    /// so nobody is ever stuck on the wrong side (e.g. after signing out).
    @State private var framing: AuthIntent
    @State private var showEmailForm = false
    @State private var mode: EmailMode
    @State private var email = ""
    @State private var password = ""
    @State private var appleNonce: String?
    @FocusState private var focusedField: Field?

    init(store: SleepStore, intent: AuthIntent = .signUp, onBack: (() -> Void)? = nil) {
        self.store = store
        self.onBack = onBack
        _framing = State(initialValue: intent)
        _mode = State(initialValue: intent == .signIn ? .signIn : .signUp)
    }

    private enum EmailMode: String, CaseIterable, Identifiable {
        case signUp, signIn
        var id: String { rawValue }
        var title: String { self == .signUp ? "Sign up" : "Sign in" }
        var actionTitle: String { self == .signUp ? "Create account" : "Sign in" }
    }

    private enum Field { case email, password }

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

            Spacer()

            VStack(spacing: SleepSpacing.md) {
                Text(framing == .signIn ? "Welcome back" : "Save your sleep plan")
                    .font(SleepFont.hero(30))
                    .foregroundStyle(SleepColor.ink)
                Text(framing == .signIn
                     ? "Sign in to pick up where you left off."
                     : "Create a free account so your plan and your nights follow you across devices.")
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
        .safeAreaPadding(.top)
        .safeAreaPadding(.bottom)
        .animation(.easeInOut(duration: 0.22), value: showEmailForm)
    }

    // MARK: - Provider choice

    @ViewBuilder
    private var providerButtons: some View {
        VStack(spacing: SleepSpacing.md) {
            SignInWithAppleButton(framing == .signIn ? .signIn : .signUp) { request in
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

            Button {
                Haptics.soft()
                store.authErrorMessage = nil
                withAnimation(.easeInOut(duration: 0.22)) {
                    framing = framing == .signIn ? .signUp : .signIn
                    mode = framing == .signIn ? .signIn : .signUp
                }
            } label: {
                framingToggleLabel
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .accessibilityIdentifier("authFramingToggle")
            .disabled(store.isAuthenticating)
        }
    }

    private var framingToggleLabel: Text {
        if framing == .signIn {
            Text("New here? ")
                .font(SleepFont.body(15))
                .foregroundStyle(SleepColor.muted)
            + Text("Create an account")
                .font(SleepFont.label(15))
                .foregroundStyle(SleepColor.amber)
        } else {
            Text("Already have an account? ")
                .font(SleepFont.body(15))
                .foregroundStyle(SleepColor.muted)
            + Text("Sign in")
                .font(SleepFont.label(15))
                .foregroundStyle(SleepColor.amber)
        }
    }

    // MARK: - Manual email

    @ViewBuilder
    private var emailForm: some View {
        VStack(spacing: SleepSpacing.lg) {
            Picker("Mode", selection: $mode) {
                ForEach(EmailMode.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)

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
                    .textContentType(AppEnvironment.isTesting ? .oneTimeCode : .newPassword)
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

            LiquidPrimaryButton(title: mode.actionTitle, systemImage: "arrow.right") {
                submitEmailForm()
            }
            // Distinguishes the submit button from the "Sign in" segmented tab
            // for UI tests.
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
        switch mode {
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
