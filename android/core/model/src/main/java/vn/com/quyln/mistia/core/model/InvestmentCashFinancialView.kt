package vn.com.quyln.mistia.core.model

import java.math.BigInteger

data class InvestmentCashFinancialView(val currencyCode:String?,val realizedProfitMinor:BigInteger?,val allocation:InvestmentCashAllocation?,
    val linkedWallet:LedgerWalletRecord?,val linkedActualMinor:BigInteger?,val linkedBalances:InvestmentLinkedWalletBalances?) {
    val availableMinor get()=allocation?.totalMinor?.max(BigInteger.ZERO)
    val shortfallMinor get()=realizedProfitMinor?.let{profit ->availableMinor?.let{(profit.max(BigInteger.ZERO)-it).max(BigInteger.ZERO)}}
}
fun investmentCashFinancialView(snapshot:InvestmentCashReadSnapshot,primaryCurrency:String):InvestmentCashFinancialView {
    snapshot.requireScoped()
    val owner=snapshot.owner
    val wallets=snapshot.rows.filter{it.entity==CloudEntity.LEDGER_WALLET.table}
    val currency=overviewInventoryAccountingCurrency(owner,wallets,primaryCurrency)?.investmentAccountingCode()
    val profit=investmentPersistedProfit(owner,snapshot.rows.filter{it.entity==CloudEntity.INVESTMENT_TRADE.table},currency)
    val walletSnapshot=snapshot.walletSnapshot()
    val allocation=currency?.let{runCatching{investmentCashAllocation(walletSnapshot,it)}.getOrNull()}
    val linked=runCatching {
        val system=wallets.singleOrNull{it.id==investmentSystemWalletId(owner)}?.let(::investmentLinkedWalletRecord)
        require(system?.kind==WalletKind.INVESTMENT && system.systemPurposeRawValue=="investmentProfit" && system.deletedAt==null && !system.isArchived)
        val id=system.investmentLinkedWalletId
        wallets.singleOrNull{it.id==id}?.let(::investmentLinkedWalletRecord)?.takeIf{it.deletedAt==null && !it.isArchived && it.kind!=null && it.kind !in setOf(WalletKind.CREDIT_CARD,WalletKind.INVESTMENT)}
    }.getOrNull()
    val actual=linked?.let{wallet ->financeWalletBalancesRaw(owner,snapshot.rows.filter{it.entity==CloudEntity.LEDGER_TRANSACTION.table},wallets,setOf(wallet.id))?.get(wallet.id)}
    val location=linked?.let{wallet ->allocation?.locations?.singleOrNull{it.walletId==wallet.id}}
    val balances=if(linked!=null && actual!=null && allocation!=null && (location==null || location.currencyCode==linked.currencyCode))
        investmentLinkedWalletBalances(actual,location?.originalTotalMinor ?: BigInteger.ZERO) else null
    return InvestmentCashFinancialView(currency,profit,allocation,linked,actual,balances)
}
