import SwiftUI
import FamilyControls
import ManagedSettings
import DeviceActivity
import UserNotifications

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
    /// Shields the chosen apps for a session the user just started. Nothing is
    /// armed to undo it: the shield comes down when the session ends, via
    /// `endLockdown()`.
    func startLockdown()
    func endLockdown()
    /// Schedules a DeviceActivityMonitor interval around the bedtime→wake
    /// window. At interval start (bedtime), the monitor extension applies the
    /// shield in the pre-sleep phase. At interval end (wake time) the monitor
    /// clears both the shield and the phase — even if the app isn't
    /// foregrounded — *unless a session is running*, in which case the shield
    /// outlasts the window and only waking lifts it.
    func scheduleLockdown(bedtimeMinutes: Int, wakeMinutes: Int)
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

    // MARK: - Naming a selection
    //
    // Both surfaces that describe the lockdown selection — Profile's preview
    // card and the Blocked apps detail row — count **apps and categories
    // separately**, because they are not the same unit. A category is a whole
    // shelf of apps the user never has to enumerate, and folding it into one
    // total made "an entire category" read as "1 chosen", i.e. indistinguishable
    // from picking a single app. Kept together here so the two surfaces can't
    // drift apart on the wording.

    /// Plural-aware "N categories".
    private static func categoryPhrase(_ count: Int) -> String {
        count == 1 ? "1 category" : "\(count) categories"
    }

    /// Plural-aware "N apps".
    private static func appPhrase(_ count: Int) -> String {
        count == 1 ? "1 app" : "\(count) apps"
    }

    /// The Profile card's caption under the icon row. Names the selection
    /// only when a category is in it — with apps alone the icons already say
    /// what locks, and a count would just restate them.
    static func selectionCaption(apps: Int, categories: Int) -> String {
        guard categories > 0 else { return "Blocked while you sleep" }
        let subject = apps > 0
            ? "\(appPhrase(apps)) and \(categoryPhrase(categories))"
            : categoryPhrase(categories)
        return "\(subject) blocked while you sleep"
    }

    // MARK: - Locked-for-the-night copy
    //
    // Three surfaces say the same thing when the lockdown settings are closed
    // (Profile's card caption, the Settings row's value, the screen itself if
    // the shield comes up while it's open), so the sentence lives once. It
    // names *when it opens again* rather than what's forbidden: the answer to
    // "why can't I tap this" is a time, not a rule.
    //
    // "until morning" covers both phases honestly — the pre-sleep shield is
    // cleared by the monitor at wake time whether or not a session was ever
    // started, and an active session ends when the user wakes.

    /// Caption under the Profile card's icon row while the lock holds.
    static let lockedCaption = "Locked until morning"
    /// Trailing value on the Settings row while the lock holds.
    static let lockedSettingsValue = "Locked until morning"

    /// The Blocked apps detail row's trailing value.
    static func selectionSummary(apps: Int, categories: Int) -> String {
        switch (apps, categories) {
        case (0, 0): "None"
        case (let a, 0): appPhrase(a)
        case (0, let c): categoryPhrase(c)
        case (let a, let c): "\(appPhrase(a)), \(categoryPhrase(c))"
        }
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
        SleepLockdownSelection.clearSnoozeWindow()
        cancelSnoozeEndNotification()
        // Retire a cap left armed by a build that predates the session-anchored
        // rule. Cheap, idempotent, and this is the moment it matters: without
        // it, the very first night after updating could still expire on the old
        // timer. Harmless when there is nothing to stop.
        deviceActivityCenter.stopMonitoring([sleepCapActivityName])
        AppLog.app.info("Sleep lockdown applied as active (\(selection.applicationTokens.count) apps)")
    }

    func endLockdown() {
        guard isSupported else { return }
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        SleepLockdownSelection.clearPhase()
        cancelSnoozeEndNotification()
        // Waking (or cancelling) is the one thing that ends a lockdown, so this
        // is also where any legacy cap is retired for good. Left running, a
        // stale one would fire mid-way through some later night and drop that
        // shield — the exact behaviour this change exists to remove.
        deviceActivityCenter.stopMonitoring([sleepCapActivityName])
        AppLog.app.info("Sleep lockdown cleared")
    }

    func reapplyShieldIfSnoozeExpired() {
        guard isSupported, SleepLockdownSelection.currentPhase() != nil else { return }
        // The slow door is the same shape of grant as a snooze — the shield
        // lifted for a fixed span — so it lapses through the same layers.
        let snoozeLapsed = SleepLockdownSelection.snoozeHasExpired()
        let doorLapsed = SleepLockdownSelection.doorHasExpired()
        guard snoozeLapsed || doorLapsed else { return }
        let selection = SleepScreenTime.decodeSelection(selectionData())
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty
            ? nil
            : .specific(selection.categoryTokens)
        SleepLockdownSelection.clearSnoozeWindow()
        SleepLockdownSelection.clearDoor()
        deviceActivityCenter.stopMonitoring([sleepSnoozeActivityName])
        cancelSnoozeEndNotification()
        AppLog.app.info("\(snoozeLapsed ? "Snooze" : "Door") expired — shield re-applied")
    }

    /// The shield-action extension schedules a "five minutes are up" nudge when
    /// it grants a snooze. Once that snooze is over — however it ended — the
    /// nudge is stale, and firing it after the user is already back under the
    /// shield (or already asleep) is just noise.
    private func cancelSnoozeEndNotification() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["sulav.sleep.snooze-over"])
    }

    func scheduleLockdown(bedtimeMinutes: Int, wakeMinutes: Int) {
        guard isSupported else { return }
        // Mirrored into the App Group so the shield extension can count the
        // hours left until the alarm without reaching into the app's profile.
        SleepLockdownSelection.setBedtimeMinutes(bedtimeMinutes)
        SleepLockdownSelection.setWakeMinutes(wakeMinutes)
        let selection = SleepScreenTime.decodeSelection(selectionData())
        let schedule = DeviceActivitySchedule(
            intervalStart: dateComponents(fromMinutes: bedtimeMinutes),
            intervalEnd: dateComponents(fromMinutes: wakeMinutes),
            repeats: true
        )
        // Only the snooze re-arms. A max-hours cap used to live here too, as a
        // `threshold: DateComponents(hour:)` event that could never fire —
        // shielded apps accrue no screen time to meter — then as a wall-clock
        // activity armed at Sleep Now. Both are gone: the shield is anchored to
        // the session now, not to any clock. See `sleepCapActivityName`.
        //
        // These are registered here, at schedule time, because the shield-action
        // extension that grants a snooze cannot reliably register anything
        // before iOS tears it down — see `sleepSnoozeEventNames`.
        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        for (index, name) in sleepSnoozeEventNames.enumerated() {
            events[name] = DeviceActivityEvent(
                applications: selection.applicationTokens,
                categories: selection.categoryTokens,
                threshold: sleepSnoozeThreshold(forSnooze: index + 1)
            )
        }
        do {
            try deviceActivityCenter.startMonitoring(
                sleepActivityName,
                during: schedule,
                events: events
            )
            AppLog.app.info("Scheduled sleep lockdown \(bedtimeMinutes)->\(wakeMinutes)")
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

/// Compact, tappable lockdown summary for the Profile screen: an interactive
/// glass row (containers are reserved for tappable controls, and this is one —
/// the glass is what says "you can press this"). With a selection it previews
/// the chosen app icons (rendered by the system from opaque
/// `ApplicationToken`s, which we can't inspect); before one it shows a warm
/// lock glyph and an invitation. The caller wraps it in a NavigationLink to
/// `BlockedAppsScreen` for the full picker + options. Lives here so
/// FamilyControls stays out of the general view layer.
///
/// **No kicker.** This carried a tracked all-caps "BLOCKED WHILE YOU SLEEP"
/// label — the loudest typographic device in the app, in the middle of the
/// screen the user reads as their calm dashboard. Per the Profile rule ("a
/// kicker earns its place only when the thing under it can't say what it is"),
/// the card now says what it is in every state: each stateline names blocking
/// itself, and the icon-preview state captions the icons with the same
/// sentence the kicker used to shout.
struct BlockedAppsPreview: View {
    var store: SleepStore
    /// Rendered while tonight's lock is in force: the caller shows the card
    /// outside a NavigationLink, and the card drops the affordances that
    /// promise a destination — the chevron and the interactive glass — while
    /// keeping the icons, which are the one thing still worth reading.
    var isLocked = false

    private var selection: FamilyActivitySelection {
        SleepScreenTime.decodeSelection(store.appSelectionData())
    }

    var body: some View {
        let appTokens = Array(selection.applicationTokens)
        let catTokens = Array(selection.categoryTokens)
        let hasSelection = !appTokens.isEmpty || !catTokens.isEmpty

        return HStack(spacing: SleepSpacing.lg) {
            content(appTokens: appTokens, catTokens: catTokens, hasSelection: hasSelection)
            Spacer(minLength: SleepSpacing.sm)
            if isLocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SleepColor.faint)
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SleepColor.faint)
            }
        }
        .padding(SleepSpacing.lg)
        .contentShape(RoundedRectangle(cornerRadius: SleepRadius.lg, style: .continuous))
        // The glass draws its own edge; no manual border on top of it.
        .liquidGlass(cornerRadius: SleepRadius.lg, interactive: !isLocked)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func content(appTokens: [ApplicationToken], catTokens: [ActivityCategoryToken], hasSelection: Bool) -> some View {
        if store.screenTimeState == .unavailable {
            glyphRow(
                icon: "iphone.slash",
                iconColor: SleepColor.muted,
                title: "Blocking needs a real iPhone"
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
                title: "App blocking is off"
            )
        } else {
            // Apps first, then categories, sharing one row budget. Categories
            // used to be left out of the icons entirely and represented by a
            // bare "+more" — so a category-only selection (a completely normal
            // choice; it's the first thing the system picker offers) rendered
            // as the word "+more" beside nothing at all, with no hint that
            // anything was actually blocked. Categories carry system icons
            // just like apps do — `BlockedAppsScreen`'s grid below has always
            // drawn them — so they belong in the preview on the same terms.
            let shownApps = appTokens.prefix(Self.previewLimit)
            let shownCats = catTokens.prefix(Self.previewLimit - shownApps.count)
            let overflow = (appTokens.count + catTokens.count) - shownApps.count - shownCats.count

            VStack(alignment: .leading, spacing: SleepSpacing.md) {
                HStack(spacing: SleepSpacing.md) {
                    ForEach(shownApps, id: \.self) { token in
                        Label(token)
                            .labelStyle(.iconOnly)
                            .font(.system(size: 30))
                            .frame(width: 34, height: 34)
                    }
                    ForEach(shownCats, id: \.self) { token in
                        Label(token)
                            .labelStyle(.iconOnly)
                            .font(.system(size: 30))
                            .frame(width: 34, height: 34)
                    }
                    // Now a real count of what didn't fit, not a stand-in for
                    // what couldn't be drawn.
                    if overflow > 0 {
                        Text("+\(overflow)")
                            .font(SleepFont.body(15))
                            .foregroundStyle(SleepColor.muted)
                    }
                }

                Text(
                    isLocked
                        ? SleepScreenTime.lockedCaption
                        : SleepScreenTime.selectionCaption(apps: appTokens.count, categories: catTokens.count)
                )
                    .font(SleepFont.body(13))
                    .foregroundStyle(SleepColor.muted)
            }
        }
    }

    /// How many icons the row shows before it starts counting instead.
    private static let previewLimit = 6

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

// MARK: - The closed-for-the-night panel

/// What a lockdown settings screen shows for as long as the lock holds: a lock
/// glyph, the shared "Locked until morning" line, and one sentence of why.
///
/// Three screens use it — Blocked apps, Sleep schedule, and the reasons — so
/// the shape and the promise ("it opens again once the night ends") can't drift
/// between them. Each passes its own `explanation`, because *why* a screen is
/// closed differs even though *when it opens* doesn't.
///
/// It replaces the controls rather than disabling them. A greyed-out toggle is
/// still an invitation to keep trying, and none of these controls has a
/// legitimate use before morning.
struct LockdownClosedPanel: View {
    let explanation: String

    var body: some View {
        VStack(alignment: .leading, spacing: SleepSpacing.md) {
            HStack(spacing: SleepSpacing.md) {
                GlassRowIcon(icon: "lock.fill")
                Text(SleepScreenTime.lockedCaption)
                    .font(SleepFont.title(16))
                    .foregroundStyle(SleepColor.ink)
            }
            Text(explanation)
                .font(SleepFont.body(14))
                .foregroundStyle(SleepColor.muted)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, SleepSpacing.huge)
    }
}

// MARK: - Blocked apps screen (pushed from Profile)

struct BlockedAppsScreen: View {
    var store: SleepStore

    @State private var selection = FamilyActivitySelection()
    @State private var showPicker = false
    @State private var blockOn = true
    @State private var hardMode = false

    var body: some View {
        SceneScreen {
            SubpageHeader(
                title: "Blocked apps",
                subtitle: store.lockdownSettingsLocked
                    ? "Tonight's block is running. What it covers can change in the morning."
                    : "Locked from Sleep Now until you wake. Calls always work."
            )

            if store.lockdownSettingsLocked {
                // Both entry points refuse to push here while the lock holds,
                // so reaching this normally is impossible; what this branch
                // actually covers is the screen being *already open* when the
                // monitor raises the pre-sleep shield at bedtime. The controls
                // are removed rather than disabled — a greyed-out toggle is
                // still an invitation to keep trying, and this one has no
                // legitimate use until morning.
                lockedPanel
            } else {
                controls
            }
        }
        .familyActivityPicker(isPresented: $showPicker, selection: $selection)
        .onChange(of: selection) { _, newValue in
            // The store refuses a mid-lockdown save too; this keeps the view's
            // own copy from drifting away from what is actually shielded.
            guard !store.lockdownSettingsLocked else { return }
            if let data = SleepScreenTime.encodeSelection(newValue) {
                store.saveAppSelection(data)
            }
        }
        .onChange(of: store.lockdownSettingsLocked) { _, locked in
            // Bedtime arriving with the system picker open: take it down with
            // the rest of the controls.
            if locked { showPicker = false }
        }
        .onAppear {
            // The foreground hook can't see a phase the monitor writes while
            // the app is already open, and this screen is exactly where that
            // matters.
            store.refreshLockdownPhase()
            selection = SleepScreenTime.decodeSelection(store.appSelectionData())
            blockOn = store.blockingEnabled
            hardMode = store.profile?.hardMode ?? false
        }
    }

    private var lockedPanel: some View {
        LockdownClosedPanel(
            explanation: "Your apps are blocked right now, so this screen is closed — changing it mid-night would just be the way out. It opens again once the night ends."
        )
    }

    /// Everything the screen offers when it is open for business. Split out
    /// of `body` so the locked branch above reads as one line.
    private var controls: some View {
        Group {
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

                    // The reasons live here rather than in general settings:
                    // this is the lockdown's own screen, and the sentences are
                    // part of the lock, not a preference.
                    NavigationLink {
                        ReasonsScreen(store: store)
                    } label: {
                        GlassRow(
                            icon: "quote.opening",
                            title: "Why you're doing this",
                            value: reasonsSummary,
                            showsChevron: true
                        )
                    }
                    .buttonStyle(.plain)

                    GlassRowDivider()

                    // Strictness the user chooses, never one the app imposes.
                    // A self-chosen constraint gets respected; the same
                    // constraint applied to someone is resented, and resentment
                    // is what uninstalls the app.
                    VStack(alignment: .leading, spacing: SleepSpacing.xs) {
                        HStack(spacing: SleepSpacing.md) {
                            GlassRowIcon(icon: "lock.shield.fill")
                            Toggle(isOn: $hardMode) {
                                Text("Hard mode")
                                    .font(SleepFont.body(16))
                                    .foregroundStyle(SleepColor.ink)
                            }
                            .tint(SleepColor.amber)
                        }
                        Text("No snooze, and the 10-minute unlock takes 3 minutes to open.")
                            .font(SleepFont.body(13))
                            .foregroundStyle(SleepColor.muted)
                            .padding(.leading, 52)
                    }
                    .padding(.vertical, SleepSpacing.md)
                    .onChange(of: hardMode) { _, on in
                        Haptics.heavy()
                        store.setHardMode(on)
                    }

                    // There was an "Unlock anyway after Nh" stepper here. It
                    // is gone, not moved: a block that expires on its own is
                    // not a block, and the hour it expired at was always the
                    // hour the user most needed it. The block now lasts as long
                    // as the session, and the slow door on the shield is the
                    // way out — a wait you choose, not a clock that runs down
                    // while you sleep.
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
    }

    private var selectionSummary: String {
        SleepScreenTime.selectionSummary(
            apps: selection.applicationTokens.count,
            categories: selection.categoryTokens.count
        )
    }

    /// "None" reads as a setting left alone; "Not written" says there is
    /// something here the user hasn't done yet.
    private var reasonsSummary: String {
        let count = store.lockReasons.count
        guard count > 0 else { return "Not written" }
        return count == 1 ? "1 reason" : "\(count) reasons"
    }
}
