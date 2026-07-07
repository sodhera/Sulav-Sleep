import SwiftUI

// Immersive sleep mode. True OLED black; everything lit is ember — the day's
// amber banked down to coals (warm, long-wavelength light that is kind to
// night vision and reads as the same identity as the rest of the app). The
// screen is the night-side sibling of Home's bedtime ring: a thin ember arc
// fills from sleep start toward the scheduled wake time, with the elapsed
// timer at its center and the wake target beneath. It opens straight into
// this collapsed instrument — the same state "Back to sleep" leaves you in —
// and tapping the screen brings the controls up (tapping the dark collapses
// them again).
//
// Control grammar: deliberate exits are *held*, harmless returns are taps.
// Entering sleep took a deliberate slide, so ending the night takes a
// deliberate hold — but one that needs zero precision from a half-asleep
// hand. "Back to sleep" is a plain tap because it costs nothing. Cancel
// (which drops the lockdown without logging a night) is a quieter, shorter
// hold.

struct SleepModeView: View {
    var store: SleepStore
    let activeSession: ActiveSleepSession

    @State private var now = Date()
    @State private var showControls = false

    private var elapsedMinutes: Int {
        max(0, Int(now.timeIntervalSince(activeSession.start) / 60))
    }

    /// Fraction of the planned night (sleep start → scheduled wake) already
    /// behind you. Clamped: oversleeping simply holds the ring full.
    private var nightProgress: Double {
        guard let profile = store.profile else { return 0 }
        let total = SleepMath.windowMinutes(
            bedtime: SleepFormatting.minutes(from: activeSession.start),
            wakeTime: profile.wakeTime
        )
        guard total > 0 else { return 0 }
        return min(1, now.timeIntervalSince(activeSession.start) / 60 / Double(total))
    }

    private var wakeClock: String? {
        store.profile.map { SleepFormatting.clock($0.wakeTime) }
    }

    var body: some View {
        ZStack {
            // True OLED black — nothing to redraw behind the instrument. Only
            // ember pixels are lit, preserving night vision.
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                NightRing(progress: nightProgress) {
                    VStack(spacing: SleepSpacing.sm) {
                        Text("Asleep")
                            .font(SleepFont.label(12))
                            .tracking(1.6)
                            .textCase(.uppercase)
                            .foregroundStyle(SleepColor.emberDim)

                        Text("\(elapsedMinutes / 60)h \(String(format: "%02d", elapsedMinutes % 60))m")
                            .font(.system(size: 48, weight: .semibold, design: .default))
                            .foregroundStyle(SleepColor.ember)
                            .monospacedDigit()
                            .shadow(color: SleepColor.emberGlow.opacity(0.45), radius: 14)
                            .contentTransition(.numericText())
                            .accessibilityLabel("Asleep for \(elapsedMinutes / 60) hours \(elapsedMinutes % 60) minutes")

                        if let wakeClock {
                            HStack(spacing: SleepSpacing.xs) {
                                Image(systemName: "sunrise.fill")
                                    .font(.system(size: 11, weight: .medium))
                                Text(wakeClock)
                                    .font(SleepFont.body(14))
                                    .monospacedDigit()
                            }
                            .foregroundStyle(SleepColor.emberDim)
                        }
                    }
                }

                Spacer()

                if showControls {
                    VStack(spacing: SleepSpacing.md) {
                        EmberHoldButton(
                            title: "Hold to wake",
                            systemImage: "sunrise.fill",
                            prominent: true,
                            duration: 1.2
                        ) {
                            Haptics.success()
                            store.wakeUp()
                        }

                        // A tap, not a hold: returning to sleep costs nothing.
                        Button {
                            Haptics.soft()
                            withAnimation(.easeInOut(duration: 0.4)) { showControls = false }
                        } label: {
                            Label {
                                Text("Back to sleep").font(SleepFont.label(16))
                            } icon: {
                                Image(systemName: "moon.fill")
                            }
                            .foregroundStyle(SleepColor.ember)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background {
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(0.04))
                            }
                            .overlay {
                                Capsule(style: .continuous)
                                    .stroke(SleepColor.emberDim, lineWidth: 1)
                            }
                            .contentShape(Capsule(style: .continuous))
                        }
                        .buttonStyle(.plain)

                        EmberHoldButton(
                            title: "Hold to cancel",
                            prominent: false,
                            duration: 0.8
                        ) {
                            Haptics.rigid()
                            store.cancelSleep()
                        }
                        .padding(.top, SleepSpacing.sm)
                    }
                    .padding(.horizontal, SleepSpacing.xxl)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else {
                    BreathingHint(text: "Tap to wake")
                        .transition(.opacity)
                        .padding(.bottom, SleepSpacing.huge)
                }
            }
            .padding(.bottom, SleepSpacing.huge)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // The dark itself toggles the controls: tap to reveal, tap again
            // to tuck them away. The buttons consume their own touches.
            Haptics.soft()
            withAnimation(.easeInOut(duration: 0.4)) { showControls.toggle() }
        }
        .task(id: activeSession.start) {
            while !Task.isCancelled {
                now = Date()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .statusBarHidden(true)
    }
}

// MARK: - Night ring

/// The ember sibling of Home's bedtime ring: the same 270° gauge arc, but
/// thin and dim for night vision — a faint ember track, a deep→bright ember
/// fill tracking the planned night, and a small glowing tip. The instrument
/// reads "how far into the night am I" at half-asleep glance distance.
private struct NightRing<Content: View>: View {
    let progress: Double
    @ViewBuilder var content: Content

