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
    /// Schedules a DeviceActivityMonitor interval around the bedtime→wake
    /// window. At interval start (bedtime), the monitor extension applies the
    /// shield in the pre-sleep phase. At interval end (wake time) or when the
    /// max-hours cap is reached, the monitor clears both the shield and the
    /// phase — even if the app isn't foregrounded.
    func scheduleLockdown(bedtimeMinutes: Int, wakeMinutes: Int, maxHours: Int)
    func cancelScheduledLockdown()
    /// Puts the shield back if a "5 more minutes" snooze has run out. The
    /// timed re-arm lives in a DeviceActivity callback that a sandboxed
    /// extension isn't guaranteed to get, so the app also checks whenever it
    /// comes to the foreground — worst case the block returns when the user
    /// next opens SleepBlock rather than never.
    func reapplyShieldIfSnoozeExpired()
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
        SleepLockdownSelection.setPhase(.active)
        AppLog.app.info("Sleep lockdown applied as active (\(selection.applicationTokens.count) apps)")
    }

    func endLockdown() {
        guard isSupported else { return }
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        SleepLockdownSelection.clearPhase()
        AppLog.app.info("Sleep lockdown cleared")
    }

    func reapplyShieldIfSnoozeExpired() {
        guard isSupported,
              SleepLockdownSelection.currentPhase() != nil,
              SleepLockdownSelection.snoozeHasExpired()
        else { return }
        let selection = SleepScreenTime.decodeSelection(selectionData())
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty
            ? nil
            : .specific(selection.categoryTokens)
        SleepLockdownSelection.clearSnoozeWindow()
        deviceActivityCenter.stopMonitoring([sleepSnoozeActivityName])
        AppLog.app.info("Snooze expired — shield re-applied")
    }

    func scheduleLockdown(bedtimeMinutes: Int, wakeMinutes: Int, maxHours: Int) {
        guard isSupported else { return }
        // Mirrored into the App Group so the shield extension can say how far
        // past bedtime the user is without reaching into the app's profile.
        SleepLockdownSelection.setBedtimeMinutes(bedtimeMinutes)
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
    var lockdownSelectionSummary: String {
        guard screenTimeState != .unavailable else { return "On device only" }
        guard blockingEnabled else { return "Off" }
        let count = lockdownSelectionCount
        if count == 0 { return "None" }
        return "\(count) blocked"
    }
}

// MARK: - Screen Time permission primer

/// The full-screen ask that stands between the paywall and Main: SleepBlock
/// is an app-blocking app, and this is where the blocking gets its teeth.
/// The centerpiece is a *mock* of the iOS permission dialog with an amber
/// arrow pointing at Allow — the primer pattern: the user decides to tap
/// Allow on our screen, so the real system sheet (fired by the CTA) is a
/// formality they've already rehearsed. Granting flows straight into the
/// system app picker, so blocking is actually armed — authorization alone
/// shields nothing.
///
/// One-shot per install, never per account: the seen-marker lives in the app
/// container (`SleepPersistence.screenTimePrimerSeen`), so deleting the app
/// and signing back in — which silently drops the authorization — primes
/// again, while normal launches never re-show it. It completes on grant,
/// deny, *or* skip: nobody gets trapped at a gate, and the Blocked apps
/// screen remains the always-available fixup path.
struct ScreenTimePrimerView: View {
    var store: SleepStore

