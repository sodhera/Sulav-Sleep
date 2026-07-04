import ManagedSettings
import ManagedSettingsUI
import UIKit

// ShieldActionExtension: handles button taps on the shield overlay when the
// user tries to open a blocked app during sleep. The primary button opens
// SleepBlock via a URL scheme so the user lands on the sleep screen. The
// secondary button simply dismisses the shield.
//
// Note: ShieldActionExtensions run in their own sandboxed process. Direct
// UIApplication.shared is not available. We open the URL through the
// extensionContext or low-level API.

class ShieldActionHandler: ShieldActionDelegate {

    override func handle(action: ShieldAction,
                         for application: ApplicationToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        handleAction(action, completionHandler: completionHandler)
    }

    override func handle(action: ShieldAction,
                         for category: ActivityCategoryToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        handleAction(action, completionHandler: completionHandler)
    }

    override func handle(action: ShieldAction,
                         for webDomain: WebDomainToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        handleAction(action, completionHandler: completionHandler)
    }

    private func handleAction(_ action: ShieldAction,
                              completionHandler: @escaping (ShieldActionResponse) -> Void) {
        switch action {
        case .primaryButtonPressed:
            // Attempting to open the main app directly via URL scheme is blocked
            // by Apple in the ShieldAction API. The standard approach is to just
            // close the shield and rely on the user to open the app manually, or
            // trigger a local notification. We will just close the shield.
            completionHandler(.close)

        case .secondaryButtonPressed:
            // Just dismiss the shield — the app underneath stays blocked.
            completionHandler(.close)

        @unknown default:
            completionHandler(.close)
        }
    }
}
