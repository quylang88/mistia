package vn.com.quyln.mistia.core.model

import java.time.Instant
import kotlinx.serialization.json.*

sealed interface InstallmentDeletionCompletion {
    data class Deferred(val reason: String) : InstallmentDeletionCompletion
    data class Conflict(val reason: String) : InstallmentDeletionCompletion
    data class NeedCycles(val ids: Set<String>) : InstallmentDeletionCompletion
    data class NeedDeletes(val mutations: List<PendingMutation>) : InstallmentDeletionCompletion
    data class Ready(val source: CloudRecord, val cycles: List<CloudRecord>) : InstallmentDeletionCompletion
}

/** Financial rows are read only; all child ACKs and batch cleanup commit together. */
fun planInstallmentDeletionCompletion(snapshot: InstallmentAcknowledgementSnapshot, remoteSource: CloudRecord?,
    remoteCycles: Map<String, CloudRecord?>, nowEpochMillis: Long): InstallmentDeletionCompletion {
    require(nowEpochMillis >= 0)
    val owner = snapshot.owner
    require(snapshot.recordsByEntity.keys == InstallmentAcknowledgementSnapshot.entities)
    snapshot.recordsByEntity.forEach { (entity, rows) ->
        require(rows.all { it.entity == entity.table && it.ownerUserId == owner.value } && rows.map { it.id }.distinct().size == rows.size)
    }
    require(snapshot.queues.all { it.mutation.entity in InstallmentAcknowledgementSnapshot.entities && it.mutation.subjectUserId == owner.value })
    require(snapshot.queues.map { it.mutation.entity to it.mutation.recordId }.distinct().size == snapshot.queues.size)
    val batch = snapshot.batch ?: return InstallmentDeletionCompletion.Deferred("unproven_deletion_batch")
    batch.requireValid(); require(batch.owner == owner && batch.planId == snapshot.planId)
    if (snapshot.queues.any { it.mutation.entity == CloudEntity.INSTALLMENT_PLAN && it.mutation.recordId == snapshot.planId })
        return InstallmentDeletionCompletion.Deferred("source_mutation_pending")
    val localSource = snapshot.recordsByEntity.getValue(CloudEntity.INSTALLMENT_PLAN).singleOrNull { it.id == snapshot.planId }
        ?: return InstallmentDeletionCompletion.Conflict("missing_source_record")
    if (ackPlan(localSource, owner, snapshot.planId).deletedAt == null) return InstallmentDeletionCompletion.Deferred("local_source_active")
    if (remoteSource != null && ackPlan(remoteSource, owner, snapshot.planId).deletedAt == null)
        return InstallmentDeletionCompletion.Conflict("source_active_after_delete_ack")
    val eligible = mutableListOf<Pair<CloudRecord, QueuedMutation>>()
    for (member in batch.cycles) {
        val current = snapshot.recordsByEntity.getValue(CloudEntity.DUE_OCCURRENCE_RECORD).singleOrNull { it.id == member.before.id }
        val queued = snapshot.queues.singleOrNull { it.mutation.entity == CloudEntity.DUE_OCCURRENCE_RECORD && it.mutation.recordId == member.before.id }
        current?.let { ackCycle(it, owner, snapshot.planId, DueOccurrenceRecord.fromCloudRecord(member.before).selectedMonthKey, member.before.id) }
        if (queued != null && current != null) {
            val q = queued.mutation
            require(q.payload == current.payload && q.baseVersion == current.syncVersion && q.modifiedAt == current.updatedAt)
            require(q.deviceId == DueOccurrenceRecord.fromCloudRecord(current).lastModifiedByDeviceId)
            require((q.kind == MutationKind.DELETE) == (current.deletedAt != null))
            require(queued.attemptCount >= 0 && queued.nextAttemptAtEpochMillis >= 0)
        }
        if (queued?.mutation == member.deletion) {
            if (current == null) return InstallmentDeletionCompletion.Conflict("missing_causal_child_record")
            if (queued.nextAttemptAtEpochMillis > nowEpochMillis) return InstallmentDeletionCompletion.Deferred("child_retry_not_due")
            eligible += current to queued
        } else if (queued == null && (current == null || current.payload == member.deletion.payload))
            return InstallmentDeletionCompletion.Conflict("missing_causal_child_queue")
    }
    val ids = eligible.mapTo(mutableSetOf()) { it.first.id }
    require(remoteCycles.keys.all { it in ids })
    if (!remoteCycles.keys.containsAll(ids)) return InstallmentDeletionCompletion.NeedCycles(ids - remoteCycles.keys)
    val deletes = mutableListOf<PendingMutation>(); val acknowledgements = mutableListOf<CloudRecord>()
    for ((local, queued) in eligible) {
        val remote = remoteCycles[local.id]
        remote?.let { ackCycle(it, owner, snapshot.planId, DueOccurrenceRecord.fromCloudRecord(local).selectedMonthKey, local.id) }
        if (remote == null || remote.deletedAt != null) { acknowledgements += remote ?: local; continue }
        val decision = if (remote.syncVersion == queued.mutation.baseVersion) RecordConflictWinner.LOCAL
            else RecordConflictResolver.resolve(canonicalAckCycle(local), canonicalAckCycle(remote)).winner
        when (decision) {
            RecordConflictWinner.REMOTE -> acknowledgements += remote
            RecordConflictWinner.UNRESOLVED -> return InstallmentDeletionCompletion.Conflict("child_delete_unresolved")
            RecordConflictWinner.LOCAL -> {
                val base = remote.syncVersion
                val highest = maxOf(base, local.syncVersion)
                require(highest >= 0 && highest < Long.MAX_VALUE) { "Sync version cannot be incremented" }
                val q = queued.mutation
                val patch = buildJsonObject {
                    put("id", local.id); put("user_id", owner.value); put("source_kind_raw_value", "installment")
                    put("updated_at", q.modifiedAt); put("deleted_at", requireNotNull(local.deletedAt))
                    put("sync_version", highest + 1); put("last_modified_by_device_id", q.deviceId)
                }
                Instant.parse(q.modifiedAt); Instant.parse(requireNotNull(local.deletedAt))
                deletes += q.copy(payload = patch, baseVersion = base)
            }
        }
    }
    return if (deletes.isNotEmpty()) InstallmentDeletionCompletion.NeedDeletes(deletes)
        else InstallmentDeletionCompletion.Ready(remoteSource ?: localSource, acknowledgements)
}
