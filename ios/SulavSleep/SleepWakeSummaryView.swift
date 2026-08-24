import SwiftUI

// The morning card — the one screen between the night and the day.
//
// Sleep mode is pitch black and ember; Home is the lit city. This sits
// between them and is where the night gets *closed*: hold to wake, and
// instead of the app silently dropping you on Home, the black lifts into the
// morning scene and the night you just slept is on screen in one clear
// reading surface.
//
// Why it exists. Everything else in this app spends its effort on the moment
// someone is trying to break the plan — the shield, the slow door, the
// wind-down. Nothing marked the moment they kept it. A habit needs the
// finish line to be visible, and "the app quietly logged a row" is not a
// finish line.
//
// Why it is restrained anyway (no looping confetti, no score, no badge wall):
// the reader is thirty seconds awake. The grammar is the same instrument
// grammar as the rest of the app — a small label, one large number, quiet
// supporting facts, one brief sunrise sparkle, and one way out. See DESIGN.md,
// "The morning card".
struct WakeSummaryView: View {
    var store: SleepStore
    let summary: WakeSummary

    @State private var risen = false
    @State private var didCelebrate = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var session: SleepSession { summary.session }

    /// The sloth in the scene's current light, eyes open — the same figure
    /// that was asleep on the black a second ago. Morning is the `Day` phase
    /// for anyone waking at a normal hour; a 3am waker gets the night art,
    /// which is honest about what's outside.
    private var slothImage: String {
        "HomeSloth\(CityPhase.current().rawValue)Awake"
    }

    /// Ordinary mornings get a small warm bloom. Human-number streaks earn a
    /// few more pixels, never different copy or a louder layout.
    private var isStreakMilestone: Bool {
        let count = summary.streak.count
        return [7, 14, 30, 50, 100, 200, 365].contains(count)
            || (count > 0 && count.isMultiple(of: 100))
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: SleepSpacing.lg)

            Image(slothImage)
                .resizable()
                .scaledToFit()
                .frame(width: 220)
                .shadow(color: SleepColor.background.opacity(0.45), radius: 18, y: 10)
                // The sunrise: a warm bloom that swells behind the sloth as
                // the card arrives. It is the only "celebration" effect on
                // the screen, and it is light rather than confetti — the
                // whole app is lit by this one amber. A `.background`, not a
                // sibling in a stack: at 380pt it is far taller than the art
                // and would otherwise pad the figure away from the reading
                // below it.
                .background {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    SleepColor.gold.opacity(0.34),
                                    SleepColor.amber.opacity(0.13),
                                    .clear,
                                ],
                                center: .center,
                                startRadius: 4,
                                endRadius: 190
                            )
                        )
                        .frame(width: 380, height: 380)
                        .scaleEffect(risen ? 1 : 0.82)
                        .opacity(risen ? 1 : 0)
                        .blur(radius: 8)
                }
                .overlay {
                    SunriseSparkles(isMilestone: isStreakMilestone)
                        .frame(width: 360, height: 250)
                        .offset(y: -4)
                }
                .accessibilityHidden(true)

            VStack(spacing: SleepSpacing.md) {
                Text("Good morning").sectionLabel()

                // One glance, in order: how long, when, then the run it joins.
                // The duration stays inside the glass because it is the one
                // fact this screen exists to land.
                NightSummaryCapsule(
                    durationMinutes: session.durationMinutes,
                    start: session.start,
                    end: session.end,
                    streak: (summary.streak.isVisible && !summary.streak.isDying)
                        ? summary.streak.count
                        : nil
                )
            }
            .padding(.top, SleepSpacing.xl)

            Spacer(minLength: SleepSpacing.xxxl)

            // One exit, thumb-low, and it goes exactly where it says. There
            // is no dismiss ✕ and no tap-anywhere: a half-awake hand should
            // not be able to lose the screen by brushing it, and there is
            // nothing here to escape from — the day is one tap away.
            LiquidPrimaryButton(title: "Start the day", systemImage: "sun.max.fill") {
                withAnimation(.easeInOut(duration: 0.32)) { store.dismissWakeSummary() }
            }

            Spacer().frame(height: SleepSpacing.xl)
        }
        .padding(.horizontal, SleepSpacing.xxl)
        .safeAreaPadding(.top)
        .opacity(risen ? 1 : 0)
        .offset(y: risen ? 0 : 14)
        .onAppear {
            guard !reduceMotion else {
                risen = true
                return
            }
            // Slow on purpose: the screen it replaces was black, and anything
            // quick reads as a flash to eyes that have been shut for hours.
            withAnimation(.easeOut(duration: 0.9)) { risen = true }
        }
        .task {
            guard !didCelebrate else { return }
            didCelebrate = true
            // Let the black-to-morning lift begin before the success lands.
            // Reduce Motion still gets the tactile finish, just no particles.
            if !reduceMotion {
                try? await Task.sleep(for: .milliseconds(260))
            }
            guard !Task.isCancelled else { return }
            Haptics.success()
        }
    }
}

