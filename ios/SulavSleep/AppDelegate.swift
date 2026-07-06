import SwiftUI
import UIKit

// MARK: - Interactive edge-swipe back

// Every pushed page in the app sits on the living scene and hides the system
// navigation bar (`SceneScreen` + `.toolbar(.hidden)`), supplying its own
// round GlassBackButton instead. UIKit ties the interactive "swipe from the
// left edge to go back" recognizer to the visible bar, so hiding the bar also
// kills that gesture — leaving the button as the only way back. Re-pointing
// the recognizer's delegate at the navigation controller restores the native
// edge-swipe on every pushed screen (Profile → All nights / Blocked apps,
// Settings → Schedule / Blocked apps) while still refusing to fire at a stack
// root. This is app-wide by design: there is no screen where we want the
// standard iOS back-swipe suppressed.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // Only govern the pop recognizer we adopted — never swallow other
        // gestures — and never let a swipe try to pop the root controller.
        guard gestureRecognizer == interactivePopGestureRecognizer else { return true }
        return viewControllers.count > 1
    }
}

@main
struct SulavSleepApp: App {
    @State private var store = SleepStore()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        SleepAssetCache.prewarmCriticalAssets()
    }

    var body: some Scene {
        WindowGroup {
            RootView(store: store)
                .preferredColorScheme(.dark)
                .onAppear {
                    Haptics.prepare()
                }
                .task {
                    AppLog.app.info("App launched")
                    await store.refreshHealthIfEnabled()
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    AppLog.app.info("Scene active")
                    Haptics.prepare()
                    store.reload()
                    Task { await store.refreshHealthIfEnabled() }
                }
                .onOpenURL { url in
                    // Handle sleepblock://sleep from the shield action extension.
                    // If there's already an active session, RootView shows
                    // SleepModeView automatically. If not, start sleep so the
                    // user lands on the immersive screen.
                    guard url.scheme == "sleepblock", url.host == "sleep" else { return }
                    AppLog.app.info("Opened via sleepblock://sleep URL")
                    if store.activeSession == nil, store.isOnboarded {
                        Haptics.soft()
                        store.startSleep()
                    }
                }
        }
    }
}
