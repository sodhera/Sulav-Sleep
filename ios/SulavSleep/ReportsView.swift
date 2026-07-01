import SwiftUI

struct ReportsView: View {
    var store: SleepStore

    private var sessions: [SleepSession] { store.displaySessions }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Reports")
                        .font(SleepFont.hero(30))
                        .foregroundStyle(SleepColor.ink)
                    Spacer()
                    if store.isImportingHealth {
                        ProgressView().controlSize(.small).tint(SleepColor.amber)
                    }
                }
                .padding(.top, SleepSpacing.lg)

                if sessions.isEmpty {
                    EmptyReports(healthState: store.healthSyncState)
                } else {
                    ReportContent(sessions: sessions, hasHealth: sessions.contains { $0.source == .healthKit })
                }
            }
            .padding(.horizontal, SleepSpacing.xxl)
            .padding(.bottom, 140)
        }
        .safeAreaPadding(.top)
    }
}

private struct EmptyReports: View {
    let healthState: HealthSyncState

    var body: some View {
        VStack(alignment: .leading, spacing: SleepSpacing.md) {
            Image(systemName: "moon.stars")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(SleepColor.muted)
                .padding(.bottom, SleepSpacing.xs)
            Text("Nothing to show yet")
                .font(SleepFont.title(20))
                .foregroundStyle(SleepColor.ink)
            Text(healthState == .connected
                 ? "Log a night, or once Apple Health has sleep recorded it will appear here — nothing is made up."
                 : "Your nights will appear here once you log sleep. Connect Apple Health in Settings to pull in your real history.")
                .font(SleepFont.body(15))
                .foregroundStyle(SleepColor.muted)
                .lineSpacing(4)
                .frame(maxWidth: 320, alignment: .leading)
        }
        .padding(.top, SleepSpacing.huge * 1.5)
    }
}

private struct ReportContent: View {
    let sessions: [SleepSession]
    let hasHealth: Bool

    private var lastSeven: [SleepSession] { Array(sessions.suffix(7)) }

    private var averageDuration: Int {
        guard !sessions.isEmpty else { return 0 }
        return sessions.reduce(0) { $0 + $1.durationMinutes } / sessions.count
    }

    private var averageScore: Int {
        guard !sessions.isEmpty else { return 0 }
        return sessions.reduce(0) { $0 + $1.score } / sessions.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: SleepSpacing.md) {
                Text("Last 7 nights").sectionLabel()

                WeeklyChart(sessions: lastSeven)
                    .frame(height: 132)

                HStack {
                    ForEach(lastSeven) { session in
                        Text(SleepFormatting.narrowWeekday.string(from: session.end))
                            .font(SleepFont.body(11))
                            .foregroundStyle(session.id == lastSeven.last?.id ? SleepColor.amber : SleepColor.faint)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.top, SleepSpacing.xxl)

            HStack(spacing: SleepSpacing.huge) {
                StatBlock(label: "Avg. duration", value: SleepFormatting.duration(averageDuration))
                StatBlock(label: "Avg. score", value: "\(averageScore)")
            }
            .padding(.top, SleepSpacing.huge)

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("History").sectionLabel()
                    Spacer()
                    if hasHealth {
                        Label("Apple Health", systemImage: "heart.fill")
                            .font(SleepFont.label(11))
                            .foregroundStyle(SleepColor.muted)
                    }
                }
                .padding(.bottom, SleepSpacing.md)

                ForEach(Array(sessions.reversed().enumerated()), id: \.element.id) { index, session in
                    HistoryRow(session: session)
                        .overlay(alignment: .top) {
                            if index > 0 {
                                Rectangle().fill(SleepColor.hairline).frame(height: 1)
                            }
                        }
                }
            }
            .padding(.top, SleepSpacing.huge)
        }
    }
}

private struct StatBlock: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(SleepFont.body(13))
                .foregroundStyle(SleepColor.muted)
            Text(value)
                .font(SleepFont.title(26))
                .foregroundStyle(SleepColor.ink)
                .monospacedDigit()
        }
    }
}

private struct HistoryRow: View {
    let session: SleepSession

