import SwiftUI

/// Which top-level screen the ZStack shows, underneath the sleep-mode overlay.
/// Kept as a single value so the crossfade between screens has exactly one
/// animation trigger — stacking several independent `.animation(value:)`
/// modifiers on the same subtree let transitions race each other and left
/// the outgoing screen briefly intercepting touches meant for the new one.
private enum RootScreen: Equatable {
    case authLoading
    case onboarding
    case main
}

struct RootView: View {
    var store: SleepStore

    /// The in-app splash (`LaunchSplashView`) is held up for a beat past auth
    /// readiness so the brand mark's rising z's are actually *seen* animating
    /// — the Keychain restore usually resolves in well under a second, which
    /// would cut the mark off before the first z fades in. The hold does not
    /// gate the sleep-mode overlay: an active session still takes the screen
    /// immediately.
    @State private var splashHoldDone = false
    private static let splashHold: Duration = .seconds(1.5)

    // Auth readiness is checked first so a signed-in user reinstalling the app
    // never flashes the welcome screen: the gate needs to know whether to open
    // on welcome (new user) or the quick-setup questions (signed in, no local
    // profile). Anyone not signed in — including an onboarded user who signed
    // out — lands on the onboarding gate, which opens on the type-led welcome
    // screen (Get started / I already have an account), not a sign-in wall.
    private var screen: RootScreen {
        guard store.isAuthReady, splashHoldDone else { return .authLoading }
        guard store.isAuthenticated else { return .onboarding }
        guard store.isOnboarded else { return .onboarding }
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
                // Scope the hard-cut to the `screen` change only. A bare
                // `.transaction { $0.disablesAnimations = true }` here disables
                // animations for the *entire* Main subtree on every state
                // change — which silently killed the settings sheet's slide-up.
                // `transaction(value:)` applies the override only when `screen`
                // itself changes, so sheets/alerts inside Main animate normally.
                MainShellView(store: store, profile: profile)
                    .transaction(value: screen) { $0.disablesAnimations = true }
            } else {
                Group {
                    switch screen {
                    case .authLoading:
                        // Continuation of the launch storyboard while the
                        // Keychain session restore runs (plus the splash
                        // hold): the same sloth on the same navy, now with
                        // the z's animating. The scene assets are prewarmed
                        // in AppDelegate, so not mounting SleepBackground
                        // here costs the next screen nothing.
                        LaunchSplashView()
                    case .onboarding:
                        // Welcome → sign-up questionnaire, with a sign-in
                        // escape for returning users. Also where a signed-out
                        // user lands, opening on the welcome screen. See
                        // OnboardingGateView.
                        SleepBackground(showsMoon: false)
                        SceneReadabilityScrim()
                        OnboardingGateView(store: store)
                    case .main:
                        EmptyView() // Handled by the branch above.
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: store.activeSession != nil)
        .animation(.easeInOut(duration: 0.32), value: screen)
        .task {
            try? await Task.sleep(for: Self.splashHold)
            splashHoldDone = true
        }
    }
}

// MARK: - Launch splash

/// SwiftUI continuation of the launch storyboard: the identical splash sloth
/// (`SplashSloth.imageset` — the icon's colorway on a transparent background,
/// generated by `scripts/generate-app-icon.py`) at the identical size and
/// position on the same flat navy, so the storyboard → app handoff is
/// invisible. Then the mark comes alive: the launch storyboard is a static
/// snapshot — iOS cannot animate it — so the gold rising z's (and the brand
/// mark's warm halo) start here, the moment the app takes over the frame.
///
/// Deliberately *not* `SlothBrandMark`: that mark wears the scene's current
/// phase light (`HomeSloth{phase}Blink`), which at night would visibly pop
/// against the storyboard's icon-colorway art.
private struct LaunchSplashView: View {
    /// Must match the storyboard's SPLASH-ICON width/height constraints
    /// (200×120, centered) or the handoff jumps.
    private static let width: CGFloat = 200

    var body: some View {
        ZStack {
            SleepColor.background.ignoresSafeArea()
            Image("SplashSloth")
                .resizable()
                .scaledToFit()
                .frame(width: Self.width)
                // The brand mark's warm halo (SlothBrandMark, night opacity),
                // seating the figure the way the icon's lamp glow does.
                .background {
                    Ellipse()
                        .fill(SleepColor.amber.opacity(0.16))
                        .blur(radius: Self.width * 0.144)
                        .padding(-Self.width * 0.05)
                }
                .overlay(alignment: .topLeading) {
                    // Same ride the brand mark runs, scaled up with the art
                    // (hero: 0.62 at 150pt).
                    RisingZs(color: SleepColor.gold, scale: 0.75)
                        .offset(x: Self.width * 0.22, y: -Self.width * 0.007)
                }
        }
        .accessibilityHidden(true)
    }
}

struct MainShellView: View {
    @Bindable var store: SleepStore
    let profile: Profile

    var body: some View {
        TabView(selection: $store.selectedTab) {
            tab { HomeView(store: store, profile: profile) }
                .tabItem { Label(AppTab.home.title, systemImage: AppTab.home.symbol) }
                .tag(AppTab.home)

            // Profile hosts its own NavigationStack; each of its screens embeds
            // the scene itself so pushed pages stay on the night city.
            ProfileView(store: store, profile: profile)
                .tabItem { Label(AppTab.profile.title, systemImage: AppTab.profile.symbol) }
                .tag(AppTab.profile)
        }
        .tint(SleepColor.amber)
    }

    // The native TabView content host is opaque, so the scene must live inside
    // each tab. SleepBackground synchronizes its Core Animation phase globally,
    // which keeps Home/Profile switches from restarting the skyline motion.
    private func tab<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ZStack {
            SleepBackground(showsMoon: true)
            SceneReadabilityScrim()
            content()
        }
    }
}
