package com.sulav.sleepblock.auth

import android.content.Context
import android.util.Log
import com.sulav.sleepblock.BuildConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.encodeToJsonElement
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.IOException
import java.time.Instant
import kotlin.math.abs

/**
 * Account auth against the same Supabase project as the iOS app, hand-rolled
 * over GoTrue's REST endpoints — the app only needs a small surface (email
 * auth, user-metadata profile sync, sign-out, the delete-account Edge
 * Function), so a dedicated SDK isn't worth the dependency. Mirrors
 * ios/SulavSleep/Auth/SupabaseAuthClient.swift; see docs/android.md.
 */
interface AuthProviding {
    suspend fun currentAccount(): AppAccount?
    suspend fun signUp(email: String, password: String): AuthResult
    suspend fun signIn(email: String, password: String): AuthResult
    suspend fun signOut()
    suspend fun fetchRemoteProfile(): RemoteProfile?
    suspend fun saveRemoteProfile(profile: RemoteProfile)
    suspend fun clearLocalSession()
    suspend fun deleteAccount()
}

object SulavAuth {
    /** Real client when BuildConfig has real values, else a no-op (dev mode). */
    fun makeDefault(context: Context): AuthProviding {
        val url = BuildConfig.SUPABASE_URL
        val key = BuildConfig.SUPABASE_ANON_KEY
        if (url.isEmpty() || key.isEmpty() || !url.startsWith("http") || key.startsWith("your-")) {
            Log.i(TAG, "Supabase config missing — auth will show errors until android/secrets.properties is set up")
            return DisabledAuthClient
        }
        return SupabaseAuthClient(context, url.trimEnd('/'), key)
    }

    const val TAG = "SleepAuth"
}

object DisabledAuthClient : AuthProviding {
    override suspend fun currentAccount(): AppAccount? = null
    override suspend fun signUp(email: String, password: String): AuthResult =
        throw AuthException.Unknown("Sign-in isn't configured yet.")
    override suspend fun signIn(email: String, password: String): AuthResult =
        throw AuthException.Unknown("Sign-in isn't configured yet.")
    override suspend fun signOut() {}
    override suspend fun fetchRemoteProfile(): RemoteProfile? = null
    override suspend fun saveRemoteProfile(profile: RemoteProfile) {}
    override suspend fun clearLocalSession() {}
    override suspend fun deleteAccount(): Unit =
        throw AuthException.Unknown("Account deletion isn't configured yet.")
}

// MARK: - Stored session

private class StoredSession(
    val accessToken: String,
    val refreshToken: String,
    val expiresAt: Long,
    val userJson: String,
) {
    val isExpired: Boolean get() = Instant.now().epochSecond > expiresAt - 60
}

