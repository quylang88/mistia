package vn.com.quyln.mistia.core.sync

import java.io.IOException
import java.time.Duration
import java.time.Instant
import kotlin.math.min
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.serialization.json.*
import vn.com.quyln.mistia.core.model.*
import vn.com.quyln.mistia.core.network.SupabaseHttpException

/** Composed inside the due-domain coordinator; only proven source-delete batches are writable. */
class InstallmentDeletionPushCoordinator(private val localStore: LocalStore, private val remoteStore: RemoteMutationStore,
    private val writesEnabled: Boolean, private val nowEpochMillis: () -> Long = System::currentTimeMillis) {
    suspend fun pushPending(owner: UserId, token: String): DomainPushSummary {
        if (!writesEnabled) return DomainPushSummary()
        var summary = DomainPushSummary()
        val now = nowEpochMillis()
        for (planId in localStore.installmentDeletionPlanIds(owner).sorted()) {
            currentCoroutineContext().ensureActive()
            var snapshot: InstallmentAcknowledgementSnapshot? = null
            try {
                snapshot = localStore.installmentAcknowledgementSnapshot(owner, planId)
                summary += pushBatch(snapshot, token, now)
            } catch (error: Exception) {
                currentCoroutineContext().ensureActive()
                if (error is CancellationException) throw error
                val expected = snapshot
                val batch = expected?.batch
                val anchor = if (expected != null && batch != null) batch.cycles.firstNotNullOfOrNull { member -> expected.queues.singleOrNull {
                    it.mutation.entity == CloudEntity.DUE_OCCURRENCE_RECORD && it.mutation.recordId == member.before.id && it.mutation == member.deletion
                } } else null
                val retryable = error !is CompletionConflict && when (error) {
                    is SupabaseHttpException -> error.statusCode >= 500 || error.statusCode in setOf(408, 429)
                    is IOException -> true
                    else -> false
                }
                val code = when (error) {
                    is CompletionConflict -> "conflict_${error.reason}"
                    is SupabaseHttpException -> "http_${error.statusCode}"
                    is IOException -> "network_io"
                    is IllegalArgumentException -> "invalid_mutation"
                    else -> "invalid_state"
                }
                val delay = min(30_000L * (1L shl min(anchor?.attemptCount?.coerceAtLeast(0) ?: 0, 10)), 6L * 60 * 60 * 1000)
                val next = if (retryable) Math.addExact(now, delay) else Long.MAX_VALUE
                // Persistence errors propagate. There is no generic ACK/failure fallback.
                val stored = if (expected != null && batch != null && anchor != null)
                    localStore.recordInstallmentDeletionFailure(expected, batch.batchId, anchor, next, code) else true
                summary += when {
                    !stored -> DomainPushSummary(staleResponses = 1)
                    error is CompletionConflict -> DomainPushSummary(conflicts = 1)
                    retryable -> DomainPushSummary(retryableFailures = 1)
                    else -> DomainPushSummary(permanentFailures = 1)
                }
            }
        }
        return summary
    }

    private suspend fun pushBatch(snapshot: InstallmentAcknowledgementSnapshot, token: String, now: Long): DomainPushSummary {
        val batch = snapshot.batch ?: return DomainPushSummary(staleResponses = 1)
        val localSource = snapshot.recordsByEntity.getValue(CloudEntity.INSTALLMENT_PLAN).singleOrNull { it.id == snapshot.planId }
        val initial = planInstallmentDeletionCompletion(snapshot, localSource, emptyMap(), now)
        if (initial is InstallmentDeletionCompletion.Deferred) return DomainPushSummary()
        if (initial is InstallmentDeletionCompletion.Conflict) throw CompletionConflict(initial.reason)
        val cycles = mutableMapOf<String, CloudRecord?>()
        val written = mutableSetOf<String>()
        val attempts = mutableMapOf<String, Int>()
        var source = fetch(CloudEntity.INSTALLMENT_PLAN, snapshot.planId, snapshot.owner, token)
        if (!unchanged(snapshot)) return DomainPushSummary(staleResponses = 1)
        var decision = planInstallmentDeletionCompletion(snapshot, source, cycles, now)
        while (true) {
            when (decision) {
                is InstallmentDeletionCompletion.Deferred -> return DomainPushSummary()
                is InstallmentDeletionCompletion.Conflict -> throw CompletionConflict(decision.reason)
                is InstallmentDeletionCompletion.NeedCycles -> decision.ids.sorted().forEach { id ->
                    cycles[id] = fetch(CloudEntity.DUE_OCCURRENCE_RECORD, id, snapshot.owner, token)
                }
                is InstallmentDeletionCompletion.NeedDeletes -> {
                    for (mutation in decision.mutations) {
                        currentCoroutineContext().ensureActive()
                        if (!unchanged(snapshot)) return DomainPushSummary(staleResponses = 1)
                        val count = attempts.getOrDefault(mutation.recordId, 0)
                        if (count >= 2) throw CompletionConflict("conditional_child_delete_race")
                        attempts[mutation.recordId] = count + 1
                        val patch = requireNotNull(mutation.payload)
                        val updated = remoteStore.conditionalUpdate(CloudEntity.DUE_OCCURRENCE_RECORD, mutation.recordId, token, snapshot.owner,
                            mutation.baseVersion, patch)
                        currentCoroutineContext().ensureActive()
                        if (updated == null) cycles[mutation.recordId] = fetch(CloudEntity.DUE_OCCURRENCE_RECORD, mutation.recordId, snapshot.owner, token)
                        else {
                            requireDeleteResponse(updated, mutation)
                            cycles[mutation.recordId] = updated
                            written += mutation.recordId
                        }
                    }
                }
                is InstallmentDeletionCompletion.Ready -> {
                    // Parent checks surround the child requests. Remote writes remain individual CAS operations.
                    source = fetch(CloudEntity.INSTALLMENT_PLAN, snapshot.planId, snapshot.owner, token)
                    val final = planInstallmentDeletionCompletion(snapshot, source, cycles, now)
                    if (final is InstallmentDeletionCompletion.Conflict) throw CompletionConflict(final.reason)
                    require(final is InstallmentDeletionCompletion.Ready)
                    currentCoroutineContext().ensureActive()
                    if (!localStore.commitInstallmentDeletionCompletion(snapshot, batch.batchId, source, cycles, now))
                        return DomainPushSummary(staleResponses = 1)
                    return DomainPushSummary(pushed = written.size, acknowledged = final.cycles.size - written.size,
                        reconciled = if (final.cycles.isEmpty()) 1 else 0)
                }
            }
            decision = planInstallmentDeletionCompletion(snapshot, source, cycles, now)
        }
    }

    private suspend fun fetch(entity: CloudEntity, id: String, owner: UserId, token: String): CloudRecord? {
        currentCoroutineContext().ensureActive()
        val result = remoteStore.fetchRecord(entity, id, token, owner)
        currentCoroutineContext().ensureActive()
        return result
    }
    private suspend fun unchanged(expected: InstallmentAcknowledgementSnapshot): Boolean {
        val current = localStore.installmentAcknowledgementSnapshot(expected.owner, expected.planId)
        return runCatching { expected.requireUnchanged(current) }.isSuccess
    }
    private fun requireDeleteResponse(row: CloudRecord, mutation: PendingMutation) {
        val patch = requireNotNull(mutation.payload)
        require(row.entity == mutation.entity.table && row.id == mutation.recordId && row.ownerUserId == mutation.subjectUserId)
        require(row.syncVersion == patch.getValue("sync_version").jsonPrimitive.long && row.deletedAt != null)
        require(row.payload["last_modified_by_device_id"]?.jsonPrimitive?.content == mutation.deviceId)
        for (key in listOf("updated_at", "deleted_at")) {
            val actual = requireNotNull(row.payload[key]?.jsonPrimitive?.contentOrNull)
            val requested = patch.getValue(key).jsonPrimitive.content
            require(Duration.between(Instant.parse(actual), Instant.parse(requested)).abs() < Duration.ofNanos(1000))
        }
    }
}

private class CompletionConflict(val reason: String) : Exception()
internal operator fun DomainPushSummary.plus(other: DomainPushSummary) = DomainPushSummary(
    pushed + other.pushed, acknowledged + other.acknowledged, conflicts + other.conflicts,
    retryableFailures + other.retryableFailures, permanentFailures + other.permanentFailures,
    staleResponses + other.staleResponses, reconciled + other.reconciled)
