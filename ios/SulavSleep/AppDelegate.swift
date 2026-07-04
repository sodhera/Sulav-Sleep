import SwiftUI

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
