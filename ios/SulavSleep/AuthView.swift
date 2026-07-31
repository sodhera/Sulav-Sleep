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
                        Keyboard.dismiss()
                        onBack()
                    }
                    Spacer()
                }
                .padding(.horizontal, SleepSpacing.xxl)
                .padding(.top, SleepSpacing.md)
            }

            // The standalone screen carries the brand mark above its title;
            // the sign-up flow's embedding doesn't — there the mark already
            // rides the questionnaire header's top-right corner.
            AuthMethodsView(store: store, intent: intent, showsBrandMark: true, onSwipeBack: swipeBackAction)
        }
        .safeAreaPadding(.top)
        .safeAreaPadding(.bottom)
    }

    /// The edge swipe mirrors the chevron: dismiss the keyboard, back to welcome.
    private var swipeBackAction: (() -> Void)? {
        guard let onBack else { return nil }
        return {
            Keyboard.dismiss()
            onBack()
        }
    }
}

/// The account methods themselves: native Sign in with Apple, Google via a web
/// OAuth sheet, and manual email/password. Single-purpose — the mode is fixed
/// by `intent`, with no sign-up/sign-in toggle. Rendered standalone by
/// `AuthView` and embedded as the final step of the sign-up questionnaire.
struct AuthMethodsView: View {
    @Bindable var store: SleepStore
    let intent: AuthIntent
    /// Whether the brand mark (sleeping sloth + rising z's) sits above the
    /// title. On for the standalone sign-in screen; off when embedded as the
    /// sign-up flow's account step, where the questionnaire header already
    /// carries the mark in its top-right corner.
    var showsBrandMark = false
    /// Where the left-edge swipe leads when there is nothing internal to
    /// unwind (the provider stack is showing) — the parent decides: back to
    /// welcome on the sign-in path, back to the wake question in the sign-up
    /// flow. With the email form open, the swipe unwinds to the providers
    /// first. `nil` means the swipe has nowhere to go from the providers.
    var onSwipeBack: (() -> Void)? = nil

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

            VStack(spacing: SleepSpacing.lg) {
                if showsBrandMark {
                    // Hero size and block shape shared with the welcome
                    // screen (`BrandHeroGeometry`): the gate crossfades the
                    // two screens, so any difference in mark size or block
                    // geometry reads as the logo shrinking or twitching.
                    SlothBrandMark(width: SlothBrandMark.heroWidth, zScale: SlothBrandMark.heroZScale)
                }
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
                // The fixed text band applies only on the brand-hero screen;
                // the sign-up account step keeps its natural height.
                .frame(height: showsBrandMark ? BrandHeroGeometry.textBandHeight : nil, alignment: .top)
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
        .swipeBack { handleSwipeBack() }
    }

    private func handleSwipeBack() {
        if showEmailForm {
            Haptics.soft()
            closeEmailForm()
        } else if let onSwipeBack {
            Haptics.soft()
            onSwipeBack()
        }
    }

