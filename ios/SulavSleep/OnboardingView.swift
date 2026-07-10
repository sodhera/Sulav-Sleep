import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// The pre-app gate for anyone without a local profile. Two paths, per the
// product brief: "Get started" runs the sign-up questionnaire (the investment
// steps) and only then asks for an account; "I already have an account" goes
// straight to sign-in, followed by a quick setup so the schedule still gets
// captured on a fresh device.

struct OnboardingGateView: View {
    @Bindable var store: SleepStore

    @State private var route: Route
    /// Bumped to force a fresh `OnboardingQuestionsView` when a sign-up run
    /// resolves to an existing account with no local profile yet — the new
    /// instance is created with `includesAccount == false` since `store` is
    /// already authenticated by then, i.e. the same quick-setup shown after
    /// signing in from the welcome screen. See `onExistingAccountNeedsSetup`.
    @State private var questionsInstanceID = UUID()

    private enum Route: Equatable {
        case welcome
        case questions
        case signIn
    }

    init(store: SleepStore) {
        self.store = store
        // A signed-in user without a profile (fresh device) skips straight to
        // the quick-setup questions — no welcome, no second auth.
        _route = State(initialValue: store.isAuthenticated ? .questions : .welcome)
    }

    var body: some View {
        ZStack {
            switch route {
            case .welcome:
                WelcomeStep(
                    onGetStarted: { setRoute(.questions) },
                    onSignIn: {
                        store.authErrorMessage = nil
                        setRoute(.signIn)
                    }
                )
                .transition(.opacity)
            case .questions:
                OnboardingQuestionsView(
                    store: store,
                    onBack: store.isAuthenticated ? nil : { setRoute(.welcome) }
                ) { name, bedtime, wakeTime, struggles in
                    store.completeOnboarding(
                        name: name, bedtime: bedtime, wakeTime: wakeTime,
                        connectHealth: false, struggles: struggles
                    )
                } onExistingAccountNeedsSetup: {
                    questionsInstanceID = UUID()
                }
                .id(questionsInstanceID)
                .transition(.opacity)
            case .signIn:
                AuthView(store: store, intent: .signIn, onBack: {
                    store.authErrorMessage = nil
                    setRoute(.welcome)
                })
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.28), value: route)
        // Sign-in succeeded but there's no profile on this device yet (no
        // cloud copy to restore either): run the quick setup before entering
        // the app. When the sign-in *did* restore a cloud profile, RootView
        // swaps to Main on its own — routing to the questions here too would
        // flash them during the crossfade.
        .onChange(of: store.isAuthenticated) { _, authenticated in
            if authenticated && route == .signIn && store.profile == nil {
                setRoute(.questions)
            }
        }
    }

    private func setRoute(_ next: Route) {
        // Warm the keyboard only while heading to the questionnaire, whose
        // name step autofocuses — so the first keyboard appears instantly
        // without a phantom flash on the welcome or account screens.
        if next == .questions { Keyboard.prewarm() }
        withAnimation(.easeInOut(duration: 0.28)) { route = next }
    }
}

// MARK: - Swipe back

/// Left-edge swipe → back, mirroring the glass chevron across the onboarding
/// and auth flows. These screens are custom ZStack transitions, not a
/// NavigationStack, so the system's interactive pop gesture doesn't exist and
/// the edge swipe is supplied by hand. It is a *trigger*, not a tracked pop:
/// releasing past the threshold runs the same ~280ms slide the chevron runs.
/// Call sites fire `Haptics.soft()` when they actually navigate — a swipe is
/// a non-button cue, so it never gets the button knock.
extension View {
    func swipeBack(_ action: @escaping () -> Void) -> some View {
        self
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 24)
                    .onEnded { value in
                        guard value.startLocation.x <= 44,
                              value.translation.width > 70,
                              abs(value.translation.height) < abs(value.translation.width)
                        else { return }
                        action()
                    }
            )
    }
}

// MARK: - Welcome

