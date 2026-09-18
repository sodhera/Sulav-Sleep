import SwiftUI
import AVKit
import UIKit

// The onboarding instruments.
//
// Each one exists to turn something the user *told* us into something they
// can *see*. That is the whole conversion argument of the sign-up flow: not
// copy, but arithmetic the user can retrace. Nothing here measures anything —
// every figure is a unit conversion of an answer (`SleepDebt`), and every
// reveal captions itself with the answer it came from, because a number
// someone can't retrace is a number they can dismiss.
//
// Three reveals, in escalating order: a verdict the user can't argue with
// (`SleepNeedBand`, sourced to the AASM), a cost they can feel
// (`YearOfNightsGrid`), and a remedy that is theirs to choose (`NightGoalStep`).

// MARK: - Slider

/// The flow's single input grammar for "how much": a live hero number, a
/// track, and an optional social anchor pip so the answer lands somewhere.
///
/// Hand-built rather than SwiftUI's `Slider` — the amber fill, the anchor
/// pip, the numeric-text roll, and one haptic tick per step are all
/// unreachable through the stock control, and the tick is most of what makes
/// the answer feel deliberate rather than dragged.
struct NightSlider: View {
    @Binding var value: Int
    /// Whether the user has actually moved this. A slider that ships with a
    /// plausible default otherwise accepts a default as an answer.
    @Binding var touched: Bool

    let range: ClosedRange<Int>
    var step: Int = 5
    /// Where a typical answer sits, if the question has one worth showing.
    var anchor: Int?
    var anchorLabel = "This is the average"
    var lowLabel: String
    var highLabel: String
    var caption: String?
    /// Renders the hero number. Kept as a closure so the same control serves
    /// minutes ("45") and durations ("6h 45m").
    let format: (Int) -> String
    var unit: String?

    private let knob: CGFloat = 28
    private let trackHeight: CGFloat = 5

    private var fraction: Double {
        let span = Double(range.upperBound - range.lowerBound)
        guard span > 0 else { return 0 }
        return (Double(value) - Double(range.lowerBound)) / span
    }

    private func fraction(of raw: Int) -> Double {
        let span = Double(range.upperBound - range.lowerBound)
        guard span > 0 else { return 0 }
        return (Double(raw) - Double(range.lowerBound)) / span
    }

    var body: some View {
        VStack(spacing: SleepSpacing.xxxl) {
            VStack(spacing: 2) {
                Text(format(value))
                    .font(SleepFont.hero(52))
                    .foregroundStyle(SleepColor.ink)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.18), value: value)
                if let unit {
                    Text(unit)
                        .font(SleepFont.body(15))
                        .foregroundStyle(SleepColor.dim)
                }
            }

            // The rail and its end labels sit on a glass stage rather than
            // bare over the scene. This is the same reasoning as the auth
            // form's field surfaces (DESIGN.md, "Onboarding & auth"): the
            // control lands on the busiest band of the skyline, where a
            // 5pt rail and 13pt grey labels all but disappear. Glass is for
            // controls, and a slider is a control.
            VStack(spacing: SleepSpacing.md) {
                track
                HStack {
                    Text(lowLabel)
                    Spacer()
                    Text(highLabel)
                }
                .font(SleepFont.body(13))
                .foregroundStyle(SleepColor.dim)
            }
            .padding(.horizontal, SleepSpacing.lg)
            .padding(.vertical, SleepSpacing.lg)
            .liquidGlass(cornerRadius: SleepRadius.lg)

            if let caption {
                Text(caption)
                    .font(SleepFont.body(14))
                    .italic()
                    .foregroundStyle(SleepColor.dim)
                    .shadow(color: SleepColor.navy.opacity(0.9), radius: 3)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(lowLabel.isEmpty ? "Amount" : "\(lowLabel) to \(highLabel)")
        .accessibilityValue(format(value))
        .accessibilityAdjustableAction { direction in
            touched = true
            switch direction {
            case .increment: set(value + step)
            case .decrement: set(value - step)
            @unknown default: break
            }
        }
    }

