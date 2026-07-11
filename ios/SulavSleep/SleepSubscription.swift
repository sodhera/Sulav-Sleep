import Foundation
import RevenueCat

// Subscriptions via RevenueCat, behind a protocol like every other system
// integration (`SleepHealthProviding`, `ScreenTimeControlling`, `AuthProviding`)
// so the store and the paywall stay SDK-free and testable.
//
// The model is a **hard paywall with a free trial**: after onboarding, the
// only way into the app is starting the trial (an App Store intro offer on
// the annual plan) or subscribing — see `RootView` and DESIGN.md. The gate
// hinges on one entitlement, `pro`.
//
// Configuration lives in `REVENUECAT_API_KEY` (Secrets/Config.xcconfig →
// Info.plist, same plumbing as the Supabase keys). An **empty key means dev
// mode**: `isConfigured` is false, the store reports `.entitled`, and the
// paywall never shows — so the Simulator and fresh clones keep working with
// zero setup. See docs/development.md for the dashboard-side setup.

/// What the gate knows about the user's entitlement. `.unknown` means the
/// first CustomerInfo fetch hasn't resolved yet — the gate must never flash
/// the paywall (or Main) off an unknown, only off a resolved answer.
enum EntitlementState: Equatable {
    case unknown
    case entitled
    case notEntitled
}

/// One purchasable plan, mapped out of RevenueCat's `Package` so views never
/// import the SDK. `id` round-trips back to the package on purchase.
struct SleepPlan: Identifiable, Equatable {
    var id: String
    var title: String            // "Yearly" / "Monthly"
    var priceString: String      // localized, e.g. "$39.99"
    var periodUnit: String       // "year" / "month"
    var perMonthString: String?  // annual plans: localized monthly equivalent
    var trialDays: Int           // 0 when the product carries no intro trial
    var isAnnual: Bool
}

protocol SubscriptionProviding {
    /// False when no API key is present (dev mode) — the gate stands down.
    var isConfigured: Bool { get }
    /// Configure the SDK and start streaming entitlement changes. `onChange`
    /// fires on the main actor with every resolved CustomerInfo, including
    /// the first fetch.
    func start(onChange: @escaping @MainActor (EntitlementState) -> Void)
    /// Tie the RevenueCat identity to the signed-in account so a
    /// subscription follows the user across devices and reinstalls.
    func logIn(accountID: String) async
    func logOut() async
    /// The current offering's plans, annual first. Empty on failure — the
    /// paywall shows a retry, never a broken sheet.
    func fetchPlans() async -> [SleepPlan]
    /// Runs the purchase flow. Returns the resolved state, `nil` when the
    /// user cancelled (not an error), or throws with a user-facing message.
    func purchase(planID: String) async throws -> EntitlementState?
    func restore() async throws -> EntitlementState
}

enum SleepSubscription {
    /// The single entitlement the app checks, as configured in RevenueCat.
    static let entitlementID = "pro"

    static func makeDefault() -> SubscriptionProviding {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-review-paywall") {
            return ReviewPaywallSubscriptionService()
        }
#endif
        return RevenueCatSubscriptionService()
    }
}

#if DEBUG
/// Deterministic App Review screenshot data. This exists only in Debug builds
/// and is activated explicitly with `-review-paywall`; Release builds cannot
/// compile or select it. It lets us capture the real SwiftUI paywall before
/// App Store Connect has propagated the live subscription metadata.
private final class ReviewPaywallSubscriptionService: SubscriptionProviding {
    var isConfigured: Bool { true }

    func start(onChange: @escaping @MainActor (EntitlementState) -> Void) {
        Task { @MainActor in onChange(.notEntitled) }
    }

    func logIn(accountID: String) async {}
    func logOut() async {}

    func fetchPlans() async -> [SleepPlan] {
        [
            SleepPlan(
                id: "$rc_annual",
                title: "Yearly",
                priceString: "$59.99",
                periodUnit: "year",
                perMonthString: "$5.00",
                trialDays: 7,
                isAnnual: true
            ),
            SleepPlan(
                id: "$rc_monthly",
                title: "Monthly",
                priceString: "$5.99",
                periodUnit: "month",
                perMonthString: nil,
                trialDays: 0,
                isAnnual: false
            )
        ]
    }

    func purchase(planID: String) async throws -> EntitlementState? { nil }
    func restore() async throws -> EntitlementState { .notEntitled }
}
#endif

/// User-facing purchase failures. Cancellation is not one of them.
struct SubscriptionError: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}

final class RevenueCatSubscriptionService: SubscriptionProviding {
    private static var isSDKConfigured = false

    private let apiKey: String