    var body: some View {
        HStack(spacing: SleepSpacing.lg) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: SleepSpacing.xs) {
                    Text(SleepFormatting.historyDate.string(from: session.end))
                        .font(SleepFont.label(15))
                        .foregroundStyle(SleepColor.ink)
                    Image(systemName: session.source == .healthKit ? "heart.fill" : "moon.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(SleepColor.faint)
                        .accessibilityLabel(session.source == .healthKit ? "From Apple Health" : "Logged in app")
                }
                Text(SleepFormatting.duration(session.durationMinutes))
                    .font(SleepFont.body(13))
                    .foregroundStyle(SleepColor.muted)
            }

            Spacer()

            ProgressView(value: Double(session.score), total: 100)
                .tint(SleepColor.gold)
                .frame(width: 70)

            Text("\(session.score)")
                .font(SleepFont.title(17))
                .foregroundStyle(SleepColor.ink)
                .frame(width: 34, alignment: .trailing)
                .monospacedDigit()
        }
        .padding(.vertical, SleepSpacing.lg)
    }
}

private struct WeeklyChart: View {
    let sessions: [SleepSession]

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                let points = chartPoints(size: size)
                guard points.count > 1 else {
                    if let only = points.first {
                        context.fill(
                            Path(ellipseIn: CGRect(x: only.x - 5, y: only.y - 5, width: 10, height: 10)),
                            with: .color(SleepColor.amber)
                        )
                    }
                    return
                }

                for hour in [8.0, 7.0, 6.0, 5.0] {
                    let y = yPosition(hours: hour, height: size.height)
                    var grid = Path()
                    grid.move(to: CGPoint(x: 0, y: y))
                    grid.addLine(to: CGPoint(x: size.width, y: y))
                    context.stroke(grid, with: .color(SleepColor.hairline), lineWidth: 1)
                }

                let line = smoothPath(points: points)
                var fill = line
                fill.addLine(to: CGPoint(x: points.last?.x ?? size.width, y: size.height - 16))
                fill.addLine(to: CGPoint(x: points.first?.x ?? 0, y: size.height - 16))
                fill.closeSubpath()

                context.fill(
                    fill,
                    with: .linearGradient(
                        Gradient(colors: [SleepColor.amber.opacity(0.24), SleepColor.amber.opacity(0)]),
                        startPoint: .zero,
                        endPoint: CGPoint(x: 0, y: size.height)
                    )
                )
                context.stroke(
                    line,
                    with: .linearGradient(
                        Gradient(colors: [SleepColor.gold, SleepColor.amber]),
                        startPoint: .zero,
                        endPoint: CGPoint(x: size.width, y: 0)
                    ),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                )

                if let last = points.last {
                    context.fill(
                        Path(ellipseIn: CGRect(x: last.x - 5.5, y: last.y - 5.5, width: 11, height: 11)),
                        with: .color(SleepColor.amber)
                    )
                    context.stroke(
                        Path(ellipseIn: CGRect(x: last.x - 10, y: last.y - 10, width: 20, height: 20)),
                        with: .color(SleepColor.amber.opacity(0.35)), lineWidth: 1.5
                    )
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func chartPoints(size: CGSize) -> [CGPoint] {
        let values = sessions.map { Double($0.durationMinutes) / 60 }
        return values.enumerated().map { index, value in
            CGPoint(
                x: CGFloat(index) / CGFloat(max(values.count - 1, 1)) * size.width,
                y: yPosition(hours: min(9, max(4.5, value)), height: size.height)
            )
        }
    }

    private func yPosition(hours: Double, height: CGFloat) -> CGFloat {
        let padTop: CGFloat = 14
        let padBottom: CGFloat = 16
        let plotHeight = height - padTop - padBottom
        return padTop + (1 - CGFloat((hours - 4.5) / (9 - 4.5))) * plotHeight
    }

    private func smoothPath(points: [CGPoint]) -> Path {
        var path = Path()
        path.move(to: points[0])
        for index in 0..<(points.count - 1) {
            let p0 = points[max(index - 1, 0)]
            let p1 = points[index]
            let p2 = points[index + 1]
            let p3 = points[min(index + 2, points.count - 1)]
            path.addCurve(
                to: p2,
                control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            )
        }
        return path
    }
}
