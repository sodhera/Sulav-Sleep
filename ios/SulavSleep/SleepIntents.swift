import AppIntents
import Foundation

struct StartSleepIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Sleep"
    static var description = IntentDescription("Starts a Sulav Sleep session without opening the app.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        SleepPersistence.shared.startSleepFromIntent()
        return .result(dialog: "Sleep started.")
    }
}

struct OpenSleepHomeIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Sulav Sleep"
    static var description = IntentDescription("Opens Sulav Sleep to the main screen.")
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
            shortTitle: "Start Sleep",
            systemImageName: "moon.fill"
        )

        AppShortcut(
            intent: OpenSleepHomeIntent(),
            phrases: [
                "Open \(.applicationName)",
                "Show \(.applicationName)"
            ],
            shortTitle: "Open Sulav Sleep",
            systemImageName: "moon.stars.fill"
        )
    }
}