private struct WelcomeStep: View {
    let onGetStarted: () -> Void
    let onSignIn: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: SleepSpacing.lg) {
                Text("Wind down nightly")
                    .sectionLabel()
                Text("SleepBlock")
                    .font(SleepFont.hero(40))
                    .foregroundStyle(SleepColor.ink)
                Text("Set a bedtime. Quiet the phone. Sleep.")
                    .font(SleepFont.body(16))
                    .foregroundStyle(SleepColor.dim)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .frame(maxWidth: 300)
            }
            .padding(.horizontal, SleepSpacing.xxl)

            Spacer()

            VStack(spacing: SleepSpacing.md) {
                LiquidPrimaryButton(title: "Get started") {
                    onGetStarted()
                }
                Button("I already have an account") {
                    Haptics.heavy()
                    onSignIn()
                }
                .font(SleepFont.body(15))
                .foregroundStyle(SleepColor.dim)
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .padding(.horizontal, SleepSpacing.xxl)
            .padding(.bottom, SleepSpacing.xxl)
        }
        .safeAreaPadding(.top)
        .safeAreaPadding(.bottom)
    }
}

// MARK: - Questionnaire

/// The sign-up flow: who you are, what's in the way, your sleep window, and —
/// as the final step — creating the account that saves it all. The account step
/// is part of this flow (same progress bar and back button) and is only present
/// when the user is not already signed in; the profile is committed via `onDone`
/// only once that last step's auth succeeds. When the user arrives already
/// authenticated (post-sign-in quick setup), the account step is dropped and
/// the wake-time question becomes the final step. Apple Health is not asked here
/// — it's offered later, on Profile (see `HealthConnectCard`).
struct OnboardingQuestionsView: View {
    let store: SleepStore
    /// Back action from the first step (to the welcome screen), or `nil` when
    /// there is nowhere to go back to (post-sign-in quick setup).
    var onBack: (() -> Void)?
    let onDone: (String, Int, Int, [String]) -> Void
    /// The account step's sign-up call matched an existing account (Apple/
    /// Google reusing an already-registered identity) instead of creating a
    /// new one. The just-answered questions belong to whoever originally
    /// signed up, not this run, so they're discarded rather than passed to
    /// `onDone`. Called only when there's no local profile yet to fall back
    /// on (fresh device/reinstall) — `RootView` handles the case where a
    /// profile already exists on its own once `isAuthenticated` flips.
    var onExistingAccountNeedsSetup: () -> Void = {}

    @State private var step: Step = .name
    @State private var movingForward = true
    @State private var name = ""
    @State private var struggles: Set<SleepStruggle> = []
    @State private var bedtime = 22 * 60 + 30
    @State private var wakeTime = 6 * 60 + 30
    /// Whether this run ends on the account step. Captured once so it does not
    /// flip mid-flow when auth flips `isAuthenticated`.
    @State private var includesAccount: Bool

    init(
        store: SleepStore,
        onBack: (() -> Void)? = nil,
        onDone: @escaping (String, Int, Int, [String]) -> Void,
        onExistingAccountNeedsSetup: @escaping () -> Void = {}
    ) {
        self.store = store
        self.onBack = onBack
        self.onDone = onDone
        self.onExistingAccountNeedsSetup = onExistingAccountNeedsSetup
        _includesAccount = State(initialValue: !store.isAuthenticated)
    }

    private enum Step {
        case name, struggles, bedtime, wake, account
    }

    private var steps: [Step] {
        var result: [Step] = [.name, .struggles, .bedtime, .wake]
        if includesAccount { result.append(.account) }
        return result
    }

    private var currentIndex: Int { steps.firstIndex(of: step) ?? 0 }

    /// The last question step (i.e. not the account step). Its primary action
    /// commits onboarding rather than advancing — only reachable on the
    /// post-sign-in quick setup, where there is no account step.
    private var isTerminalQuestion: Bool {
        step != .account && currentIndex == steps.count - 1
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, SleepSpacing.xxl)
                .padding(.top, SleepSpacing.md)

            if step == .account {
                // The account step owns its full vertical layout (title +
                // provider buttons), so it isn't wrapped in the question
                // Spacer/Next-button scaffold.
                AuthMethodsView(store: store, intent: .signUp, onSwipeBack: { goBack() })
                    .transition(.opacity)
            } else {
                Spacer()

                currentStep
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, SleepSpacing.xxl)
                    .transition(stepTransition)
                    .id(step)

