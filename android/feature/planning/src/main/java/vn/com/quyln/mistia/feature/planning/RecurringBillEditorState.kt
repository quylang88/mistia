package vn.com.quyln.mistia.feature.planning

import androidx.compose.runtime.saveable.Saver
import androidx.compose.runtime.saveable.listSaver
import java.time.Instant
import java.math.BigDecimal
import java.math.RoundingMode
import java.util.Currency
import java.time.LocalDate
import java.time.ZoneId
import vn.com.quyln.mistia.core.model.*

data class RecurringBillEditorState(
    val id:String?,val name:String,val categoryId:String?,val amountText:String,val paymentWalletId:String?,val currencyCode:String,
    val scheduleKind:BillScheduleKind,val paymentStartDay:Int,val dueDay:Int,val hasDeadline:Boolean,
    val paymentStartDate:String,val dueDate:String,val autoPayEnabled:Boolean,val autoPayDay:Int,val autoPayDate:String,
    val frequencyMonths:Int,val startsNextMonth:Boolean,
) {
    fun withAmount(text: String) = copy(amountText = planningAmountInput(text, currencyCode))
    val autoPayDayOptions:List<Int> get()=when {
        !hasDeadline || dueDay==paymentStartDay -> listOf(paymentStartDay)
        dueDay>paymentStartDay -> (paymentStartDay..dueDay).toList()
        else -> (paymentStartDay..31).toList()+(1..dueDay).toList()
    }
    fun normalizedAutoPay():RecurringBillEditorState = if(scheduleKind==BillScheduleKind.RECURRING) {
        copy(autoPayDay=autoPayDay.takeIf {it in autoPayDayOptions} ?: paymentStartDay)
    } else {
        val start=LocalDate.parse(paymentStartDate)
        val rawEnd=LocalDate.parse(dueDate)
        val end=if(hasDeadline && rawEnd>=start) rawEnd else start
        copy(autoPayDate=LocalDate.parse(autoPayDate).coerceIn(start,end).toString())
    }
    fun withPaymentStartDate(date:LocalDate):RecurringBillEditorState {
        val next=copy(paymentStartDate=date.toString())
        if(scheduleKind!=BillScheduleKind.ONE_TIME) return next.normalizedAutoPay()
        val old=LocalDate.parse(paymentStartDate)
        val due=LocalDate.parse(dueDate)
        val auto=LocalDate.parse(autoPayDate)
        return next.copy(
            dueDate=if(!hasDeadline || due==old || due<date) date.toString() else dueDate,
            autoPayDate=if(!autoPayEnabled || auto==old || auto<date) date.toString() else autoPayDate,
        ).normalizedAutoPay()
    }
    fun withCurrency(code:String):RecurringBillEditorState =
        if(id!=null || code==currencyCode) this else copy(currencyCode=code,amountText="")
    fun toDraft(zone:ZoneId):RecurringBillDraft {
        fun fail(reason:RecurringBillValidationError):Nothing=throw RecurringBillValidationException(reason)
        val trimmed=name.trim().takeIf {it.isNotEmpty()} ?: fail(RecurringBillValidationError.NAME_REQUIRED)
        if(categoryId==null) fail(RecurringBillValidationError.CATEGORY_REQUIRED)
        if(paymentWalletId==null) fail(RecurringBillValidationError.WALLET_REQUIRED)
        val amount=if(amountText.isBlank()) null else runCatching {
            BigDecimal(amountText.trim().replace(",",""))
                .movePointRight(Currency.getInstance(currencyCode).defaultFractionDigits.coerceAtLeast(0))
                .setScale(0,RoundingMode.UNNECESSARY).longValueExact()
        }.getOrElse {throw IllegalArgumentException("Invalid bill amount",it)}
        val recurring=scheduleKind==BillScheduleKind.RECURRING
        if(recurring && (paymentStartDay !in 1..31 || (hasDeadline && dueDay !in 1..31) || frequencyMonths<1))
            fail(RecurringBillValidationError.INVALID_SCHEDULE)
        val normalized=normalizedAutoPay()
        fun timestamp(day:String)=LocalDate.parse(day).atStartOfDay(zone).toInstant().toString()
        if(!recurring && hasDeadline && LocalDate.parse(dueDate)<LocalDate.parse(paymentStartDate))
            fail(RecurringBillValidationError.DEADLINE_BEFORE_START)
        return RecurringBillDraft(name=trimmed,categoryId=categoryId,amountMinor=amount,paymentWalletId=paymentWalletId,
            currencyCode=currencyCode,id=id,editingExisting=id!=null,scheduleKind=scheduleKind,
            paymentStartDay=paymentStartDay,dueDay=dueDay,hasDeadline=hasDeadline,
            paymentStartDate=if(recurring) null else timestamp(paymentStartDate),
            dueDate=if(recurring) null else timestamp(dueDate),autoPayEnabled=autoPayEnabled,
            autoPayDay=if(recurring && autoPayEnabled) normalized.autoPayDay else null,
            autoPayDate=if(!recurring && autoPayEnabled) timestamp(normalized.autoPayDate) else null,
            frequencyMonths=if(recurring) frequencyMonths else 1,startsNextMonth=startsNextMonth,zoneId=zone)
    }
    companion object {
        fun scopedSaver(owner:String,recordId:String?,currency:String):Saver<RecurringBillEditorState,Any> = Saver(
            save={state ->
                if(state.id!=recordId || state.currencyCode!=currency) null
                else with(saver(owner)) {save(state)}?.let {listOf(owner,recordId.orEmpty(),currency,it)}
            },
            restore={value ->
                val items=value as? List<*>
                if(items?.size!=4 || items[0]!=owner || items[1]!=recordId.orEmpty() || items[2]!=currency) null
                else items[3]?.let {raw -> runCatching {
                    saver(owner).restore(raw)?.also {state ->
                        LocalDate.parse(state.paymentStartDate);LocalDate.parse(state.dueDate);LocalDate.parse(state.autoPayDate)
                        require(state.paymentStartDay in 1..31 && state.dueDay in 1..31 && state.autoPayDay in 1..31 && state.frequencyMonths>=1)
                    }
                }.getOrNull()}?.takeIf {it.id==recordId && it.currencyCode==currency}
            },
        )
        fun fresh(today:LocalDate,currency:String)=RecurringBillEditorState(null,"",null,"",null,currency,
            BillScheduleKind.RECURRING,10,10,false,today.toString(),today.toString(),false,10,today.toString(),1,false)
        fun from(bill:RecurringBillPlanRecord,today:LocalDate,zone:ZoneId):RecurringBillEditorState {
            fun day(timestamp:String?)=timestamp?.let {Instant.parse(it).atZone(zone).toLocalDate().toString()} ?: today.toString()
            val digits=Currency.getInstance(bill.currencyCode).defaultFractionDigits.coerceAtLeast(0)
            val start=day(bill.paymentStartDate)
            return RecurringBillEditorState(bill.id,bill.name,bill.categoryId,
                planningAmountInput(bill.amountMinor?.let {BigDecimal.valueOf(it,digits).stripTrailingZeros().toPlainString()}.orEmpty(), bill.currencyCode),
                bill.paymentWalletId,bill.currencyCode,bill.scheduleKind,bill.resolvedPaymentStartDay,bill.dueDay,
                bill.resolvedHasExplicitDueDate(zone),start,bill.dueDate?.let(::day) ?: start,
                bill.autoPayEnabled==true,bill.autoPayDay ?: bill.resolvedPaymentStartDay,
                bill.autoPayDate?.let(::day) ?: start,bill.frequencyMonths.coerceAtLeast(1),false)
        }
        fun saver(owner:String)=listSaver<RecurringBillEditorState,Any>(
            save={listOf(owner,it.id.orEmpty(),it.name,it.categoryId.orEmpty(),it.amountText,it.paymentWalletId.orEmpty(),it.currencyCode,
                it.scheduleKind.name,it.paymentStartDay,it.dueDay,it.hasDeadline,it.paymentStartDate,it.dueDate,
                it.autoPayEnabled,it.autoPayDay,it.autoPayDate,it.frequencyMonths,it.startsNextMonth)},
            restore={ values -> runCatching {
                if(values.size!=18 || values[0]!=owner) return@runCatching null
                RecurringBillEditorState((values[1] as String).ifEmpty {null},values[2] as String,
                    (values[3] as String).ifEmpty {null},values[4] as String,(values[5] as String).ifEmpty {null},values[6] as String,
                    BillScheduleKind.valueOf(values[7] as String),values[8] as Int,values[9] as Int,values[10] as Boolean,
                    values[11] as String,values[12] as String,values[13] as Boolean,values[14] as Int,values[15] as String,
                    values[16] as Int,values[17] as Boolean)
            }.getOrNull()},
        )
    }
}

data class RecurringBillNavigationState(val owner:String,val open:Boolean,val payload:String?) {
    fun bill():RecurringBillPlanRecord?=runCatching {
        val json=kotlinx.serialization.json.Json.parseToJsonElement(requireNotNull(payload)) as kotlinx.serialization.json.JsonObject
        val id=(json["id"] as kotlinx.serialization.json.JsonPrimitive).content
        RecurringBillPlanRecord.fromCloudRecord(CloudRecord(CloudEntity.RECURRING_BILL_PLAN.table,id,owner,json,null,null,0)).takeIf {it.ownerUserId==owner && !it.isArchived && it.deletedAt==null}
    }.getOrNull()
    companion object {
        fun saver(owner:String)=listSaver<RecurringBillNavigationState,Any>(
            save={listOf(it.owner,it.open,it.payload.orEmpty())},
            restore={values -> if(values.size!=3 || values[0]!=owner) null else RecurringBillNavigationState(owner,values[1] as Boolean,(values[2] as String).ifEmpty {null})},
        )
    }
}