    private func closeEmailForm() {
        Keyboard.dismiss()
        store.authErrorMessage = nil
        withAnimation(.easeInOut(duration: 0.22)) { showEmailForm = false }
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
                Haptics.heavy()
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
                Haptics.heavy()
                store.authErrorMessage = nil
                loadingProvider = .google
                Task {
                    await store.signInWithGoogle(intent: intent)
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
                Haptics.heavy()
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
            // Glass field surfaces, not bare hairline underlines: the form
            // sits over the busiest band of the skyline, where an underlined
            // field all but disappears. The glass supplies the field's own
            // stage (containers are for controls), and the amber ring is the
            // focus affordance — a stroke that carries meaning, per the
            // glass rules.
            LiquidGlassContainer(spacing: SleepSpacing.md) {
                VStack(spacing: SleepSpacing.md) {
                    TextField(
                        "Email", text: $email,
                        prompt: Text("Email").foregroundStyle(SleepColor.quiet)
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .submitLabel(.next)
                    .modifier(AuthFieldChrome(isFocused: focusedField == .email))
                    .focused($focusedField, equals: .email)
                    .onSubmit { focusedField = .password }
                    .accessibilityLabel("Email")

                    SecureField(
                        "Password", text: $password,
                        prompt: Text("Password").foregroundStyle(SleepColor.quiet)
                    )
                    .submitLabel(.go)
                    .textContentType(intent == .signIn ? .password : .newPassword)
                    .modifier(AuthFieldChrome(isFocused: focusedField == .password))
                    .focused($focusedField, equals: .password)
                    .onSubmit(submitEmailForm)
                    .accessibilityLabel("Password")
                }
            }

            LiquidPrimaryButton(title: emailActionTitle, isLoading: store.isAuthenticating) {
                submitEmailForm()
            }
            .accessibilityIdentifier("authSubmit")
            .disabled(store.isAuthenticating || !isEmailFormValid)

            Button("Back") {
                Haptics.heavy()
                closeEmailForm()
            }
            .font(SleepFont.body(15))
            .foregroundStyle(SleepColor.muted)
            .frame(height: 44)
        }
    }

    private var isEmailFormValid: Bool {
        email.contains("@") && email.contains(".") && password.count >= 6
    }

    // No haptic here: the submit button (`LiquidPrimaryButton`) already
    // knocks on tap, and this also runs from the keyboard's return key.
    private func submitEmailForm() {
        guard isEmailFormValid else { return }
        Keyboard.dismiss()
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
            Task { await store.signInWithApple(idToken: idToken, nonce: nonce, intent: intent) }
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

/// Shared chrome for the email form's two fields: ink text on an interactive
/// glass rounded rect, with the amber focus ring animating in as focus moves.
private struct AuthFieldChrome: ViewModifier {
    var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .font(SleepFont.body(17))
            .foregroundStyle(SleepColor.ink)
            .tint(SleepColor.amber)
            .padding(.horizontal, SleepSpacing.xl)
            .frame(minHeight: 54)
            .liquidGlass(cornerRadius: SleepRadius.md, interactive: true)
            .overlay {
                if isFocused {
                    RoundedRectangle(cornerRadius: SleepRadius.md, style: .continuous)
                        .stroke(SleepColor.amber.opacity(0.45), lineWidth: 1)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: isFocused)
    }
}

// MARK: - Existing account welcome

/// The answer to "Get started" when the Apple ID or Google account behind it
/// already had an account here.
///
/// Apple's and Google's Supabase grants are *find-or-create*: there is no way
/// to ask whether an identity is registered before signing the user in, so the
/// app cannot do what the email path does and refuse up front. By the time it
/// knows, the session exists and the user's real profile and nights have been
/// restored. What it can do — and what this screen is — is refuse to pretend
/// nothing happened: name what the app did, say what became of the answers
/// they just spent nine steps giving, and make them tap to continue.
///
/// Shape borrowed from `UpdateRequiredView`: hero mark, title, one paragraph,
/// one primary button, on the onboarding scene. A gate, not a question — there
/// is no second choice to offer, because signing out and back in would land in
/// exactly the same place.
struct ExistingAccountWelcomeView: View {
    let store: SleepStore

    /// What the user actually tapped, named the way they'd name it.
    private var providerNoun: String {
        switch store.account?.provider {
        case .google: "that Google account"
        case .email: "that email"
        case .apple, .none: "that Apple ID"
        }
    }

    /// Two honest endings. When the profile came back, the reassurance is
    /// true and worth stating plainly — the nights are the thing they'd worry
    /// about. When it didn't (an account that never finished onboarding, or a
    /// cloud read that failed), promising their plan is waiting would be a lie
    /// they'd catch three seconds later on the setup questions.
    private var message: String {
        if store.isOnboarded {
            "Signing up with \(providerNoun) found the account you already had, so we signed you in instead. Your plan and your nights are exactly where you left them — the answers you just gave weren't saved over them."
        } else {
            "Signing up with \(providerNoun) found the account you already had, so we signed you in instead. There's no saved plan on it, so we'll set your schedule up next."
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            SlothBrandMark(width: SlothBrandMark.heroWidth, zScale: SlothBrandMark.heroZScale)

            Text("You already have an account")
                .font(SleepFont.hero(28))
                .foregroundStyle(SleepColor.ink)
                .multilineTextAlignment(.center)
                .padding(.top, SleepSpacing.xxl)

            Text(message)
                .font(SleepFont.body(15))
                .foregroundStyle(SleepColor.dim)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, SleepSpacing.md)

            Spacer()

            LiquidPrimaryButton(title: store.isOnboarded ? "Continue to my account" : "Continue") {
                store.acknowledgeExistingAccount()
            }
            .padding(.bottom, SleepSpacing.huge)
        }
        .padding(.horizontal, SleepSpacing.xxl)
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
