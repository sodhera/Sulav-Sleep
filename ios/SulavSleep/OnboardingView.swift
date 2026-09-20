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
    /// How far the ground has settled toward black, 0 → 1. Welcome sits at
    /// the lightest end; the questionnaire reports its own progress so the
    /// screen is closest to night at the commitment. See `OnboardingStage`.
    @State private var stageDepth: Double = 0

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
            // The gate owns its own ground rather than taking RootView's
            // scene: it is the only pre-app screen whose stage moves.
            OnboardingStage(depth: stageDepth)

            switch route {
            case .welcome:
                WelcomeStep(
                    onGetStarted: {
                        SleepAnalytics.record("get_started_tapped", screen: "welcome", control: "get_started")
                        setRoute(.questions)
                    },
                    onSignIn: {
                        SleepAnalytics.record("sign_in_tapped", screen: "welcome", control: "sign_in")
                        store.authErrorMessage = nil
                        setRoute(.signIn)
                    }
                )
                .transition(.opacity)
            case .questions:
                OnboardingQuestionsView(
                    store: store,
                    onBack: store.isAuthenticated ? nil : { setRoute(.welcome) },
                    onProgress: { stageDepth = $0 }
                ) { answers in
                    store.completeOnboarding(answers)
                }
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
        .onAppear {
            Keyboard.warmFrameworks()
            if route == .welcome { SleepAnalytics.record("welcome_viewed", screen: "welcome") }
        }
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
        // without a phantom flash on the welcome or account screens. The
        // presentation is deferred a few frames: it used to start in the
        // same frame as the tap, stacking the keyboard commit on top of the
        // questionnaire's first build, and that shared frame was the
        // residual "Get started" hitch. Started ~80ms in, it is still fully
        // masked by the 280ms route transition and done before the name
        // step's 320ms autofocus takes the keyboard over.
        if next == .questions {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                Keyboard.prewarm()
            }
        }
        // Welcome and the standalone sign-in sit at the lit end of the
        // ground; the questionnaire takes over from its own progress.
        if next != .questions { stageDepth = next == .welcome ? 0 : 0.35 }
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
            slothImage(phase: phase)
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

    /// The sloth art through `SleepAssetCache`, so the mark draws a
    /// pre-decoded bitmap — a bare `Image(named:)` decoded the 1200×720 PNG
    /// at first display, which for the questionnaire header landed inside
    /// the "Get started" transition.
    private func slothImage(phase: CityPhase) -> Image {
        #if canImport(UIKit)
        if let decoded = SleepAssetCache.image(named: "HomeSloth\(phase.rawValue)Blink") {
            return Image(uiImage: decoded)
        }
        #endif
        return Image("HomeSloth\(phase.rawValue)Blink")
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
                    Text("Block distractions. Track your sleep.")
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

/// The sign-up flow: eleven beats, then account creation for signed-out users.
///
/// The arc alternates **ask** and **reveal**, and every ask feeds a reveal the
/// user watches happen. That is the flow's whole design: three cheap factual
/// inputs (in-bed, wake, phone) are enough to derive everything else, so by
/// the fourth screen the app is handing the user's own answers back as
/// arithmetic rather than asking for more. See `SleepDebt` for the figures and
/// `OnboardingExperience.swift` for the instruments that draw them.
///
/// Ordering notes worth keeping:
/// - **No text field first.** A keyboard is the highest-friction input there
///   is and step one is where the most people leave. The name is asked late,
///   where it reads as warmth and has a visible job (Home's greeting).
/// - **"Get into bed", not "go to bed".** The gap between getting in and
///   falling asleep *is* the phone time; the wording plants the question two
///   screens early.
/// - **The shortfall verdict is sourced, not spoken.** `SleepNeedBand` cites
///   the AASM so the app never calls the user's nights inadequate itself.
/// - Setup requests no permissions and selects no real apps. Screen Time
///   stays post-paywall.
struct OnboardingQuestionsView: View {
    let store: SleepStore
    /// Back action from the first step (to the welcome screen), or `nil` when
    /// there is nowhere to go back to (post-sign-in quick setup).
    var onBack: (() -> Void)?
    /// Reports flow progress (0 → 1) so the gate can deepen the ground
    /// underneath as the user advances. See `OnboardingStage`.
    var onProgress: ((Double) -> Void)?
    let onDone: (OnboardingAnswers) -> Void

    @State private var step: Step = .inBed
    @State private var draftRestored = false
    /// Whether this run may write a draft at all. Off for the DEBUG review
    /// routes: `draftRestored` alone can't gate writes, because that flag
    /// exists to stop saves *before* a restore has happened and must end up
    /// true either way — which meant a review route's fixture answers were
    /// written to the real draft key and a later ordinary launch resumed
    /// from them. Found by walking the flow after a screenshot run.
    @State private var draftsEnabled = true
    @State private var movingForward = true

    // Answers.
    @State private var inBed = 22 * 60 + 30
    @State private var wakeTime = 6 * 60 + 30
    /// Opens on a typical answer rather than at zero: a rail that starts at
    /// one end reads as "drag me somewhere" with no sense of where normal is,
    /// and the anchor pip is right there saying what normal looks like.
    @State private var phoneMinutes = OnboardingQuestionsView.typicalPhoneMinutes
    @State private var phoneTouched = false
    @State private var goal: SleepGoal?
    @State private var name = ""

    // Reveal gates: the steps that animate own their own Continue.
    @State private var gridReady = false
    @State private var narrativeReady = false
    @State private var goalReady = false
    /// Which narrative chapter of the `story` step is showing. Owned here
    /// because the flow's single primary button drives it (see "Actions").
    @State private var storyChapter = 0

    /// Whether this run ends on the account step. Captured once so it does not
    /// flip mid-flow when auth flips `isAuthenticated`.
    @State private var includesAccount: Bool

    init(
        store: SleepStore,
        onBack: (() -> Void)? = nil,
        onProgress: ((Double) -> Void)? = nil,
        onDone: @escaping (OnboardingAnswers) -> Void
    ) {
        self.store = store
        self.onBack = onBack
        self.onProgress = onProgress
        self.onDone = onDone
        _includesAccount = State(initialValue: !store.isAuthenticated)
#if DEBUG
        // QA entry points. `-review-onboarding-step=<raw>` lands on any step
        // with the answers from the steps *before* it filled in, so a reveal
        // can be screenshotted without playing the whole flow.
        //
        // Crucially it does **not** fill in the answer the reviewed step
        // itself collects. Pre-filling that meant the route could never show
        // a step's real initial state — an unselected goal list, an empty
        // name field, a disabled Continue — which is exactly the state most
        // worth reviewing, and it reads as a bug when you land on it.
        let arguments = ProcessInfo.processInfo.arguments
        if let flag = arguments.first(where: { $0.hasPrefix("-review-onboarding-step=") }),
           let reviewStep = Step(rawValue: String(flag.dropFirst("-review-onboarding-step=".count))) {
            _step = State(initialValue: reviewStep)
            func isPast(_ collecting: Step) -> Bool {
                guard let a = Step.reviewOrder.firstIndex(of: collecting),
                      let b = Step.reviewOrder.firstIndex(of: reviewStep) else { return false }
                return a < b
            }
            if isPast(.phone) {
                _phoneMinutes = State(initialValue: 60)
                _phoneTouched = State(initialValue: true)
            }
            if isPast(.story) { _goal = State(initialValue: .lessPhoneAtNight) }
            if isPast(.name) { _name = State(initialValue: "Sulav") }
        }
#endif
    }

    // MARK: The phone rail
    //
    // A typical hour in bed on a phone, and the rail that collects it. The
    // curve is chosen so `typicalPhoneMinutes` lands at the *centre* of the
    // travel: on a linear 0-4h rail a typical answer sat a fifth of the way
    // along, which squeezed the part of the question that actually varies —
    // twenty minutes versus an hour — into the left edge, and spent most of
    // the rail on answers almost nobody gives. The ceiling came down 4h → 3h
    // in the same pass; `SleepDebt.phoneCeiling` still clamps at 4h, so
    // historical answers stay valid.
    static let typicalPhoneMinutes = 50
    static let phoneSliderMax = 180
    static let phoneSliderCurve = 1.85

    /// The arc: your schedule → what the phone takes → what that costs →
    /// what you'd fix → the plan → who you are → what it looks like → commit.
    private enum Step: String, Codable {
        case inBed, wake, phone, sleep, need, grid, story, plan, name, preview, commit, account

        /// The full order, for the DEBUG review route to reason about which
        /// answers precede a given step. Kept separate from `steps`, which is
        /// an instance property and varies with `includesAccount`.
        static let reviewOrder: [Step] = [
            .inBed, .wake, .phone, .sleep, .need, .grid,
            .story, .plan, .name, .preview, .commit, .account
        ]
    }

    private struct Draft: Codable {
        var step: Step
        var inBed: Int
        var wakeTime: Int
        var phoneMinutes: Int
        var phoneTouched: Bool
        var goal: SleepGoal?
        var name: String
    }

    /// v2: the v1 key held the retired ten-step answer set (symptoms, wake
    /// feeling, a phone dial). A stale v1 draft can't be migrated into this
    /// flow's questions, so it is left to expire rather than half-restored.
    private static let draftKey = "sulav.onboardingDraft.v2"

    private var steps: [Step] {
        var result: [Step] = [
            .inBed, .wake, .phone, .sleep, .need, .grid, .story, .plan, .name, .preview, .commit
        ]
        if includesAccount { result.append(.account) }
        return result
    }

    private var currentIndex: Int { steps.firstIndex(of: step) ?? 0 }

    // MARK: Derived figures
    //
    // All of these are pure functions of the three inputs, recomputed on
    // demand. Nothing is cached: a back-and-edit on any question has to move
    // every downstream number, or the flow stops being the user's own
    // arithmetic.

    private var windowMinutes: Int {
        SleepDebt.windowMinutes(inBed: inBed, wake: wakeTime)
    }

    private var derivedSleep: Int {
        SleepDebt.derivedSleepMinutes(inBed: inBed, wake: wakeTime, phone: phoneMinutes)
    }

    /// The sleep figure every reveal reads off. Purely derived — the
    /// calibration step presents this rather than asking the user to confirm
    /// it, so there is no override to honour.
    private var effectiveSleep: Int { derivedSleep }

    private var phoneNights: Int {
        SleepDebt.phoneNightsPerYear(phone: phoneMinutes)
    }

    private var protectedSleep: Int {
        SleepDebt.protectedSleepMinutes(inBed: inBed, wake: wakeTime)
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
                currentStep
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .topLeading
                    )
                    .padding(.horizontal, SleepSpacing.xxl)
                    .padding(.top, SleepSpacing.xxxl)
                    .transition(stepTransition)
                    .id(step)

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
        .onAppear {
            restoreDraft()
            onProgress?(progress)
            SleepAnalytics.record("onboarding_step_viewed", screen: step.rawValue)
        }
        .onChange(of: step) { _, next in
            onProgress?(progress)
            SleepAnalytics.record("onboarding_step_viewed", screen: next.rawValue)
            saveDraft()
        }
        .onChange(of: inBed) { _, _ in saveDraft() }
        .onChange(of: wakeTime) { _, _ in saveDraft() }
        .onChange(of: phoneMinutes) { _, _ in saveDraft() }
        .onChange(of: phoneTouched) { _, _ in saveDraft() }
        .onChange(of: name) { _, _ in saveDraft() }
        .onChange(of: goal) { _, next in
            saveDraft()
            if next != nil { SleepAnalytics.record("onboarding_option_tapped", screen: "story", control: "goal") }
        }
        // The account step's auth succeeded. A brand-new account commits the
        // just-answered profile. An existing account (Apple/Google matching an
        // already-registered identity) must *not* commit them over the profile
        // that account already has — `RootView` has already taken the screen
        // with `ExistingAccountWelcomeView` by this point, which is where that
        // gets explained; all that's left here is to not call `finish()`.
        .onChange(of: store.isAuthenticated) { _, authenticated in
            guard authenticated, step == .account else { return }
            if store.lastSignInWasNewAccount {
                finish()
            } else {
                Keyboard.dismiss()
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
        case .inBed:
            QuestionLayout(title: "What time do you get into bed?") {
                TimeAdjuster(minutes: $inBed)
            }

        case .wake:
            QuestionLayout(
                title: "And what time do you need to be up?",
                readout: "That's \(Self.spokenDuration(windowMinutes)) in bed."
            ) {
                TimeAdjuster(minutes: $wakeTime)
            }

        case .phone:
            QuestionLayout(title: "Once you're in bed, how long are you on your phone?") {
                NightSlider(
                    value: $phoneMinutes,
                    touched: $phoneTouched,
                    range: 0...Self.phoneSliderMax,
                    step: 5,
                    curve: Self.phoneSliderCurve,
                    anchor: Self.typicalPhoneMinutes,
                    anchorLabel: "average",
                    lowLabel: "None",
                    highLabel: "3+ hrs",
                    caption: "Be honest.",
                    format: { $0 >= Self.phoneSliderMax ? "3+" : "\($0)" },
                    unit: phoneMinutes >= Self.phoneSliderMax ? "hours" : "minutes"
                )
            }

        case .sleep:
            // The first conclusion: the user's window becomes a proportional
            // timeline, with the remaining sleep and onset assumption explicit.
            QuestionLayout(title: "So here's your night.") {
                SleepNightStrip(
                    inBedMinutes: windowMinutes,
                    phoneMinutes: phoneMinutes,
                    asleepMinutes: effectiveSleep,
                    inBedClock: SleepFormatting.clock(inBed),
                    wakeClock: SleepFormatting.clock(wakeTime)
                )
            }

        case .need:
            QuestionLayout(
                title: shortfallTitle,
                subtitle: shortfallSubtitle
            ) {
                SleepNeedBand(sleepMinutes: effectiveSleep)
            }

        case .grid:
            YearOfNightsGrid(phoneMinutes: phoneMinutes, ready: $gridReady)

        case .story:
            NightGoalStep(
                phoneNights: phoneNights,
                goal: $goal,
                showingOptions: $goalReady,
                chapter: $storyChapter,
                ready: $narrativeReady
            )

        case .plan:
            NarrativePage(lines: [
                "Phone down at \(SleepFormatting.clock(inBed)).",
                "Up at \(SleepFormatting.clock(wakeTime)) with \(Self.spokenDuration(protectedSleep)) behind you.",
                "That's \(phoneNights) nights back this year."
            ], ready: $narrativeReady)

        case .name:
            QuestionLayout(title: "What should we call you in the morning?") {
                NameField(name: $name, onSubmit: advance)
            }

        case .preview:
            BlockingPreviewStep(inBedClock: SleepFormatting.clock(inBed))

        case .commit:
            // The fingerprint *is* this step, so it lives in the content
            // region rather than the bottom action slot. A commitment you
            // authorise should be the thing you are looking at.
            QuestionLayout(
                title: commitTitle,
                subtitle: "Take back your nights. Make room for your mornings."
            ) {
                CommitmentHoldButton {
                    if includesAccount { advance() } else { finish() }
                }
            }

        case .account:
            // Rendered by AuthMethodsView in the body, outside this scaffold.
            EmptyView()
        }
    }

    // MARK: Adaptive copy
    //
    // Anyone already clearing seven hours must not be told they are short —
    // the band would contradict the headline, and a flow that argues with its
    // own graphic loses the credibility the whole arc runs on. They get the
    // protective framing instead, and the phone figure still carries the
    // reveal that follows.

    /// Three bands, not two. An earlier draft told everyone at or above the
    /// floor "You're getting enough. Barely." — which is flatly false for
    /// someone sleeping nine hours, and being told an obvious untruth on the
    /// one screen built to borrow the AASM's credibility costs the whole arc
    /// that follows it. The phone figure carries the next reveal either way,
    /// so there is nothing to gain by overstating this one.
    private var shortfallTitle: String {
        switch effectiveSleep {
        case ..<SleepDebt.target:
            let short = SleepDebt.nightlyShortfall(sleepMinutes: effectiveSleep)
            return "You're \(Self.spokenDuration(short)) short. Every night."
        case ..<(SleepDebt.target + 60):
            return "You're just inside the range."
        default:
            return "You're getting enough sleep."
        }
    }

    /// A shortfall read aloud, not clocked. `SleepFormatting.duration` is the
    /// app's *instrument* format — right for a sleep total ("6h 45m"), wrong
    /// in a sentence, where it renders a quarter of an hour as "0h 15m" and
    /// makes the headline sound broken. Durations inside prose get words.
    private static func spokenDuration(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) minutes" }
        let hours = minutes / 60
        let remainder = minutes % 60
        if remainder == 0 { return hours == 1 ? "an hour" : "\(hours) hours" }
        return "\(hours)h \(remainder)m"
    }

    private var shortfallSubtitle: String {
        switch effectiveSleep {
        case ..<SleepDebt.target:
            return "Adults need 7 to 9 hours."
        case ..<(SleepDebt.target + 60):
            return "Adults need 7 to 9 hours. You're at the bottom of it."
        default:
            return "Adults need 7 to 9 hours. Protecting that is the job now."
        }
    }

    private var commitTitle: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Are you ready to take your nights back?"
            : "Are you ready to take your nights back, \(name.trimmingCharacters(in: .whitespacesAndNewlines))?"
    }

    // MARK: Actions

    /// **One button, one gesture.** Every forward step is the same primary
    /// button; the commitment hold is the only gesture in the flow. The
    /// retired slide-to-continue capsule is discussed above
    /// `CommitmentHoldButton`.
    ///
    /// Steps that animate a figure keep their button *present but inert*
    /// until the reveal lands — faded, never absent. A control that
    /// materialises out of nothing when a page finishes typing reads as a
    /// glitch, and it hides where the user is meant to go next.
    @ViewBuilder
    private var actions: some View {
        switch step {
        // `.commit` has no bottom action: its fingerprint is the content.
        case .commit:
            EmptyView()

        case .story where !goalReady:
            // Still telling the story: the button turns the page.
            revealGatedButton("Continue", ready: narrativeReady, action: advanceStory)

        case .plan:
            revealGatedButton("Continue", ready: narrativeReady, action: advance)

        case .grid:
            revealGatedButton("Take them back", ready: gridReady, action: advance)

        case .preview:
            LiquidPrimaryButton(title: "That's what I want", action: advance)

        default:
            LiquidPrimaryButton(title: "Continue", action: advance)
                .disabled(!isStepValid)
                .opacity(isStepValid ? 1 : 0.45)
        }
    }

    private func revealGatedButton(
        _ title: String,
        ready: Bool,
        action: @escaping () -> Void
    ) -> some View {
        LiquidPrimaryButton(title: title, action: action)
            .disabled(!ready)
            .opacity(ready ? 1 : 0.35)
            .animation(.easeInOut(duration: 0.3), value: ready)
    }

    /// Turns a narrative page, or hands the step over to the goal question
    /// once the story is out of pages.
    private func advanceStory() {
        SleepAnalytics.record("onboarding_next_tapped", screen: "story", control: "chapter")
        if storyChapter >= NightGoalStep.pageCount - 1 {
            withAnimation(.easeInOut(duration: 0.32)) { goalReady = true }
        } else {
            narrativeReady = false
            withAnimation(.easeInOut(duration: 0.4)) { storyChapter += 1 }
        }
    }

    private var isStepValid: Bool {
        switch step {
        // The rail opens on a typical answer with the anchor pip beside it,
        // so the starting value is a real proposition rather than an
        // unset control — and requiring a touch would force anyone whose
        // answer *is* typical to drag away and back to prove they meant it.
        case .phone: phoneMinutes > 0
        case .story: goalReady && goal != nil
        case .plan: narrativeReady
        case .grid: gridReady
        case .name: !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default: true
        }
    }

    // No haptic here: the Next button (`LiquidPrimaryButton`) already knocks
    // on tap, and this also runs from the name field's return key.
    private func advance() {
        guard isStepValid else { return }
        SleepAnalytics.record("onboarding_next_tapped", screen: step.rawValue, control: "next")
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
        SleepAnalytics.record("onboarding_back_tapped", screen: step.rawValue, control: "back")
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
        UserDefaults.standard.removeObject(forKey: Self.draftKey)
        SleepAnalytics.record("onboarding_finished", screen: "commit")
        onDone(OnboardingAnswers(
            name: name,
            bedtime: inBed,
            wakeTime: wakeTime,
            // The retired flow's symptom and wake-feeling questions are gone;
            // their columns stay in the payload so the Supabase profile shape
            // and `SleepCloudService` need no migration.
            struggles: [],
            goal: goal?.rawValue ?? "",
            lateNightPhone: "minutes:\(phoneMinutes)",
            wakeFeeling: ""
        ))
    }

    private func setStep(_ next: Step, forward: Bool) {
        movingForward = forward
        withAnimation(.easeInOut(duration: 0.28)) { step = next }
        narrativeReady = false
        goalReady = false
        gridReady = false
        storyChapter = 0
    }

    private func saveDraft() {
        guard draftRestored, draftsEnabled else { return }
        let draft = Draft(
            step: step, inBed: inBed, wakeTime: wakeTime,
            phoneMinutes: phoneMinutes, phoneTouched: phoneTouched,
            goal: goal, name: name
        )
        if let data = try? JSONEncoder().encode(draft) {
            UserDefaults.standard.set(data, forKey: Self.draftKey)
        }
    }

    private func restoreDraft() {
        guard !draftRestored else { return }
#if DEBUG
        let isPreviewRoute = ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("-review-onboarding-") }
        if isPreviewRoute {
            draftsEnabled = false
            draftRestored = true
            return
        }
