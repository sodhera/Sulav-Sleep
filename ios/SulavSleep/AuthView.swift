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
    @State private var loadingProvider: OAuthProvider? = nil
    @FocusState private var focusedField: Field?

    private enum Field { case email, password }
    private enum OAuthProvider { case apple, google }

    private var title: String {
        intent == .signIn ? "Welcome back" : "Save your sleep plan"
    }

    private var subtitle: String {
        intent == .signIn
            ? "Sign in to pick up where you left off."
            : "Create a free account so your plan and your nights follow you across devices."
    }

    /// Names the action on each provider button: "Sign up with …" on the
    /// sign-up flow, "Sign in with …" on the returning-user path.
    private var providerActionPrefix: String {
        intent == .signIn ? "Sign in with" : "Sign up with"
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
                // Amber for guidance (e.g. "check your email"), red for failures.
                Text(message)
                    .font(SleepFont.body(14))
                    .foregroundStyle(store.authMessageIsNotice ? SleepColor.amber : SleepColor.danger)
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
        // A cohesive OAuth stack: all three buttons share the same height,
        // font, and text format. Each button tracks its own loading state so
        // a spinner only appears on the one that was tapped.
        VStack(spacing: SleepSpacing.md) {
            AuthButton(title: "\(providerActionPrefix) Apple", style: .light, isLoading: loadingProvider == .apple) {
                Image(systemName: "apple.logo")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(SleepColor.background)
            } action: {
                // `loadingProvider` also guards the window while the system
                // sheet is up but `isAuthenticating` isn't set yet — a second
                // tap there would regenerate the nonce out from under the
                // in-flight request.
                guard !store.isAuthenticating, loadingProvider == nil else { return }
                Haptics.soft()
                store.authErrorMessage = nil
                loadingProvider = .apple
                let nonce = AppleSignInNonce.randomNonce()
                appleNonce = nonce
                triggerAppleSignIn(nonce: nonce)
            }
            .disabled(store.isAuthenticating)

            AuthButton(title: "\(providerActionPrefix) Google", style: .light, isLoading: loadingProvider == .google) {
                Image("GoogleLogo")
                    .resizable()
                    .renderingMode(.original)
                    .scaledToFit()
            } action: {
                guard !store.isAuthenticating, loadingProvider == nil else { return }
                Haptics.soft()
                store.authErrorMessage = nil
                loadingProvider = .google
                Task {
                    await store.signInWithGoogle()
                    loadingProvider = nil
                }
            }
            .disabled(store.isAuthenticating)

            AuthButton(title: "\(providerActionPrefix) email", style: .glass, isLoading: false) {
                Image(systemName: "envelope.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(SleepColor.ink)
            } action: {
                Haptics.soft()
                store.authErrorMessage = nil
                withAnimation(.easeInOut(duration: 0.22)) { showEmailForm = true }
            }
            .disabled(store.isAuthenticating)
        }
        .onChange(of: store.isAuthenticating) { _, isAuthenticating in
            if !isAuthenticating { loadingProvider = nil }
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
                    .textContentType(.emailAddress)
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
                    .textContentType(intent == .signIn ? .password : .newPassword)
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

            LiquidPrimaryButton(title: emailActionTitle, isLoading: store.isAuthenticating) {
                submitEmailForm()
            }
            .accessibilityIdentifier("authSubmit")
            .disabled(store.isAuthenticating || !isEmailFormValid)

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
            else {
                // A malformed credential must still release the button —
                // returning silently here left the spinner stuck forever.
                loadingProvider = nil
                store.authErrorMessage = AuthError.unknown("Apple sign-in didn't return a usable credential. Try again.").message
                return
            }
            store.authErrorMessage = nil
            Task { await store.signInWithApple(idToken: idToken, nonce: nonce) }
        case .failure(let error):
            let nsError = error as NSError
            // User cancelling the sheet isn't an error worth surfacing.
            guard nsError.code != ASAuthorizationError.canceled.rawValue else {
                loadingProvider = nil
                return
            }
            loadingProvider = nil
            store.authErrorMessage = AuthError.unknown(error.localizedDescription).message
        }
    }

    /// Programmatically presents the Sign in with Apple sheet without the
    /// native `SignInWithAppleButton` widget (so we can use our own styled button).
    private func triggerAppleSignIn(nonce: String) {
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.email, .fullName]
        request.nonce = AppleSignInNonce.sha256(nonce)
        // The coordinator retains itself and the controller until the delegate
        // fires, so neither is deallocated mid-flow (which would leave the
        // button spinning forever with no callback). See AppleSignInCoordinator.
        let coordinator = AppleSignInCoordinator { [self] result in
            handleAppleCompletion(result)
        }
        coordinator.start(request: request)
    }
}

