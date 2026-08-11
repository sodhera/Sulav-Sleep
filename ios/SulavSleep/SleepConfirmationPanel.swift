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

            // Deliberately no wind-down offer here. This screen has exactly one
            // job — the slide — and a second amber control under it split the
            // ask in two. Someone who has already opened the confirmation is
            // past needing to be eased in; the wind-down belongs where people
            // are actually stuck, which is the snooze-expiry notification.
            Button {
                Haptics.heavy()
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
///
/// Visually this is the brightest control in the app on purpose: a tall,
/// near-solid night rail with an amber rim and a resting glow, so it never
/// melts into the pixel skyline behind it. It is the one thing to do on this
/// screen — it gets to look like it.
struct SlideToSleepButton: View {
    let onComplete: () -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var isCompleted = false
    @GestureState private var isDragging = false
    // Haptic bookkeeping: whether the knob has been grabbed this gesture,
    // which ratchet detent last fired, and whether the knob is currently past
    // the completion threshold (so the heavy "ready" knock fires once per
    // crossing, not every frame).
    @State private var isGrabbed = false
    @State private var lastHapticStep = -1
    @State private var isPastThreshold = false

    private let knobSize: CGFloat = 62
    private let trackHeight: CGFloat = 72
    private let trackPadding: CGFloat = 5
    private let completionThreshold: CGFloat = 0.80
    /// Number of detents the knob ratchets through across the full track.
    private let hapticDetents: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let maxOffset = geo.size.width - knobSize - trackPadding * 2
            let progress = maxOffset > 0 ? min(dragOffset / maxOffset, 1) : 0

            ZStack(alignment: .leading) {
                // Track — a near-solid night rail: deep navy with an inner
                // shadow so the knob visibly sits *in* something, rimmed in
                // warm amber that brightens past the threshold, and carrying
                // its own resting glow so it separates from the scene.
                Capsule(style: .continuous)
                    .fill(
                        SleepColor.navy.opacity(0.88)
                            .shadow(.inner(color: .black.opacity(0.55), radius: 7, y: 3))
                    )
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: isPastThreshold
                                        ? [SleepColor.gold.opacity(0.95), SleepColor.amber.opacity(0.6)]
                                        : [SleepColor.amber.opacity(0.5), SleepColor.amber.opacity(0.14)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1.5
                            )
                    }
                    .shadow(color: SleepColor.amber.opacity(isPastThreshold ? 0.4 : 0.2), radius: 20, y: 6)
                    .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
                    .animation(.easeInOut(duration: 0.25), value: isPastThreshold)

                // Light trail — the knob drags warm light across the rail,
                // brightest right behind it.
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                SleepColor.amber.opacity(0.06),
                                SleepColor.amber.opacity(0.35),
                                SleepColor.gold.opacity(0.55),
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

                // Knob — real interactive Liquid Glass on iOS 26 (it deforms
                // and tracks the finger as it drags), the amber→gold gradient
                // disc pre-26.
                knobSurface
                    .overlay {
                        Image(systemName: isCompleted ? "moon.zzz.fill" : "moon.fill")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(SleepColor.background)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .overlay {
                        // "Ready" ring — blooms the moment the slide crosses
                        // the completion threshold, alongside the heavy knock.
                        Circle()
                            .stroke(SleepColor.gold.opacity(isPastThreshold ? 0.9 : 0), lineWidth: 2.5)
                            .scaleEffect(isPastThreshold ? 1.18 : 1.0)
                            .animation(.spring(response: 0.32, dampingFraction: 0.6), value: isPastThreshold)
                    }
                    .frame(width: knobSize, height: knobSize)
                    .scaleEffect(isDragging ? 1.06 : 1)
                    .animation(.snappy(duration: 0.2), value: isDragging)
                    .shadow(
                        color: SleepColor.amber.opacity(0.4 + Double(progress) * 0.35 + (isDragging ? 0.1 : 0)),
                        radius: 12 + Double(progress) * 10,
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
                                if !isGrabbed {
                                    // Grab acknowledgment: the knob answers
                                    // the touch before it moves.
                                    isGrabbed = true
                                    Haptics.rigid()
                                }
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

    /// The knob's base disc: interactive Liquid Glass on iOS 26 (tinted a
    /// bright amber so it stays the screen's brightest control while gaining
    /// the liquid touch response), the amber→gold gradient disc with a white
    /// hairline pre-26.
    @ViewBuilder
    private var knobSurface: some View {
        if #available(iOS 26.0, *) {
            // The circle must be sized *before* `glassEffect`, otherwise the
            // glass computes its geometry on a flexible (full-width) circle
            // and renders as a displaced, bright-rimmed echo behind the knob.
            Circle()
                .fill(SleepColor.amber.opacity(0.55))
                .frame(width: knobSize, height: knobSize)
                .glassEffect(.regular.tint(SleepColor.gold).interactive(), in: .circle)
        } else {
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
                        .stroke(Color.white.opacity(0.35), lineWidth: 1)
                }
        }
    }

    /// Ratchet the knob: a heavy tick at each detent (rising in strength with
    /// progress) so the slide feels forceful through a firm grip, plus a
    /// double heavy knock the moment it crosses the completion threshold —
    /// the unmistakable "let go now" cue.
    private func fireDragHaptics(progress: CGFloat) {
        let step = Int(progress * hapticDetents)
        if step != lastHapticStep {
            lastHapticStep = step
            // Skip the tick at rest (step 0, progress ~0) so resting the
            // thumb is silent; every detent thereafter ticks harder.
            if step > 0 {
                Haptics.tick(intensity: 0.7 + progress * 0.3)
            }
        }

        if progress >= completionThreshold {
            if !isPastThreshold {
                isPastThreshold = true
                Haptics.doubleHeavy()
            }
        } else if isPastThreshold {
            isPastThreshold = false
        }
    }

    private func resetDragHaptics() {
        isGrabbed = false
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
            .font(SleepFont.label(16))
            .tracking(0.5)

        label
            .foregroundStyle(SleepColor.ink.opacity(0.85))
            .overlay {
                GeometryReader { geo in
                    let band = geo.size.width * 0.45
                    LinearGradient(
                        colors: [.clear, SleepColor.gold, .clear],
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
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(SleepColor.gold)
                    .opacity(breathing ? 1.0 : 0.25)
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
