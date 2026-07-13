import Foundation

enum SleepFormatting {
    static let shortTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    static let longDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEE MMMM d")
        return formatter
    }()

    static let historyDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE MMM d")
        return formatter
    }()

    static let narrowWeekday: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEEE")
        return formatter
    }()

    /// Compact month + day, e.g. "Jun 22" — used for the record chart's
    /// per-week date-range caption.
    static let monthDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter
    }()

    /// Compact month + day + year, e.g. "Jul 13, 2026" — the subscription
    /// renewal/end date, where the year carries real information (a yearly
    /// renewal lands up to twelve months out).
    static let monthDayYear: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM d yyyy")
        return formatter
    }()

    static func clock(_ minutes: Int) -> String {
        shortTime.string(from: date(fromMinutes: minutes))
    }

    static func duration(_ minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60
        return "\(hours)h \(String(format: "%02d", remainder))m"
    }

    static func minutes(from date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    static func date(fromMinutes minutes: Int) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = ((minutes % 1_440) + 1_440) % 1_440 / 60
        components.minute = ((minutes % 60) + 60) % 60
        return Calendar.current.date(from: components) ?? Date()
    }

    /// Time remaining until the next occurrence of a minute-of-day (e.g. a
    /// bedtime), formatted as "Xh YYm". Always positive — if the target
    /// already passed today, it rolls to tomorrow.
    static func countdown(toMinuteOfDay target: Int, from now: Date) -> String {
        let nowMinutes = minutes(from: now)
        let delta = ((target - nowMinutes) % 1_440 + 1_440) % 1_440
        return duration(delta == 0 ? 1_440 : delta)
    }
}