                Spacer()

                actions
                    .padding(.horizontal, SleepSpacing.xxl)
                    .padding(.bottom, SleepSpacing.xxl)
            }
        }
        .safeAreaPadding(.top)
        .safeAreaPadding(.bottom)
        .animation(.easeInOut(duration: 0.28), value: step)
        // The account step handles its own swipe inside AuthMethodsView
        // (it may need to unwind the email form first), so this outer
        // gesture stands down there to avoid double navigation.
        .swipeBack {
            guard step != .account, canGoBack else { return }
            Haptics.soft()
            goBack()
        }
        // The account step's auth succeeded. A brand-new account commits the
        // just-answered profile as before. An existing account (Apple/Google
        // silently matching an already-registered identity) discards these
        // answers instead — see `onExistingAccountNeedsSetup`.
        .onChange(of: store.isAuthenticated) { _, authenticated in
            guard authenticated, step == .account else { return }
            if store.lastSignInWasNewAccount {
                finish()
            } else {
                Keyboard.dismiss()
                if store.profile == nil {
                    onExistingAccountNeedsSetup()
                }
            }
        }
    }

    // MARK: Header — back chevron + thin progress bar

    private var header: some View {
        HStack(spacing: SleepSpacing.lg) {
            GlassBackButton {
                goBack()
            }
            .opacity(canGoBack ? 1 : 0)
            .disabled(!canGoBack)

            ProgressBar(fraction: progress)

            // Mirror the chevron itself (hidden) so the bar stays centered
            // whatever size the system draws the glass button at.
            GlassBackButton {}
                .hidden()
                .accessibilityHidden(true)
        }
        .animation(.easeInOut(duration: 0.28), value: canGoBack)
    }

    private var canGoBack: Bool { currentIndex > 0 || onBack != nil }

    private var progress: Double {
        Double(currentIndex + 1) / Double(steps.count)
    }

    private var stepTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: movingForward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: movingForward ? .leading : .trailing).combined(with: .opacity)
        )
    }

    // MARK: Steps

    @ViewBuilder
    private var currentStep: some View {
        switch step {
        case .name:
            QuestionLayout(kicker: "About you", title: "What should we call you?") {
                NameField(name: $name, onSubmit: advance)
            }
        case .struggles:
            QuestionLayout(
                kicker: "Your sleep",
                title: "What gets in the way of your sleep?",
                subtitle: "Choose any that apply."
            ) {
                // One glass set: the sibling capsules share a container so
                // iOS 26 blends their glass together as Apple intends.
                LiquidGlassContainer(spacing: SleepSpacing.md) {
                    VStack(spacing: SleepSpacing.md) {
                        ForEach(SleepStruggle.allCases) { struggle in
                            StruggleRow(
                                struggle: struggle,
                                isSelected: struggles.contains(struggle)
                            ) {
                                Haptics.heavy()
                                if struggles.contains(struggle) {
                                    struggles.remove(struggle)
                                } else {
                                    struggles.insert(struggle)
                                }
                            }
                        }
                    }
                }
            }
        case .bedtime:
            QuestionLayout(kicker: "Your schedule", title: "When do you usually go to bed?") {
                TimeAdjuster(minutes: $bedtime)
            }
        case .wake:
            QuestionLayout(
                kicker: "Your schedule",
                title: "And when do you wake up?",
                subtitle: "That's a \(SleepFormatting.duration(windowMinutes)) sleep window."
            ) {
                TimeAdjuster(minutes: $wakeTime)
            }
        case .account:
            // Rendered by AuthMethodsView in the body, outside this scaffold.
            EmptyView()
        }
    }

    private var windowMinutes: Int {
        SleepMath.windowMinutes(bedtime: bedtime, wakeTime: wakeTime)
    }

    // MARK: Actions

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: SleepSpacing.md) {
            if isTerminalQuestion {
                // Quick-setup path (already signed in): the wake step is last,
                // so its action commits onboarding instead of advancing.
                LiquidPrimaryButton(title: "Finish", systemImage: "checkmark") {
                    finish()
                }
            } else {
                LiquidPrimaryButton(title: "Next") {
                    advance()
                }
                .disabled(!isStepValid)
                .opacity(isStepValid ? 1 : 0.45)
            }
        }
    }

    private var isStepValid: Bool {
        switch step {
        case .name: !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default: true
        }
    }

    // No haptic here: the Next button (`LiquidPrimaryButton`) already knocks
    // on tap, and this also runs from the name field's return key.
    private func advance() {
        guard isStepValid else { return }
        let nextIndex = currentIndex + 1
        guard nextIndex < steps.count else { return }
        let next = steps[nextIndex]
        if step == .name {
            // Let the keyboard start dismissing before the slide so the two
            // animations don't fight.
            Keyboard.dismiss()
            Task { @MainActor in
                await Task.yield()
                setStep(next, forward: true)
            }
            return
        }
        setStep(next, forward: true)
    }

    // No haptic here: `GlassBackButton` already knocks on tap.
    private func goBack() {
        let previousIndex = currentIndex - 1
        if previousIndex >= 0 {
            Keyboard.dismiss()
            setStep(steps[previousIndex], forward: false)
        } else {
            onBack?()
        }
    }

    private func finish() {
        Keyboard.dismiss()
        Haptics.success()
        onDone(name, bedtime, wakeTime, struggles.map(\.rawValue))
    }

    private func setStep(_ next: Step, forward: Bool) {
        movingForward = forward
        withAnimation(.easeInOut(duration: 0.28)) { step = next }
    }
}

