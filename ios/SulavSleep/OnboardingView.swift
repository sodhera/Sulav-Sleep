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
                    healthAvailable: store.healthSyncState != .unavailable,
                    onBack: store.isAuthenticated ? nil : { setRoute(.welcome) }
                ) { name, bedtime, wakeTime, connectHealth, struggles in
                    store.completeOnboarding(
                        name: name, bedtime: bedtime, wakeTime: wakeTime,
                        connectHealth: connectHealth, struggles: struggles
                    )
                }
                .transition(.opacity)
            case .signIn:
                AuthView(store: store, intent: .signIn) {
                    store.authErrorMessage = nil
                    setRoute(.welcome)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.28), value: route)
        // Sign-in succeeded but there's no profile on this device yet: run the
        // quick setup before entering the app.
        .onChange(of: store.isAuthenticated) { _, authenticated in
            if authenticated && route == .signIn {
                setRoute(.questions)
            }
        }
    }

    private func setRoute(_ next: Route) {
        withAnimation(.easeInOut(duration: 0.28)) { route = next }
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
                LiquidPrimaryButton(title: "Get started", systemImage: "arrow.right") {
                    Haptics.soft()
                    onGetStarted()
                }
                Button("I already have an account") {
                    Haptics.soft()
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
        .onAppear { Keyboard.prewarm() }
    }
}

// MARK: - Questionnaire

/// The sign-up questions: who you are, what's in the way, and your sleep
/// window. Ends with Apple Health, then hands the answers to `onDone` — the
/// account step comes after, once the user is invested in their plan.
struct OnboardingQuestionsView: View {
    var healthAvailable: Bool
    /// Back action from the first step (to the welcome screen), or `nil` when
    /// there is nowhere to go back to (post-sign-in quick setup).
    var onBack: (() -> Void)?
    let onDone: (String, Int, Int, Bool, [String]) -> Void

    @State private var step: Step = .name
    @State private var movingForward = true
    @State private var name = ""
    @State private var struggles: Set<SleepStruggle> = []
    @State private var bedtime = 22 * 60 + 30
    @State private var wakeTime = 6 * 60 + 30

    private enum Step: Int, CaseIterable {
        case name, struggles, bedtime, wake, health
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, SleepSpacing.xxl)
                .padding(.top, SleepSpacing.md)

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
        .safeAreaPadding(.top)
        .safeAreaPadding(.bottom)
        .animation(.easeInOut(duration: 0.28), value: step)
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

            // Mirror the chevron's width so the bar stays centered.
            Color.clear.frame(width: 36, height: 36)
        }
        .animation(.easeInOut(duration: 0.28), value: canGoBack)
    }

    private var canGoBack: Bool { step != .name || onBack != nil }

    private var progress: Double {
        Double(step.rawValue + 1) / Double(Step.allCases.count)
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
                VStack(spacing: SleepSpacing.md) {
                    ForEach(SleepStruggle.allCases) { struggle in
                        StruggleRow(
                            struggle: struggle,
                            isSelected: struggles.contains(struggle)
                        ) {
                            Haptics.soft()
                            if struggles.contains(struggle) {
                                struggles.remove(struggle)
                            } else {
                                struggles.insert(struggle)
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
        case .health:
            QuestionLayout(
                kicker: "Last step",
                title: healthAvailable ? "Sync with Apple Health" : "Your plan is ready",
                subtitle: healthAvailable
                    ? "Your real nights fill in automatically, both ways. Change it anytime in Settings."
                    : "Log a night and your reports fill in. No sample data, ever."
            ) {
                Image(systemName: healthAvailable ? "heart.text.square.fill" : "checkmark.seal.fill")
                    .font(.system(size: 40, weight: .regular))
                    .foregroundStyle(SleepColor.amber)
            }
        }
    }

    private var windowMinutes: Int {
        SleepMath.windowMinutes(bedtime: bedtime, wakeTime: wakeTime)
    }

    // MARK: Actions

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: SleepSpacing.md) {
            if step == .health {
                if healthAvailable {
                    LiquidPrimaryButton(title: "Connect Apple Health", systemImage: "heart.fill") {
                        finish(connectHealth: true)
                    }
                    Button("Maybe later") { finish(connectHealth: false) }
                        .font(SleepFont.body(15))
                        .foregroundStyle(SleepColor.dim)
                        .frame(maxWidth: .infinity, minHeight: 44)
                } else {
                    LiquidPrimaryButton(title: "Continue", systemImage: "arrow.right") {
                        finish(connectHealth: false)
                    }
                }
            } else {
                LiquidPrimaryButton(title: "Next", systemImage: "arrow.right") {
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

    private func advance() {
        guard isStepValid, let next = Step(rawValue: step.rawValue + 1) else { return }
        Haptics.soft()
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

    private func goBack() {
        Haptics.soft()
        if let previous = Step(rawValue: step.rawValue - 1) {
            Keyboard.dismiss()
            setStep(previous, forward: false)
        } else {
            onBack?()
        }
    }

    private func finish(connectHealth: Bool) {
        Keyboard.dismiss()
        Haptics.success()
        onDone(name, bedtime, wakeTime, connectHealth, struggles.map(\.rawValue))
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

/// Round glass chevron used across onboarding and auth headers.
struct GlassBackButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(SleepColor.ink)
                .frame(width: 36, height: 36)
        }
        .liquidGlass(cornerRadius: SleepRadius.pill, interactive: true)
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
        TextField("Your name", text: $name)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled(true)
            .submitLabel(.next)
            .font(SleepFont.title(24))
            .foregroundStyle(SleepColor.ink)
            .tint(SleepColor.amber)
            .padding(.vertical, SleepSpacing.md)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(isFocused ? SleepColor.amber.opacity(0.5) : SleepColor.hairline)
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
        .background {
            Capsule(style: .continuous)
                .fill(isSelected ? SleepColor.glassWarm : SleepColor.glassFill)
        }
        .overlay {
            Capsule(style: .continuous)
                .stroke(isSelected ? SleepColor.amber.opacity(0.45) : SleepColor.border, lineWidth: 1)
        }
        .liquidGlass(
            cornerRadius: SleepRadius.pill,
            tint: isSelected ? SleepColor.glassWarm : SleepColor.glassFill,
            interactive: true
        )
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
