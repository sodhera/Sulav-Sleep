import SwiftUI
import FamilyControls
import ManagedSettings
import DeviceActivity

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
    /// Schedules a DeviceActivityMonitor interval that only *clears* the shield
    /// — at the scheduled wake time, or after `maxHours` — even if the app
    /// isn't foregrounded. The shield itself is only ever applied by
    /// `startLockdown()`, called when the user taps Sleep Now.
    func scheduleLockdown(bedtimeMinutes: Int, wakeMinutes: Int, maxHours: Int)
    func cancelScheduledLockdown()
    var hasSelection: Bool { get }
    /// Opaque encoded FamilyActivitySelection so callers can stay framework-free.
    func selectionData() -> Data?
    func saveSelection(data: Data)
}

enum SleepScreenTime {
    static let selectionKey = SleepLockdownSelection.selectionKey

    static func makeDefault() -> ScreenTimeControlling {
        ScreenTimeService()
    }

    static func decodeSelection(_ data: Data?) -> FamilyActivitySelection {
        SleepLockdownSelection.decode(data)
    }

    static func encodeSelection(_ selection: FamilyActivitySelection) -> Data? {
        SleepLockdownSelection.encode(selection)
    }
}

final class ScreenTimeService: ScreenTimeControlling {
    private let store = ManagedSettingsStore()
    private let center = AuthorizationCenter.shared
    private let deviceActivityCenter = DeviceActivityCenter()

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

    func scheduleLockdown(bedtimeMinutes: Int, wakeMinutes: Int, maxHours: Int) {
        guard isSupported else { return }
        let selection = SleepScreenTime.decodeSelection(selectionData())
        let schedule = DeviceActivitySchedule(
            intervalStart: dateComponents(fromMinutes: bedtimeMinutes),
            intervalEnd: dateComponents(fromMinutes: wakeMinutes),
            repeats: true
        )
        let event = DeviceActivityEvent(
            applications: selection.applicationTokens,
            categories: selection.categoryTokens,
            threshold: DateComponents(hour: maxHours)
        )
        do {
            try deviceActivityCenter.startMonitoring(
                sleepActivityName,
                during: schedule,
                events: [sleepEventName: event]
            )
            AppLog.app.info("Scheduled sleep lockdown \(bedtimeMinutes)->\(wakeMinutes), cap \(maxHours)h")
        } catch {
            AppLog.app.error("Failed to schedule sleep lockdown: \(error.localizedDescription, privacy: .public)")
        }
    }

    func cancelScheduledLockdown() {
        guard isSupported else { return }
        deviceActivityCenter.stopMonitoring([sleepActivityName])
    }

    private func dateComponents(fromMinutes minutes: Int) -> DateComponents {
        DateComponents(hour: (minutes / 60) % 24, minute: minutes % 60)
    }

    var hasSelection: Bool {
        let selection = SleepScreenTime.decodeSelection(selectionData())
        return !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty
    }

    /// Stored in the App Group so the DeviceActivityMonitor extension can read
    /// it when applying the scheduled shield in the background.
    func selectionData() -> Data? {
        SleepLockdownSelection.groupDefaults()?.data(forKey: SleepScreenTime.selectionKey)
    }

    func saveSelection(data: Data) {
        SleepLockdownSelection.groupDefaults()?.set(data, forKey: SleepScreenTime.selectionKey)
    }
}

// MARK: - Store convenience

// Lives here so FamilyControls stays out of the view layer that only needs a
// count for the "Blocked apps" settings row.
extension SleepStore {
    var lockdownSelectionCount: Int {
        let selection = SleepScreenTime.decodeSelection(appSelectionData())
        return selection.applicationTokens.count + selection.categoryTokens.count
    }

    /// Human-readable summary of the lockdown selection for settings rows.
    /// Shows "2 apps, 1 category" when categories are involved so the user
    /// sees a count that matches what the system picker actually chose.
    var lockdownSelectionSummary: String {
        guard screenTimeState != .unavailable else { return "On device only" }
        guard lockdownEnabled else { return "Off" }
        let count = lockdownSelectionCount
        if count == 0 { return "Choose apps" }
        return "Apps selected ✓"
    }
}

// MARK: - Blocked apps preview (Profile block)

/// Compact, tappable lockdown summary for the Profile screen: a section label
/// above an interactive glass row (containers are reserved for tappable
/// controls, and this is one — the glass is what says "you can press this").
/// With a selection it previews the chosen app icons (rendered by the system
/// from opaque `ApplicationToken`s, which we can't inspect); before one it
/// shows a warm lock glyph and an invitation. The caller wraps it in a
/// NavigationLink to `BlockedAppsScreen` for the full picker + options. Lives
/// here so FamilyControls stays out of the general view layer.
struct BlockedAppsPreview: View {
    var store: SleepStore

    private var selection: FamilyActivitySelection {
        SleepScreenTime.decodeSelection(store.appSelectionData())
    }

