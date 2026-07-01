import SwiftUI
import FamilyControls
import ManagedSettings

// Sleep lockdown via Apple's Screen Time (Family Controls) API.
//
// Reality: real app-blocking requires the `com.apple.developer.family-controls`
// entitlement (Apple approval), only works on a real device, and can only shield
// apps the user picks via the system FamilyActivityPicker. Emergency calls always
// work. On the Simulator this is reported as `.unavailable` and every call is a
// no-op, so the rest of the app is oblivious. See docs/roadmap-lockdown-and-widget.md.

enum ScreenTimeState: Equatable {
    case unavailable    // Simulator, or entitlement not present
    case notAuthorized  // available but user hasn't granted Screen Time
    case authorized
}

protocol ScreenTimeControlling {
    var isSupported: Bool { get }
    func authorizationState() -> ScreenTimeState
    func requestAuthorization() async -> Bool
    func startLockdown()
    func endLockdown()
    var hasSelection: Bool { get }
    /// Opaque encoded FamilyActivitySelection so callers can stay framework-free.
    func selectionData() -> Data?
    func saveSelection(data: Data)
}

enum SleepScreenTime {
    static let selectionKey = "sulav.lock.selection.v1"

    static func makeDefault() -> ScreenTimeControlling {
        ScreenTimeService()
    }

    static func decodeSelection(_ data: Data?) -> FamilyActivitySelection {
        guard let data, let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else {
            return FamilyActivitySelection()
        }
        return selection
    }

    static func encodeSelection(_ selection: FamilyActivitySelection) -> Data? {
        try? JSONEncoder().encode(selection)
    }
}

final class ScreenTimeService: ScreenTimeControlling {
    private let store = ManagedSettingsStore()
    private let center = AuthorizationCenter.shared

    var isSupported: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return true
        #endif
    }

    func authorizationState() -> ScreenTimeState {
        guard isSupported else { return .unavailable }
        return center.authorizationStatus == .approved ? .authorized : .notAuthorized
    }

    func requestAuthorization() async -> Bool {
        guard isSupported else { return false }
        do {
            try await center.requestAuthorization(for: .individual)
            AppLog.app.info("Requested Family Controls authorization")
            return center.authorizationStatus == .approved
        } catch {
            AppLog.app.error("Family Controls authorization failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func startLockdown() {
        guard isSupported else { return }
        let selection = SleepScreenTime.decodeSelection(selectionData())
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty
            ? nil
            : .specific(selection.categoryTokens)
        AppLog.app.info("Sleep lockdown applied (\(selection.applicationTokens.count) apps)")
    }

    func endLockdown() {
        guard isSupported else { return }
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        AppLog.app.info("Sleep lockdown cleared")
    }

    var hasSelection: Bool {
        let selection = SleepScreenTime.decodeSelection(selectionData())
        return !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty
    }

    func selectionData() -> Data? {
        UserDefaults.standard.data(forKey: SleepScreenTime.selectionKey)
    }

    func saveSelection(data: Data) {
        UserDefaults.standard.set(data, forKey: SleepScreenTime.selectionKey)
    }
}

// MARK: - Lockdown settings UI

struct LockdownSettingsView: View {
    var store: SleepStore

    @Environment(\.dismiss) private var dismiss
    @State private var selection = FamilyActivitySelection()
    @State private var showPicker = false
    @State private var enabled = false
    @State private var requesting = false

    var body: some View {
        LiquidSheetContainer {
            Text("Sleep lockdown")
                .font(SleepFont.title(20))
                .foregroundStyle(SleepColor.ink)

            switch store.screenTimeState {
            case .unavailable:
                infoBlock(
                    title: "Available on device",
                    body: "Screen Time app-blocking needs a real iPhone and Apple's Family Controls capability. Everything else works here."
                )
            default:
                Text("When you tap Sleep Now, the apps you choose are blocked until you wake. Calls and emergencies always work.")
                    .font(SleepFont.body(14))
                    .foregroundStyle(SleepColor.muted)
                    .lineSpacing(3)

                Toggle(isOn: $enabled) {
                    Text("Lock distracting apps while asleep")
                        .font(SleepFont.body(16))
                        .foregroundStyle(SleepColor.dim)
                }
                .tint(SleepColor.amber)
                .onChange(of: enabled) { _, on in
                    Haptics.soft()
                    Task {
                        requesting = true
                        if on { await store.enableLockdown() } else { store.disableLockdown() }
                        enabled = store.lockdownEnabled
                        requesting = false
                    }
                }

                Button {
                    showPicker = true
                } label: {
                    HStack {
                        Text("Choose apps to lock")
                            .font(SleepFont.body(16))
                            .foregroundStyle(SleepColor.dim)
                        Spacer()
                        Text(selectionSummary)
                            .font(SleepFont.body(14))
                            .foregroundStyle(SleepColor.muted)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(SleepColor.faint)
                    }
                    .padding(.vertical, SleepSpacing.sm)
                }
                .buttonStyle(.plain)
            }

            LiquidPrimaryButton(title: "Done", systemImage: "checkmark") { dismiss() }
        }
        .familyActivityPicker(isPresented: $showPicker, selection: $selection)
        .onChange(of: selection) { _, newValue in
            if let data = SleepScreenTime.encodeSelection(newValue) {
                store.saveAppSelection(data)
            }
        }
        .onAppear {
            selection = SleepScreenTime.decodeSelection(store.appSelectionData())
            enabled = store.lockdownEnabled
        }
    }

    private var selectionSummary: String {
        let count = selection.applicationTokens.count + selection.categoryTokens.count
        return count == 0 ? "None" : "\(count) selected"
    }

    private func infoBlock(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: SleepSpacing.sm) {
            Text(title).font(SleepFont.title(17)).foregroundStyle(SleepColor.ink)
            Text(body).font(SleepFont.body(14)).foregroundStyle(SleepColor.muted).lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
