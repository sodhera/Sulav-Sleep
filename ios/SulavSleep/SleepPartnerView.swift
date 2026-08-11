import SwiftUI

// The sleep-partner card, the invite explainer, and the referral-code sheet —
// the visible half of docs/roadmap-partner-referral.md. The card lives on
// Profile's root screen (between the blocked-apps preview and the record)
// and walks the whole partnership lifecycle in one place: invite → request →
// confirmed numbers. The redeem sheet is shared with the paywall's "Have a
// referral code?" entry, because it is the same act in both places.
//
// Grammar notes (DESIGN.md "Sleep partner"): the card is standard glass with
// the section-kicker header, the invite CTA is the Health card's amber
// capsule, and the partner's numbers reuse Home's flame-label and the app's
// clock/duration formatting — a partner's night should read exactly like
// your own.

// MARK: - Partner card (Profile root)

struct SleepPartnerCard: View {
    var store: SleepStore

    @State private var showsRedeemSheet = false
    @State private var confirmingUnlink = false
    @State private var actionError: String?
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: SleepSpacing.md) {
            Text("Sleep partner").sectionLabel()

            VStack(alignment: .leading, spacing: SleepSpacing.md) {
                content
                if let actionError {
                    Text(actionError)
                        .font(SleepFont.body(13))
                        .foregroundStyle(SleepColor.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(SleepSpacing.lg)
            .liquidGlass(cornerRadius: SleepRadius.lg)
        }
        .task { await store.loadReferralCode() }
        .sheet(isPresented: $showsRedeemSheet) {
            ReferralRedeemSheet(store: store)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .alert("Unlink sleep partner?", isPresented: $confirmingUnlink) {
            Button("Unlink", role: .destructive) {
                Task { await run { try await store.unlinkPartner() } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll stop seeing each other's sleep. Either of you can send a new invite later.")
        }
    }

    @ViewBuilder private var content: some View {
        if let partner = store.partnerState?.partner {
            linked(partner)
        } else if let request = store.partnerState?.incomingRequests.first {
            incoming(request)
        } else if store.partnerState?.awaitingConfirmation == true {
            awaiting
        } else {
            empty
        }
    }

    // MARK: Empty — the pitch and the two doors in

    private var empty: some View {
        HStack(alignment: .top, spacing: SleepSpacing.md) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(SleepColor.amber)
                .frame(width: 40, height: 40)
                .background { Circle().fill(SleepColor.glassWarm) }

            VStack(alignment: .leading, spacing: SleepSpacing.sm) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Sleep better together")
                        .font(SleepFont.title(16))
                        .foregroundStyle(SleepColor.ink)
                    Text("See each other's streak and schedule. Your invite gives them 30 nights free — and a month free for you when they subscribe.")
                        .font(SleepFont.body(13))
                        .foregroundStyle(SleepColor.dim)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(2)
                }

                HStack(spacing: SleepSpacing.md) {
                    inviteButton
                    // Hidden once this account has redeemed: one code each.
                    if store.referralStanding == nil {
                        Button {
                            Haptics.heavy()
                            showsRedeemSheet = true
                        } label: {
                            Text("I have a code")
                                .font(SleepFont.label(14))
                                .foregroundStyle(SleepColor.dim)
                                .frame(minHeight: 34)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    /// The amber capsule (the Health card's CTA grammar) wrapping a system
    /// ShareLink. Until the code arrives the capsule stands in, dimmed — the
    /// fetch is one tiny RPC, so this state is rarely seen at all.
    @ViewBuilder private var inviteButton: some View {
        if let text = inviteMessage {
            ShareLink(item: text) {
                inviteLabel
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded { Haptics.heavy() })
        } else {
            inviteLabel.opacity(0.5)
        }
    }

    private var inviteLabel: some View {
        Text("Invite")
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

    private var inviteMessage: String? {
        guard let code = store.myReferralCode else { return nil }
        return "Be my sleep partner on SleepBlock — we'll see each other's streaks, and my code \(code) gets you 30 nights free. https://apps.apple.com/app/id\(AppStoreLink.appID)"
    }

    // MARK: Incoming — the consent moment

    private func incoming(_ request: PartnerRequest) -> some View {
        VStack(alignment: .leading, spacing: SleepSpacing.sm) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(request.name.isEmpty ? "Your friend" : request.name) wants to be your sleep partner")
                    .font(SleepFont.title(16))
                    .foregroundStyle(SleepColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("You'll see each other's streak, schedule, and average sleep. Nothing is shared until you confirm.")
                    .font(SleepFont.body(13))
                    .foregroundStyle(SleepColor.dim)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }

            HStack(spacing: SleepSpacing.md) {
                Button {
                    Haptics.heavy()
                    Task { await run { try await store.confirmPartner(requestID: request.id) } }
                } label: {
                    Text("Confirm")
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

                Button {
                    Haptics.heavy()
                    Task { await run { try await store.declinePartner(requestID: request.id) } }
                } label: {
                    Text("Decline")
                        .font(SleepFont.label(14))
                        .foregroundStyle(SleepColor.dim)
                        .frame(minHeight: 34)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 2)
            .disabled(isWorking)
        }
    }

    // MARK: Awaiting — invitee's side of pending

    private var awaiting: some View {
        HStack(spacing: SleepSpacing.md) {
            Image(systemName: "hourglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(SleepColor.amber)
                .frame(width: 40, height: 40)
                .background { Circle().fill(SleepColor.glassWarm) }
            VStack(alignment: .leading, spacing: 3) {
                Text("Waiting on your friend")
                    .font(SleepFont.title(16))
                    .foregroundStyle(SleepColor.ink)
                Text("They'll confirm from their own Profile — nothing is shared until then.")
                    .font(SleepFont.body(13))
                    .foregroundStyle(SleepColor.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Linked — the partner's numbers

    private func linked(_ partner: PartnerLink) -> some View {
        VStack(alignment: .leading, spacing: SleepSpacing.md) {
            HStack {
                Text(partner.summary?.name.isEmpty == false ? partner.summary!.name : "Your partner")
                    .font(SleepFont.title(16))
                    .foregroundStyle(SleepColor.ink)
                Spacer()
                Button {
                    Haptics.heavy()
                    confirmingUnlink = true
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
                    // Home's flame grammar: filled and amber while alive,
                    // hollow and muted when the run is one miss from gone.
                    partnerStat(
                        label: "Streak",
                        value: Label("\(summary.streak)", systemImage: summary.streakDying ? "flame" : "flame.fill")
                            .foregroundStyle(summary.streakDying ? SleepColor.muted : SleepColor.amber)
                    )
                    if let bed = summary.avgBedMinutes, let wake = summary.avgWakeMinutes {
                        partnerStat(
                            label: "Schedule",
                            value: Text("\(SleepFormatting.clock(bed)) – \(SleepFormatting.clock(wake))")
                                .foregroundStyle(SleepColor.ink)
                        )
                    }
                    if let duration = summary.avgDurationMinutes {
                        partnerStat(
                            label: "Avg sleep",
                            value: Text(SleepFormatting.duration(duration))
                                .foregroundStyle(SleepColor.ink)
                        )
                    }
                }
            } else {
                // A partner who has never synced. Honest-data rule: say so,
                // never render zeroed stats.
                Text("No nights to show yet — their numbers appear after their first sleep.")
                    .font(SleepFont.body(13))
                    .foregroundStyle(SleepColor.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func partnerStat(label: String, value: some View) -> some View {
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

    // MARK: Shared action runner

    private func run(_ work: () async throws -> Void) async {
        actionError = nil
        isWorking = true
        defer { isWorking = false }
        do {
            try await work()
            Haptics.success()
        } catch {
            actionError = error.localizedDescription
        }
    }
}

// MARK: - Invite explainer (Settings → Invite a friend)

/// Pushed from Settings' "Invite a friend" row — the row itself no longer
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
                title: "Invite a friend",
                subtitle: "Turn an invite into a sleep partner — you'll see each other's streak, schedule, and average sleep once they join."
            )

            VStack(alignment: .leading, spacing: SleepSpacing.md) {
                benefitRow(
                    icon: "moon.stars.fill",
                    title: "They get 30 nights free",
                    detail: "Instead of the usual 7 — enough to actually feel the difference."
                )
                benefitRow(
                    icon: "gift.fill",
                    title: "You get a month free",
                    detail: "The moment they subscribe. Applied to your account automatically — nothing to redeem."
                )
            }
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

            Text("Nothing about your sleep is shared until they send a partner request and you confirm it.")
                .font(SleepFont.body(12))
                .foregroundStyle(SleepColor.faint)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .padding(.top, SleepSpacing.xxl)
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
                    Text("Share invite").font(SleepFont.label(16)).tracking(0.2)
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
            Text("Share invite")
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
        "Be my sleep partner on SleepBlock — we'll see each other's streaks, and my code \(code) gets you 30 nights free. https://apps.apple.com/app/id\(AppStoreLink.appID)"
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
