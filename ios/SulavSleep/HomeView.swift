import SwiftUI

struct HomeView: View {
    var store: SleepStore
    let profile: Profile

    @State private var presentedSheet: PresentedSheet?
    @State private var now = Date()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                HomeHeader(isImporting: store.isImportingHealth) {
                    presentedSheet = .settings
                }

                if let active = store.activeSession {
                    SleepingStateView(
                        profile: profile,
                        activeSession: active,
                        now: now,
                        onWake: {
                            Haptics.success()
                            store.wakeUp()
                        }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    AwakeStateView(
                        profile: profile,
                        lastSession: store.latestSession,
                        targetMinutes: store.targetMinutes,
                        streak: store.onTrackStreak,
                        healthState: store.healthSyncState,
                        onSleepNow: {
                            Haptics.soft()
                            store.startSleep()
                        },
                        onSetBedtime: { presentedSheet = .schedule },
                        onOpenSettings: { presentedSheet = .settings }
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
                ScheduleSheet(bedtime: profile.bedtime, wakeTime: profile.wakeTime) { bedtime, wakeTime in
                    store.saveSchedule(bedtime: bedtime, wakeTime: wakeTime)
                    presentedSheet = nil
                }
            case .settings:
                SettingsSheet(
                    profile: profile,
                    healthState: store.healthSyncState,
                    onSaveName: store.saveName,
                    onOpenSchedule: { presentedSheet = .schedule },
                    onToggleHealth: { enabled in
                        if enabled { Task { await store.enableHealthSync() } }
                        else { store.disableHealthSync() }
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
        .animation(.easeInOut(duration: 0.3), value: store.activeSession != nil)
    }
}

private struct HomeHeader: View {
    let isImporting: Bool
    let onSettings: () -> Void

    var body: some View {
        HStack {
            HStack(spacing: SleepSpacing.sm) {
                Text(SleepFormatting.longDate.string(from: Date()))
                    .font(SleepFont.body(14))
                    .foregroundStyle(SleepColor.muted)
                if isImporting {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(SleepColor.amber)
                        .accessibilityLabel("Syncing Apple Health")
                }
            }

            Spacer()

            Button(action: onSettings) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 16, weight: .medium))
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
    let healthState: HealthSyncState
    let onSleepNow: () -> Void
    let onSetBedtime: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: SleepSpacing.xs) {
                Text(greeting)
                    .font(SleepFont.body(16))
                    .foregroundStyle(SleepColor.dim)
                Text(profile.name)
                    .font(SleepFont.hero(36))
                    .foregroundStyle(SleepColor.ink)
            }
            .padding(.top, SleepSpacing.huge * 1.4)

            VStack(spacing: SleepSpacing.xs) {
                Text("Tonight").sectionLabel()
                Text("\(SleepFormatting.clock(profile.bedtime))  –  \(SleepFormatting.clock(profile.wakeTime))")
                    .font(SleepFont.title(24))
                    .foregroundStyle(SleepColor.ink)
                Text("\(SleepFormatting.duration(targetMinutes)) in bed")
                    .font(SleepFont.body(13))
                    .foregroundStyle(SleepColor.muted)
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

            LastNightSummary(
                lastSession: lastSession,
                streak: streak,
                healthState: healthState,
                onConnectHealth: onOpenSettings
            )
            .padding(.top, SleepSpacing.huge * 1.3)
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning,"
        case 12..<17: return "Good afternoon,"
        case 17..<22: return "Good evening,"
        default: return "Good night,"
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
                .font(SleepFont.hero(58))
                .foregroundStyle(SleepColor.ink)
                .monospacedDigit()
                .padding(.top, SleepSpacing.lg)

            Text("Since \(SleepFormatting.shortTime.string(from: activeSession.start))")
                .font(SleepFont.body(14))
                .foregroundStyle(SleepColor.muted)

            Text("The phone is resting. Wake up when you're ready and we'll log your night.")
                .font(SleepFont.body(13))
                .foregroundStyle(SleepColor.quiet)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .frame(maxWidth: 280)
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
    let healthState: HealthSyncState
    let onConnectHealth: () -> Void

    var body: some View {
        VStack(spacing: SleepSpacing.lg) {
            Rectangle().fill(SleepColor.hairline).frame(height: 1)

            if let lastSession {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Last night")
                            .font(SleepFont.body(13))
                            .foregroundStyle(SleepColor.muted)
                        Text(SleepFormatting.duration(lastSession.durationMinutes))
                            .font(SleepFont.title(28))
                            .foregroundStyle(SleepColor.ink)
                            .monospacedDigit()
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("Score")
                            .font(SleepFont.body(13))
                            .foregroundStyle(SleepColor.muted)
                        Text("\(lastSession.score)")
                            .font(SleepFont.title(28))
                            .foregroundStyle(scoreColor(lastSession.score))
                            .monospacedDigit()
                    }
                }

                if streak > 0 {
                    Label("\(streak) night\(streak > 1 ? "s" : "") on track", systemImage: "flame.fill")
                        .font(SleepFont.body(14))
                        .foregroundStyle(SleepColor.gold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                EmptyNight(healthState: healthState, onConnectHealth: onConnectHealth)
            }
        }
    }

    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 80...: return SleepColor.gold
        case 60..<80: return SleepColor.ink
        default: return SleepColor.danger
        }
    }
}

private struct EmptyNight: View {
    let healthState: HealthSyncState
    let onConnectHealth: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SleepSpacing.md) {
            Text("No nights logged yet")
                .font(SleepFont.title(18))
                .foregroundStyle(SleepColor.ink)
            Text("Tap Sleep Now when you head to bed and your first real night will appear here.")
                .font(SleepFont.body(14))
                .foregroundStyle(SleepColor.muted)
                .lineSpacing(3)

            if healthState == .notConnected {
                Button(action: onConnectHealth) {
                    Label("Connect Apple Health", systemImage: "heart.fill")
                        .font(SleepFont.label(14))
                        .foregroundStyle(SleepColor.amber)
                }
                .buttonStyle(.plain)
                .padding(.top, SleepSpacing.xs)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
