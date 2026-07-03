import SwiftUI

/// Which top-level screen the ZStack shows, underneath the sleep-mode overlay.
/// Kept as a single value so the crossfade between screens has exactly one
/// animation trigger — stacking several independent `.animation(value:)`
/// modifiers on the same subtree let transitions race each other and left
/// the outgoing screen briefly intercepting touches meant for the new one.
private enum RootScreen: Equatable {
    case authLoading
    case onboarding
    case auth
    case main
}

struct RootView: View {
    var store: SleepStore

    // Auth readiness is checked first so a signed-in user reinstalling the app
    // never flashes the welcome screen: the gate needs to know whether to open
    // on welcome (new user) or the quick-setup questions (signed in, no local
    // profile). `.auth` is only reached with a finished profile — the end of
    // the sign-up path, or an onboarded user who signed out.
    private var screen: RootScreen {
        guard store.isAuthReady else { return .authLoading }
        guard store.isOnboarded else { return .onboarding }
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
                    case .authLoading:
                        // Brief neutral state while the Keychain session
                        // restore check runs, so we don't flash the welcome
                        // screen for already signed-in users.
                        SleepBackground(showsMoon: false)
                    case .onboarding:
                        // Welcome → sign-up questionnaire, with a sign-in
                        // escape for returning users. See OnboardingGateView.
                        SleepBackground(showsMoon: false)
                        OnboardingGateView(store: store)
                    case .auth:
                        // End of the sign-up path ("save the plan you just
                        // made") — unless the user just signed out, in which
                        // case they're a returning user and get "Welcome
                        // back". Both framings carry a toggle to the other.
                        SleepBackground(showsMoon: false)
                        AuthView(store: store, intent: store.didJustSignOut ? .signIn : .signUp)
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
