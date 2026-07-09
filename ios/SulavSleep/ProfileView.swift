import SwiftUI

// The Profile tab is the app's single "about you" surface: identity plus the
// sleep record (weekly chart, averages, night history). Configuration lives in
// a separate `SettingsModal`, opened from the gear top-right as a collapsible
// full-height sheet, so the tab body stays clean. There is deliberately no
// destructive "reset all data" action; the only account-level exits are Sign
// out and (faded, below it) Delete account. Home stays a pure "go to bed"
// screen because of this.

struct ProfileView: View {
    var store: SleepStore
    let profile: Profile

    var body: some View {
        NavigationStack {
            ProfileRootScreen(store: store, profile: profile)
                .navigationDestination(for: ProfileDestination.self) { destination in
                    switch destination {
                    case .allNights:
                        AllNightsScreen(store: store)
                    case .blockedApps:
                        BlockedAppsScreen(store: store)
                    }
                }
        }
    }
}

enum ProfileDestination: Hashable {
    case allNights
    case blockedApps
}

// MARK: - Shared page scaffold

/// Every Profile screen sits on the living night scene with a transparent
/// scroll. The system navigation bar is hidden; sub-pages navigate back with
/// the round glass chevron, matching onboarding.
struct SceneScreen<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            SleepBackground(showsMoon: true)
            SceneReadabilityScrim()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    content
                }
                .padding(.horizontal, SleepSpacing.xxl)
                .padding(.bottom, 140)
            }
            .safeAreaPadding(.top)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// Editorial sub-page header: glass back chevron above a left-aligned title,
/// the same chrome language as the onboarding questionnaire.
struct SubpageHeader: View {
    let title: String
    var subtitle: String?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: SleepSpacing.xl) {
            GlassBackButton { dismiss() }
            VStack(alignment: .leading, spacing: SleepSpacing.sm) {
                Text(title)
                    .font(SleepFont.hero(28))
                    .foregroundStyle(SleepColor.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(SleepFont.body(15))
                        .foregroundStyle(SleepColor.muted)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.top, SleepSpacing.lg)
    }
}

// MARK: - Root screen

private struct ProfileRootScreen: View {
    var store: SleepStore
    let profile: Profile

    @State private var showsSettings = false

    private var sessions: [SleepSession] { store.displaySessions }