    /// The arc spans 270°, leaving a gap at the bottom — same language as
    /// Home's bedtime ring.
    private static var arcSpan: Double { 0.75 }

    private let size: CGFloat = 272
    private let lineWidth: CGFloat = 5

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: Self.arcSpan)
                .stroke(
                    SleepColor.emberDim.opacity(0.22),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(135))

            Circle()
                .trim(from: 0, to: Self.arcSpan * progress)
                .stroke(
                    AngularGradient(
                        colors: [SleepColor.emberGlow, SleepColor.ember],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(135))
                .shadow(color: SleepColor.emberGlow.opacity(0.5), radius: 8)

            tipMarker

            content
        }
        .frame(width: size, height: size)
        .animation(.easeInOut(duration: 0.6), value: progress)
    }

    /// The small ember dot riding the arc tip — "you are here in the night".
    private var tipMarker: some View {
        let angle = Angle.degrees(135 + 270 * progress)
        let radius = (size - lineWidth) / 2
        return Circle()
            .fill(SleepColor.ember)
            .frame(width: 11, height: 11)
            .shadow(color: SleepColor.ember.opacity(0.8), radius: 6)
            .offset(
                x: radius * CGFloat(cos(angle.radians)),
                y: radius * CGFloat(sin(angle.radians))
            )
    }
}

// MARK: - Hint

/// The wake hint breathes very slowly — a barely-there invitation that never
/// demands attention from someone half-asleep.
private struct BreathingHint: View {
    let text: String

    @State private var bright = false

    var body: some View {
        Text(text)
            .font(SleepFont.body(13))
            .foregroundStyle(SleepColor.emberDim)
            .opacity(bright ? 0.85 : 0.4)
            .animation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true), value: bright)
            .onAppear { bright = true }
    }
}

// MARK: - Hold button

/// Press-and-hold action for the half-asleep hand: zero precision required,
/// impossible to fire with a stray tap. A rigid tap answers the press, a
/// ratchet of medium ticks climbs while the ember fill sweeps across the
/// capsule, and a heavy knock lands at completion. Released early, the fill
/// sighs back with a soft tap.
private struct EmberHoldButton: View {
    let title: String
    var systemImage: String?
    let prominent: Bool
    var duration: Double
    let onComplete: () -> Void

    @State private var progress: Double = 0
    @State private var isHolding = false
    @State private var isComplete = false
    @State private var lastTick = -1
    @State private var holdTask: Task<Void, Never>?

    /// Detents the hold ratchets through on its way to completion.
    private let hapticDetents = 5.0

    private var height: CGFloat { prominent ? 60 : 44 }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Base
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(prominent ? 0.05 : 0))
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(
                                prominent ? SleepColor.emberDim : Color.clear,
                                lineWidth: 1
                            )
                    }

                // Ember fill sweeping with the hold. Deep tones so the ember
                // label stays readable until the completion flash.
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: isComplete
                                ? [SleepColor.ember, SleepColor.emberGlow]
                                : [SleepColor.emberDeep, SleepColor.emberGlow],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, geo.size.width * progress))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipShape(Capsule(style: .continuous))
                    .opacity(prominent ? 1 : 0.55)

                Label {
                    Text(title).font(SleepFont.label(prominent ? 16 : 15))
                } icon: {
                    if let systemImage { Image(systemName: systemImage) }
                }
                .foregroundStyle(labelColor)
            }
            .shadow(
                color: SleepColor.emberGlow.opacity(prominent ? 0.2 + progress * 0.5 : progress * 0.3),
                radius: 12 + progress * 10,
                y: 4
            )
            .scaleEffect(isHolding ? 0.98 : 1)
            .animation(.snappy(duration: 0.18), value: isHolding)
            .contentShape(Capsule(style: .continuous))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in startHold() }
                    .onEnded { _ in endHold() }
            )
        }
        .frame(height: height)
        .onDisappear { holdTask?.cancel() }
        .accessibilityLabel(title)
        .accessibilityHint("Touch and hold to confirm")
    }

    private var labelColor: Color {
        if isComplete { return SleepColor.sleepBlack }
        return prominent ? SleepColor.ember : SleepColor.emberDim
    }

    private func startHold() {
        guard !isHolding, !isComplete else { return }
        isHolding = true
        lastTick = -1
        Haptics.rigid()
        holdTask = Task { @MainActor in
            let start = Date()
            while !Task.isCancelled {
                let p = min(1, Date().timeIntervalSince(start) / duration)
                progress = p

                let step = Int(p * hapticDetents)
                if step != lastTick {
                    lastTick = step
                    if step > 0 { Haptics.tick(intensity: 0.45 + p * 0.55) }
                }

                if p >= 1 {
                    isComplete = true
                    Haptics.heavy()
                    onComplete()
                    break
                }
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }

    private func endHold() {
        guard !isComplete else { return }
        holdTask?.cancel()
        isHolding = false
        lastTick = -1
        if progress > 0.02 { Haptics.soft() }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            progress = 0
        }
    }
}
