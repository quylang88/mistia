package vn.com.quyln.mistia.core.auth

import kotlinx.coroutines.*
import java.util.concurrent.TimeUnit
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.tls.HandshakeCertificates
import okhttp3.tls.HeldCertificate
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import vn.com.quyln.mistia.core.model.AuthSession
import vn.com.quyln.mistia.core.model.AuthState
import vn.com.quyln.mistia.core.model.UserId
import vn.com.quyln.mistia.core.network.SupabaseConfig
import vn.com.quyln.mistia.core.network.SupabaseHttpException

class SupabaseAuthRepositoryTest {
    private lateinit var server: MockWebServer
    private lateinit var repository: SupabaseAuthRepository
    private val store = MemorySessionStore()
    private var credentialsCleared = false

    @Before fun setup() {
        val cert = HeldCertificate.Builder().addSubjectAlternativeName("localhost").build()
        val serverTls = HandshakeCertificates.Builder().heldCertificate(cert).build()
        val clientTls = HandshakeCertificates.Builder().addTrustedCertificate(cert.certificate).build()
        server = MockWebServer().apply { useHttps(serverTls.sslSocketFactory(), false); start() }
        repository = SupabaseAuthRepository(
            SupabaseConfig(server.url("/").toString(), "public-test-key"),
            OkHttpClient.Builder().sslSocketFactory(clientTls.sslSocketFactory(), clientTls.trustManager).build(),
            store,
            nowEpochSeconds = { 100L },
            clearCredentialState = { credentialsCleared = true },
        )
    }

    @After fun teardown() { server.shutdown() }

    @Test fun emailLoginTrimsEmailButPreservesPassword() = runBlocking {
        server.enqueue(MockResponse().setBody(sessionJson))
        repository.signIn(" user@example.test ", " password ").getOrThrow()
        val request = server.takeRequest()
        assertEquals("/auth/v1/token?grant_type=password", request.path)
        val body = Json.parseToJsonElement(request.body.readUtf8()).jsonObject
        assertEquals("user@example.test", body.getValue("email").jsonPrimitive.content)
        assertEquals(" password ", body.getValue("password").jsonPrimitive.content)
        assertEquals(3700L, store.session?.expiresAtEpochSeconds)
    }

    @Test fun googleExchangeSendsRawNonceAndGoogleProvider() = runBlocking {
        server.enqueue(MockResponse().setBody(sessionJson))
        repository.exchangeGoogleIdToken("test-id-token", "raw-nonce").getOrThrow()
        val request = server.takeRequest()
        assertEquals("/auth/v1/token?grant_type=id_token", request.path)
        val body = Json.parseToJsonElement(request.body.readUtf8()).jsonObject
        assertEquals("google", body.getValue("provider").jsonPrimitive.content)
        assertEquals("test-id-token", body.getValue("id_token").jsonPrimitive.content)
        assertEquals("raw-nonce", body.getValue("nonce").jsonPrimitive.content)
    }

    @Test fun rejectedCredentialsDoNotPersistSession() = runBlocking {
        server.enqueue(MockResponse().setResponseCode(400).setBody("{\"error_code\":\"invalid_credentials\"}"))
        assertTrue(repository.signIn("user@example.test", "wrong").isFailure)
        assertNull(store.session)
        assertFalse(repository.state.value is AuthState.SignedIn)
    }

    @Test fun signupRequiringConfirmationDoesNotCreateSession() = runBlocking {
        server.enqueue(MockResponse().setBody("{\"user\":{\"id\":\"new-user\"}}"))
        assertNull(repository.signUp("new@example.test", "Password123").getOrThrow())
        assertNull(store.session)
    }

    @Test fun signupSendsDisplayNameMetadata() = runBlocking {
        server.enqueue(MockResponse().setBody("{}"))
        repository.signUp(" user@example.test ", "Password", " Name ").getOrThrow()
        val request = server.takeRequest()
        assertEquals("/auth/v1/signup", request.path)
        val body = Json.parseToJsonElement(request.body.readUtf8()).jsonObject
        assertEquals("Name", body.getValue("data").jsonObject.getValue("display_name").jsonPrimitive.content)
        assertEquals("user@example.test", body.getValue("email").jsonPrimitive.content)
    }

    @Test fun confirmationResendUsesSignupTypeWithoutCreatingSession() = runBlocking {
        server.enqueue(MockResponse().setBody("{}"))
        repository.resendConfirmation(" user@example.test ").getOrThrow()
        val request = server.takeRequest()
        assertEquals("/auth/v1/resend", request.path)
        val body = Json.parseToJsonElement(request.body.readUtf8()).jsonObject
        assertEquals("signup", body.getValue("type").jsonPrimitive.content)
        assertEquals("user@example.test", body.getValue("email").jsonPrimitive.content)
        assertNull(store.session)
    }

    @Test fun logoutRemovesLocalSessionEvenWhenServerFails() = runBlocking {
        server.enqueue(MockResponse().setBody(sessionJson))
        repository.signIn("user@example.test", "password").getOrThrow()
        server.enqueue(MockResponse().setResponseCode(503))
        repository.signOut()
        assertNull(store.session)
        assertEquals(AuthState.SignedOut, repository.state.value)
        assertTrue(credentialsCleared)
    }

