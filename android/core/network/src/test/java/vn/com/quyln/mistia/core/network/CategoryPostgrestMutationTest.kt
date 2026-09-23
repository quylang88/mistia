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

class CategoryPostgrestMutationTest {
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
            writableEntities = setOf(CloudEntity.TRANSACTION_CATEGORY),
        )
    }

    @After
    fun tearDown() {
        server.shutdown()
    }

    @Test
    fun `fetch is scoped by category id and owner`() = runTest {
        server.enqueue(MockResponse().setBody("[${categoryJson(version = 4)}]"))

        val record = store.fetchRecord(
            CloudEntity.TRANSACTION_CATEGORY,
            CATEGORY_ID,
            TOKEN,
            UserId(OWNER),
        )

        assertEquals(4L, record?.syncVersion)
        val request = server.takeRequest(1, TimeUnit.SECONDS)
        assertNotNull(request)
        assertEquals("GET", request!!.method)
        assertEquals("eq.$CATEGORY_ID", request.requestUrl?.queryParameter("id"))
        assertEquals("eq.$OWNER", request.requestUrl?.queryParameter("user_id"))
        assertEquals("1", request.requestUrl?.queryParameter("limit"))
    }

    @Test
    fun `create keeps explicit nullable category fields and long sync version`() = runTest {
        server.enqueue(MockResponse().setBody("[${categoryJson(version = LONG_VERSION)}]"))

        store.createRecord(
            CloudEntity.TRANSACTION_CATEGORY,
            TOKEN,
            UserId(OWNER),
            categoryPayload(version = LONG_VERSION),
        )

        val request = server.takeRequest(1, TimeUnit.SECONDS)!!
        assertEquals("POST", request.method)
        assertEquals("eq.$OWNER", request.requestUrl?.queryParameter("user_id"))
        assertEquals("return=representation", request.headers["Prefer"])
        val body = request.body.readUtf8()
        assertTrue(body.startsWith("["))
        assertTrue(body.contains("\"name_english\":null"))
        assertTrue(body.contains("\"name_japanese\":null"))
        assertTrue(body.contains("\"parent_category_id\":null"))
        assertTrue(body.contains("\"sync_version\":$LONG_VERSION"))
    }

    @Test
    fun `conditional category update includes owner record and version filters`() = runTest {
        server.enqueue(MockResponse().setBody("[${categoryJson(version = 8)}]"))

        val updated = store.conditionalUpdate(
            CloudEntity.TRANSACTION_CATEGORY,
            CATEGORY_ID,
            TOKEN,
            UserId(OWNER),
            expectedVersion = 7,
            payload = categoryPayload(version = 8),
        )

        assertEquals(8L, updated?.syncVersion)
        val request = server.takeRequest(1, TimeUnit.SECONDS)!!
        assertEquals("PATCH", request.method)
        assertEquals("eq.$CATEGORY_ID", request.requestUrl?.queryParameter("id"))
        assertEquals("eq.$OWNER", request.requestUrl?.queryParameter("user_id"))
        assertEquals("eq.7", request.requestUrl?.queryParameter("sync_version"))
        assertFalse(request.body.readUtf8().startsWith("["))
    }

    @Test
    fun `category allowlist remains independent from wallet writes`() = runTest {
        val failure = runCatching {
            store.createRecord(
                CloudEntity.LEDGER_WALLET,
                TOKEN,
                UserId(OWNER),
                JsonObject(
                    mapOf(
                        "id" to JsonPrimitive(CATEGORY_ID),
                        "user_id" to JsonPrimitive(OWNER),
                    )
                ),
            )
        }.exceptionOrNull()

        assertTrue(failure is IllegalStateException)
        assertEquals(0, server.requestCount)
    }

    @Test
    fun `disabled category domain rejects writes before network`() = runTest {
        val disabled = SupabasePostgrestRemoteStore(
            SupabaseConfig(server.url("/").toString().removeSuffix("/"), "publishable-key"),
            OkHttpClient(),
        )

        val failure = runCatching {
            disabled.createRecord(
                CloudEntity.TRANSACTION_CATEGORY,
                TOKEN,
                UserId(OWNER),
                categoryPayload(version = 1),
            )
        }.exceptionOrNull()

        assertTrue(failure is IllegalStateException)
        assertEquals(0, server.requestCount)
    }

    private fun categoryPayload(version: Long): JsonObject = JsonObject(
        mapOf(
            "user_id" to JsonPrimitive(OWNER),
            "id" to JsonPrimitive(CATEGORY_ID),
            "name" to JsonPrimitive("Ăn uống"),
            "name_english" to JsonNull,
            "name_japanese" to JsonNull,
            "kind_raw_value" to JsonPrimitive("expense"),
            "parent_category_id" to JsonNull,
            "hierarchy_role_raw_value" to JsonPrimitive("parent"),
            "system_key" to JsonNull,
            "archived_at" to JsonNull,
            "deleted_at" to JsonNull,
            "sync_version" to JsonPrimitive(version),
            "updated_at" to JsonPrimitive(UPDATED_AT),
        )
    )

    private fun categoryJson(version: Long): String = categoryPayload(version).toString()

    private companion object {
        const val OWNER = "11111111-1111-1111-1111-111111111111"
        const val CATEGORY_ID = "22222222-2222-2222-2222-222222222222"
        const val TOKEN = "access-token"
        const val UPDATED_AT = "2026-09-23T10:00:00.000Z"
        const val LONG_VERSION = 9_007_199_254_740_993L
    }
}