// MARK: - Provider buttons

/// Shared metrics for the sign-in provider stack. All three provider buttons
/// (Apple, Google, email) share these values so they read as one consistent set.
private enum AuthButtonMetrics {
    static let height: CGFloat = 58
    static let font: Font = .system(size: 20, weight: .medium)
    static let iconSize: CGFloat = 22
}

/// One button in the sign-in provider stack (Apple, Google, email).
/// `.light` is a white brand pill; `.glass` is the quiet, translucent email path.
/// Pass `isLoading: true` to replace the icon+label with a spinner.
private struct AuthButton<Icon: View>: View {
    enum Style { case light, glass }

    let title: String
    let style: Style
    var isLoading: Bool = false
    @ViewBuilder var icon: () -> Icon
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if style == .light {
                labelContent
                    .background {
                        Capsule(style: .continuous).fill(SleepColor.white)
                    }
            } else {
                // Real Liquid Glass for the quiet email path — not a
                // hand-painted translucent capsule.
                labelContent
                    .liquidGlass(cornerRadius: SleepRadius.pill, interactive: true)
            }
        }
        .buttonStyle(AuthButtonPressStyle())
    }

    private var labelContent: some View {
        ZStack {
            HStack(spacing: SleepSpacing.sm) {
                icon()
                    .frame(width: AuthButtonMetrics.iconSize, height: AuthButtonMetrics.iconSize)
                Text(title).font(AuthButtonMetrics.font)
            }
            .opacity(isLoading ? 0 : 1)

            if isLoading {
                ProgressView()
                    .tint(style == .light ? SleepColor.background : SleepColor.ink)
            }
        }
        .frame(maxWidth: .infinity, minHeight: AuthButtonMetrics.height)
        .foregroundStyle(style == .light ? SleepColor.background : SleepColor.ink)
    }
}

/// Subtle press feedback matching the app's other buttons.
private struct AuthButtonPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.94 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

// MARK: - Apple sign-in coordinator

/// Bridges `ASAuthorizationControllerDelegate` so we can present the Apple
/// sign-in sheet programmatically from a SwiftUI value type (no native button).
///
/// `ASAuthorizationController` does not reliably keep itself alive between
/// `performRequests()` and its delegate callback, so the coordinator holds a
/// strong reference to both the controller and *itself* for the duration of the
/// flow. Without this, a fast path (e.g. an already-authorized Apple ID that
/// skips the consent sheet) can deallocate everything before the callback runs,
/// leaving the sign-in button spinning forever. Both references are released the
/// moment the delegate reports success or failure.
private final class AppleSignInCoordinator: NSObject,
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding {

    private let completion: (Result<ASAuthorization, Error>) -> Void
    private var controller: ASAuthorizationController?
    private var selfRetain: AppleSignInCoordinator?

    init(completion: @escaping (Result<ASAuthorization, Error>) -> Void) {
        self.completion = completion
    }

    /// Presents the Apple sheet, keeping the controller and this coordinator
    /// alive until the delegate fires.
    func start(request: ASAuthorizationAppleIDRequest) {
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        self.controller = controller
        self.selfRetain = self
        controller.performRequests()
    }

    /// Delivers the result once and drops the strong references so nothing leaks.
    private func finish(_ result: Result<ASAuthorization, Error>) {
        completion(result)
        controller = nil
        selfRetain = nil
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        finish(.success(authorization))
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        finish(.failure(error))
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
