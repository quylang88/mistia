package vn.com.quyln.mistia.core.sync

import java.io.IOException
import java.time.ZoneId
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import vn.com.quyln.mistia.core.model.*
import vn.com.quyln.mistia.core.network.SupabaseHttpException

class InstallmentSkipPushCoordinatorTest {
    private val owner = UserId("11111111-1111-1111-1111-111111111111")
    private val id = "22222222-2222-2222-2222-222222222222"
    private val child = "33333333-3333-3333-3333-333333333333"
    private val device = "44444444-4444-4444-4444-444444444444"
    private val other = "99999999-9999-9999-9999-999999999999"
    private val time = "2026-10-15T00:00:00Z"
    private val earlier = "2026-10-14T00:00:00Z"
    private val later = "2026-10-16T00:00:00Z"
    private val zone = ZoneId.of("Asia/Tokyo")
    private val plan = InstallmentPlanRecord(id, owner.value, "Loan", "mistia.plan.loan", 1000, 15, 12, 1, null, "JPY", false, earlier, earlier, null, 9007199254740995, device).toCloudRecord()
    private fun cycle(deleted: Boolean = false) = DueOccurrenceRecord(child, owner.value, "installment", id, "2026-10", time, null, "skipped", null, null, earlier, time, if (deleted) time else null, 9007199254740995, device).toCloudRecord()
    private fun queue(r: CloudRecord) = QueuedMutation(DueOccurrenceRecord.fromCloudRecord(r).pendingMutation(if (r.deletedAt == null) MutationKind.UPSERT else MutationKind.DELETE), 0, 0, null)
    private fun snapshot(row: CloudRecord = cycle()) = InstallmentAcknowledgementSnapshot(owner, id, null,
        InstallmentAcknowledgementSnapshot.entities.associateWith { when (it) { CloudEntity.INSTALLMENT_PLAN -> listOf(plan); CloudEntity.DUE_OCCURRENCE_RECORD -> listOf(row); else -> emptyList() } }, listOf(queue(row)))
    private inner class Local(var state: InstallmentAcknowledgementSnapshot = snapshot()) : LocalStore {
        var commits = 0; var failures = 0; var reads = 0; var onCommit: () -> Unit = {}; var failPersistence = false
        override fun observe(entity: String, ownerUserId: UserId) = MutableStateFlow(emptyList<CloudRecord>())
        override fun observeEntityCounts(ownerUserId: UserId) = MutableStateFlow(emptyList<EntityCount>())
        override suspend fun record(ownerUserId: UserId, entity: String, recordId: String) = state.recordsByEntity.values.flatten().singleOrNull { it.entity == entity && it.id == recordId && it.ownerUserId == ownerUserId.value }
        override suspend fun commitMutation(record: CloudRecord, mutation: PendingMutation) = error("Generic write forbidden")
        override suspend fun replacePullSnapshot(ownerUserId: UserId, entity: String, records: List<CloudRecord>) = Unit
        override suspend fun clearAccount(ownerUserId: UserId) = Unit
        override suspend fun pendingMutations(ownerUserId: UserId, entity: CloudEntity, dueAtEpochMillis: Long, limit: Int): List<QueuedMutation> { reads++; return state.queues.filter { it.mutation.entity == entity && it.mutation.subjectUserId == ownerUserId.value && it.nextAttemptAtEpochMillis <= dueAtEpochMillis } }
        override suspend fun acknowledgeMutation(mutation: QueuedMutation, remoteRecord: CloudRecord): Boolean = error("Generic ACK forbidden")
        override suspend fun recordMutationFailure(mutation: QueuedMutation, nextAttemptAtEpochMillis: Long, errorCode: String): Boolean = error("Generic failure forbidden")
        override suspend fun pendingMutationRecordIds(ownerUserId: UserId, entity: String) = state.queues.filter { it.mutation.entity.table == entity && it.mutation.subjectUserId == ownerUserId.value }.map { it.mutation.recordId }.toSet()
        override suspend fun installmentAcknowledgementSnapshot(owner: UserId, planId: String) = state.also { require(owner == it.owner && planId == it.planId) }
        override suspend fun commitInstallmentSkipAcknowledgement(expected: InstallmentAcknowledgementSnapshot, queued: QueuedMutation, remotePlan: CloudRecord, remoteCycle: CloudRecord, zone: ZoneId): Boolean {
            onCommit(); if (runCatching { expected.requireUnchanged(state) }.isFailure) return false
            require(planInstallmentSkipSync(expected, queued, remotePlan, remoteCycle, zone) is InstallmentSkipSyncDecision.Acknowledge)
            state = state.copy(queues = state.queues - queued, recordsByEntity = state.recordsByEntity +
                (CloudEntity.DUE_OCCURRENCE_RECORD to state.recordsByEntity.getValue(CloudEntity.DUE_OCCURRENCE_RECORD).map { if (it.id == remoteCycle.id) remoteCycle else it }))
            commits++; return true
        }
        override suspend fun recordInstallmentSkipFailure(expected: InstallmentAcknowledgementSnapshot, queued: QueuedMutation, nextAttemptAtEpochMillis: Long, errorCode: String): Boolean {
            if (failPersistence) error("fixture storage failure")
            if (runCatching { expected.requireUnchanged(state) }.isFailure) return false
            state = state.copy(queues = state.queues.map { if (it == queued) it.copy(attemptCount = it.attemptCount + 1, nextAttemptAtEpochMillis = nextAttemptAtEpochMillis, lastError = errorCode) else it }); failures++; return true
        }
    }
    private inner class Remote : RemoteMutationStore {
        var source: CloudRecord? = plan; var occurrence: CloudRecord? = null
        var creates = 0; var updates = 0; var reads = 0; var onFetch: suspend (CloudEntity) -> Unit = {}
        var onWrite: suspend () -> Unit = {}; var createRace = false; var updateRace: CloudRecord? = null; var loseResponse = false
        var wrongResponse = false
        var siblings = emptyList<CloudRecord>()
        override suspend fun fetchInstallmentCyclePage(planId: String, month: String, accessToken: String, ownerUserId: UserId, offset: Int, limit: Int): DueOccurrencePage {
            require(planId == id && month == "2026-10" && ownerUserId == owner); reads++; onFetch(CloudEntity.DUE_OCCURRENCE_RECORD)
            val all = listOfNotNull(occurrence) + siblings
            return DueOccurrencePage(all.drop(offset).take(1), if (offset + 1 < all.size) offset + 1 else null)
        }
        override suspend fun fetchRecord(entity: CloudEntity, recordId: String, accessToken: String, ownerUserId: UserId): CloudRecord? {
            require(owner == ownerUserId && accessToken == "fixture"); reads++; onFetch(entity)
            return when (entity) { CloudEntity.INSTALLMENT_PLAN -> source; CloudEntity.DUE_OCCURRENCE_RECORD -> occurrence; else -> error("No ledger IO permitted") }
        }
        override suspend fun createRecord(entity: CloudEntity, accessToken: String, ownerUserId: UserId, payload: JsonObject): CloudRecord {
            creates++; onWrite(); val record = decoded(payload)
            occurrence = record
            if (createRace) { createRace = false; throw SupabaseHttpException(409, "fixture") }
            if (loseResponse) { loseResponse = false; throw IOException("fixture") }
            return if (wrongResponse) record.copy(id = other) else record
        }
        override suspend fun conditionalUpdate(entity: CloudEntity, recordId: String, accessToken: String, ownerUserId: UserId, expectedVersion: Long, payload: JsonObject): CloudRecord? {
            updates++; onWrite()
            updateRace?.let { occurrence = it; updateRace = null; return null }
            assertEquals(occurrence!!.syncVersion, expectedVersion)
            val record = decoded(JsonObject(occurrence!!.payload + payload)); occurrence = record
            if (loseResponse) { loseResponse = false; throw IOException("fixture") }
            return record
        }
        private fun decoded(payload: JsonObject) = DueOccurrenceRecord.fromCloudRecord(CloudRecord(CloudEntity.DUE_OCCURRENCE_RECORD.table, child, owner.value, payload, payload["updated_at"]!!.jsonPrimitive.content, payload["deleted_at"]!!.jsonPrimitive.contentOrNull, payload["sync_version"]!!.jsonPrimitive.long)).toCloudRecord()
    }
    private var millis = 1792108800000L
    private fun worker(l: Local, r: Remote, enabled: Boolean = true) = InstallmentSkipPushCoordinator(l, r, enabled, { zone }) { millis }
    @Test fun `skip create ACK keeps explicit null metadata and exact version without ledger IO`() = runTest {
        val l = Local(); val r = Remote(); assertEquals(1, worker(l, r).pushPending(owner, "fixture").pushed)
        assertTrue(l.state.queues.isEmpty()); assertEquals(1, l.commits); assertEquals(1, r.creates)
        assertEquals(9007199254740996, r.occurrence!!.syncVersion)
    }
    @Test fun `disabled gate performs no scan or remote IO`() = runTest {
        val l = Local(); val r = Remote(); assertEquals(DomainPushSummary(), worker(l, r, false).pushPending(owner, "fixture")); assertEquals(0, l.reads); assertEquals(0, r.reads)
    }
    @Test fun `existing equivalent skip ACK and create409 race do not duplicate occurrence`() = runTest {
        for (race in listOf(false, true)) {
            val l = Local(); val r = Remote().apply { if (race) createRace = true else occurrence = cycle() }
            assertEquals(1, worker(l, r).pushPending(owner, "fixture").acknowledged); assertEquals(1, l.commits); assertTrue(l.state.queues.isEmpty()); assertEquals(if (race) 1 else 0, r.creates)
        }
    }
    @Test fun `undo missing or existing skip ACK without creating anything`() = runTest {
        for (exists in listOf(false, true)) {
            val l = Local(snapshot(cycle(true))); val r = Remote().apply { if (exists) occurrence = cycle() }
            val summary = worker(l, r).pushPending(owner, "fixture")
            assertEquals(1, summary.pushed + summary.acknowledged); assertEquals(0, r.creates); assertEquals(if (exists) 1 else 0, r.updates)
            assertTrue(l.state.queues.isEmpty()); assertNotNull(l.state.recordsByEntity.getValue(CloudEntity.DUE_OCCURRENCE_RECORD).single().deletedAt)
        }
    }
    @Test fun `paid cycle conflict cannot overwrite server or acknowledge away local skip`() = runTest {
        val l = Local(); val r = Remote().apply { occurrence = DueOccurrenceRecord.fromCloudRecord(cycle()).copy(statusWireValue = "paid", amountMinorSnapshot = 1000, linkedTransactionId = other, paidAt = time).toCloudRecord() }
        assertEquals(1, worker(l, r).pushPending(owner, "fixture").conflicts); assertEquals(0, r.creates + r.updates); assertEquals(0, l.commits); assertEquals(Long.MAX_VALUE, l.state.queues.single().nextAttemptAtEpochMillis)
    }
    @Test fun `pending plan and retry not due defer without remote IO`() = runTest {
        for (retry in listOf(false, true)) {
            val s = snapshot(); val q = QueuedMutation(PendingMutation(CloudEntity.INSTALLMENT_PLAN, id, owner.value, MutationKind.UPSERT, plan.payload, earlier, plan.syncVersion, device), 0, 0, null)
            val l = Local(s.copy(queues = if (retry) s.queues.map { it.copy(nextAttemptAtEpochMillis = Long.MAX_VALUE) } else s.queues + q)); val r = Remote()
            assertEquals(DomainPushSummary(), worker(l, r).pushPending(owner, "fixture")); assertEquals(0, r.reads)
        }
    }
    @Test fun `changed server source defers and unavailable source conflicts before metadata write`() = runTest {
        val l = Local(); val r = Remote().apply { source = InstallmentPlanRecord.fromCloudRecord(plan).copy(currencyCode = "VND").toCloudRecord() }
        assertEquals(DomainPushSummary(), worker(l, r).pushPending(owner, "fixture")); assertEquals(0, l.failures)
        r.source = null; assertEquals(1, worker(l, r).pushPending(owner, "fixture").conflicts); assertEquals(0, r.creates + r.updates)
    }
    @Test fun `new local mutation during fetch and commit races retain newer queue`() = runTest {
        for (atCommit in listOf(false, true)) {
            val l = Local(); val mutate = { l.state = l.state.copy(queues = l.state.queues.map { it.copy(attemptCount = 2) }) }
            val r = Remote().apply { if (!atCommit) onFetch = { mutate() } }
            if (atCommit) l.onCommit = mutate
            assertEquals(1, worker(l, r).pushPending(owner, "fixture").staleResponses); assertEquals(0, l.commits); assertEquals(2, l.state.queues.single().attemptCount)
            if (!atCommit) assertEquals(0, r.creates + r.updates)
        }
    }
    @Test fun `IO failure backoff and lost response retry ACK are idempotent`() = runTest {
        val l = Local(); val r = Remote().apply { loseResponse = true }
        assertEquals(1, worker(l, r).pushPending(owner, "fixture").retryableFailures); assertEquals(millis + 30000, l.state.queues.single().nextAttemptAtEpochMillis)
        millis += 30000; assertEquals(1, worker(l, r).pushPending(owner, "fixture").acknowledged); assertEquals(1, r.creates); assertTrue(l.state.queues.isEmpty())
    }
    @Test fun `foreign response cannot ACK or target a different record`() = runTest {
        val l = Local(); val r = Remote().apply { wrongResponse = true }
        assertEquals(1, worker(l, r).pushPending(owner, "fixture").permanentFailures); assertEquals(0, l.commits)
    }
    @Test fun `conditional race preserves later skip winner without a second write`() = runTest {
        val l = Local(snapshot(cycle(true))); val r = Remote().apply { occurrence = cycle(); updateRace = DueOccurrenceRecord.fromCloudRecord(cycle()).copy(updatedAt = later, scheduledDate = later, syncVersion = 9007199254740996).toCloudRecord() }
        assertEquals(1, worker(l, r).pushPending(owner, "fixture").acknowledged); assertEquals(1, r.updates); assertNull(l.state.recordsByEntity.getValue(CloudEntity.DUE_OCCURRENCE_RECORD).single().deletedAt)
    }
    @Test fun `cancellation after write propagates without ACK or failure persistence`() = runTest {
        val l = Local(); val r = Remote().apply { onWrite = { throw CancellationException("fixture") } }
        assertTrue(runCatching { worker(l, r).pushPending(owner, "fixture") }.exceptionOrNull() is CancellationException); assertEquals(0, l.commits + l.failures)
    }
    @Test fun `failure persistence exception propagates without generic fallback`() = runTest {
        val l = Local().apply { failPersistence = true }; val r = Remote().apply { onFetch = { throw IOException("fixture") } }
        assertEquals("fixture storage failure", runCatching { worker(l, r).pushPending(owner, "fixture") }.exceptionOrNull()!!.message)
    }
    @Test fun `parent archive after remote write keeps local intent for explicit recovery`() = runTest {
        val l = Local(); val r = Remote().apply { onWrite = { source = InstallmentPlanRecord.fromCloudRecord(plan).copy(isArchived = true).toCloudRecord() } }
        assertEquals(1, worker(l, r).pushPending(owner, "fixture").conflicts); assertEquals(0, l.commits); assertFalse(l.state.queues.isEmpty())
    }
    @Test fun `single due coordinator invokes skip worker even with bill writes disabled`() = runTest {
        val l = Local(); val r = Remote()
        val due = DueOccurrencePushCoordinator(l, r, writesEnabled = false, installmentSkipCoordinator = worker(l, r))
        assertEquals(1, due.pushPending(owner, "fixture").pushed); assertEquals(1, r.creates)
    }
    @Test fun `paid local intents stay held before any remote request`() = runTest {
        val paid = DueOccurrenceRecord.fromCloudRecord(cycle()).copy(statusWireValue = "paid", amountMinorSnapshot = 1000, paidAt = time, linkedTransactionId = other).toCloudRecord()
        val l = Local(snapshot(paid)); val r = Remote()
        assertEquals(DomainPushSummary(), worker(l, r).pushPending(owner, "fixture")); assertEquals(0, r.reads); assertEquals(0, l.commits)
    }
    @Test fun `invalid queued actor persists an exact snapshot scoped failure without writing remotely`() = runTest {
        val l = Local(snapshot().let { it.copy(queues = it.queues.map { q -> q.copy(mutation = q.mutation.copy(deviceId = other)) }) }); val r = Remote()
        assertEquals(1, worker(l, r).pushPending(owner, "fixture").permanentFailures); assertEquals(0, r.reads); assertEquals(1, l.failures)
    }
    @Test fun `stale IO failure cannot retry an updated queue`() = runTest {
        val l = Local(); val r = Remote().apply { onFetch = { l.state = l.state.copy(queues = l.state.queues.map { it.copy(attemptCount = 7) }); throw IOException("fixture") } }
        assertEquals(1, worker(l, r).pushPending(owner, "fixture").staleResponses); assertEquals(0, l.failures); assertEquals(7, l.state.queues.single().attemptCount)
    }