#endif
        if let data = UserDefaults.standard.data(forKey: Self.draftKey),
           let draft = try? JSONDecoder().decode(Draft.self, from: data) {
            inBed = draft.inBed
            wakeTime = draft.wakeTime
            phoneMinutes = draft.phoneMinutes
            phoneTouched = draft.phoneTouched
            goal = draft.goal
            name = draft.name
            // Reveal steps replay on resume; the account step still requires
            // authentication. Never resume past a missing required answer —
            // a restored draft that skipped the phone question would leave
            // every downstream figure derived from a default.
            step = steps.contains(draft.step) ? draft.step : .inBed
            if phoneMinutes <= 0 {
                if currentIndex > 2 { step = .phone }
            } else if currentIndex > 6 && goal == nil {
                step = .story
            } else if currentIndex > 8 && name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                step = .name
            }
        }
        draftRestored = true
    }
}

// MARK: - Shared question chrome

/// Editorial question layout with two independent anchors: the question stays
/// at the top while its controls are vertically centered in the space between
/// the prompt and the bottom action. The flexible spacers collapse for taller
/// answer groups, so the content still fits compact screens. No small-caps
/// kicker — the title carries the question on its own, so the questionnaire
/// reads cleaner and each step's self-contained question isn't shadowed by a
/// redundant category label.
private struct QuestionLayout<Content: View>: View {
    let title: String
    var subtitle: String?
    /// A live consequence of the control below it — "That's 8 hours in bed."
    ///
    /// Separate from `subtitle` because it belongs to the *answer*, not the
    /// question. Sat under the title it read as part of the prompt and the
    /// user had to look away from the wheel they were turning to see their
    /// own number change; directly beneath the control, the cause and its
    /// effect are in one glance.
    var readout: String?
    @ViewBuilder var content: Content