    private var track: some View {
        GeometryReader { geo in
            let travel = max(1, geo.size.width - knob)
            ZStack(alignment: .leading) {
                // The anchor pip rides above the rail so it never competes
                // with the knob for the same pixels.
                if let anchor, range.contains(anchor) {
                    anchorPip(travel: travel, anchor: anchor)
                }

                Capsule()
                    .fill(SleepColor.ink.opacity(0.12))
                    .frame(height: trackHeight)
                    .padding(.horizontal, knob / 2)

                Capsule()
                    .fill(LinearGradient(
                        colors: [SleepColor.gold, SleepColor.amber],
                        startPoint: .leading, endPoint: .trailing
                    ))
                    .frame(width: max(trackHeight, travel * fraction + knob / 2), height: trackHeight)
                    .padding(.leading, knob / 2)

                Circle()
                    .fill(SleepColor.ink)
                    .frame(width: knob, height: knob)
                    .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
                    .offset(x: travel * fraction)
            }
            .frame(height: 44)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        touched = true
                        let x = min(max(0, drag.location.x - knob / 2), travel)
                        let span = Double(range.upperBound - range.lowerBound)
                        set(range.lowerBound + Int((x / travel * span).rounded()))
                    }
            )
        }
        .frame(height: 44)
    }

    /// The social anchor. Deliberately **not** `danger`: in this palette red
    /// means a destructive action, and colouring "what's typical" as an alarm
    /// turns a reference mark into a judgement — which is the shaming
    /// DESIGN.md rules out. Gold is the palette's highlight, and the navy
    /// bubble gives it contrast without borrowing urgency it hasn't earned.
    private func anchorPip(travel: CGFloat, anchor: Int) -> some View {
        VStack(spacing: 5) {
            Text(anchorLabel)
                .font(SleepFont.label(10))
                .foregroundStyle(SleepColor.gold)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(SleepColor.navy, in: Capsule())
                .overlay(Capsule().stroke(SleepColor.gold.opacity(0.35), lineWidth: 1))
                .fixedSize()
            Circle()
                .fill(SleepColor.gold)
                .frame(width: 5, height: 5)
        }
        .offset(x: travel * fraction(of: anchor) + knob / 2, y: -34)
        // The bubble is centred on its pip, so it must not push layout.
        .frame(width: 0, alignment: .center)
        .accessibilityHidden(true)
    }

    /// Snaps to the step grid and ticks only when the value genuinely moves,
    /// so a slow drag across one step doesn't machine-gun the haptics.
    private func set(_ raw: Int) {
        let snapped = (Int((Double(raw) / Double(step)).rounded()) * step)
            .clamped(to: range)
        guard snapped != value else { return }
        value = snapped
        Haptics.soft()
    }
}

private extension Int {
    /// `Swift.`-qualified: inside an `Int` extension, bare `min`/`max`
    /// resolve to `Int.min`/`Int.max`, not the free functions.
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - The verdict

/// The recommended-sleep band with the user's own figure plotted against it.
///
/// This step exists so the app never has to be the one calling the user's
/// nights inadequate — the AASM band delivers the verdict and the app just
/// draws it. That matters: DESIGN.md forbids shaming, and a sourced
/// horizontal band is a mirror where "you don't sleep enough" is a scolding.
/// Copy stays adjective-free for the same reason.
struct SleepNeedBand: View {
    let sleepMinutes: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bandLit = false
    @State private var markerIn = false

    /// The axis. Wider than the recommended band on both sides so the user's
    /// marker has somewhere honest to land in either direction.
    private let axis = (4 * 60)...(10 * 60)

    private func fraction(_ minutes: Int) -> Double {
        let span = Double(axis.upperBound - axis.lowerBound)
        let clamped = min(max(minutes, axis.lowerBound), axis.upperBound)
        return (Double(clamped) - Double(axis.lowerBound)) / span
    }

    private var isEnough: Bool { sleepMinutes >= SleepDebt.target }

