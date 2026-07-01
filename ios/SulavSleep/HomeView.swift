import SwiftUI

struct HomeView: View {
    var store: SleepStore
    let profile: Profile

    @State private var presentedSheet: PresentedSheet?
    @State private var now = Date()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                HomeHeader {
                    presentedSheet = .settings
                }

                if let active = store.activeSession {
                    SleepingStateView(
                        profile: profile,
                        activeSession: active,
                        now: now,
                        onWake: store.wakeUp
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    AwakeStateView(
                        profile: profile,
                        lastSession: store.latestSession,
                        targetMinutes: store.targetMinutes,
                        streak: store.onTrackStreak,
                        onSleepNow: store.startSleep,
                        onSetBedtime: { presentedSheet = .schedule }
                    )
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(.horizontal, SleepSpacing.xxl)
            .padding(.top, SleepSpacing.sm)
            .padding(.bottom, store.activeSession == nil ? 140 : SleepSpacing.huge)
        }
        .safeAreaPadding(.top)
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .schedule:
                ScheduleSheet(
                    bedtime: profile.bedtime,
                    wakeTime: profile.wakeTime
                ) { bedtime, wakeTime in
                    store.saveSchedule(bedtime: bedtime, wakeTime: wakeTime)
                    presentedSheet = nil
                }
            case .settings:
                SettingsSheet(
                    profile: profile,
                    onSaveName: store.saveName,
                    onOpenSchedule: {
                        presentedSheet = .schedule
                    },
                    onReset: {
                        presentedSheet = nil
                        store.resetAll()
                    }
                )
            }
        }
        .task(id: store.activeSession?.start) {
            guard store.activeSession != nil else { return }
            while !Task.isCancelled {
                now = Date()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .animation(.easeInOut(duration: 0.28), value: store.activeSession != nil)
    }
}

private struct HomeHeader: View {
    let onSettings: () -> Void

    var body: some View {
        HStack {
            Text(SleepFormatting.longDate.string(from: Date()))
                .font(SleepFont.body(14))
                .foregroundStyle(SleepColor.quiet)

            Spacer()

            Button(action: onSettings) {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .foregroundStyle(SleepColor.dim)
            .liquidGlass(cornerRadius: SleepRadius.pill, interactive: true)
            .accessibilityLabel("Settings")
        }
        .frame(minHeight: 44)
    }
}

private struct AwakeStateView: View {
    let profile: Profile
    let lastSession: SleepSession?
    let targetMinutes: Int
    let streak: Int
    let onSleepNow: () -> Void
    let onSetBedtime: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: SleepSpacing.xs) {
                Text("Good evening,")
                    .font(SleepFont.body(16))
                    .foregroundStyle(SleepColor.dim)
                Text(profile.name)
                    .font(SleepFont.hero(34))
                    .foregroundStyle(SleepColor.white)
            }
            .padding(.top, SleepSpacing.huge * 1.4)

            VStack(spacing: 2) {
                Text("TONIGHT")
                    .font(SleepFont.label(12))
                    .foregroundStyle(SleepColor.faint)
                Text("\(SleepFormatting.clock(profile.bedtime))  ->  \(SleepFormatting.clock(profile.wakeTime))")
                    .font(SleepFont.title(22))
                    .foregroundStyle(SleepColor.white)
                Text("\(SleepFormatting.duration(targetMinutes)) in bed")
                    .font(SleepFont.body(13))
                    .foregroundStyle(SleepColor.quiet)
            }
            .padding(.top, SleepSpacing.huge * 1.1)

            VStack(spacing: SleepSpacing.md) {
                LiquidPrimaryButton(title: "Sleep Now", systemImage: "moon.fill", action: onSleepNow)
                LiquidSecondaryButton(
                    title: "Set Bedtime",
                    value: SleepFormatting.clock(profile.bedtime),
                    systemImage: "clock",
                    action: onSetBedtime
                )
            }
            .padding(.top, SleepSpacing.huge * 1.2)

            LastNightSummary(lastSession: lastSession, streak: streak)
                .padding(.top, SleepSpacing.huge * 1.3)
        }
    }
}

private struct SleepingStateView: View {
    let profile: Profile
    let activeSession: ActiveSleepSession
    let now: Date
    let onWake: () -> Void

    private var elapsedMinutes: Int {
        max(0, Int(now.timeIntervalSince(activeSession.start) / 60))
    }

    var body: some View {
        VStack(spacing: SleepSpacing.sm) {
            Text("Good night, \(profile.name)")
                .font(SleepFont.body(15))
                .foregroundStyle(SleepColor.dim)

            Text("\(elapsedMinutes / 60)h \(String(format: "%02d", elapsedMinutes % 60))m")
                .font(SleepFont.hero(56))
                .foregroundStyle(SleepColor.white)
                .padding(.top, SleepSpacing.lg)
                .monospacedDigit()

            Text("Sleeping since \(SleepFormatting.shortTime.string(from: activeSession.start))")
                .font(SleepFont.body(14))
                .foregroundStyle(SleepColor.quiet)

            Text("The phone is resting. Wake up when you're ready and we'll log your night.")
                .font(SleepFont.body(13))
                .foregroundStyle(SleepColor.faint)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 270)
                .padding(.top, SleepSpacing.sm)

            Spacer(minLength: SleepSpacing.huge * 2.2)

            LiquidPrimaryButton(title: "Wake up", systemImage: "sunrise.fill", action: onWake)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, SleepSpacing.huge * 2.4)
    }
}

private struct LastNightSummary: View {
    let lastSession: SleepSession?
    let streak: Int

    var body: some View {
        VStack(spacing: SleepSpacing.lg) {
            Rectangle()
                .fill(SleepColor.hairline)
                .frame(height: 1)

            if let lastSession {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Last night")
                            .font(SleepFont.body(13))
                            .foregroundStyle(SleepColor.quiet)
                        Text(SleepFormatting.duration(lastSession.durationMinutes))
                            .font(SleepFont.title(28))
                            .foregroundStyle(SleepColor.white)
                            .monospacedDigit()
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Score")
                            .font(SleepFont.body(13))
                            .foregroundStyle(SleepColor.quiet)
                        Text("\(lastSession.score)")
                            .font(SleepFont.title(28))
                            .foregroundStyle(SleepColor.white)
                            .monospacedDigit()
                    }
                }
            } else {
                Text("No nights logged yet. Tap Sleep Now when you head to bed.")
                    .font(SleepFont.body(14))
                    .foregroundStyle(SleepColor.quiet)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if streak > 0 {
                Label("\(streak) night\(streak > 1 ? "s" : "") on track", systemImage: "moon.zzz.fill")
                    .font(SleepFont.body(14))
                    .foregroundStyle(SleepColor.dim)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

