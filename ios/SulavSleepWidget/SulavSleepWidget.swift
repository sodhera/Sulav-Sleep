import WidgetKit
import SwiftUI

// Home-screen + lock-screen widgets, per DESIGN.md ("Widgets" section).
//
// Two jobs, split by surface:
//  - Small + accessories are *tonight-focused*: bedtime countdown -> past-
//    bedtime wind-down -> asleep (OLED black + ember timer, matching
//    SleepModeView). They answer "should I be in bed?"
//  - Medium is the *morning stats glance*: last score, streak, 7-night bars.
//  - Large combines both: stats on top, tonight strip at the bottom.
//
// All views read the shared App Group summary the app publishes on every
// change. Real data only — an empty summary renders an honest "log a night" /
// "set a schedule" state. The one exception is the widget-gallery preview,
// which shows sample content so the user can see what they're adding.
// Display-only: tapping opens the app (no widgetURL — `sleepblock://sleep`
// would *start* a session, which a stray tap must never do).

struct SleepEntry: TimelineEntry {
    let date: Date
    let summary: SleepWidgetSummary
}

struct SleepProvider: TimelineProvider {
    func placeholder(in context: Context) -> SleepEntry {
        SleepEntry(date: Date(), summary: .gallerySample)
    }

    func getSnapshot(in context: Context, completion: @escaping (SleepEntry) -> Void) {
        // The gallery preview shows sample content; a placed widget never does.
        let summary = SleepWidgetStore.load() ?? .empty
        completion(SleepEntry(date: Date(), summary: context.isPreview && summary.isEmpty ? .gallerySample : summary))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SleepEntry>) -> Void) {
        let now = Date()
        let summary = SleepWidgetStore.load() ?? .empty

        // Countdown/timer text is system-driven (`Text(_, style:)`), so entries
        // only exist to flip *states* at the bedtime and wake boundaries. The
        // app pushes a reload on every real change; the policy is a fallback.
        var entries = [SleepEntry(date: now, summary: summary)]
        var refresh = now.addingTimeInterval(3600)
        if summary.asleepSince == nil, let bedtime = summary.bedtimeMinutes {
            let nextBed = SleepWidgetClock.nextOccurrence(ofMinuteOfDay: bedtime, after: now)
            entries.append(SleepEntry(date: nextBed, summary: summary))
            if let wake = summary.wakeMinutes {
                refresh = SleepWidgetClock.nextOccurrence(ofMinuteOfDay: wake, after: now)
            }
        }
        completion(Timeline(entries: entries, policy: .after(refresh)))
    }
}

struct SulavSleepWidget: Widget {
    let kind = "SulavSleepWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SleepProvider()) { entry in
            SleepWidgetView(entry: entry)
        }
        .configurationDisplayName("Sleep")
        .description("Tonight's bedtime and your recent nights.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryCircular, .accessoryRectangular, .accessoryInline,
        ])
    }
}

@main
struct SulavSleepWidgetBundle: WidgetBundle {
    var body: some Widget {
        SulavSleepWidget()
        SulavSleepLiveActivity()
    }
}

// MARK: - Tonight state

/// The one question the tonight-focused surfaces answer: where is the user
/// relative to their sleep window right now?
enum TonightState {
    case asleep(since: Date)
    case beforeBed(bedtime: Date)   // next upcoming bedtime
    case pastBedtime(bedtime: Date) // inside the window, not asleep
    case noSchedule

    static func from(_ summary: SleepWidgetSummary, at now: Date) -> TonightState {
        if let since = summary.asleepSince { return .asleep(since: since) }
        guard let bed = summary.bedtimeMinutes else { return .noSchedule }
        let bedDate = SleepWidgetClock.date(fromMinuteOfDay: bed, onDayOf: now)
        if let wake = summary.wakeMinutes,
           SleepWidgetClock.isInWindow(now: now, bedtimeMinutes: bed, wakeMinutes: wake) {
            return .pastBedtime(bedtime: bedDate)
        }
        return .beforeBed(bedtime: SleepWidgetClock.nextOccurrence(ofMinuteOfDay: bed, after: now))
    }
}

