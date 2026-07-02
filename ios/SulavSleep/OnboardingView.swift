import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

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

            currentStep
                .frame(maxWidth: .infinity)
                .padding(.horizontal, SleepSpacing.xxl)

            Spacer()

            actions
                .padding(.horizontal, SleepSpacing.xxl)
                .padding(.bottom, SleepSpacing.xxl)
        }
        .safeAreaPadding(.top)
        .safeAreaPadding(.bottom)

    }

    @ViewBuilder
    private var currentStep: some View {
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
                Button("Back") { setStep(step - 1) }
                    .font(SleepFont.body(15))
                    .foregroundStyle(SleepColor.muted)
                    .frame(height: 44)
            } else if step == lastStep && healthAvailable {
                Button("Back") { setStep(step - 1) }
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
        let nextStep = min(step + 1, lastStep)
        if step == 1 {
            Keyboard.dismiss()
            Task { @MainActor in
                await Task.yield()
                setStep(nextStep)
            }
            return
        }
        setStep(nextStep)
    }

    private func finish(connectHealth: Bool) {
        Keyboard.dismiss()
        Haptics.success()
        onDone(name, bedtime, wakeTime, connectHealth)
    }

    private func setStep(_ nextStep: Int) {
        withAnimation(.easeInOut(duration: 0.22)) {
            step = max(0, min(lastStep, nextStep))
        }
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
                .onSubmit { Keyboard.dismiss() }
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

            TimeAdjuster(minutes: $minutes)
        }
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

private enum Keyboard {
    static func dismiss() {
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
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
