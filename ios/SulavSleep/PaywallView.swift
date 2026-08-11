import SwiftUI

// The subscription pitch. It appears twice, and it is the same screen both
// times: once as onboarding's closing beat (the moment to sell — the user
// just told us their name, what breaks their sleep, and which apps eat their
// night), and thereafter whenever a locked user reaches for the one thing the
// subscription buys, starting a night.
//
// It is a **soft paywall**: the ✕ closes it and drops the user into the app,
// where they can look at everything and start nothing. That is the deal the
// lock enforces — see `SleepStore.isLocked`, `HomeView`'s Sleep Now, and
// DESIGN.md ("Paywall"). docs/development.md covers the RevenueCat setup.
//
// Both presentations show this only when the entitlement has *resolved* to
// not-entitled — never off `.unknown`, and never on an unconfigured (dev)
// build — so the paywall can assume RevenueCat is live.

struct PaywallView: View {
    let store: SleepStore
    /// Closes the paywall. Distinct per presentation: the first-run route
    /// records the dismissal (`SleepStore.dismissPaywall`), the cover over
    /// Main simply lowers itself.
    var onClose: () -> Void

    @State private var plans: [SleepPlan] = []
    @State private var loadFailed = false
    @State private var selectedPlanID: String?
    @State private var isPurchasing = false
    @State private var isRestoring = false
    @State private var showsRedeemSheet = false
    /// Failure or guidance shown above the CTA — same two-tone grammar as
    /// the auth screen: `danger` for failures, `amber` for normal next steps.
    @State private var message: String?
    @State private var messageIsNotice = false

    /// Terms points at Apple's Standard EULA (the app's App Store Connect
    /// license agreement), which is professionally drafted and applies by
    /// default; Privacy points at the app's own policy (Apple provides no
    /// privacy policy). Both links are required on a paywall.
    private static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    private static let privacyURL = URL(string: "https://www.orecci.com/sleepblock/privacy-policy.html")!

