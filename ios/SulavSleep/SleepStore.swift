import Foundation
import Observation
import WidgetKit
#if canImport(UIKit)
import UIKit
#endif

@Observable
final class SleepStore {
    /// Nights the user logged in-app. Local source of truth, always persisted.
    var sessions: [SleepSession] = []
    /// Nights imported from Apple Health. Refreshed at runtime, never persisted.
    var importedHealthSessions: [SleepSession] = []
    var profile: Profile?
    var activeSession: ActiveSleepSession?
    var selectedTab: AppTab = .home
    var isImportingHealth = false
    /// The signed-in account, or `nil` before sign-in / after sign-out.
    var account: AppAccount?
    /// False until the initial session-restore check completes, so the UI can
    /// show a brief neutral state instead of flashing the auth screen.
    var isAuthReady = false
    var authErrorMessage: String?
    /// Whether `authErrorMessage` is guidance about a normal next step (e.g.
    /// "tap the confirmation link we emailed you") rather than a failure — the
    /// auth screen tones down the color for these instead of showing red.
    var authMessageIsNotice = false
    var isAuthenticating = false
    /// Whether the most recent successful sign-in created a brand-new account,
    /// vs. matching an existing one (e.g. Apple/Google reusing an already-
    /// registered identity). Read once, right after `isAuthenticated` flips, by
    /// the onboarding flow to decide whether to keep or discard the
    /// questionnaire answers just collected. See `OnboardingQuestionsView`.
    var lastSignInWasNewAccount = false
    /// Revision counter bumped every time the lockdown app selection changes.
    /// Views that read `appSelectionData()` also read this, which creates an
    /// `@Observable` tracking dependency so SwiftUI re-renders on changes.
    private(set) var appSelectionRevision = 0

    private let persistence: SleepPersistence
    private let health: SleepHealthProviding
    private let screenTime: ScreenTimeControlling
    private let auth: AuthProviding

    init(
        persistence: SleepPersistence = .shared,
        health: SleepHealthProviding? = nil,
        screenTime: ScreenTimeControlling? = nil,
        auth: AuthProviding? = nil
    ) {
        self.persistence = persistence
        self.health = health ?? SleepHealth.makeDefault()
        self.screenTime = screenTime ?? SleepScreenTime.makeDefault()
        self.auth = auth ?? SulavAuth.makeDefault()
        reload()
        Task { [weak self] in await self?.restoreSession() }
    }

    // MARK: - Derived state

    var isOnboarded: Bool { profile?.onboarded == true }
    var isAuthenticated: Bool { account != nil }

    /// The single, deduplicated history shown across the app. Health wins over a
    /// local record for the same night so a night we wrote to Health isn't
    /// counted twice. See `SleepMerge`.
    var displaySessions: [SleepSession] {
        SleepMerge.merge(local: sessions, health: importedHealthSessions)
    }

    var latestSession: SleepSession? { displaySessions.last }

    var targetMinutes: Int {
        guard let profile else { return 8 * 60 }
        return SleepMath.windowMinutes(bedtime: profile.bedtime, wakeTime: profile.wakeTime)
    }

    var onTrackStreak: Int {
        // A night is on track when it reaches at least 85% of the sleep
        // target — the same bar the retired 0–100 score set at "score ≥ 80".
        var streak = 0
        for session in displaySessions.reversed() {
            guard session.durationMinutes * 100 >= targetMinutes * 85 else { break }
            streak += 1
        }
        return streak
    }

    var healthSyncState: HealthSyncState {
        guard health.isAvailable else { return .unavailable }
        return profile?.healthSyncEnabled == true ? .connected : .notConnected
    }

    /// Whether to show the in-app "connect Apple Health" prompt (Profile). Only
    /// when Health is available, not yet connected, and the user hasn't waved
    /// the prompt off.
    var shouldPromptHealthConnect: Bool {
        healthSyncState == .notConnected && profile?.healthPromptDismissed != true
    }

