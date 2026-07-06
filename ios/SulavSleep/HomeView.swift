import SwiftUI

struct HomeView: View {
    var store: SleepStore
    let profile: Profile

    @State private var showConfirmation = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // Editorial kicker → hero name, the same chrome language as the
                // onboarding questionnaire, so the app opens on one voice.
                VStack(spacing: SleepSpacing.sm) {
                    Text(greeting).sectionLabel()
                    Text(profile.name)
                        .font(SleepFont.hero(40))
                        .foregroundStyle(SleepColor.ink)
                }
                .padding(.top, SleepSpacing.huge * 2)

                TimelineView(.periodic(from: .now, by: 60)) { timeline in
                    BedtimeInstrument(profile: profile, now: timeline.date)
                }
                .padding(.top, SleepSpacing.huge * 1.2)

                // — Action area: transitions between button+summary and confirmation panel —
                if showConfirmation {
                    SleepConfirmationPanel(store: store, profile: profile) {
                        withAnimation(.easeInOut(duration: 0.3)) { showConfirmation = false }
                    }
                    .padding(.top, SleepSpacing.huge * 1.3)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .bottom)),
                        removal: .opacity
                    ))
                } else {
                    VStack(spacing: 0) {
                        LiquidPrimaryButton(title: "Sleep Now", systemImage: "moon.fill") {
                            Haptics.soft()
                            withAnimation(.easeInOut(duration: 0.3)) { showConfirmation = true }
                        }
                        .padding(.top, SleepSpacing.huge * 1.3)

                        LastNightSummary(lastSession: store.latestSession, streak: store.onTrackStreak)
                            .padding(.top, SleepSpacing.huge * 1.4)
                    }
                    .transition(.asymmetric(
                        insertion: .opacity,
                        removal: .opacity.combined(with: .move(edge: .top))
                    ))
                }
            }
            .padding(.horizontal, SleepSpacing.xxl)
            .padding(.top, SleepSpacing.sm)
            .padding(.bottom, SleepSpacing.huge)
        }
        .safeAreaPadding(.top)
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Good night"
        }
    }
}

/// The countdown is the screen's instrument: hero numerals until bedtime, an
/// amber "wind down" state once bedtime has passed (mirroring the small
/// widget), and a quiet one-line readout of tonight's window underneath so the
/// numbers stay anchored to the actual plan.
private struct BedtimeInstrument: View {
    let profile: Profile
    let now: Date

    /// Minutes since bedtime last struck; inside this window the screen stops
    /// counting to *tomorrow's* bedtime (which reads as "22h to bedtime" at
    /// midnight — technically true, emotionally wrong) and nudges instead.
    private static let windDownWindow = 4 * 60

    var body: some View {
        let sinceBedtime = ((SleepFormatting.minutes(from: now) - profile.bedtime) % 1_440 + 1_440) % 1_440
        let isPastBedtime = sinceBedtime > 0 && sinceBedtime < Self.windDownWindow

        VStack(spacing: SleepSpacing.sm) {
            Text(isPastBedtime ? "Bedtime" : "Bedtime in").sectionLabel()

            if isPastBedtime {
                Text("Past bedtime — wind down")
                    .font(SleepFont.title(24))
                    .foregroundStyle(SleepColor.amber)
            } else {
                Text(SleepFormatting.countdown(toMinuteOfDay: profile.bedtime, from: now))
                    .font(SleepFont.hero(44))
                    .foregroundStyle(SleepColor.ink)
                    .monospacedDigit()
            }

            Text("\(SleepFormatting.clock(profile.bedtime)) – \(SleepFormatting.clock(profile.wakeTime))")
                .font(SleepFont.body(14))
                .foregroundStyle(SleepColor.muted)
                .monospacedDigit()
        }
    }
}

private struct LastNightSummary: View {
    let lastSession: SleepSession?
    let streak: Int

    var body: some View {
        // Renders nothing at all without data — no hairline, no empty-state
        // copy. A first night begins the record; until then the scene carries
        // the bottom of the screen.
        if let lastSession {
            VStack(spacing: SleepSpacing.lg) {
                Rectangle().fill(SleepColor.hairline).frame(height: 1)

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
