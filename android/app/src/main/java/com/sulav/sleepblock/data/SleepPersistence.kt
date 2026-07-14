package com.sulav.sleepblock.data

import android.content.Context
import com.sulav.sleepblock.auth.AppAccount
import kotlinx.serialization.json.Json
import kotlinx.serialization.serializer

/**
 * SharedPreferences-backed JSON persistence, mirroring the iOS
 * `SleepPersistence` (UserDefaults + Codable). One JSON blob per key.
 * Unlike iOS, Android wipes app data on uninstall, so there is no
 * reinstall/Keychain mismatch to guard against here.
 */
class SleepPersistence(context: Context) {
    private val prefs = context.getSharedPreferences("sulav.sleep.v1", Context.MODE_PRIVATE)
    private val json = Json { ignoreUnknownKeys = true }

    var profile: Profile?
        get() = decode("profile")
        set(value) = encode("profile", value)

    var sessions: List<SleepSession>
        get() = decode<List<SleepSession>>("sessions") ?: emptyList()
        set(value) = encode("sessions", value)

    var activeSession: ActiveSleepSession?
        get() = decode("active")
        set(value) = encode("active", value)

    var account: AppAccount?
        get() = decode("account")
        set(value) = encode("account", value)

    /**
     * The last account signed in on this install. Survives sign-out so the
     * next sign-in can tell a returning user (keep local data) from a
     * different user on a shared device (wipe it).
     */
    var lastAccountID: String?
        get() = prefs.getString("lastAccountID", null)
        set(value) = prefs.edit().putString("lastAccountID", value).apply()

    /** Wipe after account deletion — no previous user left to protect. */
    fun reset() {
        prefs.edit()
            .remove("profile").remove("sessions").remove("active")
            .remove("account").remove("lastAccountID")
            .apply()
    }

    private inline fun <reified T> decode(key: String): T? {
        val raw = prefs.getString(key, null) ?: return null
        return runCatching { json.decodeFromString<T>(raw) }.getOrNull()
    }

    private inline fun <reified T> encode(key: String, value: T?) {
        if (value == null) {
            prefs.edit().remove(key).apply()
        } else {
            prefs.edit().putString(key, json.encodeToString(serializer(), value)).apply()
        }
    }
}
