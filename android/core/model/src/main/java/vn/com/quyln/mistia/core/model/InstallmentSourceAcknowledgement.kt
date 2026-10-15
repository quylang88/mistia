package vn.com.quyln.mistia.core.model

import java.time.Instant
import java.time.Duration
import java.util.Locale
import java.util.UUID
import kotlinx.serialization.json.*

/** Full owner snapshots fence child inserts, financial footprint drift and retry/queue ABA. */
data class InstallmentAcknowledgementSnapshot(val owner: UserId, val planId: String, val batch: InstallmentDeletionBatch?,
    val recordsByEntity: Map<CloudEntity, List<CloudRecord>>, val queues: List<QueuedMutation>) {
    companion object { val entities = setOf(CloudEntity.INSTALLMENT_PLAN, CloudEntity.DUE_OCCURRENCE_RECORD, CloudEntity.LEDGER_TRANSACTION) }
    fun requireUnchanged(current: InstallmentAcknowledgementSnapshot) {
        require(owner == current.owner && planId == current.planId && batch == current.batch)
        require(recordsByEntity.keys == entities && current.recordsByEntity.keys == entities)
        require(entities.all { recordsByEntity.getValue(it).sortedBy(CloudRecord::id) == current.recordsByEntity.getValue(it).sortedBy(CloudRecord::id) })
        fun sorted(q: List<QueuedMutation>) = q.sortedWith(compareBy({ it.mutation.entity.table }, { it.mutation.recordId }))
        require(sorted(queues) == sorted(current.queues))
    }
}
data class InstallmentCycleAcknowledgement(val record: CloudRecord, val queue: QueuedMutation?)
sealed interface InstallmentSourceAckDecision {
    data object Stale : InstallmentSourceAckDecision
    data class NeedCycles(val ids: Set<String>) : InstallmentSourceAckDecision
    data class NeedLedger(val ids: Set<String>) : InstallmentSourceAckDecision
    data class Deferred(val reason: String) : InstallmentSourceAckDecision
    data class Conflict(val reason: String) : InstallmentSourceAckDecision
    data class Ready(val source: CloudRecord, val cycles: List<InstallmentCycleAcknowledgement>, val clearBatch: Boolean) : InstallmentSourceAckDecision
}

