package vn.com.quyln.mistia.core.network

import java.util.concurrent.TimeUnit
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.*
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.tls.HandshakeCertificates
import okhttp3.tls.HeldCertificate
import org.junit.*
import org.junit.Assert.*
import vn.com.quyln.mistia.core.model.*

/** HTTPS localhost only; no production credentials or requests. */
class InstallmentPostgrestMutationTest {
    private lateinit var server: MockWebServer
    private lateinit var store: SupabasePostgrestRemoteStore
    private val owner = UserId("11111111-1111-1111-1111-111111111111")
    private val id = "22222222-2222-2222-2222-222222222222"
    private val device = "33333333-3333-3333-3333-333333333333"
    private val now = "2026-10-15T00:00:00Z"
    private val version = 9007199254740993L
    @Before fun setup() {
        val cert = HeldCertificate.Builder().addSubjectAlternativeName("localhost").build()
        val serverCerts = HandshakeCertificates.Builder().heldCertificate(cert).build()
        val trusted = HandshakeCertificates.Builder().addTrustedCertificate(cert.certificate).build()
        server = MockWebServer().apply { useHttps(serverCerts.sslSocketFactory(), false); start() }
        store = SupabasePostgrestRemoteStore(SupabaseConfig(server.url("/").toString().removeSuffix("/"), "fixture-key"),
            OkHttpClient.Builder().sslSocketFactory(trusted.sslSocketFactory(), trusted.trustManager).build(),
            writableEntities = setOf(CloudEntity.INSTALLMENT_PLAN))
    }
    @After fun close() { server.shutdown() }
    private fun payload(v: Long = version) = InstallmentPlanRecord(id, owner.value, "Loan", "mistia.plan.loan", version, 31, null, 2, null,
        "VND", false, now, now, null, v, null).toPayload()
    private fun enqueue(p: JsonObject = payload()) { server.enqueue(MockResponse().setBody("[$p]")) }
    private fun request() = server.takeRequest(1, TimeUnit.SECONDS)!!
    @Test fun `fetch is scoped to installment table ID and owner with exact Long response`() = runTest {
        enqueue(); val result = store.fetchRecord(CloudEntity.INSTALLMENT_PLAN, id, "fixture", owner)!!
        assertEquals(version, result.syncVersion)
        val r = request(); assertEquals("GET", r.method)
        assertEquals("/rest/v1/installment_plans", r.requestUrl!!.encodedPath)
        assertEquals("eq.$id", r.requestUrl!!.queryParameter("id")); assertEquals("eq.${owner.value}", r.requestUrl!!.queryParameter("user_id"))
        assertEquals("1", r.requestUrl!!.queryParameter("limit"))
    }
    @Test fun `create keeps nullable cycles wallet actor and exact amount and version`() = runTest {
        enqueue(); store.createRecord(CloudEntity.INSTALLMENT_PLAN, "fixture", owner, payload())
        val r = request(); assertEquals("POST", r.method)
        assertEquals("eq.${owner.value}", r.requestUrl!!.queryParameter("user_id")); assertEquals("return=representation", r.headers["Prefer"])
        val body = Json.parseToJsonElement(r.body.readUtf8()).jsonArray.single().jsonObject
        assertEquals(JsonPrimitive(version), body["amount_per_cycle_minor"]); assertEquals(JsonPrimitive(version), body["sync_version"])
        listOf("total_cycles", "payment_wallet_id", "deleted_at", "last_modified_by_device_id").forEach { assertSame(JsonNull, body[it]) }
    }
    @Test fun `conditional update uses owner record and Long expected version filters`() = runTest {
        enqueue(); val result = store.conditionalUpdate(CloudEntity.INSTALLMENT_PLAN, id, "fixture", owner, version - 1, payload())!!
        assertEquals(version, result.syncVersion)
        val r = request(); assertEquals("PATCH", r.method)
        assertEquals("eq.$id", r.requestUrl!!.queryParameter("id")); assertEquals("eq.${owner.value}", r.requestUrl!!.queryParameter("user_id"))
        assertEquals("eq.${version - 1}", r.requestUrl!!.queryParameter("sync_version"))
        assertEquals(payload(), Json.parseToJsonElement(r.body.readUtf8()).jsonObject)
    }
    @Test fun `sparse tombstone patch leaves business fields absent`() = runTest {
        enqueue(JsonObject(payload() + ("deleted_at" to JsonPrimitive(now))))
        val patch = buildJsonObject { put("id", id); put("user_id", owner.value); put("updated_at", now); put("deleted_at", now)
            put("sync_version", version); put("last_modified_by_device_id", device) }
        assertEquals(now, store.conditionalUpdate(CloudEntity.INSTALLMENT_PLAN, id, "fixture", owner, version - 1, patch)!!.deletedAt)
        assertEquals(patch, Json.parseToJsonElement(request().body.readUtf8()).jsonObject)
        assertFalse(patch.containsKey("name")); assertFalse(patch.containsKey("amount_per_cycle_minor")); assertFalse(patch.containsKey("payment_wallet_id"))
    }
    @Test fun `conditional race returns no row rather than unconditional update`() = runTest {
        server.enqueue(MockResponse().setBody("[]"))
        assertNull(store.conditionalUpdate(CloudEntity.INSTALLMENT_PLAN, id, "fixture", owner, version, payload(version + 1)))
        assertEquals("PATCH", request().method); assertEquals(1, server.requestCount)
    }
    @Test fun `default disabled gate rejects installment create and patch before network`() = runTest {
        val disabled = SupabasePostgrestRemoteStore(SupabaseConfig(server.url("/").toString().removeSuffix("/"), "fixture-key"), OkHttpClient())
        assertTrue(runCatching { disabled.createRecord(CloudEntity.INSTALLMENT_PLAN, "fixture", owner, payload()) }.exceptionOrNull() is IllegalStateException)
        assertTrue(runCatching { disabled.conditionalUpdate(CloudEntity.INSTALLMENT_PLAN, id, "fixture", owner, version, payload()) }.exceptionOrNull() is IllegalStateException)
        assertEquals(0, server.requestCount)
    }
    @Test fun `wallet only allowlist cannot enable installment writes`() = runTest {
        val wallets = SupabasePostgrestRemoteStore(SupabaseConfig(server.url("/").toString().removeSuffix("/"), "fixture-key"), OkHttpClient(),
            writableEntities = setOf(CloudEntity.LEDGER_WALLET))
        assertTrue(runCatching { wallets.createRecord(CloudEntity.INSTALLMENT_PLAN, "fixture", owner, payload()) }.exceptionOrNull() is IllegalStateException)
        assertEquals(0, server.requestCount)
    }
    @Test fun `installment plan allowlist cannot enable wallet ledger or due writes`() = runTest {
        for (entity in listOf(CloudEntity.LEDGER_WALLET, CloudEntity.LEDGER_TRANSACTION, CloudEntity.DUE_OCCURRENCE_RECORD)) {
            assertTrue(runCatching { store.createRecord(entity, "fixture", owner, payload()) }.exceptionOrNull() is IllegalStateException)
        }
        assertEquals(0, server.requestCount)
    }
    @Test fun `foreign payload owner and wrong payload ID fail before network`() = runTest {
        for (p in listOf(JsonObject(payload() + ("user_id" to JsonPrimitive(device))), JsonObject(payload() + ("id" to JsonPrimitive(device))))) {
            assertTrue(runCatching { store.conditionalUpdate(CloudEntity.INSTALLMENT_PLAN, id, "fixture", owner, version, p) }.exceptionOrNull() is IllegalArgumentException)
        }
        assertEquals(0, server.requestCount)
    }
    @Test fun `foreign response cannot become owned despite filtered fetch`() = runTest {
        enqueue(JsonObject(payload() + ("user_id" to JsonPrimitive(device))))
        assertTrue(runCatching { store.fetchRecord(CloudEntity.INSTALLMENT_PLAN, id, "fixture", owner) }.exceptionOrNull() is IllegalArgumentException)
        assertEquals(1, server.requestCount)
    }
}
