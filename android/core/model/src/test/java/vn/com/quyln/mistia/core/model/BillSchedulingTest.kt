package vn.com.quyln.mistia.core.model

import java.time.Instant
import java.time.YearMonth
import java.time.ZoneId
import org.junit.Assert.*
import org.junit.Test

class BillSchedulingTest {
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
    private fun rows(bills:List<RecurringBillPlanRecord>,occurrences:List<DueOccurrenceRecord> = emptyList(),month:YearMonth=october)=recurringBillDueRows(owner,bills,occurrences,month,zone)

    @Test fun `deadline crosses month and clamps dates to actual month length`() {
        val row=rows(listOf(bill())).single()
        assertEquals("2026-10-24T15:00:00Z",row.paymentStartDate.toString())
        assertEquals("2026-11-09T15:00:00Z",row.dueDate.toString())
        assertTrue(row.hasExplicitDueDate)
        val feb=rows(listOf(bill().copy(dueDay=31,paymentStartDay=0)),month=YearMonth.of(2028,2)).single()
        assertEquals("2028-01-31T15:00:00Z",feb.paymentStartDate.toString())
        assertEquals("2028-02-28T15:00:00Z",feb.dueDate.toString())
        val equal=rows(listOf(bill().copy(paymentStartDay=10))).single()
        assertFalse(equal.hasExplicitDueDate);assertEquals(equal.paymentStartDate,equal.dueDate)
    }
    @Test fun `frequency starts at first or resume local month and never backfills paused months`() {
        val next=bill().copy(firstScheduledMonth="2026-10-31T15:00:00Z",frequencyMonths=2)
        assertTrue(rows(listOf(next)).isEmpty())
        assertEquals(1,rows(listOf(next),month=YearMonth.of(2026,11)).size)
        assertTrue(rows(listOf(next),month=YearMonth.of(2026,12)).isEmpty())
        assertEquals(1,rows(listOf(next),month=YearMonth.of(2027,1)).size)
        assertTrue(rows(listOf(next.copy(isPaused=true))).isEmpty())
        val resumed=next.copy(firstScheduledMonth=null,resumeStartMonth="2026-09-30T15:00:00Z")
        assertEquals(1,rows(listOf(resumed)).size)
        assertTrue(rows(listOf(resumed),month=YearMonth.of(2026,9)).isEmpty())
        assertEquals(1,rows(listOf(resumed.copy(frequencyMonths=0))).size)
    }
    @Test fun `one time keeps exact dates ignores pause and only appears in its payment month`() {
        val value=bill().copy(scheduleKindWireValue="oneTime",isPaused=true,paymentStartDate="2026-10-01T01:00:00Z",dueDate="2026-10-04T02:00:00Z")
        val row=rows(listOf(value)).single()
        assertEquals(Instant.parse(value.paymentStartDate),row.paymentStartDate)
        assertEquals(Instant.parse(value.dueDate),row.dueDate)
        assertTrue(rows(listOf(value),month=YearMonth.of(2026,11)).isEmpty())
        assertTrue(rows(listOf(value.copy(paymentStartDate=null))).isEmpty())
        val invalid=rows(listOf(value.copy(dueDate="2026-09-30T15:00:00Z"))).single()
        assertFalse(invalid.hasExplicitDueDate);assertEquals(invalid.paymentStartDate,invalid.dueDate)
    }
    @Test fun `auto pay stays within inclusive window and wraps with deadline`() {
        val value=bill().copy(autoPayEnabled=true,autoPayDay=5)
        assertEquals("2026-11-04T15:00:00Z",rows(listOf(value)).single().autoPayDate.toString())
        val outside=rows(listOf(value.copy(autoPayDay=20))).single()
        assertEquals(outside.paymentStartDate,outside.autoPayDate)
        val noDeadline=rows(listOf(value.copy(hasExplicitDueDate=false))).single()
        assertEquals(noDeadline.paymentStartDate,noDeadline.autoPayDate)
        assertNull(rows(listOf(value.copy(autoPayEnabled=false))).single().autoPayDate)
        val one=value.copy(scheduleKindWireValue="oneTime",paymentStartDate="2026-10-01T01:00:00Z",dueDate="2026-10-04T02:00:00Z",autoPayDate="2026-10-02T07:00:00Z")
        assertEquals("2026-10-01T15:00:00Z",rows(listOf(one)).single().autoPayDate.toString())
        assertEquals(Instant.parse(one.paymentStartDate),rows(listOf(one.copy(autoPayDate=null))).single().autoPayDate)
    }
    @Test fun `duplicates prefer first terminal snapshot and foreign deleted occurrences cannot override`() {
        val pending=occurrence()
        val paid=pending.copy(id="44444444-4444-4444-4444-444444444444",statusWireValue="paid",amountMinorSnapshot=9007199254740993L,linkedTransactionId=bill().id)
        val skipped=paid.copy(id="55555555-5555-5555-5555-555555555555",statusWireValue="skipped")
        val foreign=paid.copy(ownerUserId="66666666-6666-6666-6666-666666666666")
        val row=rows(listOf(bill()),listOf(foreign,paid.copy(deletedAt=reference.toString()),pending,paid,skipped)).single()
        assertEquals(DueStatus.PAID,row.status);assertEquals(9007199254740993L,row.amountMinor);assertEquals(bill().id,row.linkedTransactionId)
        assertEquals(DueStatus.SKIPPED,rows(listOf(bill()),listOf(skipped,paid)).single().status)
        assertTrue(rows(listOf(bill().copy(ownerUserId=foreign.ownerUserId))).isEmpty())
        assertTrue(rows(listOf(bill().copy(deletedAt=reference.toString()))).isEmpty())
    }
    @Test fun `archived paid history bypasses changed schedule and pause but does not generate new cycles`() {
        val archived=bill().copy(isArchived=true,isPaused=true,resumeStartMonth="2027-01-01T00:00:00Z")
        assertTrue(rows(listOf(archived)).isEmpty())
        assertTrue(rows(listOf(archived),listOf(occurrence(status="skipped"))).isEmpty())
        val row=rows(listOf(archived),listOf(occurrence(status="paid"))).single()
        assertTrue(row.bill.isArchived);assertEquals(123L,row.amountMinor)
        assertTrue(rows(listOf(archived),listOf(occurrence(status="paid")),YearMonth.of(2026,11)).isEmpty())
    }
    @Test fun `unpaid guard counts skipped current cycles and stops at paused month`() {
        val value=bill().copy(firstScheduledMonth="2026-08-01T00:00:00Z")
        val paid=listOf(occurrence("2026-08","paid"),occurrence("2026-09","paid"))
        assertTrue(hasUnpaidBillCycles(owner,value,paid,reference,zone))
        assertTrue(hasUnpaidBillCycles(owner,value,paid+occurrence(status="skipped"),reference,zone))
        assertFalse(hasUnpaidBillCycles(owner,value,paid+occurrence(status="paid"),reference,zone))
        assertFalse(hasUnpaidBillCycles(owner,value.copy(isPaused=true,pausedAt="2026-09-13T00:00:00Z"),paid,reference,zone))
        assertFalse(hasUnpaidBillCycles(owner,value.copy(resumeStartMonth="2026-10-31T15:00:00Z"),emptyList(),reference,zone))
    }
}