fun planInstallmentSourceAcknowledgement(snapshot: InstallmentAcknowledgementSnapshot, queued: QueuedMutation, remote: CloudRecord,
    remoteCycles: Map<String, CloudRecord?>, remoteLedger: Map<String, CloudRecord?>, now: String): InstallmentSourceAckDecision {
    val owner = snapshot.owner
    require(ackUuid(owner.value) == owner.value && ackUuid(snapshot.planId) == snapshot.planId)
    require(snapshot.recordsByEntity.keys == InstallmentAcknowledgementSnapshot.entities)
    snapshot.recordsByEntity.forEach { (entity, rows) ->
        require(rows.all { it.entity == entity.table && it.ownerUserId == owner.value } && rows.map { it.id }.distinct().size == rows.size)
    }
    require(snapshot.queues.all { it.mutation.entity in InstallmentAcknowledgementSnapshot.entities && it.mutation.subjectUserId == owner.value })
    require(snapshot.queues.map { it.mutation.entity to it.mutation.recordId }.distinct().size == snapshot.queues.size)
    fun queue(entity: CloudEntity, id: String) = snapshot.queues.singleOrNull { it.mutation.entity == entity && it.mutation.recordId == id }
    fun row(entity: CloudEntity, id: String) = snapshot.recordsByEntity.getValue(entity).singleOrNull { it.id == id }
    if (queue(CloudEntity.INSTALLMENT_PLAN, snapshot.planId) != queued) return InstallmentSourceAckDecision.Stale
    val q = queued.mutation
    require(q.entity == CloudEntity.INSTALLMENT_PLAN && q.recordId == snapshot.planId && q.subjectUserId == owner.value && q.kind == MutationKind.DELETE)
    val local = requireNotNull(row(CloudEntity.INSTALLMENT_PLAN, snapshot.planId))
    val localPlan = ackPlan(local, owner, snapshot.planId)
    val remotePlan = ackPlan(remote, owner, snapshot.planId)
    require(localPlan.deletedAt != null && local.payload == q.payload && local.syncVersion == q.baseVersion && local.updatedAt == q.modifiedAt)
    require(ackUuid(q.deviceId) == q.deviceId && local.payload.ackText("last_modified_by_device_id") == q.deviceId)
    require(Instant.parse(now).toString() == now)
    val batch = snapshot.batch
    if (batch != null) {
        batch.requireValid(); require(batch.owner == owner && batch.planId == snapshot.planId)
        if (batch.source.deletion != q) return InstallmentSourceAckDecision.Stale
    } else {
        val unknown = snapshot.queues.filter { it.mutation.entity == CloudEntity.DUE_OCCURRENCE_RECORD }.any {
            val cycle = row(CloudEntity.DUE_OCCURRENCE_RECORD, it.mutation.recordId)
            cycle == null || cycle.payload.ackText("source_kind_raw_value") == "installment" &&
                ackUuid(cycle.payload.ackText("source_id")) == snapshot.planId && ackUuid(cycle.payload.ackText("user_id")) == owner.value
        }
        if (unknown) return InstallmentSourceAckDecision.Deferred("unproven_source_delete_dependencies")
    }
    if (remotePlan.deletedAt == null && (remotePlan.currencyCode != localPlan.currencyCode || Duration.between(Instant.parse(remotePlan.createdAt), Instant.parse(localPlan.createdAt)).abs() >= Duration.ofNanos(1000)))
        return InstallmentSourceAckDecision.Conflict("source_currency_or_anchor_changed")
    val eligible = mutableListOf<InstallmentDeletionMember>()
    batch?.cycles?.forEach { member ->
        val current = row(CloudEntity.DUE_OCCURRENCE_RECORD, member.before.id)
        current?.let { ackCycle(it, owner, snapshot.planId, DueOccurrenceRecord.fromCloudRecord(member.before).selectedMonthKey, member.before.id) }
        val pending = queue(CloudEntity.DUE_OCCURRENCE_RECORD, member.before.id)
        if (pending?.mutation == member.deletion) {
            if (current == null) return InstallmentSourceAckDecision.Conflict("missing_causal_child_record")
            require(current.payload == pending.mutation.payload && current.syncVersion == pending.mutation.baseVersion && current.updatedAt == pending.mutation.modifiedAt)
            eligible += member
        } else if (pending == null && (current == null || current.payload == member.deletion.payload))
            return InstallmentSourceAckDecision.Conflict("missing_causal_child_queue")
    }
    if (remotePlan.deletedAt != null) {
        require(remoteCycles.isEmpty() && remoteLedger.isEmpty())
        return InstallmentSourceAckDecision.Ready(remote, emptyList(), batch != null && eligible.isEmpty())
    }
    val ids = eligible.mapTo(mutableSetOf()) { it.before.id }
    require(remoteCycles.keys.all { it in ids })
    if (!remoteCycles.keys.containsAll(ids)) return InstallmentSourceAckDecision.NeedCycles(ids - remoteCycles.keys)
    val targets = mutableListOf<InstallmentCycleAcknowledgement>()
    for (member in eligible) {
        val authoritative = remoteCycles[member.before.id]
        authoritative?.let { ackCycle(it, owner, snapshot.planId, DueOccurrenceRecord.fromCloudRecord(member.before).selectedMonthKey, member.before.id) }
        val prior = member.pendingBefore
        if (prior != null && authoritative != null) {
            val before = canonicalAckCycle(member.before); val server = canonicalAckCycle(authoritative)
            val equal = before.deletedAt == server.deletedAt && RecordConflictResolver.semanticFingerprint(before.payload) == RecordConflictResolver.semanticFingerprint(server.payload)
            val winner = if (equal) RecordConflictWinner.REMOTE else RecordConflictResolver.resolve(before, server).winner
            if (winner == RecordConflictWinner.UNRESOLVED) return InstallmentSourceAckDecision.Conflict("child_same_clock_version_different_payload")
            if (winner == RecordConflictWinner.REMOTE) { targets += InstallmentCycleAcknowledgement(authoritative, null); continue }
        }
        if (prior != null) targets += InstallmentCycleAcknowledgement(member.before, prior)
        else if (authoritative != null) targets += InstallmentCycleAcknowledgement(authoritative, null)
        else {
            val payload = JsonObject(member.before.payload + mapOf("updated_at" to JsonPrimitive(now), "last_modified_by_device_id" to JsonPrimitive(q.deviceId)))
            val restored = member.before.copy(payload = payload, updatedAt = now)
            val repair = PendingMutation(CloudEntity.DUE_OCCURRENCE_RECORD, restored.id, owner.value, MutationKind.UPSERT, payload, now, restored.syncVersion, q.deviceId)
            targets += InstallmentCycleAcknowledgement(restored, QueuedMutation(repair, 0, 0, null, member.remoteIdentityObservedBefore))
        }
    }
    val links = targets.mapNotNull { DueOccurrenceRecord.fromCloudRecord(it.record).linkedTransactionId }.toSet()
    require(remoteLedger.keys.all { it in links })
    if (!remoteLedger.keys.containsAll(links)) return InstallmentSourceAckDecision.NeedLedger(links - remoteLedger.keys)
    for (target in targets) {
        val cycle = DueOccurrenceRecord.fromCloudRecord(target.record)
        val linked = cycle.linkedTransactionId ?: continue // Explicit legacy paid-without-link remains representable.
        val server = remoteLedger[linked]?.let { ackLedger(it, owner, linked) }
        val current = row(CloudEntity.LEDGER_TRANSACTION, linked)?.let { ackLedger(it, owner, linked) }
        val pending = queue(CloudEntity.LEDGER_TRANSACTION, linked)
        val localIntent = current != null && pending?.mutation?.kind == MutationKind.UPSERT && pending.mutation.payload == row(CloudEntity.LEDGER_TRANSACTION, linked)?.payload && current.livePostedExpense()
        if (localIntent) {
            val intent = requireNotNull(pending).mutation
            require(intent.baseVersion == current!!.syncVersion && Instant.parse(intent.modifiedAt) == Instant.parse(current.updatedAt))
            require(ackUuid(intent.deviceId) == intent.deviceId && current.lastModifiedByDeviceId == intent.deviceId)
            require(pending.attemptCount >= 0 && pending.nextAttemptAtEpochMillis >= 0)
        }
        val live = if (localIntent) true else {
            if (current?.financialAckPayload() != server?.financialAckPayload()) return InstallmentSourceAckDecision.Deferred("linked_ledger_not_pulled")
            server?.livePostedExpense() == true
        }
        if (cycle.deletedAt == null && (cycle.status != DueStatus.PAID || !live)) return InstallmentSourceAckDecision.Conflict("invalid_paid_financial_footprint")
        if (cycle.deletedAt != null && live) return InstallmentSourceAckDecision.Conflict("deleted_cycle_linked_ledger_live")
    }
    return InstallmentSourceAckDecision.Ready(remote, targets, batch != null)
}