    var body: some View {
        SceneScreen {
            identity

            // Dashboard band: the three numbers that describe your sleep at a
            // glance, big numerals over tiny labels, straight under the name.
            if !sessions.isEmpty {
                statBand
                    .padding(.top, SleepSpacing.xxl)
            }

            if store.shouldPromptHealthConnect {
                HealthConnectCard(
                    onConnect: { Task { await store.connectHealth() } },
                    onDismiss: { store.dismissHealthPrompt() }
                )
                .padding(.top, SleepSpacing.xxl)
            }

            NavigationLink(value: ProfileDestination.blockedApps) {
                BlockedAppsPreview(store: store)
            }
            .buttonStyle(.plain)
            .padding(.top, SleepSpacing.huge)

            sleepSection
        }
        .sheet(isPresented: $showsSettings) {
            SettingsModal(store: store, profile: profile)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: Identity

    private var identity: some View {
        VStack(alignment: .leading, spacing: SleepSpacing.xs) {
            HStack(spacing: SleepSpacing.md) {
                Text("Profile").sectionLabel()
                Spacer()
                if store.isImportingHealth {
                    ProgressView().controlSize(.small).tint(SleepColor.amber)
                }
                GlassIconButton(systemImage: "gearshape") {
                    Haptics.soft()
                    showsSettings = true
                }
                .accessibilityLabel("Settings")
            }
            .frame(minHeight: 44)
            .padding(.bottom, SleepSpacing.md)

            // Name is display-only here; it's edited from Settings, so the
            // Profile body stays a clean identity + record with nothing to
            // fiddle with. Email lives in Settings too, not on this screen.
            Text(profile.name)
                .font(SleepFont.hero(34))
                .foregroundStyle(SleepColor.ink)
        }
        .padding(.top, SleepSpacing.lg)
    }

    // MARK: Sleep record

    private var lastSeven: [SleepSession] { Array(sessions.suffix(7)) }

    private var averageDuration: Int {
        guard !sessions.isEmpty else { return 0 }
        return sessions.reduce(0) { $0 + $1.durationMinutes } / sessions.count
    }

    private var averageScore: Int {
        guard !sessions.isEmpty else { return 0 }
        return sessions.reduce(0) { $0 + $1.score } / sessions.count
    }

    private var statBand: some View {
        HStack(alignment: .top, spacing: 0) {
            StatBlock(label: "Avg sleep", value: SleepFormatting.duration(averageDuration))
                .frame(maxWidth: .infinity, alignment: .leading)
            StatBlock(label: "Avg score", value: "\(averageScore)")
                .frame(maxWidth: .infinity, alignment: .leading)
            StatBlock(label: "Streak", value: "\(store.onTrackStreak)")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var sleepSection: some View {
        VStack(alignment: .leading, spacing: SleepSpacing.md) {
            Text("Your sleep").sectionLabel()

            if sessions.isEmpty {
                // Quiet, composed empty state — a warm moon beside the copy so
                // the section reads as a place waiting for data, not a gap.
                // No ghost charts or sample numbers: honest data only.
                HStack(alignment: .top, spacing: SleepSpacing.md) {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(SleepColor.amber)
                        .frame(width: 40, height: 40)
                        .background { Circle().fill(SleepColor.glassWarm) }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("No nights yet")
                            .font(SleepFont.title(16))
                            .foregroundStyle(SleepColor.ink)
                        Text("Your record starts tonight.")
                            .font(SleepFont.body(13))
                            .foregroundStyle(SleepColor.dim)
                    }
                    .padding(.top, 2)
                }
                .padding(.top, SleepSpacing.xs)
            } else {
                RecordBars(sessions: lastSeven, target: store.targetMinutes)

                historyList
                    .padding(.top, SleepSpacing.xxxl)
            }
        }
        .padding(.top, SleepSpacing.huge)
    }

    private var historyList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                // Same small-caps kicker grammar as every other section, so
                // the list reads as a deliberate subsection rather than a
                // stray line of body copy.
                Text("Recent nights").sectionLabel()
                Spacer()
                if sessions.contains(where: { $0.source == .healthKit }) {
                    Label("Apple Health", systemImage: "heart.fill")
                        .font(SleepFont.label(11))
                        .foregroundStyle(SleepColor.muted)
                }
            }
            .padding(.bottom, SleepSpacing.sm)

            ForEach(Array(lastSeven.reversed().enumerated()), id: \.element.id) { index, session in
                HistoryRow(session: session)
                    .overlay(alignment: .top) {
                        if index > 0 {
                            Rectangle().fill(SleepColor.hairline).frame(height: 1)
                        }
                    }
            }

            if sessions.count > 7 {
                NavigationLink(value: ProfileDestination.allNights) {
                    HStack {
                        Text("All \(sessions.count) nights")
                            .font(SleepFont.label(14))
                            .foregroundStyle(SleepColor.dim)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(SleepColor.faint)
                    }
                    .padding(.vertical, SleepSpacing.md)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .overlay(alignment: .top) {
                    Rectangle().fill(SleepColor.hairline).frame(height: 1)
                }
            }
        }
    }

}

// MARK: - Settings modal

/// The settings surface, opened from the gear in Profile's top-right as a
/// collapsible full-height sheet (`.large` detent + drag indicator, so it can
/// be swiped down to dismiss). It carries its own `NavigationStack` so schedule
/// and blocked-apps push as full pages inside it, and it hosts everything
/// configuration- and account-related so the Profile screen underneath stays a
/// clean identity + sleep record. There is deliberately no "reset all data";
/// the account-level exits are Sign out and, faded below it, Delete account.
struct SettingsModal: View {
    var store: SleepStore
    let profile: Profile

    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDeleteAccount = false
    @State private var deletingAccount = false
    @State private var deleteFailedMessage: String?
    @State private var isRenaming = false
    @State private var draftName = ""

