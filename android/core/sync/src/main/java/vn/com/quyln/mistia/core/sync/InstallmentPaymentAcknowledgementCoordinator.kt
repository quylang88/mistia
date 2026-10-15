package vn.com.quyln.mistia.core.sync

import java.io.IOException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import vn.com.quyln.mistia.core.model.*
import vn.com.quyln.mistia.core.network.SupabaseHttpException

/** Reads and atomically ACKs existing financial history; never invokes a remote mutation. */
class InstallmentPaymentAcknowledgementCoordinator(private val localStore: LocalStore, private val remoteStore: RemoteMutationStore,
    private val enabled: Boolean, private val nowEpochMillis: () -> Long = System::currentTimeMillis) : DomainPushCoordinator {
    override val entity = CloudEntity.DUE_OCCURRENCE_RECORD
    override suspend fun pushPending(ownerUserId: UserId, accessToken: String): DomainPushSummary {
        if (!enabled) return DomainPushSummary()
        var summary = DomainPushSummary()
        val now = nowEpochMillis()
        for (queued in localStore.pendingMutations(ownerUserId, entity, now)) {
            currentCoroutineContext().ensureActive()
            val row = localStore.record(ownerUserId, entity.table, queued.mutation.recordId) ?: continue
            val due = runCatching { DueOccurrenceRecord.fromCloudRecord(row) }.getOrNull() ?: continue
            if (due.ownerUserId != ownerUserId.value || due.sourceKindWireValue != "installment" || due.statusWireValue != "paid") continue
            val snapshot = localStore.installmentPaymentAcknowledgementSnapshot(ownerUserId, due.sourceId)
            if (snapshot.batch != null) continue
            if (queued !in snapshot.queues) { summary = summary.copy(staleResponses = summary.staleResponses + 1); continue }
            val result = try {
                requireInstallmentPaymentAcknowledgementIntent(snapshot, queued)
                val sourcePending = snapshot.queues.any { it.mutation.entity == CloudEntity.INSTALLMENT_PLAN && it.mutation.recordId == snapshot.planId }
                val ledgerPending = due.linkedTransactionId?.let { link -> snapshot.queues.any { it.mutation.entity == CloudEntity.LEDGER_TRANSACTION && it.mutation.recordId == link } } == true
                if (sourcePending || ledgerPending) Outcome.Deferred else acknowledge(snapshot, queued, accessToken)
            } catch (error: Exception) {
                currentCoroutineContext().ensureActive()
                if (error is CancellationException) throw error
                val retryable = if (error is SupabaseHttpException) error.statusCode >= 500 || error.statusCode in setOf(408, 429) else error is IOException
                val code = when (error) { is SupabaseHttpException -> "http_${error.statusCode}"; is IOException -> "network_io"; is IllegalArgumentException -> "invalid_mutation"; else -> "invalid_state" }
                Outcome.Failure(code, retryable)
            }
            summary = when (result) {
                Outcome.Acknowledged -> summary.copy(acknowledged = summary.acknowledged + 1)
                Outcome.Stale -> summary.copy(staleResponses = summary.staleResponses + 1)
                Outcome.Deferred -> summary
                is Outcome.Conflict -> if (localStore.recordInstallmentPaymentAcknowledgementFailure(snapshot, queued, Long.MAX_VALUE, "conflict_${result.reason}"))
                    summary.copy(conflicts = summary.conflicts + 1) else summary.copy(staleResponses = summary.staleResponses + 1)
                is Outcome.Failure -> {
                    val next = if (result.retryable) now + minOf(30000L * (1L shl queued.attemptCount.coerceIn(0, 10)), 6 * 60 * 60 * 1000L) else Long.MAX_VALUE
                    if (!localStore.recordInstallmentPaymentAcknowledgementFailure(snapshot, queued, next, result.code)) summary.copy(staleResponses = summary.staleResponses + 1)
                    else if (result.retryable) summary.copy(retryableFailures = summary.retryableFailures + 1)
                    else summary.copy(permanentFailures = summary.permanentFailures + 1)
                }
            }
        }
        return summary
    }
    private suspend fun fresh(expected: InstallmentPaymentAcknowledgementSnapshot): Boolean {
        val current = localStore.installmentPaymentAcknowledgementSnapshot(expected.owner, expected.planId)
        currentCoroutineContext().ensureActive()
        return runCatching { expected.requireUnchanged(current) }.isSuccess
    }
    private suspend fun acknowledge(snapshot: InstallmentPaymentAcknowledgementSnapshot, queued: QueuedMutation, token: String): Outcome {
        val local = requireInstallmentPaymentAcknowledgementIntent(snapshot, queued).second
        suspend fun fetch(entity: CloudEntity, id: String) = remoteStore.fetchRecord(entity, id, token, snapshot.owner).also { currentCoroutineContext().ensureActive() }
        var source = fetch(CloudEntity.INSTALLMENT_PLAN, snapshot.planId)
        var cycles = fetchCycles(snapshot.owner, snapshot.planId, local.selectedMonthKey, token)
        if (!fresh(snapshot)) return Outcome.Stale
        installmentPaymentSiblingDecision(snapshot.owner, snapshot.planId, local, cycles)?.let { return it.outcome() }
        var target = cycles.singleOrNull { it.id == local.id }
        val ledger = mutableMapOf<String, CloudRecord?>()
        val wallets = mutableMapOf<String, CloudRecord?>()
        var decision = planInstallmentPaymentAcknowledgement(snapshot, queued, source, target, ledger, wallets)
        while (decision is InstallmentPaymentAcknowledgement.NeedLedger || decision is InstallmentPaymentAcknowledgement.NeedWallet) {
            when (val needed = decision) {
                is InstallmentPaymentAcknowledgement.NeedLedger -> ledger[needed.id] = fetch(CloudEntity.LEDGER_TRANSACTION, needed.id)
                is InstallmentPaymentAcknowledgement.NeedWallet -> wallets[needed.id] = fetch(CloudEntity.LEDGER_WALLET, needed.id)
                else -> error("Read request expected")
            }
            if (!fresh(snapshot)) return Outcome.Stale
            decision = planInstallmentPaymentAcknowledgement(snapshot, queued, source, target, ledger, wallets)
        }
        if (decision !is InstallmentPaymentAcknowledgement.Acknowledge) return decision.outcome()
        // Reobserve dependencies and complete month membership before committing the local ACK.
        ledger.keys.toList().forEach { ledger[it] = fetch(CloudEntity.LEDGER_TRANSACTION, it) }
        wallets.keys.toList().forEach { wallets[it] = fetch(CloudEntity.LEDGER_WALLET, it) }
        source = fetch(CloudEntity.INSTALLMENT_PLAN, snapshot.planId)
        cycles = fetchCycles(snapshot.owner, snapshot.planId, local.selectedMonthKey, token)
        installmentPaymentSiblingDecision(snapshot.owner, snapshot.planId, local, cycles)?.let { return it.outcome() }
        target = cycles.singleOrNull { it.id == local.id }
        if (!fresh(snapshot)) return Outcome.Stale
        decision = planInstallmentPaymentAcknowledgement(snapshot, queued, source, target, ledger, wallets)
        if (decision !is InstallmentPaymentAcknowledgement.Acknowledge) return decision.outcome()
        currentCoroutineContext().ensureActive()
        return if (localStore.commitInstallmentPaymentAcknowledgement(snapshot, queued, requireNotNull(source), target, ledger, wallets)) Outcome.Acknowledged else Outcome.Stale
    }
    private suspend fun fetchCycles(owner: UserId, source: String, month: String, token: String): List<CloudRecord> {
        val records = mutableListOf<CloudRecord>(); var offset = 0
        repeat(1000) {
            val page = remoteStore.fetchInstallmentCyclePage(source, month, token, owner, offset, 100)
            currentCoroutineContext().ensureActive()
            require(page.records.size <= 100); records += page.records
            require(records.map { it.id }.distinct().size == records.size)
            val next = page.nextOffset ?: return records
            require(page.records.isNotEmpty() && next > offset && next == offset + page.records.size)
            offset = next
        }
        error("Installment payment cycle page limit exceeded")
    }
    private fun InstallmentPaymentAcknowledgement.outcome(): Outcome = when (this) {
        is InstallmentPaymentAcknowledgement.Deferred -> Outcome.Deferred
        is InstallmentPaymentAcknowledgement.Conflict -> Outcome.Conflict(reason)
        // A final dependency changed shape; retry only after normal pull refreshes it.
        is InstallmentPaymentAcknowledgement.NeedLedger, is InstallmentPaymentAcknowledgement.NeedWallet -> Outcome.Deferred
        is InstallmentPaymentAcknowledgement.Acknowledge -> error("Atomic acknowledgement required")
    }
    private sealed interface Outcome {
        data object Acknowledged : Outcome
        data object Deferred : Outcome
        data object Stale : Outcome
        data class Conflict(val reason: String) : Outcome
        data class Failure(val code: String, val retryable: Boolean) : Outcome
    }
}