enum SleepWidgetClock {
    /// Today's wall-clock date for a minute-of-day (may already be in the past).
    static func date(fromMinuteOfDay minutes: Int, onDayOf day: Date) -> Date {
        let normalized = ((minutes % 1_440) + 1_440) % 1_440
        var components = Calendar.current.dateComponents([.year, .month, .day], from: day)
        components.hour = normalized / 60
        components.minute = normalized % 60
        return Calendar.current.date(from: components) ?? day
    }

    /// The next future occurrence of a minute-of-day (tonight or tomorrow).
    static func nextOccurrence(ofMinuteOfDay minutes: Int, after now: Date) -> Date {
        let today = date(fromMinuteOfDay: minutes, onDayOf: now)
        if today > now { return today }
        return Calendar.current.date(byAdding: .day, value: 1, to: today)
            ?? today.addingTimeInterval(86_400)
    }

    /// Whether `now` falls inside the bedtime->wake window (handles the
    /// past-midnight wrap, e.g. 23:00 -> 07:00).
    static func isInWindow(now: Date, bedtimeMinutes: Int, wakeMinutes: Int) -> Bool {
        guard bedtimeMinutes != wakeMinutes else { return false }
        let nowMinutes = SleepFormatting.minutes(from: now)
        if bedtimeMinutes < wakeMinutes {
            return nowMinutes >= bedtimeMinutes && nowMinutes < wakeMinutes
        }
        return nowMinutes >= bedtimeMinutes || nowMinutes < wakeMinutes
    }
}

// MARK: - Family dispatch + background

private struct SleepWidgetView: View {
    let entry: SleepEntry
    @Environment(\.widgetFamily) private var family

    private var tonight: TonightState { TonightState.from(entry.summary, at: entry.date) }

    var body: some View {
        switch family {
        case .accessoryCircular:
            CircularAccessoryView(summary: entry.summary, tonight: tonight)
        case .accessoryRectangular:
            RectangularAccessoryView(summary: entry.summary, tonight: tonight)
        case .accessoryInline:
            InlineAccessoryView(summary: entry.summary, tonight: tonight)
        case .systemSmall:
            TonightView(summary: entry.summary, tonight: tonight)
                .containerBackground(for: .widget) { NightBackground(tonight: tonight) }
        case .systemLarge:
            LargeSleepView(summary: entry.summary, tonight: tonight)
                .containerBackground(for: .widget) { NightBackground(tonight: tonight) }
        default:
            MediumSleepView(summary: entry.summary)
                .containerBackground(for: .widget) { NightBackground(tonight: nil) }
        }
    }
}

/// Minimal night gradient per DESIGN.md — no scene art in widgets, just the
/// sky tones with a faint warm floor glow (the "indoor light" accent). When
/// asleep it goes true black to match SleepModeView.
private struct NightBackground: View {
    let tonight: TonightState?

    private var isAsleep: Bool {
        if case .asleep = tonight { return true }
        return false
    }

    var body: some View {
        if isAsleep {
            SleepColor.sleepBlack
        } else {
            LinearGradient(
                colors: [SleepColor.skyTop, SleepColor.background],
                startPoint: .top, endPoint: .bottom
            )
            .overlay(alignment: .bottom) {
                // Warm horizon, barely there — reads as city light below frame.
                LinearGradient(
                    colors: [SleepColor.amber.opacity(0.10), .clear],
                    startPoint: .bottom, endPoint: .top
                )
                .frame(height: 44)
            }
        }
    }
}

// MARK: - Small: tonight

private struct TonightView: View {
    let summary: SleepWidgetSummary
    let tonight: TonightState

    var body: some View {
        switch tonight {
        case .asleep(let since):
            AsleepView(since: since)
        case .beforeBed(let bedtime):
            bedtimeBody(bedtime: bedtime, past: false)
        case .pastBedtime(let bedtime):
            bedtimeBody(bedtime: bedtime, past: true)
        case .noSchedule:
            noScheduleBody
        }
    }

    private func bedtimeBody(bedtime: Date, past: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: past ? "moon.zzz.fill" : "moon.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(SleepColor.amber)
                    .widgetAccentable()
                Text("BEDTIME")
                    .font(SleepFont.label(11)).tracking(1.4)
                    .foregroundStyle(SleepColor.muted)
            }

            Spacer(minLength: 6)

