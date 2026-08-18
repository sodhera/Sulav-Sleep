import SwiftUI
import UIKit

// The Sleep Partners screen, the referral invite explainer, and the
// referral-code sheet. Referral and partnership are two separate features now
// (see DESIGN.md "Sleep partner & referral"): referral is a growth code that
// grants free nights, partnership is a mutual, data-sharing relationship you
// build by sending someone a `sleepblock://partner/<token>` invite link. This
// file holds the partner UI (reached from the Home top-right button) plus the
// two referral surfaces that happen to share the file.

// MARK: - Sleep Partners screen (Home → partner button)

/// Which pairing sheet is up. An enum behind one `sheet(item:)` rather than
/// a Bool per sheet — see the presentation note on `SleepPartnersScreen`.
private enum PartnerSheet: String, Identifiable {
    case showCode, enterCode
    var id: String { rawValue }
}

/// The one home for sleep partners: the list, adding, and unlinking. Presented
/// as a sheet from Home's top-right button (and raised automatically when a
/// partner-invite link is tapped). A partner's numbers reuse Home's flame and
/// the app's clock/duration formatting — a partner's night reads exactly like
/// your own.
struct SleepPartnersScreen: View {
    var store: SleepStore

    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?
    @State private var unlinkTarget: PartnerLink?
    @State private var activeSheet: PartnerSheet?

