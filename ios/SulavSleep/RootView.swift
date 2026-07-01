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
                OnboardingView { name, bedtime, wakeTime in
                    store.completeOnboarding(name: name, bedtime: bedtime, wakeTime: wakeTime)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.28), value: store.isOnboarded)
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
                    ReportsView(sessions: store.sessions)
                }
            }
            .transition(.opacity)

            if store.activeSession == nil {
                BottomNav(selectedTab: store.selectedTab) { tab in
                    store.selectedTab = tab
                }
                .padding(.bottom, SleepSpacing.sm)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.24), value: store.selectedTab)
        .animation(.easeInOut(duration: 0.24), value: store.activeSession != nil)
    }
}

struct BottomNav: View {
    let selectedTab: AppTab
    let onSelect: (AppTab) -> Void

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: SleepSpacing.xl) {
                navContent
            }
            .padding(.horizontal, SleepSpacing.xxl)
        } else {
            navContent
                .padding(.horizontal, SleepSpacing.xxl)
        }
    }

    private var navContent: some View {
        HStack(spacing: SleepSpacing.xl) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    onSelect(tab)
                } label: {
                    VStack(spacing: SleepSpacing.xs) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 21, weight: .semibold))
                        Text(tab.title)
                            .font(SleepFont.label(11))
                    }
                    .frame(width: 86, height: 58)
                    .foregroundStyle(selectedTab == tab ? SleepColor.white : SleepColor.faint)
                }
                .buttonStyle(.plain)
                .liquidGlass(cornerRadius: SleepRadius.pill, interactive: true)
                .accessibilityLabel(tab.title)
            }
        }
        .padding(.vertical, SleepSpacing.sm)
    }
}