            Text(bedtime, format: .dateTime.hour().minute())
                .font(SleepFont.hero(30))
                .foregroundStyle(SleepColor.ink)
                .widgetAccentable()
                .minimumScaleFactor(0.7)
                .lineLimit(1)

            if past {
                Text("Past bedtime — wind down")
                    .font(SleepFont.body(12))
                    .foregroundStyle(SleepColor.amber)
                    .lineLimit(2)
            } else {
                (Text("in ") + Text(bedtime, style: .relative))
                    .font(SleepFont.body(12))
                    .foregroundStyle(SleepColor.dim)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let score = summary.latestScore, let mins = summary.latestDurationMinutes {
                HStack(spacing: 4) {
                    Text("Last")
                        .font(SleepFont.body(11))
                        .foregroundStyle(SleepColor.muted)
                    Text("\(score)")
                        .font(SleepFont.label(11))
                        .foregroundStyle(scoreColor(score))
                        .monospacedDigit()
                    Text("· \(SleepFormatting.duration(mins))")
                        .font(SleepFont.body(11))
                        .foregroundStyle(SleepColor.muted)
                }
            } else {
                Text("No nights logged yet")
                    .font(SleepFont.body(11))
                    .foregroundStyle(SleepColor.muted)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var noScheduleBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "moon.fill")
                .font(.system(size: 16))
                .foregroundStyle(SleepColor.amber)
                .widgetAccentable()
            Spacer(minLength: 0)
            Text("Sleep")
                .font(SleepFont.title(18))
                .foregroundStyle(SleepColor.ink)
            Text("Set a schedule to see your bedtime here.")
                .font(SleepFont.body(12))
                .foregroundStyle(SleepColor.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// Matches the immersive sleep screen: black, ember, nothing else.
private struct AsleepView: View {
    let since: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(SleepColor.ember)
                    .widgetAccentable()
                Text("ASLEEP")
                    .font(SleepFont.label(11)).tracking(1.4)
                    .foregroundStyle(SleepColor.emberDim)
            }

            Spacer(minLength: 0)

            Text(since, style: .timer)
                .font(SleepFont.hero(32))
                .foregroundStyle(SleepColor.ember)
                .monospacedDigit()
                .widgetAccentable()
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            Text("since \(since, format: .dateTime.hour().minute())")
                .font(SleepFont.body(12))
                .foregroundStyle(SleepColor.emberDim)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Medium: stats

private struct MediumSleepView: View {
    let summary: SleepWidgetSummary

    var body: some View {
        if summary.isEmpty {
            EmptyStatsView()
        } else {
            HStack(alignment: .top, spacing: SleepSpacing.lg) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("LAST NIGHT")
                        .font(SleepFont.label(11)).tracking(1.4)
                        .foregroundStyle(SleepColor.muted)

                    if let score = summary.latestScore {
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text("\(score)")
                                .font(SleepFont.hero(36))
                                .foregroundStyle(scoreColor(score))
                                .monospacedDigit()
                                .widgetAccentable()
                            if let mins = summary.latestDurationMinutes {
                                Text(SleepFormatting.duration(mins))
                                    .font(SleepFont.body(13))
                                    .foregroundStyle(SleepColor.dim)
                            }
                        }
                    }

                    Spacer(minLength: 2)

                    if summary.streak > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(SleepColor.gold)
                            Text("\(summary.streak) night\(summary.streak == 1 ? "" : "s") on track")
                                .font(SleepFont.body(12))
                                .foregroundStyle(SleepColor.dim)
                        }
                    } else if let avg = averageDuration {
                        Text("avg \(SleepFormatting.duration(avg))")
                            .font(SleepFont.body(12))
                            .foregroundStyle(SleepColor.muted)
                    }
                }

                Spacer(minLength: 0)

                SleepBars(nights: summary.nights, target: summary.targetMinutes, height: 66, hourUnit: false)
                    .frame(maxWidth: 168)
            }
        }
    }

    private var averageDuration: Int? {
        guard !summary.nights.isEmpty else { return nil }
        return summary.nights.reduce(0) { $0 + $1.durationMinutes } / summary.nights.count
    }
}