    var body: some View {
        NavigationStack {
            SceneScreen {
                header

                profileSection
                configSection
                accountSection

                Text("Pixel art by CraftPix.net · OGA-BY 3.0")
                    .font(SleepFont.body(11))
                    .foregroundStyle(SleepColor.faint)
                    .padding(.top, SleepSpacing.huge)
            }
            .navigationDestination(for: SettingsDestination.self) { destination in
                switch destination {
                case .schedule:
                    ScheduleScreen(store: store, profile: profile)
                case .blockedApps:
                    BlockedAppsScreen(store: store)
                }
            }
            .alert("Your name", isPresented: $isRenaming) {
                TextField("Your name", text: $draftName)
                    .textInputAutocapitalization(.words)
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    store.saveName(trimmed)
                }
            } message: {
                Text("This is how the app greets you.")
            }
        }
    }

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: SleepSpacing.md) {
            Text("Profile").sectionLabel()

            GlassGroup {
                Button {
                    Haptics.soft()
                    draftName = store.profile?.name ?? profile.name
                    isRenaming = true
                } label: {
                    // Read from the observed store so the row updates the
                    // instant a rename is saved, not just on next open.
                    GlassRow(
                        icon: "person.fill",
                        title: "Name",
                        value: store.profile?.name ?? profile.name,
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)

                GlassRowDivider()

                // Read-only: the account email comes from the auth provider
                // and can't be changed in-app, so it shows without a chevron.
                // Middle truncation keeps long relay addresses on one line.
                GlassRow(
                    icon: "envelope.fill",
                    iconColor: SleepColor.muted,
                    title: "Email",
                    value: store.account?.email ?? "—"
                )
            }
        }
        .padding(.top, SleepSpacing.huge)
    }

    private var header: some View {
        HStack {
            Text("Settings")
                .font(SleepFont.hero(28))
                .foregroundStyle(SleepColor.ink)
            Spacer()
            // Same footprint as the Profile gear this sheet is opened from,
            // so the two read as one "settings" affordance.
            GlassIconButton(systemImage: "xmark", iconSize: 17, tint: SleepColor.ink) {
                Haptics.soft()
                dismiss()
            }
            .accessibilityLabel("Close settings")
        }
        .padding(.top, SleepSpacing.lg)
    }

    private var configSection: some View {
        VStack(alignment: .leading, spacing: SleepSpacing.md) {
            Text("Sleep").sectionLabel()

            GlassGroup {
                NavigationLink(value: SettingsDestination.schedule) {
                    GlassRow(
                        icon: "moon.fill",
                        title: "Schedule",
                        value: "\(SleepFormatting.clock(profile.bedtime)) – \(SleepFormatting.clock(profile.wakeTime))",
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)

                GlassRowDivider()

                NavigationLink(value: SettingsDestination.blockedApps) {
                    GlassRow(
                        icon: "lock.fill",
                        title: "Blocked apps",
                        value: store.lockdownSelectionSummary,
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)

                GlassRowDivider()

                healthRow
            }
        }
        .padding(.top, SleepSpacing.xxl)
    }

    @ViewBuilder
    private var healthRow: some View {
        if store.healthSyncState == .unavailable {
            GlassRow(
                icon: "heart.fill",
                iconColor: SleepColor.muted,
                title: "Apple Health",
                value: "Unavailable"
            )
        } else {
            // Derived from the store's actual connection state, not a local
            // optimistic mirror: HealthKit can report "denied" after the sheet,
            // and the toggle must reflect that rather than staying stuck on.
            HStack(spacing: SleepSpacing.md) {
                GlassRowIcon(icon: "heart.fill")
                Toggle(isOn: Binding(
                    get: { store.healthSyncState == .connected },
                    set: { enabled in
                        Haptics.soft()
                        if enabled { Task { await store.connectHealth() } }
                        else { store.disableHealthSync() }
                    }
                )) {
                    Text("Apple Health")
                        .font(SleepFont.body(16))
                        .foregroundStyle(SleepColor.ink)
                }
                .tint(SleepColor.amber)
            }
            .padding(.vertical, SleepSpacing.md)
            .frame(minHeight: 52)
        }
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: SleepSpacing.md) {
            Text("Account").sectionLabel()

            GlassGroup {
                Button {
                    Haptics.soft()
                    // Close the cover first so it doesn't tear down mid-flight
                    // as the root swaps Main → onboarding on sign-out.
                    dismiss()
                    Task { await store.signOut() }
                } label: {
                    GlassRow(
                        icon: "rectangle.portrait.and.arrow.right",
                        iconColor: SleepColor.dim,
                        title: "Sign out",
                        titleColor: SleepColor.dim
                    )
                }
                .buttonStyle(.plain)

                GlassRowDivider()

                // Deliberately faded: account deletion is a rare, irreversible
                // exit, so it sits quietly below Sign out and never competes
                // for attention.
                Button(role: .destructive) {
                    Haptics.soft()
                    confirmingDeleteAccount = true
                } label: {
                    HStack(spacing: SleepSpacing.sm) {
                        GlassRow(
                            icon: "trash",
                            iconColor: SleepColor.faint,
                            title: "Delete account",
                            titleColor: SleepColor.faint
                        )
                        if deletingAccount {
                            ProgressView().controlSize(.small).tint(SleepColor.faint)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(deletingAccount)
            }
        }
        .padding(.top, SleepSpacing.xxl)
        .alert("Delete account?", isPresented: $confirmingDeleteAccount) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task { await deleteAccount() }
            }
        } message: {
            Text("This permanently deletes your account and sleep history from our servers and this device. This can't be undone.")
        }
        .alert(
            "Couldn't delete account",
            isPresented: Binding(
                get: { deleteFailedMessage != nil },
                set: { if !$0 { deleteFailedMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteFailedMessage ?? "Please try again.")
        }
    }

    /// Remote-first delete: purge the server account, and only on success wipe
    /// local data. The cover is dismissed *before* the local wipe so the root's
    /// Main → onboarding swap doesn't tear the sheet down mid-flight (mirrors the
    /// Sign out ordering). On failure nothing local changes and we surface why.
    private func deleteAccount() async {
        deletingAccount = true
        defer { deletingAccount = false }
        if let error = await store.deleteAccountRemotely() {
            deleteFailedMessage = error
        } else {
            dismiss()
            store.finalizeAccountDeletion()
        }
    }
}

enum SettingsDestination: Hashable {
    case schedule
    case blockedApps
}

// MARK: - Sleep schedule (pushed)

private struct ScheduleScreen: View {
    var store: SleepStore
    let profile: Profile

    @Environment(\.dismiss) private var dismiss
    @State private var selectedMode: ScheduleMode = .bed
    @State private var draftBedtime: Int
    @State private var draftWakeTime: Int

    init(store: SleepStore, profile: Profile) {
        self.store = store
        self.profile = profile
        _draftBedtime = State(initialValue: profile.bedtime)
        _draftWakeTime = State(initialValue: profile.wakeTime)
    }

    var body: some View {
        SceneScreen {
            SubpageHeader(
                title: "Sleep schedule",
                subtitle: "Your bedtime countdown, sleep score, and lockdown window all follow this."
            )

            Picker("Schedule field", selection: $selectedMode) {
                Text("Bedtime · \(SleepFormatting.clock(draftBedtime))").tag(ScheduleMode.bed)
                Text("Wake · \(SleepFormatting.clock(draftWakeTime))").tag(ScheduleMode.wake)
            }
            .pickerStyle(.segmented)
            .padding(.top, SleepSpacing.huge)

            TimeAdjuster(
                minutes: Binding(
                    get: { selectedMode == .bed ? draftBedtime : draftWakeTime },
                    set: { minutes in
                        if selectedMode == .bed { draftBedtime = minutes }
                        else { draftWakeTime = minutes }
                    }
                )
            )
            .padding(.top, SleepSpacing.xl)

            LiquidPrimaryButton(title: "Save schedule", systemImage: "checkmark") {
                Haptics.soft()
                store.saveSchedule(bedtime: draftBedtime, wakeTime: draftWakeTime)
                dismiss()
            }
            .padding(.top, SleepSpacing.huge)
        }
    }
}

private enum ScheduleMode: String, CaseIterable, Identifiable {
    case bed
    case wake

    var id: String { rawValue }
}

// MARK: - All nights (pushed)

private struct AllNightsScreen: View {
    var store: SleepStore

    private var sessions: [SleepSession] { store.displaySessions }

    var body: some View {
        SceneScreen {
            SubpageHeader(title: "All nights")

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(sessions.reversed().enumerated()), id: \.element.id) { index, session in
                    HistoryRow(session: session)
                        .overlay(alignment: .top) {
                            if index > 0 {
                                Rectangle().fill(SleepColor.hairline).frame(height: 1)
                            }
                        }
                }
            }
            .padding(.top, SleepSpacing.xl)
        }
    }
}

// MARK: - Health connect prompt

/// Persistent, dismissable prompt inviting the user to connect Apple Health.
/// Apple Health is offered here, on Profile, rather than during onboarding —
/// this is where sleep data lives, so the ask lands in context.
private struct HealthConnectCard: View {
    var onConnect: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: SleepSpacing.md) {
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(SleepColor.amber)

            VStack(alignment: .leading, spacing: SleepSpacing.sm) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Connect Apple Health")
                        .font(SleepFont.title(16))
                        .foregroundStyle(SleepColor.ink)
                    Text("Sync your real nights automatically, both ways.")
                        .font(SleepFont.body(13))
                        .foregroundStyle(SleepColor.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    Haptics.soft()
                    onConnect()
                } label: {
                    Text("Connect")
                        .font(SleepFont.label(14))
                        .foregroundStyle(SleepColor.background)
                        .padding(.horizontal, SleepSpacing.lg)
                        .padding(.vertical, SleepSpacing.sm)
                        .background {
                            Capsule(style: .continuous)
                                .fill(LinearGradient(
                                    colors: [SleepColor.gold, SleepColor.amber],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ))
                        }
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }

            Spacer(minLength: 0)

            Button {
                Haptics.soft()
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SleepColor.muted)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(SleepSpacing.lg)
        // The glass draws its own edge; no manual border on top of it.
        .liquidGlass(cornerRadius: SleepRadius.lg, tint: SleepColor.glassWarm)
    }
}

