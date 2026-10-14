package vn.com.quyln.mistia.core.model

import java.time.Instant
import java.time.YearMonth
import java.time.ZoneId
import org.junit.Assert.*
import org.junit.Test

class BillMaintenanceTest {
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
    private fun events(value:RecurringBillPlanRecord=bill(),date:String="2026-10-10T00:00:00Z",occurrences:List<DueOccurrenceRecord> = emptyList())=
        recurringBillMaintenanceEvents(owner,listOf(value),occurrences,Instant.parse(date),zone)
    @Test fun `previous month deadline uses previous cycle key and current month is not notified early`() {
        val event=events().single()
        assertEquals(BillMaintenanceEventKind.DEADLINE,event.kind)
        assertEquals(YearMonth.of(2026,9),event.month)
        assertEquals("mistia.bill.payment.deadline.${bill().id}.2026-09",event.key)
    }
    @Test fun `payment start and normalized auto pay produce separate stable intents`() {
        val value=bill().copy(autoPayEnabled=true,autoPayDay=25,hasExplicitDueDate=false)
        val result=events(value,"2026-10-25T00:00:00Z")
        val current=result.filter {it.month==october}
        assertEquals(listOf(BillMaintenanceEventKind.AUTO_PAY,BillMaintenanceEventKind.PAYMENT_START),current.map {it.kind})
        assertEquals("mistia.bill.autopay.attempt.${value.id}.2026-10",current.first().key)
        assertEquals("mistia.bill.payment.start.${value.id}.2026-10",current.last().key)
    }
    @Test fun `overdue resurfaces by local date and keeps exact amount snapshot`() {
        val value=bill().copy(paymentStartDay=1,dueDay=10)
        val result=events(value,"2026-10-12T15:00:00Z",listOf(occurrence().copy(amountMinorSnapshot=9007199254740993L)))
        val event=result.single {it.month==october}
        assertEquals(BillMaintenanceEventKind.OVERDUE,event.kind)
        assertEquals("mistia.bill.overdue.${value.id}.2026-10.2026-10-13",event.key)
        assertEquals(9007199254740993L,event.due.amountMinor)
        assertEquals(event.key,events(value,"2026-10-13T12:00:00Z").single {it.month==october}.key)
        assertNotEquals(event.key,events(value,"2026-10-13T15:00:00Z").single {it.month==october}.key)
    }
    @Test fun `terminal paused archived deleted and viewer cycles do not produce maintenance intents`() {
        val value=bill().copy(firstScheduledMonth="2026-10-01T00:00:00Z",paymentStartDay=1,dueDay=10)
        assertTrue(events(value,occurrences=listOf(occurrence(status="paid"))).isEmpty())
        assertTrue(events(value,occurrences=listOf(occurrence(status="skipped"))).isEmpty())
        for(ineligible in listOf(value.copy(isPaused=true),value.copy(isArchived=true),value.copy(deletedAt=reference.toString()),value.copy(ownerUserId=reference.toString())))
            assertTrue(events(ineligible).isEmpty())
    }
    @Test fun `one time previous month deadline is considered but older cycles are excluded`() {
        val value=bill().copy(scheduleKindWireValue="oneTime",paymentStartDate="2026-09-25T00:00:00Z",dueDate="2026-10-10T00:00:00Z",hasExplicitDueDate=true)
        assertEquals(BillMaintenanceEventKind.DEADLINE,events(value).single().kind)
        assertTrue(events(value.copy(paymentStartDate="2026-08-25T00:00:00Z")).isEmpty())
    }
}
