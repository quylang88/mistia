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

class InstallmentDeletionPostgrestTest {
    private lateinit var server: MockWebServer
    private lateinit var client: OkHttpClient
    private val owner = UserId("11111111-1111-1111-1111-111111111111")
    private val id = "22222222-2222-2222-2222-222222222222"
    private val device = "33333333-3333-3333-3333-333333333333"
    private val other = "99999999-9999-9999-9999-999999999999"
    private val time = "2026-10-15T00:00:00Z"
    private val version = 9007199254740993L
    @Before fun setup() {
        val certificate = HeldCertificate.Builder().addSubjectAlternativeName("localhost").build()
        val certificates = HandshakeCertificates.Builder().heldCertificate(certificate).build()
        val trust = HandshakeCertificates.Builder().addTrustedCertificate(certificate.certificate).build()
        server = MockWebServer().apply { useHttps(certificates.sslSocketFactory(), false); start() }
        client = OkHttpClient.Builder().sslSocketFactory(trust.sslSocketFactory(), trust.trustManager).callTimeout(3, TimeUnit.SECONDS).build()
    }
    @After fun close() { server.shutdown() }
    private fun store(enabled: Boolean = true, entities: Set<CloudEntity> = setOf(CloudEntity.DUE_OCCURRENCE_RECORD),
        sources: Set<DueSourceKind> = emptySet()) = SupabasePostgrestRemoteStore(
            SupabaseConfig(server.url("/").toString().removeSuffix("/"), "fixture"), client, writableEntities = entities,
            writableDueSources = sources, allowInstallmentOccurrenceDeletes = enabled)
    private fun patch() = buildJsonObject {
        put("id", id); put("user_id", owner.value); put("source_kind_raw_value", "installment")
        put("updated_at", time); put("deleted_at", time); put("sync_version", version + 1); put("last_modified_by_device_id", device)
    }
    private fun row() = DueOccurrenceRecord(id, owner.value, "installment", device, "2026-10", time, 9007199254740993,
        "paid", time, other, time, time, time, version + 1, device).toPayload()
    private suspend fun update(store: SupabasePostgrestRemoteStore, payload: JsonObject = patch(), base: Long = version) =
        store.conditionalUpdate(CloudEntity.DUE_OCCURRENCE_RECORD, id, "fixture", owner, base, payload)
    @Test fun `gated installment delete is sparse exact Long owner version and source filtered`() = runTest {
        server.enqueue(MockResponse().setBody("[${row()}]"))
        assertEquals(version + 1, update(store())!!.syncVersion)
        val request = server.takeRequest(1, TimeUnit.SECONDS)!!
        assertEquals("PATCH", request.method); assertEquals("/rest/v1/due_occurrence_records", request.requestUrl!!.encodedPath)
        assertEquals("eq.${owner.value}", request.requestUrl!!.queryParameter("user_id")); assertEquals("eq.$id", request.requestUrl!!.queryParameter("id"))
        assertEquals("eq.$version", request.requestUrl!!.queryParameter("sync_version")); assertEquals("eq.installment", request.requestUrl!!.queryParameter("source_kind_raw_value"))
        assertEquals(patch(), Json.parseToJsonElement(request.body.readUtf8()).jsonObject)
    }
    @Test fun `source capability remains disabled by default and cannot bypass entity gate`() = runTest {
        for (s in listOf(store(false), store(entities = setOf(CloudEntity.INSTALLMENT_PLAN)))) assertTrue(runCatching { update(s) }.isFailure)
        assertEquals(0, server.requestCount)
    }
    @Test fun `delete capability alone cannot enable bill card or ledger writes`() = runTest {
        for (kind in listOf("recurringBill", "creditCard")) assertTrue(runCatching { update(store(), JsonObject(patch() + ("source_kind_raw_value" to JsonPrimitive(kind)))) }.isFailure)
        assertTrue(runCatching { store().conditionalUpdate(CloudEntity.LEDGER_TRANSACTION, id, "fixture", owner, version, patch()) }.isFailure)
        assertEquals(0, server.requestCount)
    }
    @Test fun `installment source list cannot bypass create and full upsert prohibition`() = runTest {
        server.enqueue(MockResponse().setBody("[${row()}]")); server.enqueue(MockResponse().setBody("[${row()}]"))
        val s = store(sources = setOf(DueSourceKind.INSTALLMENT))
        assertTrue(runCatching { s.createRecord(CloudEntity.DUE_OCCURRENCE_RECORD, "fixture", owner, row()) }.isFailure)
        assertTrue(runCatching { update(s, row()) }.isFailure); assertEquals(0, server.requestCount)
    }
    @Test fun `extra financial fields nullable delete invalid actor and nonincrementing versions are rejected before HTTP`() = runTest {
        val malformed = listOf(JsonObject(patch() + ("amount_minor_snapshot" to JsonPrimitive(1000))),
            JsonObject(patch() + ("deleted_at" to JsonNull)), JsonObject(patch() + ("last_modified_by_device_id" to JsonPrimitive("device"))),
            JsonObject(patch() + ("sync_version" to JsonPrimitive((version + 1).toString()))),
            JsonObject(patch() + ("sync_version" to JsonPrimitive(version))))
        repeat(malformed.size) { server.enqueue(MockResponse().setBody("[]")) }
        for (payload in malformed) assertTrue(runCatching { update(store(), payload) }.isFailure)
        assertEquals(0, server.requestCount)
    }
    @Test fun `foreign owner payload is rejected before HTTP`() = runTest {
        assertTrue(runCatching { update(store(), JsonObject(patch() + ("user_id" to JsonPrimitive(other)))) }.isFailure); assertEquals(0, server.requestCount)
    }
    @Test fun `foreign owner and aliased response ID cannot be acknowledged`() = runTest {
        for (field in listOf("user_id", "id")) {
            server.enqueue(MockResponse().setBody("[${JsonObject(row() + (field to JsonPrimitive(other)))}]"))
            assertTrue(runCatching { update(store()) }.isFailure)
        }
        assertEquals(2, server.requestCount)
    }
    @Test fun `conditional race returns null without create fallback`() = runTest {
        server.enqueue(MockResponse().setBody("[]")); assertNull(update(store())); assertEquals(1, server.requestCount)
    }
}
