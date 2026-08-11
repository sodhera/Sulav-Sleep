import SwiftUI

/// Two minutes of breathing — somewhere for a person who isn't ready to sleep
/// to go that isn't a blocked app.
///
/// The gap this fills: blocking creates an empty moment, and an empty moment at
/// 1am is when people go hunting for a way around the lock. Every other surface
/// in the app asks someone to *stop* doing something; this is the only one that
/// offers something to do instead, which is why it's a much easier yes than the
/// slide-to-sleep commitment. Someone reaching for Instagram is not ready to
/// commit to a whole night — that's precisely why they're reaching — so asking
/// them to is the wrong-sized ask.
///
/// Reached from the sleep confirmation ("Not ready?"), from the notification
/// that fires when a snooze runs out (the moment someone is most adrift), and
/// from `sleepblock://winddown`.
///
/// It never locks anything, never scolds, and can be left at any time. Two
/// minutes is deliberately short: a craving fades in about that long, and a
/// wind-down long enough to feel like a chore is one people decline.
struct WindDownView: View {
    var store: SleepStore
    /// Leaves wind-down without starting a night.
    var onDone: () -> Void
    /// "I'm ready" — hands straight over to the sleep confirmation.
    var onReady: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startedAt = Date()

    /// One full breath. 4s in, 2s hold, 6s out — a long exhale is the part that
    /// actually settles someone, so it gets half the cycle.
    private static let inhale: Double = 4
    private static let hold: Double = 2
    private static let exhale: Double = 6
    private static var cycle: Double { inhale + hold + exhale }

    private static let totalSeconds: Double = 120

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: false)) { timeline in
            let elapsed = timeline.date.timeIntervalSince(startedAt)
            let remaining = max(0, Self.totalSeconds - elapsed)
            let breath = Self.breath(at: elapsed)

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: SleepSpacing.sm) {
                    Text(remaining > 0 ? "Wind down" : "That's two minutes")
                        .sectionLabel()
                    Text(remaining > 0 ? breath.label : "No rush")
                        .font(SleepFont.title(22))
                        .foregroundStyle(SleepColor.ink)
                        .contentTransition(.opacity)
                        .animation(.easeInOut(duration: 0.4), value: breath.label)
                }

                Spacer()

                breathingCircle(scale: reduceMotion ? 0.85 : breath.scale)

                Spacer()

                // The countdown is deliberately quiet and never a progress bar:
                // a filling bar turns settling down into a task with a finish
                // line, which is the opposite of the point.
                Text(remaining > 0 ? Self.clock(remaining) : " ")
                    .font(SleepFont.body(14))
                    .foregroundStyle(SleepColor.faint)
                    .monospacedDigit()

                Spacer()

                VStack(spacing: SleepSpacing.md) {
                    LiquidPrimaryButton(title: "I'm ready", systemImage: "moon.fill") {
                        onReady()
                    }
                    Button(remaining > 0 ? "Stop" : "Not yet") {
                        Haptics.heavy()
                        onDone()
                    }
                    .font(SleepFont.body(15))
                    .foregroundStyle(SleepColor.muted)
                    .frame(maxWidth: .infinity, minHeight: 44)
                }

                Spacer().frame(height: SleepSpacing.xl)
            }
            .padding(.horizontal, SleepSpacing.xxl)
            .safeAreaPadding(.top)
            .safeAreaPadding(.bottom)
        }
        .onAppear { startedAt = Date() }
    }

    /// The breathing mark: concentric amber rings that swell and settle. Not
    /// Liquid Glass — glass is reserved for controls the user can press, and
    /// this is the one thing on screen that is purely something to look at.
    private func breathingCircle(scale: Double) -> some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [SleepColor.amber.opacity(0.22), SleepColor.amber.opacity(0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 150
                    )
                )
                .frame(width: 300, height: 300)
                .scaleEffect(scale)

            Circle()
                .stroke(SleepColor.amber.opacity(0.5), lineWidth: 1.5)
                .frame(width: 180, height: 180)
                .scaleEffect(scale)

            Circle()
                .fill(SleepColor.gold.opacity(0.16))
                .frame(width: 120, height: 120)
                .scaleEffect(scale)
        }
        .frame(height: 300)
    }

    /// Where in the breath cycle `elapsed` falls: the scale to draw and the
    /// instruction to show. Derived from elapsed time rather than a repeating
    /// SwiftUI animation so the ring and its label can never drift apart.
    private static func breath(at elapsed: Double) -> (scale: Double, label: String) {
        let t = elapsed.truncatingRemainder(dividingBy: cycle)
        let small = 0.62, large = 1.0
        if t < inhale {
            return (small + (large - small) * smooth(t / inhale), "Breathe in")
        }
        if t < inhale + hold {
            return (large, "Hold")
        }
        let out = (t - inhale - hold) / exhale
        return (large - (large - small) * smooth(out), "Breathe out")
    }

    /// Smoothstep — eases both ends of the breath so it never snaps.
    private static func smooth(_ x: Double) -> Double {
        let t = min(max(x, 0), 1)
        return t * t * (3 - 2 * t)
    }

    private static func clock(_ seconds: Double) -> String {
        let total = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