// MARK: - Shared question chrome

/// Editorial, left-aligned question layout: small-caps kicker, large title,
/// optional supporting line, then the control.
private struct QuestionLayout<Content: View>: View {
    let kicker: String
    let title: String
    var subtitle: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: SleepSpacing.lg) {
            VStack(alignment: .leading, spacing: SleepSpacing.md) {
                Text(kicker).sectionLabel()
                Text(title)
                    .font(SleepFont.title(28))
                    .foregroundStyle(SleepColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(subtitle)
                        .font(SleepFont.body(15))
                        .foregroundStyle(SleepColor.dim)
                        .lineSpacing(4)
                        .contentTransition(.numericText())
                }
            }

            content
                .padding(.top, SleepSpacing.sm)
        }
    }
}

/// Round glass chevron used across onboarding and auth headers. Slightly
/// smaller than the Profile/Settings icon buttons (44pt vs 56pt) so it stays
/// a quiet wayfinding control, but no smaller — undersized glass circles
/// read as toy chrome next to other iOS 26 apps. The questionnaire keeps its
/// progress bar centered by mirroring this button with a hidden twin, so
/// there is no width constant to keep in sync.
struct GlassBackButton: View {
    var action: () -> Void

    var body: some View {
        GlassIconButton(systemImage: "chevron.left", size: 44, iconSize: 16, tint: SleepColor.ink, action: action)
            .accessibilityLabel("Back")
    }
}

private struct ProgressBar: View {
    var fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(SleepColor.hairline)
                Capsule()
                    .fill(LinearGradient(
                        colors: [SleepColor.gold, SleepColor.amber],
                        startPoint: .leading, endPoint: .trailing
                    ))
                    .frame(width: max(6, proxy.size.width * fraction))
                    .animation(.easeInOut(duration: 0.32), value: fraction)
            }
        }
        .frame(height: 3)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int(fraction * 100)) percent")
    }
}

// MARK: - Step controls

private struct NameField: View {
    @Binding var name: String
    var onSubmit: () -> Void

    @FocusState private var isFocused: Bool
    @State private var focusTask: Task<Void, Never>?