    var screenTimeState: ScreenTimeState { screenTime.authorizationState() }
    /// The user's "Block while you sleep" switch (Blocked apps screen). On by
    /// default — this is a preference, never an authorization snapshot.
    var blockingEnabled: Bool { profile?.blockDuringSleep ?? true }
    var lockdownMaxHours: Int { profile?.lockdownMaxHours ?? 6 }

    /// Whether tapping Sleep Now will actually shield anything tonight:
    /// blocking switched on, Screen Time authorized (checked live, so a stale
    /// stored flag can never contradict reality), and at least one
    /// app/category chosen. This is the single source of truth for "are apps
    /// blocked" across Home, the confirmation panel, and the profile preview.
    var willLockDuringSleep: Bool {
        blockingEnabled && screenTimeState == .authorized && lockdownSelectionCount > 0
    }

    // MARK: - Lifecycle

    func reload(refreshWidget: Bool = false) {
        let snapshot = persistence.load()
        profile = snapshot.profile
        sessions = snapshot.sessions
        activeSession = snapshot.activeSession
        account = persistence.loadAccount()
        if refreshWidget {
            updateWidgetSoon()
        }
    }

    /// Publish a compact summary to the App Group and refresh the home-screen
    /// widget. Called on every change to displayed history.
    private func updateWidget() {
        let recent = Array(displaySessions.suffix(7)).map {
            WidgetNight(end: $0.end, durationMinutes: $0.durationMinutes)
        }
        let summary = SleepWidgetSummary(
            nights: recent,
            latestDurationMinutes: latestSession?.durationMinutes,
            streak: onTrackStreak,
            targetMinutes: targetMinutes,
            bedtimeMinutes: profile?.bedtime,
            wakeMinutes: profile?.wakeTime,
            asleepSince: activeSession?.start,
            updated: Date()
        )
        SleepWidgetStore.save(summary)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func updateWidgetSoon() {
        DispatchQueue.main.async { [weak self] in
            self?.updateWidget()
        }
    }

    /// Called when the app becomes active. Pulls fresh nights from Health if the
    /// user has connected it.
    @MainActor
    func refreshHealthIfEnabled() async {
        guard profile?.healthSyncEnabled == true else { return }
        await refreshHealth()
    }

    // MARK: - Onboarding

    func completeOnboarding(name: String, bedtime: Int, wakeTime: Int, connectHealth: Bool, struggles: [String] = []) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        profile = Profile(
            name: trimmed.isEmpty ? "Friend" : trimmed,
            bedtime: bedtime,
            wakeTime: wakeTime,
            onboarded: true,
            healthSyncEnabled: false,
            sleepStruggles: struggles
        )
        // No seeding: the history is empty until the user logs a real night or
        // connects Apple Health.
        sessions = []
        importedHealthSessions = []
        activeSession = nil
        persist()
        AppLog.store.info("Onboarding complete (connectHealth=\(connectHealth))")
        if connectHealth {
            performAfterStateChange { [weak self] in
                Task { await self?.enableHealthSync() }
            }
        }
        syncRemoteProfile()
    }

    // MARK: - Auth

