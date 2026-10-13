package vn.com.quyln.mistia.core.model

import java.time.Instant
import java.time.YearMonth
import java.time.ZoneId
import java.util.Locale
import java.util.UUID
import kotlinx.coroutines.flow.Flow

interface RecurringBillRepository {
    /** Includes archived bills to preserve paid history in monthly projections. */
    fun observeRecurringBills(ownerUserId:UserId):Flow<List<RecurringBillPlanRecord>>
    fun observeDueOccurrences(ownerUserId:UserId):Flow<List<DueOccurrenceRecord>>
    suspend fun skipRecurringBill(ownerUserId:UserId,id:RecordId,month:YearMonth,deviceId:String,now:String):Result<DueOccurrenceRecord> = Result.failure(UnsupportedOperationException("Bill skip unavailable"))
    suspend fun undoRecurringBillSkip(ownerUserId:UserId,id:RecordId,month:YearMonth,deviceId:String,now:String):Result<Unit> = Result.failure(UnsupportedOperationException("Bill undo skip unavailable"))
    suspend fun saveRecurringBill(ownerUserId:UserId,draft:RecurringBillDraft,deviceId:String,now:String):Result<RecurringBillPlanRecord>
    suspend fun pauseRecurringBill(ownerUserId:UserId,id:RecordId,deviceId:String,now:String):Result<Unit>
    suspend fun resumeRecurringBill(ownerUserId:UserId,id:RecordId,deviceId:String,now:String):Result<Unit>
    suspend fun archiveRecurringBill(ownerUserId:UserId,id:RecordId,deviceId:String,now:String):Result<Unit>
}

data class RecurringBillDraft(
    val name:String,
    val categoryId:String?,
    val amountMinor:Long?,
    val paymentWalletId:String?,
    val currencyCode:String,
    val id:String?=null,
    val editingExisting:Boolean=false,
    val scheduleKind:BillScheduleKind=BillScheduleKind.RECURRING,
    val paymentStartDay:Int=10,
    val dueDay:Int=10,
    val hasDeadline:Boolean=false,
    val paymentStartDate:String?=null,
    val dueDate:String?=null,
    val autoPayEnabled:Boolean=false,
    val autoPayDay:Int?=null,
    val autoPayDate:String?=null,
    val frequencyMonths:Int=1,
    val startsNextMonth:Boolean=false,
    val zoneId:ZoneId=ZoneId.systemDefault(),
)
enum class RecurringBillValidationError { WALLET_CURRENCY_MISMATCH, NAME_REQUIRED, CATEGORY_REQUIRED, INVALID_CATEGORY, WALLET_REQUIRED, INVALID_WALLET, INVALID_CURRENCY, INVALID_SCHEDULE, DEADLINE_BEFORE_START, NOT_FOUND, UNPAID_CYCLES }
class RecurringBillValidationException(val reason:RecurringBillValidationError):IllegalArgumentException(reason.name)

