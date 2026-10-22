package vn.com.quyln.mistia.core.model

import java.math.BigInteger
import java.util.UUID
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class FinanceWalletCashReadTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private fun n(value:Long)=BigInteger.valueOf(value)
    private fun row(entity:CloudEntity,fields:JsonObject):CloudRecord {
        val id=UUID.randomUUID().toString()
        return CloudRecord(entity.table,id,owner.value,JsonObject(fields+buildJsonObject{put("id",id);put("user_id",owner.value)}),null,null,0)
    }
    private fun wallet(amount:Long=0,code:String="JPY")=row(CloudEntity.LEDGER_WALLET,buildJsonObject{put("kind_raw_value","cash");put("currency_code",code);put("opening_balance_minor",amount)})
    private fun transfer(source:CloudRecord,destination:CloudRecord,amount:Long,incoming:Long?=null)=row(CloudEntity.LEDGER_TRANSACTION,buildJsonObject {
        put("primary_kind_raw_value","transfer");put("transfer_subtype_raw_value","internalTransfer");put("entry_status_raw_value","posted")
        put("source_wallet_id",source.id);put("destination_wallet_id",destination.id);put("amount_minor",amount);incoming?.let{put("destination_amount_minor",it)}
    })
    private fun CloudRecord.with(key:String,value:JsonElement)=copy(payload=JsonObject(payload+(key to value)))
    @Test fun selectedWalletRetainsIncomingFxPairAndDoesNotCancelAgainstItsSource() {
        val source=wallet(100,"USD");val target=wallet(10);val trade=transfer(source,target,50,7500)
        assertEquals(mapOf(target.id to n(7510)),financeWalletBalancesRaw(owner,listOf(trade),listOf(source,target),setOf(target.id)))
        assertEquals(mapOf(source.id to n(50),target.id to n(7510)),financeWalletBalancesRaw(owner,listOf(trade),listOf(source,target)))
    }
    @Test fun legacyIncomingRequiresCompatibleSourceCurrencyMetadata() {
        val source=wallet(10);val target=wallet(10);val trade=transfer(source,target,5)
        assertEquals(n(15),financeWalletBalancesRaw(owner,listOf(trade),listOf(source,target),setOf(target.id))?.get(target.id))
        assertNull(financeWalletBalancesRaw(owner,listOf(trade),listOf(source.with("currency_code",JsonPrimitive("USD")),target),setOf(target.id)))
    }
    @Test fun irrelevantOpeningDamageCannotHideReadableSelectedCashButItsConsumedLegCan() {
        val source=wallet(20).with("opening_balance_minor",JsonPrimitive("broken"));val target=wallet(10)
        val trade=transfer(source,target,5)
        assertEquals(n(15),financeWalletBalancesRaw(owner,listOf(trade),listOf(source,target),setOf(target.id))?.get(target.id))
        assertNull(financeWalletBalancesRaw(owner,listOf(trade.with("amount_minor",JsonPrimitive("broken"))),listOf(source,target),setOf(target.id)))
        assertNull(financeWalletBalancesRaw(owner,listOf(trade),listOf(source,target)))
    }
    @Test fun balancesRemainExactBeyondLongAndMatchOverviewAtSameCurrency() {
        val source=wallet(Long.MAX_VALUE);val target=wallet(Long.MAX_VALUE);val income=transfer(source,target,-Long.MAX_VALUE)
        val wallets=listOf(source,target);val rows=listOf(income)
        val balances=financeWalletBalancesRaw(owner,rows,wallets)!!
        assertEquals(n(Long.MAX_VALUE)*BigInteger.TWO,balances[source.id]);assertEquals(BigInteger.ZERO,balances[target.id])
        assertEquals(overviewTotalAssets(owner,wallets.map(LedgerWalletRecord::fromCloudRecord),rows.map(LedgerTransactionRecord::fromCloudRecord),"JPY"),balances.values.reduce(BigInteger::add))
    }
    @Test fun persistedProfitSharesOverviewPolicyWithoutNeedingAssetOrPositionMetadata() {
        val first=row(CloudEntity.INVESTMENT_TRADE,buildJsonObject{put("realized_profit_loss_minor",Long.MAX_VALUE);put("accounting_currency_code","JPY")})
        val second=first.copy(id=UUID.randomUUID().toString()).let{it.with("id",JsonPrimitive(it.id))}
        val rows=listOf(first,second)
        assertEquals(n(Long.MAX_VALUE)*BigInteger.TWO,investmentPersistedProfit(owner,rows,"JPY"))
        assertEquals(overviewInvestmentSummary(owner,OverviewFinancialReadSnapshot(owner,rows),"JPY").realizedProfitLossMinor,investmentPersistedProfit(owner,rows,"JPY"))
        assertNull(investmentPersistedProfit(owner,listOf(first.with("realized_profit_loss_minor",JsonPrimitive("broken"))),"JPY"))
        assertNull(investmentPersistedProfit(owner,listOf(first),"USD"))
    }
    @Test fun zeroCashDoesNotRequireUnusedCurrencyMetadataInOverviewTotals() {
        val empty=wallet().with("currency_code",JsonNull)
        assertEquals(BigInteger.ZERO,financeWalletCashTotalRaw(owner,emptyList(),listOf(empty),"JPY"))
        assertNull(financeWalletCashTotalRaw(owner,emptyList(),listOf(wallet(1).with("currency_code",JsonNull)),"JPY"))
    }

}