    var body: some View {
        ZStack {
            SleepBackground(showsMoon: true)
            SceneReadabilityScrim()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    header

                    if store.partners.isEmpty {
                        emptyState.padding(.top, SleepSpacing.huge)
                    } else {
                        VStack(spacing: SleepSpacing.md) {
                            ForEach(store.partners) { partner in
                                PartnerRow(partner: partner) { unlinkTarget = partner }
                            }
                        }
                        .padding(.top, SleepSpacing.xl)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(SleepFont.body(13))
                            .foregroundStyle(SleepColor.danger)
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                            .padding(.top, SleepSpacing.lg)
                    }

                    actions.padding(.top, SleepSpacing.xl)
                }
                .padding(.horizontal, SleepSpacing.xxl)
                .padding(.bottom, 120)
            }
            .safeAreaPadding(.top)
        }
        // A partner-invite link that was just accepted lands the user here with
        // a one-shot confirmation (or the error, in danger tone).
        .onAppear {
            if let msg = store.partnerInviteMessage {
                errorMessage = nil
                store.partnerInviteMessage = nil
                inviteResultBanner = msg
            }
        }
        // Both code paths (show and enter) report through the same one-shot
        // message the deep link uses, so every route into partnership
        // confirms itself identically.
        .onChange(of: store.partnerInviteMessage) { _, msg in
            guard let msg else { return }
            store.partnerInviteMessage = nil
            errorMessage = nil
            withAnimation { inviteResultBanner = msg }
        }
        // One `sheet(item:)`, not two `sheet(isPresented:)`. Stacking two
        // presentation modifiers on the same view is unreliable — SwiftUI
        // honors one and still *builds* the other's content, which fired the
        // code mint on appear, before anyone had asked for a code.
        .sheet(item: $activeSheet) { sheet in
            Group {
                switch sheet {
                case .showCode: PartnerCodeSheet(store: store)
                case .enterCode: PartnerCodeEntrySheet(store: store)
                }
            }
            .presentationDetents([.medium])
            .presentationBackground(SleepColor.background)
        }
        .task { await store.refreshReferral() }
        .alert("Unlink partner?", isPresented: unlinkBinding, presenting: unlinkTarget) { partner in
            Button("Unlink", role: .destructive) {
                Task { await unlink(partner) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { partner in
            Text("You'll stop seeing each other's sleep. You can reconnect with a new invite later.")
        }
    }

    @State private var inviteResultBanner: String?

    private var header: some View {
        VStack(alignment: .leading, spacing: SleepSpacing.xl) {
            HStack {
                Text("Sleep partners")
                    .font(SleepFont.hero(28))
                    .foregroundStyle(SleepColor.ink)
                Spacer()
                // 44pt, the app's one icon-button size (Home's chips, the
                // Profile gear, the Settings close) — this sheet's own
                // opener is Home's partner button, so it must match it.
                GlassIconButton(systemImage: "xmark", size: 44, iconSize: 17, tint: SleepColor.ink) {
                    dismiss()
                }
                .accessibilityLabel("Close")
            }
            if let inviteResultBanner {
                Text(inviteResultBanner)
                    .font(SleepFont.body(14))
                    .foregroundStyle(SleepColor.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, SleepSpacing.lg)
    }

    private var emptyState: some View {
        HStack(alignment: .top, spacing: SleepSpacing.md) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(SleepColor.amber)
                .frame(width: 40, height: 40)
                .background { Circle().fill(SleepColor.glassWarm) }
            VStack(alignment: .leading, spacing: 3) {
                Text("Sleep better together")
                    .font(SleepFont.title(16))
                    .foregroundStyle(SleepColor.ink)
                Text("See each other's streak and schedule.")
                    .font(SleepFont.body(13))
                    .foregroundStyle(SleepColor.dim)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
        }
    }

    /// Two ways in, and both are codes. The `sleepblock://` invite link that
    /// shipped first is gone from the UI: it only resolves for someone who
    /// already has the app — there's no associated-domains entitlement, so no
    /// Universal Link and no App Store fallback, and most messengers won't
    /// even make the string tappable, so it often arrives as dead grey text.
    /// A typed code needs none of that to survive: the friend installs first
    /// and types it after. It also works out loud, across a room, which is
    /// how sleep partners usually pair.
    ///
    /// Links already in the wild still work — `AppDelegate` still routes
    /// `sleepblock://partner/<token>` and the accept path is untouched — the
    /// app just stops minting new ones.
    private var actions: some View {
        VStack(spacing: SleepSpacing.md) {
            LiquidPrimaryButton(title: codeButtonTitle, systemImage: "person.badge.plus") {
                activeSheet = .showCode
            }
            LiquidSecondaryButton(title: "Enter a friend's code", systemImage: "character.cursor.ibeam") {
                activeSheet = .enterCode
            }
        }
    }

    private var codeButtonTitle: String {
        store.partners.isEmpty ? "Show my code" : "Show a code for someone else"
    }

    private var unlinkBinding: Binding<Bool> {
        Binding(get: { unlinkTarget != nil }, set: { if !$0 { unlinkTarget = nil } })
    }

    private func unlink(_ partner: PartnerLink) async {
        errorMessage = nil
        do {
            try await store.unlinkPartner(partnershipID: partner.partnershipID)
            Haptics.success()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// One partner in the list: name + their three numbers, in the app's own
/// vocabulary (Home's flame, clock schedule, duration). A partner who has
/// never synced shows the honest empty line, never zeroed stats. Unlink is a
/// quiet trailing control.
private struct PartnerRow: View {
    let partner: PartnerLink
    var onUnlink: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SleepSpacing.md) {
            HStack {
                Text(partner.displayName)
                    .font(SleepFont.title(16))
                    .foregroundStyle(SleepColor.ink)
                Spacer()
                Button {
                    Haptics.heavy()
                    onUnlink()
                } label: {
                    Text("Unlink")
                        .font(SleepFont.label(12))
                        .foregroundStyle(SleepColor.muted)
                        .frame(minHeight: 28)
                }
                .buttonStyle(.plain)
            }

            if let summary = partner.summary {
                HStack(spacing: 0) {
                    stat(label: "Streak",
                         value: Label("\(summary.streak)", systemImage: summary.streakDying ? "flame" : "flame.fill")
                            .foregroundStyle(summary.streakDying ? SleepColor.muted : SleepColor.amber))
                    if let bed = summary.avgBedMinutes, let wake = summary.avgWakeMinutes {
                        stat(label: "Schedule",
                             value: Text("\(SleepFormatting.clock(bed)) – \(SleepFormatting.clock(wake))")
                                .foregroundStyle(SleepColor.ink))
                    }
                    if let duration = summary.avgDurationMinutes {
                        stat(label: "Avg sleep",
                             value: Text(SleepFormatting.duration(duration))
                                .foregroundStyle(SleepColor.ink))
                    }
                }
            } else {
                Text("No nights to show yet — their numbers appear after their first sleep.")
                    .font(SleepFont.body(13))
                    .foregroundStyle(SleepColor.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(SleepSpacing.lg)
        .liquidGlass(cornerRadius: SleepRadius.lg)
    }

    private func stat(label: String, value: some View) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(SleepFont.label(11))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(SleepColor.muted)
            value.font(SleepFont.title(15))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Referral explainer (Settings → Refer a friend)

/// Pushed from Settings' "Refer a friend" row — the row itself no longer
/// fires the share sheet directly. A bare settings row landing straight in
/// the system share sheet left the reward unexplained at the exact moment
/// someone was about to hand it to a friend; this screen answers "what is
/// this and what's in it for each of us" first, in the same `SubpageHeader`
/// + `SceneScreen` grammar every other pushed settings page uses.
struct InviteFriendScreen: View {
    var store: SleepStore

    var body: some View {
        SceneScreen {
            SubpageHeader(
                title: "Refer a friend",
                subtitle: "Give a friend a free month of SleepBlock."
            )

            benefitRow(
                icon: "moon.stars.fill",
                title: "30 nights free, for both of you",
                detail: "Theirs starts the night they join. Yours lands when they subscribe."
            )
            .padding(.top, SleepSpacing.huge)

            VStack(alignment: .leading, spacing: SleepSpacing.md) {
                Text("Your code").sectionLabel()
                codeField
            }
            .padding(.top, SleepSpacing.huge)

            shareButton
                .padding(.top, SleepSpacing.xl)

            if let stats = store.referrerStats, stats.invitedCount > 0 {
                Text(statsLine(stats))
                    .font(SleepFont.body(13))
                    .foregroundStyle(SleepColor.muted)
                    .padding(.top, SleepSpacing.lg)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
        }
        .task { await store.loadReferralCode() }
    }

    private func benefitRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: SleepSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(SleepColor.amber)
                .frame(width: 40, height: 40)
                .background { Circle().fill(SleepColor.glassWarm) }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(SleepFont.title(16))
                    .foregroundStyle(SleepColor.ink)
                Text(detail)
                    .font(SleepFont.body(13))
                    .foregroundStyle(SleepColor.dim)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
        }
    }

    @ViewBuilder private var codeField: some View {
        if let code = store.myReferralCode {
            Text(code)
                .font(SleepFont.hero(28))
                .tracking(4)
                .foregroundStyle(SleepColor.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, SleepSpacing.lg)
                .liquidGlass(cornerRadius: SleepRadius.lg)
        } else {
            ProgressView()
                .tint(SleepColor.amber)
                .frame(maxWidth: .infinity)
                .padding(.vertical, SleepSpacing.lg)
                .liquidGlass(cornerRadius: SleepRadius.lg)
        }
    }

    /// A full-width `ShareLink`, styled like `LiquidPrimaryButton` (the same
    /// amber capsule every other primary CTA uses) rather than that type
    /// itself — `ShareLink` owns its own tap-to-present-the-share-sheet
    /// behavior and needs to be the outermost control, not wrapped in one.
    @ViewBuilder private var shareButton: some View {
        if let code = store.myReferralCode {
            ShareLink(item: inviteMessage(code: code)) {
                Label {
                    Text("Share referral").font(SleepFont.label(16)).tracking(0.2)
                } icon: {
                    Image(systemName: "square.and.arrow.up")
                }
                .foregroundStyle(SleepColor.background)
                .frame(maxWidth: .infinity, minHeight: 58)
                .background {
                    Capsule(style: .continuous)
                        .fill(LinearGradient(
                            colors: [SleepColor.gold, SleepColor.amber],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                }
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded { Haptics.heavy() })
        } else {
            Text("Share referral")
                .font(SleepFont.label(16))
                .foregroundStyle(SleepColor.background)
                .frame(maxWidth: .infinity, minHeight: 58)
                .background {
                    Capsule(style: .continuous).fill(SleepColor.amber.opacity(0.4))
                }
        }
    }

    private func statsLine(_ stats: ReferrerStats) -> String {
        let joined = "\(stats.invitedCount) friend\(stats.invitedCount == 1 ? "" : "s") joined"
        guard stats.convertedCount > 0 else { return joined }
        return "\(joined) · \(stats.convertedCount) subscribed"
    }

    private func inviteMessage(code: String) -> String {
        "Here's a free month of SleepBlock — the app that blocks your phone at bedtime so you actually sleep. Use my code \(code): https://apps.apple.com/app/id\(AppStoreLink.appID)"
    }
}

// MARK: - Redeem sheet (shared with the paywall)

/// One field, one button. The server does every check and speaks
/// user-facing messages; this sheet only relays them, in the auth screen's
/// two-tone grammar (failures in `danger` — there are no notices here).
struct ReferralRedeemSheet: View {
    var store: SleepStore

    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var isRedeeming = false
    @State private var errorMessage: String?
    @FocusState private var fieldFocused: Bool

    var body: some View {
        ZStack {
            SleepColor.background.ignoresSafeArea()
            VStack(spacing: SleepSpacing.xl) {
                VStack(spacing: SleepSpacing.xs) {
                    Text("Referral code")
                        .font(SleepFont.hero(22))
                        .foregroundStyle(SleepColor.ink)
                    Text("From a friend's invite — it starts your 30 free nights.")
                        .font(SleepFont.body(14))
                        .foregroundStyle(SleepColor.dim)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, SleepSpacing.xxl)

                TextField("ABC123", text: $code)
                    .font(SleepFont.hero(28))
                    .foregroundStyle(SleepColor.ink)
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .focused($fieldFocused)
                    .padding(.vertical, SleepSpacing.lg)
                    .liquidGlass(cornerRadius: SleepRadius.lg)
                    .onChange(of: code) { _, value in
                        // The server normalizes too; this just keeps what the
                        // user sees identical to what will be checked.
                        let cleaned = value.uppercased().filter { !$0.isWhitespace && $0 != "-" }
                        if cleaned != value { code = cleaned }
                    }

                if let errorMessage {
                    Text(errorMessage)
                        .font(SleepFont.body(14))
                        .foregroundStyle(SleepColor.danger)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                LiquidPrimaryButton(title: "Start 30 nights free", isLoading: isRedeeming) {
                    Task { await redeem() }
                }
                .disabled(code.count < 6 || isRedeeming)

                Spacer()
            }
            .padding(.horizontal, SleepSpacing.xxl)
        }
        .onAppear { fieldFocused = true }
    }

    private func redeem() async {
        guard !isRedeeming else { return }
        isRedeeming = true
        errorMessage = nil
        defer { isRedeeming = false }
        do {
            try await store.redeemReferral(code: code)
            Haptics.success()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Pairing code sheets

/// The sender's half: one 6-character code, big enough to read across a
/// room or down a phone line. Why a code at all, when there's already a
/// link — see `SleepPartnersScreen.actions` and migration 008.
///
/// Deliberately a *temporary* code rather than a permanent per-user ID. A
/// fixed handle is guessable and forever, which would force back the
/// accept/decline step migration 006 removed — and what a partner sees is
/// bed and wake times, i.e. when someone's home is empty. One use, 24 hours.
///
/// The sheet watches for its own code being claimed and confirms in place,
/// so the sender doesn't have to ask "did it work?".
struct PartnerCodeSheet: View {
    var store: SleepStore

    @Environment(\.dismiss) private var dismiss
    @State private var code: String?
    @State private var errorMessage: String?
    @State private var partnerCountAtOpen = 0

    var body: some View {
        ZStack {
            SleepColor.background.ignoresSafeArea()
            VStack(spacing: SleepSpacing.xl) {
                VStack(spacing: SleepSpacing.xs) {
                    Text("Your pairing code")
                        .font(SleepFont.hero(22))
                        .foregroundStyle(SleepColor.ink)
                    Text("Read it to a friend, or send it. They enter it in the app.")
                        .font(SleepFont.body(14))
                        .foregroundStyle(SleepColor.dim)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, SleepSpacing.xxl)

                if let code {
                    Text(code)
                        // Wide tracking so each character is picked out one at
                        // a time — this string gets read aloud, not scanned.
                        .font(SleepFont.hero(38))
                        .tracking(8)
                        .foregroundStyle(SleepColor.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, SleepSpacing.lg)
                        .liquidGlass(cornerRadius: SleepRadius.lg)
                        .contextMenu {
                            Button("Copy code") { UIPasteboard.general.string = code }
                        }

                    Text("Works once · expires in 24 hours")
                        .font(SleepFont.body(12))
                        .foregroundStyle(SleepColor.muted)

                    ShareLink(item: shareMessage(code: code)) {
                        Label("Send it", systemImage: "square.and.arrow.up")
                            .font(SleepFont.label(16))
                            .tracking(0.2)
                            .foregroundStyle(SleepColor.background)
                            .frame(maxWidth: .infinity, minHeight: 58)
                            .background {
                                Capsule(style: .continuous).fill(LinearGradient(
                                    colors: [SleepColor.gold, SleepColor.amber],
                                    startPoint: .topLeading, endPoint: .bottomTrailing))
                            }
                    }
                } else if let errorMessage {
                    Text(errorMessage)
                        .font(SleepFont.body(14))
                        .foregroundStyle(SleepColor.danger)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ProgressView()
                        .tint(SleepColor.amber)
                        .frame(maxWidth: .infinity, minHeight: 96)
                }

                Spacer()
            }
            .padding(.horizontal, SleepSpacing.xxl)
        }
        .task {
            partnerCountAtOpen = store.partners.count
            await mint()
            await watchForAcceptance()
        }
    }

    /// The whole point of the code: this message works for a friend who
    /// doesn't have SleepBlock yet. The App Store link is Apple's own, so
    /// none of this needs a domain or a web page of ours.
    private func shareMessage(code: String) -> String {
        let pitch = "Be my sleep partner on SleepBlock — we'd see each other's streak and schedule. 🌙"
        guard AppStoreLink.isConfigured else {
            return "\(pitch) Enter code \(code) in the app."
        }
        return """
        \(pitch)

        Get the app: https://apps.apple.com/app/id\(AppStoreLink.appID)
        Then enter code: \(code)
        """
    }

    private func mint() async {
        do {
            code = try await store.createPartnerCode()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Polls while the sheet is up so the sender sees the moment it lands.
    /// Cheap (the same refresh the screen already does on appear) and ends
    /// with the sheet — `task` is cancelled on dismiss.
    private func watchForAcceptance() async {
        guard code != nil else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(5))
            if Task.isCancelled { return }
            await store.refreshReferral()
            if store.partners.count > partnerCountAtOpen {
                let name = store.partners.last?.displayName ?? ""
                Haptics.success()
                store.partnerInviteMessage = name.isEmpty
                    ? "You're now sleep partners."
                    : "You're now sleep partners with \(name)."
                dismiss()
                return
            }
        }
    }
}

/// The receiver's half — the twin of `ReferralRedeemSheet`, pointed at
/// partnership instead of free nights. The server does every check and
/// owns the error copy, including the rate limit that a live, typeable
/// code space needs and a one-time link never did.
struct PartnerCodeEntrySheet: View {
    var store: SleepStore

    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var isRedeeming = false
    @State private var errorMessage: String?
    @FocusState private var fieldFocused: Bool

    var body: some View {
        ZStack {
            SleepColor.background.ignoresSafeArea()
            VStack(spacing: SleepSpacing.xl) {
                VStack(spacing: SleepSpacing.xs) {
                    Text("Enter their code")
                        .font(SleepFont.hero(22))
                        .foregroundStyle(SleepColor.ink)
                    Text("The 6 characters your friend is showing you.")
                        .font(SleepFont.body(14))
                        .foregroundStyle(SleepColor.dim)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, SleepSpacing.xxl)

                TextField("4KM9PX", text: $code)
                    .font(SleepFont.hero(28))
                    .tracking(6)
                    .foregroundStyle(SleepColor.ink)
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .focused($fieldFocused)
                    .padding(.vertical, SleepSpacing.lg)
                    .liquidGlass(cornerRadius: SleepRadius.lg)
                    .onChange(of: code) { _, value in
                        // Mirrors the server's normalization so what the user
                        // sees is exactly what gets checked. Capped at 6 so a
                        // stray keystroke can't silently invalidate the code.
                        let cleaned = String(value.uppercased()
                            .filter { !$0.isWhitespace && $0 != "-" }
                            .prefix(6))
                        if cleaned != value { code = cleaned }
                    }

                if let errorMessage {
                    Text(errorMessage)
                        .font(SleepFont.body(14))
                        .foregroundStyle(SleepColor.danger)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                LiquidPrimaryButton(title: "Connect", isLoading: isRedeeming) {
                    Task { await redeem() }
                }
                .disabled(code.count < 6 || isRedeeming)

                Spacer()
            }
            .padding(.horizontal, SleepSpacing.xxl)
        }
        .onAppear { fieldFocused = true }
    }

    private func redeem() async {
        guard !isRedeeming else { return }
        isRedeeming = true
        errorMessage = nil
        defer { isRedeeming = false }
        do {
            let name = try await store.redeemPartnerCode(code: code)
            Haptics.success()
            store.partnerInviteMessage = name.isEmpty
                ? "You're now sleep partners."
                : "You're now sleep partners with \(name)."
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
