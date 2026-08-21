import Foundation
import TikTokBusinessSDK

// Ad attribution for TikTok App Promotion campaigns. The SDK reports installs
// and launches by itself; this seam adds the three funnel events worth
// optimizing toward — an account created, a trial started, a subscription
// paid for — so TikTok can bid for people who subscribe rather than people
// who tap.
//
// **No App Tracking Transparency prompt, deliberately.** The app never asks
// for tracking permission, so the IDFA is never available and nothing here
// links a person across apps or websites. Attribution runs on Apple's
// SKAdNetwork instead, which needs no consent and is what the SDK falls back
// to. That is a product decision (see DESIGN.md → "Ad attribution"): the
// prompt buys a modest attribution lift and costs an interruption plus a
// second App Review surface (Guideline 5.1.2). If that trade is ever
// revisited, the SDK exposes
// `TikTokBusiness.requestTrackingAuthorization(completionHandler:)` — the SDK
// itself will never raise the dialog on its own.
//
// Like every other service in this app, an unconfigured build is a **silent
// no-op**, not a crash and not a fake: no TikTok keys in Config.xcconfig
// means `isConfigured` is false, `start()` never initializes the SDK, and
// every report returns immediately. Dev builds and the simulator therefore
// send nothing. See docs/development.md ("TikTok ad attribution").

enum SleepTikTok {
    /// Reads the three values the SDK needs, all injected through
    /// Secrets.xcconfig → Info.plist like the Supabase and RevenueCat keys.
    /// `appID` is the numeric App Store id; `tiktokAppID` is the app's id in
    /// TikTok Events Manager; the access token authorizes event reporting.
    private struct Credentials {
        let appID: String
        let tiktokAppID: String
        let accessToken: String
    }

    private static var credentials: Credentials? {
        func value(_ key: String) -> String? {
            let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String
            let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (trimmed?.isEmpty == false) ? trimmed : nil
        }
        guard let appID = value("APPLE_APP_ID"),
              let tiktokAppID = value("TIKTOK_APP_ID"),
              let accessToken = value("TIKTOK_ACCESS_TOKEN")
        else { return nil }
        return Credentials(appID: appID, tiktokAppID: tiktokAppID, accessToken: accessToken)
    }

    /// False on any build without TikTok keys — dev machines, the simulator,
    /// and anyone who cloned the repo. Every entry point below checks it.
    static var isConfigured: Bool { credentials != nil }

    /// Call once, as early in launch as possible: the SDK times the install
    /// and launch events off initialization, and a late start reports them
    /// with the wrong timestamps.
    static func start() {
        guard let credentials else {
            AppLog.app.info("TikTok SDK not configured — ad reporting disabled")
            return
        }
        guard let config = TikTokConfig(
            accessToken: credentials.accessToken,
            appId: credentials.appID,
            tiktokAppId: credentials.tiktokAppID
        ) else {
            AppLog.app.error("TikTok SDK config rejected its own credentials")
            return
        }
        // SKAdNetwork is the whole attribution story without ATT, so it must
        // stay on; the debug flag routes events to Events Manager's test feed
        // instead of production reporting.
        config.skAdNetworkSupportEnabled = true
#if DEBUG
        config.debugModeEnabled = true
#endif
        TikTokBusiness.initializeSdk(config) { success, error in
            if success {
                AppLog.app.info("TikTok SDK initialized")
            } else {
                AppLog.app.error("TikTok SDK init failed: \(error?.localizedDescription ?? "unknown", privacy: .public)")
            }
        }
    }

    /// A new account was created. Mid-funnel signal: trials are sparse enough
    /// early on that TikTok's optimizer learns faster from registrations.
    /// Fired only for genuinely new accounts — a returning user signing in on
    /// a new device is not a registration.
    static func reportRegistration() {
        report(event: .registration)
    }

    /// A subscription was purchased. Sends the trial start and the paid
    /// conversion as separate events when the plan carries a free trial,
    /// because they are different moments to bid on: `StartTrial` happens
    /// now, `Subscribe` carries the money.
    static func reportPurchase(priceValue: Decimal, currencyCode: String?, trialDays: Int) {
        let value = NSDecimalNumber(decimal: priceValue).doubleValue
        // TikTok's value-based optimization needs both halves; without a
        // currency the value is meaningless, so send neither.
        let money: [String: Any]? = currencyCode.map { ["value": value, "currency": $0] }
        if trialDays > 0 {
            report(event: .startTrial, properties: money)
        }
        report(event: .subscribe, properties: money)
    }

#if DEBUG
    /// Fires one of each reported event so the integration can be verified
    /// without a real sign-up and a real purchase — `-review-tiktok-events`,
    /// alongside the other `-review-*` args in docs/development.md. DEBUG
    /// builds set the SDK's debug mode, so these land in Events Manager's
    /// **test** feed, never in production reporting.
    ///
    /// Delayed because `initializeSdk` completes asynchronously (it fetches
    /// remote config first) and events reported before it lands are dropped
    /// rather than queued.
    static func fireReviewEvents() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            reportRegistration()
            reportPurchase(priceValue: 59.99, currencyCode: "USD", trialDays: 7)
        }
    }
#endif

    private static func report(event: TTEventName, properties: [String: Any]? = nil) {
        guard isConfigured else { return }
        let payload = TikTokBaseEvent(eventName: event.rawValue)
        properties?.forEach { payload.addProperty(withKey: $0.key, value: $0.value) }
        TikTokBusiness.trackTTEvent(payload)
        AppLog.app.info("TikTok event: \(event.rawValue, privacy: .public)")
    }
}
