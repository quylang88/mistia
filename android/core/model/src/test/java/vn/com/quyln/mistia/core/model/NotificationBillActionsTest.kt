package vn.com.quyln.mistia.core.model

import java.time.Instant
import java.time.YearMonth
import java.time.ZoneId
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class NotificationBillActionsTest {
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
    private val wallet=WalletDraft(name="Cash",kind=WalletKind.CASH,currencyCode="JPY").toMutation(owner,null,"44444444-4444-4444-4444-444444444444",reference.toString()).record.let(LedgerWalletRecord::fromCloudRecord)
    private fun row(kind:String="billPaymentRequired")=AppNotificationRecord(owner.value,"notice","Title","Body",kind,
        resourceType="bill",resourceId=bill().id,createdAt=reference.toString(),updatedAt=reference.toString(),metadata=buildJsonObject {
            put("sourceKind","recurringBill");put("sourceId",bill().id);put("dueMonthKey","2026-10");put("linkedPaymentWalletId",wallet.id)
            put("currencyCode","VND");put("requiresAmountInput",true)
        })
    private fun action(row:AppNotificationRecord=row(),bills:List<RecurringBillPlanRecord> = listOf(bill()),occurrences:List<DueOccurrenceRecord> = emptyList(),wallets:List<LedgerWalletRecord> = listOf(wallet))=
        notificationBillAction(owner,row,bills,occurrences,wallets,zone)
    @Test fun `pending payment action uses real current bill cycle rather than stale currency metadata`() {
        assertEquals(NotificationBillAction.Pay(bill().id,october),action())
        assertEquals(NotificationBillAction.Pay(bill().id,october),action(row().copy(isRead=true,readAt=reference.toString())))
    }
    @Test fun `auto failure opens linked wallet top up instead of automatic or manual payment`() {
        assertEquals(NotificationBillAction.TopUp(wallet.id),action(row("billAutoPaymentFailed")))
        assertEquals(NotificationBillAction.TopUp(wallet.id),action(row("billAutoPaymentFailed"),bills=emptyList()))
    }
    @Test fun `terminal paused archived deleted and foreign bills cannot open a payment form`() {
        for(value in listOf(bill().copy(isPaused=true),bill().copy(isArchived=true),bill().copy(deletedAt=reference.toString()),bill().copy(ownerUserId=wallet.id)))
            assertNull(action(bills=listOf(value)))
        assertNull(action(occurrences=listOf(occurrence(status="paid"))))
        assertNull(action(occurrences=listOf(occurrence(status="skipped"))))
    }
    @Test fun `top up refuses missing archived deleted and foreign wallet references`() {
        assertNull(action(row("billAutoPaymentFailed"),wallets=emptyList()))
        for(value in listOf(wallet.copy(isArchived=true),wallet.copy(deletedAt=reference.toString()),wallet.copy(ownerUserId=bill().id)))
            assertNull(action(row("billAutoPaymentFailed"),wallets=listOf(value)))
    }
    @Test fun `malformed cross owner or mismatched source metadata cannot route actions`() {
        assertNull(action(row().copy(ownerUserId=wallet.id)))
        assertNull(action(row().copy(metadata=null)))
        for(change in listOf("dueMonthKey" to JsonPrimitive("not a month"),"sourceId" to JsonPrimitive(wallet.id),"sourceKind" to JsonPrimitive("creditCard")))
            assertNull(action(row().copy(metadata=JsonObject(row().metadata!!+change))))
        assertNull(action(row("billAutoPaymentSucceeded")))
    }    @Test fun `malformed auto failure cycle cannot route an unrelated top up`() {
        val failure=row("billAutoPaymentFailed")
        assertNull(action(failure.copy(metadata=JsonObject(failure.metadata!!+("dueMonthKey" to JsonPrimitive("invalid"))))))
    }
    @Test fun `one time payment keeps scheduler rule that legacy pause flag is ignored`() {
        val one=bill().copy(scheduleKindWireValue="oneTime",isPaused=true,paymentStartDate="2026-10-01T00:00:00Z",dueDate="2026-10-10T00:00:00Z")
        assertEquals(NotificationBillAction.Pay(one.id,october),action(bills=listOf(one)))
    }

}
