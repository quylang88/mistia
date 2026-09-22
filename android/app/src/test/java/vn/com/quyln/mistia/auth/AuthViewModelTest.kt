package vn.com.quyln.mistia.auth

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.*
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import vn.com.quyln.mistia.core.auth.*
import vn.com.quyln.mistia.core.model.*
import vn.com.quyln.mistia.core.network.SupabaseHttpException

@OptIn(ExperimentalCoroutinesApi::class)
class AuthViewModelTest {
    private val dispatcher = StandardTestDispatcher()
    @Before fun setup() { Dispatchers.setMain(dispatcher) }
    @After fun teardown() { Dispatchers.resetMain() }

    @Test fun invalidEmailNeverSubmitsToAuthRepository() = runTest(dispatcher) {
        val repo = FakeAuth()
        val model = model(repo)
        model.show(AuthMode.SIGN_IN)
        model.submit("invalid", "password", "", "")
        advanceUntilIdle()
        assertEquals(0, repo.signInCalls)
        assertEquals(AuthInputError.EMAIL_INVALID, model.state.value.errors[AuthField.EMAIL])
    }
    @Test fun signupConfirmationClearsPasswordsAndResendsToOriginalEmail() = runTest(dispatcher) {
        val repo = FakeAuth(); val model = model(repo)
        model.show(AuthMode.SIGN_UP)
        val before = model.state.value.clearPasswordsVersion
        model.submit(" user@example.test ", "Password", "Password", " Name ")
        advanceUntilIdle()
        assertEquals(AuthMode.CONFIRM_EMAIL, model.state.value.mode)
        assertEquals("Name", repo.signupName)
        assertTrue(model.state.value.clearPasswordsVersion > before)
        model.resendConfirmation(); advanceUntilIdle()
        assertEquals("user@example.test", repo.resentEmail)
        assertEquals(AuthNotice.CONFIRMATION_SENT, model.state.value.notice)
    }
    @Test fun duplicateTapDoesNotSendDuplicateLoginRequest() = runTest(dispatcher) {
        val repo = FakeAuth(); val model = model(repo)
        model.show(AuthMode.SIGN_IN)
        repeat(2) { model.submit("u@example.test", "password", "", "") }
        advanceUntilIdle()
        assertEquals(1, repo.signInCalls)
        assertFalse(model.state.value.busy)
    }
    @Test fun incorrectCredentialsProduceLocalizedErrorCategoryOnly() = runTest(dispatcher) {
        val repo = FakeAuth().apply { failure = SupabaseHttpException(400, "{\"error_code\":\"invalid_credentials\",\"secret\":\"private\"}") }
        val model = model(repo)
        model.show(AuthMode.SIGN_IN); model.submit("u@example.test", "wrong", "", "")
        advanceUntilIdle()
        assertEquals(AuthNotice.INVALID_CREDENTIALS, model.state.value.notice)
        assertFalse(model.state.value.toString().contains("private"))
    }
    @Test fun unconfirmedLoginOffersResendInsteadOfGenericFailure() = runTest(dispatcher) {
        val repo = FakeAuth().apply { failure = SupabaseHttpException(400, "{\"error_code\":\"email_not_confirmed\"}") }
        val model = model(repo)
        model.show(AuthMode.SIGN_IN); model.submit("u@example.test", "password", "", "")
        advanceUntilIdle()
        assertEquals(AuthMode.CONFIRM_EMAIL, model.state.value.mode)
        assertFalse(model.state.value.busy)
    }
    @Test fun passwordResetReportsSuccessWithoutClaimingAccountExists() = runTest(dispatcher) {
        val repo = FakeAuth(); val model = model(repo)
        model.show(AuthMode.RESET_PASSWORD); model.submit("u@example.test", "", "", "")
        advanceUntilIdle()
        assertEquals("u@example.test", repo.resetEmail)
        assertEquals(AuthNotice.RESET_SENT, model.state.value.notice)
    }
    @Test fun googleCancellationShowsFeedbackAndDoesNotExchangeToken() = runTest(dispatcher) {
        val repo = FakeAuth()
        val google = object : GoogleSignInProvider {
            override val configured = true
            override suspend fun acquire(activityContext: android.content.Context): GoogleIdentity = throw GoogleSignInCancelled()
        }
        val model = AuthViewModel(repo, google)
        model.signInWithGoogle(org.mockito.Mockito.mock(android.content.Context::class.java))
        advanceUntilIdle()
        assertEquals(AuthNotice.GOOGLE_FAILED, model.state.value.notice)
        assertFalse(model.state.value.busy)
        assertEquals(0, repo.googleExchanges)
    }

