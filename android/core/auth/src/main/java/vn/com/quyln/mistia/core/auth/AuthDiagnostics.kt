package vn.com.quyln.mistia.core.auth

/** Deliberately accepts fixed events only: no tokens, email, nonce, response body or exception message. */
fun interface AuthDiagnostics {
    fun record(event: AuthDiagnosticEvent)
    companion object { val NONE = AuthDiagnostics {} }
}

enum class AuthDiagnosticEvent {
    GOOGLE_PICKER_STARTED, GOOGLE_PICKER_CANCELLED, GOOGLE_PICKER_NO_CREDENTIAL,
    GOOGLE_PICKER_CONFIGURATION_ERROR, GOOGLE_PICKER_FAILED, GOOGLE_UNEXPECTED_CREDENTIAL,
    GOOGLE_TOKEN_PARSE_FAILED, GOOGLE_TOKEN_RECEIVED, GOOGLE_EXCHANGE_STARTED, GOOGLE_EXCHANGE_SUCCEEDED,
    GOOGLE_EXCHANGE_REJECTED, GOOGLE_EXCHANGE_NETWORK_ERROR, GOOGLE_EXCHANGE_FAILED,
}