    var body: some View {
        VStack(alignment: .leading, spacing: SleepSpacing.xxxl) {
            GeometryReader { geo in
                let width = geo.size.width
                let lo = fraction(SleepDebt.recommendedRange.lowerBound)
                let hi = fraction(SleepDebt.recommendedRange.upperBound)

                ZStack(alignment: .topLeading) {
                    Capsule()
                        .fill(SleepColor.ink.opacity(0.10))
                        .frame(height: 14)
                        .offset(y: 30)

                    Capsule()
                        .fill(LinearGradient(
                            colors: [SleepColor.gold, SleepColor.amber],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .frame(width: bandLit ? width * (hi - lo) : 0, height: 14)
                        .offset(x: width * lo, y: 30)

                    Text("7–9 HOURS")
                        .font(SleepFont.label(11))
                        .tracking(1.4)
                        .foregroundStyle(SleepColor.gold)
                        .opacity(bandLit ? 1 : 0)
                        .frame(width: width * (hi - lo), alignment: .center)
                        .offset(x: width * lo, y: 8)

                    // The user's own figure, dropped in last.
                    marker(width: width)
                }
            }
            .frame(height: 118)

            // The citation is the whole reason this screen isn't the app
            // passing judgement, so it has to survive the skyline. Same
            // navy-shadow treatment DESIGN.md gives section kickers.
            Text("American Academy of Sleep Medicine")
                .font(SleepFont.body(12))
                .foregroundStyle(SleepColor.dim)
                .shadow(color: SleepColor.navy.opacity(0.9), radius: 3)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Recommended sleep for adults is 7 to 9 hours")
        .accessibilityValue("You get about \(SleepFormatting.duration(sleepMinutes))")
        .task {
            if reduceMotion {
                bandLit = true; markerIn = true
                return
            }
            withAnimation(.easeOut(duration: 0.55)) { bandLit = true }
            try? await Task.sleep(for: .milliseconds(620))
            Haptics.rigid()
            withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) { markerIn = true }
        }
    }

    /// Always amber, never `danger` — **position carries the verdict.** A red
    /// marker under the band would be the app editorialising about the user's
    /// nights, and the whole point of sourcing the band to the AASM is that
    /// the app doesn't have to. Landing outside the lit range says it.
    private func marker(width: CGFloat) -> some View {
        let tint = isEnough ? SleepColor.gold : SleepColor.amber
        return VStack(spacing: 4) {
            Capsule()
                .fill(tint)
                .frame(width: 3, height: 26)
            Text(SleepFormatting.duration(sleepMinutes))
                .font(SleepFont.label(14))
                .foregroundStyle(tint)
                .fixedSize()
        }
        .frame(width: 0, alignment: .center)
        .offset(x: width * fraction(sleepMinutes), y: 36)
        .opacity(markerIn ? 1 : 0)
        .scaleEffect(markerIn ? 1 : 0.7, anchor: .top)
    }
}

// MARK: - The cost

/// A year of nights as 365 cells, with the ones the user spends in bed and
/// awake on their phone lit amber.
///
/// Why phone-nights and not a sleep shortfall: the shortfall depends on where
/// you put the recommendation's floor and collapses to zero for anyone
/// already sleeping seven hours, which would leave the flow's centrepiece
/// empty for exactly the users most likely to pay for a habit tool. Time in
/// bed awake on a phone is the user's own answer divided by a night — it
/// holds for everyone, and it is the one number the product actually takes
/// back. `SleepDebt.phoneNightsPerYear` is that conversion.
///
/// The reveal is choreographed to a fixed duration and a fixed tick count
/// rather than a fixed per-cell interval, so thirteen nights and two hundred
/// nights feel like the same instrument reporting different numbers.
struct YearOfNightsGrid: View {
    let phoneMinutes: Int
    /// Set once the count has landed; the caller gates Continue on it.
    @Binding var ready: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = 0

    // Wide and shallow, not square. A 20x19 field ran nearly half the
    // screen and its lower rows sank into the skyline, which destroyed the
    // only thing the graphic has to say — the *ratio* of lit to unlit. The
    // whole 365 has to be legible as one quantity in one glance.
    private static let columns = 25
    private static let rows = 15
    private static let gap: CGFloat = 2.5

    private var total: Int { SleepDebt.nightsPerYear }
    private var lit: Int { min(total, SleepDebt.phoneNightsPerYear(phone: phoneMinutes)) }

    var body: some View {
        VStack(alignment: .leading, spacing: SleepSpacing.xxl) {
            Text("THE NEXT 365 NIGHTS")
                .font(SleepFont.label(11))
                .tracking(1.6)
                .foregroundStyle(SleepColor.dim)
                .shadow(color: SleepColor.navy.opacity(0.8), radius: 2)

            grid

            VStack(alignment: .leading, spacing: SleepSpacing.sm) {
                // An HStack rather than `Text + Text`: the count needs
                // `contentTransition`, which returns a view and can't be
                // concatenated. Baseline alignment keeps the unit sitting on
                // the number's feet as the digits roll and the width changes.
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(revealed)")
                        .font(SleepFont.hero(46))
                        .contentTransition(.numericText())
                    Text(revealed == 1 ? "night" : "nights")
                        .font(SleepFont.title(22))
                }
                .foregroundStyle(SleepColor.amber)

                Text("in bed, awake, on your phone.")
                    .font(SleepFont.title(20))
                    .foregroundStyle(SleepColor.ink)
                    .shadow(color: SleepColor.navy.opacity(0.9), radius: 4)

                // The provenance line is what keeps this figure honest, so
                // it has to be readable over the warm windows it lands on.
                Text("At the \(phoneMinutes) minutes a night you told us.")
                    .font(SleepFont.body(13))
                    .foregroundStyle(SleepColor.dim)
                    .shadow(color: SleepColor.navy.opacity(0.9), radius: 3)
                    .opacity(ready ? 1 : 0)
                    .animation(.easeIn(duration: 0.35), value: ready)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("The next 365 nights")
        .accessibilityValue(
            "\(lit) nights spent in bed, awake, on your phone, at the \(phoneMinutes) minutes a night you told us"
        )
        .task(id: lit) {
            revealed = 0
            ready = false
            guard !reduceMotion else {
                revealed = lit
                ready = true
                return
            }
            do {
                try await Task.sleep(for: .milliseconds(420))
                // One fixed budget and ~14 ticks whatever the count, so the
                // instrument feels identical across answers.
                let budget = 1_700.0
                let interval = max(6.0, min(55.0, budget / Double(max(1, lit))))
                let tickEvery = max(1, lit / 14)
                for index in 1...max(1, lit) {
                    try Task.checkCancellation()
                    revealed = index
                    if index % tickEvery == 0 { Haptics.soft() }
                    try await Task.sleep(for: .milliseconds(Int(interval)))
                }
                revealed = lit
                Haptics.rigid()
                ready = true
            } catch { /* Navigating away cancels the count. */ }
        }
    }

    /// Drawn in a `Canvas`: 365 discrete views would re-lay-out the whole
    /// field on every step of the reveal, and this is one colour change per
    /// frame over a live scene.
    private var grid: some View {
        Canvas { context, size in
            let pitch = size.width / CGFloat(Self.columns)
            let side = max(1, pitch - Self.gap)
            for index in 0..<total {
                let row = index / Self.columns
                let column = index % Self.columns
                let rect = CGRect(
                    x: CGFloat(column) * pitch,
                    y: CGFloat(row) * pitch,
                    width: side, height: side
                )
                context.fill(
                    Path(roundedRect: rect, cornerRadius: 1.5),
                    // Unlit cells need real presence: at 10% over the lit
                    // windows of the skyline they disappeared, and a field
                    // whose denominator is invisible has no ratio to read.
                    with: .color(index < revealed ? SleepColor.amber : SleepColor.ink.opacity(0.18))
                )
            }
        }
        .aspectRatio(CGFloat(Self.columns) / CGFloat(Self.rows), contentMode: .fit)
        .frame(maxWidth: .infinity)
        .drawingGroup()
        // The field is one object, so it gets one stage. Glass supplies an
        // even ground under all 365 cells — without it the grid's lower rows
        // read against warm windows and the top rows against open sky, and
        // the same colour looks like two different values.
        .padding(SleepSpacing.md)
        .liquidGlass(cornerRadius: SleepRadius.md)
    }
}

// MARK: - Narrative

/// Text reveals are cancellable and read as complete sentences to VoiceOver.
struct NarrativePage: View {
    let lines: [String]
    @Binding var ready: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var visible = 0

    private var count: Int { lines.reduce(0) { $0 + $1.count } }
    var body: some View {
        narrativeLines
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: lines) {
            visible = 0
            ready = false
            if reduceMotion || voiceOver { visible = count; ready = true; return }
            do {
                let boundaries = lines.indices.map { lines.prefix($0 + 1).reduce(0) { $0 + $1.count } }
                try await Task.sleep(for: .milliseconds(450))
                for index in 1...max(1, count) {
                    try Task.checkCancellation()
                    visible = index
                    if index % 4 == 0 { Haptics.soft() }
                    try await Task.sleep(for: .milliseconds(boundaries.contains(index) ? 650 : 38))
                }
                ready = true
            } catch { /* Navigation cancels the reveal. */ }
        }
    }

    /// Both halves participate in layout, so a word never jumps to a new line
    /// when its final character arrives. Only its ink changes during reveal.
    private var narrativeLines: some View {
        VStack(alignment: .leading, spacing: 22) {
            ForEach(lines.indices, id: \.self) { index in
                let start = lines.prefix(index).reduce(0) { $0 + $1.count }
                let shown = max(0, min(lines[index].count, visible - start))
                let line = lines[index]
                let color = index.isMultiple(of: 2) ? SleepColor.ink : SleepColor.gold
                RevealingSentence(line: line, shown: shown, color: UIColor(color), fontSize: lines.count == 1 ? 28 : 23)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(line)
            }
        }
        .padding(.vertical, 20)
    }
}

/// UILabel measures the complete sentence before painting the visible prefix.
/// That keeps word wrapping fixed while the typewriter reveals each character.
private struct RevealingSentence: UIViewRepresentable {
    let line: String
    let shown: Int
    let color: UIColor
    let fontSize: CGFloat

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.backgroundColor = .clear
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        configure(label)
        return label
    }

    func updateUIView(_ label: UILabel, context: Context) { configure(label) }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView label: UILabel, context: Context) -> CGSize? {
        let width = proposal.width ?? 320
        label.preferredMaxLayoutWidth = width
        let height = label.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        return CGSize(width: width, height: height)
    }

