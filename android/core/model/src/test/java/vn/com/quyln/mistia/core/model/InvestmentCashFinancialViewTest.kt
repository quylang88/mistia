package vn.com.quyln.mistia.core.model

import java.math.BigInteger
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class InvestmentCashFinancialViewTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val linked="22222222-2222-4222-8222-222222222222"
    private val device="33333333-3333-4333-8333-333333333333"
    private val now="2026-10-22T00:00:00Z"
    private fun wallet(id:String,amount:Long=10000)=WalletDraft(id=id,name="Cash",kind=WalletKind.CASH,currencyCode="VND",openingBalanceMinor=amount).toMutation(owner,null,device,now).record
    private fun system()=wallet(investmentSystemWalletId(owner),0).let{it.copy(payload=JsonObject(it.payload+buildJsonObject{
        put("kind_raw_value","investment");put("system_purpose_raw_value","investmentProfit");put("investment_linked_wallet_id",linked)
    }))}
    @Test fun linkedActualCashDoesNotDependOnUnusedOtherWalletOpeningBalance() {
        val other=wallet("44444444-4444-4444-8444-444444444444").let{it.copy(payload=JsonObject(it.payload+("opening_balance_minor" to JsonPrimitive("broken"))))}
        val result=investmentCashFinancialView(InvestmentCashReadSnapshot(owner,listOf(system(),wallet(linked),other)),"VND")
        assertEquals(BigInteger.valueOf(10000),result.linkedActualMinor)
        assertEquals(BigInteger.valueOf(10000),result.linkedBalances?.ordinaryMinor)
        assertEquals(BigInteger.ZERO,result.linkedBalances?.investmentMinor)
    }
}
