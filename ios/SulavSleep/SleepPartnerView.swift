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

/// The one home for sleep partners: the list, adding, and unlinking. Presented
/// as a sheet from Home's top-right button (and raised automatically when a
/// partner-invite link is tapped). A partner's numbers reuse Home's flame and
/// the app's clock/duration formatting — a partner's night reads exactly like
/// your own.
struct SleepPartnersScreen: View {
    var store: SleepStore

    @Environment(\.dismiss) private var dismiss
    @State private var isMintingInvite = false
    @State private var justCopied = false
    @State private var errorMessage: String?
    @State private var unlinkTarget: PartnerLink?

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

                    addButton.padding(.top, SleepSpacing.xl)
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

    /// Mints an invite link and copies it to the clipboard, then flips its own
    /// label to "Link copied" for a beat. Copy (not a share sheet) because the
    /// user pastes it wherever they're already talking to their friend; the
    /// label change is the confirmation that the copy happened.
    private var addButton: some View {
        Button {
            Haptics.heavy()
            Task { await copyInvite() }
        } label: {
            HStack(spacing: SleepSpacing.sm) {
                if isMintingInvite {
                    ProgressView().tint(SleepColor.background)
                } else {
                    Image(systemName: justCopied ? "checkmark" : "link")
                    Text(buttonTitle).font(SleepFont.label(16)).tracking(0.2)
                }
            }
            .foregroundStyle(SleepColor.background)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background {
                Capsule(style: .continuous).fill(LinearGradient(
                    colors: [SleepColor.gold, SleepColor.amber],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .animation(.easeInOut(duration: 0.18), value: justCopied)
        }
        .buttonStyle(.plain)
        .disabled(isMintingInvite)
    }

    private var buttonTitle: String {
        if justCopied { return "Link copied" }
        return store.partners.isEmpty ? "Copy invite link" : "Copy a new invite link"
    }

    private var unlinkBinding: Binding<Bool> {
        Binding(get: { unlinkTarget != nil }, set: { if !$0 { unlinkTarget = nil } })
    }

    private func copyInvite() async {
        guard !isMintingInvite else { return }
        isMintingInvite = true
        errorMessage = nil
        do {
            let url = try await store.createPartnerInviteURL()
            UIPasteboard.general.string = url.absoluteString
            isMintingInvite = false
            Haptics.success()
            withAnimation { justCopied = true }
            // Revert the label after a beat; a fresh tap mints a fresh link.
            try? await Task.sleep(for: .seconds(2))
            withAnimation { justCopied = false }
        } catch {
            isMintingInvite = false
            errorMessage = error.localizedDescription
        }
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