    @Test fun sessionDiagnosticsNeverExposeCredentials() {
        val text = AuthState.SignedIn(AuthSession(UserId("u"), "user@example.test", "secret-access", "secret-refresh", 100)).toString()
        assertFalse(text.contains("secret-access"))
        assertFalse(text.contains("secret-refresh"))
        assertFalse(text.contains("user@example.test"))
    }

    @Test fun networkExceptionMessageNeverEchoesServerPayload() {
        val error = SupabaseHttpException(400, "{\"access_token\":\"secret-access\"}")
        assertFalse(error.message.orEmpty().contains("secret-access"))
    }

    private fun expiredSession()=AuthSession(UserId("test-user"),null,"old-access","old-refresh",0)
    private fun delayed(body:String,code:Int=200)=MockResponse().setResponseCode(code).setBody(body).setBodyDelay(300,TimeUnit.MILLISECONDS)

    @Test fun lateRefreshCannotRestoreSignedOutOwner()=runBlocking {
        store.session=expiredSession()
        server.enqueue(delayed(sessionJson));server.enqueue(MockResponse().setBody("{}"))
        val restoring=async(start=CoroutineStart.UNDISPATCHED) {runCatching {repository.restore()}}
        server.takeRequest()
        repository.signOut()
        restoring.await()
        assertNull(store.session);assertEquals(AuthState.SignedOut,repository.state.value)
    }
    @Test fun lateLogoutCannotClearNewlySignedInOwner()=runBlocking {
        store.session=expiredSession().copy(expiresAtEpochSeconds=9999)
        repository.restore()
        server.enqueue(delayed("{}"));server.enqueue(MockResponse().setBody(sessionJson.replace("test-user","new-user")))
        val logout=async(start=CoroutineStart.UNDISPATCHED) {repository.signOut()}
        server.takeRequest()
        val newSession=repository.signIn("new@example.test","password").getOrThrow()
        logout.await()
        assertEquals(newSession,store.session);assertEquals(AuthState.SignedIn(newSession),repository.state.value)
    }
    @Test fun rejectedOldRestoreCannotClearNewActiveOwner()=runBlocking {
        store.session=expiredSession()
        server.enqueue(delayed("{}",401));server.enqueue(MockResponse().setBody(sessionJson.replace("test-user","new-user")))
        val restoring=async(start=CoroutineStart.UNDISPATCHED) {runCatching {repository.restore()}}
        server.takeRequest()
        val newSession=repository.signIn("new@example.test","password").getOrThrow()
        restoring.await()
        assertEquals(newSession,store.session);assertEquals(AuthState.SignedIn(newSession),repository.state.value)
    }
    @Test fun signedOutSessionCannotBeResurrectedFromRetainedSecureCache()=runBlocking {
        store.session=expiredSession().copy(expiresAtEpochSeconds=9999)
        repository.restore();server.enqueue(MockResponse().setBody("{}"));repository.signOut(clearLocalSession=false)
        repository.restore()
        assertEquals(AuthState.SignedOut,repository.state.value)
        assertNull(repository.refreshIfNeeded().getOrThrow())
    }
    @Test fun lateLoginCannotRestoreSessionAfterSignOut()=runBlocking {
        server.enqueue(delayed(sessionJson))
        val login=async(start=CoroutineStart.UNDISPATCHED) {repository.signIn("user@example.test","password")}
        server.takeRequest();repository.signOut();assertTrue(login.await().isFailure)
        assertNull(store.session);assertEquals(AuthState.SignedOut,repository.state.value)
    }

    @Test fun refreshCannotReplaceActiveOwnerWithForeignResponse()=runBlocking {
        val original=expiredSession();store.session=original
        server.enqueue(MockResponse().setBody(sessionJson.replace("test-user","foreign-user")))
        repository.restore()
        assertEquals(original,store.session);assertEquals(AuthState.SignedIn(original),repository.state.value)
    }
    @Test fun overlappingRefreshesUseOneRotatingTokenRequest()=runBlocking {
        store.session=expiredSession();server.enqueue(MockResponse().setResponseCode(503).setBody("{}"));repository.restore()
        server.takeRequest();server.enqueue(delayed(sessionJson))
        val first=async(start=CoroutineStart.UNDISPATCHED) {repository.refreshIfNeeded().getOrThrow()}
        server.takeRequest()
        val second=async(start=CoroutineStart.UNDISPATCHED) {repository.refreshIfNeeded().getOrThrow()}
        assertEquals(first.await(),second.await());assertEquals(2,server.requestCount)
        assertEquals(AuthState.SignedIn(store.session!!),repository.state.value)
    }

    private class MemorySessionStore : SecureSessionStore {
        var session: AuthSession? = null
        override fun read() = session
        override fun write(session: AuthSession) { this.session = session }
        override fun clear() { session = null }
    }

    private val sessionJson = """{"access_token":"test-access","refresh_token":"test-refresh","expires_in":3600,"user":{"id":"test-user","email":"user@example.test"}}"""
}
