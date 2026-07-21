import ManagedSettings
import ManagedSettingsUI
import UIKit
import UserNotifications

// ShieldActionExtension: handles button taps on the shield overlay when the
// user tries to open a blocked app during sleep.
//
// **Pre-sleep phase** ("Time for bed" shield):
//   Primary "Sleep Now": closes the shield and posts a local notification with
//   the `sleepblock://sleep` deep link, nudging the user into the app's sleep
//   confirmation screen. Direct URL opening isn't available from a shield
//   extension, so the notification is the bridge.
//   Secondary "OK": just closes the shield.
//
// **Active sleep phase** ("Time to sleep" shield):
//   Primary "Good night": closes the shield (current behavior).
//
// Note: ShieldActionExtensions run in their own sandboxed process. Direct
// UIApplication.shared is not available.

class ShieldActionHandler: ShieldActionDelegate {

    /// App Group constants — hardcoded because this extension target does not
    /// include `SleepLockdownShared.swift`.
    private static let appGroup = "group.com.sulav.sleepblock"
    private static let phaseKey = "sulav.lock.phase"

    private var isPresleep: Bool {
        let raw = UserDefaults(suiteName: Self.appGroup)?.string(forKey: Self.phaseKey)
        return raw == "presleep"
    }

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
            if isPresleep {
                // Post a notification with the deep link so the user can tap
                // it to open SleepBlock's confirmation screen.
                postSleepNowNotification()
            }
            completionHandler(.close)

        case .secondaryButtonPressed:
            completionHandler(.close)

        @unknown default:
            completionHandler(.close)
        }
    }

    // MARK: - Local notification

    /// Fires a local notification whose default action opens
    /// `sleepblock://sleep`, landing the user on the sleep confirmation panel.
    private func postSleepNowNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Ready to sleep?"
        content.body = "Tap to start your sleep session."
        content.sound = .default
        // The deep link is carried via userInfo so AppDelegate's
        // `userNotificationCenter(_:didReceive:)` can route it, or the system
        // opens it via the URL scheme when the notification is tapped.
        content.userInfo = ["url": "sleepblock://sleep"]

        let request = UNNotificationRequest(
            identifier: "sulav.sleep.presleep-nudge",
            content: content,
            trigger: nil  // fire immediately
        )
        UNUserNotificationCenter.current().add(request)
    }
}
