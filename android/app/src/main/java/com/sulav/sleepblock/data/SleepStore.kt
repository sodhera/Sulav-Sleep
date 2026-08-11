package com.sulav.sleepblock.data

import android.app.Activity
import android.app.Application
import android.util.Log
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.sulav.sleepblock.auth.AppAccount
import com.sulav.sleepblock.auth.AuthException
import com.sulav.sleepblock.auth.AuthProviding
import com.sulav.sleepblock.auth.AuthResult
import com.sulav.sleepblock.auth.GoogleCredential
import com.sulav.sleepblock.auth.RemoteProfile
import com.sulav.sleepblock.auth.SulavAuth
import com.sulav.sleepblock.subscription.EntitlementState
import com.sulav.sleepblock.subscription.SleepPlan
import com.sulav.sleepblock.subscription.SleepSubscriptionFactory
import com.sulav.sleepblock.subscription.SubscriptionProviding
import com.sulav.sleepblock.subscription.SubscriptionStatus
import com.sulav.sleepblock.blocking.SleepAppBlocking
import com.sulav.sleepblock.blocking.SleepLockdownService
import com.sulav.sleepblock.widget.SleepWidget
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit

/**
 * The app's single state holder — a Kotlin port of the iOS `SleepStore`
 * (ios/SulavSleep/SleepStore.swift), minus the Apple-only providers (Screen
 * Time, HealthKit, Live Activities, widgets) which are Android phase 2; see
 * docs/android.md for the parity map.
 */
class SleepStore(application: Application) : AndroidViewModel(application) {

    private val persistence = SleepPersistence(application)
    private val auth: AuthProviding = SulavAuth.makeDefault(application)
    private val subscription: SubscriptionProviding = SleepSubscriptionFactory.makeDefault(application)

    var profile: Profile? by mutableStateOf(null)
        private set
    var sessions: List<SleepSession> by mutableStateOf(emptyList())
        private set
    var activeSession: ActiveSleepSession? by mutableStateOf(null)
        private set
    var account: AppAccount? by mutableStateOf(null)
        private set
    var selectedTab: AppTab by mutableStateOf(AppTab.HOME)
    /** Whether Home shows the slide-to-sleep confirmation panel. */
    var showSleepConfirmation: Boolean by mutableStateOf(false)
    /** False until the initial session-restore check completes. */
    var isAuthReady: Boolean by mutableStateOf(false)
        private set
    var authErrorMessage: String? by mutableStateOf(null)
        private set
    /** True when the message is calm guidance (confirmation email), not a failure. */
    var authMessageIsNotice: Boolean by mutableStateOf(false)
        private set
    var isAuthenticating: Boolean by mutableStateOf(false)
        private set
    /** Whether the last successful sign-in created a brand-new account. */
    var lastSignInWasNewAccount: Boolean = false
        private set

    /**
     * What RevenueCat knows about the `pro` entitlement. UNKNOWN never gates;
     * an unconfigured build resolves ENTITLED at init (dev mode, no paywall).
     */
    var entitlement: EntitlementState by mutableStateOf(EntitlementState.UNKNOWN)
        private set

    /** Settings display detail; the group hides while null (dev mode too). */
    var subscriptionStatus: SubscriptionStatus? by mutableStateOf(null)
        private set

    init {
        reload()
        // A session that survived a process death (OEM kill, crash, update)
        // resumes its lockdown the moment the app is back.
        if (activeSession != null && willLockDuringSleep) {
            SleepLockdownService.start(application)
        }
        subscription.start { state, status ->
            entitlement = state
            subscriptionStatus = status
        }
        // Debug preview (mirrors iOS -review-subscription): a sample trial
        // so the Settings row can be seen on an unconfigured build.
        if (DebugFlags.reviewSubscription && subscriptionStatus == null) {
            subscriptionStatus = SubscriptionStatus(
                tier = SubscriptionStatus.Tier.TRIAL,
                willRenew = true,
                expiresAtMillis = System.currentTimeMillis() + 6L * 24 * 3600 * 1000,
                isAnnual = true,
            )
        }
        viewModelScope.launch { restoreSession() }
    }