    @Test fun googleIdentityIsExchangedWithOriginalNonceAndPublishesSession() = runTest(dispatcher) {
        val repo = FakeAuth()
        val events = mutableListOf<AuthDiagnosticEvent>()
        val model = AuthViewModel(repo, fakeGoogle(), AuthDiagnostics { events += it })
        model.signInWithGoogle(org.mockito.Mockito.mock(android.content.Context::class.java))
        advanceUntilIdle()
        assertEquals("id-token", repo.exchangedToken)
        assertEquals("raw-nonce", repo.exchangedNonce)
        assertTrue(repo.state.value is AuthState.SignedIn)
        assertEquals(listOf(AuthDiagnosticEvent.GOOGLE_EXCHANGE_STARTED, AuthDiagnosticEvent.GOOGLE_EXCHANGE_SUCCEEDED), events)
        assertFalse(model.state.value.busy)
    }

    @Test fun rejectedGoogleExchangeShowsFeedbackWithoutPublishingSession() = runTest(dispatcher) {
        val repo = FakeAuth().apply { failure = SupabaseHttpException(400, "private-token-response") }
        val events = mutableListOf<AuthDiagnosticEvent>()
        val model = AuthViewModel(repo, fakeGoogle(), AuthDiagnostics { events += it })
        model.signInWithGoogle(org.mockito.Mockito.mock(android.content.Context::class.java))
        advanceUntilIdle()
        assertEquals(AuthNotice.GOOGLE_FAILED, model.state.value.notice)
        assertEquals(AuthState.SignedOut, repo.state.value)
        assertEquals(listOf(AuthDiagnosticEvent.GOOGLE_EXCHANGE_STARTED, AuthDiagnosticEvent.GOOGLE_EXCHANGE_REJECTED), events)
        assertFalse(model.state.value.toString().contains("private-token-response"))
    }

    private fun fakeGoogle() = object : GoogleSignInProvider {
        override val configured = true
        override suspend fun acquire(activityContext: android.content.Context) = GoogleIdentity("id-token", "raw-nonce")
    }

    private fun model(repo: FakeAuth) = AuthViewModel(repo, GoogleSignInBridge("test.apps.googleusercontent.com"))

    private class FakeAuth : AuthRepository {
        override val state = MutableStateFlow<AuthState>(AuthState.SignedOut)
        var failure: Exception? = null
        var signInCalls = 0
        var googleExchanges = 0
        var exchangedToken: String? = null
        var exchangedNonce: String? = null
        var signupName: String? = null
        var resentEmail: String? = null
        var resetEmail: String? = null
        override suspend fun restore() = Unit
        override suspend fun signIn(email: String, password: String): Result<AuthSession> {
            signInCalls++
            return failure?.let { Result.failure(it) } ?: Result.success(AuthSession(UserId("u"), email, "a", "r", 9999))
        }
        override suspend fun signUp(email: String, password: String, displayName: String): Result<AuthSession?> {
            signupName = displayName
            return Result.success(null)
        }
        override suspend fun resendConfirmation(email: String): Result<Unit> { resentEmail = email; return Result.success(Unit) }
        override suspend fun sendPasswordReset(email: String): Result<Unit> { resetEmail = email; return Result.success(Unit) }
        override suspend fun exchangeGoogleIdToken(idToken: String, nonce: String?): Result<AuthSession> {
            googleExchanges++
            exchangedToken = idToken
            exchangedNonce = nonce
            failure?.let { return Result.failure(it) }
            val session = AuthSession(UserId("u"), "test@example.test", "access", "refresh", 9999)
            state.value = AuthState.SignedIn(session)
            return Result.success(session)
        }
        override suspend fun refreshIfNeeded() = Result.success<AuthSession?>(null)
        override suspend fun signOut(clearLocalSession: Boolean) = Unit
    }
}
