import SwiftUI

// Immersive sleep mode. True OLED black; everything lit is ember red (red
// preserves night vision). The screen is the night-side sibling of Home's
// bedtime ring: a thin ember arc fills from sleep start toward the scheduled
// wake time, with the elapsed timer at its center and the wake target
// beneath. It opens straight into this collapsed instrument — the same state
// "Go back to sleep" leaves you in — and tapping the screen brings the
// controls up. "Cancel & go back" leaves without logging, for someone who
// only opened this to peek.

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
            // ember-red pixels are lit, preserving night vision.
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
                            .shadow(color: SleepColor.crimsonGlow.opacity(0.45), radius: 14)
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
                        EmberButton(title: "Wake up", systemImage: "sunrise.fill", filled: true) {
                            Haptics.success()
                            store.wakeUp()
                        }
                        EmberButton(title: "Go back to sleep", systemImage: "moon.fill", filled: false) {
                            Haptics.soft()
                            withAnimation(.easeInOut(duration: 0.4)) { showControls = false }
                        }

                        Button {
                            Haptics.soft()
                            store.cancelSleep()
                        } label: {
                            Text("Cancel & go back")
                                .font(SleepFont.body(15))
                                .foregroundStyle(SleepColor.emberDim)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.plain)
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
            guard !showControls else { return }
            withAnimation(.easeInOut(duration: 0.4)) { showControls = true }
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
/// thin and dim for night vision — a faint ember track, a crimson→ember fill
/// tracking the planned night, and a small glowing tip. The instrument reads
/// "how far into the night am I" at half-asleep glance distance.
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
                        colors: [SleepColor.crimsonGlow, SleepColor.ember],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(135))
                .shadow(color: SleepColor.crimsonGlow.opacity(0.5), radius: 8)

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

// MARK: - Buttons

private struct EmberButton: View {
    let title: String
    var systemImage: String?
    let filled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text(title).font(SleepFont.label(16))
            } icon: {
                if let systemImage { Image(systemName: systemImage) }
            }
            .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(EmberButtonStyle(filled: filled))
    }
}

private struct EmberButtonStyle: ButtonStyle {
    var filled: Bool

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .foregroundStyle(filled ? SleepColor.sleepBlack : SleepColor.ember)
            .padding(.horizontal, SleepSpacing.lg)
            .background {
                Capsule(style: .continuous)
                    .fill(filled ? AnyShapeStyle(emberFill) : AnyShapeStyle(Color.white.opacity(0.04)))
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(filled ? Color.clear : SleepColor.emberDim, lineWidth: 1)
            }
            .shadow(color: SleepColor.crimsonGlow.opacity(filled ? (pressed ? 0.3 : 0.55) : 0),
                    radius: pressed ? 10 : 20, y: pressed ? 3 : 8)
            .scaleEffect(pressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.18), value: pressed)
    }

    private var emberFill: LinearGradient {
        LinearGradient(colors: [SleepColor.ember, SleepColor.crimsonGlow],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
