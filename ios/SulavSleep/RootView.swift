import SwiftUI

struct RootView: View {
    var store: SleepStore

    var body: some View {
        ZStack {
            SleepBackground(showsMoon: store.isOnboarded)

            if store.isOnboarded, let profile = store.profile {
                MainShellView(store: store, profile: profile)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                OnboardingView(healthAvailable: store.healthSyncState != .unavailable) { name, bedtime, wakeTime, connectHealth in
                    store.completeOnboarding(name: name, bedtime: bedtime, wakeTime: wakeTime, connectHealth: connectHealth)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.32), value: store.isOnboarded)
    }
}

struct MainShellView: View {
    var store: SleepStore
    let profile: Profile

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch store.selectedTab {
                case .home:
                    HomeView(store: store, profile: profile)
                case .reports:
                    ReportsView(store: store)
                }
            }
            .transition(.opacity)

            if store.activeSession == nil {
                BottomNav(selectedTab: store.selectedTab) { tab in
                    Haptics.soft()
                    store.selectedTab = tab
                }
                .padding(.bottom, SleepSpacing.sm)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.28), value: store.selectedTab)
        .animation(.easeInOut(duration: 0.28), value: store.activeSession != nil)
    }
}

struct BottomNav: View {
    let selectedTab: AppTab
    let onSelect: (AppTab) -> Void

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: SleepSpacing.lg) {
                navContent
            }
            .padding(.horizontal, SleepSpacing.xxl)
        } else {
            navContent
                .padding(.horizontal, SleepSpacing.xxl)
        }
    }

    private var navContent: some View {
        HStack(spacing: SleepSpacing.md) {
            ForEach(AppTab.allCases) { tab in
                let selected = selectedTab == tab
                Button {
                    onSelect(tab)
                } label: {
                    VStack(spacing: SleepSpacing.xs) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 19, weight: selected ? .semibold : .regular))
                        Text(tab.title)
                            .font(SleepFont.label(11))
                    }
                    .frame(width: 92, height: 56)
                    .foregroundStyle(selected ? SleepColor.amber : SleepColor.muted)
                }
                .buttonStyle(.plain)
                .liquidGlass(cornerRadius: SleepRadius.pill, interactive: true)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
        .padding(.vertical, SleepSpacing.xs)
    }
}
