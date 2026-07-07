import SwiftUI
import FamilyControls

// Confirmation shown after tapping "Sleep Now" — it takes over the whole Home
// composition. Deliberately near-wordless: a kicker, one hero gold number (the
// sleep you'd get sliding now), a one-line sub anchoring it to the wake time,
// a single compact glass row for the lockdown, and the slide-to-sleep capsule.
// The slide gesture is what makes the commitment deliberate; the screen
// doesn't need paragraphs on top of it.

struct SleepConfirmationPanel: View {
    var store: SleepStore
    let profile: Profile
    let onCancel: () -> Void

    private var selection: FamilyActivitySelection {
        SleepScreenTime.decodeSelection(store.appSelectionData())
    }

    /// Minutes of sleep the user will get if they fall asleep right now and
    /// wake at their configured wake time.
    private var estimatedMinutes: Int {
        let nowMinutes = SleepFormatting.minutes(from: Date())
        return SleepMath.windowMinutes(bedtime: nowMinutes, wakeTime: profile.wakeTime)
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: SleepSpacing.huge)

            // — The one number that matters tonight —
            VStack(spacing: SleepSpacing.sm) {
                Text("Tonight").sectionLabel()
                Text(SleepFormatting.duration(estimatedMinutes))
                    .font(SleepFont.hero(52))
                    .foregroundStyle(SleepColor.gold)
                    .monospacedDigit()
                Text("of sleep · wake \(SleepFormatting.clock(profile.wakeTime))")
                    .font(SleepFont.body(14))
                    .foregroundStyle(SleepColor.muted)
                    .monospacedDigit()
            }

            lockdownRow
                .padding(.top, SleepSpacing.huge)

            Spacer(minLength: SleepSpacing.huge)

            SlideToSleepButton {
                Haptics.soft()
                store.startSleep()
            }

            Button {
                Haptics.soft()
                onCancel()
            } label: {
                Text("Cancel")
                    .font(SleepFont.body(15))
                    .foregroundStyle(SleepColor.muted)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .padding(.top, SleepSpacing.sm)

            Spacer().frame(height: SleepSpacing.xl)
        }
    }

    // MARK: - Lockdown row

    /// One compact glass line: a lock glyph and, when blocking, the app icons
    /// themselves. Icons over words.
    @ViewBuilder
    private var lockdownRow: some View {
        let appTokens = Array(selection.applicationTokens)
        let catTokens = Array(selection.categoryTokens)
        let isBlocking = store.willLockDuringSleep

        HStack(spacing: SleepSpacing.md) {
            Image(systemName: isBlocking ? "lock.fill" : "lock.open")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isBlocking ? SleepColor.amber : SleepColor.muted)

            Text(isBlocking ? "Locked until you wake" : "No apps blocked tonight")
                .font(SleepFont.body(14))
                .foregroundStyle(SleepColor.dim)

            Spacer(minLength: SleepSpacing.md)

            if isBlocking {
                HStack(spacing: SleepSpacing.xs) {
                    ForEach(appTokens.prefix(4), id: \.self) { token in
                        Label(token)
                            .labelStyle(.iconOnly)
                            .font(.system(size: 20))
                            .frame(width: 22, height: 22)
                    }
                    if !catTokens.isEmpty || appTokens.count > 4 {
                        Text("+")
                            .font(SleepFont.label(14))
                            .foregroundStyle(SleepColor.muted)
                    }
                }
            }
        }
        .padding(.horizontal, SleepSpacing.lg)
        .frame(minHeight: 52)
        .liquidGlass(cornerRadius: SleepRadius.lg)
    }
}

// MARK: - Slide to Sleep Button

/// iPhone-style "slide to answer" capsule. The user drags a moon-icon knob
/// from left to right; past ~80% it snaps to completion and fires `onComplete`.
/// On release before the threshold the knob springs back.
struct SlideToSleepButton: View {
    let onComplete: () -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var isCompleted = false
    @GestureState private var isDragging = false
    // Haptic bookkeeping: which ratchet detent last fired, and whether the
    // knob is currently past the completion threshold (so the firm "ready"
    // cue fires once per crossing, not every frame).
    @State private var lastHapticStep = -1
    @State private var isPastThreshold = false

    private let knobSize: CGFloat = 56
    private let trackHeight: CGFloat = 64
    private let trackPadding: CGFloat = 4
    private let completionThreshold: CGFloat = 0.80
    /// Number of detents the knob ratchets through across the full track.
    private let hapticDetents: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            let maxOffset = geo.size.width - knobSize - trackPadding * 2
            let progress = maxOffset > 0 ? min(dragOffset / maxOffset, 1) : 0

            ZStack(alignment: .leading) {
                // Track — a recessed night rail: dark navy with an inner
                // shadow so the knob visibly sits *in* something, and a
                // hairline that warms once the slide is past the threshold.
                Capsule(style: .continuous)
                    .fill(
                        SleepColor.navy.opacity(0.55)
                            .shadow(.inner(color: .black.opacity(0.45), radius: 6, y: 2))
                    )
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(
                                isPastThreshold ? SleepColor.amber.opacity(0.35) : SleepColor.border,
                                lineWidth: 1
                            )
                    }
                    .animation(.easeInOut(duration: 0.25), value: isPastThreshold)

