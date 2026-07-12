import SwiftUI

// The subscription gate — the last screen before Main, right after the
// sign-up questionnaire commits. Deliberately a **hard paywall**: no ✕, no
// "not now". The primary action starts the App Store free trial (an intro
// offer on the annual plan), so nobody pays blind — but starting the trial
// or subscribing is the only way in. The moment to sell is now: the user
// just told us their name, what breaks their sleep, and which apps eat
// their night, and the copy answers with exactly those apps. See DESIGN.md
// ("Paywall") and docs/development.md for the RevenueCat setup.
//
// RootView shows this only when the entitlement has *resolved* to
// not-entitled — never off `.unknown`, and never on an unconfigured (dev)
// build — so the paywall can assume RevenueCat is live.

struct PaywallView: View {
    let store: SleepStore

    @State private var plans: [SleepPlan] = []
    @State private var loadFailed = false
    @State private var selectedPlanID: String?
    @State private var isPurchasing = false
    @State private var isRestoring = false
    /// Failure or guidance shown above the CTA — same two-tone grammar as
    /// the auth screen: `danger` for failures, `amber` for normal next steps.
    @State private var message: String?
    @State private var messageIsNotice = false

    /// Apple's standard EULA covers subscription terms until the app ships
    /// its own. The privacy URL must point at the app's real policy before
    /// App Store review — both links are required on a paywall.
    private static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    private static let privacyURL = URL(string: "https://sodhera.com/sleepblock/privacy")!

    private var selectedPlan: SleepPlan? {
        plans.first { $0.id == selectedPlanID }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: SleepSpacing.xxxl) {
                header
                if plans.isEmpty {
                    if loadFailed { loadFailureState } else { loadingState }
                } else {
                    planPicker
                    purchaseBlock
                }
            }
            .padding(.horizontal, SleepSpacing.xxl)
            .padding(.top, SleepSpacing.xl)
            .padding(.bottom, SleepSpacing.lg)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) { footer }
        .task { await loadPlans() }
    }

    // MARK: - Header

    /// Headline plus exactly one supporting line — the personalization
    /// payload. The apps the user just named on the time-sink question are
    /// the whole pitch; everything else the old feature list said is already
    /// told by the plan cards and the renewal line.
    private var header: some View {
        VStack(spacing: SleepSpacing.lg) {
            SlothBrandMark(width: 110, zScale: 0.55)
            VStack(spacing: SleepSpacing.md) {
                Text("Lock your nights in")
                    .font(SleepFont.title(28))
                    .foregroundStyle(SleepColor.ink)
                    .multilineTextAlignment(.center)
                Text(lockLine)
                    .font(SleepFont.body(15))
                    .foregroundStyle(SleepColor.dim)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var lockLine: String {
        let names = (store.profile?.timeSinkApps ?? [])
            .compactMap { TimeSinkApp(rawValue: $0)?.title }
        switch names.count {
        case 0: return "Your chosen apps, locked while you sleep."
        case 1: return "\(names[0]), locked while you sleep."
        case 2: return "\(names[0]) and \(names[1]), locked while you sleep."
        default: return "\(names[0]), \(names[1]) and more, locked while you sleep."
        }
    }

    // MARK: - Plans

    private var planPicker: some View {
        LiquidGlassContainer(spacing: SleepSpacing.md) {
            VStack(spacing: SleepSpacing.md) {
                ForEach(plans) { plan in
                    PlanCard(plan: plan, isSelected: plan.id == selectedPlanID) {
                        Haptics.heavy()
                        selectedPlanID = plan.id
                    }
                }
            }
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
                // RootView swaps to Main as `needsPaywall` flips.
                Haptics.success()
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
/// text: it rides the top edge as an amber capsule badge in the primary
/// button's colors. Selection is the onboarding grammar: constant glass
/// tint (toggling it rebuilds the effect and lags the tap — see
/// StruggleRow), amber ring + filled circle when chosen; the unselected
/// card dims so the chosen plan reads first.
private struct PlanCard: View {
    let plan: SleepPlan
    let isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: SleepSpacing.md) {
                VStack(alignment: .leading, spacing: SleepSpacing.xs) {
                    Text(plan.title)
                        .font(SleepFont.label(16))
                        .foregroundStyle(SleepColor.ink)
                    if plan.isAnnual {
                        Text("\(plan.priceString) billed annually")
                            .font(SleepFont.body(13))
                            .foregroundStyle(SleepColor.muted)
                    }
                }
                Spacer(minLength: SleepSpacing.md)
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
        .overlay(alignment: .top) {
            if plan.trialDays > 0 {
                Text("\(plan.trialDays) NIGHTS FREE")
                    .font(SleepFont.label(11))
                    .tracking(1.4)
                    .foregroundStyle(SleepColor.background)
                    .padding(.horizontal, SleepSpacing.md)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(SleepColor.amber))
                    .opacity(isSelected ? 1 : 0.55)
                    .offset(y: -12)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel(accessibilitySummary)
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
    /// card back in one sentence.
    private var accessibilitySummary: String {
        var parts = [plan.title, "\(plan.priceString) per \(plan.periodUnit)"]
        if plan.trialDays > 0 { parts.append("\(plan.trialDays) nights free") }
        if plan.isAnnual, let perMonth = plan.perMonthString { parts.append("\(perMonth) per month") }
        return parts.joined(separator: ", ")
    }
}