    /// Checks for a Keychain-restored Supabase session at launch. Runs once.
    @MainActor
    func restoreSession() async {
        // Reinstall gotcha: deleting the app wipes our container (the profile,
        // and this launch marker) but iOS keeps Keychain items — so a stale
        // Supabase session would silently sign the user back in on what looks
        // like a fresh install, dropping them onto the nameless quick-setup
        // instead of the welcome screen. Treat the first launch after install
        // as a clean slate: if the marker is missing, clear any surviving
        // Keychain session before restoring, then plant the marker.
        if !persistence.hasLaunchedBefore {
            await auth.clearLocalSession()
            persistence.markLaunched()
        }
        account = await auth.currentAccount
        if let account {
            persistAccount(account)
            persistence.saveLastAccountID(account.id)
            // Signed in but no profile on this device (e.g. a Keychain session
            // synced from another device): restore the cloud copy so the user
            // lands in the app, not back in onboarding. Runs before the ready
            // flip so onboarding never flashes — but capped so a slow network
            // can't hold the launch screen hostage; worst case the user gets
            // the quick setup they'd have gotten anyway.
            if profile == nil, let remote = await Self.withTimeout(seconds: 5, { [auth] in await auth.fetchRemoteProfile() }) {
                profile = remote.asLocalProfile
                persist(refreshWidget: false)
                AppLog.store.info("Restored profile from cloud (launch)")
            } else if persistence.cloudSeedCheckedAccountID != account.id,
                      let localCopy = RemoteProfile(profile: profile) {
                // Signed in with a local profile: make sure the account has a
                // cloud copy (accounts predating profile sync won't until they
                // sign in again otherwise). Backgrounded — never blocks launch
                // — and remembered once confirmed, so the app stays fully
                // offline at every later open instead of re-checking the
                // cloud each launch. (A launch that had to *seed* the copy
                // re-confirms on the next one before marking.)
                Task { [auth, persistence] in
                    if await auth.fetchRemoteProfile() == nil {
                        AppLog.store.info("Seeding missing cloud profile from this device")
                        await auth.saveRemoteProfile(localCopy)
                    } else {
                        persistence.markCloudSeedChecked(accountID: account.id)
                    }
                }
            }
        } else {
            clearPersistedAccount()
        }
        isAuthReady = true
    }

    @MainActor
    func signInWithApple(idToken: String, nonce: String) async {
        await performAuth { try await self.auth.signInWithApple(idToken: idToken, nonce: nonce) }
    }

    @MainActor
    func signInWithGoogle() async {
        await performAuth { try await self.auth.signInWithGoogle() }
    }

    @MainActor
    func signUpEmail(email: String, password: String) async {
        await performAuth { try await self.auth.signUp(email: email, password: password) }
    }

    @MainActor
    func signInEmail(email: String, password: String) async {
        await performAuth { try await self.auth.signIn(email: email, password: password) }
    }

    @MainActor
    func signOut() async {
        await auth.signOut()
        account = nil
        authErrorMessage = nil
        authMessageIsNotice = false
        clearPersistedAccount()
        AppLog.store.info("Signed out")
    }

    /// Step 1 of account deletion: delete the Supabase user server-side (via the
    /// `delete-account` Edge Function, which uses the service role to purge the
    /// `auth.users` row and everything cascading off it). Returns `nil` on
    /// success, or a user-facing error message on failure — in which case
    /// nothing local is touched, so the user can retry. Kept separate from the
    /// local wipe so the caller can dismiss the settings cover *before*
    /// `finalizeAccountDeletion` nils `account` and swaps the root to onboarding
    /// (same teardown-ordering reason as `signOut`). See `docs/auth-setup.md`.
    @MainActor
    func deleteAccountRemotely() async -> String? {
        authErrorMessage = nil
        do {
            try await auth.deleteAccount()
            return nil
        } catch let error as AuthError {
            AppLog.store.error("Account deletion failed: \(error.message, privacy: .public)")
            authErrorMessage = error.message
            return error.message
        } catch {
            let message = AuthError.unknown(error.localizedDescription).message
            AppLog.store.error("Account deletion failed: \(error.localizedDescription, privacy: .public)")
            authErrorMessage = message
            return message
        }
    }

    /// Step 2: wipe every on-device trace after a confirmed remote deletion —
    /// profile, logged nights, imported Health copies, any active session, and
    /// the cached account. Nilling `account` swaps the root to onboarding, so
    /// call this only *after* dismissing the settings cover.
    @MainActor
    func finalizeAccountDeletion() {
        profile = nil
        sessions = []
        importedHealthSessions = []
        activeSession = nil
        account = nil
        authErrorMessage = nil
        persistence.reset()
        AppLog.store.info("Account deleted (local data wiped)")
    }

