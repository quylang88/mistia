package vn.com.quyln.mistia.core.sync

import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.runCurrent
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import vn.com.quyln.mistia.core.model.*

@OptIn(ExperimentalCoroutinesApi::class)
class InstallmentSourcePushTest {
    private val owner = UserId("11111111-1111-1111-1111-111111111111")
    private val id = "22222222-2222-2222-2222-222222222222"
    private val device = "33333333-3333-3333-3333-333333333333"
    private val wallet = "44444444-4444-4444-4444-444444444444"
    private val tx = "55555555-5555-5555-5555-555555555555"
    private val child = "77777777-7777-7777-7777-777777777777"
    private val other = "99999999-9999-9999-9999-999999999999"
    private val created = "2026-01-15T00:00:00Z"
    private val deleted = "2026-10-15T00:00:00Z"
    private val later = "2026-10-16T00:00:00Z"
    private val now = "2026-10-17T00:00:00Z"
    private val plan = InstallmentPlanRecord(id, owner.value, "Loan", "mistia.plan.loan", 1000, 15, null, 1, wallet, "JPY", false,
        created, created, null, 3, device).toCloudRecord()
    private fun cycle(status: String = "paid", linked: String? = tx) = DueOccurrenceRecord(child, owner.value, "installment", id,
        "2026-01", created, 1000, status, if (status == "paid") created else null, linked, created, created, null, 5, device).toCloudRecord()
    private fun tombstone(r: CloudRecord) = r.copy(updatedAt = deleted, deletedAt = deleted, payload = JsonObject(r.payload + mapOf(
        "updated_at" to JsonPrimitive(deleted), "deleted_at" to JsonPrimitive(deleted), "last_modified_by_device_id" to JsonPrimitive(device))))
    private fun queued(r: CloudRecord) = QueuedMutation(PendingMutation(CloudEntity.fromTable(r.entity)!!, r.id, owner.value,
        if (r.deletedAt == null) MutationKind.UPSERT else MutationKind.DELETE, r.payload, r.updatedAt!!, r.syncVersion, device), 0, 0, null, true)
    private fun ledger(amount: Long = 1000, time: String = created) = CloudRecord(CloudEntity.LEDGER_TRANSACTION.table, tx, owner.value,
        buildJsonObject { put("id", tx); put("user_id", owner.value); put("primary_kind_raw_value", "expense"); put("entry_status_raw_value", "posted")
            put("title", "Loan payment"); put("amount_minor", amount); put("source_currency_code", "JPY"); put("source_wallet_id", wallet)
            put("occurred_at", created); put("created_at", created); put("updated_at", time); put("deleted_at", JsonNull); put("is_archived", false)
            put("sync_version", 11); put("created_by_user_id", owner.value); put("last_modified_by_user_id", owner.value); put("last_modified_by_device_id", device) }, time, null, 11)
    private fun snapshot(before: CloudRecord = cycle(), prior: QueuedMutation? = null, source: CloudRecord = plan): InstallmentAcknowledgementSnapshot {
        val original = InstallmentMutationSnapshot(owner, id, InstallmentMutationSnapshot.entities.associateWith {
            when (it) { CloudEntity.INSTALLMENT_PLAN -> listOf(source); CloudEntity.DUE_OCCURRENCE_RECORD -> listOf(before); else -> emptyList() }
        })
        val deletedRows = listOf(source, before).map(::tombstone)
        val writes = deletedRows.map { it to queued(it).mutation }
        val batch = InstallmentDeletionBatch.capture(original, writes, listOfNotNull(prior), wallet)!!
        return InstallmentAcknowledgementSnapshot(owner, id, batch, InstallmentAcknowledgementSnapshot.entities.associateWith {
            when (it) { CloudEntity.INSTALLMENT_PLAN -> listOf(deletedRows[0]); CloudEntity.DUE_OCCURRENCE_RECORD -> listOf(deletedRows[1]); else -> listOf(ledger()) }
        }, deletedRows.map(::queued))
    }
    private fun remotePlan() = plan.copy(updatedAt = later, syncVersion = 4, payload = JsonObject(plan.payload + mapOf("name" to JsonPrimitive("Remote"), "updated_at" to JsonPrimitive(later), "sync_version" to JsonPrimitive(4))))
    private fun remoteCycle() = cycle().copy(updatedAt = later, syncVersion = 6, payload = JsonObject(cycle().payload + mapOf("updated_at" to JsonPrimitive(later), "sync_version" to JsonPrimitive(6))))
    private fun root(s: InstallmentAcknowledgementSnapshot) = s.queues.single { it.mutation.entity == CloudEntity.INSTALLMENT_PLAN }
    private val millis = InstantForTest()
    private fun InstantForTest() = java.time.Instant.parse(now).toEpochMilli()
    private fun coordinator(l: Local, r: Remote, enabled: Boolean = true) =
        InstallmentPushCoordinator(l, r, enabled, dependentDeletionReady = true) { millis }
    private class Local(var snapshot: InstallmentAcknowledgementSnapshot) : LocalStore {
        var beforeCommit: (() -> Unit)? = null
        var commits = 0; var genericAcks = 0; var failScopedPersistence = false
        override fun observe(entity: String, ownerUserId: UserId) = MutableStateFlow(emptyList<CloudRecord>())
        override fun observeEntityCounts(ownerUserId: UserId) = MutableStateFlow(emptyList<EntityCount>())
        override suspend fun record(ownerUserId: UserId, entity: String, recordId: String) = snapshot.recordsByEntity.values.flatten().singleOrNull { it.ownerUserId == ownerUserId.value && it.entity == entity && it.id == recordId }
        override suspend fun commitMutation(record: CloudRecord, mutation: PendingMutation) = Unit
        override suspend fun replacePullSnapshot(ownerUserId: UserId, entity: String, records: List<CloudRecord>) = Unit
        override suspend fun clearAccount(ownerUserId: UserId) = Unit
        override suspend fun pendingMutations(ownerUserId: UserId, entity: CloudEntity, dueAtEpochMillis: Long, limit: Int) =
            snapshot.queues.filter { it.mutation.subjectUserId == ownerUserId.value && it.mutation.entity == entity && it.nextAttemptAtEpochMillis <= dueAtEpochMillis }
        override suspend fun pendingMutationRecordIds(ownerUserId: UserId, entity: String) = snapshot.queues.filter { it.mutation.entity.table == entity }.map { it.mutation.recordId }.toSet()
        override suspend fun installmentAcknowledgementSnapshot(owner: UserId, planId: String) = snapshot.also { require(it.owner == owner && it.planId == planId) }
        override suspend fun acknowledgeMutation(mutation: QueuedMutation, remoteRecord: CloudRecord): Boolean { genericAcks++; return false }
        override suspend fun recordInstallmentSourceFailure(queued: QueuedMutation, requestBatchId: String?, nextAttemptAtEpochMillis: Long, errorCode: String): Boolean {
            if (failScopedPersistence) throw IllegalStateException("fixture persistence failure")
            if (snapshot.batch?.batchId != requestBatchId) return false
            return recordMutationFailure(queued, nextAttemptAtEpochMillis, errorCode)
        }
        override suspend fun recordMutationFailure(mutation: QueuedMutation, nextAttemptAtEpochMillis: Long, errorCode: String): Boolean {
            if (mutation !in snapshot.queues) return false
            snapshot = snapshot.copy(queues = snapshot.queues.map { if (it == mutation) it.copy(attemptCount = it.attemptCount + 1, nextAttemptAtEpochMillis = nextAttemptAtEpochMillis, lastError = errorCode) else it }); return true
        }
        override suspend fun commitInstallmentSourceAcknowledgement(expected: InstallmentAcknowledgementSnapshot, queued: QueuedMutation,
            requestBatchId: String?, remote: CloudRecord, remoteCycles: Map<String, CloudRecord?>, remoteLedger: Map<String, CloudRecord?>, now: String): Boolean {
            beforeCommit?.invoke()
            if (expected.batch?.batchId != requestBatchId || runCatching { expected.requireUnchanged(snapshot) }.isFailure) return false
            val decision = planInstallmentSourceAcknowledgement(expected, queued, remote, remoteCycles, remoteLedger, now) as InstallmentSourceAckDecision.Ready
            val changed = (decision.cycles.map { it.record } + remote).associateBy { it.entity to it.id }
            val keys = changed.keys
            snapshot = snapshot.copy(batch = if (decision.clearBatch) null else snapshot.batch,
                recordsByEntity = snapshot.recordsByEntity.mapValues { (_, rows) -> rows.map { changed[it.entity to it.id] ?: it } },
                queues = snapshot.queues.filterNot { it.mutation.entity.table to it.mutation.recordId in keys } + decision.cycles.mapNotNull { it.queue })
            commits++; return true
        }
    }
    private inner class Remote : RemoteMutationStore {
        val rows = mutableMapOf<Pair<CloudEntity, String>, CloudRecord?>((CloudEntity.INSTALLMENT_PLAN to id) to remotePlan(),
            (CloudEntity.DUE_OCCURRENCE_RECORD to child) to remoteCycle(), (CloudEntity.LEDGER_TRANSACTION to tx) to ledger())
        val reads = mutableListOf<Pair<CloudEntity, String>>()
        var writes = 0; var onFetch: suspend (CloudEntity) -> Unit = {}
        override suspend fun fetchRecord(entity: CloudEntity, recordId: String, accessToken: String, ownerUserId: UserId): CloudRecord? {
            assertEquals(owner, ownerUserId); assertEquals("fixture", accessToken); reads += entity to recordId
            val result = rows[entity to recordId]; onFetch(entity); return result
        }
        override suspend fun createRecord(entity: CloudEntity, accessToken: String, ownerUserId: UserId, payload: JsonObject): CloudRecord = error("Unexpected create")
        override suspend fun conditionalUpdate(entity: CloudEntity, recordId: String, accessToken: String, ownerUserId: UserId, expectedVersion: Long, payload: JsonObject): CloudRecord {
            assertEquals(CloudEntity.INSTALLMENT_PLAN, entity); writes++
            return tombstone(plan).copy(syncVersion = 5, payload = JsonObject(tombstone(plan).payload + ("sync_version" to JsonPrimitive(5))))
        }
    }
    @Test fun `active remote winner restores paid history and clears batch atomically with no financial write`() = runTest {
        val l = Local(snapshot()); val ledger = l.snapshot.recordsByEntity.getValue(CloudEntity.LEDGER_TRANSACTION); val r = Remote()
        assertEquals(1, coordinator(l, r).pushPending(owner, "fixture").acknowledged)
        assertEquals(remotePlan(), l.record(owner, CloudEntity.INSTALLMENT_PLAN.table, id)); assertEquals(remoteCycle(), l.record(owner, CloudEntity.DUE_OCCURRENCE_RECORD.table, child))
        assertEquals(ledger, l.snapshot.recordsByEntity.getValue(CloudEntity.LEDGER_TRANSACTION)); assertNull(l.snapshot.batch)
        assertTrue(l.snapshot.queues.isEmpty()); assertEquals(1, l.commits); assertEquals(0, l.genericAcks); assertEquals(0, r.writes)
    }
    @Test fun `source delete success retains child deletion batch and posted expense`() = runTest {
        val l = Local(snapshot()); val original = l.snapshot; val r = Remote().apply { rows[CloudEntity.INSTALLMENT_PLAN to id] = plan }
        assertEquals(1, coordinator(l, r).pushPending(owner, "fixture").pushed)
        assertEquals(original.batch, l.snapshot.batch); assertEquals(listOf(original.queues.last()), l.snapshot.queues)
        assertEquals(original.recordsByEntity.getValue(CloudEntity.LEDGER_TRANSACTION), l.snapshot.recordsByEntity.getValue(CloudEntity.LEDGER_TRANSACTION))
        assertEquals(listOf(CloudEntity.INSTALLMENT_PLAN to id), r.reads); assertEquals(1, r.writes)
    }
    @Test fun `legacy deletion with no causal batch is held before any request`() = runTest {
        val l = Local(snapshot().copy(batch = null)); val r = Remote()
        assertEquals(DomainPushSummary(), coordinator(l, r).pushPending(owner, "fixture")); assertTrue(r.reads.isEmpty()); assertEquals(0, l.commits)
    }
    @Test fun `batch ABA with identical source queue makes old response stale before child fetch`() = runTest {
        val l = Local(snapshot()); val r = Remote().apply { onFetch = { e -> if (e == CloudEntity.INSTALLMENT_PLAN) l.snapshot = l.snapshot.copy(batch = l.snapshot.batch!!.copy(batchId = other)) } }
        assertEquals(1, coordinator(l, r).pushPending(owner, "fixture").staleResponses)
        assertEquals(other, l.snapshot.batch!!.batchId); assertEquals(2, l.snapshot.queues.size); assertEquals(0, l.commits); assertEquals(1, r.reads.size)
    }
    @Test fun `ledger drift defers and next pull refreshed attempt restores without a ledger write`() = runTest {
        val l = Local(snapshot()); val r = Remote().apply { rows[CloudEntity.LEDGER_TRANSACTION to tx] = ledger(900) }
        assertEquals(DomainPushSummary(), coordinator(l, r).pushPending(owner, "fixture")); assertEquals(0, l.commits)
        l.snapshot = l.snapshot.copy(recordsByEntity = l.snapshot.recordsByEntity + (CloudEntity.LEDGER_TRANSACTION to listOf(ledger(900))))
        assertEquals(1, coordinator(l, r).pushPending(owner, "fixture").acknowledged); assertEquals(0, r.writes)
    }
    @Test fun `foreign child or ledger cannot commit source ACK`() = runTest {
        for (entity in listOf(CloudEntity.DUE_OCCURRENCE_RECORD, CloudEntity.LEDGER_TRANSACTION)) {
            val l = Local(snapshot()); val r = Remote(); val key = entity to if (entity == CloudEntity.DUE_OCCURRENCE_RECORD) child else tx
            r.rows[key] = r.rows[key]!!.copy(ownerUserId = other)
            assertEquals(1, coordinator(l, r).pushPending(owner, "fixture").permanentFailures); assertEquals(0, l.commits); assertNotNull(l.snapshot.batch)
        }
    }
    @Test fun `newer child intent survives root ACK without a child request`() = runTest {
        val s = snapshot(); val newer = remoteCycle(); val q = queued(newer)
        val l = Local(s.copy(recordsByEntity = s.recordsByEntity + (CloudEntity.DUE_OCCURRENCE_RECORD to listOf(newer)), queues = listOf(root(s), q))); val r = Remote()
        assertEquals(1, coordinator(l, r).pushPending(owner, "fixture").acknowledged)
        assertEquals(listOf(q), l.snapshot.queues); assertEquals(newer, l.record(owner, CloudEntity.DUE_OCCURRENCE_RECORD.table, child)); assertEquals(1, r.reads.size)
    }
    @Test fun `prior child local winner restores exact retry metadata`() = runTest {
        val before = remoteCycle(); val prior = queued(before).copy(attemptCount = 7, nextAttemptAtEpochMillis = Long.MAX_VALUE, lastError = "http_503")
        val l = Local(snapshot(before, prior)); val r = Remote().apply { rows[CloudEntity.DUE_OCCURRENCE_RECORD to child] = cycle("pending", null) }
        assertEquals(1, coordinator(l, r).pushPending(owner, "fixture").acknowledged); assertEquals(listOf(prior), l.snapshot.queues)
    }
    @Test fun `snapshot changes at atomic commit fence leave all new data intact`() = runTest {
        val l = Local(snapshot()); val r = Remote()
        l.beforeCommit = { l.snapshot = l.snapshot.copy(recordsByEntity = l.snapshot.recordsByEntity + (CloudEntity.LEDGER_TRANSACTION to listOf(ledger(800)))) }
        assertEquals(1, coordinator(l, r).pushPending(owner, "fixture").staleResponses); assertEquals(0, l.commits); assertEquals(2, l.snapshot.queues.size)
    }
    @Test fun `gate off does not inspect or mutate causal intent`() = runTest {
        val l = Local(snapshot()); val original = l.snapshot; val r = Remote()
        assertEquals(DomainPushSummary(), coordinator(l, r, false).pushPending(owner, "fixture")); assertSame(original, l.snapshot); assertTrue(r.reads.isEmpty())
    }
    @Test fun `late noncooperative response after cancellation cannot acknowledge source`() = runTest {
        val l = Local(snapshot()); val r = Remote(); val entered = CompletableDeferred<Unit>(); val release = CompletableDeferred<Unit>()
        r.onFetch = { withContext(NonCancellable) { entered.complete(Unit); release.await() } }
        val job = launch { coordinator(l, r).pushPending(owner, "fixture") }
        runCurrent(); assertTrue("Source request must start", entered.isCompleted); entered.await(); job.cancel(); release.complete(Unit); job.join()
        assertEquals(0, l.commits); assertEquals(0, l.genericAcks); assertEquals(2, l.snapshot.queues.size)
    }
    @Test fun `concurrent requests keep independent immutable batch contexts`() = runTest {
        val l = Local(snapshot()); val r = Remote(); val entered = CompletableDeferred<Unit>(); val release = CompletableDeferred<Unit>(); var first = true
        r.onFetch = { if (first) { first = false; withContext(NonCancellable) { entered.complete(Unit); release.await() } } }
        val c = coordinator(l, r); val old = async { c.pushPending(owner, "fixture") }
        runCurrent(); assertTrue("Source request must start", entered.isCompleted); entered.await(); l.snapshot = l.snapshot.copy(batch = l.snapshot.batch!!.copy(batchId = other))
        val fresh = c.pushPending(owner, "fixture"); release.complete(Unit)
        assertEquals(1, fresh.acknowledged); assertEquals(1, old.await().staleResponses); assertEquals(1, l.commits)
    }
    @Test fun `failed old request cannot assign retry or conflict to an identical new batch queue`() = runTest {
        val l = Local(snapshot()); val r = Remote().apply { onFetch = { l.snapshot = l.snapshot.copy(batch = l.snapshot.batch!!.copy(batchId = other)); throw java.io.IOException("fixture") } }
        assertEquals(1, coordinator(l, r).pushPending(owner, "fixture").staleResponses)
        assertEquals(0, root(l.snapshot).attemptCount); assertNull(root(l.snapshot).lastError); assertEquals(other, l.snapshot.batch!!.batchId)
    }

    @Test fun `failed scoped persistence never falls back to unfenced generic queue write`() = runTest {
        val l = Local(snapshot()).apply { failScopedPersistence = true }; val r = Remote().apply { onFetch = { throw java.io.IOException("fixture") } }
        assertTrue(runCatching { coordinator(l, r).pushPending(owner, "fixture") }.isFailure)
        assertEquals(0, root(l.snapshot).attemptCount); assertNull(root(l.snapshot).lastError)
    }

}
