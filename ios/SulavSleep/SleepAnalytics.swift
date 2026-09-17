import Foundation
import Supabase

/// First-party product events. This is intentionally a small named funnel,
/// never a capture of screen contents, typed answers, Health data or picker
/// tokens. The database supplies user_id from the authenticated JWT.
@MainActor
enum SleepAnalytics {
    private struct Event: Codable {
        let id: UUID
        let installID: UUID
        let eventName: String
        let screen: String?
        let control: String?
        let appVersion: String
        let occurredAt: String

        enum CodingKeys: String, CodingKey {
            case id, screen, control
            case installID = "install_id"
            case eventName = "event_name"
            case appVersion = "app_version"
            case occurredAt = "occurred_at"
        }
    }

    private static let queueKey = "sulav.analytics.queue.v1"
    private static let installKey = "sulav.analytics.install.v1"
    private static var sending = false

    // Product decision: named first-party usage events are always enabled.
    // Never add setup answer values or health data to this payload.
    static var isEnabled: Bool { true }

    static func record(_ name: String, screen: String? = nil, control: String? = nil) {
#if targetEnvironment(simulator)
        return // Simulator QA must never pollute production funnels.
#else
        guard isEnabled, SulavAuth.sharedClient != nil else { return }
        let installID: UUID
        if let saved = UserDefaults.standard.string(forKey: installKey), let id = UUID(uuidString: saved) {
            installID = id
        } else {
            installID = UUID()
            UserDefaults.standard.set(installID.uuidString, forKey: installKey)
        }
        let event = Event(
            id: UUID(), installID: installID, eventName: name, screen: screen.map { String($0.prefix(48)) },
            control: control.map { String($0.prefix(48)) },
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            occurredAt: ISO8601DateFormatter().string(from: Date())
        )
        var pending = queue()
        pending.append(event)
        // Bound local storage if a device stays offline for a long time.
        if pending.count > 500 { pending.removeFirst(pending.count - 500) }
        save(pending)
        flush()
#endif
    }

    static func clearPending() { UserDefaults.standard.removeObject(forKey: queueKey) }

    static func rotateInstallID() {
        clearPending()
        UserDefaults.standard.removeObject(forKey: installKey)
    }

    static func reset() {
        rotateInstallID()
        UserDefaults.standard.removeObject(forKey: "sulav.analytics.consent.v1")
    }

    static func flush() {
#if targetEnvironment(simulator)
        return
#else
        guard isEnabled, !sending, SulavAuth.sharedClient != nil else { return }
        sending = true
        Task {
            defer { sending = false }
            while isEnabled, let event = queue().first, let client = SulavAuth.sharedClient {
                do {
                    try await client.from("product_events").insert(event).execute()
                } catch {
                    // A request may have reached the server before the app
                    // lost its connection. The event ID makes retry safe.
                    if !String(describing: error).contains("23505") {
                        AppLog.app.error("Product event send failed: \(error.localizedDescription, privacy: .public)")
                        return
                    }
                }
                var pending = queue()
                if pending.first?.id == event.id {
                    pending.removeFirst()
                    save(pending)
                }
            }
        }
    #endif
    }

    private static func queue() -> [Event] {
        guard let data = UserDefaults.standard.data(forKey: queueKey) else { return [] }
        return (try? JSONDecoder().decode([Event].self, from: data)) ?? []
    }

    private static func save(_ events: [Event]) {
        if let data = try? JSONEncoder().encode(events) {
            UserDefaults.standard.set(data, forKey: queueKey)
        }
    }
}
