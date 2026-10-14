package vn.com.quyln.mistia.core.model

import java.time.Instant
import java.time.YearMonth
import java.time.ZoneId

enum class BillMaintenanceEventKind { AUTO_PAY, PAYMENT_START, DEADLINE, OVERDUE }
data class BillMaintenanceEvent(val key:String,val kind:BillMaintenanceEventKind,val month:YearMonth,val due:RecurringBillDueRow)
fun recurringBillMaintenanceEvents(owner:UserId,bills:List<RecurringBillPlanRecord>,occurrences:List<DueOccurrenceRecord>,reference:Instant,zone:ZoneId):List<BillMaintenanceEvent> {
    val current=YearMonth.from(reference.atZone(zone))
    val today=reference.atZone(zone).toLocalDate()
    val eligible=bills.filter {it.ownerUserId==owner.value && it.deletedAt==null && !it.isPaused && !it.isArchived}
    return listOf(current.minusMonths(1),current).flatMap {month ->
        recurringBillDueRows(owner,eligible,occurrences,month,zone).filter {it.status==DueStatus.PENDING}.flatMap {due ->
            val cycle=YearMonth.from(due.paymentStartDate.atZone(zone))
            val id=due.bill.id.lowercase()
            buildList {
                if(due.bill.autoPayEnabled==true && due.autoPayDate?.atZone(zone)?.toLocalDate()==today)
                    add(BillMaintenanceEvent("mistia.bill.autopay.attempt.$id.$cycle",BillMaintenanceEventKind.AUTO_PAY,cycle,due))
                val start=due.paymentStartDate.atZone(zone).toLocalDate()==today
                val deadline=due.hasExplicitDueDate && due.dueDate.atZone(zone).toLocalDate()==today
                if(start || deadline) {
                    val phase=if(deadline) "deadline" else "start"
                    add(BillMaintenanceEvent("mistia.bill.payment.$phase.$id.$cycle",
                        if(deadline) BillMaintenanceEventKind.DEADLINE else BillMaintenanceEventKind.PAYMENT_START,cycle,due))
                }
                if(due.dueDate.atZone(zone).toLocalDate()<today)
                    add(BillMaintenanceEvent("mistia.bill.overdue.$id.$cycle.$today",BillMaintenanceEventKind.OVERDUE,cycle,due))
            }
        }
    }
}
