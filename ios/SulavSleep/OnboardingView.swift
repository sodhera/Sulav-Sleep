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
            Spacer()

            // All steps are built once, up front, and shown/hidden with
            // opacity rather than swapped via `switch`. Lazily constructing a
            // step (especially the wheel DatePickers) the first time it's
            // shown caused a visible hitch right as the "Next" transition
            // played; building them eagerly moves that cost to first appear,
            // before the user is interacting.
            ZStack {
                OnboardingIntro()
                    .opacity(step == 0 ? 1 : 0)
                    .allowsHitTesting(step == 0)
                    .accessibilityHidden(step != 0)
                NameStep(name: $name)
                    .opacity(step == 1 ? 1 : 0)
                    .allowsHitTesting(step == 1)
                    .accessibilityHidden(step != 1)
                TimeStep(
                    title: "When do you usually sleep?",
                    subtitle: "Around \(SleepFormatting.clock(bedtime))",
                    minutes: $bedtime
                )
                .opacity(step == 2 ? 1 : 0)
                .allowsHitTesting(step == 2)
                .accessibilityHidden(step != 2)
                TimeStep(
                    title: "And when do you wake?",
                    subtitle: "Around \(SleepFormatting.clock(wakeTime))",
                    minutes: $wakeTime
                )
                .opacity(step == 3 ? 1 : 0)
                .allowsHitTesting(step == 3)
                .accessibilityHidden(step != 3)
                HealthStep(available: healthAvailable)
                    .opacity(step == 4 ? 1 : 0)
                    .allowsHitTesting(step == 4)
                    .accessibilityHidden(step != 4)
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
