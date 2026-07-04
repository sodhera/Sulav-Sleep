import SwiftUI
import FamilyControls

// Confirmation panel shown after tapping "Sleep Now". Replaces the button and
// last-night summary with a blocked-apps preview, estimated sleep duration,
// and an iPhone-style slide-to-sleep gesture so the commitment is deliberate.

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
        VStack(spacing: SleepSpacing.xxl) {
            // — Blocked apps section —
            blockedAppsSection

            Rectangle().fill(SleepColor.hairline).frame(height: 1)

            // — Sleep duration estimate —
            sleepEstimateSection

            Spacer().frame(height: SleepSpacing.sm)

            // — Slide to sleep —
            SlideToSleepButton {
                Haptics.soft()
                store.startSleep()
            }

            // — Cancel —
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
        }
    }

    // MARK: - Blocked apps

    @ViewBuilder
    private var blockedAppsSection: some View {
        let appTokens = Array(selection.applicationTokens)
        let catTokens = Array(selection.categoryTokens)
        let hasApps = !appTokens.isEmpty || !catTokens.isEmpty
        let lockdownOn = store.lockdownEnabled

        VStack(alignment: .leading, spacing: SleepSpacing.md) {
            Text("Blocked while you sleep").sectionLabel()

            if store.screenTimeState == .unavailable {
                Text("App blocking is available on a real device.")
                    .font(SleepFont.body(14))
                    .foregroundStyle(SleepColor.muted)
            } else if !lockdownOn || !hasApps {
                Text("No apps will be blocked. You can choose apps to block in your profile settings.")
                    .font(SleepFont.body(14))
                    .foregroundStyle(SleepColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: SleepSpacing.sm) {
                    Text("These apps will lock until you wake up:")
                        .font(SleepFont.body(14))
                        .foregroundStyle(SleepColor.dim)

                    HStack(spacing: SleepSpacing.md) {
                        ForEach(appTokens.prefix(6), id: \.self) { token in
                            Label(token)
                                .labelStyle(.iconOnly)
                                .font(.system(size: 30))
                                .frame(width: 34, height: 34)
                        }
                        let overflow = max(0, appTokens.count - 6)
                        if catTokens.count > 0 || overflow > 0 {
                            Text("+more")
                                .font(SleepFont.body(15))
                                .foregroundStyle(SleepColor.muted)
                        }
                        Spacer()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Sleep estimate

    @ViewBuilder
    private var sleepEstimateSection: some View {
        let wakeTimeString = SleepFormatting.clock(profile.wakeTime)
        let durationString = SleepFormatting.duration(estimatedMinutes)

        VStack(alignment: .leading, spacing: SleepSpacing.sm) {
            Text("Sleep estimate").sectionLabel()

            (Text("If you sleep now and wake at ")
                .foregroundStyle(SleepColor.dim)
            + Text(wakeTimeString)
                .foregroundStyle(SleepColor.amber)
            + Text(", you'll get")
                .foregroundStyle(SleepColor.dim))
                .font(SleepFont.body(15))
                .fixedSize(horizontal: false, vertical: true)

            Text(durationString)
                .font(SleepFont.hero(36))
                .foregroundStyle(SleepColor.gold)
                .monospacedDigit()

            Text("of sleep")
                .font(SleepFont.body(15))
                .foregroundStyle(SleepColor.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
