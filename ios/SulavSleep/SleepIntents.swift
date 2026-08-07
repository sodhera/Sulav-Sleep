import AppIntents
import Foundation

extension Notification.Name {
    /// Posted by `StartSleepIntent` after the system foregrounds the app —
    /// `SulavSleepApp` responds by raising Home's slide-to-sleep
    /// confirmation (the same handler as the `sleepblock://sleep` deep
    /// link). The intent runs in the app's own process with
    /// `openAppWhenRun`, so the view hierarchy is mounted before this fires.
    static let sleepConfirmationRequested = Notification.Name("sleepConfirmationRequested")
    /// A `sleepblock://` deep link that arrived via a **notification tap**
    /// rather than `onOpenURL` (which notification taps don't fire). The
    /// object carries the URL's host.
    static let sleepDeepLinkRequested = Notification.Name("sleepDeepLinkRequested")
}

/// Opens the app on the slide-to-sleep confirmation. Deliberately does NOT
/// start the session: the slide gesture is the only way a night begins, on
/// every surface — in-app button, widget capsule, shield action, and Siri
/// alike. (This intent used to write an active session straight into the
/// App Group without opening the app; that skipped the commitment gesture
/// and is retired.)
struct StartSleepIntent: AppIntent {
    static var title: LocalizedStringResource = "Sleep Now"
    static var description = IntentDescription("Opens SleepBlock ready to slide to sleep.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .sleepConfirmationRequested, object: nil)
        return .result()
    }
}

struct OpenSleepHomeIntent: AppIntent {
    static var title: LocalizedStringResource = "Open SleepBlock"
    static var description = IntentDescription("Opens SleepBlock to the main screen.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        .result()
    }
}

struct SulavSleepShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartSleepIntent(),
            phrases: [
                "Start sleep in \(.applicationName)",
                "Begin sleep in \(.applicationName)"
            ],
            shortTitle: "Sleep Now",
            systemImageName: "moon.fill"
        )

        AppShortcut(
            intent: OpenSleepHomeIntent(),
            phrases: [
                "Open \(.applicationName)",
                "Show \(.applicationName)"
            ],
            shortTitle: "Open SleepBlock",
            systemImageName: "moon.stars.fill"
        )
    }
}
