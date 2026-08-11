import SwiftUI
import UserNotifications

// Home is the bedside instrument: one glance says how long until bed, one
// action starts the night. The composition is a single centered column with
// almost no prose — greeting up top, the home sloth as the hero (awake
// through the day, heavy-lidded as bedtime nears) over the bedtime
// countdown, two glass schedule chips under it, and the Sleep Now capsule
// anchored low where a thumb naturally rests. The screen never scrolls; an
// instrument doesn't.
struct HomeView: View {
    var store: SleepStore
    let profile: Profile

    @State private var showingScheduleEditor = false
    @State private var showingReasons = false
    @Environment(\.requestReview) private var requestReview

    var body: some View {
        ZStack {
            // The flag lives on the store so the widget/shield deep link can
            // open this panel too (see AppDelegate.onOpenURL).
            if store.showWindDown {
                WindDownView(
                    store: store,
                    onDone: {
                        withAnimation(.easeInOut(duration: 0.32)) { store.showWindDown = false }
                    },
                    onReady: {
                        // Straight through to the commitment while the intent
                        // is hot — the wind-down's whole job is getting someone
                        // to the point where this is an easy yes.
                        withAnimation(.easeInOut(duration: 0.32)) {
                            store.showWindDown = false
                            store.showSleepConfirmation = true
                        }
                    }
                )
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .bottom)),
                    removal: .opacity.combined(with: .move(edge: .bottom))
                ))
            } else if store.showTonightCheckIn {
                TonightCheckInView(store: store, profile: profile) {
                    withAnimation(.easeInOut(duration: 0.32)) { store.showTonightCheckIn = false }
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .bottom)),
                    removal: .opacity.combined(with: .move(edge: .bottom))
                ))
            } else if store.showSleepConfirmation {
                // Scrolls up into view when Sleep Now is tapped, and — on
                // Cancel — scrolls back down the same way it arrived, rather
                // than fading in place.
                SleepConfirmationPanel(store: store, profile: profile) {
                    withAnimation(.easeInOut(duration: 0.32)) { store.showSleepConfirmation = false }
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .bottom)),
                    removal: .opacity.combined(with: .move(edge: .bottom))
                ))
            } else {
                homeContent
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity.combined(with: .move(edge: .top))
                    ))
            }
        }
        .padding(.horizontal, SleepSpacing.xxl)
        .safeAreaPadding(.top)
        .task {
            // Request standard authorization when the user actually reaches
            // the main app interface, rather than immediately on cold boot.
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        }
        .task { await maybeAskForReview() }
        .sheet(isPresented: $showingScheduleEditor) {
            NavigationStack {
                ScheduleScreen(store: store, profile: profile)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingReasons) {
            NavigationStack {
                ReasonsScreen(store: store)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    /// Asks for a review on **Home**, never at wake-up.
    ///
    /// Waking is the obvious "success" moment and the wrong one: the user is
    /// half-awake and trying to start their day, and a dialog there is exactly
    /// the interruption this app exists to avoid. Home on a later launch is
    /// the same user, awake, with nothing in progress.
    ///
    /// The pause lets the screen settle first — the prompt shouldn't race the
    /// notification permission sheet or land on a half-drawn scene. It also
    /// re-checks afterwards, since the user may have started a night in the
    /// meantime.
    private func maybeAskForReview() async {
        guard store.shouldRequestReview else { return }
        guard (try? await Task.sleep(for: .seconds(3))) != nil else { return }
        guard store.shouldRequestReview, !store.showSleepConfirmation else { return }
        store.markReviewRequested()
        requestReview()
    }

    private var homeContent: some View {
        VStack(spacing: 0) {
            VStack(spacing: SleepSpacing.sm) {
                Text(greeting).sectionLabel()
                Text(profile.name)
                    .font(SleepFont.hero(36))
                    .foregroundStyle(SleepColor.ink)
            }
            .padding(.top, SleepSpacing.huge)

            Spacer(minLength: SleepSpacing.xxxl)

            TimelineView(.periodic(from: .now, by: 60)) { timeline in
                VStack(spacing: SleepSpacing.xxl) {
                    HomeSloth(profile: profile, now: timeline.date)

                    Button {
                        Haptics.heavy()
                        showingScheduleEditor = true
                    } label: {
                        ScheduleCapsule(
                            bedtime: SleepFormatting.clock(profile.bedtime),
                            wake: SleepFormatting.clock(profile.wakeTime)
                        )
                    }
                    .buttonStyle(ScheduleCapsuleButtonStyle())
                }
            }

            // Last night's recap, sitting under the schedule pill so the whole
            // status block reads top-down — countdown, schedule, last night —
            // and Sleep Now stays the one thing anchored low.
            LastNightStrip(lastSession: store.lastNightSession)
                .padding(.top, SleepSpacing.xl)

            // The morning mirror, directly under the strip that already answers
            // "how was last night" — same question, the part the duration can't
            // say. Absent entirely on a night with no reaches.
            if let night = store.lastNightReaches {
                ReachMirrorLine(night: night, invitesReason: store.shouldPromptForReason) {
                    showingReasons = true
                }
                .padding(.top, SleepSpacing.sm)
            }

            // A fixed gap above the button and a flexible spacer below it (see
            // the end of this stack): the button keeps the same lower-third
            // position it held before the last-night strip moved up, rather
            // than being pushed to the very bottom by a flexible gap here.
            Spacer().frame(height: SleepSpacing.xxxl)

            // The lock. A locked user gets the whole of Home — the countdown,
            // the sloth, their schedule, last night's strip — and is stopped
            // here, at the one action the subscription buys. The button keeps
            // its own name and moon: it still leads where it says it leads,
            // and the paywall (not a disabled control) is what explains the
            // price. Nothing is greyed out, because a dead button answers no
            // questions. See DESIGN.md ("Paywall").
            LiquidPrimaryButton(title: "Sleep Now", systemImage: "moon.fill") {
                guard !store.presentPaywallIfLocked() else { return }
                withAnimation(.easeInOut(duration: 0.3)) { store.showSleepConfirmation = true }
            }

            Spacer(minLength: SleepSpacing.xxxl)
        }
        // The two corner chips, in the empty band beside the greeting — a
        // balanced pair, not chrome: **your streak** top-left, **your
        // partners** top-right. Both are glass, both 44pt tall, so the top
        // edge reads as one row. The streak chip is also what keeps the
        // flame out of the center column (the last-night strip carries only
        // the duration now) — status lives at the edges, the instrument
        // stays in the middle.
        .overlay(alignment: .topLeading) {
            if store.streak.isVisible {
                StreakChip(streak: store.streak) {
                    // The flame's story lives on Profile (the record).
                    store.selectedTab = .profile
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            // The sleep-partners entrance — hidden in dev mode.
            if store.referralAvailable {
                GlassIconButton(systemImage: "person.2.fill", size: 44, iconSize: 17) {
                    store.showPartners = true
                }
                .accessibilityLabel("Sleep partners")
            }
        }
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Good night"
        }
    }
}

// MARK: - Home sloth

/// The screen's hero: the app's sloth lounging on its pillow, with the
/// bedtime countdown beneath it. The sloth is the *state* — awake through
/// the day, heavy-lidded once bedtime is near or past — and the numerals are
/// the *instrument*.
///
/// Past bedtime the countdown **turns around** rather than rolling over: the
/// kicker becomes "Past bedtime" and the numerals count *up* from it. Rolling
/// over answered a question nobody asked — telling someone who is up too late
/// that tomorrow's bedtime is 20 hours away, when the fact that matters is
/// how far past tonight's they are. It runs the whole sleep window, so Home
/// and the shield ("You're 16 minutes past your bedtime") never disagree
/// about the same moment. After wake time a forward countdown is genuinely
/// the right answer, and it returns.
private struct HomeSloth: View {
    let profile: Profile
    let now: Date

    @State private var breathing = false
    @State private var eyesShut = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Minutes before bedtime at which the sloth's eyelids get heavy.
    private static let drowsyLead = 90

    var body: some View {
        let nowMinutes = SleepFormatting.minutes(from: now)
        let sinceBedtime = ((nowMinutes - profile.bedtime) % 1_440 + 1_440) % 1_440
        let untilBedtime = ((profile.bedtime - nowMinutes) % 1_440 + 1_440) % 1_440
        // `sinceBedtime` is 0...1439, and the bedtime minute itself counts as
        // past bedtime — that is the minute blocking starts. Excluding 0 left
        // it in neither state: Home fell through to the countdown, which
        // answered "24h 00m".
        //
        // The window is bedtime→wake, the same span the shield covers, so the
        // two surfaces always describe the current moment the same way.
        let sleepWindow = SleepMath.windowMinutes(bedtime: profile.bedtime, wakeTime: profile.wakeTime)
        let isPastBedtime = sinceBedtime < sleepWindow
        let isDrowsy = isPastBedtime || untilBedtime <= Self.drowsyLead
        // The sloth wears the scene's light — day, golden hour, or lamp-lit
        // night — so the figure and the city always share one sky.
        let light = CityPhase.current(now).rawValue

        VStack(spacing: SleepSpacing.xl) {
            ZStack {
                Image("HomeSloth\(light)\(isDrowsy ? "Drowsy" : "Awake")")
                    .resizable()
                    .scaledToFit()
                // The blink frame is pixel-aligned with the open-eyed art
                // (same render, same crop) and flashes over it — a hard
                // cut, like a cartoon blink should be.
                Image("HomeSloth\(light)Blink")
                    .resizable()
                    .scaledToFit()
                    .opacity(eyesShut ? 1 : 0)
            }
            .frame(width: 250)
            // A barely-there breath — the sloth is a creature, not a
            // sticker. Anchored at the pillow so only the body swells.
            .scaleEffect(y: breathing ? 1.013 : 1.0, anchor: .bottom)
            .animation(
                .easeInOut(duration: 3.6).repeatForever(autoreverses: true),
                value: breathing
            )
            // The warm halo that seats the figure in the scene — softer in
            // daylight, strongest once the lamps are the only light.
            .background {
                Ellipse()
                    .fill(SleepColor.amber.opacity(light == "Day" ? 0.10 : 0.16))
                    .blur(radius: 36)
                    .padding(-SleepSpacing.md)
            }
            .shadow(color: SleepColor.background.opacity(0.45), radius: 18, y: 10)
            .accessibilityHidden(true)
            .onAppear { if !reduceMotion { breathing = true } }
            .task {
                // Blink every few seconds: shut for 120ms, then open. The
                // interval jitters so it never reads as a metronome.
                guard !reduceMotion else { return }
                while !Task.isCancelled {
                    let pause = Double.random(in: 3.5...7.0)
                    guard (try? await Task.sleep(for: .seconds(pause))) != nil else { return }
                    eyesShut = true
                    guard (try? await Task.sleep(for: .milliseconds(120))) != nil else { return }
                    eyesShut = false
                }
            }

            VStack(spacing: SleepSpacing.sm) {
                Text(isPastBedtime ? "Past bedtime" : "Bedtime in").sectionLabel()
                // Same numeral treatment either way — it is one instrument
                // reading in two directions, not two different displays. Only
                // the colour shifts: amber once you're over.
                Text(isPastBedtime
                     ? SleepFormatting.duration(sinceBedtime)
                     : SleepFormatting.countdown(toMinuteOfDay: profile.bedtime, from: now))
                    .font(SleepFont.hero(40))
                    .foregroundStyle(isPastBedtime ? SleepColor.amber : SleepColor.ink)
                    .monospacedDigit()
            }
        }
    }
}

// MARK: - Schedule capsule

/// One glass capsule stating tonight's window as the single fact it is —
/// moon + bedtime → sun + wake — rather than two disconnected chips.
/// Read-only; the schedule is edited in Settings.
private struct ScheduleCapsule: View {
    let bedtime: String
    let wake: String

    var body: some View {
        HStack(spacing: SleepSpacing.md) {
            endpoint(icon: "moon.fill", time: bedtime)
            Image(systemName: "arrow.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(SleepColor.muted)
            endpoint(icon: "sun.max.fill", time: wake)
        }
        .padding(.horizontal, SleepSpacing.xl)
        .frame(height: 36)
    }

    private func endpoint(icon: String, time: String) -> some View {
        HStack(spacing: SleepSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(SleepColor.amber)
            Text(time)
                .font(SleepFont.label(14))
                .foregroundStyle(SleepColor.dim)
                .monospacedDigit()
        }
    }
}

private struct ScheduleCapsuleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .liquidGlass(cornerRadius: SleepRadius.pill, tint: SleepColor.glassFill, interactive: true)
            .scaleEffect(pressed ? 0.965 : 1)
            .opacity(pressed ? 0.96 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.58), value: pressed)
    }
}

// MARK: - Last night strip

/// One quiet centered line under the button — duration and streak — and
/// nothing at all without data: no hairline, no empty-state copy. A first
/// night begins the record.
private struct LastNightStrip: View {
    let lastSession: SleepSession?

    var body: some View {
        if let lastSession {
            HStack(spacing: SleepSpacing.sm) {
                Text("Last night")
                    .font(SleepFont.body(13))
                    .foregroundStyle(SleepColor.muted)
                Text(SleepFormatting.duration(lastSession.durationMinutes))
                    .font(SleepFont.label(14))
                    .foregroundStyle(SleepColor.dim)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)
        }
    }
}

/// The streak, worn as a corner chip — Home's top-left answer to the partner
/// button on the right: your run on one side, your people on the other. A
/// glass capsule the same 44pt height as its twin, flame + bare count (a
/// flame beside a number already reads as a streak). Dying keeps the hollow
/// muted-grey grammar (see DESIGN.md): same glyph, same count, the fill is
/// what goes out. Hidden entirely at zero — honest data, no cold ashes.
/// Tapping leads to Profile, where the record behind the number lives.
private struct StreakChip: View {
    let streak: SleepStreak
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.heavy()
            action()
        } label: {
            Label("\(streak.count)", systemImage: streak.isDying ? "flame" : "flame.fill")
                .font(SleepFont.label(15))
                .foregroundStyle(streak.isDying ? SleepColor.muted : SleepColor.gold)
                .monospacedDigit()
                .padding(.horizontal, SleepSpacing.lg)
                .frame(minHeight: 44)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .liquidGlass(cornerRadius: SleepRadius.pill, interactive: true)
        .accessibilityLabel(
            streak.isDying
                ? "\(streak.count) night streak, ending tonight unless you log sleep"
                : "\(streak.count) night streak"
        )
    }
}