    private func configure(_ label: UILabel) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        paragraph.lineBreakMode = .byWordWrapping
        let text = NSMutableAttributedString(string: line, attributes: [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .medium),
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ])
        let prefixLength = String(line.prefix(shown)).utf16.count
        let remaining = (line as NSString).length - prefixLength
        if remaining > 0 {
            text.addAttribute(.foregroundColor, value: UIColor.clear,
                              range: NSRange(location: prefixLength, length: remaining))
        }
        label.attributedText = text
    }
}

// MARK: - The remedy

/// The narrative that names the phone as the cause, resolving into the goal
/// question on the same step.
///
/// One step rather than two on purpose: the argument and the choice belong to
/// the same beat, and a separate goal screen re-asks for attention the story
/// has already won. The story never diagnoses and never claims the phone
/// *causes* anything clinical — it says sleep can't start while the screen is
/// on, which is the honest mechanism and the one the product acts on.
struct NightGoalStep: View {
    let phoneNights: Int
    @Binding var goal: SleepGoal?
    @Binding var showingOptions: Bool

    @State private var chapter = 0
    @State private var ready = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var pages: [[String]] {
        [
            ["Your body already knows how to fall asleep.",
             "It has done it every night of your life."],
            ["It just can't start while the screen is still on.",
             "Those \(phoneNights) nights aren't gone. They're on loan."]
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if showingOptions {
                Text("What would you fix first?")
                    .font(SleepFont.title(28))
                    .foregroundStyle(SleepColor.ink)
                Spacer(minLength: 10)
                ScrollView {
                    LiquidGlassContainer(spacing: SleepSpacing.md) {
                        VStack(spacing: SleepSpacing.md) {
                            ForEach(SleepGoal.allCases) { option in
                                OptionRow(
                                    icon: option.systemImage,
                                    title: option.title,
                                    isSelected: goal == option
                                ) {
                                    Haptics.heavy()
                                    goal = option
                                }
                            }
                        }
                    }
                    .padding(.vertical, 3)
                }
                .scrollIndicators(.hidden)
                Spacer(minLength: 10)
            } else {
                NarrativePage(lines: pages[chapter], ready: $ready)
                    .id(chapter)
                    .transition(.opacity)
                StoryUnlockSlider {
                    if chapter == pages.count - 1 {
                        showingOptions = true
                    } else {
                        ready = false
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.4)) { chapter += 1 }
                    }
                }
                .id(chapter)
                .disabled(!ready)
                .opacity(ready ? 1 : 0)
                .padding(.bottom, 16)
            }
        }
    }
}

