import SwiftUI

struct RootView: View {
    var store: SleepStore
    @State private var onboardingNameFocused = false

    var body: some View {
        ZStack {
            if store.isOnboarded, let active = store.activeSession {
                // Immersive, pitch-black sleep mode takes over the whole screen.
                SleepModeView(store: store, activeSession: active)
                    .transition(.opacity)
                    .zIndex(2)
            } else if store.isOnboarded, let profile = store.profile {
                // The scene lives inside each tab so it shows behind the native
                // (opaque-by-default) TabView content.
                MainShellView(store: store, profile: profile)
                    .transition(.opacity)
            } else {
                SleepBackground(showsMoon: false, isActive: !onboardingNameFocused)
                OnboardingView(
                    healthAvailable: store.healthSyncState != .unavailable,
                    onNameFocusChange: { onboardingNameFocused = $0 }
                ) { name, bedtime, wakeTime, connectHealth in
                    store.completeOnboarding(name: name, bedtime: bedtime, wakeTime: wakeTime, connectHealth: connectHealth)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: store.activeSession != nil)
        .animation(.easeInOut(duration: 0.32), value: store.isOnboarded)
    }
}

struct MainShellView: View {
    @Bindable var store: SleepStore
    let profile: Profile

    var body: some View {
        TabView(selection: $store.selectedTab) {
            tab(active: store.selectedTab == .home) { HomeView(store: store, profile: profile) }
                .tabItem { Label("Home", systemImage: "house") }
                .tag(AppTab.home)

            tab(active: store.selectedTab == .reports) { ReportsView(store: store) }
                .tabItem { Label("Reports", systemImage: "chart.xyaxis.line") }
                .tag(AppTab.reports)
        }
        .tint(SleepColor.amber)
    }

    // Only the visible tab's background animates; the hidden tab's clock
    // pauses so it isn't silently costing frames in the background.
    private func tab<Content: View>(active: Bool, @ViewBuilder _ content: () -> Content) -> some View {
        ZStack {
            SleepBackground(showsMoon: true, isActive: active)
            content()
        }
    }
}
