import SwiftUI

struct OnboardingView: View {
    var healthAvailable: Bool
    let onDone: (String, Int, Int, Bool) -> Void

    @State private var step = 0
    @State private var name = ""
    @State private var bedtime = 22 * 60 + 30
    @State private var wakeTime = 6 * 60 + 30

    private let lastStep = 4

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: SleepSpacing.lg) {
                CrescentMoon(size: 92)
                StepDots(step: step, total: lastStep + 1)
            }
            .padding(.top, SleepSpacing.huge)

            Spacer()

            VStack(spacing: SleepSpacing.xl) {
                switch step {
                case 0:
                    OnboardingIntro()
                case 1:
                    NameStep(name: $name)
                case 2:
                    TimeStep(
                        title: "When do you usually sleep?",
                        subtitle: "Around \(SleepFormatting.clock(bedtime))",
                        minutes: $bedtime
                    )
                case 3:
                    TimeStep(
                        title: "And when do you wake?",
                        subtitle: "Around \(SleepFormatting.clock(wakeTime))",
                        minutes: $wakeTime
                    )
                default:
                    HealthStep(available: healthAvailable)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, SleepSpacing.xxl)
            .animation(.easeInOut(duration: 0.25), value: step)

            Spacer()

            actions
                .padding(.horizontal, SleepSpacing.xxl)
                .padding(.bottom, SleepSpacing.xxl)
        }
        .safeAreaPadding(.top)
        .safeAreaPadding(.bottom)
    }

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: SleepSpacing.md) {
            if step == lastStep {
                if healthAvailable {
                    LiquidPrimaryButton(title: "Connect Apple Health", systemImage: "heart.fill") {
                        finish(connectHealth: true)
                    }
                    Button("Maybe later") { finish(connectHealth: false) }
                        .font(SleepFont.body(15))
                        .foregroundStyle(SleepColor.dim)
                        .frame(height: 44)
                } else {
                    LiquidPrimaryButton(title: "Start sleeping well", systemImage: "checkmark") {
                        finish(connectHealth: false)
                    }
                }
            } else {
                LiquidPrimaryButton(title: primaryTitle, systemImage: "arrow.right") {
                    advance()
                }
            }

            if step > 0 && step != lastStep {
                Button("Back") { withAnimation { step -= 1 } }
                    .font(SleepFont.body(15))
                    .foregroundStyle(SleepColor.muted)
                    .frame(height: 44)
            } else if step == lastStep && healthAvailable {
                Button("Back") { withAnimation { step -= 1 } }
                    .font(SleepFont.body(15))
                    .foregroundStyle(SleepColor.muted)
                    .frame(height: 36)
            }
        }
    }

    private var primaryTitle: String {
        switch step {
        case 0: "Begin"
        default: "Next"
        }
    }

    private func advance() {
        if step == 1, name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
        Haptics.soft()
        withAnimation { step += 1 }
    }

    private func finish(connectHealth: Bool) {
        Haptics.success()
        onDone(name, bedtime, wakeTime, connectHealth)
    }
}

private struct OnboardingIntro: View {
    var body: some View {
        VStack(spacing: SleepSpacing.md) {
            Text("Sulav Sleep")
                .font(SleepFont.hero(34))
                .foregroundStyle(SleepColor.ink)
            Text("Set a bedtime. Quiet the phone. Sleep.")
                .font(SleepFont.body(16))
                .foregroundStyle(SleepColor.dim)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
    }
}

private struct NameStep: View {
    @Binding var name: String

    var body: some View {
        VStack(spacing: SleepSpacing.lg) {
            Text("What should we call you?")
                .font(SleepFont.title(24))
                .foregroundStyle(SleepColor.ink)
                .multilineTextAlignment(.center)

            TextField("Your name", text: $name)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled(true)
                .submitLabel(.done)
                .font(SleepFont.title(22))
                .foregroundStyle(SleepColor.ink)
                .multilineTextAlignment(.center)
                .tint(SleepColor.amber)
                .padding(.vertical, SleepSpacing.md)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(SleepColor.hairline).frame(height: 1)
                }
                .accessibilityLabel("Your name")
        }
    }
}

private struct TimeStep: View {
    let title: String
    let subtitle: String
    @Binding var minutes: Int

    var body: some View {
        VStack(spacing: SleepSpacing.xl) {
            VStack(spacing: SleepSpacing.sm) {
                Text(title)
                    .font(SleepFont.title(24))
                    .foregroundStyle(SleepColor.ink)
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(SleepFont.body(14))
                    .foregroundStyle(SleepColor.muted)
            }

            DatePicker(
                "",
                selection: Binding(
                    get: { SleepFormatting.date(fromMinutes: minutes) },
                    set: { minutes = SleepFormatting.minutes(from: $0) }
                ),
                displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .colorScheme(.dark)
            .tint(SleepColor.amber)
            .liquidGlass(cornerRadius: SleepRadius.xl)
        }
    }
}

private struct HealthStep: View {
    let available: Bool

    var body: some View {
        VStack(spacing: SleepSpacing.lg) {
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(SleepColor.amber)

            Text(available ? "Connect Apple Health" : "You're all set")
                .font(SleepFont.title(24))
                .foregroundStyle(SleepColor.ink)
                .multilineTextAlignment(.center)

            Text(available
                 ? "Sync your real sleep both ways. Change it anytime in Settings."
                 : "Log a night and your reports fill in. No sample data, ever.")
                .font(SleepFont.body(15))
                .foregroundStyle(SleepColor.dim)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .frame(maxWidth: 300)
        }
    }
}

private struct StepDots: View {
    let step: Int
    let total: Int

    var body: some View {
        HStack(spacing: SleepSpacing.sm) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index == step ? SleepColor.amber : SleepColor.hairline)
                    .frame(width: index == step ? 22 : 7, height: 7)
                    .animation(.snappy(duration: 0.25), value: step)
            }
        }
    }
}

struct CrescentMoon: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(SleepColor.moon.opacity(0.06))
                .frame(width: size, height: size)
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.white, SleepColor.moon],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size * 0.70, height: size * 0.70)
                .mask(alignment: .topTrailing) { CrescentMask() }
                .shadow(color: SleepColor.amber.opacity(0.18), radius: 18)
        }
    }
}

private struct CrescentMask: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(ellipseIn: CGRect(origin: .zero, size: size)), with: .color(.white))
            context.blendMode = .destinationOut
            context.fill(
                Path(ellipseIn: CGRect(x: size.width * 0.37, y: -size.height * 0.13, width: size.width, height: size.height)),
                with: .color(.black)
            )
        }
    }
}
