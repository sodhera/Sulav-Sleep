import SwiftUI

// Home is the bedside instrument: one glance says how long until bed, one
// action starts the night. The composition is a single centered column with
// almost no prose — greeting up top, the bedtime ring as the hero, two glass
// schedule chips under it, and the Sleep Now capsule anchored low where a
// thumb naturally rests. The screen never scrolls; an instrument doesn't.
struct HomeView: View {
    var store: SleepStore
    let profile: Profile

    @State private var showConfirmation = false

    var body: some View {
        ZStack {
            if showConfirmation {
                // Scrolls up into view when Sleep Now is tapped, and — on
                // Cancel — scrolls back down the same way it arrived, rather
                // than fading in place.
                SleepConfirmationPanel(store: store, profile: profile) {
                    withAnimation(.easeInOut(duration: 0.32)) { showConfirmation = false }
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .bottom)),
                    removal: .opacity.combined(with: .move(edge: .bottom))
                ))
            } else {
                homeContent
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity.combined(with: .move(edge: .top))
                    ))
            }
        }
        .padding(.horizontal, SleepSpacing.xxl)
        .safeAreaPadding(.top)
    }

    private var homeContent: some View {
        VStack(spacing: 0) {
            VStack(spacing: SleepSpacing.sm) {
                Text(greeting).sectionLabel()
                Text(profile.name)
                    .font(SleepFont.hero(36))
                    .foregroundStyle(SleepColor.ink)
            }
            .padding(.top, SleepSpacing.huge)

            Spacer(minLength: SleepSpacing.xxxl)

            TimelineView(.periodic(from: .now, by: 60)) { timeline in
                VStack(spacing: SleepSpacing.xxl) {
                    BedtimeRing(profile: profile, now: timeline.date)

                    HStack(spacing: SleepSpacing.md) {
                        ScheduleChip(icon: "moon.fill", text: SleepFormatting.clock(profile.bedtime))
                        ScheduleChip(icon: "sun.max.fill", text: SleepFormatting.clock(profile.wakeTime))
                    }
                }
            }

            Spacer(minLength: SleepSpacing.xxxl)

            LiquidPrimaryButton(title: "Sleep Now", systemImage: "moon.fill") {
                Haptics.soft()
                withAnimation(.easeInOut(duration: 0.3)) { showConfirmation = true }
            }

            LastNightStrip(lastSession: store.latestSession, streak: store.onTrackStreak)
                .padding(.top, SleepSpacing.xl)

            Spacer().frame(height: SleepSpacing.xl)
        }
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

// MARK: - Bedtime ring

/// The screen's hero instrument: a 270° gauge arc that fills as the waking day
/// runs toward bedtime, with a glowing moon marker riding the tip and the
/// countdown numerals in the middle. Once bedtime passes the ring sits full
/// and amber and the numerals give way to a "wind down" nudge (mirroring the
/// small widget) instead of counting 20-odd hours to *tomorrow's* bedtime.
private struct BedtimeRing: View {
    let profile: Profile
    let now: Date

    /// Minutes after bedtime during which the ring shows the wind-down state.
    private static let windDownWindow = 4 * 60
    /// The arc spans 270°, leaving a gap at the bottom like a speedometer.
    private static let arcSpan = 0.75

    private let size: CGFloat = 250
    private let lineWidth: CGFloat = 7

    var body: some View {
        let nowMinutes = SleepFormatting.minutes(from: now)
        let sinceBedtime = ((nowMinutes - profile.bedtime) % 1_440 + 1_440) % 1_440
        let isPastBedtime = sinceBedtime > 0 && sinceBedtime < Self.windDownWindow
        let progress = isPastBedtime ? 1 : dayProgress(nowMinutes: nowMinutes)

        ZStack {
            // Track
            Circle()
                .trim(from: 0, to: Self.arcSpan)
                .stroke(Color.white.opacity(0.08), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(135))

            // Progress fill — warm gradient sweeping with the arc.
            Circle()
                .trim(from: 0, to: Self.arcSpan * progress)
                .stroke(
                    AngularGradient(
                        colors: [SleepColor.gold, SleepColor.amber],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(135))
                .shadow(color: SleepColor.amber.opacity(0.35), radius: 12)

            moonMarker(progress: progress)

            VStack(spacing: SleepSpacing.sm) {
                Text(isPastBedtime ? "Bedtime" : "Bedtime in").sectionLabel()
                if isPastBedtime {
                    Text("Wind down")
                        .font(SleepFont.title(26))
                        .foregroundStyle(SleepColor.amber)
                } else {
                    Text(SleepFormatting.countdown(toMinuteOfDay: profile.bedtime, from: now))
                        .font(SleepFont.hero(40))
                        .foregroundStyle(SleepColor.ink)
                        .monospacedDigit()
                }
            }
        }
        .frame(width: size, height: size)
        .animation(.easeInOut(duration: 0.6), value: progress)
    }

    /// Fraction of the waking day (wake → bedtime) already behind you.
    private func dayProgress(nowMinutes: Int) -> Double {
        let awakeTotal = ((profile.bedtime - profile.wakeTime) % 1_440 + 1_440) % 1_440
        guard awakeTotal > 0 else { return 0 }
        let sinceWake = ((nowMinutes - profile.wakeTime) % 1_440 + 1_440) % 1_440
        return min(1, Double(sinceWake) / Double(awakeTotal))
    }

    /// The glowing dot riding the arc tip — "the moon is on its way".
    private func moonMarker(progress: Double) -> some View {
        let angle = Angle.degrees(135 + 270 * progress)
        let radius = (size - lineWidth) / 2
        return Circle()
            .fill(SleepColor.amber)
            .overlay { Circle().stroke(Color.white.opacity(0.35), lineWidth: 1) }
            .frame(width: 16, height: 16)
            .shadow(color: SleepColor.amber.opacity(0.7), radius: 8)
            .offset(
                x: radius * CGFloat(cos(angle.radians)),
                y: radius * CGFloat(sin(angle.radians))
            )
    }
}

// MARK: - Schedule chips

/// Tiny glass capsule stating one side of tonight's window — an icon and a
/// time, nothing to fiddle with. The schedule is edited in Settings.
private struct ScheduleChip: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: SleepSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(SleepColor.amber)
            Text(text)
                .font(SleepFont.label(14))
                .foregroundStyle(SleepColor.dim)
                .monospacedDigit()
        }
        .padding(.horizontal, SleepSpacing.lg)
        .frame(height: 36)
        .liquidGlass(cornerRadius: SleepRadius.pill)
    }
}

