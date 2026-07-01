import ActivityKit
import Foundation

// Starts/ends the Live Activity for the active-sleep timer (Dynamic Island +
// Lock Screen). The widget extension owns the rendering (SulavSleepLiveActivity).
enum SleepLiveActivity {
    static func start(startDate: Date) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            _ = try Activity<SleepActivityAttributes>.request(
                attributes: SleepActivityAttributes(),
                content: .init(state: .init(startDate: startDate), staleDate: nil)
            )
            AppLog.app.info("Live Activity started")
        } catch {
            AppLog.app.error("Live Activity start failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func end() {
        Task {
            for activity in Activity<SleepActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
