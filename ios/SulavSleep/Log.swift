import Foundation
import os

// Unified logging + performance tracing.
//
// - `AppLog` exposes category-scoped `os.Logger`s. These show up in Console.app
//   and `xcrun simctl spawn <udid> log stream --predicate 'subsystem == "..."'`.
// - `AppSignpost` exposes `OSSignposter`s for Instruments. Signpost intervals
//   wrap the operations that affect perceived performance (HealthKit imports,
//   scene frame construction) so we can profile them in the Time Profiler and
//   the "Points of Interest" instrument.
//
// Keep log lines terse and non-PII. Sleep times and names are the user's; we log
// counts and durations, never the name or raw timestamps at anything above debug.

enum AppLog {
    static let subsystem = "com.sulav.sleepblock"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let store = Logger(subsystem: subsystem, category: "store")
    static let health = Logger(subsystem: subsystem, category: "health")
    static let ui = Logger(subsystem: subsystem, category: "ui")
    static let scene = Logger(subsystem: subsystem, category: "scene")
    static let intents = Logger(subsystem: subsystem, category: "intents")
    static let paywall = Logger(subsystem: subsystem, category: "paywall")
}

enum AppSignpost {
    static let health = OSSignposter(subsystem: AppLog.subsystem, category: "health")
    static let store = OSSignposter(subsystem: AppLog.subsystem, category: "store")
    static let scene = OSSignposter(subsystem: AppLog.subsystem, category: "scene")
}

extension OSSignposter {
    /// Wrap an async operation in a signpost interval visible in Instruments.
    func measure<T>(_ name: StaticString, _ work: () async throws -> T) async rethrows -> T {
        let id = makeSignpostID()
        let state = beginInterval(name, id: id)
        defer { endInterval(name, state) }
        return try await work()
    }

    /// Wrap a synchronous operation in a signpost interval.
    func measure<T>(_ name: StaticString, _ work: () throws -> T) rethrows -> T {
        let id = makeSignpostID()
        let state = beginInterval(name, id: id)
        defer { endInterval(name, state) }
        return try work()
    }
}