// MARK: - Last night strip

/// One quiet centered line under the button — duration, score, streak — and
/// nothing at all without data: no hairline, no empty-state copy. A first
/// night begins the record.
private struct LastNightStrip: View {
    let lastSession: SleepSession?
    let streak: Int

    var body: some View {
        if let lastSession {
            HStack(spacing: SleepSpacing.sm) {
                Text("Last night")
                    .font(SleepFont.body(13))
                    .foregroundStyle(SleepColor.muted)
                Text(SleepFormatting.duration(lastSession.durationMinutes))
                    .font(SleepFont.label(14))
                    .foregroundStyle(SleepColor.dim)
                    .monospacedDigit()
                Text("·")
                    .font(SleepFont.body(13))
                    .foregroundStyle(SleepColor.faint)
                Text("\(lastSession.score)")
                    .font(SleepFont.label(14))
                    .foregroundStyle(scoreColor(lastSession.score))
                    .monospacedDigit()
                if streak > 0 {
                    Text("·")
                        .font(SleepFont.body(13))
                        .foregroundStyle(SleepColor.faint)
                    Label("\(streak)", systemImage: "flame.fill")
                        .font(SleepFont.label(13))
                        .foregroundStyle(SleepColor.gold)
                }
            }
            .frame(maxWidth: .infinity)
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
