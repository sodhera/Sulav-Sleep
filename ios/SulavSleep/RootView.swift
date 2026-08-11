import SwiftUI

/// Which top-level screen the ZStack shows, underneath the sleep-mode overlay.
/// Kept as a single value so the crossfade between screens has exactly one
/// animation trigger — stacking several independent `.animation(value:)`
/// modifiers on the same subtree let transitions race each other and left
/// the outgoing screen briefly intercepting touches meant for the new one.
private enum RootScreen: Equatable {
    case authLoading
    case onboarding
    case existingAccount
    case paywall
    case screenTimePrimer
    case main
}

struct RootView: View {
    var store: SleepStore

    private var showsReviewPaywall: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("-review-paywall")
            // Forces the paywall past a lapsed referral grant so the
            // streak-aware expiry headline can be seen (see SleepStore).
            || ProcessInfo.processInfo.arguments.contains("-review-referral-expiry")
#else
        false
#endif
    }

    /// DEBUG-only route to eyeball the Screen Time primer on the simulator,
    /// where Family Controls reports `.unavailable` and the real gate never
    /// fires. The CTA will resolve "denied" there and fall through to Main.
    private var showsPrimerPreview: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("-review-screentime-primer")
#else
        false
#endif
    }

    /// DEBUG-only preview of the forced update gate, which otherwise needs a
    /// server-side `min_supported_version` bump to appear.
    private var showsUpdateGatePreview: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("-review-update-gate")
#else
        false
#endif
    }

    /// DEBUG-only route to the "you already have an account" gate, which
    /// otherwise needs a *second* sign-up run against a real Apple/Google
    /// identity that is already registered — not something the simulator can
    /// stage. Renders against the live store, so the copy variant you see is
    /// whichever one this install's state earns (see the view's `message`).
    private var showsExistingAccountPreview: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("-review-existing-account")
#else
        false
