import WidgetKit
import SwiftUI

// Home-screen + lock-screen widgets, per DESIGN.md ("Widgets" section).
//
// The organizing idea: **the sloth is the state, on every surface.** The
// app's mascot does on the home screen exactly what it does in the app —
// awake through the day, heavy-lidded once bedtime is near or just past,
// ember-lit on OLED black while asleep — so every widget is recognizably
// SleepBlock at a glance without a logo badge, and the figure carries real
// state the whole time.
//
// Two jobs, split by surface:
//  - Small is *tonight-focused*: the sloth as hero with the bedtime clock,
//    countdown, wind-down nudge, or set-a-schedule invitation.
//  - Medium is the *morning stats glance*: last night's sleep, streak, and
//    the 7-night bars, with the sloth lounging under the numbers as the
//    brand-and-state figure. Duration is the app's only metric — the 0–100
//    score is retired everywhere.
//  - Large combines both: stats + bars on top, a mini-Home footer (sloth +
//    tonight line + Sleep Now) at the bottom.
//  - While a session runs, every system family wears the same *sleep face*:
//    OLED black, the ember night sloth, and the elapsed timer — SleepModeView
//    shrunk onto the home screen. When the phone goes down for the night,
//    the widgets go dark with it.
//  - Lock-screen accessories render in the system's vibrant material at tiny
//    sizes, so they stay SF-symbol-led — the sloth would blur into mush.
//
// All views read the shared App Group summary the app publishes on every
// change. Real data only — an empty summary renders an honest "log a night" /
// "set a schedule" state. The one exception is the widget-gallery preview,
// which shows sample content so the user can see what they're adding.
// Tapping the widget body opens the app; the only deep link is the explicit
// action capsule on medium/large (`WidgetActionCapsule`): "Sleep Now" when
// signed in (opens Home's slide-to-sleep confirmation — a widget tap never
// starts a session), "Sign in" when signed out (just opens the app, which
// lands on welcome).

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
        // only exist to flip *states*: the sloth's eyelids at the drowsy
        // boundary, then the bedtime and wake boundaries. The app pushes a
        // reload on every real change; the policy is a fallback.
        var entries = [SleepEntry(date: now, summary: summary)]
        var refresh = now.addingTimeInterval(3600)
        if summary.asleepSince == nil, let bedtime = summary.bedtimeMinutes {
            let nextBed = SleepWidgetClock.nextOccurrence(ofMinuteOfDay: bedtime, after: now)
            let drowsyStart = nextBed.addingTimeInterval(-TimeInterval(TonightState.drowsyLeadMinutes * 60))
            if drowsyStart > now {
                entries.append(SleepEntry(date: drowsyStart, summary: summary))
            }
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
    case beforeBed(bedtime: Date, drowsy: Bool) // next upcoming bedtime
    case pastBedtime(bedtime: Date)             // inside the window, not asleep
    case noSchedule

    /// Minutes before bedtime at which the sloth's eyelids get heavy —
    /// mirrors `HomeSloth.drowsyLead` so the app and widget sloths always
    /// agree.
    static let drowsyLeadMinutes = 90

    var isAsleep: Bool {
        if case .asleep = self { return true }
        return false
    }

    /// Which sloth the state wears: awake through the day, drowsy near or
    /// past bedtime, the ember night sloth while asleep.
    var slothPose: SlothPose {
        switch self {
        case .asleep: return .night
        case .pastBedtime: return .drowsy
        case .beforeBed(_, let drowsy): return drowsy ? .drowsy : .awake
        case .noSchedule: return .awake
        }
    }

    static func from(_ summary: SleepWidgetSummary, at now: Date) -> TonightState {
        if let since = summary.asleepSince { return .asleep(since: since) }
        guard let bed = summary.bedtimeMinutes else { return .noSchedule }
        let bedDate = SleepWidgetClock.date(fromMinuteOfDay: bed, onDayOf: now)
        if let wake = summary.wakeMinutes,
           SleepWidgetClock.isInWindow(now: now, bedtimeMinutes: bed, wakeMinutes: wake) {
            return .pastBedtime(bedtime: bedDate)
        }
        let nextBed = SleepWidgetClock.nextOccurrence(ofMinuteOfDay: bed, after: now)
        let drowsy = nextBed.timeIntervalSince(now) <= TimeInterval(Self.drowsyLeadMinutes * 60)
        return .beforeBed(bedtime: nextBed, drowsy: drowsy)
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

// MARK: - The sloth

/// The three poses the mascot wears across the app and its widgets.
enum SlothPose {
    case awake, drowsy, night
}

/// The app's sloth at widget scale, from the extension's own lean asset
/// catalog (WidgetAssets.xcassets, derived from the app's imagesets by
/// `scripts/generate-widget-assets.py`). In iOS 18 tinted mode it renders
/// desaturated — a quiet figure that doesn't fight the user's tint.
private struct WidgetSloth: View {
    let pose: SlothPose
    let height: CGFloat

    private var image: Image {
        switch pose {
        case .awake: return Image("HomeSlothAwake")
        case .drowsy: return Image("HomeSlothDrowsy")
        case .night: return Image("NightSloth")
        }
    }

    var body: some View {
        Group {
            if #available(iOS 18.0, *) {
                image.resizable().widgetAccentedRenderingMode(.desaturated)
            } else {
                image.resizable()
            }
        }
        .scaledToFit()
        .frame(height: height)
        .accessibilityHidden(true)
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
        default:
            // While asleep every system family wears the same sleep face;
            // awake, each family does its own job.
            if case .asleep(let since) = tonight {
                AsleepFaceView(since: since, wakeMinutes: entry.summary.wakeMinutes)
                    .containerBackground(for: .widget) { SleepColor.sleepBlack }
            } else {
                awakeBody
                    .containerBackground(for: .widget) { NightBackground() }
            }
        }
    }

    @ViewBuilder
    private var awakeBody: some View {
        switch family {
        case .systemSmall:
            TonightView(summary: entry.summary, tonight: tonight)
        case .systemLarge:
            LargeSleepView(summary: entry.summary, tonight: tonight)
        default:
            MediumSleepView(summary: entry.summary, tonight: tonight)
        }
    }
}