    /**
     * Whether the blocking-permission primer stands between Main and us.
     *
     * Locked users are exempt (iOS `needsScreenTimePrimer`). Usage access and
     * "display over other apps" are the most alarming grants the app asks for,
     * and spending them on someone who cannot start a night yet asks them to
     * hand over their phone for a feature they can't reach. The primer waits
     * for the subscription.
     */
    val needsBlockingPrimer: Boolean
        get() {
            val context = getApplication<Application>()
            return isAuthenticated && isOnboarded && !blockingPrimerSeen && !isLocked &&
                (!SleepAppBlocking.hasUsageAccess(context) || !SleepAppBlocking.hasOverlayPermission(context))
        }

    /** Observable mirror of the container-backed seen-marker. */
    var blockingPrimerSeen: Boolean by mutableStateOf(persistence.blockingPrimerSeen)
        private set

    /** One-shot per install; completes on grant or "Not now" — never a trap. */
    fun completeBlockingPrimer() {
        persistence.blockingPrimerSeen = true
        blockingPrimerSeen = true
        Log.i(TAG, "Blocking primer completed")
    }

    // MARK: - Subscription

    /**
     * Whether this user is outside the subscription: signed in, onboarded, and
     * *resolved* as not entitled. UNKNOWN never locks — the lock acts only on
     * an answer, and RevenueCat's cache answers offline for real subscribers —
     * and an unconfigured build (dev mode) resolves ENTITLED at init, so it
     * never locks either.
     *
     * **This is not a wall around the app.** A locked user gets the whole of
     * Main — Home, the record, the schedule, settings — and is stopped at
     * exactly one place: starting a night ([startSleep]). Everything the app
     * *shows* is theirs; what it *does* is the subscription. See DESIGN.md
     * ("Paywall") and iOS `SleepStore.isLocked`.
     *
     * *Parity note:* iOS additionally exempts a subscriber whose cached
     * entitlement lapsed while they were unreachable (`isWithinOfflineGrace`).
     * Android has no offline-grace window yet — see docs/android.md.
     */
    val isLocked: Boolean
        get() = (isAuthenticated && isOnboarded && entitlement == EntitlementState.NOT_ENTITLED) ||
            (DebugFlags.reviewPaywall && isAuthenticated && isOnboarded)

    /**
     * Whether the paywall is the *route* — the closing beat of onboarding,
     * shown full-screen before Main. It is dismissible (a ✕), and dismissing
     * it is remembered per install, so this is a one-time landing rather than
     * a wall the user re-hits on every cold launch. After that the paywall
     * only appears when someone reaches for the lock ([showPaywall]).
     */
    val needsPaywall: Boolean get() = isLocked && !paywallDismissed

    /**
     * Whether the paywall is up *over* Main as a dismissible cover. Distinct
     * from [needsPaywall], which is the first-run route: this is the lock
     * speaking when someone reaches for a subscriber-only action. On the store
     * because the entry points that raise it live elsewhere — Home's Sleep Now
     * and the Settings "Unlock SleepBlock" row.
     */
    var showPaywall: Boolean by mutableStateOf(false)

    /**
     * Observable mirror of the container-backed dismissal marker, so the route
     * re-computes the instant the ✕ is tapped (a bare persistence read is
     * invisible to Compose).
     *
     * A `--ez review-paywall true` build ignores the stored marker, so the
     * first-run route renders on every launch and stays screenshottable.
     */
    var paywallDismissed: Boolean by mutableStateOf(
        persistence.paywallDismissed && !DebugFlags.reviewPaywall
    )
        private set

    /**
     * The ✕ on the first-run paywall: drop the user into Main and don't put
     * the full-screen paywall in their way again. Per install, like the
     * blocking primer — not per account, since it describes what this person
     * has already been shown on this phone.
     */
    fun dismissPaywall() {
        persistence.paywallDismissed = true
        paywallDismissed = true
        showPaywall = false
        Log.i(TAG, "First-run paywall dismissed")
    }

    /**
     * Raise the paywall over Main, returning whether it went up. Every locked
     * action funnels through here rather than silently doing nothing, so the
     * lock always explains itself. Callers may ask unconditionally: an
     * entitled user is never shown it.
     */
    fun presentPaywallIfLocked(): Boolean {
        if (!isLocked) return false
        showPaywall = true
        return true
    }

    suspend fun fetchPlans(): List<SleepPlan> = subscription.fetchPlans()

    /** Null when cancelled; true when entitled afterwards. */
    suspend fun purchase(activity: Activity, plan: SleepPlan): Boolean? {
        val state = subscription.purchase(activity, plan) ?: return null
        entitlement = state
        return state == EntitlementState.ENTITLED
    }