// MARK: - Commitment gestures

struct StoryUnlockSlider: View {
    let action: () -> Void
    @State private var offset: CGFloat = 0
    @State private var completed = false
    var body: some View {
        GeometryReader { geo in
            let travel = max(1, geo.size.width - 66)
            ZStack(alignment: .leading) {
                Capsule().fill(SleepColor.navy.opacity(0.88))
                Capsule().stroke(SleepColor.amber.opacity(0.4), lineWidth: 1)
                Text("Continue")
                    .font(SleepFont.body(18)).foregroundStyle(SleepColor.ink)
                    .frame(maxWidth: .infinity).opacity(1 - Double(offset / travel))
                Image(systemName: "arrow.right")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(SleepColor.background)
                    .frame(width: 56, height: 50)
                    .background(SleepColor.gold, in: Capsule())
                    .offset(x: 5 + offset)
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard !completed else { return }
                            offset = min(travel, max(0, value.translation.width))
                        }
                        .onEnded { _ in
                            guard !completed else { return }
                            if offset >= travel * 0.85 {
                                completed = true; Haptics.success(); action()
                            } else { withAnimation(.spring()) { offset = 0 } }
                        })
            }
        }.frame(height: 60)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Slide to continue")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { guard !completed else { return }; completed = true; action() }
    }
}