    @MainActor
    private func performAuth(_ work: @escaping () async throws -> AuthResult) async {
        isAuthenticating = true
        authErrorMessage = nil
        authMessageIsNotice = false
        defer { isAuthenticating = false }
        do {
            let result = try await work()
            lastSignInWasNewAccount = result.isNewAccount
            adoptSignedInAccount(result.account, remoteProfile: result.remoteProfile)
            AppLog.store.info("Signed in (provider=\(result.account.provider.rawValue), new=\(result.isNewAccount))")
        } catch let error as AuthError {
            // Cancellation is a deliberate user action — show nothing.
            guard error != .cancelled else { return }
            authErrorMessage = error.message
            authMessageIsNotice = error.isNotice
        } catch {
            authErrorMessage = AuthError.unknown(error.localizedDescription).message
        }
    }

    /// Post-sign-in bookkeeping shared by every provider. Handles the two
    /// device-vs-account mismatches:
    /// - a *different* user signing in on this device (shared device / account
    ///   switch) must never inherit the previous user's profile or nights;
    /// - a *returning* user on a fresh device gets their profile restored from
    ///   the account's cloud copy, skipping onboarding. The profile is set
    ///   before `account` so `RootView` computes the destination screen from a
    ///   consistent pair and never routes through onboarding on the way in.
    @MainActor
    private func adoptSignedInAccount(_ newAccount: AppAccount, remoteProfile: RemoteProfile?) {
        if let previousID = persistence.lastAccountID, previousID != newAccount.id, profile != nil || !sessions.isEmpty {
            profile = nil
            sessions = []
            importedHealthSessions = []
            activeSession = nil
            AppLog.store.notice("Different account signed in — previous user's local data cleared")
        }
        if profile == nil, let remoteProfile {
            profile = remoteProfile.asLocalProfile
            AppLog.store.info("Restored profile from cloud")
        } else if remoteProfile == nil, let localCopy = RemoteProfile(profile: profile) {
            // Account predates profile sync (or its cloud copy was lost): seed
            // it from this device so the next fresh install skips onboarding.
            Task { await auth.saveRemoteProfile(localCopy) }
        }
        account = newAccount
        persistAccount(newAccount)
        persistence.saveLastAccountID(newAccount.id)
        persist(refreshWidget: true)
    }

    /// Push the local profile to the account's cloud copy, best-effort. Called
    /// after every profile-shaping change (onboarding, name, schedule).
    private func syncRemoteProfile() {
        guard isAuthenticated, let remote = RemoteProfile(profile: profile) else { return }
        Task { [auth] in await auth.saveRemoteProfile(remote) }
    }

    /// Race `operation` against a deadline, returning `nil` when the deadline
    /// wins. Used only at launch, where blocking the UI beats nothing but a
    /// bounded wait beats both.
    private static func withTimeout<T: Sendable>(
        seconds: Double,
        _ operation: @escaping @Sendable () async -> T?
    ) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await operation() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private func persistAccount(_ account: AppAccount) {
        persistence.saveAccount(account)
    }

    private func clearPersistedAccount() {
        persistence.saveAccount(nil)
    }

    // MARK: - Sleep loop

    func startSleep() {
        let start = Date()
        activeSession = ActiveSleepSession(start: start)
        selectedTab = .home
        // Refresh the widget so it flips into the asleep state immediately.
        persist()
        let shouldStartLockdown = willLockDuringSleep
        performAfterStateChange { [weak self] in
            guard let self else { return }
            if shouldStartLockdown { self.screenTime.startLockdown() }
            Task { SleepLiveActivity.start(startDate: start) }
        }
        AppLog.store.info("Sleep session started")
    }

