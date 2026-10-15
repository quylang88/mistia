package vn.com.quyln.mistia.core.sync

import java.io.IOException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import vn.com.quyln.mistia.core.model.*
import vn.com.quyln.mistia.core.network.SupabaseHttpException

class InstallmentPushCoordinatorTest {
    private val owner = UserId("11111111-1111-1111-1111-111111111111")
    private val id = "22222222-2222-2222-2222-222222222222"
    private val device = "33333333-3333-3333-3333-333333333333"
    private val wallet = "44444444-4444-4444-4444-444444444444"
    private val other = "99999999-9999-9999-9999-999999999999"
    private val now = "2026-10-15T00:00:00Z"
    private val later = "2026-10-15T01:00:00Z"
    private val millis = 1792022400000L
    private fun record(version: Long = 3, name: String = "Loan", time: String = now) = InstallmentPlanRecord(id, owner.value, name,
        "mistia.plan.loan", 9007199254740993, 31, null, 2, wallet, "JPY", false, now, time, null, version, device).toCloudRecord()
    private fun deleted(version: Long = 3) = record(version).let { it.copy(deletedAt = now, payload = JsonObject(it.payload + ("deleted_at" to JsonPrimitive(now)))) }
    private fun queue(row: CloudRecord) = QueuedMutation(PendingMutation(CloudEntity.INSTALLMENT_PLAN, id, owner.value,
        if (row.deletedAt == null) MutationKind.UPSERT else MutationKind.DELETE, row.payload, row.updatedAt!!, row.syncVersion, device), 0, 0, null)
    private fun local(row: CloudRecord = record()) = Local(row, queue(row))
    private fun coordinator(local: LocalStore, remote: RemoteMutationStore, enabled: Boolean = true) = InstallmentPushCoordinator(local, remote, enabled) { millis }
    private class Local(var row: CloudRecord?, var queued: QueuedMutation?) : LocalStore {
        var pendingWallets = emptySet<String>()
        var dueRows = emptyList<CloudRecord>()
        var pendingDueIds = emptySet<String>()
        override fun observe(entity: String, ownerUserId: UserId) = MutableStateFlow(emptyList<CloudRecord>())
        override fun observeEntityCounts(ownerUserId: UserId) = MutableStateFlow(emptyList<EntityCount>())
        override suspend fun record(ownerUserId: UserId, entity: String, recordId: String) = (listOfNotNull(row) + dueRows).firstOrNull { it.entity == entity && it.id == recordId && it.ownerUserId == ownerUserId.value }
        override suspend fun commitMutation(record: CloudRecord, mutation: PendingMutation) = Unit
        override suspend fun replacePullSnapshot(ownerUserId: UserId, entity: String, records: List<CloudRecord>) = Unit
        override suspend fun clearAccount(ownerUserId: UserId) = Unit
        override suspend fun pendingMutations(ownerUserId: UserId, entity: CloudEntity, dueAtEpochMillis: Long, limit: Int) = listOfNotNull(queued).filter {
            it.mutation.subjectUserId == ownerUserId.value && it.mutation.entity == entity && it.nextAttemptAtEpochMillis <= dueAtEpochMillis
        }
        override suspend fun pendingMutationRecordIds(ownerUserId: UserId, entity: String) = when (entity) { CloudEntity.LEDGER_WALLET.table -> pendingWallets; CloudEntity.DUE_OCCURRENCE_RECORD.table -> pendingDueIds; else -> emptySet() }
        override suspend fun acknowledgeMutation(mutation: QueuedMutation, remoteRecord: CloudRecord): Boolean {
            if (queued != mutation) return false
            queued = null; row = remoteRecord; return true
        }
        override suspend fun recordMutationFailure(mutation: QueuedMutation, nextAttemptAtEpochMillis: Long, errorCode: String): Boolean {
            if (queued != mutation) return false
            queued = mutation.copy(attemptCount = mutation.attemptCount + 1, nextAttemptAtEpochMillis = nextAttemptAtEpochMillis, lastError = errorCode); return true
        }
    }
    private class Remote : RemoteMutationStore {
        var fetched: CloudRecord? = null
        val fetchResults = ArrayDeque<CloudRecord?>()
        var created: CloudRecord? = null
        var updated: CloudRecord? = null
        var failure: Throwable? = null
        var createFailure: Throwable? = null
        var onFetch: (() -> Unit)? = null
        var reads = 0; var writes = 0
        var payload: JsonObject? = null; var base: Long? = null
        override suspend fun fetchRecord(entity: CloudEntity, recordId: String, accessToken: String, ownerUserId: UserId): CloudRecord? {
            reads++; onFetch?.invoke(); failure?.let { throw it }
            return if (fetchResults.isEmpty()) fetched else fetchResults.removeFirst()
        }
        override suspend fun createRecord(entity: CloudEntity, accessToken: String, ownerUserId: UserId, payload: JsonObject): CloudRecord {
            writes++; this.payload = payload; createFailure?.let { throw it }; return requireNotNull(created)
        }
        override suspend fun conditionalUpdate(entity: CloudEntity, recordId: String, accessToken: String, ownerUserId: UserId, expectedVersion: Long, payload: JsonObject): CloudRecord? {
            writes++; base = expectedVersion; this.payload = payload; return updated
        }
    }
    @Test fun `gate off preserves queue with zero remote calls`() = runTest {
        val l = local(); val q = l.queued; val r = Remote()
        assertEquals(DomainPushSummary(), coordinator(l, r, false).pushPending(owner, "fixture"))
        assertSame(q, l.queued); assertEquals(0, r.reads); assertEquals(0, r.writes)
    }
    @Test fun `create uses stable ID version one exact amount and nullable cycles`() = runTest {
        val l = local(record(0)); val r = Remote().apply { created = record(1) }
        assertEquals(1, coordinator(l, r).pushPending(owner, "fixture").pushed)
        assertEquals(JsonPrimitive(1), r.payload!!["sync_version"]); assertEquals(JsonPrimitive(9007199254740993L), r.payload!!["amount_per_cycle_minor"])
        assertSame(JsonNull, r.payload!!["total_cycles"]); assertNull(l.queued)
    }
    @Test fun `conditional edit keeps Long base and increments exactly`() = runTest {
        val v = 9007199254740993L; val l = local(record(v)); val r = Remote().apply { fetched = record(v, "Before"); updated = record(v + 1) }
        assertEquals(1, coordinator(l, r).pushPending(owner, "fixture").pushed)
        assertEquals(v, r.base); assertEquals(JsonPrimitive(v + 1), r.payload!!["sync_version"])
    }
    @Test fun `typed semantic ACK ignores unknown extension and missing nullable count without a write`() = runTest {
        val l = local(); val r = Remote().apply { fetched = record(4, time = later).let { it.copy(payload = JsonObject(it.payload.filterKeys { k -> k != "total_cycles" } + ("future" to JsonPrimitive(true)))) } }
        assertEquals(1, coordinator(l, r).pushPending(owner, "fixture").acknowledged)
        assertEquals(0, r.writes); assertEquals(4L, l.row!!.syncVersion); assertNull(l.queued)
    }
    @Test fun `raw currency case remains semantically distinct as Swift fingerprint requires`() = runTest {
        val row = record().let { it.copy(payload = JsonObject(it.payload + ("currency_code" to JsonPrimitive("jpy")))) }
        val l = local(row); val r = Remote().apply { fetched = record() }
        assertEquals(1, coordinator(l, r).pushPending(owner, "fixture").conflicts)
        assertNotNull(l.queued); assertEquals(1, r.writes)
    }
    @Test fun `pending payment wallet defers active plan before IO but not source tombstone`() = runTest {
        val l = local().apply { pendingWallets = setOf(wallet) }; val r = Remote()
        assertEquals(DomainPushSummary(), coordinator(l, r).pushPending(owner, "fixture")); assertEquals(0, r.reads)
        l.row = deleted(); l.queued = queue(l.row!!)
        assertEquals(1, coordinator(l, r).pushPending(owner, "fixture").acknowledged); assertNull(l.queued); assertEquals(0, r.writes)
    }
    @Test fun `source delete uses sparse metadata and leaves remote business fields intact`() = runTest {
        val l = local(deleted()); val authoritative = record(3, "Remote name")
        val r = Remote().apply { fetched = authoritative; updated = authoritative.copy(deletedAt = now, syncVersion = 4,
            payload = JsonObject(authoritative.payload + mapOf("deleted_at" to JsonPrimitive(now), "sync_version" to JsonPrimitive(4)))) }
        assertEquals(1, coordinator(l, r).pushPending(owner, "fixture").pushed)
        assertEquals(setOf("id", "user_id", "updated_at", "deleted_at", "sync_version", "last_modified_by_device_id"), r.payload!!.keys)
        assertEquals("Remote name", l.row!!.payload["name"]!!.jsonPrimitive.content); assertNull(l.queued)
    }
    @Test fun `already deleted remote is acknowledged without rewriting history`() = runTest {
        val l = local(deleted()); val r = Remote().apply { fetched = deleted(8) }
        assertEquals(1, coordinator(l, r).pushPending(owner, "fixture").acknowledged); assertEquals(0, r.writes); assertEquals(8L, l.row!!.syncVersion)
    }
    @Test fun `remote later edit wins delete conflict and source stays active`() = runTest {
        val l = local(deleted()); val r = Remote().apply { fetched = record(4, "Remote edit", later) }
        assertEquals(1, coordinator(l, r).pushPending(owner, "fixture").acknowledged); assertNull(l.row!!.deletedAt); assertEquals(0, r.writes)
    }
    @Test fun `local later edit wins with conditional remote base and higher version`() = runTest {
        val l = local(record(3, time = later)); val r = Remote().apply { fetched = record(4, "Remote edit"); updated = record(5, time = later) }
        assertEquals(1, coordinator(l, r).pushPending(owner, "fixture").pushed); assertEquals(4L, r.base); assertEquals(JsonPrimitive(5), r.payload!!["sync_version"])
    }
    @Test fun `same clock version business conflict retains mutation for review`() = runTest {
        val l = local(); val r = Remote().apply { fetched = record(3, "Different") }
        assertEquals(1, coordinator(l, r).pushPending(owner, "fixture").conflicts)
        assertEquals(Long.MAX_VALUE, l.queued!!.nextAttemptAtEpochMillis); assertTrue(l.queued!!.lastError!!.startsWith("conflict_"))
    }
    @Test fun `create race refetches and acknowledges semantic winner`() = runTest {
        val l = local(record(0)); val r = Remote().apply { fetchResults.add(null); fetchResults.add(record(1, time = later)); createFailure = SupabaseHttpException(409, "fixture") }
        assertEquals(1, coordinator(l, r).pushPending(owner, "fixture").acknowledged); assertEquals(2, r.reads); assertNull(l.queued)
    }
    @Test fun `conditional update race uses latest remote winner`() = runTest {
        val l = local(); val r = Remote().apply { fetchResults.add(record(3, "Before")); fetchResults.add(record(4, "Newer", later)) }
        assertEquals(1, coordinator(l, r).pushPending(owner, "fixture").acknowledged); assertEquals("Newer", l.row!!.payload["name"]!!.jsonPrimitive.content)
    }
    @Test fun `retryable network failure keeps sanitized failure and queue`() = runTest {
        val l = local(); val r = Remote().apply { failure = IOException("sensitive fixture") }
        assertEquals(1, coordinator(l, r).pushPending(owner, "fixture").retryableFailures)
        assertEquals("network_io", l.queued!!.lastError); assertTrue(l.queued!!.nextAttemptAtEpochMillis > millis)
    }
    @Test fun `cancellation propagates without marking a permanent failure`() = runTest {
        val l = local(); val r = Remote().apply { failure = CancellationException("fixture") }
        var cancelled = false
        try { coordinator(l, r).pushPending(owner, "fixture") } catch (_: CancellationException) { cancelled = true }
        assertTrue(cancelled); assertEquals(0, l.queued!!.attemptCount)
    }
    @Test fun `late ACK cannot remove or overwrite a newer local mutation`() = runTest {
        val l = local(record(0)); val newer = record(0, "New edit", later); val q = queue(newer)
        val r = Remote().apply { created = record(1); onFetch = { l.row = newer; l.queued = q } }
        assertEquals(1, coordinator(l, r).pushPending(owner, "fixture").staleResponses)
        assertSame(q, l.queued); assertEquals(newer, l.row)
    }
    @Test fun `account removal while response is in flight cannot recreate old data`() = runTest {
        val l = local(); val r = Remote().apply { fetched = record(4); onFetch = { l.row = null; l.queued = null } }
        assertEquals(1, coordinator(l, r).pushPending(owner, "fixture").staleResponses); assertNull(l.row); assertNull(l.queued)
    }
    @Test fun `malformed local scalar and envelope version fail before remote IO`() = runTest {
        for (row in listOf(record().copy(syncVersion = 4), record().let { it.copy(payload = JsonObject(it.payload + ("total_cycles" to JsonPrimitive("12")))) })) {
            val l = local(row); val r = Remote()
            assertEquals(1, coordinator(l, r).pushPending(owner, "fixture").permanentFailures); assertEquals(0, r.reads); assertNotNull(l.queued)
        }
    }
    @Test fun `foreign remote response cannot ACK or overwrite owned local data`() = runTest {
        val l = local(); val before = l.row; val r = Remote().apply { fetched = record(4).copy(ownerUserId = other) }
        assertEquals(1, coordinator(l, r).pushPending(owner, "fixture").permanentFailures); assertEquals(before, l.row); assertNotNull(l.queued)
    }
    @Test fun `version overflow is retained without a wrapped version write`() = runTest {
        val l = local(record(Long.MAX_VALUE)); val r = Remote()
        assertEquals(1, coordinator(l, r).pushPending(owner, "fixture").permanentFailures); assertEquals(0, r.writes); assertNotNull(l.queued)
    }
    @Test fun `plan delete with pending installment cycle is held until its dedicated readiness is resolved`() = runTest {
        val due = DueOccurrenceRecord(other, owner.value, "installment", id, "2026-10", now, 9007199254740993, "paid", now, wallet,
            now, now, now, 3, device).toCloudRecord()
        val l = local(deleted()).apply { dueRows = listOf(due); pendingDueIds = setOf(due.id) }; val r = Remote()
        assertEquals(DomainPushSummary(), coordinator(l, r).pushPending(owner, "fixture"))
        assertEquals(0, r.reads); assertEquals(0, r.writes); assertNotNull(l.queued); assertEquals(due, l.dueRows.single())
        l.pendingDueIds = emptySet()
        assertEquals(1, coordinator(l, r).pushPending(owner, "fixture").acknowledged)
        assertEquals(due, l.dueRows.single())
    }