private struct EmptyStatsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "moon.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(SleepColor.amber)
                    .widgetAccentable()
                Text("SLEEP")
                    .font(SleepFont.label(11)).tracking(1.4)
                    .foregroundStyle(SleepColor.muted)
            }
            Spacer(minLength: 0)
            Text("No nights yet")
                .font(SleepFont.title(17))
                .foregroundStyle(SleepColor.ink)
            Text("Log a night to see your rhythm.")
                .font(SleepFont.body(12))
                .foregroundStyle(SleepColor.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Large: stats + tonight

private struct LargeSleepView: View {
    let summary: SleepWidgetSummary
    let tonight: TonightState

    var body: some View {
        VStack(alignment: .leading, spacing: SleepSpacing.md) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "moon.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(SleepColor.amber)
                        .widgetAccentable()
                    Text("SLEEP")
                        .font(SleepFont.label(11)).tracking(1.4)
                        .foregroundStyle(SleepColor.muted)
                }
                Spacer()
                if summary.streak > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(SleepColor.gold)
                        Text("\(summary.streak) on track")
                            .font(SleepFont.body(12))
                            .foregroundStyle(SleepColor.dim)
                    }
                }
            }

            if summary.isEmpty {
                Spacer(minLength: 0)
                Text("No nights yet")
                    .font(SleepFont.title(18))
                    .foregroundStyle(SleepColor.ink)
                Text("Log a night to see your rhythm.")
                    .font(SleepFont.body(13))
                    .foregroundStyle(SleepColor.muted)
                Spacer(minLength: 0)
            } else {
                if let score = summary.latestScore {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(score)")
                            .font(SleepFont.hero(44))
                            .foregroundStyle(scoreColor(score))
                            .monospacedDigit()
                            .widgetAccentable()
                        VStack(alignment: .leading, spacing: 1) {
                            Text("last night")
                                .font(SleepFont.body(12))
                                .foregroundStyle(SleepColor.muted)
                            if let mins = summary.latestDurationMinutes {
                                Text(SleepFormatting.duration(mins))
                                    .font(SleepFont.body(13))
                                    .foregroundStyle(SleepColor.dim)
                            }
                        }
                    }
                }

                SleepBars(nights: summary.nights, target: summary.targetMinutes, height: 96, showWeekdays: true)
            }

            Rectangle()
                .fill(SleepColor.hairline)
                .frame(height: 1)

            TonightFooter(tonight: tonight)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// One quiet line about tonight at the bottom of the large widget.
private struct TonightFooter: View {
    let tonight: TonightState

    var body: some View {
        HStack(spacing: 6) {
            switch tonight {
            case .asleep(let since):
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(SleepColor.ember)
                Text("Asleep")
                    .font(SleepFont.body(13))
                    .foregroundStyle(SleepColor.dim)
                Text(since, style: .timer)
                    .font(SleepFont.label(13))
                    .foregroundStyle(SleepColor.ember)
                    .monospacedDigit()
            case .beforeBed(let bedtime):
                Image(systemName: "moon.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(SleepColor.amber)
                    .widgetAccentable()
                Text("Bedtime \(bedtime, format: .dateTime.hour().minute())")
                    .font(SleepFont.body(13))
                    .foregroundStyle(SleepColor.dim)
                (Text("in ") + Text(bedtime, style: .relative))
                    .font(SleepFont.body(13))
                    .foregroundStyle(SleepColor.muted)
                    .lineLimit(1)
            case .pastBedtime:
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(SleepColor.amber)
                    .widgetAccentable()
                Text("Past bedtime — wind down")
                    .font(SleepFont.body(13))
                    .foregroundStyle(SleepColor.amber)
            case .noSchedule:
                Image(systemName: "moon.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(SleepColor.muted)
                Text("Set a schedule for a bedtime reminder")
                    .font(SleepFont.body(13))
                    .foregroundStyle(SleepColor.muted)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Lock-screen accessories
//
// Accessories render in the system's vibrant/tinted material, so they use
// default foregrounds and hierarchy instead of the app palette.

private struct CircularAccessoryView: View {
    let summary: SleepWidgetSummary
    let tonight: TonightState

    var body: some View {
        switch tonight {
        case .asleep:
            // A gauge-shaped moon: unambiguous "sleep is running" at a glance.
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 20, weight: .medium))
                    .widgetAccentable()
            }
        default:
            if let score = summary.latestScore {
                Gauge(value: Double(score), in: 0...100) {
                    Image(systemName: "moon.fill")
                } currentValueLabel: {
                    Text("\(score)")
                        .font(.system(size: 18, weight: .semibold))
                        .monospacedDigit()
                }
                .gaugeStyle(.accessoryCircular)
                .widgetAccentable()
            } else if case .beforeBed(let bedtime) = tonight {
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 0) {
                        Image(systemName: "moon.fill")
                            .font(.system(size: 12, weight: .medium))
                        Text(bedtime, format: .dateTime.hour().minute())
                            .font(.system(size: 12, weight: .semibold))
                            .minimumScaleFactor(0.6)
                    }
                    .widgetAccentable()
                }
            } else {
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "moon.fill")
                        .font(.system(size: 20, weight: .medium))
                        .widgetAccentable()
                }
            }
        }
    }
}

