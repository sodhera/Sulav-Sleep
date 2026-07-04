import SwiftUI

struct HomeView: View {
    var store: SleepStore
    let profile: Profile

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                VStack(spacing: SleepSpacing.xs) {
                    Text(greeting)
                        .font(SleepFont.body(16))
                        .foregroundStyle(SleepColor.dim)
                    Text(profile.name)
                        .font(SleepFont.hero(36))
                        .foregroundStyle(SleepColor.ink)
                }
                .padding(.top, SleepSpacing.huge * 2.4)

                TimelineView(.periodic(from: .now, by: 60)) { timeline in
                    VStack(spacing: SleepSpacing.xs) {
                        Text("Bedtime in").sectionLabel()
                        Text(SleepFormatting.countdown(toMinuteOfDay: profile.bedtime, from: timeline.date))
                            .font(SleepFont.title(24))
                            .foregroundStyle(SleepColor.ink)
                            .monospacedDigit()
                    }
                }
                .padding(.top, SleepSpacing.huge)

                LiquidPrimaryButton(title: "Sleep Now", systemImage: "moon.fill") {
                    Haptics.soft()
                    store.startSleep()
                }
                .padding(.top, SleepSpacing.huge * 1.3)

                LastNightSummary(lastSession: store.latestSession, streak: store.onTrackStreak)
                    .padding(.top, SleepSpacing.huge * 1.4)
            }
            .padding(.horizontal, SleepSpacing.xxl)
            .padding(.top, SleepSpacing.sm)
            .padding(.bottom, SleepSpacing.huge)
        }
        .safeAreaPadding(.top)
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: return "Good morning,"
        case 12..<17: return "Good afternoon,"
        case 17..<22: return "Good evening,"
        default: return "Good night,"
        }
    }
}

private struct LastNightSummary: View {
    let lastSession: SleepSession?
    let streak: Int

    var body: some View {
        VStack(spacing: SleepSpacing.lg) {
            Rectangle().fill(SleepColor.hairline).frame(height: 1)

            if let lastSession {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Last night")
                            .font(SleepFont.body(13))
                            .foregroundStyle(SleepColor.muted)
                        Text(SleepFormatting.duration(lastSession.durationMinutes))
                            .font(SleepFont.title(28))
                            .foregroundStyle(SleepColor.ink)
                            .monospacedDigit()
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("Score")
                            .font(SleepFont.body(13))
                            .foregroundStyle(SleepColor.muted)
                        Text("\(lastSession.score)")
                            .font(SleepFont.title(28))
                            .foregroundStyle(scoreColor(lastSession.score))
                            .monospacedDigit()
                    }
                }

                if streak > 0 {
                    Label("\(streak) night\(streak > 1 ? "s" : "") on track", systemImage: "flame.fill")
                        .font(SleepFont.body(14))
                        .foregroundStyle(SleepColor.gold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text("No nights logged yet.")
                    .font(SleepFont.body(15))
                    .foregroundStyle(SleepColor.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 80...: return SleepColor.gold
        case 60..<80: return SleepColor.ink
        default: return SleepColor.danger
        }
    }
}