fun RecurringBillDraft.toBillRecord(owner:UserId,category:TransactionCategoryRecord,existing:RecurringBillPlanRecord?,deviceId:String,now:String):RecurringBillPlanRecord {
    fun fail(reason:RecurringBillValidationError):Nothing=throw RecurringBillValidationException(reason)
    require(category.ownerUserId==owner.value && (existing==null || existing.ownerUserId==owner.value))
    val trimmedName=name.trim().takeIf { it.isNotEmpty() } ?: fail(RecurringBillValidationError.NAME_REQUIRED)
    val currency=(existing?.currencyCode ?: currencyCode).trim().uppercase(Locale.ROOT)
    if(!Regex("[A-Z]{3}").matches(currency)) fail(RecurringBillValidationError.INVALID_CURRENCY)
    val recurring=scheduleKind==BillScheduleKind.RECURRING
    if(recurring && (paymentStartDay !in 1..31 || (hasDeadline && dueDay !in 1..31) || frequencyMonths<1)) fail(RecurringBillValidationError.INVALID_SCHEDULE)
    fun localDay(value:String)=Instant.parse(value).atZone(zoneId).toLocalDate()
    val start=if(recurring) null else (paymentStartDate?.let(::localDay) ?: fail(RecurringBillValidationError.INVALID_SCHEDULE))
    val rawDue=if(recurring) null else (dueDate?.let(::localDay) ?: start)
    if(!recurring && hasDeadline && rawDue!!<start!!) fail(RecurringBillValidationError.DEADLINE_BEFORE_START)
    val explicit=hasDeadline && if(recurring) dueDay!=paymentStartDay else rawDue!=start
    val effectiveDue=if(explicit) rawDue else start
    val normalizedStart=if(recurring) paymentStartDay else start!!.dayOfMonth
    val normalizedDue=if(recurring) (if(explicit) dueDay else paymentStartDay) else effectiveDue!!.dayOfMonth
    val allowedAutoDays=when {
        !recurring -> emptyList()
        !explicit -> listOf(paymentStartDay)
        dueDay>paymentStartDay -> (paymentStartDay..dueDay).toList()
        else -> (paymentStartDay..31).toList()+(1..dueDay).toList()
    }
    val normalizedAutoDay=if(recurring && autoPayEnabled) autoPayDay?.takeIf { it in allowedAutoDays } ?: paymentStartDay else null
    val normalizedAutoDate=if(!recurring && autoPayEnabled) {
        val candidate=autoPayDate?.let(::localDay) ?: start!!
        candidate.coerceIn(start!!,effectiveDue!!).atStartOfDay(zoneId).toInstant().toString()
    } else null
    val firstMonth=if(!recurring) null else if(existing!=null) existing.firstScheduledMonth else {
        val month=YearMonth.from(Instant.parse(now).atZone(zoneId)).plusMonths(if(startsNextMonth) 1 else 0)
        month.atDay(1).atStartOfDay(zoneId).toInstant().toString()
    }
    return RecurringBillPlanRecord(UUID.fromString(existing?.id ?: id ?: UUID.randomUUID().toString()).toString(),owner.value,trimmedName,
        category.iconSymbolName,category.id,amountMinor,normalizedDue,if(recurring) "recurring" else "oneTime",normalizedStart,
        start?.atStartOfDay(zoneId)?.toInstant()?.toString(),firstMonth,explicit,if(!recurring && explicit) effectiveDue?.atStartOfDay(zoneId)?.toInstant()?.toString() else null,
        autoPayEnabled,normalizedAutoDay,normalizedAutoDate,if(recurring) frequencyMonths else 1,paymentWalletId,currency,false,
        recurring && existing?.isPaused==true,if(recurring) existing?.pausedAt else null,if(recurring) existing?.resumeStartMonth else null,
        existing?.createdAt ?: now,now,null,existing?.syncVersion ?: 0,UUID.fromString(deviceId).toString())
}
fun RecurringBillPlanRecord.pendingMutation(kind:MutationKind=MutationKind.UPSERT)=PendingMutation(
    CloudEntity.RECURRING_BILL_PLAN,id,ownerUserId,kind,toPayload(),updatedAt,syncVersion,requireNotNull(lastModifiedByDeviceId))
fun DueOccurrenceRecord.pendingMutation(kind:MutationKind=MutationKind.UPSERT)=PendingMutation(
    CloudEntity.DUE_OCCURRENCE_RECORD,id,ownerUserId,kind,toPayload(),updatedAt,syncVersion,requireNotNull(lastModifiedByDeviceId))

/** Includes viewer-envelope rows for snapshot guards, but never grants mutation ownership. */
fun billCycleRecords(rows:List<CloudRecord>,bill:CloudRecord,monthKey:String):List<CloudRecord> = rows.filter {row ->
    row.entity==CloudEntity.DUE_OCCURRENCE_RECORD.table && row.ownerUserId==bill.ownerUserId &&
        (row.payload["source_kind_raw_value"] as? kotlinx.serialization.json.JsonPrimitive)?.content=="recurringBill" &&
        (row.payload["source_id"] as? kotlinx.serialization.json.JsonPrimitive)?.content==bill.id &&
        (row.payload["selected_month_key"] as? kotlinx.serialization.json.JsonPrimitive)?.content==monthKey
}.sortedBy {it.id}

/** Product rule shared with Swift: money may leave only a wallet in the bill currency. */
fun billPaymentCurrenciesMatch(billCurrency:String,walletCurrency:String):Boolean {
    val bill=billCurrency.trim().uppercase(Locale.ROOT)
    return bill.isNotEmpty() && bill==walletCurrency.trim().uppercase(Locale.ROOT)
}
