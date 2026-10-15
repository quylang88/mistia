package vn.com.quyln.mistia.core.model

import java.time.Instant
import java.util.UUID
import kotlinx.serialization.json.*

/** Runs at the atomic Room boundary, independently of UI/repository draft construction. */
internal fun BillMoneySnapshot.requireInstallmentMoneyCoherence(writes: List<Pair<CloudRecord, PendingMutation>>) {
    val financial = writes.filter { it.first.entity != CloudEntity.TRANSACTION_CATEGORY.table }
    val dueWrites = financial.filter { it.first.entity == CloudEntity.DUE_OCCURRENCE_RECORD.table }
    val ledgerWrites = financial.filter { it.first.entity == CloudEntity.LEDGER_TRANSACTION.table }
    val creating = dueWrites.first().second.kind == MutationKind.UPSERT
    require(financial.all { it.second.kind == if (creating) MutationKind.UPSERT else MutationKind.DELETE })
    financial.forEach { (record, mutation) ->
        require(UUID.fromString(mutation.deviceId).toString() == mutation.deviceId)
        require(Instant.parse(requireNotNull(record.updatedAt)) == Instant.parse(mutation.modifiedAt))
        require(Instant.parse(requireNotNull((record.payload["updated_at"] as? JsonPrimitive)?.contentOrNull)) == Instant.parse(record.updatedAt))
        require(record.payload["deleted_at"] == (record.deletedAt?.let(::JsonPrimitive) ?: JsonNull))
        require(record.payload["last_modified_by_device_id"] == JsonPrimitive(mutation.deviceId))
        val version = requireNotNull(record.payload["sync_version"] as? JsonPrimitive)
        require(!version.isString && version.longOrNull == record.syncVersion)
        require((record.deletedAt == null) == creating)
    }
    val cycles = dueWrites.map { DueOccurrenceRecord.fromCloudRecord(it.first) }
    val expenses = ledgerWrites.map { LedgerTransactionRecord.fromCloudRecord(it.first) }
    val currentCycles = billCycleRecords(recordsByEntity.getValue(CloudEntity.DUE_OCCURRENCE_RECORD), bill, month.toString(), sourceKind)
        .map(DueOccurrenceRecord::fromCloudRecord)
    val allCycles = recordsByEntity.getValue(CloudEntity.DUE_OCCURRENCE_RECORD).map(DueOccurrenceRecord::fromCloudRecord)
    val priorExpenses = recordsByEntity.getValue(CloudEntity.LEDGER_TRANSACTION).map(LedgerTransactionRecord::fromCloudRecord)
    if (creating) {
        require(expenses.size == 1)
        val expense = expenses.single()
        require(expense.ownerUserId == owner.value && expense.deletedAt == null && !expense.isArchived && expense.primaryKind == TransactionPrimaryKind.EXPENSE &&
            expense.entryStatus == TransactionEntryStatus.POSTED && expense.amountMinor > 0)
        require(expense.lastModifiedByUserId == owner.value)
        val pending = currentCycles.filter { it.deletedAt == null }
        require(pending.all { it.statusWireValue == "pending" && it.linkedTransactionId == null && it.paidAt == null })
        require(cycles.map { it.id }.containsAll(pending.map { it.id }))
        require(cycles.all { it.statusWireValue == "paid" && it.amountMinorSnapshot == expense.amountMinor && it.linkedTransactionId == expense.id &&
            it.paidAt != null && Instant.parse(it.paidAt) == Instant.parse(expense.updatedAt) && Instant.parse(it.updatedAt) == Instant.parse(expense.updatedAt) })
        val writtenIds = cycles.map { it.id }.toSet()
        require(allCycles.none { it.deletedAt == null && it.linkedTransactionId == expense.id && it.id !in writtenIds })
    } else {
        require(writes.none { it.first.entity == CloudEntity.TRANSACTION_CATEGORY.table })
        val paid = currentCycles.filter { it.deletedAt == null && it.status == DueStatus.PAID }
        require(paid.isNotEmpty() && cycles.map { it.id }.toSet() == paid.map { it.id }.toSet())
        cycles.forEach { deleted ->
            val before = paid.single { it.id == deleted.id }
            require(deleted.copy(updatedAt = before.updatedAt, deletedAt = before.deletedAt, lastModifiedByDeviceId = before.lastModifiedByDeviceId) == before)
        }
        val linked = paid.mapNotNull { it.linkedTransactionId }.toSet()
        val originals = linked.map { id -> priorExpenses.single { it.id == id && it.ownerUserId == owner.value } }
        require(expenses.map { it.id }.toSet() == originals.filter { it.deletedAt == null }.map { it.id }.toSet())
        require(allCycles.none { it.deletedAt == null && it.id !in paid.map { c -> c.id } && it.linkedTransactionId in linked })
        expenses.forEach { deleted ->
            val before = originals.single { it.id == deleted.id }
            require(deleted.lastModifiedByUserId == owner.value)
            require(deleted.copy(updatedAt = before.updatedAt, deletedAt = before.deletedAt, lastModifiedByDeviceId = before.lastModifiedByDeviceId,
                lastModifiedByUserId = before.lastModifiedByUserId) == before)
        }
    }
}
