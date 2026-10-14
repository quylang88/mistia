package vn.com.quyln.mistia.core.model

import java.time.Instant
import java.time.YearMonth
import java.time.ZoneId
import org.junit.Assert.*
import org.junit.Test

class CreditCardStatementPlanningTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val device="33333333-3333-3333-3333-333333333333"
    private val zone=ZoneId.of("Asia/Tokyo")
    private val now="2026-01-01T00:00:00Z"
    private val aggregate=CreditCardDraft(name="Card",creditLimitMinor=100_000).toMutation(owner,null,null,null,device,now)
    private val account=CreditCardAccount(aggregate.wallet.record,aggregate.profile.record)
    private fun charge(amount:Long=32456,at:String="2026-02-12T00:00:00Z")=TransactionDraft(primaryKind=TransactionPrimaryKind.TRANSFER,
        transferSubtype=TransactionTransferSubtype.DEBT,debtIntent=TransactionDebtIntent.LEND,title="Loan",amountMinor=amount,
        occurredAt=at,sourceWalletId=account.wallet.id,counterpartyName="A").toMutation(owner,null,account.wallet,null,null,device,now).record
    @Test fun `selected due month includes prior spending month even before closing`() {
        val rows=creditCardStatementsDue(owner,YearMonth.of(2026,3),listOf(account),listOf(charge()),emptyList(),Instant.parse("2026-03-08T15:00:00Z"),zone)
        assertEquals(1,rows.size);assertEquals(YearMonth.of(2026,2),rows.single().month)
        assertEquals(CreditCardStatementState.UNCLOSED,rows.single().state);assertEquals(32456L,rows.single().amountMinor)
    }
    @Test fun `due month search covers legacy schedule spanning two months`() {
        val legacy=account.copy(profile=account.profile.copy(statementClosingDay=30,paymentDueDay=5))
        val rows=creditCardStatementsDue(owner,YearMonth.of(2026,3),listOf(legacy),listOf(charge(at="2026-01-12T00:00:00Z")),emptyList(),Instant.parse("2026-03-05T00:00:00Z"),zone)
        assertEquals(1,rows.size);assertEquals(YearMonth.of(2026,1),rows.single().month)
        assertEquals("2026-03-04T15:00:00Z",rows.single().dueDate.toString())
    }
    @Test fun `foreign account or profile cannot produce statement for active owner`() {
        for(foreign in listOf(account.copy(wallet=account.wallet.copy(ownerUserId=device)),account.copy(profile=account.profile.copy(ownerUserId=device)))) {
            assertTrue(creditCardStatementItems(owner,listOf(foreign),listOf(charge()),emptyList(),listOf(YearMonth.of(2026,2)),Instant.parse("2026-03-10T00:00:00Z"),zone).isEmpty())
        }
    }
    @Test fun `statement total overflow fails instead of silently clamping or wrapping money`() {
        val error=runCatching {creditCardStatementItems(owner,listOf(account),listOf(charge(Long.MAX_VALUE),charge(1)),emptyList(),
            listOf(YearMonth.of(2026,2)),Instant.parse("2026-03-10T00:00:00Z"),zone)}.exceptionOrNull()
        assertTrue(error is ArithmeticException)
    }
}
