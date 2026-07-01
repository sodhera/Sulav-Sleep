import SwiftUI

struct OnboardingView: View {
    let onDone: (String, Int, Int) -> Void

    @State private var step = 0
    @State private var name = ""
    @State private var bedtime = 22 * 60 + 30
    @State private var wakeTime = 6 * 60 + 30

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: SleepSpacing.lg) {
                CrescentMoon(size: 96)
                StepDots(step: step, total: 4)
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
                default:
                    TimeStep(
                        title: "And when do you wake?",
                        subtitle: "Around \(SleepFormatting.clock(wakeTime))",
                        minutes: $wakeTime
                    )
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, SleepSpacing.xxl)

            Spacer()

            VStack(spacing: SleepSpacing.md) {
                LiquidPrimaryButton(
                    title: primaryTitle,
                    systemImage: step == 3 ? "checkmark" : "arrow.right"
                ) {
                    advance()
                }

                if step > 0 {
                    Button("Back") {
                        step -= 1
                    }
                    .font(SleepFont.body(14))
                    .foregroundStyle(SleepColor.quiet)
                    .frame(height: 44)
                }
            }
            .padding(.horizontal, SleepSpacing.xxl)
            .padding(.bottom, SleepSpacing.xxl)
        }
        .safeAreaPadding(.top)
        .safeAreaPadding(.bottom)
    }

    private var primaryTitle: String {
        switch step {
        case 0: "Continue"
        case 1: "Next"
        case 2: "Next"
        default: "Start sleeping well"
        }
    }

    private func advance() {
        if step == 1, name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return
        }
        if step < 3 {
            step += 1
        } else {
            onDone(name, bedtime, wakeTime)
        }
    }
}

private struct OnboardingIntro: View {
    var body: some View {
        VStack(spacing: SleepSpacing.md) {
            Text("Sulav Sleep")
                .font(SleepFont.hero(32))
                .foregroundStyle(SleepColor.white)
            Text("A calmer night. Set a bedtime, quiet the phone, and wake to a gentle picture of your sleep.")
                .font(SleepFont.body(16))
                .foregroundStyle(SleepColor.dim)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .frame(maxWidth: 310)
        }
    }
}

private struct NameStep: View {
    @Binding var name: String

    var body: some View {
        VStack(spacing: SleepSpacing.lg) {
            Text("What should we call you?")
                .font(SleepFont.title(24))
                .foregroundStyle(SleepColor.white)
                .multilineTextAlignment(.center)

            TextField("Your name", text: $name)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled(true)
                .submitLabel(.done)
                .font(SleepFont.title(22))
                .foregroundStyle(SleepColor.white)
                .multilineTextAlignment(.center)
                .padding(.vertical, SleepSpacing.md)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(SleepColor.hairline)
                        .frame(height: 1)
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
                    .foregroundStyle(SleepColor.white)
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(SleepFont.body(14))
                    .foregroundStyle(SleepColor.quiet)
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
            .liquidGlass(cornerRadius: SleepRadius.xl)
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
                    .fill(index == step ? SleepColor.white : SleepColor.hairline)
                    .frame(width: index == step ? 22 : 7, height: 7)
                    .animation(.snappy(duration: 0.2), value: step)
            }
        }
    }
}

struct CrescentMoon: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.05))
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
                .mask(alignment: .topTrailing) {
                    CrescentMask()
                }
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
