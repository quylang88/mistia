package vn.com.quyln.mistia.core.model

import java.math.BigInteger
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class InvestmentCashHistoryTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private fun id(value:Int)=java.util.UUID(0,value.toLong()).toString()
    private val source=id(900);private val destination=id(901);private val asset=id(902)
    private val now="2026-10-22T00:00:00Z"
    private fun n(value:Long)=BigInteger.valueOf(value)
    private fun row(entity:CloudEntity,key:Int,fields:JsonObject)=CloudRecord(entity.table,id(key),owner.value,JsonObject(buildJsonObject {
        put("id",id(key));put("user_id",owner.value);put("created_at",now);put("updated_at",now);put("deleted_at",JsonNull);put("sync_version",0L)
    }+fields),now,null,0)
    private fun ledger(event:Int,role:String?,from:String?=source,to:String?=destination)=row(CloudEntity.LEDGER_TRANSACTION,event,buildJsonObject {
        put("settlement_role_raw_value",role?.let(::JsonPrimitive) ?: JsonNull);put("source_wallet_id",from?.let(::JsonPrimitive) ?: JsonNull)
        put("destination_wallet_id",to?.let(::JsonPrimitive) ?: JsonNull);put("title","History title")
    })
    private fun posting(key:Int,event:Int,amount:Long,role:String="cashTransfer",cash:Boolean=true,wallet:String=source,trade:Int?=null,time:String=now)=row(CloudEntity.INVESTMENT_POSTING,key,buildJsonObject {
        put("event_id",id(event));put("ledger_transaction_id",id(event));put("trade_id",trade?.let{JsonPrimitive(id(it))} ?: JsonNull);put("asset_id",if(trade!=null)JsonPrimitive(asset) else JsonNull)
        put("wallet_id",wallet);put("role_raw_value",role);put("cash_bucket_raw_value",if(cash)JsonPrimitive("booked") else JsonNull);put("cash_origin_raw_value",if(cash)JsonPrimitive("manual") else JsonNull)
        put("amount_minor",amount);put("currency_code","VND");put("accounting_amount_minor",amount);put("accounting_currency_code","VND");put("occurred_at",time)
    })
    private fun trade(key:Int,kind:String="sell",profit:Long=100,gross:Long=500,unit:String?="box",quantity:String="1",funding:String?=source,time:String=now)=row(CloudEntity.INVESTMENT_TRADE,key,buildJsonObject {
        put("asset_id",asset);put("kind_raw_value",kind);put("quantity_decimal_string",quantity);put("unit_label",unit?.let(::JsonPrimitive) ?: JsonNull)
        put("funding_wallet_id",funding?.let(::JsonPrimitive) ?: JsonNull);put("capital_return_wallet_id",destination);put("occurred_at",time)
        put("realized_profit_loss_minor",profit);put("gross_amount_minor",gross);put("currency_code","JPY");put("accounting_currency_code","VND")
    })
    private fun read(vararg rows:CloudRecord,limit:Int?=null)=investmentCashHistory(InvestmentCashReadSnapshot(owner,rows.toList()),"VND",limit)
    private fun CloudRecord.with(key:String,value:JsonElement)=copy(payload=JsonObject(payload+(key to value)))

    @Test fun oneEventProducesOneEditableDepositWithLedgerWalletFlowAndExactCombinedAmount() {
        val items=read(ledger(1,"investmentCashDeposit"),posting(11,1,250),posting(12,1,350))
        val item=items.single();assertEquals(id(1),item.id);assertEquals(InvestmentCashHistoryKind.DEPOSIT,item.kind);assertEquals(n(600),item.accountingAmountMinor)
        assertEquals(source,item.sourceWalletId);assertEquals(destination,item.destinationWalletId);assertEquals(id(1),item.ledgerTransactionId);assertTrue(item.isEditable)
        assertEquals(InvestmentCashHistoryFilter.INCOMING,item.filter);assertEquals("VND",item.accountingCurrencyCode)
    }
    @Test fun allSourceKindPrecedenceAndFiltersRemainDistinctIncludingSaleLossAndLiquidation() {
        val rows=listOf(
            trade(1),posting(11,1,100,"cashAccrual",trade=1),ledger(1,"investmentCashWithdrawal"),
            trade(2,profit=-20),posting(12,2,-20,"cashAccrual",trade=2),
            trade(3,profit=-50,gross=0),posting(13,3,-50,"cashAccrual",trade=3),
            ledger(4,"investmentCashWithdrawal"),posting(14,4,10),posting(15,5,-10,"cashConsumption"),
            posting(16,6,-30,wallet=source),posting(17,6,30,wallet=destination),
            posting(18,7,-40,"transferOut",cash=false),posting(19,8,60,"transferIn",cash=false),posting(20,9,-5))
        val by=read(*rows.toTypedArray()).associateBy{it.id}
        assertEquals(InvestmentCashHistoryKind.REALIZED_PROFIT,by[id(1)]!!.kind);assertEquals(InvestmentCashHistoryKind.REALIZED_PROFIT,by[id(2)]!!.kind)
        assertEquals(InvestmentCashHistoryKind.LIQUIDATION,by[id(3)]!!.kind);assertEquals(InvestmentCashHistoryKind.WITHDRAWAL,by[id(4)]!!.kind)
        assertEquals(InvestmentCashHistoryKind.SPENDING,by[id(5)]!!.kind);assertEquals(InvestmentCashHistoryKind.MOVEMENT,by[id(6)]!!.kind)
        assertEquals(InvestmentCashHistoryKind.WITHDRAWAL,by[id(7)]!!.kind);assertEquals(InvestmentCashHistoryKind.DEPOSIT,by[id(8)]!!.kind)
        assertEquals(InvestmentCashHistoryKind.ADJUSTMENT,by[id(9)]!!.kind);assertEquals(n(30),by[id(6)]!!.accountingAmountMinor)
        val all=by.values.toList();assertEquals(all,filterInvestmentCashHistory(all,InvestmentCashHistoryFilter.ALL))
        assertEquals(setOf(id(1),id(8)),filterInvestmentCashHistory(all,InvestmentCashHistoryFilter.INCOMING).map{it.id}.toSet())
        assertEquals(setOf(id(2),id(3),id(4),id(5),id(7),id(9)),filterInvestmentCashHistory(all,InvestmentCashHistoryFilter.OUTGOING).map{it.id}.toSet())
        assertEquals(listOf(id(6)),filterInvestmentCashHistory(all,InvestmentCashHistoryFilter.MOVEMENT).map{it.id});assertFalse(by[id(7)]!!.isEditable)
    }
    @Test fun historyNeverSaturatesOrLosesTheMagnitudeOfLongMinimumOrCombinedLargePostings() {
        val by=read(ledger(1,"investmentCashDeposit"),posting(11,1,Long.MAX_VALUE),posting(12,1,Long.MAX_VALUE),
            ledger(2,"investmentCashWithdrawal"),posting(13,2,Long.MIN_VALUE)).associateBy{it.id}
        assertEquals(n(Long.MAX_VALUE)*BigInteger.TWO,by[id(1)]!!.accountingAmountMinor)
        assertEquals(n(Long.MIN_VALUE),by[id(2)]!!.accountingAmountMinor)
    }
    @Test fun orderingLimitsTombstonesAndNoncashExclusionsDoNotInventOrDuplicateEvents() {
        val old=posting(11,1,10,time="2026-10-20T00:00:00Z")
        val newest=posting(12,2,20);val tied=posting(13,3,30)
        val deleted=posting(14,4,40).copy(deletedAt=now).with("deleted_at",JsonPrimitive(now)).with("occurred_at",JsonNull)
        val ignored=posting(15,5,50,"funding",cash=false)
        val rows=arrayOf(old,newest,tied,deleted,ignored)
        assertEquals(listOf(id(2),id(3),id(1)),read(*rows).map{it.id});assertEquals(listOf(id(2),id(3)),read(*rows,limit=2).map{it.id})
        assertTrue(read(*rows,limit=0).isEmpty());assertTrue(read(*rows,limit=-1).isEmpty())
        val deletedLedger=ledger(2,"investmentCashDeposit").copy(deletedAt=now).with("deleted_at",JsonPrimitive(now))
        val item=read(newest,deletedLedger).single();assertEquals(InvestmentCashHistoryKind.ADJUSTMENT,item.kind);assertFalse(item.isEditable)
    }
    @Test fun fifoFundingWalletUsesMatchingUnitsStableDatesAndFoundationFoldWithoutCrossingAssets() {
        val buy1=trade(1,"buy",quantity="3",unit=" BÔX ",funding=source,time="2026-10-20T00:00:00Z")
        val buy2=trade(2,"buy",quantity="5",unit="pack",funding=destination,time="2026-10-20T01:00:00Z")
        val sellBox=trade(3,unit="bôx",quantity="2",funding=destination)
        val sellPack=trade(4,unit="PACK",quantity="2",funding=source)
        val unrelated=trade(5,"buy",quantity="10",unit="bôx",funding=destination,time="2026-10-19T00:00:00Z").with("asset_id",JsonPrimitive(id(903)))
        val by=read(unrelated,buy1,buy2,sellBox,sellPack,posting(13,3,100,"cashAccrual",trade=3),posting(14,4,100,"cashAccrual",trade=4)).associateBy{it.id}
        assertEquals(source,by[id(3)]!!.sourceWalletId);assertEquals(destination,by[id(4)]!!.sourceWalletId)
        assertEquals(destination,by[id(3)]!!.destinationWalletId);assertEquals(asset,by[id(3)]!!.assetId)
        assertEquals(500L,by[id(3)]!!.grossAmountMinor);assertEquals("JPY",by[id(3)]!!.grossCurrencyCode)
    }
    @Test fun detachedCashPostingRemainsReadableWithWalletFallbackAndUneditableLedgerReference() {
        val item=read(posting(11,1,-10,"cashConsumption",wallet=source)).single()
        assertEquals(source,item.sourceWalletId);assertNull(item.destinationWalletId);assertEquals(id(1),item.ledgerTransactionId);assertFalse(item.isEditable)
    }
    @Test fun ownerContradictionsAndMalformedRequiredCashNeverBecomeAnEmptyOrRelabelledHistory() {
        val good=posting(11,1,10)
        val broken=listOf(good.with("user_id",JsonPrimitive(id(999))),good.with("event_id",JsonNull),good.with("accounting_amount_minor",JsonPrimitive("10")),
            good.with("accounting_currency_code",JsonPrimitive("JPY")),good.with("occurred_at",JsonPrimitive("bad")),good.with("cash_bucket_raw_value",JsonPrimitive("unknown")))
        for(raw in broken)assertTrue("Accepted malformed history "+raw.payload,runCatching{read(raw)}.isFailure)
        assertTrue(runCatching{read(good,good)}.isFailure)
    }
    @Test fun realReconciliationAndCorrectionRolesRemainReadableForBookedAndUnreconciledHistory() {
        val by=read(posting(11,1,12,"cashReconciliation"),posting(12,2,-8,"cashCorrection").with("cash_bucket_raw_value",JsonPrimitive("unreconciled"))).associateBy{it.id}
        assertEquals(InvestmentCashHistoryKind.ADJUSTMENT,by[id(1)]!!.kind);assertEquals(n(12),by[id(1)]!!.accountingAmountMinor)
        assertEquals(InvestmentCashHistoryFilter.INCOMING,by[id(1)]!!.filter);assertEquals(InvestmentCashHistoryFilter.OUTGOING,by[id(2)]!!.filter)
        assertEquals(n(-8),by[id(2)]!!.accountingAmountMinor)
    }
    @Test fun aLiquidationCannotRelabelTradeProfitFromAnotherAccountingCurrency() {
        val wrong=trade(1,profit=-50,gross=0).with("accounting_currency_code",JsonPrimitive("JPY"))
        assertTrue(runCatching{read(wrong,posting(11,1,-50,"cashAccrual",trade=1))}.isFailure)
    }
}
