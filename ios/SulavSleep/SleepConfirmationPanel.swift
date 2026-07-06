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
        let isBlocking = store.screenTimeState != .unavailable
            && store.lockdownEnabled
            && (!appTokens.isEmpty || !catTokens.isEmpty)

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

    private let knobSize: CGFloat = 56
    private let trackHeight: CGFloat = 64
    private let trackPadding: CGFloat = 4
    private let completionThreshold: CGFloat = 0.80

    var body: some View {
        GeometryReader { geo in
            let maxOffset = geo.size.width - knobSize - trackPadding * 2
            let progress = maxOffset > 0 ? min(dragOffset / maxOffset, 1) : 0

            ZStack(alignment: .leading) {
                // Track
                Capsule(style: .continuous)
                    .fill(SleepColor.glassFill)
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(SleepColor.border, lineWidth: 1)
                    }

                // Progress fill
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [SleepColor.amber.opacity(0.25), SleepColor.gold.opacity(0.15)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: dragOffset + knobSize + trackPadding * 2)

                // Label — fades as the knob moves
                HStack {
                    Spacer()
                    Text("Slide to sleep")
                        .font(SleepFont.label(15))
                        .tracking(0.4)
                        .foregroundStyle(SleepColor.dim)
                    Spacer()
                }
                .opacity(Double(max(0, 1 - progress * 2.5)))

                // Shimmer hint arrows
                HStack(spacing: 3) {
                    Spacer()
                    ForEach(0..<3, id: \.self) { i in
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(SleepColor.muted.opacity(Double(max(0, 0.5 - progress * 2))))
                    }
                    Spacer().frame(width: knobSize + trackPadding + 4)
                }

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
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    }
                    .overlay {
                        Image(systemName: "moon.fill")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(SleepColor.background)
                    }
                    .frame(width: knobSize, height: knobSize)
                    .shadow(color: SleepColor.amber.opacity(isDragging ? 0.5 : 0.3),
                            radius: isDragging ? 16 : 10, y: 4)
                    .offset(x: trackPadding + dragOffset)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .updating($isDragging) { _, state, _ in
                                state = true
                            }
                            .onChanged { value in
                                guard !isCompleted else { return }
                                dragOffset = min(max(0, value.translation.width), maxOffset)
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
                                    // Spring back
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
}
