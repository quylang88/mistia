package vn.com.quyln.mistia.core.model

import java.time.Instant
import java.time.YearMonth
import java.time.ZoneId
import java.util.Locale

data class UpcomingRecurringDueAlert(val id:String,val ownerUserId:String,val sourceKind:DueSourceKind,val sourceId:String,val month:YearMonth,
    val name:String,val icon:String,val amountMinor:Long?,val currencyCode:String,val alertDate:Instant,val dayDelta:Int) {
    val requiresAmountInput:Boolean get()=amountMinor==null
    val urgent:Boolean get()=dayDelta<=3
}

/** Strict personal source admission, separate from payment/editor payloads. */
data class UpcomingDueReadSources(val bills:List<RecurringBillPlanRecord>,val installments:List<InstallmentPlanRecord>,val occurrences:List<DueOccurrenceRecord>)

fun upcomingDueReadSources(owner:UserId,snapshot:UpcomingDueReadSnapshot?):UpcomingDueReadSources? {
    if(snapshot==null || snapshot.owner!=owner) return null
    return runCatching {
        fun rows(entity:CloudEntity)=snapshot.records(entity).filter {it.financeRawIdentity(owner,entity,requireBodyIdentity=true)}.distinctBy {financeRawUuid(it.id)}
        fun activeSource(row:CloudRecord):Boolean {
            val deleted=row.financeRawDeleted(requireTimestamp=true);val archived=row.payload.financeRawArchived()
            if(deleted==true || archived==true) return false
            require(deleted==false && archived==false) {"Unreadable due source eligibility"}
            return true
        }
        fun code(value:String):String {
            val normalized=requireNotNull(value.financeReportingCode()) {"Unreadable due currency"}
            java.util.Currency.getInstance(normalized)
            return normalized
        }
        val bills=rows(CloudEntity.RECURRING_BILL_PLAN).filter(::activeSource).map {raw ->
            val source=RecurringBillPlanRecord.fromCloudRecord(raw)
            require(source.scheduleKindWireValue==null || source.scheduleKindWireValue in setOf("recurring","oneTime")) {"Unknown bill schedule"}
            code(source.currencyCode);source
        }
        val installments=rows(CloudEntity.INSTALLMENT_PLAN).filter(::activeSource).map {raw ->
            InstallmentPlanRecord.fromCloudRecord(raw).also {code(it.currencyCode)}
        }
        val occurrences=if(bills.isEmpty() && installments.isEmpty()) emptyList() else rows(CloudEntity.DUE_OCCURRENCE_RECORD).mapNotNull {raw ->
            when(raw.financeRawDeleted(requireTimestamp=true)) {
                true -> return@mapNotNull null
                null -> error("Unreadable cycle deletion")
                false -> Unit
            }
            val kind=raw.payload.financeRawString("source_kind_raw_value")
            if(kind==DueSourceKind.CREDIT_CARD.wireValue) return@mapNotNull null
            require(kind in setOf(DueSourceKind.RECURRING_BILL.wireValue,DueSourceKind.INSTALLMENT.wireValue)) {"Unknown due source"}
            require(raw.payload.financeRawString("status_raw_value") in DueStatus.entries.map {it.wireValue}) {"Unknown due status"}
            DueOccurrenceRecord.fromCloudRecord(raw).also {YearMonth.parse(it.selectedMonthKey)}
        }
        UpcomingDueReadSources(bills,installments,occurrences)
    }.getOrNull()
}

/** Calendar-window selection follows Swift OverviewLogic, without converting individual source money. */
fun projectUpcomingRecurringDues(owner:UserId,snapshot:UpcomingDueReadSnapshot?,reference:Instant,zone:ZoneId,locale:Locale=Locale.getDefault()):List<UpcomingRecurringDueAlert>? {
    val sources=upcomingDueReadSources(owner,snapshot) ?: return null
    return runCatching {
        val current=YearMonth.from(reference.atZone(zone));val today=reference.atZone(zone).toLocalDate()
        val alerts=mutableListOf<UpcomingRecurringDueAlert>()
        fun add(kind:DueSourceKind,id:String,month:YearMonth,name:String,icon:String,amount:Long?,currency:String,date:Instant) {
            val days=java.time.temporal.ChronoUnit.DAYS.between(today,date.atZone(zone).toLocalDate())
            if(days !in 0L..7L) return
            alerts+=UpcomingRecurringDueAlert("${kind.wireValue}-$id-$month",owner.value,kind,id,month,name,icon,amount,
                requireNotNull(currency.financeReportingCode()),date,days.toInt())
        }
        for(month in listOf(current.minusMonths(1),current)) {
            for(row in recurringBillDueRows(owner,sources.bills,sources.occurrences,month,zone)) {
                if(row.status!=DueStatus.PENDING) continue
                val date=if(today<row.paymentStartDate.atZone(zone).toLocalDate()) row.paymentStartDate else row.dueDate
                add(DueSourceKind.RECURRING_BILL,row.bill.id,month,row.bill.name,row.bill.iconSymbolName,row.amountMinor,row.bill.currencyCode,date)
            }
        }
        for(row in installmentDueRows(owner,sources.installments,sources.occurrences,current,zone)) {
            if(row.status==DueStatus.PENDING) add(DueSourceKind.INSTALLMENT,row.plan.id,current,row.plan.name,row.plan.iconSymbolName,row.amountMinor,row.plan.currencyCode,row.dueDate)
        }
        val collator=java.text.Collator.getInstance(locale).apply {strength=java.text.Collator.SECONDARY;decomposition=java.text.Collator.CANONICAL_DECOMPOSITION}
        alerts.sortedWith {a,b ->a.alertDate.compareTo(b.alertDate).takeIf {it!=0} ?: collator.compare(a.name,b.name)}.take(3)
    }.getOrNull()
}