    suspend fun restorePurchases(): Boolean {
        val state = subscription.restore()
        entitlement = state
        return state == EntitlementState.ENTITLED
    }

    // MARK: - Derived state

    val isOnboarded: Boolean get() = profile?.onboarded == true
    val isAuthenticated: Boolean get() = account != null

    /** History shown across the app, oldest → newest. */
    val displaySessions: List<SleepSession> get() = sessions.sortedBy { it.end }

    val latestSession: SleepSession? get() = displaySessions.lastOrNull()

    /**
     * The most recent session, only when it can honestly be called "last
     * night" — it ended today or yesterday. Stale hours never wear the label.
     */
    val lastNightSession: SleepSession?
        get() {
            val latest = latestSession ?: return null
            val endDay = latest.end.atZone(ZoneId.systemDefault()).toLocalDate()
            val today = LocalDate.now()
            return if (endDay == today || endDay == today.minusDays(1)) latest else null
        }

    val targetMinutes: Int
        get() = profile?.let { SleepMath.windowMinutes(it.bedtime, it.wakeTime) } ?: (8 * 60)

    /**
     * Consecutive on-track nights (≥85% of the sleep target) on *consecutive
     * sleep days*, counted back from the most recent. The run must reach today
     * or yesterday to still be live — yesterday because tonight's sleep hasn't
     * happened yet and a streak shouldn't visibly lapse all day.
     *
     * Mirrors iOS `SleepStore.onTrackStreak`. Without the day check this
     * counted qualifying records regardless of gaps, so a good night in June
     * and a good night in July read as a streak of 2 — and because sessions
     * sync through Supabase, the same user saw a different number on each
     * platform.
     *
     * A sleep day is the day you woke up (iOS `SleepMerge.key`). iOS gets one
     * night per day from its local+Health merge; Android has no Health import
     * yet, so collapse here by the same rule — longest wins — rather than
     * letting a second session on one day break the chain.
     */
    val onTrackStreak: Int
        get() {
            val today = LocalDate.now()
            val byDay = displaySessions
                .groupBy { it.end.atZone(ZoneId.systemDefault()).toLocalDate() }
                .mapValues { (_, daySessions) -> daySessions.maxBy { it.durationMinutes } }
            var streak = 0
            var expectedDay: LocalDate? = null
            for (day in byDay.keys.sortedDescending()) {
                if (expectedDay != null) {
                    if (day != expectedDay) break
                } else {
                    if (ChronoUnit.DAYS.between(day, today) > 1) break
                }
                if (byDay.getValue(day).durationMinutes * 100 < targetMinutes * 85) break
                streak += 1
                expectedDay = day.minusDays(1)
            }
            return streak
        }

    // MARK: - Sleep lockdown (app blocking)

    /** The user's "Block while you sleep" switch. On by default. */
    val blockingEnabled: Boolean get() = profile?.blockDuringSleep ?: true

    /** Bumped when the selection changes so Compose re-reads it. */
    private var blockedRevision by mutableStateOf(0)

    val blockedPackages: Set<String>
        get() {
            @Suppress("UNUSED_EXPRESSION") blockedRevision
            return persistence.blockedPackages
        }

    fun saveBlockedPackages(packages: Set<String>) {
        persistence.blockedPackages = packages
        blockedRevision += 1
    }

    fun setBlockingEnabled(on: Boolean) {
        val current = profile ?: return
        if (current.blockDuringSleep == on) return
        profile = current.copy(blockDuringSleep = on)
        persist()
        Log.i(TAG, "Sleep blocking switched ${if (on) "on" else "off"}")
    }

    /**
     * Whether tonight's Sleep Now will actually shield anything: blocking on,
     * both special permissions granted (checked live, mirroring the iOS rule
     * that authorization is never persisted), and at least one app chosen.
     * The single source of truth across Home, the confirmation panel, and
     * the Blocked apps screen.
     */
    val willLockDuringSleep: Boolean
        get() {
            val context = getApplication<Application>()
            return blockingEnabled &&
                SleepAppBlocking.hasUsageAccess(context) &&
                SleepAppBlocking.hasOverlayPermission(context) &&
                blockedPackages.isNotEmpty()
        }

    // MARK: - Lifecycle

    private fun reload() {
        profile = persistence.profile
        sessions = persistence.sessions
        activeSession = persistence.activeSession
        account = persistence.account
    }

