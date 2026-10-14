package vn.com.quyln.mistia.core.model

import java.time.Instant
import java.time.YearMonth
import java.time.ZoneId
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class BillNotificationsTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val zone=ZoneId.of("Asia/Tokyo")
    private val october=YearMonth.of(2026,10)
    private val reference=Instant.parse("2026-10-13T00:00:00Z")
    private fun bill()=RecurringBillPlanRecord("22222222-2222-2222-2222-222222222222",owner.value,"Internet","mistia.plan.bill",
        null,5000,10,"recurring",25,null,null,true,null,false,null,null,1,null,"JPY",false,false,null,null,
        "2026-01-01T00:00:00Z","2026-10-13T00:00:00Z",null,0,null)
    private fun occurrence(month:String="2026-10",status:String="pending")=DueOccurrenceRecord(
        "33333333-3333-3333-3333-333333333333",owner.value,"recurringBill",bill().id,month,"2026-10-24T15:00:00Z",123,status,
        null,null,reference.toString(),reference.toString(),null,0,null)
    private val date=Instant.parse("2026-10-10T00:00:00Z")
    private fun snapshot(value:RecurringBillPlanRecord=bill(),occurrences:List<DueOccurrenceRecord> = emptyList(),rows:List<AppNotificationRecord> = emptyList())=
        BillNotificationSnapshot(owner,listOf(value.toCloudRecord()),occurrences.map {it.toCloudRecord()},rows)
    private fun plan(snapshot:BillNotificationSnapshot,report:BillMaintenanceReport=BillMaintenanceReport(emptyList(),emptyList()),reference:Instant=date)=
        planBillNotifications(snapshot,report,reference,zone) {BillNotificationText(it.kind,it.event.due.amountMinor.toString())}
    @Test fun `batch recomputes current reminder keys and exact metadata from owned snapshots`() {
        val row=plan(snapshot()).single()
        assertEquals("mistia.bill.payment.deadline.${bill().id}.2026-09",row.key)
        assertEquals("billPaymentRequired",row.kind)
        assertEquals("2026-09",row.metadata!!["dueMonthKey"]!!.jsonPrimitive.content)
        assertEquals("JPY",row.metadata!!["currencyCode"]!!.jsonPrimitive.content)
        assertEquals(bill().id,row.resourceId)
        assertEquals(false,row.metadata!!["requiresAmountInput"]!!.jsonPrimitive.boolean)
    }
    @Test fun `fresh auto failure gets stable failure notification plus deadline reminder`() {
        val value=bill().copy(paymentStartDay=1,dueDay=10,autoPayEnabled=true,autoPayDay=10,firstScheduledMonth="2026-10-01T00:00:00Z")
        val events=recurringBillMaintenanceEvents(owner,listOf(value),emptyList(),date,zone)
        val failure=BillAutomaticPaymentResult(events.single {it.kind==BillMaintenanceEventKind.AUTO_PAY},Result.failure(BillPaymentException(BillPaymentError.WALLET_CURRENCY_MISMATCH)))
        val rows=plan(snapshot(value),BillMaintenanceReport(listOf(failure),emptyList()))
        assertEquals(setOf("billAutoPaymentFailed","billPaymentRequired"),rows.map {it.kind}.toSet())
        assertEquals("mistia.bill.autopay.failed.${value.id}.2026-10",rows.single {it.kind=="billAutoPaymentFailed"}.key)
    }
    @Test fun `stale auto failure and stale report reminders cannot recreate paid cycle alerts`() {
        val value=bill().copy(paymentStartDay=1,dueDay=10,autoPayEnabled=true,autoPayDay=10,firstScheduledMonth="2026-10-01T00:00:00Z")
        val events=recurringBillMaintenanceEvents(owner,listOf(value),emptyList(),date,zone)
        val failure=BillAutomaticPaymentResult(events.single {it.kind==BillMaintenanceEventKind.AUTO_PAY},Result.failure(IllegalArgumentException("old failure")))
        assertTrue(plan(snapshot(value,listOf(occurrence(status="paid"))),BillMaintenanceReport(listOf(failure),events)).isEmpty())
    }
    @Test fun `repeat batch preserves read state and exact amount snapshot`() {
        val value=bill().copy(paymentStartDay=1,dueDay=10,firstScheduledMonth="2026-10-01T00:00:00Z")
        val source=snapshot(value,listOf(occurrence().copy(amountMinorSnapshot=9007199254740993L)))
        val created=plan(source).single()
        val read=markLocalNotificationRead(created,date.toString())
        val updated=plan(source.copy(notifications=listOf(read))).single()
        assertTrue(updated.isRead);assertEquals(read.readAt,updated.readAt)
        assertEquals("9007199254740993",updated.body)
    }
    @Test fun `paid skipped paused archived and deleted bills resolve existing actionable rows only`() {
        val value=bill().copy(paymentStartDay=1,dueDay=10,firstScheduledMonth="2026-10-01T00:00:00Z")
        val reminder=plan(snapshot(value)).single()
        val success=reminder.copy(key="success",kind="billAutoPaymentSucceeded")
        for(source in listOf(snapshot(value,listOf(occurrence(status="paid"))),snapshot(value,listOf(occurrence(status="skipped"))),
            snapshot(value.copy(isPaused=true)),snapshot(value.copy(isArchived=true)),snapshot(value.copy(deletedAt=reference.toString())))) {
            val result=plan(source.copy(notifications=listOf(reminder,success)))
            assertTrue(result.single {it.key==reminder.key}.isRead)
            assertEquals("resolved",result.single {it.key==reminder.key}.actionState)
            assertEquals(success,result.single {it.key==success.key})
        }
    }
    @Test fun `viewer bills and other owner notification snapshots cannot create local alerts`() {
        val viewer=bill().copy(ownerUserId="99999999-9999-9999-9999-999999999999").toCloudRecord().copy(ownerUserId=owner.value)
        assertTrue(plan(snapshot().copy(bills=listOf(viewer))).isEmpty())
        val row=AppNotificationRecord("99999999-9999-9999-9999-999999999999","key","Title","Body","billOverdue",createdAt=date.toString(),updatedAt=date.toString())
        assertThrows(IllegalArgumentException::class.java) {plan(snapshot(rows=listOf(row)))}
    }    @Test fun `same clock cycle and notification read changes invalidate complete batch snapshot`() {
        val source=snapshot()
        val incoming=plan(source)
        val expected=source.copy(notifications=incoming)
        expected.requireUnchangedBillNotifications(expected.copy(bills=expected.bills.reversed()))
        assertThrows(IllegalArgumentException::class.java) {expected.requireUnchangedBillNotifications(expected.copy(
            notifications=incoming.map {markLocalNotificationRead(it,date.toString())}))}
        val bill=expected.bills.single().let {it.copy(payload=JsonObject(it.payload+("future" to JsonPrimitive(9007199254740993L))))}
        assertThrows(IllegalArgumentException::class.java) {expected.requireUnchangedBillNotifications(expected.copy(bills=listOf(bill)))}
        assertThrows(IllegalArgumentException::class.java) {expected.requireUnchangedBillNotifications(expected.copy(occurrences=listOf(occurrence(status="paid").toCloudRecord())))}
    }
    @Test fun `changed schedule resolves an old reminder that no longer has a payable cycle`() {
        val value=bill().copy(paymentStartDay=1,dueDay=10,firstScheduledMonth="2026-10-01T00:00:00Z")
        val reminder=plan(snapshot(value)).single()
        val changed=value.copy(firstScheduledMonth="2026-11-01T00:00:00Z")
        val result=plan(snapshot(changed,rows=listOf(reminder))).single()
        assertTrue(result.isRead);assertEquals("resolved",result.actionState)
    }

}
