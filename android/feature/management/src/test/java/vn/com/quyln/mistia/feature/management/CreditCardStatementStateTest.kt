package vn.com.quyln.mistia.feature.management

import androidx.compose.runtime.saveable.SaverScope
import java.time.Instant
import java.time.YearMonth
import java.time.ZoneId
import org.junit.Assert.*
import org.junit.Test
import vn.com.quyln.mistia.core.model.*

class CreditCardStatementStateTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other="99999999-9999-9999-9999-999999999999"
    private val device="33333333-3333-3333-3333-333333333333"
    private val now="2026-01-01T00:00:00Z"
    private val zone=ZoneId.of("Asia/Tokyo")
    private val aggregate=CreditCardDraft(name="Card",creditLimitMinor=100000).toMutation(owner,null,null,null,device,now)
    private val card=aggregate.wallet.record
    private val cash=card.copy(id=device,name="Cash",kindWireValue="cash")
    private val profile=aggregate.profile.record.copy(paymentSourceWalletId=cash.id)
    private val month=YearMonth.of(2026,2)
    private val reference=Instant.parse("2026-03-26T00:00:00Z")
    private fun charge(amount:Long=5000,at:String="2026-02-12T00:00:00Z")=TransactionDraft(primaryKind=TransactionPrimaryKind.TRANSFER,
        transferSubtype=TransactionTransferSubtype.DEBT,debtIntent=TransactionDebtIntent.LEND,title="Loan",amountMinor=amount,occurredAt=at,
        sourceWalletId=card.id,counterpartyName="A").toMutation(owner,null,card,null,null,device,now).record
    private fun view(wallets:List<LedgerWalletRecord> = listOf(card,cash),profiles:List<CreditCardProfileRecord> = listOf(profile),records:List<LedgerTransactionRecord> = listOf(charge()))=
        creditCardStatementViewData(owner,card.id,wallets,profiles,records,emptyList(),emptyList(),month,reference,zone)
    @Test fun `view uses current owned statement and linked wallet name`() {
        val actual=view()!!;assertEquals("Card",actual.wallet.name);assertEquals("Cash",actual.linkedWalletName)
        assertEquals(5000L,actual.statement!!.amountMinor);assertEquals(CreditCardStatementState.PAYABLE,actual.statement.state)
    }
    @Test fun `history list matches Swift raw charges and preserves rows excluded from statement total`() {
        val expense=charge().copy(primaryKindWireValue="expense",transferSubtypeWireValue=null,debtIntentWireValue=null)
        val adjustment=expense.copy(id=device,amountMinor=1000,categoryId=TransactionCategoryRecord.BALANCE_ADJUSTMENT_EXPENSE_ID,occurredAt="2026-02-13T00:00:00Z")
        val excluded=listOf(expense.copy(id=other,ownerUserId=other),expense.copy(id="44444444-4444-4444-4444-444444444444",isArchived=true),
            expense.copy(id="55555555-5555-5555-5555-555555555555",deletedAt=now),expense.copy(id="66666666-6666-6666-6666-666666666666",entryStatusWireValue="draft"),
            charge(at="2026-03-01T00:00:00Z"))
        val actual=view(records=listOf(expense,adjustment)+excluded)!!
        assertEquals(5000L,actual.statement!!.amountMinor);assertEquals(listOf(adjustment.id,expense.id),actual.charges.map {it.id})
    }
    @Test fun `missing or foreign card cannot leak profile or transaction content`() {
        assertNull(view(wallets=listOf(card.copy(ownerUserId=other),cash)))
        assertNull(view(wallets=listOf(card.copy(deletedAt=now),cash)))
        val missing=view(profiles=listOf(profile.copy(ownerUserId=other)))!!
        assertNull(missing.statement);assertTrue(missing.charges.isEmpty());assertNull(missing.linkedWalletName)
    }
    @Test fun `archived card has no active statement and foreign linked wallet is hidden`() {
        assertNull(view(wallets=listOf(card.copy(isArchived=true),cash))!!.statement)
        assertNull(view(wallets=listOf(card,cash.copy(ownerUserId=other)))!!.linkedWalletName)
    }
    @Test fun `paid statement history remains present with raw rows`() {
        val expense=charge()
        val payment=expense.copy(id=device,transferSubtypeWireValue="internalTransfer",debtIntentWireValue=null,sourceWalletId=cash.id,
            destinationWalletId=card.id,occurredAt="2026-03-26T00:00:00Z",createdAt="2026-03-26T00:00:00Z")
        val actual=view(records=listOf(expense,payment))!!
        assertEquals(CreditCardStatementState.PAID,actual.statement!!.state);assertEquals(listOf(expense),actual.charges)
    }
    @Test fun `navigation restores month only for same owner and card and rejects malformed month`() {
        val value=CreditCardStatementNavigation(owner.value,card.id,"2026-02");val saver=CreditCardStatementNavigation.saver(owner.value,card.id)
        val saved=with(saver) {SaverScope {true}.save(value)}!!
        assertEquals(value,saver.restore(saved))
        assertNull(CreditCardStatementNavigation.saver(other,card.id).restore(saved))
        assertNull(CreditCardStatementNavigation.saver(owner.value,device).restore(saved))
        assertNull(saver.restore(listOf(owner.value,card.id,"bad")))
    }
    @Test fun `month bounds match ten year January through current local month and clamp future`() {
        val bounds=StatementMonthBounds.current(Instant.parse("2026-10-31T16:00:00Z"),zone)
        assertEquals(YearMonth.of(2016,1),bounds.minimum);assertEquals(YearMonth.of(2026,11),bounds.maximum)
        assertEquals(bounds.minimum,bounds.clamp(YearMonth.of(2010,1)));assertEquals(bounds.maximum,bounds.clamp(YearMonth.of(2027,1)))
        assertEquals(month,bounds.clamp(month))
        assertEquals(YearMonth.of(2026,10),StatementMonthBounds.current(Instant.parse("2026-10-31T16:00:00Z"),ZoneId.of("Asia/Ho_Chi_Minh")).maximum)
    }
}