    // MARK: - Onboarding

    /**
     * Commits the questionnaire answers as the local profile.
     *
     * **Never touches [sessions].** These questions are not only reached by
     * fresh sign-ups — a returning user whose cloud profile has not landed yet
     * is routed through the same screens as "quick setup", and clearing the
     * history there destroyed nights the user already owned (the iOS twin of
     * this bug is documented in `SleepStore.completeOnboarding`). A genuinely
     * new account has nothing to clear, and the cases that really must start
     * clean — a different user signing in, account deletion — do their own
     * wipe. Copying the existing profile likewise keeps the device-bound
     * settings the questions never asked about.
     */
    fun completeOnboarding(answers: OnboardingAnswers) {
        val trimmed = answers.name.trim()
        profile = (profile ?: Profile(
            name = "", bedtime = answers.bedtime, wakeTime = answers.wakeTime, onboarded = false,
        )).copy(
            name = trimmed.ifEmpty { "Friend" },
            bedtime = answers.bedtime,
            wakeTime = answers.wakeTime,
            onboarded = true,
            sleepStruggles = answers.struggles,
            timeSinkApps = answers.timeSinks,
            primaryGoal = answers.goal,
            lateNightPhone = answers.lateNightPhone,
            wakeFeeling = answers.wakeFeeling,
        )
        persist()
        Log.i(TAG, "Onboarding complete")
        syncRemoteProfile()
    }

    // MARK: - Auth

    private suspend fun restoreSession() {
        account = auth.currentAccount()
        account?.let { restored ->
            persistence.account = restored
            persistence.lastAccountID = restored.id
            subscription.logIn(restored.id)
            // Signed in but no profile on this device: restore the cloud copy
            // so the user lands in the app, not back in onboarding.
            if (profile == null) {
                auth.fetchRemoteProfile()?.let { remote ->
                    profile = remote.asLocalProfile()
                    persist()
                    Log.i(TAG, "Restored profile from cloud (launch)")
                }
            }
        } ?: run { persistence.account = null }
        isAuthReady = true
    }

    fun signUpEmail(email: String, password: String) = performAuth { auth.signUp(email, password) }

    fun signInEmail(email: String, password: String) = performAuth { auth.signIn(email, password) }

    /** Credential Manager → Supabase id_token grant. Cancel shows nothing. */
    fun signInWithGoogle(activity: Activity) = performAuth {
        val idToken = GoogleCredential.idToken(activity)
        auth.signInWithGoogleIdToken(idToken)
    }

    fun signOut() {
        viewModelScope.launch {
            auth.signOut()
            subscription.logOut()
            account = null
            authErrorMessage = null
            authMessageIsNotice = false
            persistence.account = null
            Log.i(TAG, "Signed out")
        }
    }

    /**
     * Step 1 of account deletion: server-side delete via the Edge Function.
     * Returns null on success or a user-facing message on failure (nothing
     * local is touched, so the user can retry).
     */
    suspend fun deleteAccountRemotely(): String? {
        authErrorMessage = null
        return try {
            auth.deleteAccount()
            null
        } catch (e: AuthException) {
            Log.e(TAG, "Account deletion failed: ${e.userMessage}")
            authErrorMessage = e.userMessage
            e.userMessage
        } catch (e: Exception) {
            val message = e.message ?: "Couldn't delete your account. Please try again."
            authErrorMessage = message
            message
        }
    }

    /** Step 2: wipe every on-device trace after a confirmed remote deletion. */
    fun finalizeAccountDeletion() {
        profile = null
        sessions = emptyList()
        activeSession = null
        account = null
        authErrorMessage = null
        persistence.reset()
        Log.i(TAG, "Account deleted (local data wiped)")
    }

    fun clearAuthMessage() {
        authErrorMessage = null
        authMessageIsNotice = false
    }

    private fun performAuth(work: suspend () -> AuthResult) {
        viewModelScope.launch {
            isAuthenticating = true
            authErrorMessage = null
            authMessageIsNotice = false
            try {
                val result = work()
                lastSignInWasNewAccount = result.isNewAccount
                adoptSignedInAccount(result.account, result.remoteProfile)
                Log.i(TAG, "Signed in (provider=${result.account.provider}, new=${result.isNewAccount})")
            } catch (e: AuthException.Cancelled) {
                // Deliberate user action — show nothing.
            } catch (e: AuthException) {
                authErrorMessage = e.userMessage
                authMessageIsNotice = e.isNotice
            } catch (e: Exception) {
                authErrorMessage = e.message ?: "Something went wrong."
            } finally {
                isAuthenticating = false
            }
        }
    }

