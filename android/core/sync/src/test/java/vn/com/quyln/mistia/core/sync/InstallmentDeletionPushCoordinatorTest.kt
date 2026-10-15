package vn.com.quyln.mistia.core.sync

import java.io.IOException
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.runCurrent
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import vn.com.quyln.mistia.core.model.*

@OptIn(ExperimentalCoroutinesApi::class)
class InstallmentDeletionPushCoordinatorTest {
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
    private var millis = java.time.Instant.parse(now).toEpochMilli()
    private fun acknowledged() = snapshot().let { it.copy(queues = it.queues.filterNot { q -> q.mutation.entity == CloudEntity.INSTALLMENT_PLAN }) }
    private fun coordinator(l: Local, r: Remote, enabled: Boolean = true) = InstallmentDeletionPushCoordinator(l, r, enabled) { millis }
    private class Local(var snapshot: InstallmentAcknowledgementSnapshot) : LocalStore {
        var beforeCommit: (() -> Unit)? = null
        var commits = 0; var failures = 0; var batchReads = 0; var failPersistence = false
        override fun observe(entity: String, ownerUserId: UserId) = MutableStateFlow(emptyList<CloudRecord>())
        override fun observeEntityCounts(ownerUserId: UserId) = MutableStateFlow(emptyList<EntityCount>())
        override suspend fun record(ownerUserId: UserId, entity: String, recordId: String) = snapshot.recordsByEntity.values.flatten().singleOrNull { it.ownerUserId == ownerUserId.value && it.entity == entity && it.id == recordId }
        override suspend fun commitMutation(record: CloudRecord, mutation: PendingMutation) = error("Generic financial write forbidden")
        override suspend fun replacePullSnapshot(ownerUserId: UserId, entity: String, records: List<CloudRecord>) = Unit
        override suspend fun clearAccount(ownerUserId: UserId) = Unit
        override suspend fun pendingMutations(ownerUserId: UserId, entity: CloudEntity, dueAtEpochMillis: Long, limit: Int) = snapshot.queues.filter { it.mutation.subjectUserId == ownerUserId.value && it.mutation.entity == entity && it.nextAttemptAtEpochMillis <= dueAtEpochMillis }
        override suspend fun pendingMutationRecordIds(ownerUserId: UserId, entity: String) = snapshot.queues.filter { it.mutation.entity.table == entity }.map { it.mutation.recordId }.toSet()
        override suspend fun acknowledgeMutation(mutation: QueuedMutation, remoteRecord: CloudRecord): Boolean = error("Generic ACK forbidden")
        override suspend fun recordMutationFailure(mutation: QueuedMutation, nextAttemptAtEpochMillis: Long, errorCode: String): Boolean = error("Generic failure write forbidden")
        override suspend fun installmentDeletionPlanIds(owner: UserId): Set<String> { batchReads++; require(owner == snapshot.owner); return setOfNotNull(snapshot.batch?.planId) }
        override suspend fun installmentAcknowledgementSnapshot(owner: UserId, planId: String) = snapshot.also { require(it.owner == owner && it.planId == planId) }
        override suspend fun commitInstallmentDeletionCompletion(expected: InstallmentAcknowledgementSnapshot, requestBatchId: String,
            remoteSource: CloudRecord?, remoteCycles: Map<String, CloudRecord?>, nowEpochMillis: Long): Boolean {
            beforeCommit?.invoke()
            if (expected.batch?.batchId != requestBatchId || runCatching { expected.requireUnchanged(snapshot) }.isFailure) return false
            val decision = planInstallmentDeletionCompletion(expected, remoteSource, remoteCycles, nowEpochMillis) as InstallmentDeletionCompletion.Ready
            val rows = (decision.cycles + decision.source).associateBy { it.entity to it.id }
            snapshot = snapshot.copy(batch = null,
                recordsByEntity = snapshot.recordsByEntity.mapValues { (_, current) -> current.map { rows[it.entity to it.id] ?: it } },
                queues = snapshot.queues.filterNot { it.mutation.entity.table to it.mutation.recordId in rows.keys })
            commits++; return true
        }
        override suspend fun recordInstallmentDeletionFailure(expected: InstallmentAcknowledgementSnapshot, requestBatchId: String,
            queued: QueuedMutation, nextAttemptAtEpochMillis: Long, errorCode: String): Boolean {
            if (failPersistence) throw IllegalStateException("fixture storage failure")
            if (snapshot.batch?.batchId != requestBatchId || runCatching { expected.requireUnchanged(snapshot) }.isFailure || queued !in snapshot.queues) return false
            snapshot = snapshot.copy(queues = snapshot.queues.map { if (it == queued) it.copy(attemptCount = it.attemptCount + 1, nextAttemptAtEpochMillis = nextAttemptAtEpochMillis, lastError = errorCode) else it })
            failures++; return true
        }
    }
    private inner class Remote : RemoteMutationStore {
        val rows = mutableMapOf<Pair<CloudEntity, String>, CloudRecord?>((CloudEntity.INSTALLMENT_PLAN to id) to tombstone(plan),
            (CloudEntity.DUE_OCCURRENCE_RECORD to child) to cycle())
        val reads = mutableListOf<Pair<CloudEntity, String>>(); val writes = mutableListOf<PendingMutation>()
        var onFetch: suspend (CloudEntity, String) -> Unit = { _, _ -> }
        var onUpdate: suspend (String) -> Unit = { }
        var race: CloudRecord? = null
        var afterUpdate: suspend (CloudRecord) -> CloudRecord = { it }
        override suspend fun fetchRecord(entity: CloudEntity, recordId: String, accessToken: String, ownerUserId: UserId): CloudRecord? {
            assertEquals(owner, ownerUserId); assertEquals("fixture", accessToken); reads += entity to recordId
            val result = rows[entity to recordId]; onFetch(entity, recordId); return result
        }
        override suspend fun createRecord(entity: CloudEntity, accessToken: String, ownerUserId: UserId, payload: JsonObject): CloudRecord = error("Creation forbidden")
        override suspend fun conditionalUpdate(entity: CloudEntity, recordId: String, accessToken: String, ownerUserId: UserId, expectedVersion: Long, payload: JsonObject): CloudRecord? {
            assertEquals(CloudEntity.DUE_OCCURRENCE_RECORD, entity); assertEquals(owner, ownerUserId)
            writes += PendingMutation(entity, recordId, ownerUserId.value, MutationKind.DELETE, payload, payload["updated_at"]!!.jsonPrimitive.content, expectedVersion, device)
            onUpdate(recordId)
            race?.let { rows[entity to recordId] = it; race = null; return null }
            val before = rows[entity to recordId]!!
            assertEquals(before.syncVersion, expectedVersion)
            val result = before.copy(payload = JsonObject(before.payload + payload), updatedAt = payload["updated_at"]!!.jsonPrimitive.content,
                deletedAt = payload["deleted_at"]!!.jsonPrimitive.content, syncVersion = payload["sync_version"]!!.jsonPrimitive.long)
            rows[entity to recordId] = result; return afterUpdate(result)
        }
    }
    @Test fun `source deletion batch commits paid metadata ACK and cleanup with no ledger request`() = runTest {
        val l = Local(acknowledged()); val financial = l.snapshot.recordsByEntity.getValue(CloudEntity.LEDGER_TRANSACTION); val r = Remote()
        assertEquals(1, coordinator(l, r).pushPending(owner, "fixture").pushed)
        assertNull(l.snapshot.batch); assertTrue(l.snapshot.queues.isEmpty()); assertEquals(1, l.commits)
        assertEquals(financial, l.snapshot.recordsByEntity.getValue(CloudEntity.LEDGER_TRANSACTION)); assertTrue(r.reads.none { it.first == CloudEntity.LEDGER_TRANSACTION })
        assertEquals(listOf(CloudEntity.INSTALLMENT_PLAN, CloudEntity.DUE_OCCURRENCE_RECORD, CloudEntity.INSTALLMENT_PLAN), r.reads.map { it.first })
        val result = DueOccurrenceRecord.fromCloudRecord(l.snapshot.recordsByEntity.getValue(CloudEntity.DUE_OCCURRENCE_RECORD).single())
        assertEquals(DueStatus.PAID, result.status); assertEquals(1000L, result.amountMinorSnapshot); assertEquals(tx, result.linkedTransactionId); assertNotNull(result.deletedAt)
    }
    @Test fun `disabled gate performs no local scan or remote request`() = runTest {
        val l = Local(acknowledged()); val r = Remote(); val before = l.snapshot
        assertEquals(DomainPushSummary(), coordinator(l, r, false).pushPending(owner, "fixture")); assertSame(before, l.snapshot); assertEquals(0, l.batchReads); assertTrue(r.reads.isEmpty())
    }
    @Test fun `pending source and blocked child defer before remote IO`() = runTest {
        for (s in listOf(snapshot(), acknowledged().let { it.copy(queues = it.queues.map { q -> q.copy(nextAttemptAtEpochMillis = Long.MAX_VALUE) }) })) {
            val l = Local(s); val r = Remote(); assertEquals(DomainPushSummary(), coordinator(l, r).pushPending(owner, "fixture")); assertTrue(r.reads.isEmpty()); assertEquals(0, l.commits)
        }
    }
    @Test fun `active source after ACK holds batch with a scoped attention code and zero child writes`() = runTest {
        val l = Local(acknowledged()); val r = Remote().apply { rows[CloudEntity.INSTALLMENT_PLAN to id] = plan }
        assertEquals(1, coordinator(l, r).pushPending(owner, "fixture").conflicts)
        assertNotNull(l.snapshot.batch); assertEquals(0, l.commits); assertTrue(r.writes.isEmpty()); assertEquals(Long.MAX_VALUE, l.snapshot.queues.single().nextAttemptAtEpochMillis)
    }
    @Test fun `confirmed absent source and child ACK without creating a remote record`() = runTest {
        val l = Local(acknowledged()); val r = Remote().apply { rows.clear() }
        assertEquals(1, coordinator(l, r).pushPending(owner, "fixture").acknowledged); assertNull(l.snapshot.batch); assertTrue(r.writes.isEmpty())
    }
    @Test fun `already deleted child keeps its authoritative payload and requires no delete retry`() = runTest {
        val server = DueOccurrenceRecord.fromCloudRecord(tombstone(cycle())).copy(syncVersion = 9).toCloudRecord()
        val l = Local(acknowledged()); val r = Remote().apply { rows[CloudEntity.DUE_OCCURRENCE_RECORD to child] = server }
        assertEquals(1, coordinator(l, r).pushPending(owner, "fixture").acknowledged); assertEquals(server, l.record(owner, server.entity, child)); assertTrue(r.writes.isEmpty())
    }
    @Test fun `later remote child edit wins its conflict without deleting the edited paid history`() = runTest {
        val server = DueOccurrenceRecord.fromCloudRecord(cycle()).copy(updatedAt = later, syncVersion = 9).toCloudRecord()
        val l = Local(acknowledged()); val r = Remote().apply { rows[CloudEntity.DUE_OCCURRENCE_RECORD to child] = server }
        assertEquals(1, coordinator(l, r).pushPending(owner, "fixture").acknowledged); assertEquals(server, l.record(owner, server.entity, child)); assertTrue(r.writes.isEmpty())
    }
    @Test fun `conditional race refetches later child winner before atomic ACK`() = runTest {
        val l = Local(acknowledged()); val r = Remote().apply { race = DueOccurrenceRecord.fromCloudRecord(cycle()).copy(updatedAt = later, syncVersion = 9).toCloudRecord() }
        assertEquals(1, coordinator(l, r).pushPending(owner, "fixture").acknowledged); assertEquals(1, r.writes.size); assertEquals(1, l.commits)
    }
    @Test fun `parent resurrection after remote child write cannot release local source pin`() = runTest {
        val l = Local(acknowledged()); val r = Remote().apply { onUpdate = { rows[CloudEntity.INSTALLMENT_PLAN to id] = plan } }
        assertEquals(1, coordinator(l, r).pushPending(owner, "fixture").conflicts); assertEquals(0, l.commits); assertNotNull(l.snapshot.batch); assertNotNull(l.snapshot.recordsByEntity.getValue(CloudEntity.INSTALLMENT_PLAN).single().deletedAt)
    }
    @Test fun `batch ABA and newer child while parent request is in flight prevent a delete request`() = runTest {
        for (aba in listOf(true, false)) {
            val l = Local(acknowledged()); val r = Remote().apply { onFetch = { e, _ -> if (e == CloudEntity.INSTALLMENT_PLAN) {
                l.snapshot = if (aba) l.snapshot.copy(batch = l.snapshot.batch!!.copy(batchId = other)) else l.snapshot.copy(queues = l.snapshot.queues.map { it.copy(attemptCount = 2) })
            } } }
            assertEquals(1, coordinator(l, r).pushPending(owner, "fixture").staleResponses); assertTrue(r.writes.isEmpty()); assertEquals(0, l.commits)
        }
    }
    @Test fun `failure response cannot assign retry to an identical queue in a new batch`() = runTest {
        val l = Local(acknowledged()); val r = Remote().apply { onFetch = { _, _ -> l.snapshot = l.snapshot.copy(batch = l.snapshot.batch!!.copy(batchId = other)); throw IOException("fixture") } }
        assertEquals(1, coordinator(l, r).pushPending(owner, "fixture").staleResponses); assertEquals(0, l.failures); assertEquals(0, l.snapshot.queues.single().attemptCount)
    }
    @Test fun `foreign source or cycle response cannot commit or write a different domain`() = runTest {
        for (entity in listOf(CloudEntity.INSTALLMENT_PLAN, CloudEntity.DUE_OCCURRENCE_RECORD)) {
            val l = Local(acknowledged()); val r = Remote(); val key = entity to if (entity == CloudEntity.INSTALLMENT_PLAN) id else child
            r.rows[key] = r.rows[key]!!.copy(ownerUserId = other)
            assertEquals(1, coordinator(l, r).pushPending(owner, "fixture").permanentFailures); assertEquals(0, l.commits); assertTrue(r.writes.isEmpty())
        }
    }
    @Test fun `snapshot CAS race preserves newer financial data and all queued deletes`() = runTest {
        val l = Local(acknowledged()); val r = Remote()
        l.beforeCommit = { l.snapshot = l.snapshot.copy(recordsByEntity = l.snapshot.recordsByEntity + (CloudEntity.LEDGER_TRANSACTION to listOf(ledger(800)))) }
        assertEquals(1, coordinator(l, r).pushPending(owner, "fixture").staleResponses); assertEquals(0, l.commits); assertNotNull(l.snapshot.batch); assertEquals(1, l.snapshot.queues.size)
    }
    @Test fun `late noncooperative response after cancellation leaves queues and batch intact`() = runTest {
        val l = Local(acknowledged()); val r = Remote(); val entered = CompletableDeferred<Unit>(); val release = CompletableDeferred<Unit>()
        r.onFetch = { _, _ -> withContext(NonCancellable) { entered.complete(Unit); release.await() } }
        val job = launch { coordinator(l, r).pushPending(owner, "fixture") }; runCurrent(); assertTrue(entered.isCompleted)
        job.cancel(); release.complete(Unit); job.join(); assertEquals(0, l.commits); assertEquals(0, l.failures); assertNotNull(l.snapshot.batch)
    }
    @Test fun `network retry preserves batch and uses sanitized retry state then completes`() = runTest {
        val l = Local(acknowledged()); val r = Remote().apply { onUpdate = { throw IOException("sensitive fixture") } }; val c = coordinator(l, r)
        assertEquals(1, c.pushPending(owner, "fixture").retryableFailures); assertEquals("network_io", l.snapshot.queues.single().lastError); assertNotNull(l.snapshot.batch)
        val beforeReads = r.reads.size; assertEquals(DomainPushSummary(), c.pushPending(owner, "fixture")); assertEquals(beforeReads, r.reads.size)
        millis += 30000; r.onUpdate = {}; assertEquals(1, c.pushPending(owner, "fixture").pushed); assertNull(l.snapshot.batch)
    }
    private fun withSecond(s: InstallmentAcknowledgementSnapshot): InstallmentAcknowledgementSnapshot {
        val before = DueOccurrenceRecord.fromCloudRecord(cycle()).copy(id = other, selectedMonthKey = "2026-02", scheduledDate = "2026-02-15T00:00:00Z").toCloudRecord()
        val row = tombstone(before); val q = queued(row)
        val member = InstallmentDeletionMember(before, q.mutation, null, true)
        return s.copy(batch = s.batch!!.copy(cycles = (s.batch!!.cycles + member).sortedBy { it.before.id }),
            recordsByEntity = s.recordsByEntity + (CloudEntity.DUE_OCCURRENCE_RECORD to (s.recordsByEntity.getValue(CloudEntity.DUE_OCCURRENCE_RECORD) + row)), queues = s.queues + q)
    }
    @Test fun `partial remote success does not ACK any local child until the whole batch completes`() = runTest {
        val l = Local(withSecond(acknowledged())); val original = l.snapshot
        val r = Remote().apply {
            rows[CloudEntity.DUE_OCCURRENCE_RECORD to other] = l.snapshot.batch!!.cycles.last().before
            onUpdate = { if (it == other) throw IOException("fixture second child") }
        }
        val c = coordinator(l, r)
        assertEquals(1, c.pushPending(owner, "fixture").retryableFailures)
        assertEquals(0, l.commits); assertEquals(2, l.snapshot.queues.size); assertEquals(original.recordsByEntity, l.snapshot.recordsByEntity); assertEquals(original.batch, l.snapshot.batch)
        assertNotNull(r.rows[CloudEntity.DUE_OCCURRENCE_RECORD to child]!!.deletedAt)
        millis += 30000; r.onUpdate = {}
        val result = c.pushPending(owner, "fixture")
        assertEquals(1, result.pushed); assertEquals(1, result.acknowledged); assertNull(l.snapshot.batch); assertTrue(l.snapshot.queues.isEmpty())
        assertEquals(original.recordsByEntity.getValue(CloudEntity.LEDGER_TRANSACTION), l.snapshot.recordsByEntity.getValue(CloudEntity.LEDGER_TRANSACTION))
    }
    @Test fun `repeated conditional races stop after two requests and hold the causal batch`() = runTest {
        val l = Local(acknowledged()); var version = 5L
        val r = Remote().apply { onUpdate = { version++; race = DueOccurrenceRecord.fromCloudRecord(cycle()).copy(syncVersion = version).toCloudRecord() } }
        assertEquals(1, coordinator(l, r).pushPending(owner, "fixture").conflicts)
        assertEquals(2, r.writes.size); assertEquals(0, l.commits); assertNotNull(l.snapshot.batch)
    }
    @Test fun `single due-domain coordinator runs installment completion even when bill writes are disabled`() = runTest {
        val l = Local(acknowledged()); val r = Remote()
        val due = DueOccurrencePushCoordinator(l, r, writesEnabled = false, installmentDeletionCoordinator = coordinator(l, r)) { millis }
        assertEquals(CloudEntity.DUE_OCCURRENCE_RECORD, due.entity)
        assertEquals(1, due.pushPending(owner, "fixture").pushed); assertEquals(1, l.commits)
    }
    @Test fun `composition holds unproven installment and ordinary installment upsert queues without IO`() = runTest {
        for (upsert in listOf(false, true)) {
            val s = acknowledged().let { it.copy(batch = null, recordsByEntity = if (upsert) it.recordsByEntity + (CloudEntity.DUE_OCCURRENCE_RECORD to listOf(cycle())) else it.recordsByEntity,
                queues = if (upsert) listOf(queued(cycle())) else it.queues) }
            val l = Local(s); val r = Remote(); val due = DueOccurrencePushCoordinator(l, r, writesEnabled = true, installmentDeletionCoordinator = coordinator(l, r)) { millis }
            assertEquals(DomainPushSummary(), due.pushPending(owner, "fixture")); assertTrue(r.reads.isEmpty()); assertTrue(r.writes.isEmpty()); assertEquals(0, l.commits)
        }
    }
    @Test fun `scoped failure persistence error propagates without a generic fallback`() = runTest {
        val l = Local(acknowledged()).apply { failPersistence = true }; val r = Remote().apply { onFetch = { _, _ -> throw IOException("fixture") } }
        assertTrue(runCatching { coordinator(l, r).pushPending(owner, "fixture") }.isFailure)
        assertEquals(0, l.snapshot.queues.single().attemptCount); assertEquals(0, l.commits)
    }

