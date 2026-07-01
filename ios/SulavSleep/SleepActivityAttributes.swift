import ActivityKit
import Foundation

// Shared between the app (starts/ends the activity) and the widget extension
// (renders it). No dynamic content beyond the start date — the system renders
// the live-updating elapsed timer from it, no periodic updates needed.
struct SleepActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var startDate: Date
    }
}
