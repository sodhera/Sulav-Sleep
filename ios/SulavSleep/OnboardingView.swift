import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct OnboardingView: View {
    var healthAvailable: Bool
    var onNameFocusChanged: (Bool) -> Void = { _ in }
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
        .onChange(of: step) { _, newStep in
            if newStep != 1 {
                onNameFocusChanged(false)
            }
        }
    }

    @ViewBuilder
    private var currentStep: some View {
        switch step {
        case 0:
            OnboardingIntro()
        case 1:
            NameStep(name: $name, onFocusChanged: onNameFocusChanged)
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
    let onFocusChanged: (Bool) -> Void
    @FocusState private var isFocused: Bool

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
                .focused($isFocused)
                .simultaneousGesture(TapGesture().onEnded {
                    onFocusChanged(true)
                })
                .onSubmit { Keyboard.dismiss() }
                .onChange(of: isFocused) { _, focused in
                    onFocusChanged(focused)
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

            TimeAdjuster(minutes: $minutes)
        }
    }
}

struct TimeAdjuster: View {
    @Binding var minutes: Int

    var body: some View {
        HStack(spacing: SleepSpacing.md) {
            TimeAdjustColumn(
                label: "Hour",
                value: hourBinding.wrappedValue.formatted(),
                incrementLabel: "Increase hour",
                decrementLabel: "Decrease hour",
                onIncrement: { hourBinding.wrappedValue = nextHour },
                onDecrement: { hourBinding.wrappedValue = previousHour }
            )

            Text(":")
                .font(SleepFont.title(24))
                .foregroundStyle(SleepColor.faint)

            TimeAdjustColumn(
                label: "Minute",
                value: String(format: "%02d", minuteBinding.wrappedValue),
                incrementLabel: "Increase minute",
                decrementLabel: "Decrease minute",
                onIncrement: { minuteBinding.wrappedValue = nextMinute },
                onDecrement: { minuteBinding.wrappedValue = previousMinute }
            )

            TimePeriodControl(selection: periodBinding)
        }
        .padding(.horizontal, SleepSpacing.lg)
        .padding(.vertical, SleepSpacing.md)
        .frame(height: 148)
        .frame(maxWidth: .infinity)
        .tint(SleepColor.amber)
        .liquidGlass(cornerRadius: SleepRadius.xl)
    }

    private var normalizedMinutes: Int {
        ((minutes % 1_440) + 1_440) % 1_440
    }

    private var hourBinding: Binding<Int> {
        Binding(
            get: {
                let hour = normalizedMinutes / 60
                let displayHour = hour % 12
                return displayHour == 0 ? 12 : displayHour
            },
            set: { newHour in
                let current = normalizedMinutes
                let oldHour = current / 60
                let minute = current % 60
                let baseHour = newHour == 12 ? 0 : newHour
                let hour = baseHour + (oldHour >= 12 ? 12 : 0)
                minutes = hour * 60 + minute
            }
        )
    }

    private var nextHour: Int {
        let hour = hourBinding.wrappedValue
        return hour == 12 ? 1 : hour + 1
    }

    private var previousHour: Int {
        let hour = hourBinding.wrappedValue
        return hour == 1 ? 12 : hour - 1
    }

    private var minuteBinding: Binding<Int> {
        Binding(
            get: { normalizedMinutes % 60 },
            set: { newMinute in
                let hour = normalizedMinutes / 60
                minutes = hour * 60 + newMinute
            }
        )
    }

    private var nextMinute: Int {
        (minuteBinding.wrappedValue + 1) % 60
    }

    private var previousMinute: Int {
        (minuteBinding.wrappedValue + 59) % 60
    }

    private var periodBinding: Binding<TimePeriod> {
        Binding(
            get: { normalizedMinutes / 60 >= 12 ? .pm : .am },
            set: { newPeriod in
                let current = normalizedMinutes
                let hour12 = (current / 60) % 12
                let minute = current % 60
                minutes = (newPeriod == .pm ? hour12 + 12 : hour12) * 60 + minute
            }
        )
    }
}

private struct TimeAdjustColumn: View {
    let label: String
    let value: String
    let incrementLabel: String
    let decrementLabel: String
    let onIncrement: () -> Void
    let onDecrement: () -> Void

    var body: some View {
        VStack(spacing: SleepSpacing.xs) {
            Button(action: onIncrement) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 44, height: 34)
            }
            .buttonStyle(.plain)
            .foregroundStyle(SleepColor.dim)
            .accessibilityLabel(incrementLabel)

            Text(value)
                .font(SleepFont.hero(34))
                .monospacedDigit()
                .foregroundStyle(SleepColor.ink)
                .frame(width: 68, height: 38)
                .accessibilityLabel(label)
                .accessibilityValue(value)

            Button(action: onDecrement) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 44, height: 34)
            }
            .buttonStyle(.plain)
            .foregroundStyle(SleepColor.dim)
            .accessibilityLabel(decrementLabel)
        }
        .frame(width: 72)
    }
}

private struct TimePeriodControl: View {
    @Binding var selection: TimePeriod

    var body: some View {
        VStack(spacing: SleepSpacing.xs) {
            periodButton(.am)
            periodButton(.pm)
        }
        .frame(width: 72)
    }

    private func periodButton(_ period: TimePeriod) -> some View {
        Button {
            selection = period
        } label: {
            Text(period.rawValue)
                .font(SleepFont.label(13))
                .frame(maxWidth: .infinity, minHeight: 38)
                .foregroundStyle(selection == period ? SleepColor.background : SleepColor.dim)
                .background {
                    Capsule(style: .continuous)
                        .fill(selection == period ? SleepColor.amber : SleepColor.glassFill)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(period == .am ? "AM" : "PM")
        .accessibilityAddTraits(selection == period ? .isSelected : [])
    }
}

private enum TimePeriod: String, CaseIterable, Identifiable {
    case am = "AM"
    case pm = "PM"

    var id: String { rawValue }
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