// MARK: - Sunrise sparkles

/// A one-shot, pixel-edged morning bloom. These are warm window-light flecks,
/// not falling confetti: they start close to the sloth, move out and slightly
/// upward, then disappear before the user starts reading the duration.
private struct SunriseSparkles: View {
    let isMilestone: Bool

    private var seeds: [WakeSparkleSeed] {
        WakeSparkleSeed.ordinary + (isMilestone ? WakeSparkleSeed.milestoneExtra : [])
    }

    var body: some View {
        ZStack {
            ForEach(seeds) { seed in
                WakeSparkle(seed: seed)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct WakeSparkle: View {
    let seed: WakeSparkleSeed

    @State private var phase = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        WakeSparkleGlyph(kind: seed.kind, size: seed.size)
            .foregroundStyle(seed.color)
            .shadow(color: seed.color.opacity(0.55), radius: 5)
            .scaleEffect(phase == 0 ? 0.15 : phase == 1 ? 1 : 0.35)
            .opacity(phase == 1 ? 0.95 : 0)
            .offset(phase == 2 ? seed.end : seed.start)
            .task {
                guard !reduceMotion else { return }
                do {
                    try await Task.sleep(for: .seconds(seed.delay))
                } catch { return }
                withAnimation(.spring(response: 0.22, dampingFraction: 0.58)) {
                    phase = 1
                }
                do {
                    try await Task.sleep(for: .milliseconds(170))
                } catch { return }
                withAnimation(.easeOut(duration: 0.68)) {
                    phase = 2
                }
            }
    }
}

private struct WakeSparkleGlyph: View {
    let kind: WakeSparkleKind
    let size: CGFloat

    var body: some View {
        switch kind {
        case .cross:
            ZStack {
                Rectangle().frame(width: size, height: max(2, size * 0.24))
                Rectangle().frame(width: max(2, size * 0.24), height: size)
            }
        case .diamond:
            Rectangle()
                .frame(width: size * 0.62, height: size * 0.62)
                .rotationEffect(.degrees(45))
        }
    }
}

private enum WakeSparkleKind {
    case cross
    case diamond
}

private struct WakeSparkleSeed: Identifiable {
    let id: Int
    let start: CGSize
    let end: CGSize
    let size: CGFloat
    let delay: Double
    let kind: WakeSparkleKind
    let color: Color

    static let ordinary: [WakeSparkleSeed] = [
        .init(id: 0, start: .init(width: -108, height: -45), end: .init(width: -148, height: -88), size: 10, delay: 0.18, kind: .cross, color: SleepColor.gold),
        .init(id: 1, start: .init(width: 110, height: -42), end: .init(width: 151, height: -79), size: 8, delay: 0.24, kind: .diamond, color: SleepColor.amber),
        .init(id: 2, start: .init(width: -129, height: 8), end: .init(width: -169, height: -10), size: 7, delay: 0.31, kind: .diamond, color: SleepColor.moon),
        .init(id: 3, start: .init(width: 130, height: 17), end: .init(width: 169, height: -5), size: 11, delay: 0.37, kind: .cross, color: SleepColor.gold),
        .init(id: 4, start: .init(width: -83, height: 62), end: .init(width: -118, height: 83), size: 8, delay: 0.43, kind: .cross, color: SleepColor.amber),
        .init(id: 5, start: .init(width: 82, height: 64), end: .init(width: 116, height: 88), size: 7, delay: 0.49, kind: .diamond, color: SleepColor.moon),
        .init(id: 6, start: .init(width: -47, height: -76), end: .init(width: -62, height: -119), size: 6, delay: 0.29, kind: .diamond, color: SleepColor.gold),
        .init(id: 7, start: .init(width: 49, height: -79), end: .init(width: 66, height: -123), size: 9, delay: 0.35, kind: .cross, color: SleepColor.moon),
        .init(id: 8, start: .init(width: -143, height: -22), end: .init(width: -180, height: -52), size: 6, delay: 0.54, kind: .diamond, color: SleepColor.amber),
        .init(id: 9, start: .init(width: 145, height: -14), end: .init(width: 182, height: -43), size: 7, delay: 0.58, kind: .cross, color: SleepColor.gold),
    ]

    static let milestoneExtra: [WakeSparkleSeed] = [
        .init(id: 10, start: .init(width: -22, height: -92), end: .init(width: -27, height: -142), size: 8, delay: 0.20, kind: .cross, color: SleepColor.amber),
        .init(id: 11, start: .init(width: 18, height: 82), end: .init(width: 23, height: 121), size: 6, delay: 0.46, kind: .diamond, color: SleepColor.gold),
        .init(id: 12, start: .init(width: -151, height: 39), end: .init(width: -192, height: 48), size: 9, delay: 0.33, kind: .cross, color: SleepColor.moon),
        .init(id: 13, start: .init(width: 151, height: 45), end: .init(width: 191, height: 54), size: 7, delay: 0.40, kind: .diamond, color: SleepColor.amber),
        .init(id: 14, start: .init(width: -74, height: -70), end: .init(width: -105, height: -112), size: 6, delay: 0.51, kind: .diamond, color: SleepColor.gold),
        .init(id: 15, start: .init(width: 76, height: -67), end: .init(width: 108, height: -109), size: 10, delay: 0.55, kind: .cross, color: SleepColor.moon),
    ]
}

// MARK: - The night capsule

/// The whole night in one glass surface, deliberately ordered by importance:
/// duration first, the actual clock window second, and the streak last.
///
/// The moon→sun grammar is Home's schedule capsule, deliberately — "the window
/// you planned" and "the window you slept" should read as the same kind of
/// fact in the same kind of container. Not a button: there is one action on
/// this screen.
private struct NightSummaryCapsule: View {
    let durationMinutes: Int
    let start: Date
    let end: Date
    /// Nights in a row, or `nil` to show the clock alone.
    let streak: Int?

    private var startText: String { SleepFormatting.shortTime.string(from: start) }
    private var endText: String { SleepFormatting.shortTime.string(from: end) }

    var body: some View {
        VStack(spacing: SleepSpacing.lg) {
            // The timer's last reading, kept in the same hero numerals and
            // given the capsule's only high-contrast position.
            Text(SleepFormatting.duration(durationMinutes))
                .font(SleepFont.hero(50))
                .foregroundStyle(SleepColor.ink)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            details
        }
        .padding(.horizontal, SleepSpacing.xl)
        .padding(.vertical, SleepSpacing.xl)
        .frame(maxWidth: .infinity)
        .liquidGlass(cornerRadius: SleepRadius.xl)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    /// Keep the ordinary case on one calm line. Larger text sizes and narrow
    /// widths fall back to a vertical reading instead of compressing the two
    /// supporting facts into an unreadable row.
    @ViewBuilder
    private var details: some View {
        if let streak {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: SleepSpacing.md) {
                    window
                    detailDivider
                    streakLabel(streak)
                }

                VStack(spacing: SleepSpacing.md) {
                    window
                    streakLabel(streak)
                }
            }
        } else {
            window
        }
    }

    private var window: some View {
        HStack(spacing: SleepSpacing.sm) {
            endpoint(icon: "moon.fill", time: startText)
            Image(systemName: "arrow.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(SleepColor.muted)
            endpoint(icon: "sun.max.fill", time: endText)
        }
    }

    private var detailDivider: some View {
        Rectangle()
            .fill(SleepColor.hairline)
            .frame(width: 1, height: 18)
    }

    private func streakLabel(_ count: Int) -> some View {
        Label("\(count) \(count == 1 ? "night" : "nights")", systemImage: "flame.fill")
            .font(SleepFont.label(13))
            .foregroundStyle(SleepColor.gold)
            .monospacedDigit()
            .lineLimit(1)
    }

    private func endpoint(icon: String, time: String) -> some View {
        HStack(spacing: SleepSpacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(SleepColor.amber.opacity(0.9))
            Text(time)
                .font(SleepFont.label(13))
                .foregroundStyle(SleepColor.dim)
                .monospacedDigit()
                .lineLimit(1)
        }
    }

    private var accessibilityText: String {
        let duration = "You slept \(durationMinutes / 60) hours \(durationMinutes % 60) minutes."
        let window = "Asleep \(startText), awake \(endText)."
        guard let streak else { return "\(duration) \(window)" }
        return "\(duration) \(window) \(streak) night streak."
    }
}

// MARK: - Preview data

#if DEBUG
extension WakeSummary {
    /// The night `-review-wake-summary` renders (see RootView). A good,
    /// ordinary night on a live run — the card's most common shape, not its
    /// best case, so the preview is worth trusting.
    static var sample: WakeSummary {
        let end = Date()
        let minutes = 7 * 60 + 32
        let start = end.addingTimeInterval(-Double(minutes) * 60)
        return WakeSummary(
            session: SleepSession(
                id: "sample",
                start: start,
                end: end,
                durationMinutes: minutes,
                source: .local
            ),
            streak: SleepStreak(count: 4, state: .alive)
        )
    }
}
#endif