// MARK: - Record components

private struct StatBlock: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(SleepFont.body(13))
                .foregroundStyle(SleepColor.muted)
            Text(value)
                .font(SleepFont.title(26))
                .foregroundStyle(SleepColor.ink)
                .monospacedDigit()
        }
    }
}

private struct HistoryRow: View {
    let session: SleepSession

    var body: some View {
        HStack(spacing: SleepSpacing.lg) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: SleepSpacing.xs) {
                    Text(SleepFormatting.historyDate.string(from: session.end))
                        .font(SleepFont.label(15))
                        .foregroundStyle(SleepColor.ink)
                    Image(systemName: session.source == .healthKit ? "heart.fill" : "moon.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(SleepColor.faint)
                        .accessibilityLabel(session.source == .healthKit ? "From Apple Health" : "Logged in app")
                }
                Text(SleepFormatting.duration(session.durationMinutes))
                    .font(SleepFont.body(13))
                    .foregroundStyle(SleepColor.dim)
                    .monospacedDigit()
            }

            Spacer()

            // Slim custom meter instead of a stock ProgressView: a quiet
            // track with a fill tinted by the score color, always paired
            // with the numeral so the reading never rides on color alone.
            Capsule()
                .fill(Color.white.opacity(0.08))
                .frame(width: 64, height: 4)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(recordScoreColor(session.score))
                        .frame(width: 64 * CGFloat(min(max(session.score, 0), 100)) / 100)
                }

            // Score numerals keep the app's coloring (gold ≥ 80, ink 60–79,
            // danger < 60) in a fixed trailing spot, same as Home and the
            // widgets.
            Text("\(session.score)")
                .font(SleepFont.title(19))
                .foregroundStyle(recordScoreColor(session.score))
                .frame(width: 36, alignment: .trailing)
                .monospacedDigit()
        }
        .padding(.vertical, SleepSpacing.lg)
    }
}

