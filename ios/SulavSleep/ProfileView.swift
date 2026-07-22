import SwiftUI

// The Profile tab is the app's single "about you" surface: identity plus the
// sleep record (weekly chart, averages, night history). Configuration lives in
// a separate `SettingsModal`, opened from the gear top-right as a collapsible
// full-height sheet, so the tab body stays clean. There is deliberately no
// destructive "reset all data" action; the only account-level exits are Sign
// out (confirmed by an alert) and, as bare faded text below the group, Delete
// account (confirmed by typing "delete"). Home stays a pure "go to bed" screen
// because of this.

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
            // NavigationLinks are buttons to the finger, so they knock like
            // one; simultaneous so it never steals the tap from the push.
            .simultaneousGesture(TapGesture().onEnded { Haptics.heavy() })
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

    private var statBand: some View {
        HStack(alignment: .top, spacing: 0) {
            StatBlock(label: "Avg sleep", value: SleepFormatting.duration(averageDuration))
                .frame(maxWidth: .infinity, alignment: .leading)
            StatBlock(label: "Streak", value: "\(store.onTrackStreak)")
                .frame(maxWidth: .infinity, alignment: .leading)
            StatBlock(label: "Nights", value: "\(sessions.count)")
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
                RecordChart(sessions: sessions, target: store.targetMinutes)

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
                .simultaneousGesture(TapGesture().onEnded { Haptics.heavy() })
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
/// the account-level exits are Sign out (behind a confirmation alert) and,
/// as bare faded text below the group, Delete account (behind a type-"delete"
/// confirmation).
struct SettingsModal: View {
    var store: SleepStore
    let profile: Profile

    @Environment(\.dismiss) private var dismiss
    @State private var confirmingSignOut = false
    @State private var confirmingDeleteAccount = false
    @State private var deleteConfirmationText = ""
    @State private var deletingAccount = false
    @State private var deleteFailedMessage: String?
    @State private var isRenaming = false
    @State private var draftName = ""

    var body: some View {
        NavigationStack {
            SceneScreen {
                header

                profileSection
                subscriptionSection
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
                Button("Cancel", role: .cancel) { Haptics.heavy() }
                Button("Save") {
                    Haptics.heavy()
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
                    Haptics.heavy()
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

    // MARK: Subscription

    /// The plan status group — trial vs paid, the renewal/end date, and a way
    /// to manage billing. It hides entirely when there's no status to show
    /// (dev mode, or before the first entitlement fetch resolves), matching the
    /// paywall's "never shows in dev mode" rule rather than faking a plan.
    @ViewBuilder
    private var subscriptionSection: some View {
        if let status = store.subscriptionStatus {
            VStack(alignment: .leading, spacing: SleepSpacing.md) {
                Text("Subscription").sectionLabel()

                GlassGroup {
                    SubscriptionStatusRow(status: status)

                    GlassRowDivider()

                    Button {
                        Haptics.heavy()
                        Task { await store.manageSubscriptions() }
                    } label: {
                        GlassRow(
                            icon: "creditcard.fill",
                            iconColor: SleepColor.muted,
                            title: "Manage subscription",
                            showsChevron: true
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, SleepSpacing.xxl)
        }
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
                .simultaneousGesture(TapGesture().onEnded { Haptics.heavy() })

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
                .simultaneousGesture(TapGesture().onEnded { Haptics.heavy() })

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
                        Haptics.heavy()
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
                    Haptics.heavy()
                    confirmingSignOut = true
                } label: {
                    GlassRow(
                        icon: "rectangle.portrait.and.arrow.right",
                        iconColor: SleepColor.dim,
                        title: "Sign out",
                        titleColor: SleepColor.dim
                    )
                }
                .buttonStyle(.plain)
            }

            // Deliberately bare and faded: account deletion is a rare,
            // irreversible exit, so it sits outside the glass group as quiet
            // text that never competes for attention.
            Button(role: .destructive) {
                Haptics.heavy()
                deleteConfirmationText = ""
                confirmingDeleteAccount = true
            } label: {
                HStack(spacing: SleepSpacing.sm) {
                    Text("Delete account")
                        .font(SleepFont.body(14))
                        .foregroundStyle(SleepColor.faint)
                    if deletingAccount {
                        ProgressView().controlSize(.small).tint(SleepColor.faint)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .disabled(deletingAccount)
            .padding(.top, SleepSpacing.sm)
        }
        .padding(.top, SleepSpacing.xxl)
        .alert("Sign out?", isPresented: $confirmingSignOut) {
            Button("Cancel", role: .cancel) { Haptics.heavy() }
            Button("Sign out") {
                Haptics.heavy()
                // Close the cover first so it doesn't tear down mid-flight
                // as the root swaps Main → onboarding on sign-out.
                dismiss()
                Task { await store.signOut() }
            }
        } message: {
            Text("Your sleep record stays on this device and in your account. You can sign back in anytime.")
        }
        .alert("Delete account?", isPresented: $confirmingDeleteAccount) {
            TextField("Type \"delete\"", text: $deleteConfirmationText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) { Haptics.heavy() }
            Button("Delete", role: .destructive) {
                Haptics.heavy()
                Task { await deleteAccount() }
            }
            .disabled(deleteConfirmationText.trimmingCharacters(in: .whitespaces).lowercased() != "delete")
        } message: {
            Text("This permanently deletes your account and sleep history from our servers and this device. This can't be undone. Type \"delete\" to confirm.")
        }
        .alert(
            "Couldn't delete account",
            isPresented: Binding(
                get: { deleteFailedMessage != nil },
                set: { if !$0 { deleteFailedMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { Haptics.heavy() }
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

// MARK: - Sleep schedule (pushed or sheet)

struct ScheduleScreen: View {
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
                subtitle: "Your bedtime countdown and lockdown window follow this."
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
                store.saveSchedule(bedtime: draftBedtime, wakeTime: draftWakeTime)
                dismiss()
            }
            .padding(.top, SleepSpacing.huge)
        }
    }
}

enum ScheduleMode: String, CaseIterable, Identifiable {
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
                    Haptics.heavy()
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
                Haptics.heavy()
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

// MARK: - Subscription status

/// The subscription status row: a data readout, not a control — so, like the
/// plan reveal's summary rows, it carries a dim detail line (the one place a
/// settings row explains rather than only naming). The "about to end" case
/// (active but set to cancel) shows its detail in amber: a heads-up, not a
/// failure, per the app's two-tone rule (`danger` is reserved for real
/// failures).
private struct SubscriptionStatusRow: View {
    let status: SubscriptionStatus

    var body: some View {
        HStack(spacing: SleepSpacing.md) {
            icon

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(SleepFont.body(16))
                    .foregroundStyle(SleepColor.ink)
                if let detail {
                    Text(detail)
                        .font(SleepFont.body(13))
                        .foregroundStyle(isEnding ? SleepColor.amber : SleepColor.muted)
                }
            }

            Spacer(minLength: SleepSpacing.md)
        }
        .padding(.vertical, SleepSpacing.md)
        .frame(minHeight: 52)
    }

    /// Active but set not to renew — the "about to end" heads-up that colors
    /// the detail line amber.
    private var isEnding: Bool { status.tier != .expired && !status.willRenew }

    /// The leading chip. For an entitled user (trial/pro) it's the brand sloth
    /// turned to gold — the "you're a subscriber" mark
    /// (`scripts/generate-subscription-icon.py`), sitting in the same soft
    /// tinted rounded square as every other `GlassRowIcon` so the row still
    /// scans with its siblings. Expired falls back to a muted SF glyph.
    @ViewBuilder
    private var icon: some View {
        switch status.tier {
        case .trial, .pro:
            Image("SubscriptionSloth")
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
                .frame(width: 30, height: 30)
                .background {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(SleepColor.gold.opacity(0.14))
                }
                .accessibilityHidden(true)
        case .expired:
            GlassRowIcon(icon: "xmark.circle.fill", color: SleepColor.muted)
        }
    }

    private var title: String {
        switch status.tier {
        case .trial: return "Free trial"
        case .pro: return "SleepBlock Pro"
        case .expired: return "Not subscribed"
        }
    }

    private var detail: String? {
        switch status.tier {
        case .expired:
            return "Your access has ended"
        case .trial, .pro:
            guard let expiration = status.expiration else {
                return status.willRenew ? nil : "Set to cancel"
            }
            let date = SleepFormatting.monthDayYear.string(from: expiration)
            if !status.willRenew {
                return "Ends \(date) · won't renew"
            }
            if status.tier == .trial {
                return "\(daysLeft(until: expiration)) · renews \(date)"
            }
            return [planWord, "Renews \(date)"].compactMap { $0 }.joined(separator: " · ")
        }
    }

    /// "Yearly" / "Monthly" when the period is known, else nothing.
    private var planWord: String? {
        switch status.isAnnual {
        case .some(true): return "Yearly"
        case .some(false): return "Monthly"
        case .none: return nil
        }
    }

    /// "6 days left" / "1 day left" / "Ends today" for a trial countdown.
    private func daysLeft(until date: Date) -> String {
        let calendar = Calendar.current
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: Date()),
            to: calendar.startOfDay(for: date)
        ).day ?? 0
        if days <= 0 { return "Ends today" }
        return days == 1 ? "1 day left" : "\(days) days left"
    }
}

// MARK: - Record components

private struct StatBlock: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // `muted` washes out against the brighter day/dusk sky, so the
            // label borrows the section-kicker treatment — `dim` over a soft
            // navy shadow that grounds it across all three scene phases where
            // a scrim alone can't.
            Text(label)
                .font(SleepFont.body(13))
                .foregroundStyle(SleepColor.dim)
                .shadow(color: SleepColor.background.opacity(0.85), radius: 3, y: 1)
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
            HStack(spacing: SleepSpacing.xs) {
                Text(SleepFormatting.historyDate.string(from: session.end))
                    .font(SleepFont.label(15))
                    .foregroundStyle(SleepColor.ink)
                Image(systemName: session.source == .healthKit ? "heart.fill" : "moon.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(SleepColor.faint)
                    .accessibilityLabel(session.source == .healthKit ? "From Apple Health" : "Logged in app")
            }

            Spacer()

            // Duration is the record's only reading — one number per row,
            // in a fixed trailing spot.
            Text(SleepFormatting.duration(session.durationMinutes))
                .font(SleepFont.title(19))
                .foregroundStyle(SleepColor.ink)
                .monospacedDigit()
        }
        .padding(.vertical, SleepSpacing.lg)
    }
}

/// The widgets' 7-night bar rhythm brought home (see DESIGN.md "Widgets"):
/// exactly 7 fixed-width columns with the latest night rightmost, gold→amber
/// capsules against a quiet target hairline (~15% headroom keeps it a
/// reference line *inside* the chart), every bar's hours on one shared plane
/// via `BarHoursLabel` (navy inside the bar, gold above it, split at the
/// bar's edge), weekday initials underneath every slot. Nights not yet
/// logged render as hairline stubs, so a young record honestly reads as a
/// week filling in — never a lone value stretched across the full width the
/// way the retired smoothed line chart did.
private struct RecordBars: View {
    /// One page's worth of nights (up to `slotCount`), oldest→newest.
    let sessions: [SleepSession]
    let target: Int
    /// Whether this page is the most recent one — only then does the caption
    /// append a "· N days ago" cue, so a stale newest week reads as stale.
    var showsRelativeAge: Bool = true

    private static let slotCount = 7
    private static let barWidth: CGFloat = 28
    private let chartHeight: CGFloat = 120

    /// Fixed 7 columns where each column is a calendar day.  The rightmost
    /// column is the latest night's date; the leftmost is six calendar days
    /// earlier.  Sessions are placed into the column that matches their `end`
    /// date (start-of-day).  Missed days appear as `nil` — the hairline
    /// placeholder bar — in the correct position, so gaps are visible.
    private var slots: [SleepSession?] {
        guard let latest = sessions.last else {
            return Array(repeating: nil, count: Self.slotCount)
        }
        let calendar = Calendar.current
        let latestDay = calendar.startOfDay(for: latest.end)
        // Map each session to its day-offset from the latest night.
        var byOffset: [Int: SleepSession] = [:]
        for session in sessions.suffix(Self.slotCount) {
            let sessionDay = calendar.startOfDay(for: session.end)
            let offset = calendar.dateComponents([.day], from: sessionDay, to: latestDay).day ?? 0
            if offset >= 0 && offset < Self.slotCount {
                byOffset[offset] = session
            }
        }
        // Build the 7-slot array: index 0 = six days ago … index 6 = latest.
        return (0 ..< Self.slotCount).map { index in
            let daysBack = Self.slotCount - 1 - index
            return byOffset[daysBack]
        }
    }

    /// The calendar date for each slot, used by the weekday labels so even
    /// missed-day columns show the correct day letter.
    private var slotDates: [Date] {
        let calendar = Calendar.current
        let latestDay: Date
        if let latest = sessions.last {
            latestDay = calendar.startOfDay(for: latest.end)
        } else {
            latestDay = calendar.startOfDay(for: Date())
        }
        return (0 ..< Self.slotCount).map { index in
            let daysBack = Self.slotCount - 1 - index
            return calendar.date(byAdding: .day, value: -daysBack, to: latestDay)!
        }
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
                        ZStack(alignment: .bottom) {
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [SleepColor.gold, SleepColor.amber],
                                        startPoint: .top, endPoint: .bottom
                                    )
                                )
                                // Capped width: at phone width a full slot
                                // reads as a blobby pill, not a chart bar.
                                .frame(maxWidth: Self.barWidth)
                                .frame(height: barHeight)
                            BarHoursLabel(
                                text: hoursLabel(session.durationMinutes),
                                fontSize: 10,
                                plane: 6,
                                barHeight: barHeight
                            )
                        }
                        .opacity(index == Self.slotCount - 1 ? 1 : 0.62)
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
            .overlay(alignment: .bottomTrailing) {
                // Target sleep window, as a quiet reference line — tagged with
                // the goal itself ("8h") on a small navy chip at the trailing
                // end, so the line reads as "your target", not an unlabeled
                // rule. The chip rides just above the line, right-aligned.
                VStack(alignment: .trailing, spacing: 2) {
                    Text(hoursLabel(target))
                        .font(SleepFont.label(10))
                        .foregroundStyle(SleepColor.dim)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(SleepColor.navy.opacity(0.72)))
                    Rectangle()
                        .fill(SleepColor.ink.opacity(0.18))
                        .frame(height: 1)
                }
                .offset(y: -chartHeight * targetFraction)
            }

            HStack(spacing: SleepSpacing.sm) {
                let dates = slotDates
                ForEach(Array(slots.enumerated()), id: \.offset) { index, session in
                    Text(SleepFormatting.narrowWeekday.string(from: dates[index]))
                        .font(SleepFont.label(11))
                        .foregroundStyle(index == Self.slotCount - 1 ? SleepColor.amber : SleepColor.faint)
                        .frame(maxWidth: .infinity)
                }
            }

            // Weekday initials alone can't tell one week from another (a stale
            // June week looks just like the current one), so every page names
            // its date range; the newest page also says how long ago, so an
            // old record reads as old at a glance.
            if let dateCaption {
                Text(dateCaption)
                    .font(SleepFont.label(11))
                    .foregroundStyle(SleepColor.faint)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, SleepSpacing.xs)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    /// "Jun 16 – Jun 22" for this page's span, with "· N days ago" appended on
    /// the newest page once its latest night is ≥ 2 calendar days back.
    private var dateCaption: String? {
        guard let first = sessions.first?.end, let last = sessions.last?.end else { return nil }
        let range = first == last
            ? SleepFormatting.monthDay.string(from: last)
            : "\(SleepFormatting.monthDay.string(from: first)) – \(SleepFormatting.monthDay.string(from: last))"
        guard showsRelativeAge else { return range }
        let calendar = Calendar.current
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: last),
            to: calendar.startOfDay(for: Date())
        ).day ?? 0
        return days >= 2 ? "\(range) · \(days) days ago" : range
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
        var summary = "Sleep chart, \(nights) this week. Latest night \(SleepFormatting.duration(latest.durationMinutes))."
        if let dateCaption {
            summary += " \(dateCaption)."
        }
        return summary
    }
}

/// Swipeable wrapper around `RecordBars`: the record is chunked into pages of
/// seven nights (boundaries anchored to the newest night, so the current week
/// is always a full column set and older weeks fill in behind it), and each
/// page is a self-contained bar chart with its own date-range caption. Pages
/// sit oldest→newest left→right — matching the "latest rightmost" rhythm of a
/// single chart — so the newest week shows by default and the user swipes
/// right to walk back through history. A single week renders as a plain chart
/// with no pager chrome.
private struct RecordChart: View {
    let sessions: [SleepSession]
    let target: Int

    private static let perPage = 7
    private let pageHeight: CGFloat = 172

    @State private var page = 0

    /// Oldest→newest pages, each spanning a 7-calendar-day window anchored from
    /// the newest night backward.  Because `RecordBars` maps sessions onto a
    /// 7-day grid by date, pages must also be date-aligned — otherwise sessions
    /// that fall outside a 7-day span (due to sparse logging) would be silently
    /// dropped.
    private var pages: [[SleepSession]] {
        guard let latest = sessions.last else { return [] }
        let calendar = Calendar.current
        let latestDay = calendar.startOfDay(for: latest.end)

        // Walk backward from the newest night in 7-day steps.  Each page
        // collects sessions whose `end` date falls within [windowStart,
        // windowEnd).
        var result: [[SleepSession]] = []
        var windowEnd = calendar.date(byAdding: .day, value: 1, to: latestDay)!
        let earliest = calendar.startOfDay(for: sessions.first!.end)

        while windowEnd > earliest {
            let windowStart = calendar.date(byAdding: .day, value: -Self.perPage, to: windowEnd)!
            let page = sessions.filter { session in
                let day = calendar.startOfDay(for: session.end)
                return day >= windowStart && day < windowEnd
            }
            if !page.isEmpty {
                result.append(page)
            }
            windowEnd = windowStart
        }
        return result.reversed()
    }

    var body: some View {
        let pages = pages
        if pages.count <= 1 {
            RecordBars(sessions: pages.first ?? [], target: target)
        } else {
            VStack(spacing: SleepSpacing.md) {
                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, week in
                        RecordBars(
                            sessions: week,
                            target: target,
                            showsRelativeAge: index == pages.count - 1
                        )
                        .frame(maxHeight: .infinity, alignment: .top)
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: pageHeight)

                PageDots(count: pages.count, current: $page)
            }
            .onAppear { page = pages.count - 1 }
        }
    }
}

/// Instagram-style page indicator, scaled for a record that can run to
/// dozens of weeks. The strip is a **fixed-width window** of at most
/// `maxVisible` dots — it never grows no matter how long the record is; when
/// there are more weeks than fit, the dots on whichever edge still has hidden
/// weeks shrink to signal "more this way". The current week is amber, the
/// rest faint. The system's own TabView dots are suppressed because they
/// clash with the bars and can't do any of this.
///
/// The strip is also a **scrubber**: press and drag it left/right to fast-
/// forward or rewind through weeks (finger travel maps to weeks at a fixed
/// step), with a soft tick each time a new week lands — so reaching week 3 of
/// 15 is one drag, not fifteen swipes.
private struct PageDots: View {
    let count: Int
    @Binding var current: Int

    private static let maxVisible = 7
    private static let dotSize: CGFloat = 7
    private static let scrubStep: CGFloat = 18 // finger points per week

    // The week the current drag started from, so scrubbing is measured as a
    // delta rather than an absolute position on a narrow strip.
    @State private var scrubAnchor: Int?

    // First index of the visible window, slid so the current week stays
    // centered until the window bumps into either end of the record.
    private var windowStart: Int {
        guard count > Self.maxVisible else { return 0 }
        let half = Self.maxVisible / 2
        return min(max(0, current - half), count - Self.maxVisible)
    }

    private var visibleIndices: Range<Int> {
        windowStart ..< min(count, windowStart + Self.maxVisible)
    }

    /// Relative size for a dot: full, except the outermost one or two dots on
    /// an edge that still has weeks hidden beyond it, which taper down.
    private func scale(for index: Int) -> CGFloat {
        guard count > Self.maxVisible else { return 1 }
        let start = windowStart
        let end = start + Self.maxVisible - 1
        if start > 0 {
            if index == start { return 0.45 }
            if index == start + 1 { return 0.7 }
        }
        if end < count - 1 {
            if index == end { return 0.45 }
            if index == end - 1 { return 0.7 }
        }
        return 1
    }

    var body: some View {
        HStack(spacing: SleepSpacing.sm) {
            ForEach(visibleIndices, id: \.self) { index in
                Circle()
                    .fill(index == current ? SleepColor.amber : SleepColor.faint)
                    .frame(width: Self.dotSize * scale(for: index),
                           height: Self.dotSize * scale(for: index))
                    // Stable slot so shrinking a dot never jiggles the row.
                    .frame(width: Self.dotSize, height: Self.dotSize)
            }
        }
        .frame(height: Self.dotSize)
        .animation(.easeInOut(duration: 0.2), value: current)
        // Roomy invisible hit area so the thin strip is easy to grab and scrub.
        .padding(.vertical, SleepSpacing.sm)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let anchor = scrubAnchor ?? current
                    if scrubAnchor == nil { scrubAnchor = current }
                    let delta = Int((value.translation.width / Self.scrubStep).rounded())
                    let target = min(max(0, anchor + delta), count - 1)
                    if target != current {
                        Haptics.soft()
                        current = target
                    }
                }
                .onEnded { _ in scrubAnchor = nil }
        )
        .accessibilityElement()
        .accessibilityLabel("Week \(current + 1) of \(count)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: current = min(count - 1, current + 1)
            case .decrement: current = max(0, current - 1)
            default: break
            }
        }
    }
}