struct CommitmentHoldButton: View {
    let action: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var progress = 0.0
    @State private var task: Task<Void, Never>?
    @State private var complete = false
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(SleepColor.navy)
                Capsule().fill(SleepColor.gold.opacity(0.8)).frame(width: geo.size.width * progress)
                Capsule().stroke(SleepColor.gold.opacity(0.5), lineWidth: 1)
                Label(complete ? "Committed" : "Hold to commit", systemImage: "hand.raised.fill")
                    .font(SleepFont.label(18))
                    .foregroundStyle(progress > 0.55 ? SleepColor.background : SleepColor.ink)
                    .frame(maxWidth: .infinity)
            }.contentShape(Capsule())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if abs(value.translation.width) > 45 || abs(value.translation.height) > 45 { cancel(); return }
                    start()
                }.onEnded { _ in cancel() })
        }.frame(height: 60)
        .onDisappear { cancel() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { cancel() } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hold to commit")
        .accessibilityHint("Hold for two seconds to commit to your nights")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Commit") { guard !complete else { return }; complete = true; action() }
    }
    private func start() {
        guard task == nil, !complete else { return }
        Haptics.soft()
        task = Task { @MainActor in
            do {
                for tick in 1...40 {
                    try await Task.sleep(for: .milliseconds(50))
                    progress = Double(tick) / 40
                    if tick % 10 == 0 { Haptics.tick(intensity: 0.4 + 0.6 * progress) }
                }
                complete = true; Haptics.doubleHeavy(); action()
            } catch { }
        }
    }
    private func cancel() {
        task?.cancel(); task = nil
        if !complete { withAnimation(.easeOut(duration: 0.18)) { progress = 0 } }
    }
}

// MARK: - The demo

struct BlockingPreviewStep: View {
    let inBedClock: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("This is what \(inBedClock) looks like now.")
                .font(SleepFont.title(28)).foregroundStyle(SleepColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            GeometryReader { geo in
                let height = min(geo.size.height, 490.0)
                BlockingDemoPlayback()
                    .frame(width: height * 0.47, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: height * 0.065))
                    .padding(5)
                    .background(.black, in: RoundedRectangle(cornerRadius: height * 0.075))
                    .overlay(RoundedRectangle(cornerRadius: height * 0.075).stroke(.white.opacity(0.3), lineWidth: 1))
                    .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.padding(.bottom, 18)
    }
}