                // Light trail — the knob drags warm light across the rail,
                // brightest right behind it.
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                SleepColor.amber.opacity(0.03),
                                SleepColor.amber.opacity(0.22),
                                SleepColor.gold.opacity(0.34),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: dragOffset + knobSize + trackPadding * 2)
                    .opacity(progress > 0.02 ? 1 : 0)
                    .animation(.easeOut(duration: 0.2), value: progress > 0.02)

                // Hint — shimmering label + breathing chevrons, both fading
                // out as the knob covers ground.
                HStack(spacing: SleepSpacing.sm) {
                    ShimmeringHint(text: "Slide to sleep")
                    BreathingChevrons()
                }
                .frame(maxWidth: .infinity)
                .opacity(isCompleted ? 0 : Double(max(0, 1 - progress * 2.5)))
                .allowsHitTesting(false)

                // Knob
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [SleepColor.gold, SleepColor.amber],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        Circle()
                            .stroke(Color.white.opacity(0.25), lineWidth: 1)
                    }
                    .overlay {
                        Image(systemName: isCompleted ? "moon.zzz.fill" : "moon.fill")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(SleepColor.background)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .overlay {
                        // "Ready" ring — blooms the moment the slide crosses
                        // the completion threshold, alongside the firm haptic.
                        Circle()
                            .stroke(SleepColor.gold.opacity(isPastThreshold ? 0.85 : 0), lineWidth: 2)
                            .scaleEffect(isPastThreshold ? 1.16 : 1.0)
                            .animation(.spring(response: 0.32, dampingFraction: 0.6), value: isPastThreshold)
                    }
                    .frame(width: knobSize, height: knobSize)
                    .scaleEffect(isDragging ? 1.05 : 1)
                    .animation(.snappy(duration: 0.2), value: isDragging)
                    .shadow(
                        color: SleepColor.amber.opacity(0.28 + Double(progress) * 0.3 + (isDragging ? 0.12 : 0)),
                        radius: 10 + Double(progress) * 8,
                        y: 4
                    )
                    .offset(x: trackPadding + dragOffset)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .updating($isDragging) { _, state, _ in
                                state = true
                            }
                            .onChanged { value in
                                guard !isCompleted else { return }
                                let newOffset = min(max(0, value.translation.width), maxOffset)
                                dragOffset = newOffset
                                fireDragHaptics(progress: maxOffset > 0 ? newOffset / maxOffset : 0)
                            }
                            .onEnded { value in
                                guard !isCompleted else { return }
                                let finalOffset = min(max(0, value.translation.width), maxOffset)
                                if finalOffset / maxOffset >= completionThreshold {
                                    // Complete
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        dragOffset = maxOffset
                                    }
                                    isCompleted = true
                                    Haptics.success()
                                    // Small delay so the snap animation is visible
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                        onComplete()
                                    }
                                } else {
                                    // Spring back — a soft tap acknowledges the release.
                                    Haptics.soft()
                                    resetDragHaptics()
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                        dragOffset = 0
                                    }
                                }
                            }
                    )
            }
            .frame(height: trackHeight)
        }
        .frame(height: trackHeight)
    }

    /// Ratchet the knob: a light tick at each detent (rising in strength with
    /// progress) so the slide feels physical, plus one firmer tap the moment
    /// it crosses the completion threshold — the "let go now" cue.
    private func fireDragHaptics(progress: CGFloat) {
        let step = Int(progress * hapticDetents)
        if step != lastHapticStep {
            lastHapticStep = step
            // Skip the tick at rest (step 0, progress ~0) so a stray touch is
            // silent; every detent thereafter ticks a little harder.
            if step > 0 {
                Haptics.tick(intensity: 0.35 + progress * 0.55)
            }
        }

        if progress >= completionThreshold {
            if !isPastThreshold {
                isPastThreshold = true
                Haptics.rigid()
            }
        } else if isPastThreshold {
            isPastThreshold = false
        }
    }

    private func resetDragHaptics() {
        lastHapticStep = -1
        isPastThreshold = false
    }
}

/// The classic slide-to-unlock treatment: a soft band of light sweeps across
/// the hint text, masked to the glyphs, inviting the drag without a single
/// extra word. Slow and dim enough to read as ambient, not attention-seeking.
private struct ShimmeringHint: View {
    let text: String

    @State private var phase: CGFloat = 0

    var body: some View {
        let label = Text(text)
            .font(SleepFont.label(15))
            .tracking(0.4)

        label
            .foregroundStyle(SleepColor.dim)
            .overlay {
                GeometryReader { geo in
                    let band = geo.size.width * 0.45
                    LinearGradient(
                        colors: [.clear, SleepColor.ink.opacity(0.9), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: band)
                    .offset(x: -band + phase * (geo.size.width + band * 2))
                }
                .mask(label)
            }
            .onAppear {
                withAnimation(.linear(duration: 2.6).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

/// Three amber chevrons that breathe in sequence toward the knob's
/// destination — the directional hint, replacing static arrows.
private struct BreathingChevrons: View {
    @State private var breathing = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(SleepColor.amber)
                    .opacity(breathing ? 0.85 : 0.2)
                    .animation(
                        .easeInOut(duration: 0.9)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.18),
                        value: breathing
                    )
            }
        }
        .onAppear { breathing = true }
    }
}
