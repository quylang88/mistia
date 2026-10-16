package vn.com.quyln.mistia.core.model

import java.math.BigInteger
import java.util.UUID
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class OverviewAssetsTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other="99999999-9999-9999-9999-999999999999"
    private val time="2026-10-16T00:00:00Z"
    private fun raw(entity:CloudEntity,fields:JsonObject=JsonObject(emptyMap()),id:String=UUID.randomUUID().toString())=CloudRecord(entity.table,id,owner.value,
        JsonObject(buildJsonObject {put("id",id);put("user_id",owner.value);put("created_at",time);put("updated_at",time);put("is_archived",false)}+fields),time,null,0)
    private fun wallet(kind:WalletKind=WalletKind.CASH,opening:Long=1000,currency:String="JPY")=LedgerWalletRecord.fromCloudRecord(raw(CloudEntity.LEDGER_WALLET,buildJsonObject {
        put("name","Cash");put("kind_raw_value",kind.wireValue);put("currency_code",currency);put("opening_balance_minor",opening)
    }))
    private fun record(wallet:LedgerWalletRecord,kind:String="expense",amount:Long=100)=LedgerTransactionRecord.fromCloudRecord(raw(CloudEntity.LEDGER_TRANSACTION,buildJsonObject {
        put("title","Ordinary");put("primary_kind_raw_value",kind);put("entry_status_raw_value","posted");put("amount_minor",amount)
        put("source_wallet_id",wallet.id);put("source_currency_code",wallet.currencyCode);put("occurred_at",time)
    }))
    private fun total(wallets:List<LedgerWalletRecord>,records:List<LedgerTransactionRecord> = emptyList(),currency:String="JPY",rates:List<ExchangeRateSnapshot> = emptyList(),inventory:BigInteger=BigInteger.ZERO,inventoryCode:String=currency)=
        overviewTotalAssets(owner,wallets,records,currency,rates,inventory,inventoryCode)
    @Test fun `owned active noncredit wallets contribute current balances without including credit liability`() {
        val cash=wallet(opening=9007199254740993L);val bank=wallet(WalletKind.BANK,opening=500)
        val hidden=listOf(wallet().copy(ownerUserId=other),wallet().copy(isArchived=true),wallet().copy(deletedAt=time),wallet(WalletKind.CREDIT_CARD,opening=Long.MAX_VALUE))
        val rows=listOf(record(cash),record(bank,"income",25),record(cash).copy(entryStatusWireValue="draft"),record(cash).copy(isArchived=true),record(cash).copy(deletedAt=time))
        assertEquals(9007199254741418L,total(listOf(cash,bank)+hidden,rows))
    }
    @Test fun `cross currency transfer applies original source and explicit destination leg before wallet conversion`() {
        val cash=wallet();val vnd=wallet(currency="VND",opening=0)
        val row=record(cash,"transfer").copy(transferSubtypeWireValue="internalTransfer",destinationWalletId=vnd.id,destinationAmountMinor=16500,
            reportingCurrencyCode="VND",reportingAmountMinor=1)
        val rate=ExchangeRateSnapshot("JPY","VND","165","test",0,null)
        assertEquals(1000L,total(listOf(cash,vnd),listOf(row),rates=listOf(rate)))
        assertEquals(165000L,total(listOf(cash,vnd),listOf(row),"VND",listOf(rate)))
        val same=wallet(opening=0)
        assertEquals(1000L,total(listOf(cash,same),listOf(row.copy(destinationWalletId=same.id,destinationAmountMinor=null))))
    }
    @Test fun `future posted balance applies regardless of reporting month while foreign records cannot affect wallet`() {
        val cash=wallet();val row=record(cash).copy(occurredAt="2030-01-01T00:00:00Z")
        assertEquals(900L,total(listOf(cash),listOf(row,row.copy(ownerUserId=other),row.copy(entryStatusWireValue="unknown"))))
    }
    @Test fun `family and debt legs match wallet cash while shared principal is neutral and resale uses cost`() {
        val cash=wallet();val row=record(cash,"transfer")
        val outgoing=row.copy(transferSubtypeWireValue="familyTransfer",destinationWalletId=UUID.randomUUID().toString())
        val incoming=row.copy(transferSubtypeWireValue="familyTransfer",destinationWalletId=null)
        val lend=row.copy(transferSubtypeWireValue="debt",debtIntentWireValue="lend")
        val collect=lend.copy(debtIntentWireValue="collect")
        val shared=lend.copy(settlementRoleWireValue="sharedExpenseReceivable")
        val resale=lend.copy(settlementRoleWireValue="resaleReceivable",reportingExpenseMinor=30)
        assertEquals(970L,total(listOf(cash),listOf(outgoing,incoming,lend,collect,shared,shared.copy(settlementRoleWireValue="sharedExpensePayable"),resale)))
    }
    @Test fun `wallet currency conversion is per final wallet balance and missing rate contributes zero`() {
        val cash=wallet(opening=3);val vnd=wallet(opening=-1,currency="VND")
        val rate=ExchangeRateSnapshot("JPY","VND","2.5","test",0,null)
        assertEquals(-1L,total(listOf(cash,vnd),currency="VND"))
        assertEquals(7L,total(listOf(cash,vnd),currency="VND",rates=listOf(rate)))
        assertEquals(3L,total(listOf(cash,vnd),rates=listOf(rate)))
    }
    @Test fun `intermediate wallet balance conversion and totals retain overflow until final cancellation`() {
        val cash=wallet(opening=Long.MAX_VALUE);val row=record(cash,"income",Long.MAX_VALUE)
        val expense=record(cash,amount=Long.MAX_VALUE)
        for(rows in listOf(listOf(row,expense),listOf(expense,row))) assertEquals(Long.MAX_VALUE,total(listOf(cash),rows))
        val negative=wallet(opening=-Long.MAX_VALUE)
        assertEquals(0L,total(listOf(cash,negative),listOf(row,expense)))
        val rate=ExchangeRateSnapshot("JPY","VND","2","test",0,null)
        assertEquals(0L,total(listOf(cash,negative),listOf(row,expense),"VND",listOf(rate)))
        assertEquals(Long.MAX_VALUE,total(listOf(cash),listOf(record(cash,amount=Long.MIN_VALUE))))
    }
    @Test fun `inventory is converted in accounting currency and summed before final display clamp`() {
        val cash=wallet(opening=-Long.MAX_VALUE,currency="VND")
        val inventory=BigInteger.valueOf(Long.MAX_VALUE).multiply(BigInteger.TWO)
        assertEquals(Long.MAX_VALUE,total(listOf(cash),currency="VND",inventory=inventory))
        val rate=ExchangeRateSnapshot("JPY","VND","2.5","test",0,null)
        assertEquals(8L,total(emptyList(),currency="VND",rates=listOf(rate),inventory=BigInteger.valueOf(3),inventoryCode="JPY"))
        assertEquals(0L,total(emptyList(),currency="VND",inventory=BigInteger.valueOf(3),inventoryCode="JPY"))
    }
    private fun channel()=raw(CloudEntity.INVESTMENT_CHANNEL)
    private fun asset(channel:CloudRecord)=raw(CloudEntity.INVESTMENT_ASSET,buildJsonObject {put("channel_id",channel.id)})
    private fun trade(asset:CloudRecord,cost:Long=500,quantity:String="1",occurred:String=time,created:String=time,id:String=UUID.randomUUID().toString())=raw(CloudEntity.INVESTMENT_TRADE,buildJsonObject {
        put("channel_id",(asset.payload["channel_id"] as JsonPrimitive).content);put("asset_id",asset.id);put("position_cost_basis_after_minor",cost)
        put("position_quantity_after_decimal_string",quantity);put("occurred_at",occurred);put("created_at",created)
    },id)
    private fun CloudRecord.with(vararg fields:Pair<String,JsonElement>)=copy(payload=JsonObject(payload+fields.toMap()))
    @Test fun `inventory takes latest occurred created then stable UUID and ignores sold zero quantity`() {
        val channel=channel();val first=asset(channel);val sold=asset(channel)
        val trades=listOf(trade(first,100,occurred="2026-10-15T00:00:00Z"),trade(first,200,created="2026-10-16T00:00:01Z",id="00000000-0000-0000-0000-000000000001"),
            trade(first,300,created="2026-10-16T00:00:01Z",id="00000000-0000-0000-0000-000000000002"),trade(sold,900,quantity="0"))
        assertEquals(BigInteger.valueOf(300),overviewInventoryCost(owner,listOf(channel),listOf(first,sold),trades.reversed()))
    }
    @Test fun `inventory holds malformed latest position rather than resurrecting older cost and rejects foreign or inactive parents`() {
        val channel=channel();val asset=asset(channel);val old=trade(asset,100,occurred="2026-10-15T00:00:00Z");val latest=trade(asset)
        assertEquals(BigInteger.valueOf(500),overviewInventoryCost(owner,listOf(channel),listOf(asset),listOf(old,latest)))
        for(bad in listOf(latest.with("position_cost_basis_after_minor" to JsonPrimitive("broken")),latest.with("position_quantity_after_decimal_string" to JsonPrimitive("broken"))))
            assertEquals(BigInteger.ZERO,overviewInventoryCost(owner,listOf(channel),listOf(asset),listOf(old,bad)))
        for(bad in listOf(channel.copy(ownerUserId=other),channel.with("user_id" to JsonPrimitive(other)),channel.with("is_archived" to JsonPrimitive(true)),channel.copy(deletedAt=time)))
            assertEquals(BigInteger.ZERO,overviewInventoryCost(owner,listOf(bad),listOf(asset),listOf(latest)))
        for(bad in listOf(asset.copy(ownerUserId=other),asset.with("is_archived" to JsonPrimitive(true)),asset.with("id" to JsonPrimitive(UUID.randomUUID().toString()))))
            assertEquals(BigInteger.ZERO,overviewInventoryCost(owner,listOf(channel),listOf(bad),listOf(latest)))
        assertEquals(BigInteger.ZERO,overviewInventoryCost(owner,listOf(channel),listOf(asset),listOf(latest.copy(ownerUserId=other))))
    }
    @Test fun `foreign latest trades cannot overwrite owned inventory and moved asset keeps historical position`() {
        val oldChannel=channel();val current=channel();val asset=asset(current)
        val old=trade(asset,100,occurred="2026-10-15T00:00:00Z").with("channel_id" to JsonPrimitive(oldChannel.id))
        val latest=trade(asset,500)
        for(bad in listOf(latest.copy(ownerUserId=other),latest.with("user_id" to JsonPrimitive(other)),latest.with("id" to JsonPrimitive(UUID.randomUUID().toString())),
            latest.copy(entity=CloudEntity.INVESTMENT_ASSET.table),latest.copy(deletedAt=time),latest.with("deleted_at" to JsonPrimitive(time))))
            assertEquals(BigInteger.valueOf(100),overviewInventoryCost(owner,listOf(current),listOf(asset),listOf(old,bad)))
    }
    @Test fun `positive fractional positions retain cost while zero negative quantity and negative cost contribute zero`() {
        val channel=channel();val assets=(1..4).map {asset(channel)}
        val trades=listOf(trade(assets[0],101,"0.0000000000000000000000000000000000000001"),trade(assets[1],999,"0"),trade(assets[2],999,"-1"),trade(assets[3],-999))
        assertEquals(BigInteger.valueOf(101),overviewInventoryCost(owner,listOf(channel),assets,trades))
    }
    @Test fun `inventory invalid calendar holds asset and duplicate instant offsets still sort by created time`() {
        val channel=channel();val asset=asset(channel);val old=trade(asset,100)
        val latest=trade(asset,500,occurred="2026-10-16T09:00:00+09:00",created="2026-10-16T00:00:01Z")
        assertEquals(BigInteger.valueOf(500),overviewInventoryCost(owner,listOf(channel),listOf(asset),listOf(latest,old)))
        assertEquals(BigInteger.ZERO,overviewInventoryCost(owner,listOf(channel),listOf(asset),listOf(old,latest.with("occurred_at" to JsonPrimitive("broken")))))
    }
    @Test fun `wallet balances above Long range retain exact conversion until cross wallet cancellation`() {
        val positive=wallet(opening=Long.MAX_VALUE);val negative=wallet(opening=-Long.MAX_VALUE)
        val rows=listOf(record(positive,"income",Long.MAX_VALUE),record(negative,"income",-Long.MAX_VALUE))
        val rate=ExchangeRateSnapshot("JPY","VND","2","test",0,null)
        assertEquals(0L,total(listOf(positive,negative),rows,"VND",listOf(rate)))
    }
    @Test fun `inventory accounting currency uses independent owned metadata and holds malformed currency`() {
        val system=raw(CloudEntity.LEDGER_WALLET,buildJsonObject {put("currency_code"," vnd ");put("opening_balance_minor","broken")},investmentSystemWalletId(owner))
        assertEquals("VND",overviewInventoryAccountingCurrency(owner,listOf(system),"JPY"))
        assertEquals("JPY",overviewInventoryAccountingCurrency(owner,emptyList(),"JPY"))
        for(bad in listOf(system.copy(ownerUserId=other),system.with("user_id" to JsonPrimitive(other)),system.copy(deletedAt=time)))
            assertEquals("JPY",overviewInventoryAccountingCurrency(owner,listOf(bad),"JPY"))
        for(value in listOf(JsonNull,JsonPrimitive(true),JsonPrimitive("broken"))) assertNull(overviewInventoryAccountingCurrency(owner,listOf(system.with("currency_code" to value)),"JPY"))
    }
    @Test fun `system investment wallet UUID matches independent SHA256 golden and owner scope`() {
        assertEquals("b491e482-7dfc-5ecc-874f-d07ebc5ea67c",investmentSystemWalletId(owner))
        assertNotEquals(investmentSystemWalletId(owner),investmentSystemWalletId(UserId(other)))
    }
}