class SupabaseAuthClient(
    context: Context,
    private val baseUrl: String,
    private val anonKey: String,
) : AuthProviding {

    // App-private storage; fine for a session token on a non-rooted device.
    // (iOS uses the Keychain via supabase-swift; Android has no free
    // equivalent without the deprecated EncryptedSharedPreferences.)
    private val prefs = context.getSharedPreferences("sulav.auth.v1", Context.MODE_PRIVATE)
    private val http = OkHttpClient()
    private val json = Json { ignoreUnknownKeys = true }
    private val jsonMedia = "application/json; charset=utf-8".toMediaType()

    // MARK: Session persistence

    private fun loadSession(): StoredSession? {
        val access = prefs.getString("access", null) ?: return null
        val refresh = prefs.getString("refresh", null) ?: return null
        val user = prefs.getString("user", null) ?: return null
        return StoredSession(access, refresh, prefs.getLong("expiresAt", 0), user)
    }

    private fun saveSession(sessionJson: JsonObject) {
        val access = sessionJson["access_token"]?.jsonPrimitive?.content ?: return
        val refresh = sessionJson["refresh_token"]?.jsonPrimitive?.content ?: return
        val expiresIn = sessionJson["expires_in"]?.jsonPrimitive?.content?.toLongOrNull() ?: 3600
        val user = sessionJson["user"]?.jsonObject ?: return
        prefs.edit()
            .putString("access", access)
            .putString("refresh", refresh)
            .putLong("expiresAt", Instant.now().epochSecond + expiresIn)
            .putString("user", user.toString())
            .apply()
    }

    private fun dropSession() {
        prefs.edit().clear().apply()
    }

    // MARK: AuthProviding

    override suspend fun currentAccount(): AppAccount? {
        // Local-first, like iOS: identity comes from the stored session, never
        // a launch-blocking network call. Expired tokens refresh lazily on the
        // next authenticated request.
        val session = loadSession() ?: return null
        return runCatching {
            account(json.parseToJsonElement(session.userJson).jsonObject)
        }.getOrNull()
    }

    override suspend fun signUp(email: String, password: String): AuthResult = withContext(Dispatchers.IO) {
        val body = buildJsonObject {
            put("email", email)
            put("password", password)
        }
        val response = request("POST", "$baseUrl/auth/v1/signup", body)
        // No access_token means the project requires email confirmation first —
        // a calm notice, not a failure.
        if (response["access_token"] == null) throw AuthException.ConfirmationEmailSent
        saveSession(response)
        val user = response["user"]!!.jsonObject
        Log.i(SulavAuth.TAG, "Signed up with email")
        AuthResult(account(user), isNewAccount = true, remoteProfile = null)
    }

    override suspend fun signIn(email: String, password: String): AuthResult = withContext(Dispatchers.IO) {
        val body = buildJsonObject {
            put("email", email)
            put("password", password)
        }
        val response = request("POST", "$baseUrl/auth/v1/token?grant_type=password", body)
        saveSession(response)
        val user = response["user"]!!.jsonObject
        Log.i(SulavAuth.TAG, "Signed in with email")
        AuthResult(account(user), isNewAccount = isNewAccount(user), remoteProfile = remoteProfile(user))
    }

    override suspend fun signOut(): Unit = withContext(Dispatchers.IO) {
        val token = validAccessToken()
        dropSession()
        if (token != null) {
            runCatching { request("POST", "$baseUrl/auth/v1/logout", body = null, bearer = token) }
        }
        Log.i(SulavAuth.TAG, "Signed out")
    }

    override suspend fun fetchRemoteProfile(): RemoteProfile? = withContext(Dispatchers.IO) {
        // Prefer a fresh server read; fall back to the stored session's copy offline.
        val token = validAccessToken()
        if (token != null) {
            val fresh = runCatching { request("GET", "$baseUrl/auth/v1/user", body = null, bearer = token) }
            fresh.getOrNull()?.let { return@withContext remoteProfile(it) }
        }
        val stored = loadSession() ?: return@withContext null
        runCatching {
            remoteProfile(json.parseToJsonElement(stored.userJson).jsonObject)
        }.getOrNull()
    }

    override suspend fun saveRemoteProfile(profile: RemoteProfile): Unit = withContext(Dispatchers.IO) {
        val token = validAccessToken() ?: return@withContext
        val body = buildJsonObject {
            put("data", buildJsonObject {
                put(PROFILE_METADATA_KEY, json.encodeToJsonElement(profile))
            })
        }
        runCatching { request("PUT", "$baseUrl/auth/v1/user", body, bearer = token) }
            .onSuccess {
                // Keep the cached user current so an offline restore sees it.
                prefs.edit().putString("user", it.toString()).apply()
                Log.i(SulavAuth.TAG, "Cloud profile saved")
            }
            .onFailure { Log.e(SulavAuth.TAG, "Cloud profile save failed: ${it.message}") }
    }

    override suspend fun clearLocalSession() {
        // Local only, never a server round-trip (reinstall reset at launch).
        dropSession()
    }

    override suspend fun deleteAccount(): Unit = withContext(Dispatchers.IO) {
        val token = validAccessToken() ?: throw AuthException.Unknown("You're not signed in.")
        request("POST", "$baseUrl/functions/v1/delete-account", buildJsonObject {}, bearer = token)
        // Server-side user is gone; only the local session needs clearing.
        dropSession()
        Log.i(SulavAuth.TAG, "Account deleted")
    }

    // MARK: Token refresh

    private fun validAccessToken(): String? {
        val session = loadSession() ?: return null
        if (!session.isExpired) return session.accessToken
        return runCatching {
            val refreshed = request(
                "POST", "$baseUrl/auth/v1/token?grant_type=refresh_token",
                buildJsonObject { put("refresh_token", session.refreshToken) }
            )
            saveSession(refreshed)
            refreshed["access_token"]!!.jsonPrimitive.content
        }.getOrNull()
    }

    // MARK: HTTP

    private fun request(method: String, url: String, body: JsonObject?, bearer: String? = null): JsonObject {
        val builder = Request.Builder()
            .url(url)
            .header("apikey", anonKey)
            .header("Authorization", "Bearer ${bearer ?: anonKey}")
        when (method) {
            "GET" -> builder.get()
            else -> builder.method(method, (body ?: buildJsonObject {}).toString().toRequestBody(jsonMedia))
        }
        val response = try {
            http.newCall(builder.build()).execute()
        } catch (e: IOException) {
            throw AuthException.Network
        }
        response.use {
            val text = it.body?.string().orEmpty()
            if (!it.isSuccessful) throw mapError(it.code, text)
            if (text.isBlank()) return buildJsonObject {}
            return json.parseToJsonElement(text).jsonObject
        }
    }

    private fun mapError(code: Int, body: String): AuthException {
        val parsed = runCatching { json.parseToJsonElement(body).jsonObject }.getOrNull()
        val errorCode = parsed?.get("error_code")?.jsonPrimitive?.content
        val message = parsed?.get("msg")?.jsonPrimitive?.content
            ?: parsed?.get("error_description")?.jsonPrimitive?.content
            ?: parsed?.get("message")?.jsonPrimitive?.content
            ?: "Something went wrong ($code)."
        return when (errorCode) {
            "invalid_credentials" -> AuthException.InvalidCredentials
            "user_already_exists", "email_exists" -> AuthException.EmailAlreadyRegistered
            "email_not_confirmed" -> AuthException.EmailNotConfirmed
            "weak_password" -> AuthException.WeakPassword(message)
            "over_request_rate_limit", "over_email_send_rate_limit" -> AuthException.RateLimited
            else -> {
                val lower = message.lowercase()
                if ("invalid" in lower || "credentials" in lower) AuthException.InvalidCredentials
                else AuthException.Unknown(message)
            }
        }
    }

    // MARK: User parsing

    private fun account(user: JsonObject): AppAccount {
        val provider = user["app_metadata"]?.jsonObject?.get("provider")?.jsonPrimitive?.content
        return AppAccount(
            id = user["id"]!!.jsonPrimitive.content,
            email = user["email"]?.jsonPrimitive?.content?.ifEmpty { null },
            provider = when (provider) {
                "apple" -> AuthProvider.APPLE
                "google" -> AuthProvider.GOOGLE
                else -> AuthProvider.EMAIL
            },
        )
    }

    private fun remoteProfile(user: JsonObject): RemoteProfile? {
        val metadata = user["user_metadata"]?.jsonObject ?: return null
        val stored = metadata[PROFILE_METADATA_KEY]?.jsonObject ?: return null
        val profile = runCatching { json.decodeFromJsonElement<RemoteProfile>(stored) }.getOrNull() ?: return null
        // Reject garbage a different/older client might have written.
        if (profile.bedtime !in 0 until 1_440 || profile.wakeTime !in 0 until 1_440) return null
        return profile
    }

    /**
     * GoTrue doesn't expose an explicit "new user" flag; a brand-new user's
     * first sign-in coincides with its creation (same heuristic as iOS).
     */
    private fun isNewAccount(user: JsonObject): Boolean {
        val created = user["created_at"]?.jsonPrimitive?.content ?: return true
        val lastSignIn = user["last_sign_in_at"]?.jsonPrimitive?.content ?: return true
        return runCatching {
            abs(Instant.parse(lastSignIn).epochSecond - Instant.parse(created).epochSecond) < 5
        }.getOrDefault(true)
    }

    private companion object {
        /** Key inside auth.users.user_metadata holding the synced profile (same as iOS). */
        const val PROFILE_METADATA_KEY = "sleep_profile"
    }
}
