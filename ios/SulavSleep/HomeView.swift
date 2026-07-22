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

    var body: some View {
        ZStack {
            // The flag lives on the store so the widget/shield deep link can
            // open this panel too (see AppDelegate.onOpenURL).
            if store.showSleepConfirmation {
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
        .sheet(isPresented: $showingScheduleEditor) {
            NavigationStack {
                ScheduleScreen(store: store, profile: profile)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
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

            Spacer(minLength: SleepSpacing.xxxl)

            LiquidPrimaryButton(title: "Sleep Now", systemImage: "moon.fill") {
                withAnimation(.easeInOut(duration: 0.3)) { store.showSleepConfirmation = true }
            }

            LastNightStrip(lastSession: store.lastNightSession, streak: store.onTrackStreak)
                .padding(.top, SleepSpacing.xl)

            Spacer().frame(height: SleepSpacing.xl)
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
/// the day, heavy-lidded once bedtime is near or just past — and the
/// numerals are the *instrument*. Once bedtime passes the countdown gives
/// way to a "wind down" nudge (mirroring the small widget) instead of
/// counting 20-odd hours to *tomorrow's* bedtime.
private struct HomeSloth: View {
    let profile: Profile
    let now: Date

    @State private var breathing = false
    @State private var eyesShut = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Minutes after bedtime during which Home shows the wind-down state.
    private static let windDownWindow = 4 * 60
    /// Minutes before bedtime at which the sloth's eyelids get heavy.
    private static let drowsyLead = 90

    var body: some View {
        let nowMinutes = SleepFormatting.minutes(from: now)
        let sinceBedtime = ((nowMinutes - profile.bedtime) % 1_440 + 1_440) % 1_440
        let untilBedtime = ((profile.bedtime - nowMinutes) % 1_440 + 1_440) % 1_440
        let isPastBedtime = sinceBedtime > 0 && sinceBedtime < Self.windDownWindow
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
                Text(isPastBedtime ? "Bedtime" : "Bedtime in").sectionLabel()
                if isPastBedtime {
                    Text("Wind down")
                        .font(SleepFont.title(26))
                        .foregroundStyle(SleepColor.amber)
                } else {
                    Text(SleepFormatting.countdown(toMinuteOfDay: profile.bedtime, from: now))
                        .font(SleepFont.hero(40))
                        .foregroundStyle(SleepColor.ink)
                        .monospacedDigit()
                }
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
    let streak: Int

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
                if streak > 0 {
                    Text("·")
                        .font(SleepFont.body(13))
                        .foregroundStyle(SleepColor.faint)
                    Label("\(streak)", systemImage: "flame.fill")
                        .font(SleepFont.label(13))
                        .foregroundStyle(SleepColor.gold)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}
