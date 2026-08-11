import SwiftUI
import UIKit
import UserNotifications

// MARK: - Interactive edge-swipe back

// Every pushed page in the app sits on the living scene and hides the system
// navigation bar (`SceneScreen` + `.toolbar(.hidden)`), supplying its own
// round GlassBackButton instead. UIKit ties the interactive "swipe from the
// left edge to go back" recognizer to the visible bar, so hiding the bar also
// kills that gesture — leaving the button as the only way back. Re-pointing
// the recognizer's delegate at the navigation controller restores the native
// edge-swipe on every pushed screen (Profile → All nights / Blocked apps,
// Settings → Schedule / Blocked apps) while still refusing to fire at a stack
// root. This is app-wide by design: there is no screen where we want the
// standard iOS back-swipe suppressed.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // Only govern the pop recognizer we adopted — never swallow other
        // gestures — and never let a swipe try to pop the root controller.
        guard gestureRecognizer == interactivePopGestureRecognizer else { return true }
        return viewControllers.count > 1
    }
}

// MARK: - Notification delegate (pre-sleep shield deep link)

/// Handles taps on the local notification that the shield action extension
/// fires when the user presses "Sleep Now" during the pre-sleep phase.
/// Tapping the notification opens the app and routes to the sleep
/// confirmation, exactly like `sleepblock://sleep`.
class SleepAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// Notification tapped — extract the deep link and route to sleep
    /// confirmation via the same internal notification that Siri intents use.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        // A notification tap does **not** go through `onOpenURL` — it arrives
        // here — so every deep link the app posts to itself has to be routed
        // twice. The host travels as the notification's object and the scene
        // does the routing, so the two paths stay one switch.
        let userInfo = response.notification.request.content.userInfo
        if let urlString = userInfo["url"] as? String,
           let url = URL(string: urlString),
           url.scheme == "sleepblock",
           let host = url.host {
            AppLog.app.info("Notification tapped with sleepblock://\(host, privacy: .public)")
            NotificationCenter.default.post(name: .sleepDeepLinkRequested, object: host)
        }
        completionHandler()
    }

    /// Show notifications even when the app is in the foreground (the shield
    /// action fires the notification while the app may already be visible).
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

@main
struct SulavSleepApp: App {
    @UIApplicationDelegateAdaptor(SleepAppDelegate.self) var appDelegate
    @State private var store = SleepStore()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        SleepAssetCache.prewarmCriticalAssets()
    }

    var body: some Scene {
        WindowGroup {
            RootView(store: store)
                .preferredColorScheme(.dark)
                .onAppear {
                    Haptics.prepare()
                }
                .task {
                    AppLog.app.info("App launched")
                    await store.refreshHealthIfEnabled()
                }
                .task {
                    // Separate task so a slow config fetch never delays the
                    // Health refresh (or vice versa). Fails open on any error.
                    await store.checkAppUpdateGate()
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    AppLog.app.info("Scene active")
                    Haptics.prepare()
                    store.reload()
                    Task { await store.refreshHealthIfEnabled() }
                    Task { await store.checkAppUpdateGate() }
                    Task { await store.refreshReferral() }
                }
                .onOpenURL { url in
                    // sleepblock://sleep arrives from the widget capsule and
                    // the shield action extension. sleepblock://tonight comes
                    // from the evening check-in notification.
                    // (sleepblock://signin, from the widget's signed-out
                    // capsule, needs no handling: opening the app is enough —
                    // RootView lands on welcome.)
                    guard url.scheme == "sleepblock", let host = url.host else { return }
                    AppLog.app.info("Opened via sleepblock://\(host, privacy: .public) URL")
                    route(host)
                }
                .onReceive(NotificationCenter.default.publisher(for: .sleepDeepLinkRequested)) { note in
                    // The notification-tap half of the same links.
                    guard let host = note.object as? String else { return }
                    route(host)
                }
                .onReceive(NotificationCenter.default.publisher(for: .sleepConfirmationRequested)) { _ in
                    // Siri / Shortcuts ("Sleep Now" intent), after the system
                    // foregrounds the app.
                    AppLog.app.info("Sleep confirmation requested via App Intent")
                    openSleepConfirmation()
                }
        }
    }

    /// The one place a `sleepblock://` host becomes a screen, shared by the
    /// URL-open and notification-tap paths.
    private func route(_ host: String) {
        switch host {
        case "sleep": openSleepConfirmation()
        case "tonight": openTonight()
        case "winddown": openWindDown()
        // "signin" needs no handling: opening the app is enough, RootView
        // lands on welcome.
        default: break
        }
    }

    /// Every external "sleep" entry point — widget capsule, shield action,
    /// Siri intent — lands here, and none of them starts the session: this
    /// only raises Home's slide-to-sleep confirmation, because the slide
    /// gesture is the only way a night begins. Signed-out or mid-session
    /// requests do nothing (RootView is already showing welcome or
    /// SleepModeView).
    private func openSleepConfirmation() {
        guard store.activeSession == nil, store.isAuthenticated, store.isOnboarded else { return }
        // A locked user asking to sleep — from the widget, the shield, or
        // Siri — gets the paywall, not silence. These are the app's back
        // doors into `startSleep`, so leaving them to fall through would
        // make the Siri intent a way around the subscription; standing them
        // down without a word would be the older, ruder bug.
        guard !store.presentPaywallIfLocked() else { return }
        Haptics.soft()
        store.selectedTab = .home
        withAnimation(.easeInOut(duration: 0.3)) {
            store.showSleepConfirmation = true
        }
    }

    /// The evening check-in, an hour before bedtime. Gated the same way as the
    /// sleep confirmation — and additionally stood down once a session is
    /// running, since there is nothing left to commit to.
    private func openTonight() {
        guard store.activeSession == nil, store.isAuthenticated, store.isOnboarded else { return }
        guard !store.presentPaywallIfLocked() else { return }
        Haptics.soft()
        store.selectedTab = .home
        store.showTonightCheckIn = true
    }

    /// The wind-down, from `sleepblock://winddown` — chiefly the notification
    /// that fires when a snooze runs out, which reaches someone at the moment
    /// they are most adrift and least ready to be told to sleep.
    private func openWindDown() {
        guard store.activeSession == nil, store.isAuthenticated, store.isOnboarded else { return }
        guard !store.presentPaywallIfLocked() else { return }
        Haptics.soft()
        store.selectedTab = .home
        withAnimation(.easeInOut(duration: 0.3)) {
            store.showWindDown = true
        }
    }
}