internal fun ackIdentity(row: CloudRecord, entity: CloudEntity, owner: UserId, id: String) {
    require(row.entity == entity.table && row.ownerUserId == owner.value && row.id == id && ackUuid(id) == id)
    require(ackUuid(row.payload.ackText("id")) == id && ackUuid(row.payload.ackText("user_id")) == owner.value)
    val version = row.payload["sync_version"] as? JsonPrimitive
    require(version != null && !version.isString && version.longOrNull == row.syncVersion && row.syncVersion >= 0)
}
internal fun ackPlan(row: CloudRecord, owner: UserId, id: String): InstallmentPlanRecord {
    ackIdentity(row, CloudEntity.INSTALLMENT_PLAN, owner, id)
    return InstallmentPlanRecord.fromCloudRecord(row).also { require(it.deletedAt == row.deletedAt && Instant.parse(it.updatedAt) == Instant.parse(requireNotNull(row.updatedAt))) }
}
internal fun ackCycle(row: CloudRecord, owner: UserId, source: String, month: String, id: String): DueOccurrenceRecord {
    ackIdentity(row, CloudEntity.DUE_OCCURRENCE_RECORD, owner, id)
    return DueOccurrenceRecord.fromCloudRecord(row).also {
        require(it.sourceKindWireValue == "installment" && it.sourceId == source && it.selectedMonthKey == month)
        require(it.deletedAt == row.deletedAt && Instant.parse(it.updatedAt) == Instant.parse(requireNotNull(row.updatedAt)))
    }
}
internal fun ackLedger(row: CloudRecord, owner: UserId, id: String): LedgerTransactionRecord {
    ackIdentity(row, CloudEntity.LEDGER_TRANSACTION, owner, id)
    return LedgerTransactionRecord.fromCloudRecord(row).also {
        require(it.id == id && it.ownerUserId == owner.value && it.deletedAt == row.deletedAt)
        require(Instant.parse(it.updatedAt) == Instant.parse(requireNotNull(row.updatedAt)))
        Instant.parse(it.createdAt); Instant.parse(it.occurredAt)
    }
}
private fun LedgerTransactionRecord.livePostedExpense() = deletedAt == null && !isArchived && primaryKind == TransactionPrimaryKind.EXPENSE && entryStatus == TransactionEntryStatus.POSTED && amountMinor > 0
internal fun LedgerTransactionRecord.financialAckPayload(): JsonObject {
    val ignored = setOf("created_at", "updated_at", "sync_version", "last_modified_by_device_id", "created_by_user_id", "last_modified_by_user_id", "title", "note", "counterparty_name", "normalized_counterparty_key")
    val fields = toPayload().filterKeys { it !in ignored }.toMutableMap()
    listOf("occurred_at", "archived_at", "deleted_at").forEach { key -> (fields[key] as? JsonPrimitive)?.contentOrNull?.let { fields[key] = JsonPrimitive(Instant.parse(it).toString()) } }
    listOf("source_currency_code", "destination_currency_code", "reporting_currency_code").forEach { key -> (fields[key] as? JsonPrimitive)?.contentOrNull?.let { fields[key] = JsonPrimitive(it.uppercase(Locale.ROOT)) } }
    return JsonObject(fields)
}
internal fun canonicalAckCycle(row: CloudRecord): CloudRecord {
    val fields = DueOccurrenceRecord.fromCloudRecord(row).toPayload().toMutableMap()
    listOf("scheduled_date", "paid_at").forEach { key -> (fields[key] as? JsonPrimitive)?.contentOrNull?.let { fields[key] = JsonPrimitive(Instant.parse(it).toString()) } }
    return row.copy(payload = JsonObject(fields), deletedAt = row.deletedAt?.let { Instant.parse(it).toString() })
}
private fun JsonObject.ackText(key: String) = (get(key) as? JsonPrimitive)?.takeIf { it.isString }?.content
private val ackUuidPattern = Regex("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")
private fun ackUuid(value: String?): String? = value?.takeIf { ackUuidPattern.matches(it) }?.let { UUID.fromString(it).toString() }
