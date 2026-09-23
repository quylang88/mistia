package vn.com.quyln.mistia.core.network

import java.util.concurrent.TimeUnit
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.tls.HandshakeCertificates
import okhttp3.tls.HeldCertificate
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import vn.com.quyln.mistia.core.model.CloudEntity
import vn.com.quyln.mistia.core.model.UserId

class CreditCardPostgrestMutationTest {
    private lateinit var server: MockWebServer
    private lateinit var store: SupabasePostgrestRemoteStore

    @Before
    fun setUp() {
        val certificate = HeldCertificate.Builder().addSubjectAlternativeName("localhost").build()
        val serverCertificates = HandshakeCertificates.Builder().heldCertificate(certificate).build()
        val clientCertificates = HandshakeCertificates.Builder()
            .addTrustedCertificate(certificate.certificate)
            .build()
        server = MockWebServer().apply {
            useHttps(serverCertificates.sslSocketFactory(), false)
            start()
        }
        store = SupabasePostgrestRemoteStore(
            config = SupabaseConfig(server.url("/").toString().removeSuffix("/"), "publishable-key"),
            client = OkHttpClient.Builder().sslSocketFactory(
                clientCertificates.sslSocketFactory(),
                clientCertificates.trustManager,
            ).build(),
            writableEntities = setOf(CloudEntity.CREDIT_CARD_PROFILE),
        )
    }

    @After
    fun tearDown() = server.shutdown()

    @Test
    fun `fetch is scoped by profile and owner`() = runTest {
        server.enqueue(MockResponse().setBody("[${profileJson(version = 4)}]"))

        val record = store.fetchRecord(
            CloudEntity.CREDIT_CARD_PROFILE,
            PROFILE_ID,
            TOKEN,
            UserId(OWNER),
        )

        assertEquals(4L, record?.syncVersion)
        val request = server.takeRequest(1, TimeUnit.SECONDS)
        assertNotNull(request)
        assertEquals("GET", request!!.method)
        assertEquals("eq.$PROFILE_ID", request.requestUrl?.queryParameter("id"))
        assertEquals("eq.$OWNER", request.requestUrl?.queryParameter("user_id"))
        assertEquals("1", request.requestUrl?.queryParameter("limit"))
    }

    @Test
    fun `create preserves linked wallet long limit and explicit nulls`() = runTest {
        server.enqueue(MockResponse().setBody("[${profileJson(version = 1)}]"))

        store.createRecord(
            CloudEntity.CREDIT_CARD_PROFILE,
            TOKEN,
            UserId(OWNER),
            profilePayload(version = 1),
        )

        val request = server.takeRequest(1, TimeUnit.SECONDS)!!
        assertEquals("POST", request.method)
        assertEquals("eq.$OWNER", request.requestUrl?.queryParameter("user_id"))
        val body = request.body.readUtf8()
        assertTrue(body.startsWith("["))
        assertTrue(body.contains("\"wallet_id\":\"$WALLET_ID\""))
        assertTrue(body.contains("\"credit_limit_minor\":9007199254740993"))
        assertTrue(body.contains("\"payment_source_wallet_id\":null"))
        assertTrue(body.contains("\"notes\":null"))
    }

    @Test
    fun `update uses owner id and expected version filters`() = runTest {
        server.enqueue(MockResponse().setBody("[${profileJson(version = 8)}]"))

        val updated = store.conditionalUpdate(
            CloudEntity.CREDIT_CARD_PROFILE,
            PROFILE_ID,
            TOKEN,
            UserId(OWNER),
            expectedVersion = 7,
            payload = profilePayload(version = 8),
        )

        assertEquals(8L, updated?.syncVersion)
        val request = server.takeRequest(1, TimeUnit.SECONDS)!!
        assertEquals("PATCH", request.method)
        assertEquals("eq.$PROFILE_ID", request.requestUrl?.queryParameter("id"))
        assertEquals("eq.$OWNER", request.requestUrl?.queryParameter("user_id"))
        assertEquals("eq.7", request.requestUrl?.queryParameter("sync_version"))
        assertFalse(request.body.readUtf8().startsWith("["))
    }

    @Test
    fun `disabled card domain rejects writes before network`() = runTest {
        val disabled = SupabasePostgrestRemoteStore(
            config = SupabaseConfig(server.url("/").toString().removeSuffix("/"), "publishable-key"),
            client = OkHttpClient(),
        )

        val failure = runCatching {
            disabled.createRecord(
                CloudEntity.CREDIT_CARD_PROFILE,
                TOKEN,
                UserId(OWNER),
                profilePayload(version = 1),
            )
        }.exceptionOrNull()

        assertTrue(failure is IllegalStateException)
        assertEquals(0, server.requestCount)
    }

    private fun profilePayload(version: Long): JsonObject = JsonObject(
        mapOf(
            "user_id" to JsonPrimitive(OWNER),
            "id" to JsonPrimitive(PROFILE_ID),
            "issuer_name" to JsonPrimitive("Mistia Bank"),
            "network_raw_value" to JsonPrimitive("visa"),
            "last4" to JsonPrimitive("1234"),
            "credit_limit_minor" to JsonPrimitive(9_007_199_254_740_993L),
            "statement_closing_day" to JsonPrimitive(10),
            "payment_due_day" to JsonPrimitive(26),
            "notes" to JsonNull,
            "wallet_id" to JsonPrimitive(WALLET_ID),
            "payment_source_wallet_id" to JsonNull,
            "auto_pay_enabled" to JsonPrimitive(true),
            "sync_version" to JsonPrimitive(version),
            "updated_at" to JsonPrimitive(UPDATED_AT),
        )
    )

    private fun profileJson(version: Long): String = profilePayload(version).toString()

    private companion object {
        const val OWNER = "11111111-1111-1111-1111-111111111111"
        const val PROFILE_ID = "22222222-2222-2222-2222-222222222222"
        const val WALLET_ID = "33333333-3333-3333-3333-333333333333"
        const val TOKEN = "access-token"
        const val UPDATED_AT = "2026-09-23T12:00:00.000Z"
    }
}