    private var selectedPlan: SleepPlan? {
        plans.first { $0.id == selectedPlanID }
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: SleepSpacing.xxxl) {
                    // A flexible spacer above the hero *and* below it (before
                    // the cards) splits the free space between them, so the
                    // brand mark + headline sit lower — near the upper third
                    // rather than jammed under the status bar — instead of
                    // leaving all the emptiness in one gap below the headline.
                    Spacer(minLength: SleepSpacing.huge)
                    header
                    if plans.isEmpty {
                        if loadFailed { loadFailureState } else { loadingState }
                    } else {
                        // The lower flexible spacer keeps the cards and CTA
                        // anchored low no matter the device height.
                        Spacer(minLength: SleepSpacing.huge)
                        VStack(spacing: SleepSpacing.xxxl) {
                            planPicker
                            purchaseBlock
                        }
                    }
                }
                .padding(.horizontal, SleepSpacing.xxl)
                .padding(.top, SleepSpacing.xl)
                .padding(.bottom, SleepSpacing.lg)
                .frame(minHeight: proxy.size.height, alignment: .top)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .safeAreaInset(edge: .bottom) { footer }
        // Floated over the scroll rather than placed in it: the header is a
        // centered brand lockup, and giving the ✕ a row of its own would
        // push the whole pitch down a line on every device. Top-*trailing*
        // is where this app's other closes live (the settings sheet), and it
        // keeps the corner opposite the back chevron of onboarding, which
        // this screen follows.
        .overlay(alignment: .topTrailing) { closeButton }
        .task { await loadPlans() }
    }

    /// The way out. Quiet on purpose — smaller and dimmer than the app's
    /// other icon buttons — because it should be findable without competing
    /// with the CTA. It is never hidden or delayed: a paywall that hides its
    /// exit for three seconds is the pattern App Review rejects, and it reads
    /// as a trap to the user long before it reads as a conversion tactic.
    private var closeButton: some View {
        GlassIconButton(systemImage: "xmark", size: 40, iconSize: 15, tint: SleepColor.muted) {
            onClose()
        }
        .padding(.trailing, SleepSpacing.lg)
        .padding(.top, SleepSpacing.sm)
        .accessibilityLabel("Close")
    }

    // MARK: - Header

    /// Brand mark, the "SleepBlock" wordmark, then one headline — no subtext.
    /// The wordmark signs the screen (the same identity the welcome screen
    /// leads with); the headline answers the plan currently selected rather
    /// than repeating the cards: the trial plan gets the trial pitch, the
    /// no-trial plan gets the app's own pitch.
    private var header: some View {
        VStack(spacing: SleepSpacing.xl) {
            // Logo + wordmark are one brand lockup: the wordmark is a small,
            // tracked signature sitting tight under the mark — deliberately
            // *quieter* than the headline (smaller, dim, letter-spaced) so
            // it never competes with the pitch. When it matched the
            // headline's size and weight the two read as twin headlines with
            // no hierarchy.
            VStack(spacing: SleepSpacing.xs) {
                SlothBrandMark(width: 140, zScale: 0.58)
                Text("SleepBlock")
                    .font(SleepFont.label(15))
                    .tracking(2.5)
                    .textCase(.uppercase)
                    .foregroundStyle(SleepColor.dim)
            }
            Text(headline)
                .font(SleepFont.hero(30))
                .foregroundStyle(SleepColor.ink)
                .multilineTextAlignment(.center)
                // The flexible spacer lower in this VStack proposes a very
                // wide, very short frame while solving for the screen's
                // minHeight; without this, that pass wins and the headline
                // renders single-line and clips instead of wrapping.
                .fixedSize(horizontal: false, vertical: true)
                .animation(.easeInOut(duration: 0.18), value: selectedPlanID)
        }
        .frame(maxWidth: .infinity)
    }

    private var headline: String {
        // A user whose free nights just ran out gets the loss-aversion hook —
        // the streak (and partner) they built over the month — instead of a
        // cold pitch. The trial badge/CTA/subline still carry the mechanics;
        // only the emotional line changes. See `SleepStore.referralExpiryHeadline`.
        if let expiry = store.referralExpiryHeadline { return expiry }
        guard let plan = selectedPlan else { return "Lock your nights in" }
        guard plan.trialDays > 0 else {
            return "Unlock SleepBlock to build a sleep routine that sticks"
        }
        let nightWord = plan.trialDays == 1 ? "night" : "nights"
        return "Start your \(plan.trialDays)-\(nightWord) FREE trial to continue"
    }

    // MARK: - Plans

    private var planPicker: some View {
        LiquidGlassContainer(spacing: SleepSpacing.md) {
            VStack(spacing: SleepSpacing.md) {
                ForEach(plans) { plan in
                    PlanCard(
                        plan: plan,
                        isSelected: plan.id == selectedPlanID,
                        savingsPercent: plan.isAnnual ? annualSavingsPercent : nil
                    ) {
                        Haptics.heavy()
                        selectedPlanID = plan.id
                    }
                }
            }
        }
        // The badge hangs on the container, not the card: inside a
        // GlassEffectContainer the composited glass draws over any overlay
        // attached to a glass card, so a card-level badge renders half
        // behind its own surface. The trial plan is always sorted first, so
        // the container's top edge *is* the annual card's top edge.
        .overlay(alignment: .top) { trialBadge }
    }

    /// The annual card's own headline states the savings, so it needs the
    /// real number rather than a hardcoded guess. Computed from the two
    /// fetched plans' raw prices — never hand-picked, since it must track
    /// whatever RevenueCat actually returns.
    private var annualSavingsPercent: Int? {
        guard let annual = plans.first(where: { $0.isAnnual }),
              let monthly = plans.first(where: { !$0.isAnnual }),
              monthly.priceValue > 0
        else { return nil }
        let annualMonthly = annual.priceValue / 12
        let savings = (1 - annualMonthly / monthly.priceValue) * 100
        return Int((savings as NSDecimalNumber).doubleValue.rounded())
    }

    @ViewBuilder private var trialBadge: some View {
        if let trial = plans.first, trial.trialDays > 0 {
            Text("\(trial.trialDays) NIGHTS FREE")
                .font(SleepFont.label(11))
                .tracking(1.4)
                .foregroundStyle(SleepColor.background)
                .padding(.horizontal, SleepSpacing.md)
                .padding(.vertical, 5)
                .background(Capsule().fill(SleepColor.amber))
                .opacity(trial.id == selectedPlanID ? 1 : 0.55)
                .offset(y: -12)
                .allowsHitTesting(false)
                .animation(.easeInOut(duration: 0.18), value: selectedPlanID)
                .accessibilityHidden(true)
        }
    }

    private var purchaseBlock: some View {
        VStack(spacing: SleepSpacing.md) {
            if let message {
                Text(message)
                    .font(SleepFont.body(14))
                    .foregroundStyle(messageIsNotice ? SleepColor.amber : SleepColor.danger)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            LiquidPrimaryButton(title: ctaTitle, isLoading: isPurchasing) {
                Task { await purchase() }
            }
            .disabled(isPurchasing || isRestoring || selectedPlan == nil)

            if let plan = selectedPlan {
                Text(renewalLine(for: plan))
                    .font(SleepFont.body(13))
                    .foregroundStyle(SleepColor.muted)
            }

            // The referred user's door, directly under the money: a friend's
            // code beats every plan on this screen, so it must be findable
            // here — but quietly, in the footer's type, because for most
            // people it's an answer to a question they weren't asked. Hidden
            // once this account has redeemed (one code each) and in dev mode.
            if store.referralAvailable && store.referralStanding == nil {
                Button {
                    Haptics.heavy()
                    showsRedeemSheet = true
                } label: {
                    Text("Have a referral code?")
                        .font(SleepFont.body(13))
                        .foregroundStyle(SleepColor.dim)
                        .frame(minHeight: 34)
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showsRedeemSheet) {
                    // On success the lock recomputes and the paywall route
                    // falls through to Main on its own; the cover variant is
                    // closed explicitly for the same reason as purchase.
                    ReferralRedeemSheet(store: store)
                        .presentationDetents([.medium])
                        .presentationDragIndicator(.visible)
                        .onDisappear {
                            if store.isWithinReferralNights { onClose() }
                        }
                }
            }
        }
    }

    private var ctaTitle: String {
        guard let plan = selectedPlan else { return "Continue" }
        return plan.trialDays > 0 ? "Start \(plan.trialDays) nights free" : "Continue"
    }

    private func renewalLine(for plan: SleepPlan) -> String {
        plan.trialDays > 0
            ? "Then \(plan.priceString) per \(plan.periodUnit) · cancel anytime"
            : "\(plan.priceString) per \(plan.periodUnit) · cancel anytime"
    }

    // MARK: - Loading / failure

    private var loadingState: some View {
        VStack(spacing: SleepSpacing.lg) {
            ProgressView()
                .tint(SleepColor.amber)
            Text("Loading plans…")
                .font(SleepFont.body(14))
                .foregroundStyle(SleepColor.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SleepSpacing.huge)
    }

    private var loadFailureState: some View {
        VStack(spacing: SleepSpacing.lg) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(SleepColor.amber)
                .frame(width: 52, height: 52)
                .background { Circle().fill(SleepColor.amber.opacity(0.12)) }
            Text("Couldn't load the plans.\nCheck your connection and try again.")
                .font(SleepFont.body(15))
                .foregroundStyle(SleepColor.dim)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
            LiquidSecondaryButton(title: "Try again") {
                Task { await loadPlans() }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SleepSpacing.xxl)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: SleepSpacing.sm) {
            footerButton(isRestoring ? "Restoring…" : "Restore purchases") {
                Task { await restore() }
            }
            .disabled(isRestoring || isPurchasing)
            footerDot
            Link(destination: Self.termsURL) { footerLabel("Terms") }
            footerDot
            Link(destination: Self.privacyURL) { footerLabel("Privacy") }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SleepSpacing.md)
        .background {
            // The footer rides over the scrolling content; a soft floor of
            // the scene's own navy keeps it legible without reading as a bar.
            LinearGradient(
                colors: [SleepColor.background.opacity(0), SleepColor.background.opacity(0.85)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }

    private func footerButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.heavy()
            action()
        } label: {
            footerLabel(title)
        }
    }

    private func footerLabel(_ title: String) -> some View {
        Text(title)
            .font(SleepFont.body(13))
            .foregroundStyle(SleepColor.muted)
            .frame(minHeight: 44)
    }

    private var footerDot: some View {
        Circle().fill(SleepColor.faint).frame(width: 2.5, height: 2.5)
    }

    // MARK: - Actions

    private func loadPlans() async {
        loadFailed = false
        let fetched = await store.fetchPlans()
        plans = fetched
        loadFailed = fetched.isEmpty
        // Annual (with its trial) is the default choice; keep any existing
        // selection across a retry.
        if selectedPlan == nil {
            selectedPlanID = fetched.first?.id
        }
    }

    private func purchase() async {
        guard let plan = selectedPlan, !isPurchasing else { return }
        isPurchasing = true
        message = nil
        defer { isPurchasing = false }
        do {
            guard let entitled = try await store.purchase(planID: plan.id) else { return } // cancelled
            if entitled {
                Haptics.success()
                // The first-run route disappears on its own as `needsPaywall`
                // flips, but the cover over Main is held up by its own flag
                // and would otherwise stay parked over the app the user just
                // paid for. Closing both is correct; the route is already gone
                // by the time this runs.
                onClose()
            } else {
                message = "The App Store confirmed the purchase but the subscription isn't active yet. Try Restore purchases in a moment."
                messageIsNotice = true
            }
        } catch {
            message = error.localizedDescription
            messageIsNotice = false
        }
    }

    private func restore() async {
        guard !isRestoring else { return }
        isRestoring = true
        message = nil
        defer { isRestoring = false }
        do {
            if try await store.restorePurchases() {
                Haptics.success()
                onClose()
            } else {
                message = "No subscription to restore on this Apple ID."
                messageIsNotice = true
            }
        } catch {
            message = error.localizedDescription
            messageIsNotice = false
        }
    }
}

// MARK: - Pieces

/// One selectable plan: an interactive glass rounded-rect carrying **one
/// price fact** — the annual card's price is its monthly equivalent (the
/// full price lives in a quiet "billed annually" subline and the renewal
/// line), the monthly card's price is simply its own. The trial is not card
/// text: it rides the top edge as an amber capsule badge (`trialBadge`,
/// attached at the picker level — see planPicker). The annual card's title
/// states the deal itself ("Start for free & save 17%") rather than naming
/// the period — the period is already implied by "billed annually" beneath
/// it, and stating the savings is what actually moves someone off the
/// monthly card. Selection is the
/// onboarding grammar: constant glass
/// tint (toggling it rebuilds the effect and lags the tap — see
/// StruggleRow), amber ring + filled circle when chosen; the unselected
/// card dims so the chosen plan reads first.
private struct PlanCard: View {
    let plan: SleepPlan
    let isSelected: Bool
    var savingsPercent: Int?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: SleepSpacing.md) {
                VStack(alignment: .leading, spacing: SleepSpacing.xs) {
                    Text(titleText)
                        .font(SleepFont.label(17))
                        .foregroundStyle(SleepColor.ink)
                        // The savings headline is long enough to need two
                        // lines on narrower phones. Without this, the HStack
                        // measures Text at its unwrapped ideal width, then
                        // clips it to an ellipsis instead of wrapping once
                        // the trailing price/checkmark claim their space.
                        .fixedSize(horizontal: false, vertical: true)
                    if plan.isAnnual {
                        Text("\(plan.priceString) billed annually")
                            .font(SleepFont.body(13))
                            .foregroundStyle(SleepColor.muted)
                    }
                }
                // Claims the leftover width outright rather than leaving it
                // to Spacer's minLength, so the title actually gets the full
                // space to wrap into.
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(priceLine)
                    .font(SleepFont.title(17))
                    .foregroundStyle(SleepColor.ink)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(isSelected ? SleepColor.amber : SleepColor.faint)
            }
            .padding(.horizontal, SleepSpacing.xl)
            .padding(.vertical, SleepSpacing.lg)
            .frame(maxWidth: .infinity, minHeight: 68)
            .contentShape(RoundedRectangle(cornerRadius: SleepRadius.lg, style: .continuous))
            .opacity(isSelected ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .liquidGlass(cornerRadius: SleepRadius.lg, interactive: true)
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: SleepRadius.lg, style: .continuous)
                    .stroke(SleepColor.amber.opacity(0.45), lineWidth: 1)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel(accessibilitySummary)
    }

    private var titleText: String {
        guard plan.isAnnual, let percent = savingsPercent else { return plan.title }
        return plan.trialDays > 0 ? "Start for free & save \(percent)%" : "Save \(percent)%"
    }

    private var priceLine: String {
        if plan.isAnnual, let perMonth = plan.perMonthString {
            return "\(perMonth)/mo"
        }
        switch plan.periodUnit {
        case "month": return "\(plan.priceString)/mo"
        case "week": return "\(plan.priceString)/wk"
        case "year": return "\(plan.priceString)/yr"
        default: return plan.priceString
        }
    }

    /// The badge and subline are visual shorthand; the label reads the whole
    /// card back in one sentence. Uses `plan.title` ("Yearly"/"Monthly")
    /// rather than the savings headline — VoiceOver needs the period name
    /// even when the on-screen title doesn't say it.
    private var accessibilitySummary: String {
        var parts = [plan.title, "\(plan.priceString) per \(plan.periodUnit)"]
        if plan.trialDays > 0 { parts.append("\(plan.trialDays) nights free") }
        if plan.isAnnual, let perMonth = plan.perMonthString { parts.append("\(perMonth) per month") }
        if let percent = savingsPercent, plan.isAnnual { parts.append("saves \(percent)% versus monthly") }
        return parts.joined(separator: ", ")
    }
}