    var body: some View {
        // Centred, not leading. The flow reads as a sequence of statements
        // addressed to one person, and a centred column carries that better
        // than a left rag — it also keeps the question, the control and the
        // readout on one axis, so the eye travels straight down.
        VStack(alignment: .center, spacing: 0) {
            VStack(alignment: .center, spacing: SleepSpacing.md) {
                Text(title)
                    .font(SleepFont.title(28))
                    .foregroundStyle(SleepColor.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(subtitle)
                        .font(SleepFont.body(15))
                        .foregroundStyle(SleepColor.ink.opacity(0.88))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: SleepSpacing.lg)

            VStack(spacing: SleepSpacing.xl) {
                content
                if let readout {
                    Text(readout)
                        .font(SleepFont.body(16))
                        .foregroundStyle(SleepColor.dim)
                        .contentTransition(.numericText())
                        .animation(.snappy(duration: 0.2), value: readout)
                        .frame(maxWidth: .infinity)
                }
            }

            Spacer(minLength: SleepSpacing.lg)
        }
        .frame(maxHeight: .infinity, alignment: .top)
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
/// multi-select struggles and the single-select goal/phone-time/feeling steps
/// (selection semantics live in the caller; the row just shows state).
struct OptionRow: View {
    let icon: String
    let title: String
    let isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            // The label the glass renders is deliberately constant — see the
            // comment on the selection overlay below.
            HStack(spacing: SleepSpacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(SleepColor.muted)
                    .frame(width: 24)
                Text(title)
                    .font(SleepFont.label(16))
                    .foregroundStyle(SleepColor.ink)
                Spacer()
                Image(systemName: "circle")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(SleepColor.faint)
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
        // Selection is painted entirely *above* the glass, as one overlay
        // faded by opacity: the amber ring, plus amber twins of the icon and
        // trailing glyph sitting exactly over their constant base copies.
        // Changing any pixel *inside* glassEffect content (the old
        // color/symbol swap) re-rendered the glass on every tap — the same
        // failure family as the tint toggle above — while an overlay fade is
        // a pure composite. The overlay duplicates the base label's geometry
        // (same paddings, frames, and font metrics) so the twins cover 1:1.
        .overlay {
            ZStack {
                Capsule(style: .continuous)
                    .stroke(SleepColor.amber.opacity(0.45), lineWidth: 1)
                HStack(spacing: SleepSpacing.md) {
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .regular))
                        .frame(width: 24)
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20, weight: .light))
                }
                .padding(.horizontal, SleepSpacing.xl)
            }
            .foregroundStyle(SleepColor.amber)
            .opacity(isSelected ? 1 : 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
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