/// Minimal night gradient per DESIGN.md — no scene art in widgets, just the
/// sky tones with a faint warm floor glow (the "indoor light" accent) that
/// doubles as the lamp the sloth lounges under.
private struct NightBackground: View {
    var body: some View {
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

// MARK: - Asleep: the sleep face

/// SleepModeView shrunk onto the home screen: OLED black, the ember night
/// sloth, the system-driven elapsed timer, and the wake target. One layout
/// grammar per family — small and medium put the instrument beside the
/// figure; large centers the figure like the sleep screen itself.
private struct AsleepFaceView: View {
    let since: Date
    let wakeMinutes: Int?
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemSmall:
            VStack(alignment: .leading, spacing: 0) {
                kicker
                Spacer(minLength: 4)
                timer(size: 26)
                sinceLine(size: 11)
                Spacer(minLength: 6)
                HStack {
                    Spacer(minLength: 0)
                    WidgetSloth(pose: .night, height: 54)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        case .systemLarge:
            VStack(spacing: SleepSpacing.lg) {
                Spacer(minLength: 0)
                WidgetSloth(pose: .night, height: 132)
                kicker
                timer(size: 44)
                HStack(spacing: SleepSpacing.md) {
                    sinceLine(size: 13)
                    wakeLine(size: 13)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        default:
            HStack(alignment: .bottom, spacing: SleepSpacing.lg) {
                VStack(alignment: .leading, spacing: 2) {
                    kicker
                    Spacer(minLength: 4)
                    timer(size: 34)
                    sinceLine(size: 12)
                    wakeLine(size: 12)
                }
                Spacer(minLength: 0)
                WidgetSloth(pose: .night, height: 88)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private var kicker: some View {
        HStack(spacing: 5) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 11))
                .foregroundStyle(SleepColor.ember)
                .widgetAccentable()
            Text("ASLEEP")
                .font(SleepFont.label(11)).tracking(1.4)
                .foregroundStyle(SleepColor.emberDim)
        }
    }

    private func timer(size: CGFloat) -> some View {
        Text(since, style: .timer)
            .font(SleepFont.hero(size))
            .foregroundStyle(SleepColor.ember)
            .monospacedDigit()
            .widgetAccentable()
            .minimumScaleFactor(0.6)
            .lineLimit(1)
    }

    private func sinceLine(size: CGFloat) -> some View {
        Text("since \(since, format: .dateTime.hour().minute())")
            .font(SleepFont.body(size))
            .foregroundStyle(SleepColor.emberDim)
    }

    @ViewBuilder
    private func wakeLine(size: CGFloat) -> some View {
        if let wake = wakeMinutes {
            HStack(spacing: 4) {
                Image(systemName: "sunrise.fill")
                    .font(.system(size: size - 2))
                    .foregroundStyle(SleepColor.emberDim)
                Text("wake \(SleepFormatting.clock(wake))")
                    .font(SleepFont.body(size))
                    .foregroundStyle(SleepColor.emberDim)
            }
        }
    }
}

// MARK: - Small: tonight

/// The bedtime instrument: text block top-leading, the sloth lounging
/// bottom-trailing with its eyes matching the hour. Tonight only — the
/// record lives on medium/large.
private struct TonightView: View {
    let summary: SleepWidgetSummary
    let tonight: TonightState

    var body: some View {
        switch tonight {
        case .beforeBed(let bedtime, _):
            bedtimeBody(bedtime: bedtime, past: false)
        case .pastBedtime(let bedtime):
            bedtimeBody(bedtime: bedtime, past: true)
        case .noSchedule:
            noScheduleBody
        case .asleep:
            EmptyView() // handled by AsleepFaceView at the family dispatch
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

            Spacer(minLength: 4)

            Text(bedtime, format: .dateTime.hour().minute())
                .font(SleepFont.hero(28))
                .foregroundStyle(SleepColor.ink)
                .widgetAccentable()
                .minimumScaleFactor(0.7)
                .lineLimit(1)

            if past {
                Text("Wind down")
                    .font(SleepFont.body(12))
                    .foregroundStyle(SleepColor.amber)
                    .lineLimit(1)
            } else {
                (Text("in ") + Text(bedtime, style: .relative))
                    .font(SleepFont.body(12))
                    .foregroundStyle(SleepColor.dim)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            HStack {
                Spacer(minLength: 0)
                WidgetSloth(pose: tonight.slothPose, height: 56)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var noScheduleBody: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Image(systemName: "moon.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(SleepColor.amber)
                    .widgetAccentable()
                Text("SLEEP")
                    .font(SleepFont.label(11)).tracking(1.4)
                    .foregroundStyle(SleepColor.muted)
            }
            Spacer(minLength: 4)
            Text("Set a schedule to see your bedtime here.")
                .font(SleepFont.body(12))
                .foregroundStyle(SleepColor.dim)
                .lineLimit(3)
            Spacer(minLength: 6)
            HStack {
                Spacer(minLength: 0)
                WidgetSloth(pose: .awake, height: 50)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Medium: stats

/// The morning glance: last night's numbers on the left, the 7-night rhythm
/// and the one action on the right. The sloth lounges under the numerals —
/// the brand figure at rest, its eyes still telling tonight's state.
private struct MediumSleepView: View {
    let summary: SleepWidgetSummary
    let tonight: TonightState

    var body: some View {
        if summary.isEmpty {
            EmptyStatsView(pose: tonight.slothPose, signedIn: summary.isSignedIn ?? true, showButton: !tonight.isAsleep)
        } else {
            HStack(alignment: .top, spacing: SleepSpacing.lg) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Image(systemName: "moon.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(SleepColor.amber)
                            .widgetAccentable()
                        Text("SLEEP")
                            .font(SleepFont.label(11)).tracking(1.4)
                            .foregroundStyle(SleepColor.muted)
                    }

                    // Last night's duration is the hero — the one number the
                    // morning glance answers. No "last night" label: the
                    // rightmost full-strength bar is the same night.
                    if let mins = summary.latestDurationMinutes {
                        Text(SleepFormatting.duration(mins))
                            .font(SleepFont.hero(30))
                            .foregroundStyle(SleepColor.ink)
                            .monospacedDigit()
                            .widgetAccentable()
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                    }

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

                    Spacer(minLength: 2)

                    WidgetSloth(pose: tonight.slothPose, height: 46)
                }
                .frame(maxHeight: .infinity, alignment: .top)

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 0) {
                    SleepBars(nights: summary.nights, target: summary.targetMinutes, height: 64, wholeHours: true)

                    Spacer(minLength: 6)

                    WidgetActionCapsule(signedIn: summary.isSignedIn ?? true)
                }
                .frame(maxWidth: 168, maxHeight: .infinity)
            }
        }
    }

    private var averageDuration: Int? {
        guard !summary.nights.isEmpty else { return nil }
        return summary.nights.reduce(0) { $0 + $1.durationMinutes } / summary.nights.count
    }
}

private struct EmptyStatsView: View {
    let pose: SlothPose
    let signedIn: Bool
    let showButton: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: SleepSpacing.lg) {
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
                if showButton {
                    Spacer(minLength: 4)
                    WidgetActionCapsule(signedIn: signedIn)
                }
            }
            .frame(maxHeight: .infinity, alignment: .topLeading)

            Spacer(minLength: 0)

            WidgetSloth(pose: pose, height: 80)
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
            } else {
                // No hero numeral: the labeled bars carry the week, hour
                // figures included — a second duration on top would just
                // repeat the rightmost bar.
                SleepBars(nights: summary.nights, target: summary.targetMinutes, height: 128, showWeekdays: true)
            }

            Spacer(minLength: 0)

            Rectangle()
                .fill(SleepColor.hairline)
                .frame(height: 1)

            // A mini-Home: the sloth as tonight's figure, the tonight line,
            // and the one action — anchored where a glance lands last.
            HStack(spacing: SleepSpacing.md) {
                WidgetSloth(pose: tonight.slothPose, height: 44)
                TonightFooter(tonight: tonight)
                WidgetActionCapsule(signedIn: summary.isSignedIn ?? true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Tonight in words, beside the footer sloth. The sloth carries the state's
/// mood, so this stays text-only — no doubled moon glyphs.
private struct TonightFooter: View {
    let tonight: TonightState

    var body: some View {
        Group {
            switch tonight {
            case .beforeBed(let bedtime, _):
                VStack(alignment: .leading, spacing: 1) {
                    Text("Bedtime \(bedtime, format: .dateTime.hour().minute())")
                        .font(SleepFont.body(13))
                        .foregroundStyle(SleepColor.dim)
                    (Text("in ") + Text(bedtime, style: .relative))
                        .font(SleepFont.body(12))
                        .foregroundStyle(SleepColor.muted)
                        .lineLimit(1)
                }
            case .pastBedtime:
                VStack(alignment: .leading, spacing: 1) {
                    Text("Past bedtime")
                        .font(SleepFont.body(13))
                        .foregroundStyle(SleepColor.amber)
                    Text("Wind down and sleep")
                        .font(SleepFont.body(12))
                        .foregroundStyle(SleepColor.muted)
                }
            case .noSchedule:
                Text("Set a schedule for a bedtime reminder")
                    .font(SleepFont.body(13))
                    .foregroundStyle(SleepColor.muted)
            case .asleep:
                EmptyView() // large wears the sleep face instead
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Lock-screen accessories
//
// Accessories render in the system's vibrant/tinted material at tiny sizes,
// so they use default foregrounds and SF symbols instead of the app palette
// or the sloth.

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
            if let mins = summary.latestDurationMinutes {
                // Last night's sleep against the target — hours in the middle.
                Gauge(value: Double(min(mins, summary.targetMinutes)), in: 0...Double(max(summary.targetMinutes, 1))) {
                    Image(systemName: "moon.fill")
                } currentValueLabel: {
                    Text("\(Int((Double(mins) / 60).rounded()))h")
                        .font(.system(size: 16, weight: .semibold))
                        .monospacedDigit()
                }
                .gaugeStyle(.accessoryCircular)
                .widgetAccentable()
            } else if case .beforeBed(let bedtime, _) = tonight {
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
            case .beforeBed(let bedtime, _):
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
        if let mins = summary.latestDurationMinutes {
            Text("Slept \(SleepFormatting.duration(mins))")
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
        case .beforeBed(let bedtime, _):
            (Text(Image(systemName: "moon.fill")) + Text(" Bed \(SleepFormatting.shortTime.string(from: bedtime))"))
        case .pastBedtime:
            (Text(Image(systemName: "moon.zzz.fill")) + Text(" Past bedtime"))
        case .noSchedule:
            if let mins = summary.latestDurationMinutes {
                (Text(Image(systemName: "moon.fill")) + Text(" Slept \(SleepFormatting.duration(mins))"))
            } else {
                (Text(Image(systemName: "moon.fill")) + Text(" Sleep"))
            }
        }
    }
}

// MARK: - Shared pieces

/// The widget's one action, in the app's primary-button style. Signed in:
/// "Sleep Now" rides `sleepblock://sleep` (same path as the shield action
/// extension) — the app opens on Home's slide-to-sleep confirmation, because
/// a widget tap must never *start* a session; the slide gesture is the only
/// way a night begins. Signed out: the same capsule reads "Sign in" and
/// rides `sleepblock://signin`, which just opens the app on the welcome
/// screen. Only this capsule carries a URL — tapping anywhere else on the
/// widget simply opens the app.
private struct WidgetActionCapsule: View {
    let signedIn: Bool

    var body: some View {
        Link(destination: URL(string: signedIn ? "sleepblock://sleep" : "sleepblock://signin")!) {
            HStack(spacing: 5) {
                Image(systemName: signedIn ? "moon.fill" : "person.fill")
                    .font(.system(size: 10))
                Text(signedIn ? "Sleep Now" : "Sign in")
                    .font(SleepFont.label(12))
            }
            .foregroundStyle(SleepColor.navy)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(
                    LinearGradient(
                        colors: [SleepColor.amber, SleepColor.gold],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
            )
        }
        .widgetAccentable()
    }
}

/// The 7-night rhythm: duration bars against a target hairline. The latest
/// night is full-strength; earlier nights recede slightly, so "how did I do
/// last night" reads first and the week reads second. Every bar carries its
/// hours on one shared plane via `BarHoursLabel` (navy inside the bar, gold
/// above it, split at the bar's edge), so short nights keep their number.
///
/// The chart always lays out exactly 7 fixed-width columns. Nights the user
/// hasn't logged yet render as the quiet hairline stubs from the empty state,
/// so one logged night is one narrow bar in its slot — not a lone capsule
/// stretched across the full chart width.
private struct SleepBars: View {
    let nights: [WidgetNight]
    let target: Int
    let height: CGFloat
    var showWeekdays: Bool = false
    /// Whole hours, no unit ("7") for the medium widget's narrow columns;
    /// the large widget keeps one decimal + unit ("7.5h").
    var wholeHours: Bool = false

    private static let slotCount = 7

    /// Fixed 7 columns, latest night in the rightmost slot; missing nights
    /// lead-pad as nil.
    private var slots: [WidgetNight?] {
        let recent = Array(nights.suffix(Self.slotCount))
        return Array(repeating: nil, count: Self.slotCount - recent.count) + recent
    }

    var body: some View {
        // 15% headroom above the tallest value keeps the target hairline a
        // reference line *inside* the chart, not a stray rule flush against
        // its top edge (target is usually the max, i.e. fraction 1.0).
        let maxNight = nights.map(\.durationMinutes).max() ?? target
        let scaleMinutes = CGFloat(max(target, maxNight)) * 1.15
        let targetFraction = CGFloat(target) / scaleMinutes

        VStack(spacing: 4) {
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(Array(slots.enumerated()), id: \.offset) { index, night in
                    if let night {
                        let barHeight = max(6, height * CGFloat(night.durationMinutes) / scaleMinutes)
                        ZStack(alignment: .bottom) {
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [SleepColor.gold, SleepColor.amber],
                                        startPoint: .top, endPoint: .bottom
                                    )
                                )
                                .frame(height: barHeight)
                                .frame(maxWidth: .infinity)
                                .widgetAccentable()
                            BarHoursLabel(
                                text: hoursLabel(night.durationMinutes),
                                fontSize: 9,
                                plane: 5,
                                barHeight: barHeight
                            )
                        }
                        .opacity(index == Self.slotCount - 1 ? 1 : 0.62)
                        .frame(maxWidth: .infinity, alignment: .bottom)
                    } else {
                        Capsule().fill(SleepColor.hairline).frame(height: 4)
                            .frame(maxWidth: .infinity, alignment: .bottom)
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
                    ForEach(Array(slots.enumerated()), id: \.offset) { _, night in
                        Text(night.map { SleepFormatting.narrowWeekday.string(from: $0.end) } ?? " ")
                            .font(SleepFont.label(10))
                            .foregroundStyle(SleepColor.muted)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    /// Hours for a bar: whole-number "7" when `wholeHours`, else "7.5h"
    /// (one decimal, no trailing .0).
    private func hoursLabel(_ minutes: Int) -> String {
        let hours = Double(minutes) / 60
        if wholeHours {
            return "\(Int(hours.rounded()))"
        }
        let rounded = (hours * 10).rounded() / 10
        return rounded == rounded.rounded()
            ? "\(Int(rounded))h"
            : String(format: "%.1fh", rounded)
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
            return WidgetNight(end: end, durationMinutes: minutes)
        }
        return SleepWidgetSummary(
            nights: nights,
            latestDurationMinutes: nights.last?.durationMinutes,
            streak: 3,
            targetMinutes: 480,
            bedtimeMinutes: 23 * 60,
            wakeMinutes: 7 * 60,
            asleepSince: nil,
            isSignedIn: true,
            updated: now
        )
    }
}
