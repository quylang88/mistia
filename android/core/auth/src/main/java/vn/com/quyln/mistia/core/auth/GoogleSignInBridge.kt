package vn.com.quyln.mistia.core.auth

import android.content.Context
import android.content.MutableContextWrapper
import androidx.credentials.ClearCredentialStateRequest
import androidx.credentials.CredentialManager
import androidx.credentials.CustomCredential
import androidx.credentials.GetCredentialRequest
import androidx.credentials.exceptions.GetCredentialCancellationException
import androidx.credentials.exceptions.GetCredentialException
import androidx.credentials.exceptions.NoCredentialException
import androidx.credentials.exceptions.GetCredentialProviderConfigurationException
import com.google.android.libraries.identity.googleid.GetSignInWithGoogleOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential

class GoogleIdentity(val idToken: String, val rawNonce: String) {
    override fun toString() = "GoogleIdentity(redacted)"
}
class GoogleSignInCancelled : Exception()

class GoogleSignInBridge(private val serverClientId: String, private val diagnostics: AuthDiagnostics = AuthDiagnostics.NONE) : GoogleSignInProvider {
    override val configured: Boolean get() = serverClientId.endsWith(".apps.googleusercontent.com")

    override suspend fun acquire(activityContext: Context): GoogleIdentity {
        check(configured) { "Google client configuration is missing" }
        val nonce = GoogleNonce.create()
        val option = GetSignInWithGoogleOption.Builder(serverClientId).setNonce(nonce.hashed).build()
        diagnostics.record(AuthDiagnosticEvent.GOOGLE_PICKER_STARTED)
        val result = try { CredentialManager.create(activityContext).getCredential(
            MutableContextWrapper(activityContext),
            GetCredentialRequest.Builder().addCredentialOption(option).build(),
        ) } catch (_: GetCredentialCancellationException) {
            diagnostics.record(AuthDiagnosticEvent.GOOGLE_PICKER_CANCELLED)
            throw GoogleSignInCancelled()
        } catch (error: GetCredentialException) {
            diagnostics.record(when (error) {
                is NoCredentialException -> AuthDiagnosticEvent.GOOGLE_PICKER_NO_CREDENTIAL
                is GetCredentialProviderConfigurationException -> AuthDiagnosticEvent.GOOGLE_PICKER_CONFIGURATION_ERROR
                else -> AuthDiagnosticEvent.GOOGLE_PICKER_FAILED
            })
            throw error
        }
        val credential = result.credential
        if (credential !is CustomCredential || credential.type != GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL) {
            diagnostics.record(AuthDiagnosticEvent.GOOGLE_UNEXPECTED_CREDENTIAL)
            error("Unexpected credential type")
        }
        val token = try { GoogleIdTokenCredential.createFrom(credential.data).idToken }
        catch (error: Exception) {
            diagnostics.record(AuthDiagnosticEvent.GOOGLE_TOKEN_PARSE_FAILED)
            throw error
        }
        diagnostics.record(AuthDiagnosticEvent.GOOGLE_TOKEN_RECEIVED)
        return GoogleIdentity(token, nonce.raw)
    }

    companion object {
        suspend fun clear(context: Context) {
            CredentialManager.create(context).clearCredentialState(ClearCredentialStateRequest())
        }
    }
}
