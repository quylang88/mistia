package vn.com.quyln.mistia.core.model

import java.math.BigInteger
import kotlinx.serialization.json.*

enum class InvestmentCashBucket { BOOKED, UNRECONCILED }
enum class InvestmentCashReadError { UNREADABLE_SOURCE, INVALID_CURRENCY, UNREADABLE_CASH, MIXED_ACCOUNTING_CURRENCY, MIXED_WALLET_CURRENCY }
class InvestmentCashReadException(val reason:InvestmentCashReadError):IllegalArgumentException(reason.name)

data class InvestmentCashLocation(
    val walletId:String,val currencyCode:String,
    val bookedMinor:BigInteger,val unreconciledMinor:BigInteger,
    val originalBookedMinor:BigInteger,val originalUnreconciledMinor:BigInteger,
) {
    val totalMinor get()=bookedMinor+unreconciledMinor
    val originalTotalMinor get()=originalBookedMinor+originalUnreconciledMinor
}
data class InvestmentCashAllocation(val accountingCurrencyCode:String,val locations:List<InvestmentCashLocation>) {
    val bookedMinor get()=locations.fold(BigInteger.ZERO){sum,location ->sum+location.bookedMinor}
    val unreconciledMinor get()=locations.fold(BigInteger.ZERO){sum,location ->sum+location.unreconciledMinor}
    val totalMinor get()=bookedMinor+unreconciledMinor
}

fun investmentCashAllocation(snapshot:InvestmentWalletSnapshot,accountingCurrencyCode:String):InvestmentCashAllocation {
    fun fail(reason:InvestmentCashReadError):Nothing=throw InvestmentCashReadException(reason)
    val accountCode=investmentAssetCurrency(accountingCurrencyCode) ?: fail(InvestmentCashReadError.INVALID_CURRENCY)
    if(financeRawUuid(snapshot.owner.value)!=snapshot.owner.value || snapshot.rows.any { row ->
        val entity=CloudEntity.fromTable(row.entity)
        entity==null || entity !in InvestmentWalletSnapshot.entities || !row.financeRawIdentity(snapshot.owner,entity,true) || financeRawUuid(row.id)!=row.id
    } || snapshot.rows.map{it.entity to it.id}.distinct().size!=snapshot.rows.size)fail(InvestmentCashReadError.UNREADABLE_SOURCE)
    data class Totals(val currency:String,var booked:BigInteger=BigInteger.ZERO,var unreconciled:BigInteger=BigInteger.ZERO,
        var originalBooked:BigInteger=BigInteger.ZERO,var originalUnreconciled:BigInteger=BigInteger.ZERO)
    val totals=linkedMapOf<String,Totals>()
    val noncash=setOf("funding","capitalReturn","realizedProfit","transferOut","transferIn")
    for(raw in snapshot.rows.filter{it.entity==CloudEntity.INVESTMENT_POSTING.table}) {
        val deleted=raw.financeRawDeleted(true)
        if(deleted==true)continue
        val p=raw.payload
        val bucket=when(p.financeRawString("cash_bucket_raw_value")) {
            "booked"->InvestmentCashBucket.BOOKED
            "unreconciled"->InvestmentCashBucket.UNRECONCILED
            null->{
                if((p["cash_bucket_raw_value"]==null || p["cash_bucket_raw_value"]==JsonNull) && p.financeRawString("role_raw_value") in noncash)continue
                fail(InvestmentCashReadError.UNREADABLE_CASH)
            }
            else->fail(InvestmentCashReadError.UNREADABLE_CASH)
        }
        if(deleted==null)fail(InvestmentCashReadError.UNREADABLE_CASH)
        val wallet=p.financeRawReference("wallet_id")
        if(!wallet.readable || wallet.id==null)fail(InvestmentCashReadError.UNREADABLE_CASH)
        val currency=p.financeRawString("currency_code")?.let(::investmentAssetCurrency) ?: fail(InvestmentCashReadError.UNREADABLE_CASH)
        val accounting=p.financeRawString("accounting_currency_code")?.let(::investmentAssetCurrency) ?: fail(InvestmentCashReadError.UNREADABLE_CASH)
        if(accounting!=accountCode)fail(InvestmentCashReadError.MIXED_ACCOUNTING_CURRENCY)
        val local=p.financeRawLong("amount_minor")?.let(BigInteger::valueOf) ?: fail(InvestmentCashReadError.UNREADABLE_CASH)
        val value=p.financeRawLong("accounting_amount_minor")?.let(BigInteger::valueOf) ?: fail(InvestmentCashReadError.UNREADABLE_CASH)
        if(currency==accountCode && local!=value)fail(InvestmentCashReadError.UNREADABLE_CASH)
        val total=totals.getOrPut(wallet.id){Totals(currency)}
        if(total.currency!=currency)fail(InvestmentCashReadError.MIXED_WALLET_CURRENCY)
        when(bucket) {
            InvestmentCashBucket.BOOKED->{total.booked+=value;total.originalBooked+=local}
            InvestmentCashBucket.UNRECONCILED->{total.unreconciled+=value;total.originalUnreconciled+=local}
        }
    }
    val locations=totals.map{(wallet,total)->InvestmentCashLocation(wallet,total.currency,total.booked,total.unreconciled,total.originalBooked,total.originalUnreconciled)}
        .filter{it.bookedMinor.signum()!=0 || it.unreconciledMinor.signum()!=0 || it.originalBookedMinor.signum()!=0 || it.originalUnreconciledMinor.signum()!=0}
        .sortedBy{it.walletId}
    return InvestmentCashAllocation(accountCode,locations)
}

