package vn.com.quyln.mistia.auth

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import java.io.IOException
import javax.inject.Inject
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import vn.com.quyln.mistia.core.auth.*
import vn.com.quyln.mistia.core.model.AuthRepository
import vn.com.quyln.mistia.core.network.SupabaseHttpException

enum class AuthNotice { INVALID_CREDENTIALS, CONFIRM_EMAIL, RESET_SENT, CONFIRMATION_SENT, NETWORK, RATE_LIMITED, GOOGLE_SETUP, GOOGLE_FAILED, GENERAL }
data class AuthScreenState(
    val mode: AuthMode = AuthMode.MENU,
    val busy: Boolean = false,
    val errors: Map<AuthField, AuthInputError> = emptyMap(),
    val notice: AuthNotice? = null,
    val clearPasswordsVersion: Int = 0,
)

@HiltViewModel
class AuthViewModel @Inject constructor(
    private val repository: AuthRepository,
    private val google: GoogleSignInProvider,
    private val diagnostics: AuthDiagnostics = AuthDiagnostics.NONE,
) : ViewModel() {
    private val mutableState = MutableStateFlow(AuthScreenState())
    val state = mutableState.asStateFlow()
    private var confirmationEmail = ""

    fun show(mode: AuthMode) {
        if (state.value.busy) return
        mutableState.value = state.value.copy(mode = mode, errors = emptyMap(), notice = null,
            clearPasswordsVersion = state.value.clearPasswordsVersion + 1)
    }

    fun submit(email: String, password: String, confirmation: String, name: String) {
        if (state.value.busy) return
        val mode = state.value.mode
        val errors = AuthInputValidation.validate(mode, email, password, confirmation, name)
        mutableState.value = state.value.copy(errors = errors, notice = null)
        if (errors.isNotEmpty() || mode !in setOf(AuthMode.SIGN_IN, AuthMode.SIGN_UP, AuthMode.RESET_PASSWORD)) return
        confirmationEmail = email.trim()
        perform {
            when (mode) {
                AuthMode.SIGN_IN -> repository.signIn(email.trim(), password).getOrThrow()
                AuthMode.SIGN_UP -> {
                    if (repository.signUp(email.trim(), password, name.trim()).getOrThrow() == null) {
                        mutableState.value = state.value.copy(mode = AuthMode.CONFIRM_EMAIL, notice = AuthNotice.CONFIRM_EMAIL)
                    }
                }
                AuthMode.RESET_PASSWORD -> {
                    repository.sendPasswordReset(email.trim()).getOrThrow()
                    mutableState.value = state.value.copy(notice = AuthNotice.RESET_SENT)
                }
                else -> Unit
            }
            mutableState.value = state.value.copy(clearPasswordsVersion = state.value.clearPasswordsVersion + 1)
        }
    }

    fun resendConfirmation() {
        if (confirmationEmail.isBlank() || state.value.busy) return
        perform {
            repository.resendConfirmation(confirmationEmail).getOrThrow()
            mutableState.value = state.value.copy(notice = AuthNotice.CONFIRMATION_SENT)
        }
    }

    fun signInWithGoogle(context: Context) {
        if (state.value.busy) return
        if (!google.configured) {
            mutableState.value = state.value.copy(notice = AuthNotice.GOOGLE_SETUP)
            return
        }
        perform(googleAction = true) {
            val identity = google.acquire(context)
            diagnostics.record(AuthDiagnosticEvent.GOOGLE_EXCHANGE_STARTED)
            try {
                repository.exchangeGoogleIdToken(identity.idToken, identity.rawNonce).getOrThrow()
                diagnostics.record(AuthDiagnosticEvent.GOOGLE_EXCHANGE_SUCCEEDED)
            } catch (error: CancellationException) { throw error }
            catch (error: Exception) {
                diagnostics.record(when (error) {
                    is SupabaseHttpException -> AuthDiagnosticEvent.GOOGLE_EXCHANGE_REJECTED
                    is IOException -> AuthDiagnosticEvent.GOOGLE_EXCHANGE_NETWORK_ERROR
                    else -> AuthDiagnosticEvent.GOOGLE_EXCHANGE_FAILED
                })
                throw error
            }
        }
    }

    private fun perform(googleAction: Boolean = false, action: suspend () -> Unit) {
        mutableState.value = state.value.copy(busy = true, notice = null)
        viewModelScope.launch {
            try { action() }
            catch (error: CancellationException) { throw error }
            catch (_: GoogleSignInCancelled) {
                // Google can also report cancellation for authorization/configuration failures.
                // Give neutral feedback and never automatically repeat a consent flow.
                mutableState.value = state.value.copy(notice = AuthNotice.GOOGLE_FAILED)
            }
            catch (error: Exception) {
                val code = (error as? SupabaseHttpException)?.let {
                    runCatching { Json.parseToJsonElement(it.responseBody).jsonObject["error_code"]?.jsonPrimitive?.content }.getOrNull()
                }
                val notice = when {
                    code == "email_not_confirmed" -> AuthNotice.CONFIRM_EMAIL
                    code == "invalid_credentials" -> AuthNotice.INVALID_CREDENTIALS
                    error is SupabaseHttpException && error.statusCode == 429 -> AuthNotice.RATE_LIMITED
                    error is IOException && error !is SupabaseHttpException -> AuthNotice.NETWORK
                    googleAction -> AuthNotice.GOOGLE_FAILED
                    else -> AuthNotice.GENERAL
                }
                mutableState.value = state.value.copy(notice = notice,
                    mode = if (notice == AuthNotice.CONFIRM_EMAIL) AuthMode.CONFIRM_EMAIL else state.value.mode,
                    clearPasswordsVersion = if (notice == AuthNotice.CONFIRM_EMAIL) state.value.clearPasswordsVersion + 1 else state.value.clearPasswordsVersion)
            } finally { mutableState.value = state.value.copy(busy = false) }
        }
    }
}
