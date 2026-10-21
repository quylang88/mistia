package vn.com.quyln.mistia.core.model

import java.math.BigInteger
import java.util.UUID
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class OverviewInvestmentSummaryTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other=UserId("99999999-9999-9999-9999-999999999999")
    private val time="2026-10-21T00:00:00Z"
    private fun row(entity:CloudEntity)=UUID.randomUUID().toString().let {id ->CloudRecord(entity.table,id,owner.value,buildJsonObject {
        put("id",id);put("user_id",owner.value);put("created_at",time);put("occurred_at",time);put("updated_at",time);put("is_archived",false)
    },time,null,0)}
    private fun CloudRecord.with(vararg fields:Pair<String,JsonElement>)=copy(payload=JsonObject(payload+fields.toMap()))
    private val channel=row(CloudEntity.INVESTMENT_CHANNEL)
    private fun asset(channel:CloudRecord=this.channel)=row(CloudEntity.INVESTMENT_ASSET).with("channel_id" to JsonPrimitive(channel.id))
    private fun trade(asset:CloudRecord,capital:Long=7,profit:Long=3,code:String="JPY",quantity:String="1")=row(CloudEntity.INVESTMENT_TRADE).with(
        "channel_id" to asset.payload.getValue("channel_id"),"asset_id" to JsonPrimitive(asset.id),"position_quantity_after_decimal_string" to JsonPrimitive(quantity),
        "position_cost_basis_after_minor" to JsonPrimitive(capital),"realized_profit_loss_minor" to JsonPrimitive(profit),"accounting_currency_code" to JsonPrimitive(code),"gross_amount_minor" to JsonPrimitive(999999))
    private fun wallet(code:String)=row(CloudEntity.LEDGER_WALLET).let {it.copy(id=investmentSystemWalletId(owner))}.with("id" to JsonPrimitive(investmentSystemWalletId(owner)),"currency_code" to JsonPrimitive(code))
    private fun project(rows:List<CloudRecord>,primary:String="JPY")=overviewInvestmentSummary(owner,OverviewFinancialReadSnapshot(owner,rows),primary)
    private fun n(value:Long)=BigInteger.valueOf(value)
    @Test fun `loaded empty is zero but withheld and wrong-owner snapshots remain unknown`() {
        assertEquals(OverviewInvestmentSummary(null,null,null),overviewInvestmentSummary(owner,null,"JPY"))
        assertEquals(OverviewInvestmentSummary(null,null,null),overviewInvestmentSummary(owner,OverviewFinancialReadSnapshot(other,emptyList()),"JPY"))
        assertEquals(OverviewInvestmentSummary(BigInteger.ZERO,BigInteger.ZERO,"JPY"),project(emptyList()))
    }
    @Test fun `capital is latest active position while profit includes closed archived and orphan history`() {
        val active=asset();val sold=asset();val hidden=asset().with("is_archived" to JsonPrimitive(true));val orphan=asset()
        val old=trade(active,100,11).with("occurred_at" to JsonPrimitive("2026-10-20T00:00:00Z"))
        val latest=trade(active,7,-2);val closed=trade(sold,999,5,quantity="0");val archived=trade(hidden,999,13);val past=trade(orphan,999,17)
        val result=project(listOf(channel,active,sold,hidden,old,latest,closed,archived,past).reversed())
        assertEquals(n(7),result.capitalMinor);assertEquals(n(44),result.realizedProfitLossMinor);assertEquals("JPY",result.currencyCode)
    }
    @Test fun `profit is persisted all-time signed value independent of position dates kind or asset metadata`() {
        val asset=asset();val first=trade(asset,profit=1375).with("occurred_at" to JsonPrimitive("bad"),"created_at" to JsonNull,"kind_raw_value" to JsonPrimitive("other"),"position_quantity_after_decimal_string" to JsonPrimitive("bad"))
        val second=trade(asset,profit=-75).with("asset_id" to JsonNull)
        val result=project(listOf(first,second));assertEquals(n(1300),result.realizedProfitLossMinor);assertEquals(BigInteger.ZERO,result.capitalMinor)
    }
    @Test fun `capital and profit aggregate exactly beyond Long without order-dependent saturation`() {
        val a=asset();val b=asset();val c=asset();val trades=listOf(trade(a,Long.MAX_VALUE,Long.MAX_VALUE),trade(b,Long.MAX_VALUE,Long.MAX_VALUE),trade(c,0,-Long.MAX_VALUE))
        for(order in listOf(trades,trades.reversed())) {
            val result=project(listOf(channel,a,b,c)+order);assertEquals(n(Long.MAX_VALUE)*BigInteger.TWO,result.capitalMinor);assertEquals(n(Long.MAX_VALUE),result.realizedProfitLossMinor)
        }
    }
    @Test fun `archived canonical wallet determines source cents without requiring its cash balance`() {
        val asset=asset();val wallet=wallet(" usd ").with("is_archived" to JsonPrimitive(true),"opening_balance_minor" to JsonPrimitive("bad"))
        val result=project(listOf(channel,asset,trade(asset,1375,-25,"USD"),wallet),"VND")
        assertEquals(OverviewInvestmentSummary(n(1375),n(-25),"USD"),result)
        assertEquals("VND",project(listOf(wallet.copy(deletedAt=time)),"VND").currencyCode)
    }
    @Test fun `missing or conflicting required accounting currency cannot relabel nonzero money`() {
        val asset=asset();val good=trade(asset)
        for(value in listOf(JsonNull,JsonPrimitive("USD"),JsonPrimitive(5),JsonPrimitive("???"))) {
            val result=project(listOf(channel,asset,good.with("accounting_currency_code" to value)))
            assertNull(result.capitalMinor);assertNull(result.realizedProfitLossMinor);assertEquals("JPY",result.currencyCode)
        }
        for(value in listOf(JsonPrimitive("???"),JsonPrimitive("ZZZ"),JsonNull)) {
            val result=project(listOf(channel,asset,good,wallet("JPY").with("currency_code" to value)))
            assertNull(result.capitalMinor);assertNull(result.realizedProfitLossMinor);assertNull(result.currencyCode)
        }
    }
    @Test fun `capital and profit damage are independent and zero effects need no unused currency`() {
        val asset=asset();val good=trade(asset)
        val badProfit=project(listOf(channel,asset,good.with("realized_profit_loss_minor" to JsonPrimitive("bad"))))
        assertEquals(n(7),badProfit.capitalMinor);assertNull(badProfit.realizedProfitLossMinor)
        val badPosition=project(listOf(channel,asset,good.with("position_cost_basis_after_minor" to JsonPrimitive("bad"))))
        assertNull(badPosition.capitalMinor);assertEquals(n(3),badPosition.realizedProfitLossMinor)
        val zero=project(listOf(channel,asset,trade(asset,profit=0,quantity="0").with("accounting_currency_code" to JsonNull,"position_cost_basis_after_minor" to JsonPrimitive("bad"))))
        assertEquals(OverviewInvestmentSummary(BigInteger.ZERO,BigInteger.ZERO,"JPY"),zero)
    }
    @Test fun `known deleted and foreign damage stays neutral while uncertain live profit holds`() {
        val asset=asset();val good=trade(asset)
        val bad=trade(asset,100,100).with("realized_profit_loss_minor" to JsonPrimitive("bad"))
        val exclusions=listOf(bad.copy(deletedAt=time),bad.copy(ownerUserId=other.value),bad.with("user_id" to JsonPrimitive(other.value)))
        assertEquals(OverviewInvestmentSummary(n(7),n(3),"JPY"),project(listOf(channel,asset,good)+exclusions))
        val uncertain=good.with("deleted_at" to buildJsonObject{put("bad",true)})
        assertNull(project(listOf(channel,asset,uncertain)).realizedProfitLossMinor)
    }
}
