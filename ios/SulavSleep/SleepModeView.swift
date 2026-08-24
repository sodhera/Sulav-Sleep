import SwiftUI

/// Shared height for the sleep screen's two main actions — Hold to wake (the
/// deliberate exit) and Back to sleep (the harmless return). Equal footprint,
/// radically different light.
private let sleepControlHeight: CGFloat = 58

// Immersive sleep mode. True OLED black; everything lit is ember — the day's
// amber banked down to coals (warm, long-wavelength light that is kind to
// night vision and reads as the same identity as the rest of the app). The
// centerpiece is the night sloth — the app icon's sloth in ember tones,
// asleep on its pillow with z's rising off its head — over the elapsed
// timer and the wake target. The sloth is the state ("the app is doing its
// job"); the numbers are the instrument. It opens straight into this
// collapsed screen — the same state "Back to sleep" leaves you in — and an
// explicit "Wake controls" prompt brings the actions up. The dark still
// toggles them for a zero-precision half-asleep hand, but the copy never
// suggests that one tap will end the night.
//
// Control grammar: consequential exits take a deliberate confirmation;
// harmless returns are taps.
// Entering sleep took a deliberate slide, so ending the night takes a
// deliberate hold — but one that needs zero precision from a half-asleep
// hand. "Back to sleep" is a plain tap because it costs nothing. Cancel
// (which drops the lockdown without logging a night) is a quiet text action
// followed by an honest destructive confirmation — deliberate without
// making the user type a shaming sentence.

struct SleepModeView: View {
    var store: SleepStore
    let activeSession: ActiveSleepSession

    @State private var now = Date()
    @State private var showControls: Bool
    @State private var showingCancelConfirmation = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Used only by the deterministic DEBUG route; production always reads
    /// the live profile schedule from the store.
    private let wakeClockOverride: String?

    init(
        store: SleepStore,
        activeSession: ActiveSleepSession,
        initiallyShowsControls: Bool = false,
        wakeClockOverride: String? = nil
    ) {
        self.store = store
        self.activeSession = activeSession
        self.wakeClockOverride = wakeClockOverride
        _showControls = State(initialValue: initiallyShowsControls)
    }

    private var elapsedMinutes: Int {
        max(0, Int(now.timeIntervalSince(activeSession.start) / 60))
    }

    private var wakeClock: String? {
        wakeClockOverride ?? store.profile.map { SleepFormatting.clock($0.wakeTime) }
    }

