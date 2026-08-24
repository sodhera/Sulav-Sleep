import SwiftUI

// The morning card — the one screen between the night and the day.
//
// Sleep mode is pitch black and ember; Home is the lit city. This sits
// between them and is where the night gets *closed*: hold to wake, and
// instead of the app silently dropping you on Home, the black lifts into the
// morning scene and the night you just slept is on screen with a line that
// says something true about it.
//
// Why it exists. Everything else in this app spends its effort on the moment
// someone is trying to break the plan — the shield, the slow door, the
// wind-down. Nothing marked the moment they kept it. A habit needs the
// finish line to be visible, and "the app quietly logged a row" is not a
// finish line.
//
// Why it is restrained anyway (no confetti, no score, no streak fireworks):
// the reader is thirty seconds awake. The grammar is the same instrument
// grammar as the rest of the app — a small label, one large number, a quiet
// caption — with exactly one warm sentence and one way out. See DESIGN.md,
// "The morning card".
struct WakeSummaryView: View {
    var store: SleepStore
    let summary: WakeSummary

    @State private var risen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var session: SleepSession { summary.session }

    /// The sloth in the scene's current light, eyes open — the same figure
    /// that was asleep on the black a second ago. Morning is the `Day` phase
    /// for anyone waking at a normal hour; a 3am waker gets the night art,
    /// which is honest about what's outside.
    private var slothImage: String {
        "HomeSloth\(CityPhase.current().rawValue)Awake"
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
                .accessibilityHidden(true)

            VStack(spacing: SleepSpacing.sm) {
                Text("Good morning").sectionLabel()

                // The night, in the same numerals the sleep screen was
                // counting up a moment ago — the timer's last reading, kept.
                Text(SleepFormatting.duration(session.durationMinutes))
                    .font(SleepFont.hero(44))
                    .foregroundStyle(SleepColor.ink)
                    .monospacedDigit()
                    .accessibilityLabel(
                        "You slept \(session.durationMinutes / 60) hours \(session.durationMinutes % 60) minutes"
                    )

                WokeWindowLine(start: session.start, end: session.end)
                    .padding(.top, SleepSpacing.xs)
            }
            .padding(.top, SleepSpacing.xl)

            // The flame, only when there is a live run behind it. A dying or
            // absent streak says nothing here: this screen is the one place
            // in the app that is purely for the good news, and a warning
            // delivered to someone who just did the thing right is noise.
            if summary.streak.isVisible && !summary.streak.isDying {
                StreakBadge(count: summary.streak.count)
                    .padding(.top, SleepSpacing.xl)
            }

            // The line. Earned by this night specifically — see
            // `WakeCelebration` for the tiers and why none of them inflate.
            Text(WakeCelebration.line(for: summary.night))
                .font(SleepFont.body(15))
                .foregroundStyle(SleepColor.dim)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, SleepSpacing.md)
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
    }
}

// MARK: - Window line

/// When the night ran: moon + the hour they started → sun + the hour they
/// woke. The same moon→sun grammar as Home's schedule capsule, so "the window
/// you planned" and "the window you slept" are visibly the same kind of fact.
private struct WokeWindowLine: View {
    private let startText: String
    private let endText: String

    init(start: Date, end: Date) {
        startText = SleepFormatting.shortTime.string(from: start)
        endText = SleepFormatting.shortTime.string(from: end)
    }

    var body: some View {
        HStack(spacing: SleepSpacing.sm) {
            endpoint(icon: "moon.fill", time: startText)
            Image(systemName: "arrow.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(SleepColor.muted)
            endpoint(icon: "sun.max.fill", time: endText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Asleep \(startText), awake \(endText)")
    }

    private func endpoint(icon: String, time: String) -> some View {
        HStack(spacing: SleepSpacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(SleepColor.amber.opacity(0.85))
            Text(time)
                .font(SleepFont.label(13))
                .foregroundStyle(SleepColor.muted)
                .monospacedDigit()
        }
    }
}

// MARK: - Streak badge

/// The run, worn as a glass capsule — the same flame and the same filled gold
/// as Home's corner chip, so the number the user is about to see there is
/// already familiar. Not a button: there is one action on this screen.
private struct StreakBadge: View {
    let count: Int

    var body: some View {
        Label("\(count) \(count == 1 ? "night" : "nights") in a row", systemImage: "flame.fill")
            .font(SleepFont.label(14))
            .foregroundStyle(SleepColor.gold)
            .monospacedDigit()
            .padding(.horizontal, SleepSpacing.lg)
            .frame(minHeight: 40)
            .liquidGlass(cornerRadius: SleepRadius.pill)
            .accessibilityLabel("\(count) night streak")
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
            streak: SleepStreak(count: 4, state: .alive),
            night: WakeNight(
                durationMinutes: minutes,
                targetMinutes: 8 * 60,
                streak: 4,
                isFirstNight: false,
                reaches: 0,
                variant: 0
            )
        )
    }
}
#endif