/// An explicit recreation, never presented as proof of granted Screen Time
/// permissions. Fixed iPhone coordinates keep the status bar, app launch, and
/// shield readable at card scale.
struct IPhoneBlockingDemo: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var stage = 0
    @State private var grayscaleAmount = 0.0
    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(colors: [Color(hex: 0x122843), Color(hex: 0x56798A), Color(hex: 0x121E37)], startPoint: .topLeading, endPoint: .bottomTrailing)
                if stage < 2 { home }
                if stage == 2 {
                    Color.black
                    VStack(spacing: 24) { tiktokMark.font(.system(size: 90, weight: .bold)); Text("TikTok").font(.system(size: 34, weight: .bold)) }
                        .foregroundStyle(.white)
                        .saturation(1 - grayscaleAmount)
                }
                if stage >= 3 { shield.transition(.opacity) }
                VStack {
                    HStack {
                        Text("9:41").font(.system(size: 15, weight: .semibold))
                        Spacer()
                        Image(systemName: "cellularbars")
                        Image(systemName: "wifi")
                        Image(systemName: "battery.100percent")
                    }.font(.system(size: 13)).padding(.horizontal, 26).padding(.top, 18)
                    Spacer()
                    Capsule().fill(.white).frame(width: 130, height: 5).padding(.bottom, 9)
                }.foregroundStyle(.white)
                Capsule().fill(.black).frame(width: 115, height: 32).frame(maxHeight: .infinity, alignment: .top).padding(.top, 10)
            }
            .frame(width: 393, height: 852)
            .scaleEffect(geo.size.width / 393, anchor: .topLeading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Illustrative iPhone demo: TikTok is tapped, opens, then SleepBlock displays the bedtime shield.")
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            if reduceMotion { stage = 3; return }
            do {
                while !Task.isCancelled {
                    stage = 0; try await Task.sleep(for: .milliseconds(1600))
                    stage = 1; try await Task.sleep(for: .milliseconds(450))
                    grayscaleAmount = 0
                    stage = 2
                    withAnimation(.linear(duration: 1.4)) { grayscaleAmount = 1 }
                    try await Task.sleep(for: .milliseconds(1400))
                    withAnimation(.easeOut(duration: 0.2)) { stage = 3 }
                    try await Task.sleep(for: .milliseconds(3200))
                }
            } catch { }
        }
    }
    private var tiktokMark: some View {
        Text("♪").foregroundStyle(.white)
            .shadow(color: .cyan, radius: 0, x: -3, y: -1)
            .shadow(color: .pink, radius: 0, x: 3, y: 2)
    }
    private var home: some View {
        VStack(spacing: 28) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 9) {
                    Text("MONDAY").font(.system(size: 13, weight: .medium)).foregroundStyle(.red)
                    Text("17").font(.system(size: 48, weight: .light))
                    Text("A quieter night").font(.system(size: 13))
                }.foregroundStyle(.black).frame(width: 140, height: 135).background(.white.opacity(0.93), in: RoundedRectangle(cornerRadius: 22))
                VStack(alignment: .leading, spacing: 9) {
                    Image(systemName: "moon.stars.fill").font(.system(size: 25))
                    Text("18°").font(.system(size: 42, weight: .light))
                    Text("Clear tonight").font(.system(size: 13))
                }.foregroundStyle(.white).frame(width: 140, height: 135).background(Color(hex: 0x243E62), in: RoundedRectangle(cornerRadius: 22))
            }.padding(.top, 100)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(70), spacing: 15), count: 4), spacing: 25) {
                appIcon("FaceTime", symbol: "video.fill", color: .green)
                appIcon("Photos", symbol: "camera.macro", color: .pink)
                appIcon("Camera", symbol: "camera.fill", color: .gray)
                appIcon("Mail", symbol: "envelope.fill", color: .blue)
                appIcon("Clock", symbol: "clock.fill", color: .black)
                appIcon("Maps", symbol: "map.fill", color: .green)
                appIcon("Notes", symbol: "note.text", color: .yellow)
                appIcon("Settings", symbol: "gear", color: .gray)
                VStack(spacing: 7) {
                    tiktokMark.font(.system(size: 43, weight: .bold))
                        .frame(width: 62, height: 62).background(.black, in: RoundedRectangle(cornerRadius: 15))
                        .scaleEffect(stage == 1 ? 0.88 : 1)
                        .overlay {
                            if stage == 1 { Circle().fill(.white.opacity(0.3)).frame(width: 42, height: 42).overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 2)).offset(x: 10, y: 13) }
                        }
                    Text("TikTok").font(.system(size: 12)).foregroundStyle(.white)
                }
                appIcon("Podcasts", symbol: "mic.fill", color: .purple)
                appIcon("Books", symbol: "book.fill", color: .orange)
                appIcon("SleepBlock", symbol: "moon.zzz.fill", color: Color(hex: 0x172334))
            }
            Spacer()
            HStack(spacing: 6) { Circle().fill(.white); Circle().fill(.white.opacity(0.4)) }.frame(width: 18, height: 5)
            HStack(spacing: 24) {
                dockIcon("phone.fill", color: .green); dockIcon("safari", color: .blue)
                dockIcon("message.fill", color: .green); dockIcon("music.note", color: .pink)
            }.padding(16).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30)).padding(.bottom, 30)
        }
    }
    private func appIcon(_ name: String, symbol: String, color: Color) -> some View {
        VStack(spacing: 7) { dockIcon(symbol, color: color); Text(name).font(.system(size: 12)).foregroundStyle(.white) }
    }
    private func dockIcon(_ symbol: String, color: Color) -> some View {
        Image(systemName: symbol).font(.system(size: 29)).foregroundStyle(.white)
            .frame(width: 62, height: 62).background(color.gradient, in: RoundedRectangle(cornerRadius: 15))
    }
    private var shield: some View {
        ZStack {
            SleepColor.background
            VStack(spacing: 23) {
                Image("HomeSlothNightBlink").resizable().scaledToFit().frame(width: 160, height: 96)
                Text("SleepBlock").font(.system(size: 17, weight: .medium)).foregroundStyle(SleepColor.gold)
                Text("Your night is protected.").font(.system(size: 27, weight: .semibold)).multilineTextAlignment(.center)
                Text("TikTok can wait until morning.\nThis time belongs to you.")
                    .font(.system(size: 17)).foregroundStyle(SleepColor.dim).multilineTextAlignment(.center).lineSpacing(5)
                Text("Back to sleep").font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(SleepColor.background).frame(width: 280, height: 52).background(SleepColor.amber, in: Capsule()).padding(.top, 12)
                Text("I need a moment").font(.system(size: 14)).foregroundStyle(SleepColor.dim)
            }.foregroundStyle(SleepColor.ink).padding(28)
        }
    }
}