    @Test fun `source deletion batch after root ACK remains exclusive to causal child worker`() = runTest {
        fun deleted(r: CloudRecord) = r.copy(updatedAt = later, deletedAt = later, payload = JsonObject(r.payload + mapOf("updated_at" to JsonPrimitive(later), "deleted_at" to JsonPrimitive(later))))
        val initial = snapshot()
        val base = InstallmentMutationSnapshot(owner, id, InstallmentMutationSnapshot.entities.associateWith { initial.recordsByEntity[it].orEmpty() })
        val writes = listOf(plan, cycle()).map(::deleted).map { r -> r to PendingMutation(CloudEntity.fromTable(r.entity)!!, r.id, owner.value, MutationKind.DELETE, r.payload, later, r.syncVersion, device) }
        val batch = InstallmentDeletionBatch.capture(base, writes, emptyList(), other)!!
        val childRow = writes.last().first
        val state = initial.copy(batch = batch, recordsByEntity = initial.recordsByEntity + (CloudEntity.INSTALLMENT_PLAN to listOf(writes.first().first)) + (CloudEntity.DUE_OCCURRENCE_RECORD to listOf(childRow)), queues = listOf(queue(childRow)))
        val l = Local(state); val r = Remote()
        assertEquals(DomainPushSummary(), worker(l, r).pushPending(owner, "fixture")); assertEquals(0, r.reads); assertEquals(0, l.commits)
    }

    @Test fun `another paid cycle on a later page holds skip and undo before writes`() = runTest {
        for (undo in listOf(false, true)) {
            val l = Local(snapshot(cycle(undo))); val r = Remote().apply {
                occurrence = cycle()
                siblings = listOf(DueOccurrenceRecord.fromCloudRecord(cycle()).copy(id = other, statusWireValue = "paid", amountMinorSnapshot = 1000, paidAt = time, linkedTransactionId = device).toCloudRecord())
            }
            assertEquals(1, worker(l, r).pushPending(owner, "fixture").conflicts); assertEquals(0, r.updates + r.creates); assertEquals(0, l.commits)
        }
    }
    @Test fun `another live unlinked skip holds new identity until duplicate reconciliation`() = runTest {
        val l = Local(); val r = Remote().apply { siblings = listOf(DueOccurrenceRecord.fromCloudRecord(cycle()).copy(id = other).toCloudRecord()) }
        assertEquals(DomainPushSummary(), worker(l, r).pushPending(owner, "fixture")); assertEquals(0, r.creates + r.updates); assertFalse(l.state.queues.isEmpty())
    }

}
