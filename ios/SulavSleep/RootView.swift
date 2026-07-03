import SwiftUI

/// Which top-level screen the ZStack shows, underneath the sleep-mode overlay.
/// Kept as a single value so the crossfade between screens has exactly one
/// animation trigger — stacking several independent `.animation(value:)`
/// modifiers on the same subtree let transitions race each other and left
/// the outgoing screen briefly intercepting touches meant for the new one.
private enum RootScreen: Equatable {
    case onboarding
    case authLoading
    case auth
    case main
}

struct RootView: View {
    var store: SleepStore

    private var screen: RootScreen {
        guard store.isOnboarded else { return .onboarding }
        guard store.isAuthReady else { return .authLoading }
        guard store.isAuthenticated else { return .auth }
        return .main
    }

    var body: some View {
        ZStack {
            if store.isOnboarded, let active = store.activeSession {
                // Immersive, pitch-black sleep mode takes over the whole screen.
                SleepModeView(store: store, activeSession: active)
                    .transition(.opacity)
                    .zIndex(2)
            } else if screen == .main, let profile = store.profile {
                // The scene lives inside each tab so it shows behind the
                // native (opaque-by-default) TabView content. Entering Main
                // is intentionally a hard cut, not a crossfade: animating it
                // left the outgoing auth/onboarding scene (and its animated
                // background layers) mounted alongside the new tab scenes for
                // the duration of the fade, which briefly broke hit-testing
                // on Home.
                MainShellView(store: store, profile: profile)
                    .transaction { $0.disablesAnimations = true }
            } else {
                Group {
                    switch screen {
                    case .onboarding:
                        SleepBackground(showsMoon: false)
                        OnboardingView(
                            healthAvailable: store.healthSyncState != .unavailable
                        ) { name, bedtime, wakeTime, connectHealth in
                            store.completeOnboarding(name: name, bedtime: bedtime, wakeTime: wakeTime, connectHealth: connectHealth)
                        }
                    case .authLoading:
                        // Brief neutral state while the Keychain session
                        // restore check runs, so we don't flash the auth
                        // screen for already signed-in users.
                        SleepBackground(showsMoon: false)
                    case .auth:
                        SleepBackground(showsMoon: false)
                        AuthView(store: store)
                    case .main:
                        EmptyView() // Handled by the branch above.
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: store.activeSession != nil)
        .animation(.easeInOut(duration: 0.32), value: screen)
    }
}

struct MainShellView: View {
    @Bindable var store: SleepStore
    let profile: Profile

    var body: some View {
        TabView(selection: $store.selectedTab) {
            tab { HomeView(store: store, profile: profile) }
                .tabItem { Label("Home", systemImage: "house") }
                .tag(AppTab.home)

            tab { ReportsView(store: store) }
                .tabItem { Label("Reports", systemImage: "chart.xyaxis.line") }
                .tag(AppTab.reports)
        }
        .tint(SleepColor.amber)
    }

    // The native TabView content host is opaque, so the scene must live inside
    // each tab. SleepBackground synchronizes its Core Animation phase globally,
    // which keeps Home/Reports switches from restarting the skyline motion.
    private func tab<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ZStack {
            SleepBackground(showsMoon: true)
            content()
        }
    }
}