    @State private var isRequesting = false
    @State private var showPicker = false
    @State private var selection = FamilyActivitySelection()

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: SleepSpacing.md) {
                Text("One last step").sectionLabel()
                Text("Let SleepBlock put your apps to sleep")
                    .font(SleepFont.title(28))
                    .foregroundStyle(SleepColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("iOS will ask for Screen Time access — that's what locks your apps from Sleep Now until you wake. Calls always work.")
                    .font(SleepFont.body(15))
                    .foregroundStyle(SleepColor.dim)
                    .lineSpacing(4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            MockPermissionDialog()

            Spacer()
            Spacer()

            VStack(spacing: SleepSpacing.md) {
                LiquidPrimaryButton(title: "Turn on app blocking", isLoading: isRequesting) {
                    requestAccess()
                }
                Button("Not now") {
                    Haptics.heavy()
                    store.completeScreenTimePrimer()
                }
                .font(SleepFont.body(15))
                .foregroundStyle(SleepColor.dim)
                .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .padding(.horizontal, SleepSpacing.xxl)
        .padding(.bottom, SleepSpacing.xxl)
        .safeAreaPadding(.top)
        .safeAreaPadding(.bottom)
        .familyActivityPicker(isPresented: $showPicker, selection: $selection)
        .onChange(of: selection) { _, newValue in
            if let data = SleepScreenTime.encodeSelection(newValue) {
                store.saveAppSelection(data)
            }
        }
        .onChange(of: showPicker) { _, shown in
            // Picker dismissed — apps chosen or not, the primer's work is
            // done and RootView moves on to Main.
            if !shown { store.completeScreenTimePrimer() }
        }
    }

    private func requestAccess() {
        guard !isRequesting else { return }
        isRequesting = true
        Task { @MainActor in
            let granted = await store.requestScreenTimeAccess()
            isRequesting = false
            if granted {
                // Straight into choosing what locks, while the intent is hot.
                showPicker = true
            } else {
                store.completeScreenTimePrimer()
            }
        }
    }
}

/// A stylized miniature of the system permission dialog, so the real one is
/// recognized on sight. Deliberately *not* Liquid Glass — it depicts iOS
/// chrome, not one of the app's own controls. The real sheet's affirmative is
/// "Continue" (left); iOS makes "Don't Allow" (right) the blue default, and the
/// mock keeps that blue on "Don't Allow": the primer's whole job is
/// pattern-matching against the sheet iOS is about to show (the one sanctioned
/// exception to the no-blue-identity rule; see DESIGN.md). Decorative only,
/// hidden from accessibility — the headline above carries the meaning.
private struct MockPermissionDialog: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrowLift = false

    var body: some View {
        VStack(spacing: SleepSpacing.lg) {
            VStack(spacing: 0) {
                VStack(spacing: SleepSpacing.md) {
                    Image(systemName: "hourglass")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(SleepColor.dim)
                    Text("\u{201C}SleepBlock\u{201D} Would Like to Access Screen Time")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SleepColor.ink)
                        .multilineTextAlignment(.center)
                    // Greeked body lines — the mock gestures at the sheet's
                    // legalese without pretending to quote it.
                    VStack(spacing: 5) {
                        Capsule().fill(SleepColor.hairline).frame(width: 170, height: 6)
                        Capsule().fill(SleepColor.hairline).frame(width: 128, height: 6)
                    }
                    .padding(.top, 2)
                }
                .padding(SleepSpacing.xl)

                Rectangle().fill(SleepColor.hairline).frame(height: 1)

                HStack(spacing: 0) {
                    Text("Continue")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(SleepColor.ink)
                        .frame(maxWidth: .infinity, minHeight: 46)
                    Rectangle().fill(SleepColor.hairline).frame(width: 1, height: 46)
                    Text("Don't Allow")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(red: 0.04, green: 0.52, blue: 1.0))
                        .frame(maxWidth: .infinity, minHeight: 46)
                }
            }
            .frame(maxWidth: 300)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(SleepColor.navy.opacity(0.94))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(SleepColor.border, lineWidth: 1)
            }

            // The amber arrow under the Continue half — the one instruction.
            // iOS makes "Don't Allow" the blue default here, so the affirmative
            // is the grey "Continue" on the left; the guidance must point there.
            HStack(spacing: 0) {
                VStack(spacing: SleepSpacing.sm) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(SleepColor.amber)
                        .offset(y: arrowLift ? -3 : 3)
                    Text("Tap Continue")
                        .font(SleepFont.label(13))
                        .foregroundStyle(SleepColor.amber)
                }
                .frame(maxWidth: .infinity)
                Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
            }
            .frame(maxWidth: 300)
        }
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                arrowLift = true
            }
        }
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
            // The glass draws its own edge; no manual border on top of it.
            .liquidGlass(cornerRadius: SleepRadius.lg, interactive: true)
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
        } else if !hasSelection {
            glyphRow(
                icon: "lock.fill",
                iconColor: SleepColor.amber,
                title: "Choose apps to block"
            )
        } else if !store.blockingEnabled {
            glyphRow(
                icon: "lock.open",
                iconColor: SleepColor.muted,
                title: "Blocking is off"
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
    @State private var blockOn = true
    @State private var maxHours = 6

    var body: some View {
        SceneScreen {
            SubpageHeader(
                title: "Blocked apps",
                subtitle: "Locked from Sleep Now until you wake. Calls always work."
            )

            switch store.screenTimeState {
            case .unavailable:
                HStack(spacing: SleepSpacing.md) {
                    GlassRowIcon(icon: "iphone.slash", color: SleepColor.muted)
                    Text("Needs a real iPhone")
                        .font(SleepFont.title(16))
                        .foregroundStyle(SleepColor.ink)
                }
                .padding(.top, SleepSpacing.huge)
            default:
                GlassGroup {
                    // The user's explicit control: on by default (choosing
                    // apps is the commitment), off keeps the selection but
                    // blocks nothing until it's switched back on.
                    HStack(spacing: SleepSpacing.md) {
                        GlassRowIcon(icon: "moon.zzz.fill")
                        Toggle(isOn: $blockOn) {
                            Text("Block while you sleep")
                                .font(SleepFont.body(16))
                                .foregroundStyle(SleepColor.ink)
                        }
                        .tint(SleepColor.amber)
                    }
                    .padding(.vertical, SleepSpacing.md)
                    .frame(minHeight: 52)
                    .onChange(of: blockOn) { _, on in
                        Haptics.heavy()
                        store.setBlockingEnabled(on)
                    }

                    GlassRowDivider()

                    Button {
                        Haptics.heavy()
                        // Screen Time authorization is requested lazily, right
                        // when it's needed: the picker is useless without it.
                        Task {
                            if await store.requestScreenTimeAccess() { showPicker = true }
                        }
                    } label: {
                        GlassRow(
                            icon: "square.grid.2x2.fill",
                            title: "Apps",
                            value: selectionSummary,
                            showsChevron: true
                        )
                    }
                    .buttonStyle(.plain)

                    GlassRowDivider()

                    // Safety valve: the shield always drops after this many
                    // hours, even if the user never taps wake.
                    HStack(spacing: SleepSpacing.md) {
                        GlassRowIcon(icon: "alarm.fill")
                        Text("Unlock anyway after")
                            .font(SleepFont.body(16))
                            .foregroundStyle(SleepColor.ink)
                        Spacer(minLength: SleepSpacing.md)
                        Text("\(maxHours)h")
                            .font(SleepFont.label(16))
                            .foregroundStyle(SleepColor.amber)
                            .monospacedDigit()
                        Stepper("", value: $maxHours, in: 1...12)
                            .labelsHidden()
                            .tint(SleepColor.amber)
                            .onChange(of: maxHours) { _, hours in
                                Haptics.heavy()
                                store.setLockdownMaxHours(hours)
                            }
                    }
                    .padding(.vertical, SleepSpacing.md)
                    .frame(minHeight: 52)
                }
                .padding(.top, SleepSpacing.xl)

                // The chosen apps and categories, rendered by the system
                // (tokens are opaque, so Apple draws them) as an icon grid —
                // the user sees exactly what locks, without a text list.
                if !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 44), spacing: SleepSpacing.md)],
                        spacing: SleepSpacing.md
                    ) {
                        ForEach(Array(selection.applicationTokens), id: \.self) { token in
                            Label(token)
                                .labelStyle(.iconOnly)
                                .font(.system(size: 34))
                                .frame(width: 44, height: 44)
                        }
                        ForEach(Array(selection.categoryTokens), id: \.self) { token in
                            Label(token)
                                .labelStyle(.iconOnly)
                                .font(.system(size: 34))
                                .frame(width: 44, height: 44)
                        }
                    }
                    .padding(.top, SleepSpacing.xl)
                }
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
            blockOn = store.blockingEnabled
            maxHours = store.lockdownMaxHours
        }
    }

    private var selectionSummary: String {
        let count = selection.applicationTokens.count + selection.categoryTokens.count
        if count == 0 { return "None" }
        return "\(count) chosen"
    }
}
