package vn.com.quyln.mistia.core.model

import java.math.BigInteger
import java.util.UUID
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class OverviewAssetsMoneyTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other="99999999-9999-9999-9999-999999999999"
    private val time="2026-10-20T00:00:00Z"
    private val rate=ExchangeRateSnapshot("JPY","VND","2.5","test",0,null)
    private fun raw(entity:CloudEntity,fields:JsonObject=JsonObject(emptyMap())):CloudRecord {
        val id=UUID.randomUUID().toString()
        return CloudRecord(entity.table,id,owner.value,JsonObject(buildJsonObject {
            put("id",id);put("user_id",owner.value);put("created_at",time);put("updated_at",time);put("occurred_at",time);put("is_archived",false)
        }+fields),time,null,0)
    }
    private fun wallet(amount:Long=0,code:String="JPY")=LedgerWalletRecord.fromCloudRecord(raw(CloudEntity.LEDGER_WALLET,buildJsonObject {
        put("name","Exact cash");put("kind_raw_value","cash");put("opening_balance_minor",amount);put("currency_code",code)
    }))
    private fun income(wallet:LedgerWalletRecord,amount:Long)=LedgerTransactionRecord.fromCloudRecord(raw(CloudEntity.LEDGER_TRANSACTION,buildJsonObject {
        put("title","Cash");put("primary_kind_raw_value","income");put("entry_status_raw_value","posted");put("source_wallet_id",wallet.id);put("amount_minor",amount);put("source_currency_code",wallet.currencyCode)
    }))
    private fun total(wallets:List<LedgerWalletRecord>,rows:List<LedgerTransactionRecord> = emptyList(),code:String="JPY",rates:List<ExchangeRateSnapshot> = emptyList(),inventory:BigInteger=BigInteger.ZERO,inventoryCode:String=code)=
        overviewTotalAssets(owner,wallets,rows,code,rates,inventory,inventoryCode)
    private fun n(value:Long)=BigInteger.valueOf(value)
    private fun minor(expected:BigInteger,actual:Any?)=assertEquals(expected.toString(),actual?.toString())
    private fun channel()=raw(CloudEntity.INVESTMENT_CHANNEL)
    private fun asset(channel:CloudRecord)=raw(CloudEntity.INVESTMENT_ASSET,buildJsonObject {put("channel_id",channel.id)})
    private fun trade(asset:CloudRecord,cost:Long=500,quantity:String="1")=raw(CloudEntity.INVESTMENT_TRADE,buildJsonObject {
        put("asset_id",asset.id);put("channel_id",asset.payload.getValue("channel_id"));put("position_quantity_after_decimal_string",quantity);put("position_cost_basis_after_minor",cost)
    })
    private fun CloudRecord.with(key:String,value:JsonElement)=copy(payload=JsonObject(payload+(key to value)))
    @Test fun `cash totals retain positive and negative twice Long bounds`() {
        for(value in listOf(Long.MAX_VALUE,Long.MIN_VALUE)) minor(n(value)*BigInteger.TWO,total(listOf(wallet(value),wallet(value))))
    }
    @Test fun `final wallet balances and cross conversion keep overflow until signed cancellation`() {
        val positive=wallet(Long.MAX_VALUE);val doubled=rate.copy(rateDecimalString="2")
        val rows=listOf(income(positive,Long.MAX_VALUE))
        minor(n(Long.MAX_VALUE)*n(4),total(listOf(positive),rows,"VND",listOf(doubled)))
        val negative=wallet(-Long.MAX_VALUE)
        for(ordered in listOf(rows+income(negative,-Long.MAX_VALUE),(rows+income(negative,-Long.MAX_VALUE)).reversed()))
            minor(BigInteger.ZERO,total(listOf(positive,negative),ordered,"VND",listOf(doubled)))
    }
    @Test fun `FX rounds each final wallet balance once rather than each ledger record`() {
        val first=wallet();val second=wallet(3)
        minor(n(15),total(listOf(first),listOf(income(first,3),income(first,3)),"VND",listOf(rate)))
        minor(n(16),total(listOf(first,second),listOf(income(first,3)),"VND",listOf(rate)))
    }
    @Test fun `missing conversion holds whole assets instead of omitting one active wallet`() {
        val yen=wallet(3);val dong=wallet(70,"VND")
        for(order in listOf(listOf(yen,dong),listOf(dong,yen))) {
            assertNull(total(order,code="VND"));minor(n(78),total(order,code="VND",rates=listOf(rate)))
        }
        for(text in listOf("0","-1","broken")) assertNull(total(listOf(yen,dong),code="VND",rates=listOf(rate.copy(rateDecimalString=text))))
    }
    @Test fun `same ISO imported cents retain identity while unsupported or malformed currency holds`() {
        val dollars=wallet(1375," usd ")
        minor(n(1375),total(listOf(dollars),code="USD"));assertNull(total(listOf(dollars)))
        assertNull(total(listOf(wallet(1375,"??"))));assertNull(total(listOf(wallet(1375)),code="??"))
        assertNull(total(emptyList(),inventory=n(3),inventoryCode="??"))
    }
    @Test fun `zero balances need no FX and excluded wallets or records never poison totals`() {
        val valid=wallet(9);val unknown=wallet(0,"??");val foreign=wallet(100,"USD").copy(ownerUserId=other)
        val hidden=listOf(wallet(100,"USD").copy(isArchived=true),wallet(100,"USD").copy(deletedAt=time),wallet(100,"USD").copy(kindWireValue="creditCard"))
        minor(n(9),total(listOf(valid,unknown,foreign)+hidden,listOf(income(valid,100).copy(ownerUserId=other),income(valid,100).copy(entryStatusWireValue="draft"))))
        minor(BigInteger.ZERO,total(listOf(unknown),inventoryCode="??"))
        minor(BigInteger.ZERO,overviewTotalAssets(owner,emptyList(),emptyList(),"JPY",inventoryCurrency=null))
        assertNull(overviewTotalAssets(owner,listOf(valid),emptyList(),"JPY",inventoryCost=n(1),inventoryCurrency=null))
        assertNull(overviewTotalAssets(owner,listOf(valid),emptyList(),"JPY",inventoryCost=null))
    }
    @Test fun `cash and inventory combine exactly without final saturation or relabeling`() {
        val inventory=n(Long.MAX_VALUE)*BigInteger.TWO
        minor(inventory+n(1),total(listOf(wallet(1)),inventory=inventory))
        minor(n(Long.MAX_VALUE),total(listOf(wallet(-Long.MAX_VALUE)),inventory=inventory))
        val doubled=rate.copy(rateDecimalString="2")
        minor(inventory*n(2),total(emptyList(),code="VND",rates=listOf(doubled),inventory=inventory,inventoryCode="JPY"))
        assertNull(total(listOf(wallet(70,"VND")),code="VND",inventory=n(3),inventoryCode="JPY"))
    }
    @Test fun `malformed latest position holds whole portfolio and composed cash plus inventory`() {
        val channel=channel();val known=asset(channel);val damaged=asset(channel)
        val good=trade(known,7);val old=trade(damaged,100).with("occurred_at",JsonPrimitive("2026-10-19T00:00:00Z"));val latest=trade(damaged)
        for(bad in listOf(latest.with("position_quantity_after_decimal_string",JsonPrimitive("broken")),latest.with("position_cost_basis_after_minor",JsonPrimitive("broken")))) {
            val cost=overviewInventoryCost(owner,listOf(channel),listOf(known,damaged),listOf(good,old,bad))
            assertNull(overviewTotalAssets(owner,listOf(wallet(9)),emptyList(),"JPY",inventoryCost=cost))
            assertNull(cost)
        }
    }
    @Test fun `position wire quantity must be decimal string and nonzero cost must be integer number`() {
        val channel=channel();val asset=asset(channel);val latest=trade(asset)
        for(bad in listOf(latest.with("position_quantity_after_decimal_string",JsonPrimitive(1)),latest.with("position_cost_basis_after_minor",JsonPrimitive("500")),
            latest.with("position_cost_basis_after_minor",JsonPrimitive(1.5)),latest.with("position_quantity_after_decimal_string",JsonPrimitive(true))))
            assertNull(overviewInventoryCost(owner,listOf(channel),listOf(asset),listOf(bad)))
    }
    @Test fun `unorderable calendar holds whole inventory without resurrecting an older snapshot`() {
        val channel=channel();val first=asset(channel);val second=asset(channel);val good=trade(first,7);val valid=trade(second,100)
        for(key in listOf("occurred_at","created_at")) {
            val bad=trade(second).with(key,JsonPrimitive("broken"))
            assertNull(overviewInventoryCost(owner,listOf(channel),listOf(first,second),listOf(good,valid,bad)))
        }
    }
    @Test fun `closed positions need no cost and negative numeric basis follows existing zero normalization`() {
        val channel=channel();val assets=(0..2).map {asset(channel)}
        val rows=listOf(trade(assets[0],quantity="0").with("position_cost_basis_after_minor",JsonPrimitive("broken")),
            trade(assets[1],quantity="-1").with("position_cost_basis_after_minor",JsonNull),trade(assets[2],cost=-1))
        minor(BigInteger.ZERO,overviewInventoryCost(owner,listOf(channel),assets,rows))
    }
    @Test fun `foreign malformed positions cannot poison owned inventory and latest snapshots remain exact`() {
        val channel=channel();val first=asset(channel);val second=asset(channel)
        val own=listOf(trade(first,Long.MAX_VALUE),trade(second,Long.MAX_VALUE))
        val foreign=trade(first).copy(ownerUserId=other).with("occurred_at",JsonPrimitive("broken"))
        minor(n(Long.MAX_VALUE)*BigInteger.TWO,overviewInventoryCost(owner,listOf(channel),listOf(first,second),own+foreign))
        minor(BigInteger.ZERO,overviewInventoryCost(owner,listOf(channel.with("is_archived",JsonPrimitive(true))),listOf(first,second),own))
    }
}
