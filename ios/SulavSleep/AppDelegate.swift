import SwiftUI

@main
struct SulavSleepApp: App {
    @State private var store = SleepStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView(store: store)
                .preferredColorScheme(.dark)
                .task {
                    AppLog.app.info("App launched")
                    await store.refreshHealthIfEnabled()
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    AppLog.app.info("Scene active")
                    Task { await store.refreshHealthIfEnabled() }
                }
                .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
                    store.reload()
                }
        }
    }
}
