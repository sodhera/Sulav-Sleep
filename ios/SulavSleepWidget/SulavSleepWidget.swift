import WidgetKit
import SwiftUI

// Home-screen widget: recent sleep at a glance — last score and a 7-night bar
// graph. Reads the shared App Group summary the app publishes on every change.
// No fabricated data: an empty summary renders an honest "Log a night" state.

struct SleepEntry: TimelineEntry {
    let date: Date
    let summary: SleepWidgetSummary
}

struct SleepProvider: TimelineProvider {
    func placeholder(in context: Context) -> SleepEntry {
        SleepEntry(date: Date(), summary: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (SleepEntry) -> Void) {
        completion(SleepEntry(date: Date(), summary: SleepWidgetStore.load() ?? .empty))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SleepEntry>) -> Void) {
        let entry = SleepEntry(date: Date(), summary: SleepWidgetStore.load() ?? .empty)
        // The app pushes reloads on change; this is just a slow fallback refresh.
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(3600))))
    }
}

struct SulavSleepWidget: Widget {
    let kind = "SulavSleepWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SleepProvider()) { entry in
            SleepWidgetView(summary: entry.summary)
                .containerBackground(for: .widget) {
                    LinearGradient(
                        colors: [SleepColor.navy, SleepColor.background],
                        startPoint: .top, endPoint: .bottom
                    )
                }
        }
        .configurationDisplayName("Sleep")
        .description("Your recent sleep and score.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct SulavSleepWidgetBundle: WidgetBundle {
    var body: some Widget {
        SulavSleepWidget()
    }
}

// MARK: - Views

private struct SleepWidgetView: View {
    let summary: SleepWidgetSummary
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemSmall: SmallSleepView(summary: summary)
        default: MediumSleepView(summary: summary)
        }
    }
}

private struct SmallSleepView: View {
    let summary: SleepWidgetSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("SLEEP")
                .font(SleepFont.label(11)).tracking(1.4)
                .foregroundStyle(SleepColor.muted)

            Spacer(minLength: 4)

            if let score = summary.latestScore {
                Text("\(score)")
                    .font(.system(size: 44, weight: .semibold, design: .default))
                    .foregroundStyle(scoreColor(score))
                    .monospacedDigit()
                if let mins = summary.latestDurationMinutes {
                    Text(SleepFormatting.duration(mins))
                        .font(SleepFont.body(12))
                        .foregroundStyle(SleepColor.dim)
                }
            } else {
                Text("—")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(SleepColor.muted)
                Text("Log a night")
                    .font(SleepFont.body(12))
                    .foregroundStyle(SleepColor.muted)
            }

            Spacer(minLength: 6)

            SleepBars(nights: summary.nights, target: summary.targetMinutes, height: 26)
        }
    }
}

private struct MediumSleepView: View {
    let summary: SleepWidgetSummary

    var body: some View {
        HStack(spacing: SleepSpacing.lg) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Sleep")
                    .font(SleepFont.title(20))
                    .foregroundStyle(SleepColor.ink)

                if summary.isEmpty {
                    Text("Log a night to see your rhythm.")
                        .font(SleepFont.body(12))
                        .foregroundStyle(SleepColor.muted)
                } else {
                    if let score = summary.latestScore {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(score)")
                                .font(.system(size: 30, weight: .semibold))
                                .foregroundStyle(scoreColor(score))
                                .monospacedDigit()
                            Text("last score")
                                .font(SleepFont.body(11))
                                .foregroundStyle(SleepColor.muted)
                        }
                    }
                    if summary.streak > 0 {
                        Label("\(summary.streak) on track", systemImage: "flame.fill")
                            .font(SleepFont.body(12))
                            .foregroundStyle(SleepColor.gold)
                    }
                    if let avg = averageDuration {
                        Text("avg \(SleepFormatting.duration(avg))")
                            .font(SleepFont.body(11))
                            .foregroundStyle(SleepColor.muted)
                    }
                }
            }

            Spacer(minLength: 0)

            SleepBars(nights: summary.nights, target: summary.targetMinutes, height: 74)
                .frame(maxWidth: 160)
        }
    }

    private var averageDuration: Int? {
        guard !summary.nights.isEmpty else { return nil }
        return summary.nights.reduce(0) { $0 + $1.durationMinutes } / summary.nights.count
    }
}

private struct SleepBars: View {
    let nights: [WidgetNight]
    let target: Int
    let height: CGFloat

    var body: some View {
        let maxMinutes = max(target, nights.map(\.durationMinutes).max() ?? target)
        HStack(alignment: .bottom, spacing: 4) {
            if nights.isEmpty {
                ForEach(0..<7, id: \.self) { _ in
                    Capsule().fill(SleepColor.hairline).frame(height: 4)
                        .frame(maxWidth: .infinity, alignment: .bottom)
                }
            } else {
                ForEach(nights) { night in
                    let frac = max(0.08, CGFloat(night.durationMinutes) / CGFloat(maxMinutes))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [SleepColor.gold, SleepColor.amber],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .frame(height: height * frac)
                        .frame(maxWidth: .infinity, alignment: .bottom)
                }
            }
        }
        .frame(height: height, alignment: .bottom)
    }
}

private func scoreColor(_ score: Int) -> Color {
    switch score {
    case 80...: return SleepColor.gold
    case 60..<80: return SleepColor.ink
    default: return SleepColor.danger
    }
}
