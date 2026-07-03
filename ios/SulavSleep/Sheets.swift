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

            TimeAdjuster(
                minutes: Binding(
                    get: { selectedMode == .bed ? draftBedtime : draftWakeTime },
                    set: { minutes in
                        if selectedMode == .bed { draftBedtime = minutes }
                        else { draftWakeTime = minutes }
                    }
                )
            )

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
    let onOpenLockdown: () -> Void
    let onReset: () -> Void
    let onSignOut: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String

    init(
        profile: Profile,
        healthState: HealthSyncState,
        onSaveName: @escaping (String) -> Void,
        onOpenSchedule: @escaping () -> Void,
        onToggleHealth: @escaping (Bool) -> Void,
        onOpenLockdown: @escaping () -> Void,
        onReset: @escaping () -> Void,
        onSignOut: @escaping () -> Void
    ) {
        self.profile = profile
        self.healthState = healthState
        self.onSaveName = onSaveName
        self.onOpenSchedule = onOpenSchedule
        self.onToggleHealth = onToggleHealth
        self.onOpenLockdown = onOpenLockdown
        self.onReset = onReset
        self.onSignOut = onSignOut
        _name = State(initialValue: profile.name)
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

            Button {
                saveName()
                onOpenLockdown()
            } label: {
                HStack {
                    Text("Sleep lockdown")
                        .font(SleepFont.body(16))
                        .foregroundStyle(SleepColor.dim)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(SleepColor.faint)
                }
                .padding(.vertical, SleepSpacing.md)
            }
            .buttonStyle(.plain)

            Button {
                onSignOut()
                dismiss()
            } label: {
                Text("Sign out")
                    .font(SleepFont.label(15))
                    .foregroundStyle(SleepColor.dim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, SleepSpacing.md)
            }
            .buttonStyle(.plain)

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
            // Derived from the store's actual connection state, not a local
            // optimistic mirror: HealthKit can report "denied" after the sheet,
            // and the toggle must reflect that rather than staying stuck on.
            Toggle(isOn: Binding(
                get: { healthState == .connected },
                set: { newValue in
                    Haptics.soft()
                    onToggleHealth(newValue)
                }
            )) {
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