private func recordScoreColor(_ score: Int) -> Color {
    switch score {
    case 80...: return SleepColor.gold
    case 60..<80: return SleepColor.ink
    default: return SleepColor.danger
    }
}

/// The widgets' 7-night bar rhythm brought home (see DESIGN.md "Widgets"):
/// exactly 7 fixed-width columns with the latest night rightmost, gold→amber
/// capsules against a quiet target hairline (~15% headroom keeps it a
/// reference line *inside* the chart), hours set in navy ink inside each
/// bar's bottom, weekday initials underneath every slot. Nights not yet
/// logged render as hairline stubs, so a young record honestly reads as a
/// week filling in — never a lone value stretched across the full width the
/// way the retired smoothed line chart did.
private struct RecordBars: View {
    let sessions: [SleepSession]
    let target: Int

    private static let slotCount = 7
    private static let barWidth: CGFloat = 28
    private let chartHeight: CGFloat = 120

    /// Fixed 7 columns, latest night in the rightmost slot; missing nights
    /// lead-pad as nil.
    private var slots: [SleepSession?] {
        let recent = Array(sessions.suffix(Self.slotCount))
        return Array(repeating: nil, count: Self.slotCount - recent.count) + recent
    }

    var body: some View {
        let maxNight = sessions.map(\.durationMinutes).max() ?? target
        let scaleMinutes = CGFloat(max(target, maxNight)) * 1.15
        let targetFraction = CGFloat(target) / scaleMinutes

        VStack(spacing: SleepSpacing.sm) {
            HStack(alignment: .bottom, spacing: SleepSpacing.sm) {
                ForEach(Array(slots.enumerated()), id: \.offset) { index, session in
                    if let session {
                        let barHeight = max(6, chartHeight * CGFloat(session.durationMinutes) / scaleMinutes)
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [SleepColor.gold, SleepColor.amber],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                            .overlay(alignment: .bottom) {
                                // Bottom-anchored so every label sits on one
                                // shared baseline regardless of bar height;
                                // bars too short to hold it drop it.
                                if barHeight >= 26 {
                                    Text(hoursLabel(session.durationMinutes))
                                        .font(SleepFont.label(10))
                                        .foregroundStyle(SleepColor.navy)
                                        .monospacedDigit()
                                        .minimumScaleFactor(0.6)
                                        .lineLimit(1)
                                        .padding(.bottom, 6)
                                        .padding(.horizontal, 2)
                                }
                            }
                            .opacity(index == Self.slotCount - 1 ? 1 : 0.62)
                            // Capped width: at phone width a full slot reads
                            // as a blobby pill, not a chart bar.
                            .frame(maxWidth: Self.barWidth)
                            .frame(height: barHeight)
                            .frame(maxWidth: .infinity, alignment: .bottom)
                    } else {
                        Capsule().fill(SleepColor.hairline)
                            .frame(maxWidth: Self.barWidth)
                            .frame(height: 4)
                            .frame(maxWidth: .infinity, alignment: .bottom)
                    }
                }
            }
            .frame(height: chartHeight, alignment: .bottom)
            .overlay(alignment: .bottom) {
                // Target sleep window, as a quiet reference line.
                Rectangle()
                    .fill(SleepColor.ink.opacity(0.18))
                    .frame(height: 1)
                    .offset(y: -chartHeight * targetFraction)
            }

            HStack(spacing: SleepSpacing.sm) {
                ForEach(Array(slots.enumerated()), id: \.offset) { index, session in
                    Text(session.map { SleepFormatting.narrowWeekday.string(from: $0.end) } ?? " ")
                        .font(SleepFont.label(11))
                        .foregroundStyle(index == Self.slotCount - 1 ? SleepColor.amber : SleepColor.faint)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    /// Hours for a bar: "7h" for whole hours, else one decimal ("7.5h").
    private func hoursLabel(_ minutes: Int) -> String {
        let hours = Double(minutes) / 60
        let rounded = (hours * 10).rounded() / 10
        return rounded == rounded.rounded()
            ? "\(Int(rounded))h"
            : String(format: "%.1fh", rounded)
    }

    private var accessibilitySummary: String {
        guard let latest = sessions.last else { return "No nights logged yet" }
        let nights = sessions.count == 1 ? "1 night" : "\(sessions.count) nights"
        return "Sleep chart, \(nights) logged. Last night \(SleepFormatting.duration(latest.durationMinutes))."
    }
}
