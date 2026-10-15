package vn.com.quyln.mistia.core.model

import java.time.Instant
import java.time.YearMonth
import java.time.ZoneId
import java.util.UUID
import kotlinx.serialization.json.*

enum class InstallmentCycleAction { SKIP, UNDO_SKIP }

/** A metadata-only cycle intent. Full raw tables also protect concurrent duplicate inserts. */
data class InstallmentCycleSnapshot(val base: InstallmentMutationSnapshot, val expectedPlan: InstallmentPlanRecord,
    val month: YearMonth, val zone: ZoneId, val action: InstallmentCycleAction) {
    fun liveCycleRecords(): List<CloudRecord> {
        requireHeader()
        return base.recordsByEntity.getValue(CloudEntity.DUE_OCCURRENCE_RECORD).filter { row ->
            if (!owned(row, CloudEntity.DUE_OCCURRENCE_RECORD) || row.payload.text("source_kind_raw_value") != "installment" ||
                canonicalUuid(row.payload.text("source_id")) != base.planId || row.payload.text("selected_month_key") != month.toString()) return@filter false
            val typed = DueOccurrenceRecord.fromCloudRecord(row)
            require(typed.syncVersion == row.syncVersion) { "Occurrence version metadata mismatch" }
            typed.deletedAt == null
        }.sortedBy { it.id }
    }

    fun buildMutations(createId: String, deviceId: String, now: String): List<Pair<CloudRecord, PendingMutation>> {
        val plan = currentPlan()
        val due = installmentDueRows(base.owner, listOf(plan), emptyList(), month, zone).singleOrNull()
            ?: fail(InstallmentValidationError.NOT_SCHEDULED)
        val live = liveCycleRecords()
        val typed = live.associateWith(DueOccurrenceRecord::fromCloudRecord)
        if (typed.values.any { it.status == DueStatus.PAID || it.linkedTransactionId != null || it.paidAt != null }) fail(InstallmentValidationError.SETTLED_CYCLE)
        require(canonicalUuid(deviceId) == deviceId)
        require(Instant.parse(now).toString() == now)
        val undo = action == InstallmentCycleAction.UNDO_SKIP
        if (!undo && typed.values.any { it.status == DueStatus.SKIPPED }) return emptyList()
        val selected = live.filter { typed.getValue(it).status == if (undo) DueStatus.SKIPPED else DueStatus.PENDING }
        val records = if (!undo && selected.isEmpty()) {
            require(canonicalUuid(createId) == createId && base.recordsByEntity.getValue(CloudEntity.DUE_OCCURRENCE_RECORD).none { it.id == createId })
            listOf(DueOccurrenceRecord(createId, base.owner.value, "installment", base.planId, month.toString(), due.dueDate.toString(),
                null, "skipped", null, null, now, now, null, 0, deviceId).toCloudRecord())
        } else selected.map { original ->
            val changed = buildMap<String, JsonElement> {
                put("updated_at", JsonPrimitive(now)); put("last_modified_by_device_id", JsonPrimitive(deviceId))
                if (undo) put("deleted_at", JsonPrimitive(now))
                else {
                    put("scheduled_date", JsonPrimitive(due.dueDate.toString())); put("amount_minor_snapshot", JsonNull)
                    put("status_raw_value", JsonPrimitive("skipped")); put("paid_at", JsonNull); put("linked_transaction_id", JsonNull)
                }
            }
            original.copy(payload = JsonObject(original.payload + changed), updatedAt = now, deletedAt = if (undo) now else null)
        }
        return records.map { row -> row to PendingMutation(CloudEntity.DUE_OCCURRENCE_RECORD, row.id, base.owner.value,
            if (undo) MutationKind.DELETE else MutationKind.UPSERT, row.payload, now, row.syncVersion, deviceId) }
    }

    /** Reconstruct the entire permitted intent; missing duplicates and extra ledger/plan writes fail. */
    fun requireValidMutations(mutations: List<Pair<CloudRecord, PendingMutation>>) {
        require(mutations.isNotEmpty())
        require(mutations.map { it.first.id }.distinct().size == mutations.size)
        val first = mutations.first()
        val expected = buildMutations(first.first.id, first.second.deviceId, first.second.modifiedAt)
        require(expected == mutations.sortedBy { it.first.id }) { "Invalid installment cycle mutations" }
    }

    private fun currentPlan(): InstallmentPlanRecord {
        requireHeader()
        if (expectedPlan.ownerUserId != base.owner.value || expectedPlan.id != base.planId) fail(InstallmentValidationError.NOT_FOUND)
        val row = base.recordsByEntity.getValue(CloudEntity.INSTALLMENT_PLAN).singleOrNull { it.id == base.planId }
            ?.takeIf { owned(it, CloudEntity.INSTALLMENT_PLAN) } ?: fail(InstallmentValidationError.NOT_FOUND)
        val plan = InstallmentPlanRecord.fromCloudRecord(row)
        require(plan.syncVersion == row.syncVersion)
        if (plan.isArchived || plan.deletedAt != null) fail(InstallmentValidationError.NOT_FOUND)
        fun semantic(p: InstallmentPlanRecord) = p.copy(createdAt = Instant.parse(p.createdAt).toString(), updatedAt = "", syncVersion = 0, lastModifiedByDeviceId = null)
        if (semantic(plan) != semantic(expectedPlan)) fail(InstallmentValidationError.STALE_RECORD)
        return plan
    }
    private fun requireHeader() {
        require(canonicalUuid(base.owner.value) == base.owner.value && canonicalUuid(base.planId) == base.planId)
        require(base.recordsByEntity.keys == InstallmentMutationSnapshot.entities)
        base.recordsByEntity.forEach { (entity, rows) ->
            require(rows.all { it.entity == entity.table && it.ownerUserId == base.owner.value })
            require(rows.map { it.id }.distinct().size == rows.size)
        }
    }
    private fun owned(row: CloudRecord, entity: CloudEntity) = row.entity == entity.table && row.ownerUserId == base.owner.value &&
        canonicalUuid(row.id) == row.id && row.id == canonicalUuid(row.payload.text("id")) && canonicalUuid(row.payload.text("user_id")) == base.owner.value
}

private val uuidPattern = Regex("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")
private fun canonicalUuid(value: String?): String? = value?.takeIf { uuidPattern.matches(it) }?.let { UUID.fromString(it).toString() }
private fun JsonObject.text(key: String) = (get(key) as? JsonPrimitive)?.takeIf { it.isString }?.content
private fun fail(reason: InstallmentValidationError): Nothing = throw InstallmentValidationException(reason)
