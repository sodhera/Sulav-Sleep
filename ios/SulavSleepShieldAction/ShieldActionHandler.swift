import DeviceActivity
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
    /// include `SleepLockdownShared.swift`. Keep in sync with
    /// `SleepLockdownSelection`.
    private static let appGroup = "group.com.sulav.sleepblock"
    private static let phaseKey = "sulav.lock.phase"
    private static let selectionKey = "sulav.lock.selection.v1"
    private static let snoozeUntilKey = "sulav.lock.snoozeUntil"
    private static let snoozeCountKey = "sulav.lock.snoozeCount"
    private static let snoozeLimit = 2
    private static let snoozeMinutes = 5
    private static let snoozeActivity = DeviceActivityName("sulav.sleep.snooze")

    private static var groupDefaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    private var isPresleep: Bool {
        let raw = Self.groupDefaults?.string(forKey: Self.phaseKey)
        return raw == "presleep"
    }

    private var snoozeAvailable: Bool {
        (Self.groupDefaults?.integer(forKey: Self.snoozeCountKey) ?? 0) < Self.snoozeLimit
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
            // Presleep only. The active-phase shield has no secondary button:
            // snoozing out of a session the user deliberately started would
            // make lockdown meaningless, and `lockdownMaxHours` is already the
            // sanctioned way out of one.
            if isPresleep, snoozeAvailable {
                grantSnooze()
            }
            completionHandler(.close)

        @unknown default:
            completionHandler(.close)
        }
    }

    // MARK: - Snooze

    /// Lifts the shield for `snoozeMinutes`, spends one of the night's
    /// allowance, and arranges for it to come back.
    ///
    /// `ShieldActionResponse` has no "allow for N minutes", so the only way to
    /// let the user back in is to drop the shield off the store ourselves.
    /// Nothing here can run a timer, so the return trip has three chances:
    /// a short DeviceActivity schedule (below), the monitor extension, and the
    /// app's own foreground check in `reapplyShieldIfSnoozeExpired()`.
    private func grantSnooze() {
        let defaults = Self.groupDefaults
        let spent = defaults?.integer(forKey: Self.snoozeCountKey) ?? 0
        let until = Date().addingTimeInterval(Double(Self.snoozeMinutes) * 60)
        defaults?.set(spent + 1, forKey: Self.snoozeCountKey)
        defaults?.set(until.timeIntervalSince1970, forKey: Self.snoozeUntilKey)

        let store = ManagedSettingsStore()
        store.shield.applications = nil
        store.shield.applicationCategories = nil

        scheduleReArm(at: until)
    }

    /// Best-effort timed re-arm.
    ///
    /// DeviceActivity refuses intervals shorter than 15 minutes, so this window
    /// runs from the snooze expiry to 20 minutes later — only its *start*
    /// matters, and `SulavSleepMonitor` treats this activity's end as a no-op
    /// precisely so the long tail can't unshield the rest of the night.
    private func scheduleReArm(at date: Date) {
        let calendar = Calendar.current
        let start = calendar.dateComponents([.hour, .minute], from: date)
        let end = calendar.dateComponents(
            [.hour, .minute],
            from: date.addingTimeInterval(20 * 60)
        )
        let schedule = DeviceActivitySchedule(
            intervalStart: start,
            intervalEnd: end,
            repeats: false
        )
        do {
            try DeviceActivityCenter().startMonitoring(Self.snoozeActivity, during: schedule)
        } catch {
            // Non-fatal: the app's foreground check still restores the shield,
            // so a failure here delays the block rather than dropping it.
            NSLog("SleepBlock: snooze re-arm scheduling failed — \(error.localizedDescription)")
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