    /// Leave the sleep screen without logging a night — for someone who opened
    /// it to peek or tapped Sleep Now by mistake.
    func cancelSleep() {
        activeSession = nil
        // Refresh the widget so it leaves the asleep state immediately.
        persist()
        performAfterStateChange { [weak self] in
            guard let self else { return }
            self.screenTime.endLockdown()
            SleepLiveActivity.end()
        }
        AppLog.store.info("Sleep session canceled (not logged)")
    }

    func wakeUp() {
        guard let activeSession else { return }
        let end = Date()
        let minutes = max(1, Int((end.timeIntervalSince(activeSession.start) / 60).rounded()))
        let session = SleepSession(
            id: "s-\(Int(end.timeIntervalSince1970))",
            start: activeSession.start,
            end: end,
            durationMinutes: minutes,
            source: .local
        )
        sessions.append(session)
        self.activeSession = nil
        persist()
        performAfterStateChange { [weak self] in
            guard let self else { return }
            self.screenTime.endLockdown()
            SleepLiveActivity.end()
        }
        AppLog.store.info("Logged night: \(minutes)m")

        if profile?.healthSyncEnabled == true {
            Task {
                await health.save(session: session)
                await refreshHealth()
            }
        }
    }

    // MARK: - Health sync

    /// Whether the user has explicitly denied Health access. Once denied, iOS
    /// won't re-show the permission sheet, so the app must send them to Settings.
    var healthAccessDenied: Bool { health.isAccessDenied }

    /// The entry point for the Connect button / Settings toggle. Requests
    /// authorization the first time; if access was already denied at the OS
    /// level (where a re-request silently no-ops), opens Settings instead.
    @MainActor
    func connectHealth() async {
        if health.isAccessDenied {
            openSystemSettings()
            return
        }
        await enableHealthSync()
    }

    @MainActor
    func enableHealthSync() async {
        guard health.isAvailable else {
            AppLog.health.notice("HealthKit unavailable on this device")
            return
        }
        let granted = await health.requestAuthorization()
        guard var profile else { return }
        profile.healthSyncEnabled = granted
        self.profile = profile
        persist(refreshWidget: false)
        if granted {
            await refreshHealth()
        } else {
            AppLog.health.notice("Health authorization not granted; sync stays off")
        }
    }

    private func openSystemSettings() {
        #if canImport(UIKit)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        #endif
    }

    func disableHealthSync() {
        guard var profile else { return }
        profile.healthSyncEnabled = false
        self.profile = profile
        importedHealthSessions = []
        persist()
        AppLog.store.info("Health sync disabled")
    }

    /// Wave off the in-app Health prompt so it stops reappearing. Connecting via
    /// Settings still works afterward.
    func dismissHealthPrompt() {
        guard var profile, !profile.healthPromptDismissed else { return }
        profile.healthPromptDismissed = true
        self.profile = profile
        persist(refreshWidget: false)
        AppLog.store.info("Health connect prompt dismissed")
    }

    // MARK: - Sleep lockdown (Screen Time)

    /// Requests Screen Time authorization (lazily, from the Apps row — the
    /// picker is useless without it). Returns whether we're allowed to shield.
    /// Writes nothing to the profile: authorization is always read live.
    @MainActor
    func requestScreenTimeAccess() async -> Bool {
        let granted = await screenTime.requestAuthorization()
        if granted { rescheduleLockdown() }
        AppLog.store.info("Screen Time access \(granted ? "granted" : "denied")")
        return granted
    }

    /// The "Block while you sleep" toggle. Off tears down any active shield
    /// and the scheduled safety-net window; the app selection is kept.
    func setBlockingEnabled(_ on: Bool) {
        guard var profile, profile.blockDuringSleep != on else { return }
        profile.blockDuringSleep = on
        self.profile = profile
        persist(refreshWidget: false)
        if on {
            rescheduleLockdown()
        } else {
            screenTime.endLockdown()
            screenTime.cancelScheduledLockdown()
        }
        AppLog.store.info("Sleep blocking switched \(on ? "on" : "off")")
    }