    @Test fun `lost response after applied delete retains queue then ACKs without a second delete`() = runTest {
        val l = Local(acknowledged()); val original = l.snapshot
        val r = Remote().apply { afterUpdate = { throw IOException("fixture response lost") } }; val c = coordinator(l, r)
        assertEquals(1, c.pushPending(owner, "fixture").retryableFailures)
        assertEquals(original.recordsByEntity, l.snapshot.recordsByEntity); assertNotNull(l.snapshot.batch); assertEquals(0, l.commits)
        assertNotNull(r.rows[CloudEntity.DUE_OCCURRENCE_RECORD to child]!!.deletedAt)
        millis += 30000; r.afterUpdate = { it }
        assertEquals(1, c.pushPending(owner, "fixture").acknowledged); assertEquals(1, r.writes.size); assertNull(l.snapshot.batch)
    }
    @Test fun `malformed DELETE representation cannot acknowledge batch or remove financial history`() = runTest {
        for (alter in listOf<(CloudRecord) -> CloudRecord>(
            { it.copy(id = other) }, { it.copy(ownerUserId = other) }, { it.copy(deletedAt = null) },
            { it.copy(syncVersion = 0) }, { it.copy(payload = JsonObject(it.payload + ("last_modified_by_device_id" to JsonPrimitive(other)))) },
            { it.copy(updatedAt = later, payload = JsonObject(it.payload + ("updated_at" to JsonPrimitive(later)))) })) {
            val l = Local(acknowledged()); val original = l.snapshot; val r = Remote().apply { afterUpdate = { row -> alter(row) } }
            assertEquals(1, coordinator(l, r).pushPending(owner, "fixture").permanentFailures)
            assertEquals(0, l.commits); assertEquals(original.recordsByEntity, l.snapshot.recordsByEntity); assertNotNull(l.snapshot.batch)
        }
    }
    @Test fun `cancellation after applied server delete keeps durable batch for idempotent retry`() = runTest {
        val l = Local(acknowledged()); val r = Remote(); val entered = CompletableDeferred<Unit>(); val release = CompletableDeferred<Unit>()
        r.afterUpdate = { row -> withContext(NonCancellable) { entered.complete(Unit); release.await(); row } }
        val c = coordinator(l, r); val job = launch { c.pushPending(owner, "fixture") }; runCurrent(); assertTrue(entered.isCompleted)
        job.cancel(); release.complete(Unit); job.join(); assertEquals(0, l.commits); assertEquals(0, l.failures); assertNotNull(l.snapshot.batch)
        assertEquals(1, c.pushPending(owner, "fixture").acknowledged); assertEquals(1, r.writes.size)
    }

}