/// Bundled simulator recording, with a live illustration fallback and a static
/// shield for Reduce Motion. Player/looper ownership ends with the page.
private struct BlockingDemoPlayback: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        Group {
            if !reduceMotion, let url = Bundle.main.url(forResource: "attention-demo", withExtension: "mp4") {
                LoopingDemoMovie(url: url, playing: scenePhase == .active)
            } else {
                IPhoneBlockingDemo()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Illustrative iPhone demo: TikTok is tapped, opens, then SleepBlock displays the bedtime shield.")
    }
}

private struct LoopingDemoMovie: UIViewRepresentable {
    let url: URL
    let playing: Bool
    final class Coordinator {
        let player = AVQueuePlayer()
        var looper: AVPlayerLooper?
        init(url: URL) {
            player.isMuted = true
            looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(url: url) }
    func makeUIView(context: Context) -> DemoMovieSurface {
        let view = DemoMovieSurface()
        view.playerLayer.player = context.coordinator.player
        view.playerLayer.videoGravity = .resizeAspectFill
        return view
    }
    func updateUIView(_ view: DemoMovieSurface, context: Context) {
        if playing { context.coordinator.player.play() } else { context.coordinator.player.pause() }
    }
    static func dismantleUIView(_ view: DemoMovieSurface, coordinator: Coordinator) {
        coordinator.player.pause()
        coordinator.looper?.disableLooping()
        coordinator.player.removeAllItems()
    }
}

private final class DemoMovieSurface: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
