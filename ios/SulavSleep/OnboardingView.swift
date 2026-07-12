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
                ) { answers in
                    store.completeOnboarding(answers)
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
        // Load the input frameworks while the gate idles (flash-free), so
        // neither the Get-started prewarm nor a first field focus pays the
        // keyboard cold path at interaction time.
        .onAppear { Keyboard.warmFrameworks() }
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

// MARK: - Brand mark

/// The geometry contract between the two brand-hero screens (welcome and the
/// standalone "Welcome back"). The gate crossfades one into the other, so the
/// mark must land on *exactly* the same pixel on both — close is not enough;
/// a few points of drift reads as the logo twitching mid-fade. Both screens
/// therefore center the same-shaped block — mark, `lg` gap, a text band of
/// this fixed height — between a chevron-height header row (welcome renders
/// an invisible twin of sign-in's real one) and a bottom band of this fixed
/// height (the provider stack's natural size; welcome bottom-aligns its two
/// smaller controls inside the same band).
enum BrandHeroGeometry {
    /// Reserved height for the title + subtitle under the mark, top-aligned:
    /// fits welcome's 40pt hero and sign-in's 30pt title + subtitle alike.
    static let textBandHeight: CGFloat = 92
    /// The sign-in provider stack's natural height — 3 × 58pt buttons with
    /// 2 × `md` gaps. Welcome's bottom band matches it.
    static let bottomBandHeight: CGFloat = 198
}

/// The app icon as a living mark for the onboarding/auth screens: the
/// sleeping sloth (the home art's closed-eye frame, wearing the scene's
/// current light) with the icon's static gold ZZZ replaced by the sleep
/// screen's rising-z chain (`RisingZs`, SleepTheme.swift). Decorative only —
/// hidden from accessibility, never a tap target. Lives here rather than in
/// SleepTheme.swift because it needs `CityPhase` and the Home sloth art,
/// neither of which exists in the widget target that compiles the theme.
struct SlothBrandMark: View {
    /// One shared size for the *hero* placements (welcome, Welcome back):
    /// the two screens crossfade into each other at nearly the same spot,
    /// so differing sizes read as the logo shrinking mid-transition.
    static let heroWidth: CGFloat = 150
    static let heroZScale: CGFloat = 0.62

    /// Rendered width of the sloth figure (the art is 1200×720, so height
    /// is 0.6 × width); the z's ride above its head, unclipped.
    var width: CGFloat
    /// Scale of the rising z's. Deliberately *not* derived from `width`:
    /// small marks keep oversized z's — like the icon's ZZZ — so the
    /// animation stays legible at corner sizes.
    var zScale: CGFloat

    var body: some View {
        // Minute ticks keep the mark wearing the same light as the scene
        // behind it if a phase boundary passes while the screen is up.
        TimelineView(.everyMinute) { timeline in
            let phase = CityPhase.current(timeline.date)
            Image("HomeSloth\(phase.rawValue)Blink")
                .resizable()
                .scaledToFit()
                .frame(width: width)
                // The same warm halo that seats Home's sloth in the scene,
                // scaled to the mark.
                .background {
                    Ellipse()
                        .fill(SleepColor.amber.opacity(phase == .day ? 0.10 : 0.16))
                        .blur(radius: width * 0.144)
                        .padding(-width * 0.05)
                }
                .overlay(alignment: .topLeading) {
                    RisingZs(color: SleepColor.gold, scale: zScale)
                        .offset(x: width * 0.22, y: -width * 0.007)
                }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Welcome

private struct WelcomeStep: View {
    let onGetStarted: () -> Void
    let onSignIn: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Invisible twin of the sign-in screen's chevron header, so both
            // screens consume identical vertical structure and the brand
            // mark holds still through the gate's crossfade — see
            // `BrandHeroGeometry`.
            HStack {
                GlassBackButton {}
                    .hidden()
                Spacer()
            }
            .padding(.horizontal, SleepSpacing.xxl)
            .padding(.top, SleepSpacing.md)
            .accessibilityHidden(true)

            Spacer()

            VStack(spacing: SleepSpacing.lg) {
                // The brand mark above the wordmark: the icon's sleeping
                // sloth with its ZZZ animating.
                SlothBrandMark(width: SlothBrandMark.heroWidth, zScale: SlothBrandMark.heroZScale)
                VStack(spacing: SleepSpacing.md) {
                    Text("SleepBlock")
                        .font(SleepFont.hero(40))
                        .foregroundStyle(SleepColor.ink)
                    Text("Block apps and Log your sleep")
                        .font(SleepFont.body(16))
                        .foregroundStyle(SleepColor.dim)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .frame(maxWidth: 300)
                }
                .frame(height: BrandHeroGeometry.textBandHeight, alignment: .top)
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
            // Bottom-aligned inside the sign-in provider stack's footprint,
            // per the BrandHeroGeometry contract.
            .frame(height: BrandHeroGeometry.bottomBandHeight, alignment: .bottom)
            .padding(.horizontal, SleepSpacing.xxl)
            .padding(.bottom, SleepSpacing.xxl)
        }
        .safeAreaPadding(.top)
        .safeAreaPadding(.bottom)
        // No text input lives here, so keyboard frames must never move this
        // layout: without this, the flash-free warmup's registered frame (on
        // first entry) and the still-dismissing keyboard (backing out of the
        // name question) both lifted the content, which then visibly fell
        // back into place.
        .ignoresSafeArea(.keyboard)
    }
}

// MARK: - Questionnaire

/// The sign-up flow: who you are, what you want, what's in the way, how bad
/// it's gotten, your sleep window — then a **plan reveal** ("Building your
/// sleep plan…" resolving into a personalized summary) and, as the final
/// step, creating the account that saves it all. Each question deepens the
/// user's investment and sharpens the plan the paywall then unlocks; the
/// reveal is what makes the trial feel like unlocking something they built.
/// The account step is part of this flow (same progress bar and back button)
/// and is only present when the user is not already signed in; the profile is
/// committed via `onDone` only once that last step's auth succeeds. When the
/// user arrives already authenticated (post-sign-in quick setup), the account
/// step is dropped and the plan reveal becomes the final step. Apple Health
/// is not asked here — it's offered later, on Profile (see
/// `HealthConnectCard`).
struct OnboardingQuestionsView: View {
    let store: SleepStore
    /// Back action from the first step (to the welcome screen), or `nil` when
    /// there is nowhere to go back to (post-sign-in quick setup).
    var onBack: (() -> Void)?
    let onDone: (OnboardingAnswers) -> Void
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
    @State private var goal: SleepGoal?
    @State private var struggles: Set<SleepStruggle> = []
    @State private var timeSinks: Set<TimeSinkApp> = []
    @State private var phoneTime: LateNightPhoneTime?
    @State private var feeling: WakeFeeling?
    @State private var bedtime = 22 * 60 + 30
    @State private var wakeTime = 6 * 60 + 30
    /// Whether the plan step has finished its "Building…" beat and revealed
    /// the summary. Sticky on purpose: backing into the plan step from the
    /// account step shows the summary immediately — the build animation is a
    /// first-arrival moment, not a toll.
    @State private var planBuilt = false
    @State private var planBuildTask: Task<Void, Never>?
    /// Whether this run ends on the account step. Captured once so it does not
    /// flip mid-flow when auth flips `isAuthenticated`.
    @State private var includesAccount: Bool

    init(
        store: SleepStore,
        onBack: (() -> Void)? = nil,
        onDone: @escaping (OnboardingAnswers) -> Void,
        onExistingAccountNeedsSetup: @escaping () -> Void = {}
    ) {
        self.store = store
        self.onBack = onBack
        self.onDone = onDone
        self.onExistingAccountNeedsSetup = onExistingAccountNeedsSetup
        _includesAccount = State(initialValue: !store.isAuthenticated)
    }

    /// The investment arc: who you are → what you want → what's in the way →
    /// how bad it's gotten → your schedule → the plan built from all of it.
    private enum Step {
        case name, goal, struggles, timeSinks, phoneTime, feeling, bedtime, wake, plan, account
    }

    private var steps: [Step] {
        var result: [Step] = [.name, .goal, .struggles, .timeSinks, .phoneTime, .feeling, .bedtime, .wake, .plan]
        if includesAccount { result.append(.account) }
        return result
    }

    private var currentIndex: Int { steps.firstIndex(of: step) ?? 0 }

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
            // whatever size the system draws the glass button at — and let
            // the brand mark ride the mirrored slot, so the sloth keeps the
            // flow branded from the top-right corner without adding any
            // width of its own. Its z's drift up past the slot, unclipped.
            GlassBackButton {}
                .hidden()
                .accessibilityHidden(true)
                .overlay {
                    SlothBrandMark(width: 48, zScale: 0.5)
                }
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
        case .goal:
            QuestionLayout(
                kicker: "Your goal",
                title: "What do you want most?",
                subtitle: "Pick the one that matters tonight."
            ) {
                LiquidGlassContainer(spacing: SleepSpacing.md) {
                    VStack(spacing: SleepSpacing.md) {
                        ForEach(SleepGoal.allCases) { option in
                            OptionRow(
                                icon: option.systemImage,
                                title: option.title,
                                isSelected: goal == option
                            ) {
                                Haptics.heavy()
                                goal = option
                            }
                        }
                    }
                }
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
                            OptionRow(
                                icon: struggle.systemImage,
                                title: struggle.title,
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
        case .timeSinks:
            QuestionLayout(
                kicker: "Your phone",
                title: "Which apps keep you up?",
                subtitle: "The ones you're still in when you meant to be asleep. Choose any."
            ) {
                // Short app names fit two per row, so this question compacts
                // the struggle-row grammar into a 2-column grid of the same
                // glass capsules — same selection ring, same icon warm-up.
                LiquidGlassContainer(spacing: SleepSpacing.md) {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: SleepSpacing.md),
                            GridItem(.flexible(), spacing: SleepSpacing.md)
                        ],
                        spacing: SleepSpacing.md
                    ) {
                        ForEach(TimeSinkApp.allCases) { app in
                            TimeSinkChip(
                                app: app,
                                isSelected: timeSinks.contains(app)
                            ) {
                                Haptics.heavy()
                                if timeSinks.contains(app) {
                                    timeSinks.remove(app)
                                } else {
                                    timeSinks.insert(app)
                                }
                            }
                        }
                    }
                }
            }
        case .phoneTime:
            QuestionLayout(
                kicker: "Late nights",
                title: "How long does your phone keep you up?",
                subtitle: "After you're already in bed."
            ) {
                LiquidGlassContainer(spacing: SleepSpacing.md) {
                    VStack(spacing: SleepSpacing.md) {
                        ForEach(LateNightPhoneTime.allCases) { option in
                            OptionRow(
                                icon: option.systemImage,
                                title: option.title,
                                isSelected: phoneTime == option
                            ) {
                                Haptics.heavy()
                                phoneTime = option
                            }
                        }
                    }
                }
            }
        case .feeling:
            QuestionLayout(
                kicker: "Your mornings",
                title: "How do you usually wake up?"
            ) {
                LiquidGlassContainer(spacing: SleepSpacing.md) {
                    VStack(spacing: SleepSpacing.md) {
                        ForEach(WakeFeeling.allCases) { option in
                            OptionRow(
                                icon: option.systemImage,
                                title: option.title,
                                isSelected: feeling == option
                            ) {
                                Haptics.heavy()
                                feeling = option
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
        case .plan:
            PlanStep(
                built: planBuilt,
                name: name,
                bedtime: bedtime,
                wakeTime: wakeTime,
                goal: goal,
                phoneTime: phoneTime,
                timeSinks: timeSinks
            )
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
            if step == .plan {
                // The plan summary's CTA is the flow's micro-commitment — a
                // small pledge, right before the account step asks to save
                // the plan (or, on the quick-setup path, before committing
                // directly). Hidden (not removed) during the build beat so
                // the layout doesn't jump when it appears.
                LiquidPrimaryButton(title: "I'm ready", systemImage: "checkmark") {
                    if includesAccount { advance() } else { finish() }
                }
                .opacity(planBuilt ? 1 : 0)
                .disabled(!planBuilt)
                .animation(.easeInOut(duration: 0.4), value: planBuilt)
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
        // Single-select questions require an answer: the plan speaks to the
        // choice, so there is no meaningful "skipped" reading. Multi-selects
        // stay skippable — an empty set is an honest answer there.
        case .goal: goal != nil
        case .phoneTime: phoneTime != nil
        case .feeling: feeling != nil
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
            // Leaving to welcome: start the dismissal now rather than letting
            // the name field's teardown do it mid-transition.
            Keyboard.dismiss()
            onBack?()
        }
    }

    private func finish() {
        Keyboard.dismiss()
        Haptics.success()
        onDone(OnboardingAnswers(
            name: name,
            bedtime: bedtime,
            wakeTime: wakeTime,
            struggles: struggles.map(\.rawValue),
            timeSinks: timeSinks.map(\.rawValue),
            goal: goal?.rawValue ?? "",
            lateNightPhone: phoneTime?.rawValue ?? "",
            wakeFeeling: feeling?.rawValue ?? ""
        ))
    }

    private func setStep(_ next: Step, forward: Bool) {
        movingForward = forward
        withAnimation(.easeInOut(duration: 0.28)) { step = next }
        if next == .plan && !planBuilt { startPlanBuild() }
    }

    /// The "Building your sleep plan…" beat: a short, deliberate pause while
    /// the sloth works, then the summary fades in with a success knock. Long
    /// enough to feel like the answers *made* something, short enough to
    /// never read as a spinner. Backing out mid-build cancels the reveal so
    /// re-entering runs it again from the top.
    private func startPlanBuild() {
        planBuildTask?.cancel()
        planBuildTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard !Task.isCancelled, step == .plan else { return }
            Haptics.success()
            withAnimation(.easeInOut(duration: 0.45)) { planBuilt = true }
        }
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

/// One full-width answer capsule, shared by every list question — the
/// multi-select struggles and the single-select goal/phone-time/feeling
/// steps (selection semantics live in the caller; the row just shows state).
private struct OptionRow: View {
    let icon: String
    let title: String
    let isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: SleepSpacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(isSelected ? SleepColor.amber : SleepColor.muted)
                    .frame(width: 24)
                Text(title)
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
        // The tint is deliberately constant: toggling it with selection
        // rebuilt the glassEffect on every tap — animated, across all five
        // container siblings, over the live scene — which is what made
        // choosing an option visibly lag. The ring, icon, and checkmark
        // carry the selection instead.
        .liquidGlass(
            cornerRadius: SleepRadius.pill,
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

/// The time-sink question's compact sibling of `OptionRow`: same glass
/// capsule, same amber selection ring/icon/checkmark grammar, halved to fit
/// two app names per row (eight options would overflow the screen as
/// full-width rows). The tint stays constant for the same reason as
/// OptionRow's — toggling glass tint rebuilt the effect across all
/// container siblings and visibly lagged the tap.
private struct TimeSinkChip: View {
    let app: TimeSinkApp
    let isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: SleepSpacing.sm) {
                Image(systemName: app.systemImage)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(isSelected ? SleepColor.amber : SleepColor.muted)
                    .frame(width: 20)
                Text(app.title)
                    .font(SleepFont.label(15))
                    .foregroundStyle(SleepColor.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(isSelected ? SleepColor.amber : SleepColor.faint)
            }
            .padding(.horizontal, SleepSpacing.lg)
            .frame(maxWidth: .infinity, minHeight: 54)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .liquidGlass(
            cornerRadius: SleepRadius.pill,
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

// MARK: - Plan reveal

/// The questionnaire's closing beat before the account step: a short
/// "Building your sleep plan…" pause — the brand sloth at work, its rising
/// z's the only motion — resolving into a personalized summary assembled
/// from the answers just given (the sleep window, the weekly hours the phone
/// is eating and which apps eat them, the stated goal). The reveal is what
/// makes the paywall that follows read as unlocking a plan the user built,
/// not buying a cold product; the "I'm ready" CTA beneath it is the flow's
/// one micro-commitment.
private struct PlanStep: View {
    let built: Bool
    let name: String
    let bedtime: Int
    let wakeTime: Int
    let goal: SleepGoal?
    let phoneTime: LateNightPhoneTime?
    let timeSinks: Set<TimeSinkApp>

    var body: some View {
        ZStack {
            if built {
                summary.transition(.opacity)
            } else {
                building.transition(.opacity)
            }
        }
    }

    private var building: some View {
        VStack(spacing: SleepSpacing.xl) {
            SlothBrandMark(width: 120, zScale: 0.6)
            Text("Building your sleep plan…")
                .font(SleepFont.body(16))
                .foregroundStyle(SleepColor.dim)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Building your sleep plan")
    }

    private var summary: some View {
        QuestionLayout(
            kicker: "Your plan",
            title: firstName.isEmpty ? "Your plan is ready." : "\(firstName), your plan is ready.",
            subtitle: "Tonight is night one."
        ) {
            GlassGroup {
                PlanRow(
                    icon: "moon.zzz",
                    label: "Sleep window",
                    value: "\(SleepFormatting.clock(bedtime)) – \(SleepFormatting.clock(wakeTime))",
                    detail: "\(SleepFormatting.duration(SleepMath.windowMinutes(bedtime: bedtime, wakeTime: wakeTime))) of sleep a night"
                )
                if let phoneTime {
                    GlassRowDivider()
                    PlanRow(
                        icon: "hourglass",
                        label: "Time to win back",
                        value: "\(SleepFormatting.duration(phoneTime.weeklyMinutes)) a week",
                        detail: sinksLine
                    )
                }
                if let goal {
                    GlassRowDivider()
                    PlanRow(icon: goal.systemImage, label: "Your goal", value: goal.title)
                }
            }
        }
    }

    private var firstName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: " ").first ?? ""
    }

    /// Names the user's own apps back to them — the sharpest line in the
    /// summary. Falls back to a generic read when none were picked.
    private var sinksLine: String {
        let names = TimeSinkApp.allCases.filter(timeSinks.contains).prefix(2).map(\.title)
        switch names.count {
        case 0: return "Back from your phone, into your night."
        case 1: return "Mostly \(names[0])."
        default: return "Mostly \(names[0]) & \(names[1])."
        }
    }
}

/// One fact of the plan summary: icon chip, quiet label, ink value, and an
/// optional dim detail line. Deliberately *not* a `GlassRow` — settings rows
/// name controls and never explain them, but this is a data readout whose
/// detail line carries the personalization payload (the user's own apps).
private struct PlanRow: View {
    let icon: String
    let label: String
    let value: String
    var detail: String?

    var body: some View {
        HStack(alignment: .center, spacing: SleepSpacing.md) {
            GlassRowIcon(icon: icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(SleepFont.body(13))
                    .foregroundStyle(SleepColor.muted)
                Text(value)
                    .font(SleepFont.title(17))
                    .foregroundStyle(SleepColor.ink)
                if let detail {
                    Text(detail)
                        .font(SleepFont.body(13))
                        .foregroundStyle(SleepColor.dim)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, SleepSpacing.md)
        .accessibilityElement(children: .combine)
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
    private static var didWarmFrameworks = false

    private static var activeWindow: UIWindow? {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
        else { return nil }
        return scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first
    }

    private static func makeWarmupField(in window: UIWindow) -> UITextField {
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
        return field
    }
    #endif

    static func dismiss() {
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }

    /// Flash-free first-stage warmup: become and resign first responder in
    /// the same runloop turn, so the keyboard presentation is cancelled
    /// before it commits and nothing ever appears on screen — but the input
    /// frameworks and keyboard process still spin up. Called while the
    /// onboarding gate idles: without it, that whole cold path ran at the
    /// instant "Get started" was tapped (inside `prewarm`), janking the
    /// route transition, with its tail still lagging the first keystrokes
    /// in the name field. Runs once per process, slightly delayed so it
    /// never competes with the gate's own first frame.
    static func warmFrameworks() {
        #if canImport(UIKit)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard !didWarmFrameworks, warmupField == nil else { return }
            guard let window = activeWindow else { return }
            didWarmFrameworks = true
            let field = makeWarmupField(in: window)
            field.becomeFirstResponder()
            field.resignFirstResponder()
            field.removeFromSuperview()
        }
        #endif
    }

    /// Second-stage warmup: really present a keyboard for a beat — masked by
    /// the welcome → questionnaire transition, whose name step auto-focuses
    /// moments later — so the first genuine appearance is instant. With
    /// `warmFrameworks()` having prepaid the framework load, this is cheap.
    static func prewarm(duration: TimeInterval = 0.55) {
        #if canImport(UIKit)
        DispatchQueue.main.async {
            guard warmupField == nil else { return }
            guard let window = activeWindow else { return }

            let field = makeWarmupField(in: window)
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
