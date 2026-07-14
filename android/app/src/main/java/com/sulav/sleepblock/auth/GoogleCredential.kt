package com.sulav.sleepblock.auth

import android.app.Activity
import androidx.credentials.CredentialManager
import androidx.credentials.GetCredentialRequest
import androidx.credentials.exceptions.GetCredentialCancellationException
import androidx.credentials.exceptions.GetCredentialException
import androidx.credentials.exceptions.NoCredentialException
import com.google.android.libraries.identity.googleid.GetGoogleIdOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import com.sulav.sleepblock.BuildConfig

/**
 * Google sign-in via Credential Manager (the Android sibling of the iOS
 * ASWebAuthenticationSession flow). Returns a Google ID token minted against
 * the project's *web* client id — the same id Supabase's Google provider is
 * configured with — which the auth client exchanges via the id_token grant.
 */
object GoogleCredential {

    suspend fun idToken(activity: Activity): String {
        val clientId = BuildConfig.GOOGLE_WEB_CLIENT_ID
        if (clientId.isEmpty() || clientId.startsWith("your-")) {
            throw AuthException.Unknown("Google sign-in isn't configured yet.")
        }
        val request = GetCredentialRequest.Builder()
            .addCredentialOption(
                GetGoogleIdOption.Builder()
                    .setServerClientId(clientId)
                    .setFilterByAuthorizedAccounts(false)
                    .build()
            )
            .build()
        val result = try {
            CredentialManager.create(activity).getCredential(activity, request)
        } catch (e: GetCredentialCancellationException) {
            throw AuthException.Cancelled
        } catch (e: NoCredentialException) {
            throw AuthException.Unknown("No Google account available on this device.")
        } catch (e: GetCredentialException) {
            throw AuthException.Unknown(e.message ?: "Google sign-in failed.")
        }
        val credential = result.credential
        if (credential.type != GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL) {
            throw AuthException.Unknown("Google sign-in returned an unexpected credential.")
        }
        return GoogleIdTokenCredential.createFrom(credential.data).idToken
    }
}
