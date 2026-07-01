import SwiftUI

// Immersive sleep mode. True OLED black; only the timer glows, in ember red
// (red preserves night vision). It opens straight into the bare, minimal
// timer — the same collapsed state "Go back to sleep" leaves you in — and
// tapping the screen brings the controls back. "Cancel & go back" leaves
// without logging, for someone who only opened this to peek.

struct SleepModeView: View {
    var store: SleepStore
    let activeSession: ActiveSleepSession

    @State private var now = Date()
    @State private var showControls = false

    private var elapsedMinutes: Int {
        max(0, Int(now.timeIntervalSince(activeSession.start) / 60))
    }

    var body: some View {
        ZStack {
            SleepModeBackground()

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
        // True OLED black — no glow, no gradient, nothing to redraw. Only the
        // ember-red timer text supplies color, preserving night vision.
        Color.black.ignoresSafeArea()
    }
}
