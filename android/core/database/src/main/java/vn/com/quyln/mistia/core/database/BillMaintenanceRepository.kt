package vn.com.quyln.mistia.core.database

import java.time.Instant
import java.time.ZoneId
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.JsonPrimitive
import vn.com.quyln.mistia.core.model.*

/** Executes local money and optionally persists current notification reminders/failures. */
internal class OfflineBillMaintenanceRepository(private val store:LocalStore,private val zone:ZoneId,
    private val payments:BillPaymentRepository,private val notificationText:((BillNotificationMessage)->BillNotificationText)?=null):BillMaintenanceRepository {
    private val mutex=Mutex()
    override suspend fun maintainRecurringBills(owner:UserId,deviceId:String,now:String):Result<BillMaintenanceReport> = try {
        Result.success(mutex.withLock {
            UUID.fromString(owner.value);UUID.fromString(deviceId)
            val reference=Instant.parse(now)
            val outcomes=mutableListOf<BillAutomaticPaymentResult>()
            for(event in events(owner,reference).filter {it.kind==BillMaintenanceEventKind.AUTO_PAY}) {
                currentCoroutineContext().ensureActive()
                val result=payments.payRecurringBill(owner,BillPaymentRequest(RecordId(event.due.bill.id),event.month,automatic=true),deviceId,now)
                result.exceptionOrNull()?.let {if(it is CancellationException) throw it}
                outcomes+=BillAutomaticPaymentResult(event,result)
            }
            currentCoroutineContext().ensureActive()
            // A manual payment/skip can win while an auto attempt is in flight.
            // Re-read statuses rather than sending reminders from the old plan.
            val report=BillMaintenanceReport(outcomes,events(owner,reference).filter {it.kind!=BillMaintenanceEventKind.AUTO_PAY})
            notificationText?.let {OfflineBillNotificationRepository(store,zone,it).persist(owner,report,reference)}
            report
        })
    } catch(cancelled:CancellationException) {throw cancelled}
      catch(error:Exception) {Result.failure(error)}

    private suspend fun events(owner:UserId,reference:Instant):List<BillMaintenanceEvent> {
        suspend fun owned(entity:CloudEntity)=store.recordsIncludingDeleted(owner,entity.table).filter {row ->
            require(row.ownerUserId==owner.value && row.entity==entity.table)
            require((row.payload["id"] as? JsonPrimitive)?.content==row.id)
            val payloadOwner=requireNotNull((row.payload["user_id"] as? JsonPrimitive)?.content)
            UUID.fromString(payloadOwner)
            payloadOwner==owner.value
        }
        val bills=owned(CloudEntity.RECURRING_BILL_PLAN).map(RecurringBillPlanRecord::fromCloudRecord)
        val occurrences=owned(CloudEntity.DUE_OCCURRENCE_RECORD).map(DueOccurrenceRecord::fromCloudRecord)
        return recurringBillMaintenanceEvents(owner,bills,occurrences,reference,zone)
    }
}
