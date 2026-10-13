package vn.com.quyln.mistia.core.model

import java.time.Instant
import java.time.ZoneId
import java.util.Locale
import java.util.UUID
import kotlinx.serialization.json.*

enum class BillScheduleKind { RECURRING, ONE_TIME }

/** Swift RemoteRecurringBillPlan wire contract. Nullable clears remain explicit. */
data class RecurringBillPlanRecord(
    val id: String,
    val ownerUserId: String,
    val name: String,
    val iconSymbolName: String,
    val categoryId: String?,
    val amountMinor: Long?,
    val dueDay: Int,
    val scheduleKindWireValue: String?,
    val paymentStartDay: Int?,
    val paymentStartDate: String?,
    val firstScheduledMonth: String?,
    val hasExplicitDueDate: Boolean?,
    val dueDate: String?,
    val autoPayEnabled: Boolean?,
    val autoPayDay: Int?,
    val autoPayDate: String?,
    val frequencyMonths: Int,
    val paymentWalletId: String?,
    val currencyCode: String,
    val isArchived: Boolean,
    val isPaused: Boolean,
    val pausedAt: String?,
    val resumeStartMonth: String?,
    val createdAt: String,
    val updatedAt: String,
    val deletedAt: String?,
    val syncVersion: Long,
    val lastModifiedByDeviceId: String?,
 ) {
    val scheduleKind:BillScheduleKind get()=if(scheduleKindWireValue=="oneTime") BillScheduleKind.ONE_TIME else BillScheduleKind.RECURRING
    val resolvedPaymentStartDay:Int get()=paymentStartDay ?: dueDay
    fun resolvedHasExplicitDueDate(zone:ZoneId):Boolean {
        if(hasExplicitDueDate!=true) return false
        if(scheduleKind==BillScheduleKind.RECURRING) return dueDay!=resolvedPaymentStartDay
        val due=dueDate?.let { Instant.parse(it).atZone(zone).toLocalDate() } ?: return false
        val start=paymentStartDate?.let { Instant.parse(it).atZone(zone).toLocalDate() } ?: return false
        return due>start
    }
    fun toPayload():JsonObject=buildJsonObject {
        put("id",JsonPrimitive(id))
        put("user_id",JsonPrimitive(ownerUserId))
        put("name",JsonPrimitive(name))
        put("icon_symbol_name",JsonPrimitive(iconSymbolName))
        put("category_id",categoryId?.let(::JsonPrimitive) ?: JsonNull)
        put("amount_minor",amountMinor?.let(::JsonPrimitive) ?: JsonNull)
        put("due_day",JsonPrimitive(dueDay))
        put("schedule_kind_raw_value",scheduleKindWireValue?.let(::JsonPrimitive) ?: JsonNull)
        put("payment_start_day",paymentStartDay?.let(::JsonPrimitive) ?: JsonNull)
        put("payment_start_date",paymentStartDate?.let(::JsonPrimitive) ?: JsonNull)
        put("first_scheduled_month",firstScheduledMonth?.let(::JsonPrimitive) ?: JsonNull)
        put("has_explicit_due_date",hasExplicitDueDate?.let(::JsonPrimitive) ?: JsonNull)
        put("due_date",dueDate?.let(::JsonPrimitive) ?: JsonNull)
        put("auto_pay_enabled",autoPayEnabled?.let(::JsonPrimitive) ?: JsonNull)
        put("auto_pay_day",autoPayDay?.let(::JsonPrimitive) ?: JsonNull)
        put("auto_pay_date",autoPayDate?.let(::JsonPrimitive) ?: JsonNull)
        put("frequency_months",JsonPrimitive(frequencyMonths))
        put("payment_wallet_id",paymentWalletId?.let(::JsonPrimitive) ?: JsonNull)
        put("currency_code",JsonPrimitive(currencyCode))
        put("is_archived",JsonPrimitive(isArchived))
        put("is_paused",JsonPrimitive(isPaused))
        put("paused_at",pausedAt?.let(::JsonPrimitive) ?: JsonNull)
        put("resume_start_month",resumeStartMonth?.let(::JsonPrimitive) ?: JsonNull)
        put("created_at",JsonPrimitive(createdAt))
        put("updated_at",JsonPrimitive(updatedAt))
        put("deleted_at",deletedAt?.let(::JsonPrimitive) ?: JsonNull)
        put("sync_version",JsonPrimitive(syncVersion))
        put("last_modified_by_device_id",lastModifiedByDeviceId?.let(::JsonPrimitive) ?: JsonNull)
    }
    fun toCloudRecord()=CloudRecord(CloudEntity.RECURRING_BILL_PLAN.table,id,ownerUserId,toPayload(),updatedAt,deletedAt,syncVersion)
    companion object {
        fun fromCloudRecord(record:CloudRecord):RecurringBillPlanRecord {
            require(record.entity==CloudEntity.RECURRING_BILL_PLAN.table)
            val p=record.payload
            return RecurringBillPlanRecord(
                id=uuid(p.string("id")),
                ownerUserId=uuid(p.string("user_id")),
                name=p.string("name"),
                iconSymbolName=p.string("icon_symbol_name"),
                categoryId=p.optionalString("category_id")?.let(::uuid),
                amountMinor=p.optionalNumber("amount_minor"),
                dueDay=p.integer("due_day"),
                scheduleKindWireValue=p.optionalString("schedule_kind_raw_value"),
                paymentStartDay=p.optionalInteger("payment_start_day"),
                paymentStartDate=p.optionalString("payment_start_date")?.let(::utc),
                firstScheduledMonth=p.optionalString("first_scheduled_month")?.let(::utc),
                hasExplicitDueDate=p.optionalBoolean("has_explicit_due_date"),
                dueDate=p.optionalString("due_date")?.let(::utc),
                autoPayEnabled=p.optionalBoolean("auto_pay_enabled"),
                autoPayDay=p.optionalInteger("auto_pay_day"),
                autoPayDate=p.optionalString("auto_pay_date")?.let(::utc),
                frequencyMonths=p.integer("frequency_months"),
                paymentWalletId=p.optionalString("payment_wallet_id")?.let(::uuid),
                currencyCode=p.string("currency_code").uppercase(Locale.ROOT),
                isArchived=p.boolean("is_archived"),
                isPaused=p.optionalBoolean("is_paused") ?: false,
                pausedAt=p.optionalString("paused_at")?.let(::utc),
                resumeStartMonth=p.optionalString("resume_start_month")?.let(::utc),
                createdAt=utc(p.string("created_at")),
                updatedAt=utc(p.string("updated_at")),
                deletedAt=(p.optionalString("deleted_at") ?: record.deletedAt)?.let(::utc),
                syncVersion=p.number("sync_version"),
                lastModifiedByDeviceId=p.optionalString("last_modified_by_device_id")?.let(::uuid),
            )
        }
    }
}