private struct RectangularAccessoryView: View {
    let summary: SleepWidgetSummary
    let tonight: TonightState

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            switch tonight {
            case .asleep(let since):
                HStack(spacing: 4) {
                    Image(systemName: "moon.stars.fill").font(.system(size: 11))
                    Text("Asleep").font(.system(size: 13, weight: .semibold))
                }
                .widgetAccentable()
                Text(since, style: .timer)
                    .font(.system(size: 15, weight: .medium))
                    .monospacedDigit()
            case .beforeBed(let bedtime):
                HStack(spacing: 4) {
                    Image(systemName: "moon.fill").font(.system(size: 11))
                    Text("Bedtime \(bedtime, format: .dateTime.hour().minute())")
                        .font(.system(size: 13, weight: .semibold))
                }
                .widgetAccentable()
                (Text("in ") + Text(bedtime, style: .relative))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                lastNightLine
            case .pastBedtime:
                HStack(spacing: 4) {
                    Image(systemName: "moon.zzz.fill").font(.system(size: 11))
                    Text("Past bedtime").font(.system(size: 13, weight: .semibold))
                }
                .widgetAccentable()
                Text("Wind down and sleep")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                lastNightLine
            case .noSchedule:
                HStack(spacing: 4) {
                    Image(systemName: "moon.fill").font(.system(size: 11))
                    Text("Sleep").font(.system(size: 13, weight: .semibold))
                }
                .widgetAccentable()
                Text("Set a schedule in the app")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var lastNightLine: some View {
        if let score = summary.latestScore, let mins = summary.latestDurationMinutes {
            Text("Last \(score) · \(SleepFormatting.duration(mins))")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }
}

private struct InlineAccessoryView: View {
    let summary: SleepWidgetSummary
    let tonight: TonightState

    var body: some View {
        switch tonight {
        case .asleep(let since):
            (Text(Image(systemName: "moon.stars.fill")) + Text(" Asleep ") + Text(since, style: .timer))
        case .beforeBed(let bedtime):
            (Text(Image(systemName: "moon.fill")) + Text(" Bed \(SleepFormatting.shortTime.string(from: bedtime))") + inlineScoreSuffix)
        case .pastBedtime:
            (Text(Image(systemName: "moon.zzz.fill")) + Text(" Past bedtime"))
        case .noSchedule:
            if let score = summary.latestScore {
                (Text(Image(systemName: "moon.fill")) + Text(" Sleep score \(score)"))
            } else {
                (Text(Image(systemName: "moon.fill")) + Text(" Sleep"))
            }
        }
    }

    private var inlineScoreSuffix: Text {
        guard let score = summary.latestScore else { return Text("") }
        return Text(" · \(score)")
    }
}

// MARK: - Shared pieces

/// The 7-night rhythm: duration bars against a target hairline. The latest
/// night is full-strength; earlier nights recede slightly, so "how did I do
/// last night" reads first and the week reads second. Each bar carries the
/// hours slept that night as a small navy-ink label set *inside* its top —
/// the amber-fill/navy-ink pairing from the primary button. Bars too short
/// to hold the label drop it rather than overflow.
private struct SleepBars: View {
    let nights: [WidgetNight]
    let target: Int
    let height: CGFloat
    var showWeekdays: Bool = false
    /// Whether the in-bar label carries the "h" unit ("7.5h" vs "7.5").
    /// The medium widget's narrow columns go without it.
    var hourUnit: Bool = true

    var body: some View {
        let maxMinutes = max(target, nights.map(\.durationMinutes).max() ?? target)
        let targetFraction = CGFloat(target) / CGFloat(maxMinutes)

        VStack(spacing: 4) {
            HStack(alignment: .bottom, spacing: 5) {
                if nights.isEmpty {
                    ForEach(0..<7, id: \.self) { _ in
                        Capsule().fill(SleepColor.hairline).frame(height: 4)
                            .frame(maxWidth: .infinity, alignment: .bottom)
                    }
                } else {
                    ForEach(Array(nights.enumerated()), id: \.element.id) { index, night in
                        let frac = max(0.08, CGFloat(night.durationMinutes) / CGFloat(maxMinutes))
                        let barHeight = height * frac
                        let isLatest = index == nights.count - 1
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [SleepColor.gold, SleepColor.amber],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                            .overlay(alignment: .top) {
                                if barHeight >= 20 {
                                    Text(hoursLabel(night.durationMinutes))
                                        .font(SleepFont.label(9))
                                        .foregroundStyle(SleepColor.navy)
                                        .monospacedDigit()
                                        .minimumScaleFactor(0.6)
                                        .lineLimit(1)
                                        .padding(.top, 5)
                                        .padding(.horizontal, 1)
                                }
                            }
                            .opacity(isLatest ? 1 : 0.62)
                            .frame(height: barHeight)
                            .frame(maxWidth: .infinity, alignment: .bottom)
                            .widgetAccentable()
                    }
                }
            }
            .frame(height: height, alignment: .bottom)
            .overlay(alignment: .bottom) {
                if !nights.isEmpty {
                    // Target sleep window, as a quiet reference line.
                    Rectangle()
                        .fill(SleepColor.ink.opacity(0.18))
                        .frame(height: 1)
                        .offset(y: -height * targetFraction)
                }
            }

            if showWeekdays, !nights.isEmpty {
                HStack(spacing: 5) {
                    ForEach(nights) { night in
                        Text(SleepFormatting.narrowWeekday.string(from: night.end))
                            .font(SleepFont.label(10))
                            .foregroundStyle(SleepColor.muted)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    /// Compact hours for a bar: "7.5h"/"8h" (or unit-less "7.5"/"8") — one
    /// decimal, no trailing .0.
    private func hoursLabel(_ minutes: Int) -> String {
        let hours = Double(minutes) / 60
        let rounded = (hours * 10).rounded() / 10
        let number = rounded == rounded.rounded()
            ? "\(Int(rounded))"
            : String(format: "%.1f", rounded)
        return hourUnit ? "\(number)h" : number
    }
}

private func scoreColor(_ score: Int) -> Color {
    switch score {
    case 80...: return SleepColor.gold
    case 60..<80: return SleepColor.ink
    default: return SleepColor.danger
    }
}

// MARK: - Gallery sample

extension SleepWidgetSummary {
    /// Sample content for the widget-gallery preview ONLY (`context.isPreview`
    /// with no real data, and `placeholder`). A placed widget always renders
    /// real data or an honest empty state.
    static var gallerySample: SleepWidgetSummary {
        let calendar = Calendar.current
        let now = Date()
        let durations = [432, 465, 401, 488, 452, 419, 471]
        let nights = durations.enumerated().map { index, minutes in
            let end = calendar.date(byAdding: .day, value: index - 6, to: now) ?? now
            return WidgetNight(
                end: end,
                durationMinutes: minutes,
                score: SleepMathPreview.score(durationMinutes: minutes, targetMinutes: 480)
            )
        }
        return SleepWidgetSummary(
            nights: nights,
            latestScore: nights.last?.score,
            latestDurationMinutes: nights.last?.durationMinutes,
            streak: 3,
            targetMinutes: 480,
            bedtimeMinutes: 23 * 60,
            wakeMinutes: 7 * 60,
            asleepSince: nil,
            updated: now
        )
    }
}

/// Local copy of the app's score curve for gallery sample data only — the
/// widget target doesn't compile SleepStore.swift.
private enum SleepMathPreview {
    static func score(durationMinutes: Int, targetMinutes: Int) -> Int {
        let ratio = Double(durationMinutes) / Double(max(targetMinutes, 1))
        let raw: Double = ratio >= 1 ? 92 + min(8, (ratio - 1) * 30) : 100 - (1 - ratio) * 140
        return max(40, min(100, Int(raw.rounded())))
    }
}