enum class InvestmentFundUsageOutcome { ORDINARY_FUNDS_ONLY, REQUIRES_CONFIRMATION, INSUFFICIENT_FUNDS }
data class InvestmentFundUsagePreview(
    val currencyCode:String,val requestedMinor:Long,val ordinaryAvailableMinor:BigInteger,
    val bookedToUseMinor:BigInteger,val unreconciledToUseMinor:BigInteger,val remainingInvestmentInWalletMinor:BigInteger,
    val outcome:InvestmentFundUsageOutcome,
) {val investmentToUseMinor get()=bookedToUseMinor+unreconciledToUseMinor}

/**
 * Every numeric input is in the declared wallet currency. A null location
 * denotes a successful read with no cash at that wallet. Financial writes
 * additionally require current spendable-cash validation.
 */
fun investmentFundUsagePreview(requestedMinor:Long,visibleWalletBalanceMinor:BigInteger,location:InvestmentCashLocation?,currencyCode:String,
    spendableWalletBalanceMinor:BigInteger?=null):InvestmentFundUsagePreview {
    val code=investmentAssetCurrency(currencyCode) ?: throw InvestmentCashReadException(InvestmentCashReadError.INVALID_CURRENCY)
    if(location!=null && investmentAssetCurrency(location.currencyCode)!=code)throw InvestmentCashReadException(InvestmentCashReadError.MIXED_WALLET_CURRENCY)
    val requested=requestedMinor.coerceAtLeast(0);val request=BigInteger.valueOf(requested)
    val booked=(location?.originalBookedMinor ?: BigInteger.ZERO).max(BigInteger.ZERO)
    val unreconciled=(location?.originalUnreconciledMinor ?: BigInteger.ZERO).max(BigInteger.ZERO)
    val ordinary=(visibleWalletBalanceMinor-booked).max(BigInteger.ZERO)
    var remaining=(request-ordinary).max(BigInteger.ZERO)
    val bookedToUse=booked.min(remaining);remaining-=bookedToUse
    val unreconciledToUse=unreconciled.min(remaining);remaining-=unreconciledToUse
    val insufficient=spendableWalletBalanceMinor?.let{it.max(BigInteger.ZERO)<request} ?: (remaining.signum()>0)
    val outcome=when {
        insufficient->InvestmentFundUsageOutcome.INSUFFICIENT_FUNDS
        bookedToUse.signum()>0 || unreconciledToUse.signum()>0->InvestmentFundUsageOutcome.REQUIRES_CONFIRMATION
        else->InvestmentFundUsageOutcome.ORDINARY_FUNDS_ONLY
    }
    val investment=(location?.originalTotalMinor ?: BigInteger.ZERO)-bookedToUse-unreconciledToUse
    return InvestmentFundUsagePreview(code,requested,ordinary,bookedToUse,unreconciledToUse,investment.max(BigInteger.ZERO),outcome)
}

data class InvestmentLinkedWalletBalances(val actualMinor:BigInteger,val ordinaryMinor:BigInteger,val investmentMinor:BigInteger)
fun investmentLinkedWalletBalances(ledgerBalanceMinor:BigInteger,allocatedInvestmentMinor:BigInteger):InvestmentLinkedWalletBalances {
    val investment=allocatedInvestmentMinor.max(BigInteger.ZERO)
    return InvestmentLinkedWalletBalances(ledgerBalanceMinor,ledgerBalanceMinor-investment,investment)
}
