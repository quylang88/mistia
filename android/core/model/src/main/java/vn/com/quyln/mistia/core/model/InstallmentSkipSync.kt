package vn.com.quyln.mistia.core.model

import java.time.ZoneId
import java.time.YearMonth
import java.time.Instant
import java.time.Duration
import java.util.UUID
import kotlinx.serialization.json.*

sealed interface InstallmentSkipSyncDecision {
    data class Write(val payload: JsonObject, val expectedVersion: Long?) : InstallmentSkipSyncDecision
    data class Acknowledge(val record: CloudRecord) : InstallmentSkipSyncDecision
    data class Deferred(val reason: String) : InstallmentSkipSyncDecision
    data class Conflict(val reason: String) : InstallmentSkipSyncDecision
}

/** Only unlinked skip metadata. Paid cycles and source-deletion batches use dedicated workflows. */
fun planInstallmentSkipSync(snapshot: InstallmentAcknowledgementSnapshot, queued: QueuedMutation,
    remotePlan: CloudRecord?, remoteCycle: CloudRecord?, zone: ZoneId): InstallmentSkipSyncDecision {
    val (plan, local) = requireInstallmentSkipIntent(snapshot, queued)
    if (snapshot.batch != null) return InstallmentSkipSyncDecision.Deferred("source_deletion_batch")
    val localCycles = snapshot.recordsByEntity.getValue(CloudEntity.DUE_OCCURRENCE_RECORD).map { it to DueOccurrenceRecord.fromCloudRecord(it) }
        .filter { (_, c) -> c.sourceKindWireValue == "installment" && c.sourceId == snapshot.planId && c.selectedMonthKey == local.selectedMonthKey }.map { it.first }
    installmentSkipSiblingDecision(snapshot.owner, snapshot.planId, local.selectedMonthKey, local.id, localCycles)?.let { return it }
    if (snapshot.queues.any { it.mutation.entity == CloudEntity.INSTALLMENT_PLAN && it.mutation.recordId == snapshot.planId })
        return InstallmentSkipSyncDecision.Deferred("source_pending")
    if (plan.deletedAt != null || plan.isArchived || remotePlan == null) return InstallmentSkipSyncDecision.Conflict("source_unavailable")
    val serverPlan = ackPlan(remotePlan, snapshot.owner, snapshot.planId)
    if (serverPlan.deletedAt != null || serverPlan.isArchived) return InstallmentSkipSyncDecision.Conflict("source_unavailable")
    val normalized = plan.copy(createdAt = serverPlan.createdAt, updatedAt = serverPlan.updatedAt,
        syncVersion = serverPlan.syncVersion, lastModifiedByDeviceId = serverPlan.lastModifiedByDeviceId)
    if (normalized != serverPlan || Duration.between(Instant.parse(plan.createdAt), Instant.parse(serverPlan.createdAt)).abs() >= Duration.ofNanos(1000))
        return InstallmentSkipSyncDecision.Deferred("source_not_pulled")
    val month = YearMonth.parse(local.selectedMonthKey)
    if (installmentDueRows(snapshot.owner, listOf(serverPlan), emptyList(), month, zone).isEmpty())
        return InstallmentSkipSyncDecision.Conflict("not_scheduled")
    val record = snapshot.recordsByEntity.getValue(CloudEntity.DUE_OCCURRENCE_RECORD).single { it.id == local.id }
    val remote = remoteCycle?.let { ackCycle(it, snapshot.owner, snapshot.planId, local.selectedMonthKey, local.id) }
    if (remote != null && (!remote.metadataOnly() || remote.status !in setOf(DueStatus.PENDING, DueStatus.SKIPPED)))
        return InstallmentSkipSyncDecision.Conflict("financial_cycle_requires_reconciliation")
    val deleting = queued.mutation.kind == MutationKind.DELETE
    if (deleting && remote?.status == DueStatus.PENDING)
        return InstallmentSkipSyncDecision.Acknowledge(requireNotNull(remoteCycle))
    if (deleting && remote == null) return InstallmentSkipSyncDecision.Acknowledge(record)
    if (remote?.deletedAt != null && deleting) return InstallmentSkipSyncDecision.Acknowledge(requireNotNull(remoteCycle))
    if (remoteCycle != null) {
        val left = canonicalAckCycle(record); val right = canonicalAckCycle(remoteCycle)
        if (left.deletedAt == right.deletedAt && RecordConflictResolver.semanticFingerprint(left.payload) == RecordConflictResolver.semanticFingerprint(right.payload))
            return InstallmentSkipSyncDecision.Acknowledge(remoteCycle)
        if (!(queued.mutation.baseVersion > 0 && remoteCycle.syncVersion == queued.mutation.baseVersion && remoteCycle.deletedAt == null)) {
            when (RecordConflictResolver.resolve(left, right).winner) {
                RecordConflictWinner.REMOTE -> return InstallmentSkipSyncDecision.Acknowledge(remoteCycle)
                RecordConflictWinner.UNRESOLVED -> return InstallmentSkipSyncDecision.Conflict("same_clock_version_different_payload")
                RecordConflictWinner.LOCAL -> Unit
            }
        }
    }
    val base = maxOf(local.syncVersion, queued.mutation.baseVersion, remoteCycle?.syncVersion ?: 0)
    require(base in 0 until Long.MAX_VALUE)
    val payload = if (deleting) buildJsonObject {
        put("id", local.id); put("user_id", snapshot.owner.value); put("source_kind_raw_value", "installment")
        put("status_raw_value", "skipped"); put("amount_minor_snapshot", JsonNull); put("paid_at", JsonNull); put("linked_transaction_id", JsonNull)
        put("updated_at", local.updatedAt); put("deleted_at", requireNotNull(local.deletedAt)); put("sync_version", base + 1)
        put("last_modified_by_device_id", queued.mutation.deviceId)
    } else JsonObject(record.payload + mapOf("sync_version" to JsonPrimitive(base + 1), "last_modified_by_device_id" to JsonPrimitive(queued.mutation.deviceId)))
    return InstallmentSkipSyncDecision.Write(payload, remoteCycle?.syncVersion)
}