#endif
    }

    /// The in-app splash (`LaunchSplashView`) is held up for a beat past auth
    /// readiness so the brand mark's rising z's are actually *seen* animating
    /// — the Keychain restore usually resolves in well under a second, which
    /// would cut the mark off before the first z fades in. The hold does not
    /// gate the sleep-mode overlay: an active session still takes the screen
    /// immediately.
    @State private var splashHoldDone = false
    private static let splashHold: Duration = .seconds(1.5)

    /// The paywall gate waits for the entitlement to *resolve* before showing
    /// anything past the splash — RevenueCat replays its cached CustomerInfo
    /// immediately, so this is normally instant — but the wait is capped so a
    /// first launch with no cache and no network can't hold the splash
    /// hostage. Past the cap an unresolved state fails **open** (Main, not
    /// paywall): real subscribers resolve offline from the cache, and locking
    /// someone out over a network hiccup is worse than one free session.
    @State private var entitlementWaitExpired = false
    private static let entitlementWait: Duration = .seconds(4)

    // Auth readiness is checked first so a signed-in user reinstalling the app
    // never flashes the welcome screen: the gate needs to know whether to open
    // on welcome (new user) or the quick-setup questions (signed in, no local
    // profile). Anyone not signed in — including an onboarded user who signed
    // out — lands on the onboarding gate, which opens on the type-led welcome
    // screen (Get started / I already have an account), not a sign-in wall.
    private var screen: RootScreen {
        guard store.isAuthReady, splashHoldDone else { return .authLoading }
        guard store.isAuthenticated else { return .onboarding }
        // "Get started" that turned out to be a sign-in. Outranks every gate
        // below because all of them would silently answer the user's question
        // for them: Main implies the sign-up worked, and quick setup implies
        // they're new. Neither is what happened. See
        // `SleepStore.showsExistingAccountWelcome`.
        if store.showsExistingAccountWelcome { return .existingAccount }
        guard store.isOnboarded else { return .onboarding }
        // Onboarding's closing beat: signed in, onboarded, resolved as not
        // subscribed, and this install has never closed the paywall. It sells
        // at peak intent — the questionnaire's answers are still on screen in
        // spirit — but it is *not* a wall: the ✕ drops the user into Main and
        // is remembered, after which the lock lives on Sleep Now alone. While
        // the entitlement is still unknown, hold the splash (briefly, capped)
        // rather than flashing Home and snapping the paywall over it.
        if store.needsPaywall { return .paywall }
        if store.entitlement == .unknown && !entitlementWaitExpired { return .authLoading }
        // Subscribed and Screen Time was never granted on this install — the
        // CalAI-style permission primer. Covers both the fresh sign-up (right
        // after the purchase, at peak commitment) and the delete-and-reinstall
        // sign-in, where iOS silently dropped the authorization along with the
        // app. Locked users skip it (see `needsScreenTimePrimer`).
        if store.needsScreenTimePrimer { return .screenTimePrimer }
        return .main
    }

    var body: some View {
        ZStack {
            if showsReviewPaywall {
                // A deterministic, DEBUG-only route for the private screenshot
                // App Store Connect asks for when reviewing a subscription.
                SleepBackground(showsMoon: false)
                SceneReadabilityScrim()
                PaywallView(store: store, onClose: { store.dismissPaywall() })
            } else if showsPrimerPreview {
                SleepBackground(showsMoon: false)
                SceneReadabilityScrim()
                ScreenTimePrimerView(store: store)
            } else if showsExistingAccountPreview {
                SleepBackground(showsMoon: false)
                SceneReadabilityScrim()
                ExistingAccountWelcomeView(store: store)
            } else if store.isOnboarded, let active = store.activeSession {
                // Immersive, pitch-black sleep mode takes over the whole screen.
                SleepModeView(store: store, activeSession: active)
                    .transition(.opacity)
                    .zIndex(2)
            } else if showsUpdateGatePreview || store.updateRequired {
                // The forced update gate: this install is below the server's
                // minimum supported version, i.e. actually broken. Placed
                // *after* the sleep-mode branch on purpose — an active night
                // always keeps wake/cancel and the lockdown teardown
                // reachable (the paywall's rule) — and before every other
                // screen, because none of them work on a build old enough to
                // trip this. Only a successfully fetched config can raise
                // `updateRequired`, so network failure never lands here.
                SleepBackground(showsMoon: false)
                SceneReadabilityScrim()
                UpdateRequiredView(message: store.updateGateMessage) {
                    store.openAppStoreProductPage()
                }
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
                    case .existingAccount:
                        // Same scene as the flow it interrupts — this is the
                        // account step's answer, not a new place.
                        SleepBackground(showsMoon: false)
                        SceneReadabilityScrim()
                        ExistingAccountWelcomeView(store: store)
                    case .paywall:
                        // The subscription pitch, on the same scene as
                        // onboarding — it *is* the questionnaire's closing
                        // beat. Note the sleep-mode overlay above outranks
                        // it: an active night always keeps wake/cancel (and
                        // the lockdown teardown) reachable, subscribed or not.
                        SleepBackground(showsMoon: false)
                        SceneReadabilityScrim()
                        PaywallView(store: store, onClose: { store.dismissPaywall() })
                    case .screenTimePrimer:
                        // The Screen Time permission primer, on the same
                        // scene — the last gate before Main. See
                        // ScreenTimePrimerView for the show/skip rules.
                        SleepBackground(showsMoon: false)
                        SceneReadabilityScrim()
                        ScreenTimePrimerView(store: store)
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
        .task {
            try? await Task.sleep(for: Self.entitlementWait)
            entitlementWaitExpired = true
        }
    }
}

// MARK: - Launch splash

/// SwiftUI continuation of the launch storyboard: the identical splash sloth
/// (`SplashSloth.imageset` — the icon's colorway on a transparent background,
/// generated by `scripts/generate-app-icon.py`) at the identical size and
/// position on the same flat navy, so the storyboard → app handoff is
/// invisible — the *only* thing that changes when the app takes over is the
/// gold rising z's starting (a launch storyboard is a static snapshot; iOS
/// cannot animate it, and their slow fade-in *is* the reveal). Anything else
/// appearing at handoff — even the brand mark's soft halo — reads as a
/// second splash screen popping in, so nothing else does.
///
/// Two handoff traps, learned the janky way:
/// - The storyboard centers the image on the *full screen*; SwiftUI lays out
///   inside the safe area, whose asymmetric insets (status bar > home
///   indicator) sink a safe-area-centered image ~13pt below true screen
///   center. `.ignoresSafeArea()` on the whole stack restores full-screen
///   centering. Do not center this view inside any inset container.
/// - The image frame must match the storyboard's SPLASH-ICON constraints
///   (200×120, centered) exactly.
///
/// Deliberately *not* `SlothBrandMark`: that mark wears the scene's current
/// phase light (`HomeSloth{phase}Blink`), which at night would visibly pop
/// against the storyboard's icon-colorway art.
private struct LaunchSplashView: View {
    private static let width: CGFloat = 200

    var body: some View {
        ZStack {
            SleepColor.background
            Image("SplashSloth")
                .resizable()
                .scaledToFit()
                .frame(width: Self.width)
                .overlay(alignment: .topLeading) {
                    // Same ride the brand mark runs, scaled up with the art
                    // (hero: 0.62 at 150pt).
                    RisingZs(color: SleepColor.gold, scale: 0.75)
                        .offset(x: Self.width * 0.22, y: -Self.width * 0.007)
                }
        }
        .ignoresSafeArea()
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
        // The lock, whenever a locked user reaches for a subscriber-only
        // action (Sleep Now, the Settings row, the widget/shield/Siri deep
        // links). A full-screen cover rather than a sheet: this is the same
        // screen as the first-run pitch, and a half-height card would sell
        // the plan cards short. Closing it here does *not* mark the first-run
        // dismissal — that already happened, or the route would still be up.
        .fullScreenCover(isPresented: $store.showPaywall) {
            ZStack {
                SleepBackground(showsMoon: false)
                SceneReadabilityScrim()
                PaywallView(store: store, onClose: { store.showPaywall = false })
            }
        }
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
