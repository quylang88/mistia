package vn.com.quyln.mistia.core.sync

import java.io.IOException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import vn.com.quyln.mistia.core.model.*

class InstallmentPaymentAcknowledgementCoordinatorTest {
    private val owner = UserId("11111111-1111-1111-1111-111111111111")
    private val id = "22222222-2222-2222-2222-222222222222"
    private val child = "33333333-3333-3333-3333-333333333333"
    private val device = "44444444-4444-4444-4444-444444444444"
    private val walletId = "55555555-5555-5555-5555-555555555555"
    private val txId = "66666666-6666-6666-6666-666666666666"
    private val other = "99999999-9999-9999-9999-999999999999"
    private val time = "2026-10-15T00:00:00Z"
    private val later = "2026-10-15T01:00:00Z"
    private val plan = InstallmentPlanRecord(id, owner.value, "Loan", "mistia.plan.loan", 9007199254740993, 15, 12, 1, walletId, "JPY", false, time, time, null, 7, device).toCloudRecord()
    private val wallet = LedgerWalletRecord.fromCloudRecord(WalletDraft(id = walletId, name = "Cash", kind = WalletKind.CASH, currencyCode = "JPY").toMutation(owner, null, device, time).record).toCloudRecord()
    private val expense = LedgerTransactionRecord.fromCloudRecord(CloudRecord(CloudEntity.LEDGER_TRANSACTION.table, txId, owner.value, buildJsonObject {
        put("id", txId); put("user_id", owner.value); put("primary_kind_raw_value", "expense"); put("entry_status_raw_value", "posted"); put("title", "Loan")
        put("amount_minor", 9007199254740993); put("source_wallet_id", walletId); put("source_currency_code", "JPY"); put("occurred_at", time)
        put("created_at", time); put("updated_at", time); put("deleted_at", JsonNull); put("is_archived", false); put("sync_version", 7); put("last_modified_by_device_id", device)
    }, time, null, 7)).toCloudRecord()
    private fun cycle() = DueOccurrenceRecord(child, owner.value, "installment", id, "2026-10", time, 9007199254740993, "paid", time, txId, time, time, null, 7, device).toCloudRecord()
    private fun queue(r: CloudRecord) = QueuedMutation(DueOccurrenceRecord.fromCloudRecord(r).pendingMutation(if (r.deletedAt == null) MutationKind.UPSERT else MutationKind.DELETE), 0, 0, null)
    private fun snapshot() = InstallmentPaymentAcknowledgementSnapshot(owner, id, null, InstallmentPaymentAcknowledgementSnapshot.entities.associateWith { when (it) {
        CloudEntity.INSTALLMENT_PLAN -> listOf(plan); CloudEntity.DUE_OCCURRENCE_RECORD -> listOf(cycle()); CloudEntity.LEDGER_TRANSACTION -> listOf(expense); CloudEntity.LEDGER_WALLET -> listOf(wallet); else -> error("Unexpected table")
    } }, listOf(queue(cycle())))
    private inner class Local(var state: InstallmentPaymentAcknowledgementSnapshot = snapshot()) : LocalStore {
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
        override suspend fun installmentPaymentAcknowledgementSnapshot(owner: UserId, planId: String) = state.also { require(owner == it.owner && planId == it.planId) }
        override suspend fun commitInstallmentPaymentAcknowledgement(expected: InstallmentPaymentAcknowledgementSnapshot, queued: QueuedMutation, remotePlan: CloudRecord, remoteCycle: CloudRecord?, remoteLedger: Map<String, CloudRecord?>, remoteWallets: Map<String, CloudRecord?>): Boolean {
            onCommit(); if (runCatching { expected.requireUnchanged(state) }.isFailure) return false
            val decision = planInstallmentPaymentAcknowledgement(expected, queued, remotePlan, remoteCycle, remoteLedger, remoteWallets) as InstallmentPaymentAcknowledgement.Acknowledge
            state = state.copy(queues = state.queues - queued, recordsByEntity = state.recordsByEntity +
                (CloudEntity.DUE_OCCURRENCE_RECORD to state.recordsByEntity.getValue(CloudEntity.DUE_OCCURRENCE_RECORD).map { if (it.id == decision.record.id) decision.record else it }))
            commits++; return true
        }
        override suspend fun recordInstallmentPaymentAcknowledgementFailure(expected: InstallmentPaymentAcknowledgementSnapshot, queued: QueuedMutation, nextAttemptAtEpochMillis: Long, errorCode: String): Boolean {
            if (failPersistence) error("fixture storage failure")
            if (runCatching { expected.requireUnchanged(state) }.isFailure) return false
            state = state.copy(queues = state.queues.map { if (it == queued) it.copy(attemptCount = it.attemptCount + 1, nextAttemptAtEpochMillis = nextAttemptAtEpochMillis, lastError = errorCode) else it }); failures++; return true
        }
    }
    private inner class Remote : RemoteMutationStore {
        val rows = mutableMapOf<Pair<CloudEntity, String>, CloudRecord?>((CloudEntity.INSTALLMENT_PLAN to id) to plan,
            (CloudEntity.DUE_OCCURRENCE_RECORD to child) to cycle(), (CloudEntity.LEDGER_TRANSACTION to txId) to expense, (CloudEntity.LEDGER_WALLET to walletId) to wallet)
        val reads = mutableListOf<Pair<CloudEntity, String>>()
        var onFetch: (CloudEntity) -> Unit = {}
        var siblings = emptyList<CloudRecord>()
        override suspend fun fetchRecord(entity: CloudEntity, recordId: String, accessToken: String, ownerUserId: UserId): CloudRecord? {
            require(ownerUserId == owner && accessToken == "fixture"); reads += entity to recordId; onFetch(entity); return rows[entity to recordId]
        }
        override suspend fun fetchInstallmentCyclePage(planId: String, month: String, accessToken: String, ownerUserId: UserId, offset: Int, limit: Int): DueOccurrencePage {
            require(planId == id && month == "2026-10" && ownerUserId == owner)
            val all = listOfNotNull(rows[CloudEntity.DUE_OCCURRENCE_RECORD to child]) + siblings
            return DueOccurrencePage(all.drop(offset).take(1), if (offset + 1 < all.size) offset + 1 else null)
        }
        override suspend fun createRecord(entity: CloudEntity, accessToken: String, ownerUserId: UserId, payload: JsonObject): CloudRecord = error("Remote creation forbidden")
        override suspend fun conditionalUpdate(entity: CloudEntity, recordId: String, accessToken: String, ownerUserId: UserId, expectedVersion: Long, payload: JsonObject): CloudRecord? = error("Remote update forbidden")
    }
    private val millis = 1792108800000L
    private fun worker(l: Local, r: Remote, enabled: Boolean = true) = InstallmentPaymentAcknowledgementCoordinator(l, r, enabled) { millis }
    @Test fun `existing coherent paid history is ACKed without any remote write`() = runTest {
        val l = Local(); val r = Remote(); val before = l.state.recordsByEntity.filterKeys { it != CloudEntity.DUE_OCCURRENCE_RECORD }
        assertEquals(1, worker(l, r).pushPending(owner, "fixture").acknowledged)
        assertTrue(l.state.queues.isEmpty()); assertEquals(1, l.commits); assertEquals(before, l.state.recordsByEntity.filterKeys { it != CloudEntity.DUE_OCCURRENCE_RECORD })
    }
    @Test fun `disabled capability does not inspect local or remote state`() = runTest {
        val l = Local(); val r = Remote(); assertEquals(DomainPushSummary(), worker(l, r, false).pushPending(owner, "fixture")); assertEquals(0, l.reads); assertTrue(r.reads.isEmpty())
    }
    @Test fun `missing remote paid record stays pending with zero remote writes`() = runTest {
        val l = Local(); val r = Remote().apply { rows[CloudEntity.DUE_OCCURRENCE_RECORD to child] = null }
        assertEquals(DomainPushSummary(), worker(l, r).pushPending(owner, "fixture")); assertFalse(l.state.queues.isEmpty()); assertEquals(0, l.failures)
    }
    @Test fun `changed wallet currency cannot ACK paid intent`() = runTest {
        val changed = LedgerWalletRecord.fromCloudRecord(wallet).copy(currencyCode = "VND").toCloudRecord()
        val l = Local(snapshot().let { it.copy(recordsByEntity = it.recordsByEntity + (CloudEntity.LEDGER_WALLET to listOf(changed))) })
        val r = Remote().apply { rows[CloudEntity.LEDGER_WALLET to walletId] = changed }
        assertEquals(1, worker(l, r).pushPending(owner, "fixture").conflicts); assertEquals(0, l.commits)
    }
    @Test fun `new queue during reads or atomic ACK keeps new local intent`() = runTest {
        for (commit in listOf(false, true)) {
            val l = Local(); val change = { l.state = l.state.copy(queues = l.state.queues.map { it.copy(attemptCount = 8) }) }
            val r = Remote().apply { if (!commit) onFetch = { change() } }; if (commit) l.onCommit = change
            assertEquals(1, worker(l, r).pushPending(owner, "fixture").staleResponses); assertEquals(0, l.commits); assertEquals(8, l.state.queues.single().attemptCount)
        }
    }
    @Test fun `foreign ledger response is rejected without an ACK`() = runTest {
        val l = Local(); val r = Remote().apply { rows[CloudEntity.LEDGER_TRANSACTION to txId] = expense.copy(ownerUserId = other) }
        assertEquals(1, worker(l, r).pushPending(owner, "fixture").permanentFailures); assertEquals(0, l.commits)
    }
    @Test fun `retryable read failure is snapshot scoped and cancellation does not write retry`() = runTest {
        val l = Local(); val r = Remote().apply { onFetch = { throw IOException("fixture") } }
        assertEquals(1, worker(l, r).pushPending(owner, "fixture").retryableFailures); assertEquals(millis + 30000, l.state.queues.single().nextAttemptAtEpochMillis)
        val l2 = Local(); val r2 = Remote().apply { onFetch = { throw CancellationException("fixture") } }
        assertTrue(runCatching { worker(l2, r2).pushPending(owner, "fixture") }.exceptionOrNull() is CancellationException); assertEquals(0, l2.failures)
    }
    @Test fun `another paid expense on a later month page requires explicit reconciliation`() = runTest {
        val l = Local(); val r = Remote().apply { siblings = listOf(DueOccurrenceRecord.fromCloudRecord(cycle()).copy(id = other, linkedTransactionId = device).toCloudRecord()) }
        assertEquals(1, worker(l, r).pushPending(owner, "fixture").conflicts); assertEquals(0, l.commits)
    }
    @Test fun `persistence exception cannot fall back to generic failure or ACK`() = runTest {
        val l = Local().apply { failPersistence = true }; val r = Remote().apply { onFetch = { throw IOException("fixture") } }
        assertEquals("fixture storage failure", runCatching { worker(l, r).pushPending(owner, "fixture") }.exceptionOrNull()!!.message)
    }
    @Test fun `composed due coordinator ACKs payment with bill delegate disabled`() = runTest {
        val l = Local(); val r = Remote()
        val due = DueOccurrencePushCoordinator(l, r, false, installmentPaymentAcknowledgementCoordinator = worker(l, r))
        assertEquals(1, due.pushPending(owner, "fixture").acknowledged); assertEquals(1, l.commits)
    }
    @Test fun `completed undo and lost ledger undo conflict never cause a remote write`() = runTest {
        for (restored in listOf(false, true)) {
            val tomb = DueOccurrenceRecord.fromCloudRecord(cycle()).copy(deletedAt = later, updatedAt = later).toCloudRecord()
            val tx = if (restored) expense else LedgerTransactionRecord.fromCloudRecord(expense).copy(deletedAt = later, updatedAt = later).toCloudRecord()
            val s = snapshot().let { it.copy(recordsByEntity = it.recordsByEntity + (CloudEntity.DUE_OCCURRENCE_RECORD to listOf(tomb)) + (CloudEntity.LEDGER_TRANSACTION to listOf(tx)), queues = listOf(queue(tomb))) }
            val l = Local(s); val r = Remote().apply { rows[CloudEntity.LEDGER_TRANSACTION to txId] = tx; if (!restored) rows[CloudEntity.DUE_OCCURRENCE_RECORD to child] = null }
            assertEquals(1, worker(l, r).pushPending(owner, "fixture").acknowledged)
            val saved = l.state.recordsByEntity.getValue(CloudEntity.DUE_OCCURRENCE_RECORD).single()
            assertEquals(!restored, saved.deletedAt != null); assertTrue(l.state.queues.isEmpty())
        }
    }

}