/** Shared by the worker, atomic ACK and scoped failure persistence. */
fun requireInstallmentSkipIntent(snapshot: InstallmentAcknowledgementSnapshot, queued: QueuedMutation): Pair<InstallmentPlanRecord, DueOccurrenceRecord> {
    require(UUID.fromString(snapshot.owner.value).toString() == snapshot.owner.value && UUID.fromString(snapshot.planId).toString() == snapshot.planId)
    require(snapshot.recordsByEntity.keys == InstallmentAcknowledgementSnapshot.entities)
    snapshot.recordsByEntity.forEach { (entity, rows) -> require(rows.all { it.entity == entity.table && it.ownerUserId == snapshot.owner.value } && rows.map { it.id }.distinct().size == rows.size) }
    require(snapshot.queues.all { it.mutation.entity in InstallmentAcknowledgementSnapshot.entities && it.mutation.subjectUserId == snapshot.owner.value })
    require(snapshot.queues.map { it.mutation.entity to it.mutation.recordId }.distinct().size == snapshot.queues.size)
    require(queued in snapshot.queues)
    val q = queued.mutation
    require(q.entity == CloudEntity.DUE_OCCURRENCE_RECORD && q.subjectUserId == snapshot.owner.value)
    val row = snapshot.recordsByEntity.getValue(CloudEntity.DUE_OCCURRENCE_RECORD).single { it.id == q.recordId }
    val typed = DueOccurrenceRecord.fromCloudRecord(row)
    val cycle = ackCycle(row, snapshot.owner, snapshot.planId, typed.selectedMonthKey, q.recordId)
    require(YearMonth.parse(cycle.selectedMonthKey).toString() == cycle.selectedMonthKey)
    require(cycle.status == DueStatus.SKIPPED && cycle.metadataOnly())
    require(q.kind == if (cycle.deletedAt == null) MutationKind.UPSERT else MutationKind.DELETE)
    require(row.payload == q.payload && row.syncVersion == q.baseVersion && row.updatedAt == q.modifiedAt)
    require(UUID.fromString(q.deviceId).toString() == q.deviceId && cycle.lastModifiedByDeviceId == q.deviceId)
    require(queued.attemptCount >= 0 && queued.nextAttemptAtEpochMillis >= 0)
    val source = snapshot.recordsByEntity.getValue(CloudEntity.INSTALLMENT_PLAN).single { it.id == snapshot.planId }
    return ackPlan(source, snapshot.owner, snapshot.planId) to cycle
}

private fun DueOccurrenceRecord.metadataOnly() = paidAt == null && linkedTransactionId == null &&
    (status == DueStatus.PENDING || amountMinorSnapshot == null)

/** Complete authoritative month collection; a different ID may carry paid history. */
fun installmentSkipSiblingDecision(owner: UserId, planId: String, month: String, targetId: String, records: List<CloudRecord>): InstallmentSkipSyncDecision? {
    require(records.map { it.id }.distinct().size == records.size)
    val siblings = records.map { ackCycle(it, owner, planId, month, it.id) }.filter { it.id != targetId }
    if (siblings.any { it.statusWireValue !in setOf("pending", "skipped") || it.paidAt != null || it.linkedTransactionId != null ||
            (it.status == DueStatus.SKIPPED && it.amountMinorSnapshot != null) })
        return InstallmentSkipSyncDecision.Conflict("financial_sibling_requires_reconciliation")
    if (siblings.any { it.deletedAt == null }) return InstallmentSkipSyncDecision.Deferred("duplicate_cycle_requires_reconciliation")
    return null
}
