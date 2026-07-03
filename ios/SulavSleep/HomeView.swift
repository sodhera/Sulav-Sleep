import SwiftUI

struct HomeView: View {
    var store: SleepStore
    let profile: Profile

    @State private var presentedSheet: PresentedSheet?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                HomeHeader(isImporting: store.isImportingHealth) {
                    presentedSheet = .settings
                }

                VStack(spacing: SleepSpacing.xs) {
                    Text(greeting)
                        .font(SleepFont.body(16))
                        .foregroundStyle(SleepColor.dim)
                    Text(profile.name)
                        .font(SleepFont.hero(36))
                        .foregroundStyle(SleepColor.ink)
                }
                .padding(.top, SleepSpacing.huge * 1.6)

                TimelineView(.periodic(from: .now, by: 60)) { timeline in
                    VStack(spacing: SleepSpacing.xs) {
                        Text("Bedtime in").sectionLabel()
                        Text(SleepFormatting.countdown(toMinuteOfDay: profile.bedtime, from: timeline.date))
                            .font(SleepFont.title(24))
                            .foregroundStyle(SleepColor.ink)
                            .monospacedDigit()
                    }
                }
                .padding(.top, SleepSpacing.huge)

                LiquidPrimaryButton(title: "Sleep Now", systemImage: "moon.fill") {
                    Haptics.soft()
                    store.startSleep()
                }
                .padding(.top, SleepSpacing.huge * 1.3)

                LastNightSummary(lastSession: store.latestSession, streak: store.onTrackStreak)
                    .padding(.top, SleepSpacing.huge * 1.4)
            }
            .padding(.horizontal, SleepSpacing.xxl)
            .padding(.top, SleepSpacing.sm)
            .padding(.bottom, SleepSpacing.huge)
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
                    onOpenLockdown: { presentedSheet = .lockdown },
                    onReset: {
                        presentedSheet = nil
                        store.resetAll()
                    },
                    onSignOut: {
                        presentedSheet = nil
                        Task { await store.signOut() }
                    }
                )
            case .lockdown:
                LockdownSettingsView(store: store)
            }
        }
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: return "Good morning,"
        case 12..<17: return "Good afternoon,"
        case 17..<22: return "Good evening,"
        default: return "Good night,"
        }
    }
}

private struct HomeHeader: View {
    let isImporting: Bool
    let onSettings: () -> Void

    var body: some View {
        HStack {
            if isImporting {
                ProgressView().controlSize(.mini).tint(SleepColor.amber)
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

private struct LastNightSummary: View {
    let lastSession: SleepSession?
    let streak: Int

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
                Text("No nights logged yet.")
                    .font(SleepFont.body(15))
                    .foregroundStyle(SleepColor.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