    func setLockdownMaxHours(_ hours: Int) {
        guard var profile else { return }
        guard profile.lockdownMaxHours != hours else { return }
        profile.lockdownMaxHours = hours
        self.profile = profile
        persist(refreshWidget: false)
        rescheduleLockdown()
    }

    /// Opaque encoded app selection for the lockdown picker UI.
    /// Reads `appSelectionRevision` to create an observation dependency so
    /// SwiftUI views re-render when the selection changes.
    func appSelectionData() -> Data? {
        _ = appSelectionRevision  // touch the tracked property
        return screenTime.selectionData()
    }
    func saveAppSelection(_ data: Data) {
        screenTime.saveSelection(data: data)
        appSelectionRevision += 1
        // With nothing left to block tonight (selection cleared, or blocking
        // switched off), tear down the shield and its scheduled window rather
        // than registering an empty (no-op but lingering) one.
        if willLockDuringSleep {
            rescheduleLockdown()
        } else {
            screenTime.endLockdown()
            screenTime.cancelScheduledLockdown()
        }
    }

    /// Re-registers the scheduled bedtime->wake DeviceActivityMonitor window so
    /// the shield applies/clears even if the app isn't open.
    private func rescheduleLockdown() {
        guard let profile, willLockDuringSleep else { return }
        screenTime.scheduleLockdown(
            bedtimeMinutes: profile.bedtime,
            wakeMinutes: profile.wakeTime,
            maxHours: profile.lockdownMaxHours
        )
    }

    @MainActor
    func refreshHealth() async {
        guard health.isAvailable, profile?.healthSyncEnabled == true else { return }
        isImportingHealth = true
        defer { isImportingHealth = false }
        importedHealthSessions = await health.fetchNights(days: 30, targetMinutes: targetMinutes)
        AppLog.store.info("Display history now \(self.displaySessions.count) night(s)")
        updateWidgetSoon()
    }

    // MARK: - Profile edits

    func saveSchedule(bedtime: Int, wakeTime: Int) {
        guard var profile else { return }
        guard profile.bedtime != bedtime || profile.wakeTime != wakeTime else { return }
        profile.bedtime = bedtime
        profile.wakeTime = wakeTime
        self.profile = profile
        persist()
        rescheduleLockdown()
        syncRemoteProfile()
    }

    func saveName(_ name: String) {
        guard var profile else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard profile.name != trimmed else { return }
        profile.name = trimmed
        self.profile = profile
        persist(refreshWidget: false)
        syncRemoteProfile()
    }

    private func persist(refreshWidget: Bool = true) {
        DispatchQueue.main.async { [weak self] in
            self?.persistNow(refreshWidget: refreshWidget)
        }
    }

    private func persistNow(refreshWidget: Bool = true) {
        persistence.save(
            SleepSnapshot(profile: profile, sessions: sessions, activeSession: activeSession)
        )
        if refreshWidget {
            updateWidgetSoon()
        }
    }

    private func performAfterStateChange(_ work: @escaping () -> Void) {
        DispatchQueue.main.async {
            work()
        }
    }
}

// MARK: - History merge (pure, testable)

enum SleepMerge {
    static func merge(
        local: [SleepSession],
        health: [SleepSession],
        calendar: Calendar = .current
    ) -> [SleepSession] {
        var byNight: [Date: SleepSession] = [:]
        for session in local {
            byNight[key(for: session.end, calendar: calendar)] = session
        }
        for session in health {
            byNight[key(for: session.end, calendar: calendar)] = session // Health wins
        }
        return byNight.values.sorted { $0.end < $1.end }
    }

    /// A stable per-night key. Shifting back 12h keeps early-morning wake times
    /// grouped with the evening they belong to.
    static func key(for end: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: end.addingTimeInterval(-12 * 3600))
    }
}

