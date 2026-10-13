package vn.com.quyln.mistia.core.model

import java.math.BigInteger
import java.text.Collator
import java.time.Instant
import java.time.YearMonth
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import java.util.Locale
import java.util.UUID
import kotlinx.serialization.json.*

/** Wire contract of Swift RemoteSavingsGoal; no inferred wallet balance. */
data class SavingsGoalRecord(
    val id: String,
    val ownerUserId: String,
    val name: String,
    val iconSymbolName: String,
    val targetMinor: Long,
    val currentSavedMinor: Long,
    val targetDate: String,
    val linkedWalletId: String?,
    val currencyCode: String,
    val sortOrder: Int,
    val isArchived: Boolean,
    val createdAt: String,
    val updatedAt: String,
    val deletedAt: String?,
    val syncVersion: Long,
    val lastModifiedByDeviceId: String?,
) {
    fun toPayload(): JsonObject = buildJsonObject {
        put("user_id",JsonPrimitive(ownerUserId)); put("id",JsonPrimitive(id))
        put("name",JsonPrimitive(name)); put("icon_symbol_name",JsonPrimitive(iconSymbolName))
        put("target_minor",JsonPrimitive(targetMinor)); put("current_saved_minor",JsonPrimitive(currentSavedMinor))
        put("target_date",JsonPrimitive(targetDate)); putNullable("linked_wallet_id",linkedWalletId)
        put("currency_code",JsonPrimitive(currencyCode)); put("sort_order",JsonPrimitive(sortOrder))
        put("is_archived",JsonPrimitive(isArchived)); put("created_at",JsonPrimitive(createdAt)); put("updated_at",JsonPrimitive(updatedAt))
        putNullable("deleted_at",deletedAt); put("sync_version",JsonPrimitive(syncVersion)); putNullable("last_modified_by_device_id",lastModifiedByDeviceId)
    }
    fun toCloudRecord() = CloudRecord(CloudEntity.SAVINGS_GOAL.table,id,ownerUserId,toPayload(),updatedAt,deletedAt,syncVersion)
    companion object {
        fun fromCloudRecord(record: CloudRecord): SavingsGoalRecord {
            require(record.entity==CloudEntity.SAVINGS_GOAL.table)
            val p=record.payload
            return SavingsGoalRecord(
                uuid(p.string("id")),uuid(p.string("user_id")),p.string("name"),p.string("icon_symbol_name"),
                p.number("target_minor"),p.number("current_saved_minor"),utc(p.string("target_date")),
                p.optionalString("linked_wallet_id")?.let(::uuid),p.string("currency_code").uppercase(Locale.ROOT),
                p.number("sort_order").also { require(it in Int.MIN_VALUE.toLong()..Int.MAX_VALUE.toLong()) }.toInt(),p.boolean("is_archived"),utc(p.string("created_at")),utc(p.string("updated_at")),
                (p.optionalString("deleted_at") ?: record.deletedAt)?.let(::utc),p.number("sync_version"),p.optionalString("last_modified_by_device_id")?.let(::uuid),
            )
        }
    }
}

data class SavingsGoalRow(val goal: SavingsGoalRecord, val monthlyRequiredMinor: Long)

/** Inclusive target month, exact ceiling and progress comparison beyond Double precision. */
fun savingsGoalRows(owner: UserId, goals: List<SavingsGoalRecord>, month: YearMonth, zone: ZoneId): List<SavingsGoalRow> =
    goals.filter { it.ownerUserId==owner.value && !it.isArchived && it.deletedAt==null }.map { goal ->
        val targetMonth=YearMonth.from(Instant.parse(goal.targetDate).atZone(zone))
        val months=maxOf(ChronoUnit.MONTHS.between(month,targetMonth)+1,1)
        val remaining=BigInteger.valueOf(goal.targetMinor).subtract(BigInteger.valueOf(goal.currentSavedMinor)).max(BigInteger.ZERO)
        val required=remaining.add(BigInteger.valueOf(months-1)).divide(BigInteger.valueOf(months)).min(BigInteger.valueOf(Long.MAX_VALUE)).toLong()
        SavingsGoalRow(goal,required)
    }.sortedWith { a,b ->
        fun ratio(g:SavingsGoalRecord)=if(g.targetMinor>0) BigInteger.valueOf(g.currentSavedMinor) to BigInteger.valueOf(g.targetMinor) else BigInteger.ZERO to BigInteger.ONE
        val (an,ad)=ratio(a.goal);val (bn,bd)=ratio(b.goal)
        val progress=bn.multiply(ad).compareTo(an.multiply(bd))
        if(progress!=0) progress else {
            val date=Instant.parse(a.goal.targetDate).compareTo(Instant.parse(b.goal.targetDate))
            if(date!=0) date else Collator.getInstance().apply { strength=Collator.SECONDARY }.compare(a.goal.name,b.goal.name)
        }
    }

private fun JsonObjectBuilder.putNullable(key:String,value:String?) { put(key,value?.let(::JsonPrimitive) ?: JsonNull) }
private fun uuid(value:String):String {
    require(Regex("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}").matches(value))
    return UUID.fromString(value).toString()
}
private fun utc(value:String):String = value.also { require(runCatching { Instant.parse(it) }.isSuccess) { "Invalid savings timestamp" } }
private fun JsonObject.optionalString(key:String):String? = when(val value=get(key)) {
    null,JsonNull -> null
    is JsonPrimitive -> { require(value.isString);value.content }
    else -> throw IllegalArgumentException("Savings field $key must be a string")
}
private fun JsonObject.string(key:String):String = optionalString(key) ?: throw IllegalArgumentException("Missing savings field $key")
private fun JsonObject.number(key:String):Long = (get(key) as? JsonPrimitive)?.takeUnless { it.isString }?.longOrNull
    ?: throw IllegalArgumentException("Savings field $key must be an Int64")
private fun JsonObject.boolean(key:String):Boolean = (get(key) as? JsonPrimitive)?.takeUnless { it.isString }?.booleanOrNull
    ?: throw IllegalArgumentException("Savings field $key must be a boolean")

data class SavingsGoalSummary(val activeCount:Int,val totalSavedMinor:Long,val nearestGoalName:String?)

fun savingsGoalSummary(rows:List<SavingsGoalRow>,reportingCurrency:String,rates:List<ExchangeRateSnapshot>):SavingsGoalSummary {
    val total=rows.fold(BigInteger.ZERO) { sum,row ->
        sum.add(planningMoneyMinorExact(row.goal.currentSavedMinor,row.goal.currencyCode,reportingCurrency,rates))
    }.max(BigInteger.valueOf(Long.MIN_VALUE)).min(BigInteger.valueOf(Long.MAX_VALUE)).toLong()
    val nearest=rows.maxWithOrNull { a,b ->
        fun ratio(goal:SavingsGoalRecord)=if(goal.targetMinor>0) BigInteger.valueOf(goal.currentSavedMinor) to BigInteger.valueOf(goal.targetMinor) else BigInteger.ZERO to BigInteger.ONE
        val (an,ad)=ratio(a.goal);val (bn,bd)=ratio(b.goal)
        val progress=an.multiply(bd).compareTo(bn.multiply(ad))
        if(progress!=0) progress else Instant.parse(b.goal.targetDate).compareTo(Instant.parse(a.goal.targetDate))
    }?.goal?.name
    return SavingsGoalSummary(rows.size,total,nearest)
}
