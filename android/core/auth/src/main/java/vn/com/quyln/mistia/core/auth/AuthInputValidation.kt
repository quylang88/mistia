package vn.com.quyln.mistia.core.auth

enum class AuthMode { MENU, SIGN_IN, SIGN_UP, RESET_PASSWORD, CONFIRM_EMAIL }
enum class AuthField { NAME, EMAIL, PASSWORD, CONFIRM_PASSWORD }
enum class AuthInputError { NAME_REQUIRED, EMAIL_INVALID, PASSWORD_REQUIRED, PASSWORD_LENGTH, PASSWORD_UPPERCASE, PASSWORD_LOWERCASE, CONFIRM_REQUIRED, PASSWORD_MISMATCH }

/** Mirrors ManagementAuthView's validation; existing passwords keep their original rules. */
object AuthInputValidation {
    fun validate(
        mode: AuthMode,
        email: String,
        password: String = "",
        confirmation: String = "",
        displayName: String = "",
    ): Map<AuthField, AuthInputError> = buildMap {
        if (mode == AuthMode.MENU || mode == AuthMode.CONFIRM_EMAIL) return@buildMap
        if (!Regex("^\\S+@\\S+\\.\\S+$").matches(email.trim())) put(AuthField.EMAIL, AuthInputError.EMAIL_INVALID)
        if (mode == AuthMode.SIGN_IN && password.isEmpty()) put(AuthField.PASSWORD, AuthInputError.PASSWORD_REQUIRED)
        if (mode == AuthMode.SIGN_UP) {
            if (displayName.isBlank()) put(AuthField.NAME, AuthInputError.NAME_REQUIRED)
            val passwordError = when {
                Regex("\\X").findAll(password).count() < 8 -> AuthInputError.PASSWORD_LENGTH
                !password.codePoints().anyMatch(Character::isUpperCase) -> AuthInputError.PASSWORD_UPPERCASE
                !password.codePoints().anyMatch(Character::isLowerCase) -> AuthInputError.PASSWORD_LOWERCASE
                else -> null
            }
            passwordError?.let { put(AuthField.PASSWORD, it) }
            when {
                confirmation.isEmpty() -> put(AuthField.CONFIRM_PASSWORD, AuthInputError.CONFIRM_REQUIRED)
                confirmation != password -> put(AuthField.CONFIRM_PASSWORD, AuthInputError.PASSWORD_MISMATCH)
            }
        }
    }
}
