package vn.com.quyln.mistia.feature.planning

import androidx.compose.runtime.saveable.SaverScope
import java.time.YearMonth
import java.time.ZoneId
import org.junit.Assert.*
import org.junit.Test
import vn.com.quyln.mistia.core.model.*

class BillPaymentStateTest {
    private val owner="11111111-1111-1111-1111-111111111111"
    private val id="22222222-2222-2222-2222-222222222222"
    private val walletId="33333333-3333-3333-3333-333333333333"
    private val month=YearMonth.of(2026,10)
    private val zone=ZoneId.of("Asia/Tokyo")
    private val now="2026-10-13T00:00:00Z"
    private fun wallet(currency:String="JPY")=LedgerWalletRecord.fromCloudRecord(WalletDraft(id=walletId,name="Cash",kind=WalletKind.CASH,currencyCode=currency,openingBalanceMinor=Long.MAX_VALUE)
        .toMutation(UserId(owner),null,id,now).record)
    private fun row(amount:Long?=5000,currency:String="JPY"):RecurringBillDueRow {
        val bill=RecurringBillPlanRecord(id,owner,"Rent","house.fill",null,amount,3,"recurring",28,
            null,"2026-09-30T15:00:00Z",true,null,false,null,null,1,walletId,currency,false,false,null,null,now,now,null,0,id)
        return recurringBillDueRows(UserId(owner),listOf(bill),emptyList(),month,zone).single()
    }
    @Test fun `request carries visible bill and effective cycle amount independently of default`() {
        val due=row().copy(amountMinor=6000)
        val request=BillPaymentState.initial(owner,due,month,listOf(wallet())).request(due,listOf(wallet()))
        assertEquals(due.bill,request.expectedBill);assertEquals(6000L,request.expectedDueAmountMinor)
        assertEquals(6000L,request.amountMinorOverride)
    }
    @Test fun `known amount uses default and captures cycle month across month end`() {
        val row=row(9007199254740993L)
        val state=BillPaymentState.initial(owner,row,month,listOf(wallet()))
        assertEquals(walletId,state.walletId)
        val request=state.request(row,listOf(wallet()))
        assertEquals(month,request.month)
        assertEquals(9007199254740993L,request.amountMinorOverride)
        assertEquals(walletId,request.walletId!!.value)
        assertEquals(11,row.dueDate.atZone(zone).monthValue)
    }
    @Test fun `nil amount parses exact minor integer and USD fraction without rounding`() {
        val row=row(null)
        val state=BillPaymentState.initial(owner,row,month,listOf(wallet())).copy(amountText="9,007,199,254,740,993")
        assertEquals(9007199254740993L,state.request(row,listOf(wallet())).amountMinorOverride)
        val usd=row(null,"USD")
        assertEquals(1375L,BillPaymentState.initial(owner,usd,month,listOf(wallet("USD"))).copy(amountText="13.75")
            .request(usd,listOf(wallet("USD"))).amountMinorOverride)
        listOf("","0","-1","1.5","9223372036854775808","invalid").forEach {
            assertThrows(IllegalArgumentException::class.java) {state.copy(amountText=it).request(row,listOf(wallet()))}
        }
    }
    @Test fun `wallet choices and stale selected wallet enforce owner archive and currency`() {
        val cash=wallet()
        assertEquals(listOf(cash),eligibleBillPaymentWallets(owner,"JPY",listOf(cash,cash.copy(id=id,currencyCode="VND"),
            cash.copy(id=id,ownerUserId=id),cash.copy(id=id,isArchived=true),cash.copy(id=id,deletedAt=now),
            cash.copy(id=id,kindWireValue=WalletKind.INVESTMENT.wireValue))))
        val row=row()
        assertNull(BillPaymentState.initial(owner,row,month,listOf(wallet("VND"))).walletId)
        assertThrows(IllegalArgumentException::class.java) {BillPaymentState.initial(owner,row,month,listOf(cash)).request(row,listOf(wallet("VND")))}
    }
    @Test fun `saved form restores only same owner bill and cycle`() {
        val state=BillPaymentState.initial(owner,row(null),month,listOf(wallet())).copy(amountText="500")
        val saver=BillPaymentState.saver(owner,id,month.toString())
        val saved=with(saver) {SaverScope {true}.save(state)}!!
        assertEquals(state,saver.restore(saved))
        assertNull(BillPaymentState.saver(walletId,id,month.toString()).restore(saved))
        assertNull(BillPaymentState.saver(owner,walletId,month.toString()).restore(saved))
        assertNull(BillPaymentState.saver(owner,id,"2026-11").restore(saved))
    }
    @Test fun `paid archived foreign and changed source cannot submit`() {
        val row=row()
        val state=BillPaymentState.initial(owner,row,month,listOf(wallet()))
        listOf(row.copy(status=DueStatus.PAID),row.copy(bill=row.bill.copy(isArchived=true)),
            row.copy(bill=row.bill.copy(ownerUserId=id)),row.copy(bill=row.bill.copy(id=walletId)),
            row.copy(bill=row.bill.copy(currencyCode="VND"))).forEach {
            assertThrows(IllegalArgumentException::class.java) {state.request(it,listOf(wallet()))}
        }
    }
    @Test fun `payment navigation restores undo cycle and rejects foreign owner or malformed month`() {
        val navigation=BillPaymentNavigation(owner,id,month.toString(),true)
        val saver=BillPaymentNavigation.saver(owner)
        val saved=with(saver) {SaverScope {true}.save(navigation)}!!
        assertEquals(navigation,saver.restore(saved))
        assertNull(BillPaymentNavigation.saver(walletId).restore(saved))
        assertNull(saver.restore(listOf(owner,id,"2026-13",true)))
    }

}
