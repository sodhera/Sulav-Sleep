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
    /// Whether Home shows the slide-to-sleep confirmation panel. Lives on the
    /// store (not Home-local state) so the widget/shield `sleepblock://sleep`
    /// deep link can open it — a tap anywhere never *starts* a session; the
    /// slide gesture is the only way a night begins.
    var showSleepConfirmation = false
    var isImportingHealth = false
    // MARK: App update gate state (all logic in SleepUpdateGate.swift —
    // extensions can't add storage, so only the stored slots live here).
    /// Whether the installed version is below the server's minimum — RootView
    /// mounts the blocking `UpdateRequiredView` when true. Starts false and
    /// only a successfully *fetched* config can raise it: fail open.
    var updateRequired = false
    /// Server-set copy for the gate screen (`app_config.update_message`).
    var updateGateMessage: String?
    /// The newer version the soft nudge advertises, nil when current.
    var availableUpdateVersion: String?
    /// Which version's nudge the user has waved off (mirrors persistence so
    /// dismissal is observable).
    var dismissedUpdateNudgeVersion: String?
    /// In-memory throttle for config fetches — deliberately not persisted, so
    /// a cold launch always checks.
    var lastUpdateGateCheck: Date?
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
    /// What RevenueCat knows about the `pro` entitlement. Starts `.unknown`;
    /// the customer-info stream (which replays the cache immediately, so a
    /// subscriber resolves offline too) keeps it current. On an unconfigured
    /// build (no API key) it is `.entitled` from init — dev mode, no paywall.
    private(set) var entitlement: EntitlementState = .unknown
    /// Display-only detail about the active subscription (trial vs paid, the
    /// renewal or end date, whether it's set to cancel) for the Settings
    /// status row — distinct from `entitlement`, which stays the gate's
    /// three-state answer. Nil until the first fetch resolves, in dev mode, or
    /// when there's no entitlement to describe; the Settings subscription
    /// group hides while it's nil.
    private(set) var subscriptionStatus: SubscriptionStatus?

    private let persistence: SleepPersistence
    private let health: SleepHealthProviding
    private let screenTime: ScreenTimeControlling
    private let auth: AuthProviding
    private let cloud: CloudSyncing
    private let subscription: SubscriptionProviding

    init(
        persistence: SleepPersistence = .shared,
        health: SleepHealthProviding? = nil,
        screenTime: ScreenTimeControlling? = nil,
        auth: AuthProviding? = nil,
        cloud: CloudSyncing? = nil,
        subscription: SubscriptionProviding? = nil
    ) {
        self.persistence = persistence
        self.health = health ?? SleepHealth.makeDefault()
        self.screenTime = screenTime ?? SleepScreenTime.makeDefault()
        self.auth = auth ?? SulavAuth.makeDefault()
        // Cloud must be created after auth (auth creates the shared SupabaseClient)
        self.cloud = cloud ?? SleepCloud.makeDefault()
        self.subscription = subscription ?? SleepSubscription.makeDefault()
        screenTimePrimerSeen = persistence.screenTimePrimerSeen
        reload()
        startSubscriptionTracking()
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

    /// The most recent session, but only when it can honestly be called "last
    /// night" — i.e. it ended this morning or yesterday. When the newest record
    /// is older than that (e.g. the user hasn't slept with the app in weeks),
    /// this is `nil` so the Home strip renders nothing rather than labelling
    /// stale hours "Last night". `latestSession` still exposes the raw newest
    /// row for callers that want it (the widget's own recency logic).
    var lastNightSession: SleepSession? {
        guard let latest = latestSession else { return nil }
        let calendar = Calendar.current
        guard calendar.isDateInToday(latest.end) || calendar.isDateInYesterday(latest.end)
        else { return nil }
        return latest
    }

    var targetMinutes: Int {
        guard let profile else { return 8 * 60 }
        return SleepMath.windowMinutes(bedtime: profile.bedtime, wakeTime: profile.wakeTime)
    }

    /// Consecutive on-track nights, counted back from the most recent one.
    ///
    /// A night is on track when it reaches at least 85% of the sleep target —
    /// the same bar the retired 0–100 score set at "score ≥ 80" — *and* falls on
    /// the sleep day right after the night before it. The day check is what
    /// makes this a streak: without it a good night in June and a good night in
    /// July counted as 2.
    ///
    /// The run must reach today or yesterday to still be live. Yesterday counts
    /// because tonight's sleep hasn't happened yet — a streak shouldn't visibly
    /// lapse all day and come back at breakfast.
    var onTrackStreak: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var streak = 0
        var expectedDay: Date?
        // `displaySessions` is one entry per sleep day, oldest first.
        for session in displaySessions.reversed() {
            let day = SleepMerge.key(for: session.end, calendar: calendar)
            if let expectedDay {
                guard day == expectedDay else { break }
            } else {
                let daysAgo = calendar.dateComponents([.day], from: day, to: today).day ?? .max
                guard daysAgo <= 1 else { break }
            }
            guard session.durationMinutes * 100 >= targetMinutes * 85 else { break }
            streak += 1
            expectedDay = calendar.date(byAdding: .day, value: -1, to: day)
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
        // Safety net for the shield snooze: if a "5 more minutes" grant lapsed
        // while the timed re-arm didn't fire, restore the block now. Cheap and
        // a no-op unless a snooze is actually outstanding.
        screenTime.reapplyShieldIfSnoozeExpired()
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
            latestDurationMinutes: lastNightSession?.durationMinutes,
            streak: onTrackStreak,
            targetMinutes: targetMinutes,
            bedtimeMinutes: profile?.bedtime,
            wakeMinutes: profile?.wakeTime,
            asleepSince: activeSession?.start,
            isSignedIn: isAuthenticated,
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

    // MARK: - Subscription

    /// Whether the hard paywall stands between this user and Main: signed in,
    /// onboarded, and *resolved* as not entitled. `.unknown` never gates —
    /// the gate acts only on an answer, and RevenueCat's cache answers
    /// offline for real subscribers — and an unconfigured build (dev mode)
    /// resolves `.entitled` at init, so it never gates either.
    var needsPaywall: Bool {
        isAuthenticated && isOnboarded && entitlement == .notEntitled
    }

    private func startSubscriptionTracking() {
        guard subscription.isConfigured else {
            entitlement = .entitled
#if DEBUG
            // Dev mode has no real subscription, so the status row hides. This
            // arg injects a sample trial so the Settings row can be previewed
            // and screenshotted on the Simulator (mirrors `-review-paywall`).
            if ProcessInfo.processInfo.arguments.contains("-review-subscription") {
                subscriptionStatus = SubscriptionStatus(
                    tier: .trial,
                    willRenew: true,
                    expiration: Calendar.current.date(byAdding: .day, value: 6, to: Date()),
                    isAnnual: true
                )
            }
#endif
            return
        }
        subscription.start { [weak self] state, status in
            self?.entitlement = state
            self?.subscriptionStatus = status
        }
    }

    /// Opens the system-managed subscription sheet so the user can switch
    /// plans or cancel — the only sanctioned place to change billing.
    @MainActor
    func manageSubscriptions() async {
        await subscription.manageSubscriptions()
    }

    func fetchPlans() async -> [SleepPlan] {
        await subscription.fetchPlans()
    }

    /// Runs the purchase flow for the paywall. Returns whether the user is
    /// entitled afterwards; `nil` when they cancelled. Throws
    /// `SubscriptionError` with a user-facing message on real failures.
    @MainActor
    func purchase(planID: String) async throws -> Bool? {
        guard let state = try await subscription.purchase(planID: planID) else { return nil }
        entitlement = state
        return state == .entitled
    }

    @MainActor
    func restorePurchases() async throws -> Bool {
        let state = try await subscription.restore()
        entitlement = state
        return state == .entitled
    }

    // MARK: - Onboarding

    func completeOnboarding(_ answers: OnboardingAnswers) {
        let trimmed = answers.name.trimmingCharacters(in: .whitespacesAndNewlines)
        profile = Profile(
            name: trimmed.isEmpty ? "Friend" : trimmed,
            bedtime: answers.bedtime,
            wakeTime: answers.wakeTime,
            onboarded: true,
            healthSyncEnabled: false,
            sleepStruggles: answers.struggles,
            timeSinkApps: answers.timeSinks,
            primaryGoal: answers.goal,
            lateNightPhone: answers.lateNightPhone,
            wakeFeeling: answers.wakeFeeling
        )
        // No seeding: the history is empty until the user logs a real night or
        // connects Apple Health.
        sessions = []
        importedHealthSessions = []
        activeSession = nil
        persist()
        AppLog.store.info("Onboarding complete")
        syncCloudProfile()
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
            // Tie the subscription to the account so it follows the user
            // across devices/reinstalls. Backgrounded — never blocks launch.
            Task { [subscription] in await subscription.logIn(accountID: account.id) }
            // Signed in but no profile on this device (e.g. a Keychain session
            // synced from another device): restore the cloud copy so the user
            // lands in the app, not back in onboarding.
            if profile == nil {
                // Try the profiles table first; fall back to legacy auth
                // metadata for accounts that predate the table migration.
                if let cloudProfile = await Self.withTimeout(seconds: 5, { [cloud] in
                    await cloud.fetchProfile(userId: account.id)
                }) {
                    profile = cloudProfile.asLocalProfile
                    persist(refreshWidget: false)
                    AppLog.store.info("Restored profile from cloud table (launch)")
                } else if let remote = await Self.withTimeout(seconds: 5, { [auth] in
                    await auth.fetchRemoteProfile()
                }) {
                    profile = remote.asLocalProfile
                    persist(refreshWidget: false)
                    AppLog.store.info("Restored profile from auth metadata (launch)")
                    // Migrate legacy metadata to the profiles table
                    Task { [cloud] in
                        await cloud.upsertProfile(CloudProfile(from: remote), userId: account.id)
                        AppLog.store.info("Migrated legacy metadata profile to table")
                    }
                }
            } else if !persistence.cloudMigrated(accountID: account.id) {
                // First launch after the cloud sync update: seed the table
                // from local data so the user's history is backed up.
                let localProfile = CloudProfile(profile: profile)
                let localSessions = sessions.filter { $0.source == .local }
                Task { [cloud, persistence] in
                    if let cp = localProfile {
                        await cloud.upsertProfile(cp, userId: account.id)
                    }
                    if !localSessions.isEmpty {
                        await cloud.upsertSessions(localSessions, userId: account.id)
                    }
                    persistence.markCloudMigrated(accountID: account.id)
                    AppLog.store.info("Seeded cloud tables from local data")
                }
            }
            // Restore cloud sessions and merge with local
            Task { [weak self] in await self?.restoreCloudSessions() }
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
        await subscription.logOut()
        account = nil
        authErrorMessage = nil
        authMessageIsNotice = false
        clearPersistedAccount()
        // The widget flips its action capsule to "Sign in".
        updateWidgetSoon()
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
        Task { [subscription] in await subscription.logOut() }
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
        // Case-insensitive: installs from before the account id was lowercased
        // (see `SupabaseAuthClient.account(from:)`) hold an uppercase
        // `lastAccountID`, and a bare `!=` would read the same user as a
        // different one on first launch after upgrading — wiping their profile
        // and nights.
        if let previousID = persistence.lastAccountID,
           previousID.caseInsensitiveCompare(newAccount.id) != .orderedSame,
           profile != nil || !sessions.isEmpty {
            profile = nil
            sessions = []
            importedHealthSessions = []
            activeSession = nil
            AppLog.store.notice("Different account signed in — previous user's local data cleared")
        }
        if profile == nil, let remoteProfile {
            profile = remoteProfile.asLocalProfile
            AppLog.store.info("Restored profile from cloud")
        } else if profile == nil {
            // Try cloud table (profile may exist in the table but not metadata)
            Task { [cloud] in
                if let cloudProfile = await cloud.fetchProfile(userId: newAccount.id) {
                    await MainActor.run {
                        self.profile = cloudProfile.asLocalProfile
                        self.persist(refreshWidget: true)
                    }
                    AppLog.store.info("Restored profile from cloud table (sign-in)")
                }
            }
        }
        // Sync local profile to cloud table
        if let cp = CloudProfile(profile: profile) {
            Task { [cloud] in await cloud.upsertProfile(cp, userId: newAccount.id) }
        }
        account = newAccount
        persistAccount(newAccount)
        persistence.saveLastAccountID(newAccount.id)
        persist(refreshWidget: true)
        // Link the subscription to this account (see restoreSession).
        Task { [subscription] in await subscription.logIn(accountID: newAccount.id) }
        // Restore cloud sessions and merge
        Task { [weak self] in await self?.restoreCloudSessions() }
    }

    /// Push the local profile to the cloud table, best-effort. Called
    /// after every profile-shaping change (onboarding, name, schedule).
    private func syncCloudProfile() {
        guard isAuthenticated, let userId = account?.id,
              let cp = CloudProfile(profile: profile) else { return }
        Task { [cloud] in await cloud.upsertProfile(cp, userId: userId) }
    }

    /// Fetch sleep sessions from the cloud table and merge with local.
    /// Called at launch and after sign-in, backgrounded.
    @MainActor
    private func restoreCloudSessions() async {
        guard let userId = account?.id else { return }
        let cloudSessions = await cloud.fetchSessions(userId: userId)
        guard !cloudSessions.isEmpty else { return }
        // Merge cloud sessions into local using the same night-dedup logic
        // as Health merge. Local wins on conflict.
        let merged = SleepMerge.merge(local: self.sessions, health: cloudSessions)
        let added = merged.count - self.sessions.count
        if added > 0 {
            self.sessions = merged
            persist(refreshWidget: true)
            AppLog.store.info("Restored \(added) session(s) from cloud")
        }
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
        // The confirmation did its job; without this, Home would reopen on
        // the panel after waking (the flag lives on the store, not the view).
        showSleepConfirmation = false
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

        // Sync to cloud
        if let userId = account?.id {
            Task { [cloud] in await cloud.upsertSessions([session], userId: userId) }
        }

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

    // MARK: - App Store review

    /// Whether this is a reasonable moment to show the system review prompt.
    ///
    /// **You cannot detect the outcome of a review prompt.** iOS gives no
    /// callback and no API for "has this user reviewed" — deliberately, so
    /// developers can't treat reviewers differently. So "ask again if they
    /// dismissed it" is not literally implementable: all this can do is ask
    /// again after a cooldown, without knowing what happened. Two things make
    /// that acceptable rather than nagging: iOS won't re-show the prompt to
    /// someone who already rated this version, and the system independently
    /// caps the prompt at three appearances per year whatever we request.
    /// `maxAsks` matches that cap so we never burn a request the OS would
    /// have swallowed anyway.
    var shouldRequestReview: Bool {
        // Two logged nights is the earliest point the app has actually done
        // its job. Asking before that is asking a stranger for a favour.
        guard displaySessions.count >= Self.reviewMinimumNights else { return false }
        // Never mid-night: the prompt would land over the sleep screen, or in
        // the groggy seconds after waking.
        guard activeSession == nil else { return false }
        guard SleepPersistence.shared.reviewAskCount < Self.maxReviewAsks else { return false }
        guard let last = SleepPersistence.shared.lastReviewAsk else { return true }
        return Date().timeIntervalSince(last) >= Self.reviewCooldown
    }

    func markReviewRequested() {
        SleepPersistence.shared.recordReviewAsk()
        AppLog.app.info("Review prompt requested (ask \(SleepPersistence.shared.reviewAskCount))")
    }

    /// Nights logged before the first ask.
    private static let reviewMinimumNights = 2
    /// Lifetime cap, matching iOS's own three-per-year ceiling.
    private static let maxReviewAsks = 3
    /// Gap between asks when we don't know how the last one went — which is
    /// always.
    private static let reviewCooldown: TimeInterval = 7 * 24 * 60 * 60

    /// Opens the App Store straight to the write-a-review sheet.
    ///
    /// This is **not** `requestReview()`. That call is a *request*: the system
    /// decides whether to show anything, and often shows nothing — which is
    /// fine for an ambient prompt the user didn't ask for, and unacceptable
    /// for a button they deliberately tapped. A tap must always do something
    /// visible, so an explicit "Rate" control uses the URL instead.
    func openAppStoreReview() {
        #if canImport(UIKit)
        guard let url = AppStoreLink.writeReview else {
            AppLog.app.error("Review link tapped with no App Store ID configured")
            return
        }
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

    /// Whether the full-screen Screen Time primer stands between this user
    /// and Main (after the paywall — see `RootView`): onboarded, on real
    /// hardware, not yet authorized, and not already primed *on this
    /// install*. The seen-marker deliberately lives in the app container
    /// (wiped by deletion), so a reinstalled returning user is primed again —
    /// exactly the case where authorization needs re-granting.
    var needsScreenTimePrimer: Bool {
        isAuthenticated && isOnboarded && !screenTimePrimerSeen
            && screenTimeState == .notAuthorized
    }

    /// Observable mirror of the container-backed seen-marker, so RootView's
    /// gate re-computes the moment the primer completes (`screenTimeState`
    /// alone is a live read, invisible to @Observable tracking). Loaded from
    /// persistence in `init`.
    private(set) var screenTimePrimerSeen = false

    /// The primer is a one-shot per install: it completes whether the user
    /// granted, denied, or skipped — never trap someone at a gate. The
    /// Blocked apps screen remains the always-available fixup path.
    func completeScreenTimePrimer() {
        persistence.markScreenTimePrimerSeen()
        screenTimePrimerSeen = true
        AppLog.store.info("Screen Time primer completed")
    }

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
        syncCloudProfile()
    }

    func saveName(_ name: String) {
        guard var profile else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard profile.name != trimmed else { return }
        profile.name = trimmed
        self.profile = profile
        persist(refreshWidget: false)
        syncCloudProfile()
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
    /// Collapses local and Health records into **at most one session per sleep
    /// day**, newest last. Every display surface reads the result, so this is
    /// the single place a night is bound to a day — the chart, the history
    /// pages, `latestSession`, "Last night", and the streak all inherit it and
    /// none of them re-bucket.
    static func merge(
        local: [SleepSession],
        health: [SleepSession],
        calendar: Calendar = .current
    ) -> [SleepSession] {
        var byNight: [Date: SleepSession] = [:]
        for session in local + health {
            let day = key(for: session.end, calendar: calendar)
            byNight[day] = byNight[day].map { preferred($0, session) } ?? session
        }
        return byNight.values.sorted { $0.end < $1.end }
    }

    /// Which of two records sharing a sleep day is *that day's night*.
    ///
    /// Longest wins. The old rule was "Health wins", which is right for one
    /// night recorded twice — Health measured it, the local record is only
    /// button-press timing — but wrong for two genuinely different events. A
    /// 45-minute afternoon nap clears `SleepNightBuilder.minimumNightMinutes`
    /// and lands on the same day as the night you woke from that morning; under
    /// source precedence it displaced a full night, so the chart showed an hour,
    /// Home called it "Last night", and the streak reset. Duration tells the two
    /// apart without guessing at a nap cutoff.
    ///
    /// Health still breaks ties, which is exactly the same-night case: two
    /// records of one sleep agree on duration, and Health's is authoritative.
    /// Order-independent, so the merge doesn't depend on which list came first.
    static func preferred(_ a: SleepSession, _ b: SleepSession) -> SleepSession {
        if a.durationMinutes != b.durationMinutes {
            return a.durationMinutes > b.durationMinutes ? a : b
        }
        if a.source != b.source {
            return a.source == .healthKit ? a : b
        }
        return a
    }

    /// The sleep day a night belongs to: **the day you woke up**.
    ///
    /// Matches Apple Health, Oura, and Whoop, and matches when the app is
    /// actually read — you wake, open it, and today's column holds the sleep you
    /// just got. Crossing midnight is irrelevant; only `end` is consulted, so a
    /// Friday 23:00 → Saturday 07:00 night is Saturday's.
    ///
    /// This is the only day rule in the app. It previously shifted back 12h
    /// here while every view bucketed on plain `startOfDay(end)`, and the two
    /// disagreeing was what let a nap silently overwrite a night.
    ///
    /// The implementation lives in `SleepDay` (SleepWidgetShared.swift) because
    /// the widget extension doesn't compile this file and its chart has to
    /// bucket identically.
    static func key(for end: Date, calendar: Calendar = .current) -> Date {
        SleepDay.key(for: end, calendar: calendar)
    }
}

// MARK: - Persistence

struct SleepSnapshot: Codable {
    var profile: Profile?
    var sessions: [SleepSession]
    var activeSession: ActiveSleepSession?
}

/// The app's App Store identity.
///
/// `appID` is blank until the app exists in App Store Connect, and everything
/// that links to the store checks `isConfigured` first — the Settings "Rate"
/// row hides itself entirely while it's unset. That's deliberate: a placeholder
/// id would ship a row that opens the App Store to a nonexistent app, which is
/// worse than no row at all.
///
/// **To enable: paste the numeric id (digits only, no "id" prefix) from App
/// Store Connect below.**
enum AppStoreLink {
    static let appID = "6787030239"

    static var isConfigured: Bool {
        !appID.isEmpty && appID.allSatisfy(\.isNumber)
    }

    /// Deep link that opens the store page with the review sheet already up.
    static var writeReview: URL? {
        guard isConfigured else { return nil }
        return URL(string: "https://apps.apple.com/app/id\(appID)?action=write-review")
    }

    /// The plain product page — where the update gate and nudge send people.
    static var productPage: URL? {
        guard isConfigured else { return nil }
        return URL(string: "https://apps.apple.com/app/id\(appID)")
    }
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
    // Written by builds between d1dcd33 and 31e122a to gate a launch-time seed
    // of the *legacy* auth-metadata profile. The profiles-table migration
    // replaced that path — `cloudMigratedKey` below is its direct successor —
    // so nothing reads this any more. Still cleared by `reset()` so account
    // deletion doesn't strand it on installs that predate the migration.
    private let legacyCloudSeedCheckedKey = "sulav.cloudSeedChecked.v1"
    // Whether this install has shown the Screen Time permission primer.
    // Container-backed on purpose: deleting the app wipes it, so a reinstall
    // (where the authorization must be re-granted anyway) primes again. Not
    // cleared by `reset()` — the primer is per-install, not per-account.
    private let screenTimePrimerKey = "sulav.screenTimePrimer.v1"
    // How many times we've shown the App Store review prompt, and when we last
    // did. Per-install like the primer, and deliberately not cleared by
    // `reset()`: signing out is not a licence to start asking again.
    private let reviewAskCountKey = "sulav.reviewAskCount.v1"
    private let reviewLastAskKey = "sulav.reviewLastAsk.v1"
    // Which version's update nudge was waved off (the version *string*, so a
    // newer release nudges once again). Not cleared by `reset()` — signing
    // out is not a reason to re-nudge.
    private let updateNudgeDismissedKey = "sulav.updateNudgeDismissed.v1"

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
        defaults.removeObject(forKey: legacyCloudSeedCheckedKey)
    }

    /// Whether the app has been launched before on this install. Backed by the
    /// container, so a reinstall resets it to `false` even if the Keychain
    /// session survives. See `SleepStore.restoreSession()`.
    var hasLaunchedBefore: Bool { defaults.bool(forKey: launchedKey) }

    func markLaunched() { defaults.set(true, forKey: launchedKey) }

    /// How many times this install has shown the review prompt, and when it
    /// last did (nil if never).
    var reviewAskCount: Int { defaults.integer(forKey: reviewAskCountKey) }
    var lastReviewAsk: Date? { defaults.object(forKey: reviewLastAskKey) as? Date }

    func recordReviewAsk(at date: Date = Date()) {
        defaults.set(reviewAskCount + 1, forKey: reviewAskCountKey)
        defaults.set(date, forKey: reviewLastAskKey)
    }

    var dismissedUpdateNudgeVersion: String? { defaults.string(forKey: updateNudgeDismissedKey) }

    func dismissUpdateNudge(version: String) {
        defaults.set(version, forKey: updateNudgeDismissedKey)
    }

    /// Non-secret account info only (id/email/provider) — the real session
    /// token lives in the Keychain via the auth SDK, never here.
    func loadAccount() -> AppAccount? { decode(AppAccount.self, forKey: accountKey) }

    func saveAccount(_ account: AppAccount?) {
        encode(account, forKey: accountKey)
    }

    var lastAccountID: String? { defaults.string(forKey: lastAccountIDKey) }

    func saveLastAccountID(_ id: String) { defaults.set(id, forKey: lastAccountIDKey) }

    // Whether the local profile + sessions for this account have been
    // migrated to the cloud tables (one-time seed on app update).
    private let cloudMigratedKey = "sulav.cloudMigrated.v1"

    /// Case-insensitive for the same reason as the account-switch check in
    /// `adoptSignedInAccount` — a pre-lowercasing install stored the uppercase
    /// id, and an exact compare would re-run the one-time migration.
    func cloudMigrated(accountID: String) -> Bool {
        defaults.string(forKey: cloudMigratedKey)?
            .caseInsensitiveCompare(accountID) == .orderedSame
    }

    func markCloudMigrated(accountID: String) {
        defaults.set(accountID, forKey: cloudMigratedKey)
    }

    var screenTimePrimerSeen: Bool { defaults.bool(forKey: screenTimePrimerKey) }

    func markScreenTimePrimerSeen() { defaults.set(true, forKey: screenTimePrimerKey) }

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

/// What the app averages over a run of nights: how long you slept, and the two
/// clock times that bracket it.
struct SleepAverages: Equatable {
    /// How many nights actually went into the numbers. Surfaced so the UI can
    /// say "last 7 nights" honestly when the record only holds three.
    var nights: Int
    var durationMinutes: Int
    /// Average minute-of-day the user fell asleep, and woke up.
    var bedtimeMinutes: Int
    var wakeMinutes: Int
}

enum SleepStats {
    /// The window every "recent average" in the app is taken over. One
    /// constant so Profile's stat band and its averages band can never drift
    /// into describing two different weeks.
    static let recentWindow = 7

    /// Averages over the `count` most recent nights, or nil when there is
    /// nothing to average — callers render nothing rather than a zeroed stat,
    /// the same honest-data rule the charts follow.
    ///
    /// Deliberately the last N *logged nights*, not the last N calendar days.
    /// `displaySessions` holds at most one entry per sleep day, so for an
    /// unbroken record the two are identical; where they differ — a sparse
    /// record — averaging the nights that exist beats averaging over a window
    /// that is mostly empty, and "last 7 nights" is a label that stays true.
    static func averages(of sessions: [SleepSession], last count: Int = recentWindow) -> SleepAverages? {
        let window = Array(sessions.suffix(count))
        guard !window.isEmpty else { return nil }
        return SleepAverages(
            nights: window.count,
            durationMinutes: window.reduce(0) { $0 + $1.durationMinutes } / window.count,
            bedtimeMinutes: meanMinuteOfDay(window.map { SleepFormatting.minutes(from: $0.start) }),
            wakeMinutes: meanMinuteOfDay(window.map { SleepFormatting.minutes(from: $0.end) })
        )
    }

    /// Mean of minute-of-day values treated as angles on a 24-hour dial.
    ///
    /// Bedtimes straddle midnight, so a plain arithmetic mean is wrong in the
    /// exact case this app cares about most: 11:50 PM and 12:10 AM average to
    /// **midnight**, but `(1430 + 10) / 2` is 720 — 12:00 *noon*, a bedtime
    /// nobody has. Averaging the unit vectors instead wraps correctly.
    static func meanMinuteOfDay(_ minutes: [Int]) -> Int {
        guard let first = minutes.first else { return 0 }
        let radiansPerMinute = 2 * Double.pi / 1_440
        var x = 0.0
        var y = 0.0
        for minute in minutes {
            let angle = Double(minute) * radiansPerMinute
            x += cos(angle)
            y += sin(angle)
        }
        // Perfectly opposed inputs (6 AM and 6 PM, say) cancel to the origin,
        // where the mean angle is genuinely undefined. atan2(0, 0) would hand
        // back midnight, which reads as a real answer; the first night is at
        // least an honest one.
        guard x.magnitude > 1e-9 || y.magnitude > 1e-9 else { return first }
        let mean = atan2(y, x) / radiansPerMinute
        return (Int(mean.rounded()) % 1_440 + 1_440) % 1_440
    }
}
