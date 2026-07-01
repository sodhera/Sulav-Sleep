import SwiftUI

struct ScheduleSheet: View {
    let bedtime: Int
    let wakeTime: Int
    let onSave: (Int, Int) -> Void

    @State private var selectedMode: ScheduleMode = .bed
    @State private var draftBedtime: Int
    @State private var draftWakeTime: Int

    init(bedtime: Int, wakeTime: Int, onSave: @escaping (Int, Int) -> Void) {
        self.bedtime = bedtime
        self.wakeTime = wakeTime
        self.onSave = onSave
        _draftBedtime = State(initialValue: bedtime)
        _draftWakeTime = State(initialValue: wakeTime)
    }

    var body: some View {
        LiquidSheetContainer {
            Text("Sleep schedule")
                .font(SleepFont.title(20))
                .foregroundStyle(SleepColor.white)

            Picker("Schedule field", selection: $selectedMode) {
                Text("Bedtime · \(SleepFormatting.clock(draftBedtime))").tag(ScheduleMode.bed)
                Text("Wake · \(SleepFormatting.clock(draftWakeTime))").tag(ScheduleMode.wake)
            }
            .pickerStyle(.segmented)

            DatePicker(
                "",
                selection: Binding(
                    get: {
                        SleepFormatting.date(fromMinutes: selectedMode == .bed ? draftBedtime : draftWakeTime)
                    },
                    set: { date in
                        if selectedMode == .bed {
                            draftBedtime = SleepFormatting.minutes(from: date)
                        } else {
                            draftWakeTime = SleepFormatting.minutes(from: date)
                        }
                    }
                ),
                displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .colorScheme(.dark)

            LiquidPrimaryButton(title: "Save schedule", systemImage: "checkmark") {
                onSave(draftBedtime, draftWakeTime)
            }
        }
    }
}

struct SettingsSheet: View {
    let profile: Profile
    let onSaveName: (String) -> Void
    let onOpenSchedule: () -> Void
    let onReset: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String

    init(
        profile: Profile,
        onSaveName: @escaping (String) -> Void,
        onOpenSchedule: @escaping () -> Void,
        onReset: @escaping () -> Void
    ) {
        self.profile = profile
        self.onSaveName = onSaveName
        self.onOpenSchedule = onOpenSchedule
        self.onReset = onReset
        _name = State(initialValue: profile.name)
    }

    var body: some View {
        LiquidSheetContainer {
            Text("Settings")
                .font(SleepFont.title(20))
                .foregroundStyle(SleepColor.white)

            VStack(alignment: .leading, spacing: SleepSpacing.sm) {
                Text("Name")
                    .font(SleepFont.body(13))
                    .foregroundStyle(SleepColor.quiet)
                TextField("Your name", text: $name)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled(true)
                    .font(SleepFont.label(18))
                    .foregroundStyle(SleepColor.white)
                    .padding(.vertical, SleepSpacing.md)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(SleepColor.hairline)
                            .frame(height: 1)
                    }
                    .onSubmit(saveName)
            }

            Button {
                saveName()
                onOpenSchedule()
            } label: {
                HStack {
                    Text("Sleep schedule")
                        .font(SleepFont.body(16))
                        .foregroundStyle(SleepColor.dim)
                    Spacer()
                    Text("\(SleepFormatting.clock(profile.bedtime)) -> \(SleepFormatting.clock(profile.wakeTime))")
                        .font(SleepFont.body(15))
                        .foregroundStyle(SleepColor.quiet)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SleepColor.faint)
                }
                .padding(.vertical, SleepSpacing.md)
            }
            .buttonStyle(.plain)

            Button(role: .destructive) {
                onReset()
                dismiss()
            } label: {
                Text("Reset all data")
                    .font(SleepFont.label(15))
                    .foregroundStyle(Color(red: 240 / 255, green: 138 / 255, blue: 155 / 255))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, SleepSpacing.md)
            }
            .buttonStyle(.plain)
        }
        .onDisappear(perform: saveName)
    }

    private func saveName() {
        onSaveName(name)
    }
}

private enum ScheduleMode: String, CaseIterable, Identifiable {
    case bed
    case wake

    var id: String { rawValue }
}
