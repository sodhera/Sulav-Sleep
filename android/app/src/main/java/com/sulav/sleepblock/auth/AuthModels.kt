package com.sulav.sleepblock.auth

import com.sulav.sleepblock.data.Profile
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/** Mirror of ios/SulavSleep/Auth/AuthModels.swift. */

@Serializable
enum class AuthProvider {
    @SerialName("apple") APPLE,
    @SerialName("google") GOOGLE,
    @SerialName("email") EMAIL,
}

/** Non-secret account slice kept for display; tokens live elsewhere. */
@Serializable
data class AppAccount(
    val id: String,
    val email: String? = null,
    val provider: AuthProvider = AuthProvider.EMAIL,
)

data class AuthResult(
    val account: AppAccount,
    val isNewAccount: Boolean,
    val remoteProfile: RemoteProfile?,
)

/**
 * The slice of [Profile] that follows the account across devices, stored in
 * Supabase auth user metadata under the `sleep_profile` key — the exact JSON
 * the iOS client writes, so a profile created on iPhone restores on Android
 * and vice versa.
 */
@Serializable
data class RemoteProfile(
    val name: String,
    @SerialName("bedtime_minutes") val bedtime: Int,
    @SerialName("wake_minutes") val wakeTime: Int,
    @SerialName("struggles") val sleepStruggles: List<String> = emptyList(),
    @SerialName("time_sinks") val timeSinkApps: List<String> = emptyList(),
    @SerialName("goal") val primaryGoal: String = "",
    @SerialName("late_night_phone") val lateNightPhone: String = "",
    @SerialName("wake_feeling") val wakeFeeling: String = "",
) {
    fun asLocalProfile(): Profile = Profile(
        name = name,
        bedtime = bedtime,
        wakeTime = wakeTime,
        onboarded = true,
        sleepStruggles = sleepStruggles,
        timeSinkApps = timeSinkApps,
        primaryGoal = primaryGoal,
        lateNightPhone = lateNightPhone,
        wakeFeeling = wakeFeeling,
    )

    companion object {
        /** From an onboarded local profile; null when nothing is worth syncing. */
        fun from(profile: Profile?): RemoteProfile? {
            if (profile == null || !profile.onboarded) return null
            return RemoteProfile(
                name = profile.name,
                bedtime = profile.bedtime,
                wakeTime = profile.wakeTime,
                sleepStruggles = profile.sleepStruggles,
                timeSinkApps = profile.timeSinkApps,
                primaryGoal = profile.primaryGoal,
                lateNightPhone = profile.lateNightPhone,
                wakeFeeling = profile.wakeFeeling,
            )
        }
    }
}

/** User-facing auth failures; raw SDK/network errors never reach the UI. */
sealed class AuthException(val userMessage: String, val isNotice: Boolean = false) : Exception(userMessage) {
    object InvalidCredentials : AuthException("That email or password isn't right.")
    object EmailAlreadyRegistered : AuthException(
        "That email already has an account. Go back and choose \"I already have an account\" to sign in."
    )
    object EmailNotConfirmed : AuthException(
        "Confirm your email first — check your inbox for the confirmation link, then sign in."
    )
    object ConfirmationEmailSent : AuthException(
        "Almost there — tap the confirmation link we just emailed you, then sign in.", isNotice = true
    )
    class WeakPassword(detail: String) : AuthException(
        detail.ifEmpty { "That password is too weak. Try a longer one." }
    )
    object RateLimited : AuthException("Too many attempts. Wait a moment and try again.")
    object Network : AuthException("Couldn't reach the network. Try again.")
    class Unknown(detail: String) : AuthException(detail)
}
