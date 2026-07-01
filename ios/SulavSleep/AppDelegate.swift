import SwiftUI

@main
struct SulavSleepApp: App {
    @State private var store = SleepStore()

    var body: some Scene {
        WindowGroup {
            RootView(store: store)
                .preferredColorScheme(.dark)
                .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
                    store.reload()
                }
        }
    }
}

