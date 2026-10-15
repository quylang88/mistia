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

class InstallmentSkipPostgrestTest {
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
    private fun store(enabled: Boolean = true, entities: Set<CloudEntity> = setOf(CloudEntity.DUE_OCCURRENCE_RECORD), delete: Boolean = false) = SupabasePostgrestRemoteStore(
        SupabaseConfig(server.url("/").toString().removeSuffix("/"), "fixture"), client, writableEntities = entities,
        writableDueSources = setOf(DueSourceKind.INSTALLMENT), allowInstallmentOccurrenceDeletes = delete, allowInstallmentOccurrenceSkips = enabled)
    private fun row() = DueOccurrenceRecord(id, owner.value, "installment", device, "2026-10", time, null, "skipped", null, null, time, time, null, version + 1, device).toPayload()
    private fun undo() = JsonObject(row().filterKeys { it in setOf("id", "user_id", "source_kind_raw_value", "status_raw_value", "amount_minor_snapshot", "paid_at", "linked_transaction_id", "updated_at", "sync_version", "last_modified_by_device_id") } + ("deleted_at" to JsonPrimitive(time)))
    private suspend fun update(s: SupabasePostgrestRemoteStore, payload: JsonObject = row()) = s.conditionalUpdate(CloudEntity.DUE_OCCURRENCE_RECORD, id, "fixture", owner, version, payload)
    @Test fun `skip create requires separate capability and retains exact Long and explicit nulls`() = runTest {
        server.enqueue(MockResponse().setBody("[${row()}]"))
        assertEquals(version + 1, store().createRecord(CloudEntity.DUE_OCCURRENCE_RECORD, "fixture", owner, row()).syncVersion)
        val request = server.takeRequest(1, TimeUnit.SECONDS)!!
        assertEquals("POST", request.method); assertEquals(row(), Json.parseToJsonElement(request.body.readUtf8()).jsonArray.single().jsonObject)
    }
    @Test fun `skip conditional update is source owner exact-version and nonfinancial filtered`() = runTest {
        server.enqueue(MockResponse().setBody("[${row()}]")); assertNotNull(update(store()))
        val request = server.takeRequest(1, TimeUnit.SECONDS)!!; val url = request.requestUrl!!
        assertEquals("eq.$version", url.queryParameter("sync_version")); assertEquals("eq.${owner.value}", url.queryParameter("user_id"))
        assertEquals("eq.installment", url.queryParameter("source_kind_raw_value")); assertEquals("in.(pending,skipped)", url.queryParameter("status_raw_value"))
        assertEquals("is.null", url.queryParameter("paid_at")); assertEquals("is.null", url.queryParameter("linked_transaction_id"))
    }
    @Test fun `undo skip uses sparse explicit nonfinancial patch and only targets skipped rows`() = runTest {
        server.enqueue(MockResponse().setBody("[${JsonObject(row() + ("deleted_at" to JsonPrimitive(time)))}]")); assertNotNull(update(store(), undo()))
        val request = server.takeRequest(1, TimeUnit.SECONDS)!!
        assertEquals("eq.skipped", request.requestUrl!!.queryParameter("status_raw_value")); assertEquals("is.null", request.requestUrl!!.queryParameter("amount_minor_snapshot"))
        assertEquals(undo(), Json.parseToJsonElement(request.body.readUtf8()).jsonObject)
    }
    @Test fun `default disabled source list and entity gate cannot bypass skip capability`() = runTest {
        for (s in listOf(store(false), store(entities = emptySet()), store(false, delete = true)))
            assertTrue(runCatching { s.createRecord(CloudEntity.DUE_OCCURRENCE_RECORD, "fixture", owner, row()) }.isFailure)
        assertEquals(0, server.requestCount)
    }
    @Test fun `skip capability cannot create paid pending linked or monetary records`() = runTest {
        val bad = listOf(JsonObject(row() + ("status_raw_value" to JsonPrimitive("paid"))), JsonObject(row() + ("status_raw_value" to JsonPrimitive("pending"))),
            JsonObject(row() + ("linked_transaction_id" to JsonPrimitive(other))), JsonObject(row() + ("paid_at" to JsonPrimitive(time))),
            JsonObject(row() + ("amount_minor_snapshot" to JsonPrimitive(1000))), JsonObject(row() + ("source_kind_raw_value" to JsonPrimitive("creditCard"))))
        for (payload in bad) assertTrue(runCatching { update(store(), payload) }.isFailure)
        assertEquals(0, server.requestCount)
    }
    @Test fun `undo cannot masquerade as causal paid deletion without separate capability`() = runTest {
        val sparse = JsonObject(undo().filterKeys { it !in setOf("status_raw_value", "amount_minor_snapshot", "paid_at", "linked_transaction_id") })
        assertTrue(runCatching { update(store(), sparse) }.isFailure); assertEquals(0, server.requestCount)
    }
    @Test fun `malformed actor foreign owner string version nonincrementing version and skipped tombstone create fail before HTTP`() = runTest {
        val bad = listOf(JsonObject(row() + ("last_modified_by_device_id" to JsonPrimitive("device"))), JsonObject(row() + ("user_id" to JsonPrimitive(other))),
            JsonObject(row() + ("sync_version" to JsonPrimitive(version))), JsonObject(row() + ("sync_version" to JsonPrimitive((version + 1).toString()))))
        for (payload in bad) assertTrue(runCatching { update(store(), payload) }.isFailure)
        assertTrue(runCatching { store().createRecord(CloudEntity.DUE_OCCURRENCE_RECORD, "fixture", owner, JsonObject(row() + ("deleted_at" to JsonPrimitive(time)))) }.isFailure)
        assertEquals(0, server.requestCount)
    }
    @Test fun `foreign response identity and owner cannot be acknowledged`() = runTest {
        for (key in listOf("id", "user_id")) {
            server.enqueue(MockResponse().setBody("[${JsonObject(row() + (key to JsonPrimitive(other)))}]"))
            assertTrue(runCatching { update(store()) }.isFailure)
        }
        assertEquals(2, server.requestCount)
    }
    @Test fun `complete cycle lookup is owned source month ordered and obeys exact capped range`() = runTest {
        server.enqueue(MockResponse().setHeader("Content-Range", "0-0/2").setBody("[${row()}]"))
        val page = store(false).fetchInstallmentCyclePage(device, "2026-10", "fixture", owner, 0, 100)
        assertEquals(1, page.nextOffset); assertEquals(id, page.records.single().id)
        val request = server.takeRequest(1, TimeUnit.SECONDS)!!; val url = request.requestUrl!!
        assertEquals("GET", request.method); assertEquals("eq.${owner.value}", url.queryParameter("user_id")); assertEquals("eq.installment", url.queryParameter("source_kind_raw_value"))
        assertEquals("eq.$device", url.queryParameter("source_id")); assertEquals("eq.2026-10", url.queryParameter("selected_month_key")); assertEquals("id.asc", url.queryParameter("order")); assertNull(url.queryParameter("deleted_at"))
        assertEquals("0-99", request.getHeader("Range")); assertEquals("count=exact", request.getHeader("Prefer"))
    }
    @Test fun `incomplete range wrong scope and malformed cycle page cannot prove absence`() = runTest {
        val bodies = listOf(row(), JsonObject(row() + ("source_id" to JsonPrimitive(other))), JsonObject(row() + ("selected_month_key" to JsonPrimitive("2026-11"))), JsonObject(row() + ("user_id" to JsonPrimitive(other))))
        for ((index, body) in bodies.withIndex()) {
            val response = MockResponse().setBody("[$body]"); if (index > 0) response.setHeader("Content-Range", "0-0/1")
            server.enqueue(response)
            assertTrue(runCatching { store(false).fetchInstallmentCyclePage(device, "2026-10", "fixture", owner, 0, 100) }.isFailure)
        }
    }

}