// MARK: - Persistence

struct SleepSnapshot: Codable {
    var profile: Profile?
    var sessions: [SleepSession]
    var activeSession: ActiveSleepSession?
}

struct SleepPersistence {
    static let shared = SleepPersistence()

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private let profileKey = "sulav.profile.v1"
    private let sessionsKey = "sulav.sessions.v1"
    private let activeKey = "sulav.active.v1"
    private let accountKey = "sulav.account.v1"
    // Lives in the app container (wiped on delete), so its absence marks a
    // fresh install. Deliberately not cleared by `reset()` — a sign-out within
    // the same install is not a reinstall.
    private let launchedKey = "sulav.hasLaunched.v1"
    // The id of the last account that signed in on this install. Unlike the
    // cached account, this survives sign-out, so the *next* sign-in can tell a
    // returning user (keep their local data) from a different user on a shared
    // device (wipe it). Cleared by `reset()` — after account deletion there is
    // no previous user left to protect.
    private let lastAccountIDKey = "sulav.lastAccountID.v1"
    // The id of the account whose cloud profile copy this install has already
    // confirmed, so the launch-time seed check runs once per account instead
    // of hitting the network at every open. See `SleepStore.restoreSession()`.
    private let cloudSeedCheckedKey = "sulav.cloudSeedChecked.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() -> SleepSnapshot {
        SleepSnapshot(
            profile: decode(Profile.self, forKey: profileKey),
            sessions: decode([SleepSession].self, forKey: sessionsKey) ?? [],
            activeSession: decode(ActiveSleepSession.self, forKey: activeKey)
        )
    }

    func save(_ snapshot: SleepSnapshot) {
        encode(snapshot.profile, forKey: profileKey)
        encode(snapshot.sessions, forKey: sessionsKey)
        encode(snapshot.activeSession, forKey: activeKey)
    }

    func reset() {
        defaults.removeObject(forKey: profileKey)
        defaults.removeObject(forKey: sessionsKey)
        defaults.removeObject(forKey: activeKey)
        defaults.removeObject(forKey: accountKey)
        defaults.removeObject(forKey: lastAccountIDKey)
        defaults.removeObject(forKey: cloudSeedCheckedKey)
    }

    /// Whether the app has been launched before on this install. Backed by the
    /// container, so a reinstall resets it to `false` even if the Keychain
    /// session survives. See `SleepStore.restoreSession()`.
    var hasLaunchedBefore: Bool { defaults.bool(forKey: launchedKey) }

    func markLaunched() { defaults.set(true, forKey: launchedKey) }

    /// Non-secret account info only (id/email/provider) — the real session
    /// token lives in the Keychain via the auth SDK, never here.
    func loadAccount() -> AppAccount? { decode(AppAccount.self, forKey: accountKey) }

    func saveAccount(_ account: AppAccount?) {
        encode(account, forKey: accountKey)
    }

    var lastAccountID: String? { defaults.string(forKey: lastAccountIDKey) }

    func saveLastAccountID(_ id: String) { defaults.set(id, forKey: lastAccountIDKey) }

    var cloudSeedCheckedAccountID: String? { defaults.string(forKey: cloudSeedCheckedKey) }

    func markCloudSeedChecked(accountID: String) { defaults.set(accountID, forKey: cloudSeedCheckedKey) }

    func startSleepFromIntent() {
        encode(ActiveSleepSession(start: Date()), forKey: activeKey)
    }

    private func decode<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private func encode<T: Encodable>(_ value: T?, forKey key: String) {
        guard let value, let data = try? encoder.encode(value) else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(data, forKey: key)
    }
}

// MARK: - Sleep math (pure, testable)

enum SleepMath {
    static func windowMinutes(bedtime: Int, wakeTime: Int) -> Int {
        var diff = wakeTime - bedtime
        if diff <= 0 { diff += 1_440 }
        return diff
    }
}
