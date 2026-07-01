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
                .foregroundStyle(SleepColor.ink)

            Picker("Schedule field", selection: $selectedMode) {
                Text("Bedtime · \(SleepFormatting.clock(draftBedtime))").tag(ScheduleMode.bed)
                Text("Wake · \(SleepFormatting.clock(draftWakeTime))").tag(ScheduleMode.wake)
            }
            .pickerStyle(.segmented)

            DatePicker(
                "",
                selection: Binding(
                    get: { SleepFormatting.date(fromMinutes: selectedMode == .bed ? draftBedtime : draftWakeTime) },
                    set: { date in
                        if selectedMode == .bed { draftBedtime = SleepFormatting.minutes(from: date) }
                        else { draftWakeTime = SleepFormatting.minutes(from: date) }
                    }
                ),
                displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .colorScheme(.dark)
            .tint(SleepColor.amber)

            LiquidPrimaryButton(title: "Save schedule", systemImage: "checkmark") {
                Haptics.soft()
                onSave(draftBedtime, draftWakeTime)
            }
        }
    }
}

struct SettingsSheet: View {
    let profile: Profile
    let healthState: HealthSyncState
    let onSaveName: (String) -> Void
    let onOpenSchedule: () -> Void
    let onToggleHealth: (Bool) -> Void
    let onReset: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var healthOn: Bool

    init(
        profile: Profile,
        healthState: HealthSyncState,
        onSaveName: @escaping (String) -> Void,
        onOpenSchedule: @escaping () -> Void,
        onToggleHealth: @escaping (Bool) -> Void,
        onReset: @escaping () -> Void
    ) {
        self.profile = profile
        self.healthState = healthState
        self.onSaveName = onSaveName
        self.onOpenSchedule = onOpenSchedule
        self.onToggleHealth = onToggleHealth
        self.onReset = onReset
        _name = State(initialValue: profile.name)
        _healthOn = State(initialValue: healthState == .connected)
    }

    var body: some View {
        LiquidSheetContainer {
            Text("Settings")
                .font(SleepFont.title(20))
                .foregroundStyle(SleepColor.ink)

            VStack(alignment: .leading, spacing: SleepSpacing.sm) {
                Text("Name")
                    .font(SleepFont.body(13))
                    .foregroundStyle(SleepColor.muted)
                TextField("Your name", text: $name)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled(true)
                    .font(SleepFont.label(18))
                    .foregroundStyle(SleepColor.ink)
                    .tint(SleepColor.amber)
                    .padding(.vertical, SleepSpacing.md)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(SleepColor.hairline).frame(height: 1)
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
                    Text("\(SleepFormatting.clock(profile.bedtime)) – \(SleepFormatting.clock(profile.wakeTime))")
                        .font(SleepFont.body(15))
                        .foregroundStyle(SleepColor.muted)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(SleepColor.faint)
                }
                .padding(.vertical, SleepSpacing.md)
            }
            .buttonStyle(.plain)

            healthRow

            Button(role: .destructive) {
                onReset()
                dismiss()
            } label: {
                Text("Reset all data")
                    .font(SleepFont.label(15))
                    .foregroundStyle(SleepColor.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, SleepSpacing.md)
            }
            .buttonStyle(.plain)

            Text("Pixel art by CraftPix.net · OGA-BY 3.0")
                .font(SleepFont.body(11))
                .foregroundStyle(SleepColor.faint)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onDisappear(perform: saveName)
    }

    @ViewBuilder
    private var healthRow: some View {
        if healthState == .unavailable {
            HStack {
                Text("Apple Health")
                    .font(SleepFont.body(16))
                    .foregroundStyle(SleepColor.dim)
                Spacer()
                Text("Unavailable")
                    .font(SleepFont.body(14))
                    .foregroundStyle(SleepColor.faint)
            }
            .padding(.vertical, SleepSpacing.md)
        } else {
            Toggle(isOn: $healthOn) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Apple Health")
                        .font(SleepFont.body(16))
                        .foregroundStyle(SleepColor.dim)
                    Text("Sync your real sleep history both ways")
                        .font(SleepFont.body(12))
                        .foregroundStyle(SleepColor.faint)
                }
            }
            .tint(SleepColor.amber)
            .padding(.vertical, SleepSpacing.sm)
            .onChange(of: healthOn) { _, newValue in
                Haptics.soft()
                onToggleHealth(newValue)
            }
        }
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