    var body: some View {
        TextField(
            "Your name", text: $name,
            prompt: Text("Your name").foregroundStyle(SleepColor.quiet)
        )
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled(true)
            .submitLabel(.next)
            .font(SleepFont.title(24))
            .foregroundStyle(SleepColor.ink)
            .tint(SleepColor.amber)
            .padding(.vertical, SleepSpacing.md)
            // `faint` when idle, not `hairline` — a 6% rule vanishes into the
            // scene and the field reads as bare text.
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(isFocused ? SleepColor.amber.opacity(0.5) : SleepColor.faint)
                    .frame(height: 1)
            }
            .focused($isFocused)
            .onSubmit(onSubmit)
            .accessibilityLabel("Your name")
            .onAppear {
                focusTask?.cancel()
                focusTask = Task { @MainActor in
                    // Wait out the step slide so the keyboard doesn't stutter it.
                    try? await Task.sleep(nanoseconds: 320_000_000)
                    guard !Task.isCancelled else { return }
                    isFocused = true
                }
            }
            .onDisappear {
                focusTask?.cancel()
                isFocused = false
            }
    }
}

private struct StruggleRow: View {
    let struggle: SleepStruggle
    let isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: SleepSpacing.md) {
                Image(systemName: struggle.systemImage)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(isSelected ? SleepColor.amber : SleepColor.muted)
                    .frame(width: 24)
                Text(struggle.title)
                    .font(SleepFont.label(16))
                    .foregroundStyle(SleepColor.ink)
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(isSelected ? SleepColor.amber : SleepColor.faint)
            }
            .padding(.horizontal, SleepSpacing.xl)
            .frame(maxWidth: .infinity, minHeight: 54)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        // The glass owns its fill and edge; the row only adds an amber
        // stroke as the *selection* affordance. (Painting a manual capsule
        // fill + border on top of real glass muted it into a flat panel.)
        .liquidGlass(
            cornerRadius: SleepRadius.pill,
            tint: isSelected ? SleepColor.glassWarm : SleepColor.glassFill,
            interactive: true
        )
        .overlay {
            if isSelected {
                Capsule(style: .continuous)
                    .stroke(SleepColor.amber.opacity(0.45), lineWidth: 1)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct TimeAdjuster: View {
    @Binding var minutes: Int

    /// Reference date used to anchor the DatePicker. Only the time component matters.
    private static let calendar = Calendar.current
    private static let referenceDate: Date = {
        calendar.startOfDay(for: Date())
    }()

    var body: some View {
        DatePicker(
            "Time",
            selection: dateBinding,
            displayedComponents: .hourAndMinute
        )
        .datePickerStyle(.wheel)
        .labelsHidden()
        .tint(SleepColor.amber)
        .frame(maxWidth: .infinity)
        .frame(height: 160)
        .accessibilityLabel("Select time")
    }

    /// Two-way binding that converts between total minutes-from-midnight (Int)
    /// and a Date for the native DatePicker.
    private var dateBinding: Binding<Date> {
        Binding(
            get: {
                let normalized = ((minutes % 1_440) + 1_440) % 1_440
                let hour = normalized / 60
                let minute = normalized % 60
                return Self.calendar.date(
                    bySettingHour: hour, minute: minute, second: 0,
                    of: Self.referenceDate
                ) ?? Self.referenceDate
            },
            set: { newDate in
                let components = Self.calendar.dateComponents([.hour, .minute], from: newDate)
                minutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
            }
        )
    }
}

enum Keyboard {
    #if canImport(UIKit)
    private static var warmupField: UITextField?
    #endif

    static func dismiss() {
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }

    /// Force-load the keyboard framework into memory so the first real
    /// keyboard appearance is instant. Call once on the intro screen.
    static func prewarm(duration: TimeInterval = 0.55) {
        #if canImport(UIKit)
        DispatchQueue.main.async {
            guard warmupField == nil else { return }
            guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
                let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first
            else { return }

            let field = UITextField(frame: CGRect(x: -1, y: -1, width: 1, height: 1))
            field.alpha = 0.01
            field.autocorrectionType = .no
            field.spellCheckingType = .no
            field.smartQuotesType = .no
            field.smartDashesType = .no
            field.inputAssistantItem.leadingBarButtonGroups = []
            field.inputAssistantItem.trailingBarButtonGroups = []
            field.isAccessibilityElement = false
            window.addSubview(field)
            warmupField = field
            field.becomeFirstResponder()

            // Let the keyboard stack finish its async cold path before resigning.
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                field.resignFirstResponder()
                field.removeFromSuperview()
                if warmupField === field {
                    warmupField = nil
                }
            }
        }
        #endif
    }
}
