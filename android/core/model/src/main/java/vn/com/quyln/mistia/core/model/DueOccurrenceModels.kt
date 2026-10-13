package vn.com.quyln.mistia.core.model

import java.time.Instant
import java.util.UUID
import kotlinx.serialization.json.*

enum class DueSourceKind(val wireValue:String) {
    CREDIT_CARD("creditCard"), RECURRING_BILL("recurringBill"), INSTALLMENT("installment")
}
enum class DueStatus(val wireValue:String) { PENDING("pending"), PAID("paid"), SKIPPED("skipped") }

/** Lossless RemoteDueOccurrenceRecord. Unknown enums resolve like Swift persistence. */
data class DueOccurrenceRecord(
    val id:String,
    val ownerUserId:String,
    val sourceKindWireValue:String,
    val sourceId:String,
    val selectedMonthKey:String,
    val scheduledDate:String,
    val amountMinorSnapshot:Long?,
    val statusWireValue:String,
    val paidAt:String?,
    val linkedTransactionId:String?,
    val createdAt:String,
    val updatedAt:String,
    val deletedAt:String?,
    val syncVersion:Long,
    val lastModifiedByDeviceId:String?,
) {
    val sourceKind:DueSourceKind get()=DueSourceKind.entries.firstOrNull { it.wireValue==sourceKindWireValue } ?: DueSourceKind.CREDIT_CARD
    val status:DueStatus get()=DueStatus.entries.firstOrNull { it.wireValue==statusWireValue } ?: DueStatus.PENDING
    fun toPayload():JsonObject=buildJsonObject {
        put("user_id",JsonPrimitive(ownerUserId));put("id",JsonPrimitive(id))
        put("source_kind_raw_value",JsonPrimitive(sourceKindWireValue));put("source_id",JsonPrimitive(sourceId))
        put("selected_month_key",JsonPrimitive(selectedMonthKey));put("scheduled_date",JsonPrimitive(scheduledDate))
        put("amount_minor_snapshot",amountMinorSnapshot?.let(::JsonPrimitive) ?: JsonNull)
        put("status_raw_value",JsonPrimitive(statusWireValue));putNullable("paid_at",paidAt);putNullable("linked_transaction_id",linkedTransactionId)
        put("created_at",JsonPrimitive(createdAt));put("updated_at",JsonPrimitive(updatedAt));putNullable("deleted_at",deletedAt)
        put("sync_version",JsonPrimitive(syncVersion));putNullable("last_modified_by_device_id",lastModifiedByDeviceId)
    }
    fun toCloudRecord()=CloudRecord(CloudEntity.DUE_OCCURRENCE_RECORD.table,id,ownerUserId,toPayload(),updatedAt,deletedAt,syncVersion)
    companion object {
        fun fromCloudRecord(record:CloudRecord):DueOccurrenceRecord {
            require(record.entity==CloudEntity.DUE_OCCURRENCE_RECORD.table)
            val p=record.payload
            return DueOccurrenceRecord(uuid(p.string("id")),uuid(p.string("user_id")),p.string("source_kind_raw_value"),uuid(p.string("source_id")),
                p.string("selected_month_key"),utc(p.string("scheduled_date")),p.optionalNumber("amount_minor_snapshot"),p.string("status_raw_value"),
                p.optionalString("paid_at")?.let(::utc),p.optionalString("linked_transaction_id")?.let(::uuid),utc(p.string("created_at")),utc(p.string("updated_at")),
                (p.optionalString("deleted_at") ?: record.deletedAt)?.let(::utc),p.optionalNumber("sync_version") ?: throw IllegalArgumentException("Missing occurrence version"),
                p.optionalString("last_modified_by_device_id")?.let(::uuid))
        }
    }
}
private fun JsonObjectBuilder.putNullable(key:String,value:String?) { put(key,value?.let(::JsonPrimitive) ?: JsonNull) }
private fun uuid(value:String):String {
    require(Regex("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}").matches(value))
    return UUID.fromString(value).toString()
}
private fun utc(value:String):String=value.also { require(runCatching { Instant.parse(it) }.isSuccess) { "Invalid occurrence timestamp" } }
private fun JsonObject.optionalString(key:String):String?=when(val value=get(key)) {
    null,JsonNull -> null
    is JsonPrimitive -> { require(value.isString);value.content }
    else -> throw IllegalArgumentException("Occurrence field $key must be a string")
}
private fun JsonObject.string(key:String):String=optionalString(key) ?: throw IllegalArgumentException("Missing occurrence field $key")
private fun JsonObject.optionalNumber(key:String):Long?=when(val value=get(key)) {
    null,JsonNull -> null
    is JsonPrimitive -> value.takeUnless { it.isString }?.longOrNull ?: throw IllegalArgumentException("Occurrence field $key must be an Int64")
    else -> throw IllegalArgumentException("Occurrence field $key must be an Int64")
}
