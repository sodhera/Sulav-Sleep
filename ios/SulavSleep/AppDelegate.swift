import SwiftUI

@main
struct SulavSleepApp: App {
    @State private var store = SulavSleepApp.makeStore()
    @Environment(\.scenePhase) private var scenePhase

    /// UI tests launch with `-uitest-reset` and get a throwaway, empty
    /// UserDefaults suite so every run starts at onboarding — never touching or
    /// depending on real persisted state.
    private static func makeStore() -> SleepStore {
        if CommandLine.arguments.contains("-uitest-reset") {
            let suite = "uitest.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defaults.removePersistentDomain(forName: suite)
            return SleepStore(persistence: SleepPersistence(defaults: defaults))
        }
        return SleepStore()
    }

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
                .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification, object: UserDefaults.standard)) { _ in
                    store.reload()
                }
        }
    }
}
