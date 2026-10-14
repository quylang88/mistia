package vn.com.quyln.mistia.core.model

import java.time.Instant
import java.time.YearMonth
import java.time.ZoneId
import java.util.UUID
import kotlinx.serialization.json.*

data class BillNotificationSnapshot(val owner:UserId,val bills:List<CloudRecord>,val occurrences:List<CloudRecord>,val notifications:List<AppNotificationRecord>)
data class BillNotificationMessage(val kind:String,val event:BillMaintenanceEvent,val failure:Throwable?=null)
data class BillNotificationText(val title:String,val body:String)

fun BillNotificationSnapshot.requireUnchangedBillNotifications(current:BillNotificationSnapshot) {
    fun validate(snapshot:BillNotificationSnapshot) {
        UUID.fromString(snapshot.owner.value)
        listOf(CloudEntity.RECURRING_BILL_PLAN to snapshot.bills,CloudEntity.DUE_OCCURRENCE_RECORD to snapshot.occurrences).forEach {(entity,rows) ->
            require(rows.all {it.entity==entity.table && it.ownerUserId==snapshot.owner.value})
            require(rows.map {it.id}.distinct().size==rows.size)
        }
        require(snapshot.notifications.map {it.key}.distinct().size==snapshot.notifications.size)
        snapshot.notifications.forEach {it.requireValidLocalNotification();require(it.ownerUserId==snapshot.owner.value)}
    }
    validate(this);validate(current)
    require(owner==current.owner && bills.associateBy {it.id}==current.bills.associateBy {it.id} &&
        occurrences.associateBy {it.id}==current.occurrences.associateBy {it.id} &&
        notifications.associateBy {it.key}==current.notifications.associateBy {it.key}) {"Bill notification dependencies changed"}
}

/** Uses fresh bill/cycle rows rather than stale report reminders. */
fun planBillNotifications(snapshot:BillNotificationSnapshot,report:BillMaintenanceReport,reference:Instant,zone:ZoneId,
    text:(BillNotificationMessage)->BillNotificationText):List<AppNotificationRecord> {
    snapshot.requireUnchangedBillNotifications(snapshot)
    val owner=snapshot.owner
    fun owned(rows:List<CloudRecord>)=rows.filter {row ->
        require(row.payload["id"]==JsonPrimitive(row.id))
        val payloadOwner=requireNotNull((row.payload["user_id"] as? JsonPrimitive)?.contentOrNull)
        UUID.fromString(payloadOwner)
        payloadOwner==owner.value
    }
    val bills=owned(snapshot.bills).map(RecurringBillPlanRecord::fromCloudRecord)
    val occurrences=owned(snapshot.occurrences).map(DueOccurrenceRecord::fromCloudRecord)
    val events=recurringBillMaintenanceEvents(owner,bills,occurrences,reference,zone)
    var result=snapshot.notifications
    for(row in snapshot.notifications) {
        if(row.resourceType!="bill" || row.resourceId==null || row.kind !in setOf("billPaymentRequired","billAutoPaymentFailed","billOverdue")) continue
        val bill=bills.singleOrNull {it.id==row.resourceId}
        if(bill==null || bill.deletedAt!=null || bill.isArchived || bill.isPaused) {
            result=resolveLocalBillNotifications(owner,result,row.resourceId,null,reference.toString());continue
        }
        val month=(row.metadata?.get("dueMonthKey") as? JsonPrimitive)?.contentOrNull?.let {runCatching {YearMonth.parse(it)}.getOrNull()} ?: continue
        val due=recurringBillDueRows(owner,listOf(bill),occurrences,month,zone).singleOrNull()
        if(due==null || due.status in setOf(DueStatus.PAID,DueStatus.SKIPPED))
            result=resolveLocalBillNotifications(owner,result,bill.id,month.toString(),reference.toString())
    }
    val messages=events.filter {it.kind!=BillMaintenanceEventKind.AUTO_PAY}.map {event ->
        BillNotificationMessage(if(event.kind==BillMaintenanceEventKind.OVERDUE) "billOverdue" else "billPaymentRequired",event)
    }+report.payments.mapNotNull {payment ->
        val error=payment.result.exceptionOrNull() ?: return@mapNotNull null
        val current=events.singleOrNull {it.kind==BillMaintenanceEventKind.AUTO_PAY && it==payment.event} ?: return@mapNotNull null
        BillNotificationMessage("billAutoPaymentFailed",current,error)
    }
    val byKey=result.associateBy {it.key}.toMutableMap()
    for(message in messages) {
        val event=message.event;val bill=event.due.bill
        val key=if(message.kind=="billAutoPaymentFailed") "mistia.bill.autopay.failed.${bill.id.lowercase()}.${event.month}" else event.key
        val copy=text(message)
        val incoming=AppNotificationRecord(owner.value,key,copy.title,copy.body,message.kind,resourceType="bill",resourceId=bill.id,
            createdAt=reference.toString(),updatedAt=reference.toString(),metadata=buildJsonObject {
                put("sourceKind","recurringBill");put("sourceId",bill.id);put("dueMonthKey",event.month.toString());put("dueDate",event.due.dueDate.toString())
                put("requiresAmountInput",event.due.amountMinor==null);put("currencyCode",bill.currencyCode);put("billName",bill.name)
                put("linkedPaymentWalletId",bill.paymentWalletId?.let(::JsonPrimitive) ?: JsonNull)
            })
        byKey[key]=upsertLocalNotification(byKey[key],incoming)
    }
    return byKey.values.toList()
}

fun resolveTerminalBillWriteNotifications(bill:CloudRecord,month:String,writes:List<CloudRecord>,rows:List<AppNotificationRecord>,now:String):List<AppNotificationRecord> {
    require(bill.entity==CloudEntity.RECURRING_BILL_PLAN.table)
    if(bill.payload["user_id"]!=JsonPrimitive(bill.ownerUserId) || bill.payload["id"]!=JsonPrimitive(bill.id)) return rows
    val terminal=billCycleRecords(writes,bill,month).any {it.deletedAt==null && it.payload["user_id"]==JsonPrimitive(bill.ownerUserId) &&
        (it.payload["status_raw_value"] as? JsonPrimitive)?.content in setOf("paid","skipped")}
    return if(terminal) resolveLocalBillNotifications(UserId(bill.ownerUserId),rows,bill.id,month,now) else rows
}
