package vn.com.quyln.mistia.core.model

import java.util.UUID
import kotlinx.serialization.json.*

/** Complete raw read set used by ordinary transaction validation, including tombstones. */
data class TransactionSaveSnapshot(val owner: UserId, val recordsByEntity: Map<CloudEntity, List<CloudRecord>>) {
    companion object {
        val entities = setOf(CloudEntity.LEDGER_TRANSACTION, CloudEntity.LEDGER_WALLET,
            CloudEntity.TRANSACTION_CATEGORY, CloudEntity.CREDIT_CARD_PROFILE, CloudEntity.DUE_OCCURRENCE_RECORD)
    }

    fun requireValid() {
        require(UUID.fromString(owner.value).toString() == owner.value)
        require(recordsByEntity.keys == entities) { "Incomplete transaction dependencies" }
        recordsByEntity.forEach { (entity, rows) ->
            require(rows.map { it.id }.distinct().size == rows.size)
            rows.forEach { row ->
                require(row.entity == entity.table && row.ownerUserId == owner.value)
                require(UUID.fromString(row.id).toString() == row.id)
                require(row.payload["id"] == JsonPrimitive(row.id) && row.payload["user_id"] == JsonPrimitive(owner.value))
                require(row.syncVersion >= 0 && row.payload["sync_version"] == JsonPrimitive(row.syncVersion))
            }
        }
    }

    fun active(entity: CloudEntity): List<CloudRecord> = recordsByEntity.getValue(entity).filter { it.deletedAt == null }

    fun requireUnchanged(current: TransactionSaveSnapshot) {
        requireValid(); current.requireValid()
        require(current.owner == owner && recordsByEntity.all { (entity, rows) ->
            rows.sortedBy { it.id } == current.recordsByEntity.getValue(entity).sortedBy { it.id }
        }) { "Transaction dependencies changed during save" }
    }

    fun requireValidMutation(record: CloudRecord, mutation: PendingMutation) {
        requireValid()
        require(record.entity == CloudEntity.LEDGER_TRANSACTION.table && mutation.entity == CloudEntity.LEDGER_TRANSACTION)
        require(record.ownerUserId == owner.value && mutation.subjectUserId == owner.value)
        require(UUID.fromString(record.id).toString() == record.id && mutation.recordId == record.id)
        require(record.payload["id"] == JsonPrimitive(record.id) && record.payload["user_id"] == JsonPrimitive(owner.value))
        require(mutation.kind == MutationKind.UPSERT && mutation.payload == record.payload)
        require(record.deletedAt == null && record.payload["deleted_at"] == JsonNull)
        require(record.updatedAt == mutation.modifiedAt && record.payload["updated_at"] == JsonPrimitive(mutation.modifiedAt))
        val existing = recordsByEntity.getValue(CloudEntity.LEDGER_TRANSACTION).singleOrNull { it.id == record.id }
        require(existing == null || (existing.deletedAt == null && existing.payload["deleted_at"] == JsonNull)) { "Deleted transaction identity is occupied" }
        require(record.syncVersion == (existing?.syncVersion ?: 0L) && mutation.baseVersion == record.syncVersion &&
            record.payload["sync_version"] == JsonPrimitive(record.syncVersion))
        require(record.payload["amount_minor"]?.let { it as? JsonPrimitive }?.takeUnless { it.isString }?.longOrNull?.let { it > 0 } == true)
    }
}