    var body: some View {
        ZStack {
            // True OLED black — nothing to redraw behind the instrument. Only
            // ember pixels are lit, preserving night vision.
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: showControls ? SleepSpacing.xl : SleepSpacing.huge)

                // The night sloth: the app icon's sloth banked down to
                // ember coals, asleep on its pillow — the sleep state made
                // visible. Its z's rise off the head; the numbers below
                // stay the screen's actual instrument.
                Image("NightSloth")
                    .resizable()
                    .scaledToFit()
                    .frame(width: showControls ? 232 : 292)
                    .overlay(alignment: .topLeading) {
                        RisingZs(scale: showControls ? 0.8 : 1)
                            .offset(
                                x: showControls ? 51 : 64,
                                y: showControls ? 0 : -2
                            )
                    }
                    .accessibilityHidden(true)

                VStack(spacing: SleepSpacing.sm) {
                    Text("Asleep")
                        .font(SleepFont.label(12))
                        .tracking(1.6)
                        .textCase(.uppercase)
                        .foregroundStyle(SleepColor.emberDim)

                    Text("\(elapsedMinutes / 60)h \(String(format: "%02d", elapsedMinutes % 60))m")
                        .font(.system(size: 48, weight: .semibold, design: .default))
                        .foregroundStyle(SleepColor.ember)
                        .monospacedDigit()
                        .shadow(color: SleepColor.emberGlow.opacity(0.45), radius: 14)
                        .contentTransition(.numericText())
                        .accessibilityLabel("Asleep for \(elapsedMinutes / 60) hours \(elapsedMinutes % 60) minutes")

                    if let wakeClock {
                        HStack(spacing: SleepSpacing.xs) {
                            Image(systemName: "sunrise.fill")
                                .font(.system(size: 11, weight: .medium))
                            Text("Wake at \(wakeClock)")
                                .font(SleepFont.body(14))
                                .monospacedDigit()
                        }
                        .foregroundStyle(SleepColor.emberDim)
                    }
                }
                .padding(.top, showControls ? SleepSpacing.md : SleepSpacing.xl)

                Spacer(minLength: showControls ? SleepSpacing.xl : SleepSpacing.huge)

                if showControls {
                    VStack(spacing: SleepSpacing.md) {
                        Text("Wake controls")
                            .font(SleepFont.label(11))
                            .tracking(1.5)
                            .textCase(.uppercase)
                            .foregroundStyle(SleepColor.emberDim.opacity(0.72))

                        EmberHoldButton(
                            title: "Hold to wake",
                            systemImage: "sunrise.fill",
                            prominent: true,
                            duration: 1.2
                        ) {
                            Haptics.success()
                            store.wakeUp()
                        }

                        // A tap, not a hold: returning to sleep costs nothing.
                        // Same footprint as "Hold to wake" right above it —
                        // but plain, cool glass instead of warm ember fill and
                        // glow, so the eye reads "this one is free" at a
                        // glance without needing to read the label. Real
                        // interactive Liquid Glass on iOS 26+ (untinted, so it
                        // stays cool next to the ember-tinted hold above),
                        // via the shared `GlassCapsuleButtonStyle` — the
                        // manual capsule fill + hairline below is the pre-26
                        // fallback only.
                        Group {
                            if #available(iOS 26.0, *) {
                                Button {
                                    Haptics.heavy()
                                    setControls(false)
                                } label: {
                                    backToSleepLabel
                                }
                                .buttonStyle(GlassCapsuleButtonStyle(tint: nil))
                            } else {
                                Button {
                                    Haptics.heavy()
                                    setControls(false)
                                } label: {
                                    backToSleepLabel
                                        .frame(maxWidth: .infinity, minHeight: sleepControlHeight, maxHeight: sleepControlHeight)
                                        .background {
                                            Capsule(style: .continuous)
                                                .fill(Color.white.opacity(0.04))
                                        }
                                        .overlay {
                                            // Neutral hairline, not ember-tinted —
                                            // brighter than the app's usual 5% since
                                            // it sits on pure black rather than navy,
                                            // but still cool glass rather than warm
                                            // ember.
                                            Capsule(style: .continuous)
                                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                                        }
                                        .contentShape(Capsule(style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Button {
                            Haptics.heavy()
                            showingCancelConfirmation = true
                        } label: {
                            Text("Cancel this sleep")
                                .font(SleepFont.body(13))
                                .foregroundStyle(SleepColor.emberDim.opacity(0.72))
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Ends this session without saving after confirmation")
                    }
                    .padding(.horizontal, SleepSpacing.xxl)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else {
                    WakeControlsPrompt {
                        Haptics.soft()
                        setControls(true)
                    }
                        .transition(.opacity)
                }

                Spacer().frame(height: showControls ? SleepSpacing.xl : SleepSpacing.huge)
            }
            .animation(
                reduceMotion ? nil : .spring(response: 0.48, dampingFraction: 0.86),
                value: showControls
            )
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // The dark itself toggles the controls: tap to reveal, tap again
            // to tuck them away. The buttons consume their own touches.
            Haptics.soft()
            setControls(!showControls)
        }
        .task(id: activeSession.start) {
            while !Task.isCancelled {
                now = Date()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .statusBarHidden(true)
        .alert("Cancel this sleep?", isPresented: $showingCancelConfirmation) {
            Button("Keep sleeping", role: .cancel) { Haptics.heavy() }
            Button("Cancel without saving", role: .destructive) {
                Haptics.heavy()
                store.cancelSleep()
            }
        } message: {
            Text("This ends the session without saving the night and turns off app blocking.")
        }
    }

    private func setControls(_ visible: Bool) {
        if reduceMotion {
            showControls = visible
        } else {
            withAnimation(.spring(response: 0.48, dampingFraction: 0.86)) {
                showControls = visible
            }
        }
    }

    /// Shared label for both the iOS 26+ glass and the pre-26 fallback "Back
    /// to sleep" buttons — icon + title in the ember-dim palette.
    private var backToSleepLabel: some View {
        Label {
            Text("Back to sleep").font(SleepFont.label(16))
        } icon: {
            Image(systemName: "moon.fill")
        }
        .foregroundStyle(SleepColor.emberDim)
    }
}

// MARK: - Wake-controls prompt

/// A real, accessible button with the visual volume of a hint. "Tap to wake"
/// used to sound like the tap itself would end the night; this names the panel
/// it reveals while staying dim enough not to become a bedside light source.
private struct WakeControlsPrompt: View {
    let action: () -> Void

    @State private var bright = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: SleepSpacing.sm) {
                Image(systemName: "sunrise.fill")
                    .font(.system(size: 11, weight: .medium))
                Text("Wake controls")
                    .font(SleepFont.body(13))
                Image(systemName: "chevron.up")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(SleepColor.emberDim)
            .frame(minWidth: 170, minHeight: 44)
            .contentShape(Capsule(style: .continuous))
            .opacity(bright ? 0.88 : 0.46)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows actions to wake, keep sleeping, or cancel")
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 2.6).repeatForever(autoreverses: true),
            value: bright
        )
        .onAppear { if !reduceMotion { bright = true } }
    }
}

// MARK: - Hold button

/// Press-and-hold action for the half-asleep hand: zero precision required,
/// impossible to fire with a stray tap. A rigid tap answers the press, a
/// ratchet of heavy ticks climbs while the ember fill sweeps across the
/// capsule, and a double heavy knock lands at completion. Released early,
/// the fill sighs back with a soft tap.
private struct EmberHoldButton: View {
    let title: String
    var systemImage: String?
    let prominent: Bool
    var duration: Double
    let onComplete: () -> Void

    @State private var progress: Double = 0
    @State private var isHolding = false
    @State private var isComplete = false
    @State private var lastTick = -1
    @State private var holdTask: Task<Void, Never>?

    /// Detents the hold ratchets through on its way to completion.
    private let hapticDetents = 5.0

    private var height: CGFloat { prominent ? sleepControlHeight : 44 }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Base — real ember-tinted Liquid Glass on iOS 26+ for the
                // prominent (Hold to wake) capsule; the pre-26 fallback is a
                // hand-drawn capsule with a warm gradient fill.
                if prominent {
                    if #available(iOS 26.0, *) {
                        Capsule(style: .continuous)
                            .fill(.clear)
                            .glassEffect(
                                .regular.tint(SleepColor.ember.opacity(0.35)).interactive(),
                                in: Capsule(style: .continuous)
                            )
                    } else {
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.05))
                            .overlay {
                                Capsule(style: .continuous)
                                    .stroke(SleepColor.emberDim, lineWidth: 1)
                            }

                        // Resting warmth — a banked-coal tint under the progress
                        // fill so the primary hold reads warm even at 0% held.
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [SleepColor.emberDeep.opacity(0.55), SleepColor.emberGlow.opacity(0.22)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    }
                } else {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0))
                }

                // Ember fill sweeping with the hold. Deep tones so the ember
                // label stays readable until the completion flash.
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: isComplete
                                ? [SleepColor.ember, SleepColor.emberGlow]
                                : [SleepColor.emberDeep, SleepColor.emberGlow],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, geo.size.width * progress))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipShape(Capsule(style: .continuous))
                    .opacity(prominent ? 1 : 0.55)

                Label {
                    Text(title).font(SleepFont.label(prominent ? 16 : 15))
                } icon: {
                    if let systemImage { Image(systemName: systemImage) }
                }
                .foregroundStyle(labelColor)
            }
            .shadow(
                color: SleepColor.emberGlow.opacity(prominent ? 0.2 + progress * 0.5 : progress * 0.3),
                radius: 12 + progress * 10,
                y: 4
            )
            .scaleEffect(isHolding ? 0.98 : 1)
            .animation(.snappy(duration: 0.18), value: isHolding)
            .contentShape(Capsule(style: .continuous))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in startHold() }
                    .onEnded { _ in endHold() }
            )
        }
        .frame(height: height)
        .onDisappear { holdTask?.cancel() }
        .accessibilityLabel(title)
        .accessibilityHint("Touch and hold to confirm")
    }

    private var labelColor: Color {
        if isComplete { return SleepColor.sleepBlack }
        return prominent ? SleepColor.ember : SleepColor.emberDim
    }

    private func startHold() {
        guard !isHolding, !isComplete else { return }
        isHolding = true
        lastTick = -1
        Haptics.rigid()
        holdTask = Task { @MainActor in
            let start = Date()
            while !Task.isCancelled {
                let p = min(1, Date().timeIntervalSince(start) / duration)
                progress = p

                let step = Int(p * hapticDetents)
                if step != lastTick {
                    lastTick = step
                    if step > 0 { Haptics.tick(intensity: 0.7 + p * 0.3) }
                }

                if p >= 1 {
                    isComplete = true
                    Haptics.doubleHeavy()
                    onComplete()
                    break
                }
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }

    private func endHold() {
        holdTask?.cancel()
        isHolding = false
        lastTick = -1
        
        if isComplete {
            // The button used to never reset because completing the hold would
            // unmount the view. Now that it triggers an alert, it must reset.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(250))
                isComplete = false
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    progress = 0
                }
            }
        } else {
            if progress > 0.02 { Haptics.soft() }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                progress = 0
            }
        }
    }
}

// MARK: - Preview data

#if DEBUG
extension ActiveSleepSession {
    /// The active night rendered by `-review-sleep-mode`: far enough into a
    /// normal night for the timer to carry real visual weight.
    static var sample: ActiveSleepSession {
        ActiveSleepSession(start: Date().addingTimeInterval(-(6 * 60 + 18) * 60))
    }
}
#endif
