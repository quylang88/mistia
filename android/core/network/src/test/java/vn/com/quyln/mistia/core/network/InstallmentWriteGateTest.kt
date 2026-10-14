package vn.com.quyln.mistia.core.network

import kotlinx.coroutines.test.runTest
import okhttp3.OkHttpClient
import okhttp3.tls.HeldCertificate
import okhttp3.tls.HandshakeCertificates
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.MockResponse
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import vn.com.quyln.mistia.core.model.*

class InstallmentWriteGateTest {
    private fun transport(): Pair<MockWebServer, OkHttpClient> {
        val certificate = HeldCertificate.Builder().commonName("localhost").addSubjectAlternativeName("localhost").build()
        val serverTls = HandshakeCertificates.Builder().heldCertificate(certificate).build()
        val clientTls = HandshakeCertificates.Builder().addTrustedCertificate(certificate.certificate).build()
        val server = MockWebServer().apply { useHttps(serverTls.sslSocketFactory(), false); start() }
        val client = OkHttpClient.Builder().sslSocketFactory(clientTls.sslSocketFactory(), clientTls.trustManager).build()
        return server to client
    }
    @Test fun `bill occurrence permission does not enable installment children`() = runTest { dueSourceDenied("installment") }
    @Test fun `bill occurrence permission does not enable card children`() = runTest { dueSourceDenied("creditCard") }
    @Test fun `source less occurrence writes cannot bypass the domain gate`() = runTest { dueSourceDenied(null) }
    private suspend fun dueSourceDenied(kind: String?) {
        val (server, client) = transport()
        try {
            val owner = UserId("11111111-1111-1111-1111-111111111111"); val id = "22222222-2222-2222-2222-222222222222"
            val now = "2026-10-14T00:00:00Z"
            val typed = DueOccurrenceRecord(id, owner.value, kind ?: "recurringBill", id, "2026-10", now, 5000, "skipped", null, null, now, now, null, 0, null)
            val payload = typed.toPayload().let { if (kind == null) JsonObject(it - "source_kind_raw_value") else it }
            val store = SupabasePostgrestRemoteStore(SupabaseConfig(server.url("/").toString().removeSuffix("/"), "publishable-key"),
                client, writableEntities = setOf(CloudEntity.DUE_OCCURRENCE_RECORD))
            server.enqueue(MockResponse().setBody("[$payload]"))
            assertTrue(runCatching { store.createRecord(CloudEntity.DUE_OCCURRENCE_RECORD, "test-token", owner, payload) }.exceptionOrNull() is IllegalStateException)
            server.enqueue(MockResponse().setBody("[$payload]"))
            assertTrue(runCatching { store.conditionalUpdate(CloudEntity.DUE_OCCURRENCE_RECORD, id, "test-token", owner, 0, payload) }.exceptionOrNull() is IllegalStateException)
            val deleted = JsonObject(payload + ("deleted_at" to JsonPrimitive(now)))
            server.enqueue(MockResponse().setBody("[$deleted]"))
            assertTrue(runCatching { store.conditionalUpdate(CloudEntity.DUE_OCCURRENCE_RECORD, id, "test-token", owner, 0, deleted) }.exceptionOrNull() is IllegalStateException)
            assertEquals(0, server.requestCount)
        } finally { server.shutdown() }
    }

    @Test fun `default and unrelated write permissions cannot send installment creation edits or tombstones`() = runTest {
        val (server, client) = transport()
        try {
            val owner = UserId("11111111-1111-1111-1111-111111111111")
            val now = "2026-10-14T00:00:00Z"
            val plan = InstallmentPlanRecord("22222222-2222-2222-2222-222222222222", owner.value, "Loan", "mistia.plan.installment",
                5000, 15, null, 1, null, "JPY", false, now, now, null, 1, null)
            for (allowed in listOf(emptySet(), CloudEntity.entries.filterNot { it == CloudEntity.INSTALLMENT_PLAN }.toSet())) {
                val store = SupabasePostgrestRemoteStore(SupabaseConfig(server.url("/").toString().removeSuffix("/"), "publishable-key"),
                    client, writableEntities = allowed)
                assertTrue(runCatching { store.createRecord(CloudEntity.INSTALLMENT_PLAN, "test-token", owner, plan.toPayload()) }.exceptionOrNull() is IllegalStateException)
                assertTrue(runCatching { store.conditionalUpdate(CloudEntity.INSTALLMENT_PLAN, plan.id, "test-token", owner, 1, plan.toPayload()) }.exceptionOrNull() is IllegalStateException)
                assertTrue(runCatching { store.conditionalUpdate(CloudEntity.INSTALLMENT_PLAN, plan.id, "test-token", owner, 1, plan.copy(deletedAt = now).toPayload()) }.exceptionOrNull() is IllegalStateException)
            }
            assertEquals(0, server.requestCount)
        } finally { server.shutdown() }
    }
}
