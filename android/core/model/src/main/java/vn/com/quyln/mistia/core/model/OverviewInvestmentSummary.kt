package vn.com.quyln.mistia.core.model

import java.math.BigInteger
import java.util.Currency

/** Independent source-currency amounts; null retains an unreadable required dependency. */
data class OverviewInvestmentSummary(val capitalMinor:BigInteger?,val realizedProfitLossMinor:BigInteger?,val currencyCode:String?)

fun overviewInvestmentSummary(owner:UserId,snapshot:OverviewFinancialReadSnapshot?,primaryCurrency:String):OverviewInvestmentSummary {
    if(snapshot==null || snapshot.owner!=owner) return OverviewInvestmentSummary(null,null,null)
    val wallets=snapshot.records(CloudEntity.LEDGER_WALLET)
    val trades=snapshot.records(CloudEntity.INVESTMENT_TRADE)
    val currency=overviewInventoryAccountingCurrency(owner,wallets,primaryCurrency)?.investmentAccountingCode()
    val capital=overviewInventoryCostInCurrency(owner,snapshot.records(CloudEntity.INVESTMENT_CHANNEL),snapshot.records(CloudEntity.INVESTMENT_ASSET),trades,currency)
    val profit=investmentPersistedProfit(owner,trades,currency)
    return OverviewInvestmentSummary(capital,profit,currency)
}

/** All-time persisted realized profit, independent of asset visibility, positions and FIFO. */
fun investmentPersistedProfit(owner:UserId,trades:List<CloudRecord>,currency:String?):BigInteger? {
    var profit:BigInteger?=BigInteger.ZERO
    for(raw in trades) {
        if(!raw.financeRawIdentity(owner,CloudEntity.INVESTMENT_TRADE,true) || raw.financeRawDeleted()==true) continue
        val amount=raw.payload.financeRawLong("realized_profit_loss_minor")
        if(amount==0L) continue
        val source=raw.payload.financeRawString("accounting_currency_code")?.investmentAccountingCode()
        if(amount==null || raw.financeRawDeleted()==null || source==null || currency==null || source!=currency) {profit=null;break}
        profit=profit?.plus(BigInteger.valueOf(amount))
    }
    return profit
}

internal fun String.investmentAccountingCode():String? = financeReportingCode()?.takeIf {code ->
    runCatching {Currency.getInstance(code).defaultFractionDigits>=0}.getOrDefault(false)
}
