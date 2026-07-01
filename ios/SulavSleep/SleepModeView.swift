import SwiftUI

// Immersive sleep mode. Pitch black with layered reds (red preserves night
// vision). The timer is the only text. Controls are visible by default; "Go
// back to sleep" collapses to the bare timer, and tapping the screen brings the
// controls back. "Cancel & go back" leaves without logging, for someone who
// only opened this to peek.

struct SleepModeView: View {
    var store: SleepStore
    let activeSession: ActiveSleepSession

    @State private var now = Date()
    @State private var showControls = true

    private var elapsedMinutes: Int {
        max(0, Int(now.timeIntervalSince(activeSession.start) / 60))
    }

    var body: some View {
        ZStack {
            SleepModeBackground()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.4)) { showControls = true }
                }

            VStack(spacing: SleepSpacing.huge) {
                Spacer()

                Text("\(elapsedMinutes / 60)h \(String(format: "%02d", elapsedMinutes % 60))m")
                    .font(.system(size: 68, weight: .semibold, design: .default))
                    .foregroundStyle(SleepColor.ember)
                    .monospacedDigit()
                    .shadow(color: SleepColor.crimsonGlow.opacity(0.6), radius: 24)
                    .contentTransition(.numericText())
                    .accessibilityLabel("Asleep for \(elapsedMinutes / 60) hours \(elapsedMinutes % 60) minutes")

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
                    Text("Tap to wake")
                        .font(SleepFont.body(13))
                        .foregroundStyle(SleepColor.emberDim.opacity(0.7))
                        .transition(.opacity)
                        .padding(.bottom, SleepSpacing.huge)
                }
            }
            .padding(.bottom, SleepSpacing.huge)
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

private struct SleepModeBackground: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                // Pitch-black base.
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(SleepColor.sleepBlack))

                // Layered red glows in different tones, each pulsing slowly at
                // its own rate — "different versions of red all throughout".
                let glows: [(CGFloat, CGFloat, CGFloat, Color, Double)] = [
                    (0.20, 0.18, 340, SleepColor.crimsonGlow, 13),
                    (0.85, 0.32, 300, SleepColor.bloodGlow, 17),
                    (0.50, 0.92, 460, SleepColor.crimsonGlow, 11),
                    (0.12, 0.78, 280, SleepColor.bloodGlow, 19),
                ]
                for (i, g) in glows.enumerated() {
                    let pulse = 1 + 0.06 * sin(t / g.4 + Double(i))
                    let r = g.2 * pulse
                    let center = CGPoint(x: size.width * g.0, y: size.height * g.1)
                    context.fill(
                        Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
                        with: .radialGradient(
                            Gradient(colors: [g.3.opacity(0.5 * pulse), .clear]),
                            center: center, startRadius: 0, endRadius: r
                        )
                    )
                }
            }
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
        .background(SleepColor.sleepBlack.ignoresSafeArea())
    }
}
