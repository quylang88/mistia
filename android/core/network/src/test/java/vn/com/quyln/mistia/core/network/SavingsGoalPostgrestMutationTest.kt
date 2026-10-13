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

class SavingsGoalPostgrestMutationTest {
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
            SupabaseConfig(server.url("/").toString().removeSuffix("/"), "publishable-key"),
            OkHttpClient.Builder().sslSocketFactory(
                clientCertificates.sslSocketFactory(),
                clientCertificates.trustManager,
            ).build(),
            writableEntities = setOf(CloudEntity.SAVINGS_GOAL),
        )
    }

    @After
    fun tearDown() {
        server.shutdown()
    }

    @Test
    fun `fetch is scoped by goal id and owner`() = runTest {
        server.enqueue(MockResponse().setBody("[${goalJson(version = 4)}]"))

        val record = store.fetchRecord(
            CloudEntity.SAVINGS_GOAL,
            GOAL_ID,
            TOKEN,
            UserId(OWNER),
        )

        assertEquals(4L, record?.syncVersion)
        val request = server.takeRequest(1, TimeUnit.SECONDS)
        assertNotNull(request)
        assertEquals("GET", request!!.method)
        assertEquals("eq.$GOAL_ID", request.requestUrl?.queryParameter("id"))
        assertEquals("eq.$OWNER", request.requestUrl?.queryParameter("user_id"))
        assertEquals("1", request.requestUrl?.queryParameter("limit"))
    }

    @Test
    fun `create keeps explicit nullable goal fields and long sync version`() = runTest {
        server.enqueue(MockResponse().setBody("[${goalJson(version = LONG_VERSION)}]"))

        store.createRecord(
            CloudEntity.SAVINGS_GOAL,
            TOKEN,
            UserId(OWNER),
            goalPayload(version = LONG_VERSION),
        )

        val request = server.takeRequest(1, TimeUnit.SECONDS)!!
        assertEquals("POST", request.method)
        assertEquals("eq.$OWNER", request.requestUrl?.queryParameter("user_id"))
        assertEquals("return=representation", request.headers["Prefer"])
        val body = request.body.readUtf8()
        assertTrue(body.startsWith("["))
        assertTrue(body.contains("\"linked_wallet_id\":null"))
        assertTrue(body.contains("\"last_modified_by_device_id\":null"))
        assertTrue(body.contains("\"deleted_at\":null"))
        assertTrue(body.contains("\"sync_version\":$LONG_VERSION"))
    }

    @Test
    fun `conditional goal update includes owner record and version filters`() = runTest {
        server.enqueue(MockResponse().setBody("[${goalJson(version = 8)}]"))

        val updated = store.conditionalUpdate(
            CloudEntity.SAVINGS_GOAL,
            GOAL_ID,
            TOKEN,
            UserId(OWNER),
            expectedVersion = 7,
            payload = goalPayload(version = 8),
        )

        assertEquals(8L, updated?.syncVersion)
        val request = server.takeRequest(1, TimeUnit.SECONDS)!!
        assertEquals("PATCH", request.method)
        assertEquals("eq.$GOAL_ID", request.requestUrl?.queryParameter("id"))
        assertEquals("eq.$OWNER", request.requestUrl?.queryParameter("user_id"))
        assertEquals("eq.7", request.requestUrl?.queryParameter("sync_version"))
        assertFalse(request.body.readUtf8().startsWith("["))
    }

    @Test
    fun `goal allowlist remains independent from wallet writes`() = runTest {
        val failure = runCatching {
            store.createRecord(
                CloudEntity.LEDGER_WALLET,
                TOKEN,
                UserId(OWNER),
                JsonObject(
                    mapOf(
                        "id" to JsonPrimitive(GOAL_ID),
                        "user_id" to JsonPrimitive(OWNER),
                    )
                ),
            )
        }.exceptionOrNull()

        assertTrue(failure is IllegalStateException)
        assertEquals(0, server.requestCount)
    }

    @Test
    fun `disabled goal domain rejects writes before network`() = runTest {
        val disabled = SupabasePostgrestRemoteStore(
            SupabaseConfig(server.url("/").toString().removeSuffix("/"), "publishable-key"),
            OkHttpClient(),
        )

        val failure = runCatching {
            disabled.createRecord(
                CloudEntity.SAVINGS_GOAL,
                TOKEN,
                UserId(OWNER),
                goalPayload(version = 1),
            )
        }.exceptionOrNull()

        assertTrue(failure is IllegalStateException)
        assertEquals(0, server.requestCount)
    }

    @Test fun `conditional tombstone patch is sparse and owner scoped`() = runTest {
        val deleted = JsonObject(goalPayload(8) + ("deleted_at" to JsonPrimitive(UPDATED_AT)))
        server.enqueue(MockResponse().setBody("[$deleted]"))
        val payload = JsonObject(mapOf("id" to JsonPrimitive(GOAL_ID), "user_id" to JsonPrimitive(OWNER),
            "deleted_at" to JsonPrimitive(UPDATED_AT), "updated_at" to JsonPrimitive(UPDATED_AT),
            "sync_version" to JsonPrimitive(8), "last_modified_by_device_id" to JsonPrimitive(DEVICE)))
        val result = store.conditionalUpdate(CloudEntity.SAVINGS_GOAL, GOAL_ID, TOKEN, UserId(OWNER), 7, payload)
        assertEquals(UPDATED_AT, result!!.deletedAt)
        val request = server.takeRequest(1, TimeUnit.SECONDS)!!
        assertEquals("PATCH", request.method)
        assertEquals("eq.$OWNER", request.requestUrl!!.queryParameter("user_id"))
        assertEquals("eq.$GOAL_ID", request.requestUrl!!.queryParameter("id"))
        assertEquals("eq.7", request.requestUrl!!.queryParameter("sync_version"))
        val body = request.body.readUtf8()
        assertTrue(body.contains("\"deleted_at\":\"$UPDATED_AT\""))
        assertFalse(body.contains("target_minor"))
        assertFalse(body.contains("linked_wallet_id"))
    }

    @Test fun `foreign goal payload is rejected before network`() = runTest {
        val payload = JsonObject(goalPayload(1) + ("user_id" to JsonPrimitive(DEVICE)))
        val failure = runCatching { store.createRecord(CloudEntity.SAVINGS_GOAL, TOKEN, UserId(OWNER), payload) }.exceptionOrNull()
        assertTrue(failure is IllegalArgumentException)
        assertEquals(0, server.requestCount)
    }

    @Test fun `wallet allowlist does not enable goal patch`() = runTest {
        val walletOnly = SupabasePostgrestRemoteStore(
            SupabaseConfig(server.url("/").toString().removeSuffix("/"), "publishable-key"),
            OkHttpClient(), writableEntities = setOf(CloudEntity.LEDGER_WALLET))
        val failure = runCatching {
            walletOnly.conditionalUpdate(CloudEntity.SAVINGS_GOAL, GOAL_ID, TOKEN, UserId(OWNER), 1, goalPayload(2))
        }.exceptionOrNull()
        assertTrue(failure is IllegalStateException)
        assertEquals(0, server.requestCount)
    }

    @Test fun `foreign owner response is rejected despite owner filtered request`() = runTest {
        val foreign = JsonObject(goalPayload(1) + ("user_id" to JsonPrimitive(DEVICE)))
        server.enqueue(MockResponse().setBody("[$foreign]"))
        val failure = runCatching {
            store.fetchRecord(CloudEntity.SAVINGS_GOAL, GOAL_ID, TOKEN, UserId(OWNER))
        }.exceptionOrNull()
        assertTrue(failure is IllegalArgumentException)
        assertEquals(1, server.requestCount)
    }

    private fun goalPayload(version: Long): JsonObject = vn.com.quyln.mistia.core.model.SavingsGoalRecord(
        GOAL_ID,OWNER,"Travel","mistia.goal.savings",LONG_VERSION,100,
        "2027-01-01T00:00:00Z",null,"JPY",0,false,UPDATED_AT,UPDATED_AT,null,version,null,
    ).toPayload()

    private fun goalJson(version: Long): String = goalPayload(version).toString()

    private companion object {
        const val OWNER = "11111111-1111-1111-1111-111111111111"
        const val GOAL_ID = "22222222-2222-2222-2222-222222222222"
        const val DEVICE = "44444444-4444-4444-4444-444444444444"
        const val TOKEN = "access-token"
        const val UPDATED_AT = "2026-09-23T10:00:00.000Z"
        const val LONG_VERSION = 9_007_199_254_740_993L
    }
}
