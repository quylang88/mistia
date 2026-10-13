package vn.com.quyln.mistia.core.model

import java.text.Collator
import java.time.Instant
import java.time.YearMonth
import java.time.ZoneId
import java.time.temporal.ChronoUnit

data class RecurringBillDueRow(
    val bill:RecurringBillPlanRecord,
    val amountMinor:Long?,
    val paymentStartDate:Instant,
    val dueDate:Instant,
    val hasExplicitDueDate:Boolean,
    val autoPayDate:Instant?,
    val status:DueStatus,
    val linkedTransactionId:String?,
)

fun recurringBillDueRows(owner:UserId,bills:List<RecurringBillPlanRecord>,occurrences:List<DueOccurrenceRecord>,month:YearMonth,zone:ZoneId):List<RecurringBillDueRow> =
    bills.filter { it.ownerUserId==owner.value && it.deletedAt==null }.mapNotNull { bill ->
        makeBillDueRow(bill,preferredBillOccurrence(owner,bill.id,month,occurrences),month,zone)
    }.sortedWith { a,b ->
        val date=a.dueDate.compareTo(b.dueDate)
        if(date!=0) date else Collator.getInstance().apply { strength=Collator.SECONDARY }.compare(a.bill.name,b.bill.name)
    }

/** Skipped is still unpaid for archive eligibility, matching Swift. */
fun hasUnpaidBillCycles(owner:UserId,bill:RecurringBillPlanRecord,occurrences:List<DueOccurrenceRecord>,reference:Instant,zone:ZoneId):Boolean {
    if(bill.ownerUserId!=owner.value || bill.deletedAt!=null) return false
    val current=YearMonth.from(reference.atZone(zone))
    val first=if(bill.scheduleKind==BillScheduleKind.RECURRING) monthOf(bill.resumeStartMonth ?: bill.firstScheduledMonth ?: bill.createdAt,zone)
        else bill.paymentStartDate?.let { monthOf(it,zone) } ?: return false
    val last=if(bill.scheduleKind==BillScheduleKind.RECURRING && bill.isPaused && bill.pausedAt!=null) minOf(current,monthOf(bill.pausedAt,zone)) else current
    if(first>last) return false
    var month=first
    while(month<=last) {
        val row=makeBillDueRow(bill,preferredBillOccurrence(owner,bill.id,month,occurrences),month,zone,ignoresPause=true)
        if(row!=null && row.status!=DueStatus.PAID) return true
        if(bill.scheduleKind==BillScheduleKind.ONE_TIME) break
        month=month.plusMonths(bill.frequencyMonths.coerceAtLeast(1).toLong())
    }
    return false
}

private fun preferredBillOccurrence(owner:UserId,id:String,month:YearMonth,occurrences:List<DueOccurrenceRecord>):DueOccurrenceRecord? {
    val eligible=occurrences.filter { it.ownerUserId==owner.value && it.deletedAt==null && it.sourceKind==DueSourceKind.RECURRING_BILL &&
        it.sourceId==id && it.selectedMonthKey==month.toString() }
    return eligible.firstOrNull { it.status!=DueStatus.PENDING } ?: eligible.firstOrNull()
}
private data class BillWindow(val start:Instant,val due:Instant,val explicit:Boolean,val auto:Instant?)
private fun makeBillDueRow(bill:RecurringBillPlanRecord,occurrence:DueOccurrenceRecord?,month:YearMonth,zone:ZoneId,ignoresPause:Boolean=false):RecurringBillDueRow? {
    val archivedPaid=bill.isArchived && occurrence?.status==DueStatus.PAID
    if(bill.isArchived && !archivedPaid) return null
    val window=billWindow(bill,month,zone,ignoresPause || archivedPaid,archivedPaid) ?: return null
    return RecurringBillDueRow(bill,occurrence?.amountMinorSnapshot ?: bill.amountMinor,window.start,window.due,window.explicit,window.auto,
        occurrence?.status ?: DueStatus.PENDING,occurrence?.linkedTransactionId)
}
private fun billWindow(bill:RecurringBillPlanRecord,month:YearMonth,zone:ZoneId,ignoresPause:Boolean,assumesScheduled:Boolean):BillWindow? {
    if(bill.scheduleKind==BillScheduleKind.ONE_TIME) {
        val start=bill.paymentStartDate?.let(Instant::parse) ?: return null
        if(!assumesScheduled && YearMonth.from(start.atZone(zone))!=month) return null
        val explicit=bill.resolvedHasExplicitDueDate(zone)
        val due=if(explicit) Instant.parse(bill.dueDate) else start
        val auto=if(bill.autoPayEnabled==true) normalizeAuto(bill.autoPayDate?.let(Instant::parse),start,due,zone) else null
        return BillWindow(start,due,explicit,auto)
    }
    if(bill.isPaused && !ignoresPause) return null
    val anchor=monthOf(bill.resumeStartMonth ?: bill.firstScheduledMonth ?: bill.createdAt,zone)
    val delta=ChronoUnit.MONTHS.between(anchor,month)
    if(!assumesScheduled && (delta<0 || delta%bill.frequencyMonths.coerceAtLeast(1)!=0L)) return null
    val startDay=bill.resolvedPaymentStartDay
    val start=scheduledBillDate(startDay,month,zone)
    val explicit=bill.resolvedHasExplicitDueDate(zone)
    val due=if(explicit) scheduledBillDate(bill.dueDay,if(bill.dueDay<startDay) month.plusMonths(1) else month,zone) else start
    val auto=if(bill.autoPayEnabled!=true) null else if(!explicit || bill.autoPayDay==null) start else {
        val autoMonth=if(bill.dueDay<startDay && bill.autoPayDay<startDay) month.plusMonths(1) else month
        normalizeAuto(scheduledBillDate(bill.autoPayDay,autoMonth,zone),start,due,zone)
    }
    return BillWindow(start,due,explicit,auto)
}
private fun normalizeAuto(candidate:Instant?,start:Instant,due:Instant,zone:ZoneId):Instant {
    if(candidate==null) return start
    val day=candidate.atZone(zone).toLocalDate()
    if(day<start.atZone(zone).toLocalDate() || day>due.atZone(zone).toLocalDate()) return start
    return day.atStartOfDay(zone).toInstant()
}
private fun scheduledBillDate(day:Int,month:YearMonth,zone:ZoneId):Instant=month.atDay(day.coerceIn(1,month.lengthOfMonth())).atStartOfDay(zone).toInstant()
private fun monthOf(value:String,zone:ZoneId):YearMonth=YearMonth.from(Instant.parse(value).atZone(zone))