private fun uuid(value:String):String {
    require(Regex("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}").matches(value))
    return UUID.fromString(value).toString()
}
private fun utc(value:String):String=value.also { require(runCatching { Instant.parse(it) }.isSuccess) { "Invalid bill timestamp" } }
private fun JsonObject.optionalString(key:String):String?=when(val value=get(key)) {
    null,JsonNull -> null
    is JsonPrimitive -> { require(value.isString);value.content }
    else -> throw IllegalArgumentException("Bill field $key must be a string")
}
private fun JsonObject.string(key:String):String=optionalString(key) ?: throw IllegalArgumentException("Missing bill field $key")
private fun JsonObject.optionalNumber(key:String):Long?=when(val value=get(key)) {
    null,JsonNull -> null
    is JsonPrimitive -> value.takeUnless { it.isString }?.longOrNull ?: throw IllegalArgumentException("Bill field $key must be an Int64")
    else -> throw IllegalArgumentException("Bill field $key must be an Int64")
}
private fun JsonObject.number(key:String):Long=optionalNumber(key) ?: throw IllegalArgumentException("Missing bill field $key")
private fun JsonObject.optionalInteger(key:String):Int?=optionalNumber(key)?.also { require(it in Int.MIN_VALUE.toLong()..Int.MAX_VALUE.toLong()) }?.toInt()
private fun JsonObject.integer(key:String):Int=optionalInteger(key) ?: throw IllegalArgumentException("Missing bill field $key")
private fun JsonObject.optionalBoolean(key:String):Boolean?=when(val value=get(key)) {
    null,JsonNull -> null
    is JsonPrimitive -> value.takeUnless { it.isString }?.booleanOrNull ?: throw IllegalArgumentException("Bill field $key must be a boolean")
    else -> throw IllegalArgumentException("Bill field $key must be a boolean")
}
private fun JsonObject.boolean(key:String):Boolean=optionalBoolean(key) ?: throw IllegalArgumentException("Missing bill field $key")
