package vn.com.quyln.mistia.core.auth

import org.junit.Assert.*
import org.junit.Test

class AuthInputValidationTest {
    @Test fun signInDoesNotApplyNewPasswordStrengthToExistingAccounts() {
        assertTrue(AuthInputValidation.validate(AuthMode.SIGN_IN, " user@example.test ", "old", "", "").isEmpty())
    }
    @Test fun signupMatchesSwiftLengthAndCaseRequirements() {
        assertEquals(AuthInputError.PASSWORD_LENGTH, validate("Abc")[AuthField.PASSWORD])
        assertEquals(AuthInputError.PASSWORD_UPPERCASE, validate("abcdefgh")[AuthField.PASSWORD])
        assertEquals(AuthInputError.PASSWORD_LOWERCASE, validate("ABCDEFGH")[AuthField.PASSWORD])
        assertTrue(validate("Abcdefgh").isEmpty())
    }
    @Test fun signupRequiresNameAndMatchingConfirmation() {
        val errors = AuthInputValidation.validate(AuthMode.SIGN_UP, "u@example.test", "Abcdefgh", "different", "  ")
        assertEquals(AuthInputError.NAME_REQUIRED, errors[AuthField.NAME])
        assertEquals(AuthInputError.PASSWORD_MISMATCH, errors[AuthField.CONFIRM_PASSWORD])
    }
    @Test fun malformedEmailsNeverReachTheRepository() {
        listOf("", "user", "user@host", "user name@example.test").forEach {
            assertEquals(AuthInputError.EMAIL_INVALID, AuthInputValidation.validate(AuthMode.RESET_PASSWORD, it)[AuthField.EMAIL])
        }
    }
    @Test fun googleNonceUsesSha256WithRawValueKeptSeparate() {
        assertEquals("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", GoogleNonce.sha256("abc"))
        val first = GoogleNonce.create()
        val second = GoogleNonce.create()
        assertNotEquals(first.raw, second.raw)
        assertEquals(64, first.hashed.length)
        assertEquals(GoogleNonce.sha256(first.raw), first.hashed)
        assertFalse(first.toString().contains(first.raw))
    }
    private fun validate(password: String) = AuthInputValidation.validate(AuthMode.SIGN_UP, "u@example.test", password, password, "Test")
}