    @Test fun `unrelated bill cycle and foreign payload cannot block an independent plan tombstone`() = runTest {
        val raw = DueOccurrenceRecord(other, owner.value, "recurringBill", id, "2026-10", now, null, "skipped", null, null, now, now, now, 3, device).toCloudRecord()
        for (due in listOf(raw, raw.copy(payload = JsonObject(raw.payload + mapOf("source_kind_raw_value" to JsonPrimitive("installment"), "user_id" to JsonPrimitive(other)))))) {
            val l = local(deleted()).apply { dueRows = listOf(due); pendingDueIds = setOf(due.id) }; val r = Remote()
            assertEquals(1, coordinator(l, r).pushPending(owner, "fixture").acknowledged)
            assertEquals(due, l.dueRows.single()); assertEquals(0, r.writes)
        }
    }
    @Test fun `missing pending cycle row holds source deletion without unsafe remote fallback`() = runTest {
        val l = local(deleted()).apply { pendingDueIds = setOf(other) }; val r = Remote()
        assertEquals(DomainPushSummary(), coordinator(l, r).pushPending(owner, "fixture"))
        assertEquals(0, r.reads); assertNotNull(l.queued)
    }

    @Test fun `foreign local payload owner and aliased payload ID fail before remote IO`() = runTest {
        for (field in listOf("user_id", "id")) {
            val row = record().let { it.copy(payload = JsonObject(it.payload + (field to JsonPrimitive(other)))) }
            val l = local(row); val r = Remote()
            assertEquals(1, coordinator(l, r).pushPending(owner, "fixture").permanentFailures)
            assertEquals(0, r.reads); assertEquals(0, r.writes); assertEquals(row, l.row); assertNotNull(l.queued)
        }
    }

    @Test fun `uppercase wallet UUID waits for the same canonical pending wallet`() = runTest {
        val canonical = "abcdefab-cdef-abcd-efab-cdefabcdefab"
        val row = record(0).let { it.copy(payload = JsonObject(it.payload + ("payment_wallet_id" to JsonPrimitive(canonical.uppercase())))) }
        val l = local(row).apply { pendingWallets = setOf(canonical) }
        val r = Remote().apply { created = row.copy(syncVersion = 1, payload = JsonObject(row.payload + ("sync_version" to JsonPrimitive(1)))) }
        assertEquals(DomainPushSummary(), coordinator(l, r).pushPending(owner, "fixture"))
        assertEquals(0, r.reads); assertEquals(0, r.writes); assertNotNull(l.queued)
    }

}
