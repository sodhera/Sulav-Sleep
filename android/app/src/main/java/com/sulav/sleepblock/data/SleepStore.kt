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

    /** Whether the blocking-permission primer stands between Main and us. */
    val needsBlockingPrimer: Boolean
        get() {
            val context = getApplication<Application>()
            return isAuthenticated && isOnboarded && !blockingPrimerSeen &&
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

    /** Whether the hard paywall stands between this user and Main. */
    val needsPaywall: Boolean
        get() = (isAuthenticated && isOnboarded && entitlement == EntitlementState.NOT_ENTITLED) ||
            (DebugFlags.reviewPaywall && isAuthenticated && isOnboarded)

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

    /** Nights in a row reaching ≥85% of the sleep target. */
    val onTrackStreak: Int
        get() {
            var streak = 0
            for (session in displaySessions.reversed()) {
                if (session.durationMinutes * 100 < targetMinutes * 85) break
                streak += 1
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

    fun completeOnboarding(answers: OnboardingAnswers) {
        val trimmed = answers.name.trim()
        profile = Profile(
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
        // No seeding: history stays empty until the user logs a real night.
        sessions = emptyList()
        activeSession = null
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
