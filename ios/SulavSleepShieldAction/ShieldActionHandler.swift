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

    /// The one DeviceActivity name this target needs. Hardcoded rather than
    /// read from `SleepLockdownShared.swift`, which would pull FamilyControls
    /// into the extension; the App Group keys all come from
    /// `SleepLockdownKeys.swift`, which this target does compile.
    private static let snoozeActivity = DeviceActivityName("sulav.sleep.snooze")

    private var isPresleep: Bool {
        SleepLockdownSelection.currentPhase() == .presleep
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
            // What the secondary button *means* is resolved in one shared
            // place, so the label the user read and the action they get can't
            // drift apart.
            switch SleepLockdownSelection.currentEscape() {
            case .snooze:
                grantSnooze()
            case .doorClosed:
                // Costs nothing but starts the clock. The wait is the whole
                // mechanism: most people never come back for the second tap.
                SleepLockdownSelection.requestDoor()
            case .doorWaiting:
                break   // still waiting; the label already said so
            case .doorReady:
                openDoor()
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
    /// Nothing here can run a timer, so the return trip is layered — see the
    /// four chances listed in `docs/development.md`. This process is torn down
    /// the instant `completionHandler` runs, so the two links that matter most
    /// (the usage-threshold event, the app's foreground check) live elsewhere;
    /// what happens here is best-effort on top of them.
    private func grantSnooze() {
        let until = SleepLockdownSelection.consumeSnooze()
        lift(until: until)
        postSnoozeEndNotification(at: until, title: "Five minutes are up")
    }

    /// Opens the slow door: the user asked, waited out the delay, and came
    /// back. Unlike the snooze this is *not* rationed per night — it is the
    /// exit that must always exist, because the alternative someone reaches for
    /// when no exit exists is deleting the app. It costs the wait every time,
    /// which is what keeps it from becoming a plain off switch.
    private func openDoor() {
        let until = SleepLockdownSelection.openDoor()
        lift(until: until)
        postSnoozeEndNotification(at: until, title: "Your \(SleepLockdownSelection.doorMinutes) minutes are up")
    }

    /// Drops the shield and arranges every way we have of putting it back.
    private func lift(until: Date) {
        let store = ManagedSettingsStore()
        store.shield.applications = nil
        store.shield.applicationCategories = nil

        scheduleReArm(at: until)
    }

    /// Best-effort wall-clock re-arm, for the snooze that gets put down rather
    /// than spent: with the phone idle no usage accrues, so the threshold event
    /// never fires and this interval is what brings the shield back.
    ///
    /// DeviceActivity refuses intervals shorter than 15 minutes, so this window
    /// runs from the snooze expiry to 20 minutes later — only its *start*
    /// matters, and `SulavSleepMonitor` treats this activity's end as a no-op
    /// precisely so the long tail can't unshield the rest of the night.
    ///
    /// The components carry the full date, not just hour/minute. A
    /// `repeats: false` schedule has no recurrence to hang a bare time-of-day
    /// on, and one built that way never fired — the original reason a snooze
    /// could run out with the shield still down.
    private func scheduleReArm(at date: Date) {
        let calendar = Calendar.current
        let fields: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        let start = calendar.dateComponents(fields, from: date)
        let end = calendar.dateComponents(fields, from: date.addingTimeInterval(20 * 60))
        let schedule = DeviceActivitySchedule(
            intervalStart: start,
            intervalEnd: end,
            repeats: false
        )
        do {
            try DeviceActivityCenter().startMonitoring(Self.snoozeActivity, during: schedule)
        } catch {
            // Non-fatal: the threshold event and the app's foreground check
            // still restore the shield, so a failure here delays the block
            // rather than dropping it.
            NSLog("SleepBlock: snooze re-arm scheduling failed — \(error.localizedDescription)")
        }
    }

    /// Tells the user the five minutes are up, and gives them a tap that opens
    /// SleepBlock — which runs `reapplyShieldIfSnoozeExpired()` on foreground.
    ///
    /// The one link that reaches someone who is still scrolling: local
    /// notifications are scheduled by the system, so this survives the
    /// extension being killed a moment from now.
    private func postSnoozeEndNotification(at date: Date, title: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        // Lands on the wind-down, not the slide-to-sleep commitment. Someone
        // whose snooze just ran out is, by definition, not ready to sleep —
        // that is why they spent the snooze — so asking them to commit to a
        // whole night is the wrong-sized ask, and the easy refusal sends them
        // straight back to the app they were in. Two minutes of breathing is a
        // much easier yes, and it ends one tap from the real thing.
        content.body = "Two minutes to wind down?"
        content.sound = .default
        content.userInfo = ["url": "sleepblock://winddown"]

        let delay = max(1, date.timeIntervalSinceNow)
        let request = UNNotificationRequest(
            identifier: "sulav.sleep.snooze-over",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
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
