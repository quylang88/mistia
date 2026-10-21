package vn.com.quyln.mistia.core.model

import java.time.YearMonth
import org.junit.Assert.*
import org.junit.Test

class BillPaymentConsentTest {
    private val owner="11111111-1111-1111-1111-111111111111"
    private val id="22222222-2222-2222-2222-222222222222"
    private val wallet="33333333-3333-3333-3333-333333333333"
    private val now="2026-10-13T00:00:00Z"
    private fun source()=RecurringBillPlanRecord(id,owner,"Internet","wifi",null,5000,10,"recurring",10,null,
        "2026-09-30T15:00:00Z",false,null,false,null,null,1,wallet,"JPY",false,false,null,null,now,now,null,0,id)
    private fun request(bill:RecurringBillPlanRecord=source())=BillPaymentRequest(RecordId(id),YearMonth.of(2026,10),RecordId(wallet),5000,expectedBill=bill)
    @Test fun `ack metadata and equivalent created instant preserve visible intent`() {
        val original=source();val ack=original.copy(createdAt="2026-10-13T00:00:00.000000Z",updatedAt="2026-10-14T00:00:00Z",syncVersion=Long.MAX_VALUE,lastModifiedByDeviceId=wallet)
        assertTrue(ack.matchesBillPaymentSource(original));assertTrue(request().matchesBillPaymentConsent(request(ack)))
    }
    @Test fun `every relevant source change invalidates the frozen request`() {
        val original=source()
        for(next in listOf(original.copy(id=wallet),original.copy(ownerUserId=wallet),original.copy(name="New bill"),original.copy(iconSymbolName="house"),original.copy(categoryId=wallet),
            original.copy(amountMinor=6000),original.copy(currencyCode="VND"),original.copy(paymentWalletId=id),original.copy(paymentStartDay=9),original.copy(dueDay=20),
            original.copy(scheduleKindWireValue="oneTime"),original.copy(paymentStartDate=now),original.copy(dueDate=now),original.copy(firstScheduledMonth=now),
            original.copy(hasExplicitDueDate=true),original.copy(autoPayEnabled=true),original.copy(autoPayDay=12),original.copy(autoPayDate=now),original.copy(frequencyMonths=2),
            original.copy(isPaused=true),original.copy(pausedAt=now),original.copy(resumeStartMonth=now),original.copy(isArchived=true),original.copy(deletedAt=now),
            original.copy(createdAt="2026-10-13T00:00:00.000000001Z"))) {
            assertFalse(next.toString(),next.matchesBillPaymentSource(original));assertFalse(request().matchesBillPaymentConsent(request(next)))
        }
    }
    @Test fun `request wallet month amount mode and cycle source amount are part of consent`() {
        val original=request()
        for(next in listOf(null,original.copy(walletId=RecordId(id)),original.copy(month=YearMonth.of(2026,11)),original.copy(amountMinorOverride=6000),
            original.copy(automatic=true),original.copy(expectedBill=null),original.copy(expectedDueAmountMinor=6000),original.copy(expectedDueAmountMinor=null)))
            assertFalse(original.matchesBillPaymentConsent(next))
        assertTrue(original.matchesBillPaymentConsent(original))
    }
    @Test fun `unreadable created timestamp cannot prove a matching source even against itself`() {
        val bad=source().copy(createdAt="broken")
        assertFalse(bad.matchesBillPaymentSource(bad));assertFalse(request(bad).matchesBillPaymentConsent(request(bad)))
    }
}
