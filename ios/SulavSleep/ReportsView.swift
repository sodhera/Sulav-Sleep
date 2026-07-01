import SwiftUI

struct ReportsView: View {
    let sessions: [SleepSession]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Reports")
                    .font(SleepFont.hero(30))
                    .foregroundStyle(SleepColor.white)
                    .padding(.top, SleepSpacing.lg)

                if sessions.isEmpty {
                    Text("Your nights will appear here once you start logging sleep.")
                        .font(SleepFont.body(15))
                        .foregroundStyle(SleepColor.quiet)
                        .padding(.top, SleepSpacing.huge)
                } else {
                    ReportContent(sessions: sessions)
                }
            }
            .padding(.horizontal, SleepSpacing.xxl)
            .padding(.bottom, 140)
        }
        .safeAreaPadding(.top)
    }
}

private struct ReportContent: View {
    let sessions: [SleepSession]

    private var lastSeven: [SleepSession] {
        Array(sessions.suffix(7))
    }

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
            VStack(alignment: .leading, spacing: SleepSpacing.sm) {
                Text("LAST 7 NIGHTS")
                    .font(SleepFont.label(12))
                    .foregroundStyle(SleepColor.faint)

                WeeklyChart(sessions: lastSeven)
                    .frame(height: 130)

                HStack {
                    ForEach(lastSeven) { session in
                        Text(SleepFormatting.narrowWeekday.string(from: session.end))
                            .font(SleepFont.body(11))
                            .foregroundStyle(session.id == lastSeven.last?.id ? SleepColor.white : SleepColor.faint)
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
                Text("HISTORY")
                    .font(SleepFont.label(12))
                    .foregroundStyle(SleepColor.faint)
                    .padding(.bottom, SleepSpacing.md)

                ForEach(Array(sessions.reversed().enumerated()), id: \.element.id) { index, session in
                    HistoryRow(session: session)
                        .overlay(alignment: .top) {
                            if index > 0 {
                                Rectangle()
                                    .fill(SleepColor.hairline)
                                    .frame(height: 1)
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
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(SleepFont.body(13))
                .foregroundStyle(SleepColor.quiet)
            Text(value)
                .font(SleepFont.title(26))
                .foregroundStyle(SleepColor.white)
                .monospacedDigit()
        }
    }
}

private struct HistoryRow: View {
    let session: SleepSession

    var body: some View {
        HStack(spacing: SleepSpacing.lg) {
            VStack(alignment: .leading, spacing: 3) {
                Text(SleepFormatting.historyDate.string(from: session.end))
                    .font(SleepFont.label(15))
                    .foregroundStyle(SleepColor.white)
                Text(SleepFormatting.duration(session.durationMinutes))
                    .font(SleepFont.body(13))
                    .foregroundStyle(SleepColor.quiet)
            }

            Spacer()

            ProgressView(value: Double(session.score), total: 100)
                .tint(SleepColor.white)
                .frame(width: 70)

            Text("\(session.score)")
                .font(SleepFont.title(17))
                .foregroundStyle(SleepColor.white)
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
                guard points.count > 1 else { return }

                for hour in [8.0, 7.0, 6.0, 5.0] {
                    let y = yPosition(hours: hour, height: size.height)
                    var grid = Path()
                    grid.move(to: CGPoint(x: 0, y: y))
                    grid.addLine(to: CGPoint(x: size.width, y: y))
                    context.stroke(grid, with: .color(SleepColor.hairline.opacity(0.55)), lineWidth: 1)
                }

                let line = smoothPath(points: points)
                var fill = line
                fill.addLine(to: CGPoint(x: points.last?.x ?? size.width, y: size.height - 16))
                fill.addLine(to: CGPoint(x: points.first?.x ?? 0, y: size.height - 16))
                fill.closeSubpath()

                context.fill(
                    fill,
                    with: .linearGradient(
                        Gradient(colors: [SleepColor.white.opacity(0.22), SleepColor.white.opacity(0)]),
                        startPoint: .zero,
                        endPoint: CGPoint(x: 0, y: size.height)
                    )
                )
                context.stroke(line, with: .color(SleepColor.white), lineWidth: 2.5)

                if let peak = points.min(by: { $0.y < $1.y }) {
                    context.fill(Path(ellipseIn: CGRect(x: peak.x - 4, y: peak.y - 4, width: 8, height: 8)), with: .color(.white.opacity(0.6)))
                }
                if let last = points.last {
                    context.fill(Path(ellipseIn: CGRect(x: last.x - 5.5, y: last.y - 5.5, width: 11, height: 11)), with: .color(SleepColor.white))
                    context.stroke(Path(ellipseIn: CGRect(x: last.x - 10, y: last.y - 10, width: 20, height: 20)), with: .color(.white.opacity(0.35)), lineWidth: 1.5)
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

