package vn.com.quyln.mistia.core.sync

import java.io.IOException
import java.time.ZoneId
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import vn.com.quyln.mistia.core.model.*
import vn.com.quyln.mistia.core.network.SupabaseHttpException

/** No linked ledger/payment writes. Composed within the single due-domain worker. */
class InstallmentSkipPushCoordinator(private val localStore: LocalStore, private val remoteStore: RemoteMutationStore,
    private val writesEnabled: Boolean, private val zone: () -> ZoneId = ZoneId::systemDefault,
    private val nowEpochMillis: () -> Long = System::currentTimeMillis) : DomainPushCoordinator {
    override val entity = CloudEntity.DUE_OCCURRENCE_RECORD
    override suspend fun pushPending(ownerUserId: UserId, accessToken: String): DomainPushSummary {
        if (!writesEnabled) return DomainPushSummary()
        var result = DomainPushSummary()
        val now = nowEpochMillis()
        val pending = localStore.pendingMutations(ownerUserId, entity, now)
        for (queued in pending) {
            currentCoroutineContext().ensureActive()
            val row = localStore.record(ownerUserId, entity.table, queued.mutation.recordId) ?: continue
            val cycle = runCatching { DueOccurrenceRecord.fromCloudRecord(row) }.getOrNull() ?: continue
            if (cycle.ownerUserId != ownerUserId.value || cycle.sourceKindWireValue != "installment" || cycle.status != DueStatus.SKIPPED ||
                cycle.linkedTransactionId != null || cycle.paidAt != null || cycle.amountMinorSnapshot != null) continue
            val snapshot = localStore.installmentAcknowledgementSnapshot(ownerUserId, cycle.sourceId)
            // Causal source deletion owns all of its child intents, including skipped history.
            if (snapshot.batch != null || snapshot.queues.any { it.mutation.entity == CloudEntity.INSTALLMENT_PLAN && it.mutation.recordId == cycle.sourceId }) continue
            if (queued !in snapshot.queues) { result = result.copy(staleResponses = result.staleResponses + 1); continue }
            val outcome = try {
                requireInstallmentSkipIntent(snapshot, queued)
                pushOne(snapshot, queued, accessToken, zone())
            } catch (error: Exception) {
                currentCoroutineContext().ensureActive()
                if (error is CancellationException) throw error
                when {
                    error is SupabaseHttpException && error.statusCode in 400..499 && error.statusCode !in setOf(408, 429) -> Outcome.Failure("http_${error.statusCode}", false)
                    error is SupabaseHttpException -> Outcome.Failure("http_${error.statusCode}", true)
                    error is IOException -> Outcome.Failure("network_io", true)
                    error is IllegalArgumentException -> Outcome.Failure("invalid_mutation", false)
                    else -> Outcome.Failure("invalid_state", false)
                }
            }
            result = when (outcome) {
                Outcome.Pushed -> result.copy(pushed = result.pushed + 1)
                Outcome.Acknowledged -> result.copy(acknowledged = result.acknowledged + 1)
                Outcome.Stale -> result.copy(staleResponses = result.staleResponses + 1)
                Outcome.Deferred -> result
                is Outcome.Conflict -> if (localStore.recordInstallmentSkipFailure(snapshot, queued, Long.MAX_VALUE, "conflict_${outcome.reason}"))
                    result.copy(conflicts = result.conflicts + 1) else result.copy(staleResponses = result.staleResponses + 1)
                is Outcome.Failure -> {
                    val next = if (outcome.retryable) now + minOf(30000L * (1L shl queued.attemptCount.coerceIn(0, 10)), 6 * 60 * 60 * 1000L) else Long.MAX_VALUE
                    // Persistence errors propagate; never fall back to a generic, less-scoped retry write.
                    if (!localStore.recordInstallmentSkipFailure(snapshot, queued, next, outcome.code)) result.copy(staleResponses = result.staleResponses + 1)
                    else if (outcome.retryable) result.copy(retryableFailures = result.retryableFailures + 1)
                    else result.copy(permanentFailures = result.permanentFailures + 1)
                }
            }
        }
        return result
    }

    private suspend fun fresh(snapshot: InstallmentAcknowledgementSnapshot): Boolean {
        val current = localStore.installmentAcknowledgementSnapshot(snapshot.owner, snapshot.planId)
        currentCoroutineContext().ensureActive()
        return runCatching { snapshot.requireUnchanged(current) }.isSuccess
    }
    private suspend fun pushOne(snapshot: InstallmentAcknowledgementSnapshot, queued: QueuedMutation, token: String, zone: ZoneId): Outcome {
        suspend fun fetch(entity: CloudEntity, id: String): CloudRecord? = remoteStore.fetchRecord(entity, id, token, snapshot.owner).also { currentCoroutineContext().ensureActive() }
        repeat(3) {
            if (!fresh(snapshot)) return Outcome.Stale
            var source = fetch(CloudEntity.INSTALLMENT_PLAN, snapshot.planId)
            var allCycles = fetchCycles(snapshot, queued, token)
            installmentSkipSiblingDecision(snapshot.owner, snapshot.planId, requireInstallmentSkipIntent(snapshot, queued).second.selectedMonthKey, queued.mutation.recordId, allCycles)?.let { return it.outcome() }
            var cycle = allCycles.singleOrNull { it.id == queued.mutation.recordId }
            if (!fresh(snapshot)) return Outcome.Stale
            var decision = planInstallmentSkipSync(snapshot, queued, source, cycle, zone)
            if (decision is InstallmentSkipSyncDecision.Write) {
                // Recheck the authoritative parent after child fetch and immediately before writing.
                source = fetch(CloudEntity.INSTALLMENT_PLAN, snapshot.planId)
                if (!fresh(snapshot)) return Outcome.Stale
                decision = planInstallmentSkipSync(snapshot, queued, source, cycle, zone)
            }
            when (val selected = decision) {
                is InstallmentSkipSyncDecision.Deferred -> return Outcome.Deferred
                is InstallmentSkipSyncDecision.Conflict -> return Outcome.Conflict(selected.reason)
                is InstallmentSkipSyncDecision.Acknowledge -> {
                    // ACK also observes the latest source and the complete local dependencies.
                    source = fetch(CloudEntity.INSTALLMENT_PLAN, snapshot.planId)
                    if (!fresh(snapshot)) return Outcome.Stale
                    return acknowledge(snapshot, queued, source, selected.record, zone, false)
                }
                is InstallmentSkipSyncDecision.Write -> {
                    cycle = if (selected.expectedVersion == null) {
                        try { remoteStore.createRecord(entity, token, snapshot.owner, selected.payload) }
                        catch (error: SupabaseHttpException) { if (error.statusCode == 409) return@repeat else throw error }
                    } else remoteStore.conditionalUpdate(entity, queued.mutation.recordId, token, snapshot.owner, requireNotNull(selected.expectedVersion), selected.payload)
                    currentCoroutineContext().ensureActive()
                    if (cycle == null) return@repeat
                    // Reject malformed/misdirected write results even if the parent changed concurrently.
                    val validated = planInstallmentSkipSync(snapshot, queued, source, cycle, zone)
                    if (validated !is InstallmentSkipSyncDecision.Acknowledge) return Outcome.Conflict("unexpected_write_response")
                    allCycles = fetchCycles(snapshot, queued, token)
                    installmentSkipSiblingDecision(snapshot.owner, snapshot.planId, requireInstallmentSkipIntent(snapshot, queued).second.selectedMonthKey, queued.mutation.recordId, allCycles)?.let { return it.outcome() }
                    val current = allCycles.singleOrNull { it.id == queued.mutation.recordId }
                    if (current == null && queued.mutation.kind != MutationKind.DELETE) return Outcome.Conflict("write_result_not_visible")
                    source = fetch(CloudEntity.INSTALLMENT_PLAN, snapshot.planId)
                    if (!fresh(snapshot)) return Outcome.Stale
                    return acknowledge(snapshot, queued, source, current ?: cycle, zone, true)
                }
            }
        }
        return Outcome.Conflict("conditional_race_limit")
    }
    private suspend fun fetchCycles(snapshot: InstallmentAcknowledgementSnapshot, queued: QueuedMutation, token: String): List<CloudRecord> {
        val month = requireInstallmentSkipIntent(snapshot, queued).second.selectedMonthKey
        val rows = mutableListOf<CloudRecord>()
        var offset = 0
        repeat(1000) {
            val page = remoteStore.fetchInstallmentCyclePage(snapshot.planId, month, token, snapshot.owner, offset, 100)
            currentCoroutineContext().ensureActive()
            require(page.records.size <= 100)
            rows += page.records
            require(rows.map { it.id }.distinct().size == rows.size)
            val next = page.nextOffset ?: return rows
            require(page.records.isNotEmpty() && next == offset + page.records.size && next > offset)
            offset = next
        }
        error("Installment cycle pagination limit exceeded")
    }
    private fun InstallmentSkipSyncDecision.outcome(): Outcome = when (this) {
        is InstallmentSkipSyncDecision.Conflict -> Outcome.Conflict(reason)
        is InstallmentSkipSyncDecision.Deferred -> Outcome.Deferred
        else -> error("Sibling validation cannot produce a write or ACK")
    }
    private suspend fun acknowledge(snapshot: InstallmentAcknowledgementSnapshot, queued: QueuedMutation, source: CloudRecord?,
        cycle: CloudRecord, zone: ZoneId, wrote: Boolean): Outcome = when (val decision = planInstallmentSkipSync(snapshot, queued, source, cycle, zone)) {
        is InstallmentSkipSyncDecision.Acknowledge -> {
            currentCoroutineContext().ensureActive()
            if (!localStore.commitInstallmentSkipAcknowledgement(snapshot, queued, requireNotNull(source), decision.record, zone)) Outcome.Stale
            else if (wrote) Outcome.Pushed else Outcome.Acknowledged
        }
        is InstallmentSkipSyncDecision.Conflict -> Outcome.Conflict(decision.reason)
        is InstallmentSkipSyncDecision.Deferred -> Outcome.Deferred
        is InstallmentSkipSyncDecision.Write -> Outcome.Conflict("acknowledgement_not_authoritative")
    }
    private sealed interface Outcome {
        data object Pushed : Outcome
        data object Acknowledged : Outcome
        data object Deferred : Outcome
        data object Stale : Outcome
        data class Conflict(val reason: String) : Outcome
        data class Failure(val code: String, val retryable: Boolean) : Outcome
    }
}
