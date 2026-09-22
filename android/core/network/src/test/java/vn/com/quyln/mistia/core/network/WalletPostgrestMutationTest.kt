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

class WalletPostgrestMutationTest {
    private lateinit var server: MockWebServer
    private lateinit var store: SupabasePostgrestRemoteStore

    @Before
    fun setUp() {
        val certificate = HeldCertificate.Builder().addSubjectAlternativeName("localhost").build()
        val serverCertificates = HandshakeCertificates.Builder()
            .heldCertificate(certificate)
            .build()
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
            writableEntities = setOf(CloudEntity.LEDGER_WALLET),
        )
    }

    @After
    fun tearDown() {
        server.shutdown()
    }

    @Test
    fun `fetch is scoped by record and owner`() = runTest {
        server.enqueue(MockResponse().setBody("[${walletJson(version = 4)}]"))

        val record = store.fetchRecord(
            CloudEntity.LEDGER_WALLET,
            WALLET_ID,
            TOKEN,
            UserId(OWNER),
        )

        assertEquals(4L, record?.syncVersion)
        val request = server.takeRequest(1, TimeUnit.SECONDS)
        assertNotNull(request)
        assertEquals("GET", request!!.method)
        assertEquals("eq.$WALLET_ID", request.requestUrl?.queryParameter("id"))
        assertEquals("eq.$OWNER", request.requestUrl?.queryParameter("user_id"))
        assertEquals("1", request.requestUrl?.queryParameter("limit"))
        assertEquals("Bearer $TOKEN", request.headers["Authorization"])
    }

    @Test
    fun `create sends array payload with explicit null and owner scope`() = runTest {
        server.enqueue(MockResponse().setBody("[${walletJson(version = 1)}]"))
        val payload = walletPayload(version = 1)

        store.createRecord(CloudEntity.LEDGER_WALLET, TOKEN, UserId(OWNER), payload)

        val request = server.takeRequest(1, TimeUnit.SECONDS)!!
        assertEquals("POST", request.method)
        assertEquals("eq.$OWNER", request.requestUrl?.queryParameter("user_id"))
        assertEquals("return=representation", request.headers["Prefer"])
        val body = request.body.readUtf8()
        assertTrue(body.startsWith("["))
        assertTrue(body.contains("\"institution_display_name\":null"))
        assertTrue(body.contains("\"opening_balance_minor\":9007199254740993"))
    }

    @Test
    fun `update uses owner id and expected version filters`() = runTest {
        server.enqueue(MockResponse().setBody("[${walletJson(version = 8)}]"))

        val updated = store.conditionalUpdate(
            CloudEntity.LEDGER_WALLET,
            WALLET_ID,
            TOKEN,
            UserId(OWNER),
            expectedVersion = 7,
            payload = walletPayload(version = 8),
        )

        assertEquals(8L, updated?.syncVersion)
        val request = server.takeRequest(1, TimeUnit.SECONDS)!!
        assertEquals("PATCH", request.method)
        assertEquals("eq.$WALLET_ID", request.requestUrl?.queryParameter("id"))
        assertEquals("eq.$OWNER", request.requestUrl?.queryParameter("user_id"))
        assertEquals("eq.7", request.requestUrl?.queryParameter("sync_version"))
        assertFalse(request.body.readUtf8().startsWith("["))
    }

    @Test
    fun `disabled wallet domain rejects writes before network`() = runTest {
        val disabled = SupabasePostgrestRemoteStore(
            config = SupabaseConfig(server.url("/").toString().removeSuffix("/"), "publishable-key"),
            client = OkHttpClient(),
        )

        val failure = runCatching {
            disabled.createRecord(
                CloudEntity.LEDGER_WALLET,
                TOKEN,
                UserId(OWNER),
                walletPayload(version = 1),
            )
        }.exceptionOrNull()

        assertTrue(failure is IllegalStateException)
        assertEquals(0, server.requestCount)
    }

    private fun walletPayload(version: Long): JsonObject = JsonObject(
        mapOf(
            "user_id" to JsonPrimitive(OWNER),
            "id" to JsonPrimitive(WALLET_ID),
            "name" to JsonPrimitive("Cash"),
            "opening_balance_minor" to JsonPrimitive(9_007_199_254_740_993L),
            "institution_display_name" to JsonNull,
            "sync_version" to JsonPrimitive(version),
            "updated_at" to JsonPrimitive(UPDATED_AT),
        )
    )

    private fun walletJson(version: Long): String = walletPayload(version).toString()

    private companion object {
        const val OWNER = "11111111-1111-1111-1111-111111111111"
        const val WALLET_ID = "22222222-2222-2222-2222-222222222222"
        const val TOKEN = "access-token"
        const val UPDATED_AT = "2026-09-22T10:00:00.000Z"
    }
}