    /**
     * Post-sign-in bookkeeping (same rules as iOS): a *different* user on this
     * device never inherits the previous user's data; a *returning* user on a
     * fresh device restores the cloud profile and skips onboarding.
     */
    private fun adoptSignedInAccount(newAccount: AppAccount, remoteProfile: RemoteProfile?) {
        val previousID = persistence.lastAccountID
        if (previousID != null && previousID != newAccount.id && (profile != null || sessions.isNotEmpty())) {
            profile = null
            sessions = emptyList()
            activeSession = null
            Log.w(TAG, "Different account signed in — previous user's local data cleared")
        }
        if (profile == null && remoteProfile != null) {
            profile = remoteProfile.asLocalProfile()
            Log.i(TAG, "Restored profile from cloud")
        } else if (remoteProfile == null) {
            // Account predates profile sync: seed the cloud copy from here.
            RemoteProfile.from(profile)?.let { copy ->
                viewModelScope.launch { auth.saveRemoteProfile(copy) }
            }
        }
        account = newAccount
        persistence.account = newAccount
        persistence.lastAccountID = newAccount.id
        persist()
        // Tie the subscription to the account so it follows across devices.
        subscription.logIn(newAccount.id)
    }

    /** Best-effort push of the local profile to the account's cloud copy. */
    private fun syncRemoteProfile() {
        if (!isAuthenticated) return
        val remote = RemoteProfile.from(profile) ?: return
        viewModelScope.launch { auth.saveRemoteProfile(remote) }
    }

    // MARK: - Sleep loop

    fun startSleep() {
        // The lock's last line. Home's Sleep Now checks first and raises the
        // paywall itself, so this should never fire — but starting a night is
        // the one thing the subscription buys, and it must not depend on every
        // future caller (a widget action, a notification, a Quick Settings
        // tile) remembering to ask.
        if (presentPaywallIfLocked()) {
            showSleepConfirmation = false
            Log.i(TAG, "Sleep start blocked — no subscription")
            return
        }
        activeSession = ActiveSleepSession(start = Instant.now())
        selectedTab = AppTab.HOME
        // The confirmation did its job; without this, Home would reopen on
        // the panel after waking.
        showSleepConfirmation = false
        persist()
        if (willLockDuringSleep) {
            SleepLockdownService.start(getApplication())
        }
        Log.i(TAG, "Sleep session started")
    }

    /** Leave the sleep screen without logging a night. */
    fun cancelSleep() {
        activeSession = null
        persist()
        SleepLockdownService.stop(getApplication())
        Log.i(TAG, "Sleep session canceled (not logged)")
    }

    fun wakeUp() {
        val active = activeSession ?: return
        val end = Instant.now()
        val minutes = maxOf(1, ((end.epochSecond - active.start.epochSecond) / 60.0).toInt())
        sessions = sessions + SleepSession(
            id = "s-${end.epochSecond}",
            start = active.start,
            end = end,
            durationMinutes = minutes,
            source = SleepSource.LOCAL,
        )
        activeSession = null
        persist()
        SleepLockdownService.stop(getApplication())
        Log.i(TAG, "Logged night: ${minutes}m")
    }

    // MARK: - Profile edits

    fun saveSchedule(bedtime: Int, wakeTime: Int) {
        val current = profile ?: return
        if (current.bedtime == bedtime && current.wakeTime == wakeTime) return
        profile = current.copy(bedtime = bedtime, wakeTime = wakeTime)
        persist()
        syncRemoteProfile()
    }

    fun saveName(name: String) {
        val current = profile ?: return
        val trimmed = name.trim()
        if (trimmed.isEmpty() || current.name == trimmed) return
        profile = current.copy(name = trimmed)
        persist()
        syncRemoteProfile()
    }

    private fun persist() {
        persistence.profile = profile
        persistence.sessions = sessions
        persistence.activeSession = activeSession
        // Keep the home-screen widget's snapshot current.
        viewModelScope.launch { SleepWidget.refresh(getApplication()) }
    }

    private companion object {
        const val TAG = "SleepStore"
    }
}