    init() {
        let raw = Bundle.main.object(forInfoDictionaryKey: "REVENUECAT_API_KEY") as? String
        apiKey = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    var isConfigured: Bool { !apiKey.isEmpty }

    func start(onChange: @escaping @MainActor (EntitlementState) -> Void) {
        guard isConfigured else {
            AppLog.paywall.notice("REVENUECAT_API_KEY empty — paywall disabled (dev mode)")
            return
        }
        if !Self.isSDKConfigured {
            Purchases.logLevel = .warn
            Purchases.configure(withAPIKey: apiKey)
            Self.isSDKConfigured = true
            AppLog.paywall.info("RevenueCat configured")
        }
        // The stream replays the cached CustomerInfo immediately (offline-
        // friendly: a subscriber whose network is down at 7am still resolves
        // entitled from cache) and then follows every change — purchases,
        // renewals, restores, logIn identity switches.
        Task { @MainActor in
            for await info in Purchases.shared.customerInfoStream {
                onChange(Self.state(of: info))
            }
        }
    }

    func logIn(accountID: String) async {
        guard isConfigured else { return }
        do {
            _ = try await Purchases.shared.logIn(accountID)
            AppLog.paywall.info("RevenueCat identity linked")
        } catch {
            // Non-fatal: the anonymous ID keeps working; the entitlement
            // stream stays live either way.
            AppLog.paywall.error("RevenueCat logIn failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func logOut() async {
        guard isConfigured, !Purchases.shared.isAnonymous else { return }
        do {
            _ = try await Purchases.shared.logOut()
            AppLog.paywall.info("RevenueCat identity cleared")
        } catch {
            AppLog.paywall.error("RevenueCat logOut failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func fetchPlans() async -> [SleepPlan] {
        guard isConfigured else { return [] }
        do {
            guard let offering = try await Purchases.shared.offerings().current else {
                AppLog.paywall.error("No current offering configured in RevenueCat")
                return []
            }
            let plans = offering.availablePackages.compactMap(Self.plan(from:))
            return plans.sorted { $0.isAnnual && !$1.isAnnual }
        } catch {
            AppLog.paywall.error("Offerings fetch failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func purchase(planID: String) async throws -> EntitlementState? {
        guard isConfigured else { return .entitled }
        guard let package = try? await Purchases.shared.offerings().current?
            .availablePackages.first(where: { $0.identifier == planID })
        else {
            throw SubscriptionError(message: "That plan isn't available right now. Try again.")
        }
        do {
            let result = try await Purchases.shared.purchase(package: package)
            if result.userCancelled { return nil }
            AppLog.paywall.info("Purchase completed (plan=\(planID, privacy: .public))")
            return Self.state(of: result.customerInfo)
        } catch let error as ErrorCode where error == .purchaseCancelledError {
            return nil
        } catch {
            AppLog.paywall.error("Purchase failed: \(error.localizedDescription, privacy: .public)")
            throw SubscriptionError(message: "The purchase didn't go through. You haven't been charged — try again.")
        }
    }

    func restore() async throws -> EntitlementState {
        guard isConfigured else { return .entitled }
        do {
            let info = try await Purchases.shared.restorePurchases()
            let state = Self.state(of: info)
            AppLog.paywall.info("Restore finished (entitled=\(state == .entitled))")
            return state
        } catch {
            AppLog.paywall.error("Restore failed: \(error.localizedDescription, privacy: .public)")
            throw SubscriptionError(message: "Couldn't reach the App Store to restore. Try again.")
        }
    }

    // MARK: - Mapping

    private static func state(of info: CustomerInfo) -> EntitlementState {
        info.entitlements[SleepSubscription.entitlementID]?.isActive == true ? .entitled : .notEntitled
    }

    private static func plan(from package: Package) -> SleepPlan? {
        let product = package.storeProduct
        guard let period = product.subscriptionPeriod else { return nil }

        let isAnnual = period.unit == .year
        let title: String
        let periodUnit: String
        switch period.unit {
        case .year: title = "Yearly"; periodUnit = "year"
        case .month: title = "Monthly"; periodUnit = "month"
        case .week: title = "Weekly"; periodUnit = "week"
        case .day: title = "Daily"; periodUnit = "day"
        }

        // Trial length from the App Store intro offer, in days. Only free
        // trials count — pay-up-front intro pricing is not "N nights free".
        var trialDays = 0
        if let intro = product.introductoryDiscount, intro.paymentMode == .freeTrial {
            let length = intro.subscriptionPeriod
            switch length.unit {
            case .day: trialDays = length.value
            case .week: trialDays = length.value * 7
            case .month: trialDays = length.value * 30
            case .year: trialDays = length.value * 365
            }
        }

        // The annual card carries its monthly equivalent so the two plans
        // compare at a glance, formatted in the product's own locale/currency.
        var perMonth: String?
        if isAnnual {
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            if let locale = product.priceFormatter?.locale {
                formatter.locale = locale
            }
            formatter.currencyCode = product.currencyCode
            let monthly = (product.price as NSDecimalNumber).dividing(by: 12)
            perMonth = formatter.string(from: monthly)
        }

        return SleepPlan(
            id: package.identifier,
            title: title,
            priceString: product.localizedPriceString,
            periodUnit: periodUnit,
            perMonthString: perMonth,
            trialDays: trialDays,
            isAnnual: isAnnual
        )
    }
}