    var body: some View {
        let appTokens = Array(selection.applicationTokens)
        let catTokens = Array(selection.categoryTokens)
        let hasSelection = !appTokens.isEmpty || !catTokens.isEmpty

        return VStack(alignment: .leading, spacing: SleepSpacing.md) {
            Text("Blocked while you sleep").sectionLabel()

            HStack(spacing: SleepSpacing.lg) {
                content(appTokens: appTokens, catTokens: catTokens, hasSelection: hasSelection)
                Spacer(minLength: SleepSpacing.sm)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SleepColor.faint)
            }
            .padding(SleepSpacing.lg)
            .contentShape(RoundedRectangle(cornerRadius: SleepRadius.lg, style: .continuous))
            .liquidGlass(cornerRadius: SleepRadius.lg, interactive: true)
            .overlay {
                RoundedRectangle(cornerRadius: SleepRadius.lg, style: .continuous)
                    .stroke(SleepColor.border, lineWidth: 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func content(appTokens: [ApplicationToken], catTokens: [ActivityCategoryToken], hasSelection: Bool) -> some View {
        if store.screenTimeState == .unavailable {
            glyphRow(
                icon: "iphone.slash",
                iconColor: SleepColor.muted,
                title: "Needs a real iPhone"
            )
        } else if !store.lockdownEnabled || !hasSelection {
            glyphRow(
                icon: "lock.fill",
                iconColor: SleepColor.amber,
                title: "Choose apps to block"
            )
        } else {
            VStack(alignment: .leading, spacing: SleepSpacing.md) {
                HStack(spacing: SleepSpacing.md) {
                    ForEach(appTokens.prefix(6), id: \.self) { token in
                        Label(token)
                            .labelStyle(.iconOnly)
                            .font(.system(size: 30))
                            .frame(width: 34, height: 34)
                    }
                    // Categories contain many apps whose icons Apple
                    // doesn't expose, so we show "+more" whenever
                    // categories are selected, plus any overflow apps.
                    let overflow = max(0, appTokens.count - 6)
                    if catTokens.count > 0 || overflow > 0 {
                        Text("+more")
                            .font(SleepFont.body(15))
                            .foregroundStyle(SleepColor.muted)
                    }
                }

                Text("Lock when you sleep")
                    .font(SleepFont.body(13))
                    .foregroundStyle(SleepColor.muted)
            }
        }
    }

    /// Shared no-selection layout: a warm glyph in a soft circle beside one
    /// short line — no explanatory copy; the row itself is the invitation.
    private func glyphRow(icon: String, iconColor: Color, title: String) -> some View {
        HStack(spacing: SleepSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: 40, height: 40)
                .background { Circle().fill(SleepColor.glassWarm) }

            Text(title)
                .font(SleepFont.title(16))
                .foregroundStyle(SleepColor.ink)
        }
    }
}

// MARK: - Blocked apps screen (pushed from Profile)

struct BlockedAppsScreen: View {
    var store: SleepStore

    @State private var selection = FamilyActivitySelection()
    @State private var showPicker = false
    @State private var enabled = false
    @State private var maxHours = 6

    var body: some View {
        SceneScreen {
            SubpageHeader(
                title: "Blocked apps",
                subtitle: "When you tap Sleep Now, the apps you choose stay locked until you wake up. Calls and emergencies always work."
            )

            switch store.screenTimeState {
            case .unavailable:
                infoBlock(
                    title: "Available on device",
                    body: "Screen Time app-blocking needs a real iPhone and Apple's Family Controls capability. Everything else works here."
                )
                .padding(.top, SleepSpacing.huge)
            default:
                VStack(alignment: .leading, spacing: 0) {
                    Toggle(isOn: $enabled) {
                        Text("Block these apps while I sleep")
                            .font(SleepFont.body(16))
                            .foregroundStyle(SleepColor.dim)
                    }
                    .tint(SleepColor.amber)
                    .padding(.vertical, SleepSpacing.md)
                    .onChange(of: enabled) { _, on in
                        Haptics.soft()
                        Task {
                            if on { await store.enableLockdown() } else { store.disableLockdown() }
                            enabled = store.lockdownEnabled
                        }
                    }

                    Rectangle().fill(SleepColor.hairline).frame(height: 1)

                    Button {
                        showPicker = true
                    } label: {
                        HStack {
                            Text("Choose apps")
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
                        .padding(.vertical, SleepSpacing.lg)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty {
                        // The chosen apps and categories, rendered by the
                        // system (tokens are opaque) so the user sees exactly
                        // what locks.
                        VStack(alignment: .leading, spacing: SleepSpacing.md) {
                            ForEach(Array(selection.applicationTokens), id: \.self) { token in
                                Label(token)
                                    .labelStyle(.titleAndIcon)
                                    .font(SleepFont.body(15))
                                    .foregroundStyle(SleepColor.dim)
                            }
                            ForEach(Array(selection.categoryTokens), id: \.self) { token in
                                Label(token)
                                    .labelStyle(.titleAndIcon)
                                    .font(SleepFont.body(15))
                                    .foregroundStyle(SleepColor.dim)
                            }
                        }
                        .padding(.bottom, SleepSpacing.lg)
                    }

                    Rectangle().fill(SleepColor.hairline).frame(height: 1)

                    Stepper(value: $maxHours, in: 1...12) {
                        Text("Unlock after \(maxHours)h even if I don't wake up")
                            .font(SleepFont.body(15))
                            .foregroundStyle(SleepColor.dim)
                    }
                    .tint(SleepColor.amber)
                    .padding(.vertical, SleepSpacing.md)
                    .onChange(of: maxHours) { _, hours in store.setLockdownMaxHours(hours) }
                }
                .padding(.top, SleepSpacing.xl)
            }
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
            maxHours = store.lockdownMaxHours
        }
    }

    private var selectionSummary: String {
        let apps = selection.applicationTokens.count
        let cats = selection.categoryTokens.count
        if apps == 0 && cats == 0 { return "None" }
        return "Apps selected ✓"
    }

    private func infoBlock(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: SleepSpacing.sm) {
            Text(title).font(SleepFont.title(17)).foregroundStyle(SleepColor.ink)
            Text(body).font(SleepFont.body(14)).foregroundStyle(SleepColor.muted).lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
