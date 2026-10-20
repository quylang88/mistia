package vn.com.quyln.mistia.core.model

import java.time.Instant
import java.time.YearMonth
import java.time.ZoneId
import java.math.BigInteger
import java.util.Locale

data class OverviewMonthlyCashflow(val month:YearMonth,val incomeMinor:BigInteger?,val expenseMinor:BigInteger?) {
    constructor(month:YearMonth,incomeMinor:Long,expenseMinor:Long):this(month,BigInteger.valueOf(incomeMinor),BigInteger.valueOf(expenseMinor))
}

fun overviewMonthlyCashflow(owner:UserId,records:List<LedgerTransactionRecord>,wallets:List<LedgerWalletRecord>,
    reportingCurrency:String,rates:List<ExchangeRateSnapshot> = emptyList(),knownTitles:Map<GeneratedTransactionTitle,Collection<String>> = emptyMap(),
    reference:Instant,zone:ZoneId):List<OverviewMonthlyCashflow> {
    val current=YearMonth.from(reference.atZone(zone))
    val ownedWallets=wallets.filter {it.ownerUserId==owner.value && it.deletedAt==null}.associateBy {it.id}
    val target=reportingCurrency.overviewCurrencyCode() ?: reportingCurrency
    data class Totals(var income:BigInteger?=BigInteger.ZERO,var expense:BigInteger?=BigInteger.ZERO)
    val totals=mutableMapOf<YearMonth,Totals>()
    for(record in records) {
        if(record.ownerUserId!=owner.value || record.deletedAt!=null || record.isArchived || record.entryStatus!=TransactionEntryStatus.POSTED || record.primaryKind==null) continue
        val wallet=ownedWallets[record.sourceWalletId]
        val expense=reportedOverviewExpense(record,wallet?.kind,knownTitles)
        val income=reportedOverviewIncome(record,knownTitles)
        if(expense==0L && income==0L) continue
        val month=runCatching {YearMonth.from(Instant.parse(record.occurredAt).atZone(zone))}.getOrNull() ?: continue
        if(month>current) continue
        val source=record.sourceCurrencyCode?.takeIf(String::isNotBlank) ?: wallet?.currencyCode ?: "JPY"
        val total=totals.getOrPut(month) {Totals()}
        // Availability is independent and sticky per direction; incomplete sums never become partial totals.
        total.income=total.income?.let {subtotal ->overviewMoneyMinorExact(income,source,target,rates)?.let(subtotal::plus)}
        total.expense=total.expense?.let {subtotal ->overviewMoneyMinorExact(expense,source,target,rates)?.let(subtotal::plus)}
    }
    val result=mutableListOf<OverviewMonthlyCashflow>()
    var month=totals.keys.minOrNull() ?: current
    while(month<=current) {
        val total=totals[month] ?: Totals()
        result+=OverviewMonthlyCashflow(month,total.income,total.expense)
        month=month.plusMonths(1)
    }
    return result
}

internal fun reportedOverviewExpense(record:LedgerTransactionRecord,walletKind:WalletKind?,titles:Map<GeneratedTransactionTitle,Collection<String>>):Long {
    record.reportingExpenseMinor?.let {return it}
    return if(isOverviewExpenseSpending(record,walletKind,titles)) record.amountMinor else 0
}

fun isOverviewExpenseSpending(record:LedgerTransactionRecord,walletKind:WalletKind?,titles:Map<GeneratedTransactionTitle,Collection<String>> = emptyMap()):Boolean {
    val adjustment=record.isOverviewAdjustment(titles)
    val installment=record.categoryId==SystemCategoryIdentity.canonicalId("loan_repayment")
    val paidFor=record.primaryKind==TransactionPrimaryKind.TRANSFER && record.transferSubtype==TransactionTransferSubtype.DEBT &&
        record.debtIntent==TransactionDebtIntent.BORROW && record.sourceWalletId==null && record.categoryId!=null
    if(paidFor && !adjustment && !installment) return true
    val payment=walletKind!=WalletKind.CREDIT_CARD && listOf("card payment","thanh toan the","thanh toán thẻ","カード支払い").any {record.title.lowercase(Locale.ROOT).contains(it)}
    return record.primaryKind==TransactionPrimaryKind.EXPENSE && !adjustment && !installment && !payment
}

private fun reportedOverviewIncome(record:LedgerTransactionRecord,titles:Map<GeneratedTransactionTitle,Collection<String>>):Long {
    val legacy=record.primaryKind==TransactionPrimaryKind.INCOME && (record.categoryId==SystemCategoryIdentity.canonicalId("people_repayment") ||
        record.title.matchesOverviewTitle(titles[GeneratedTransactionTitle.COLLECT].orEmpty()+titles[GeneratedTransactionTitle.BORROW].orEmpty()))
    if(record.transferSubtype==TransactionTransferSubtype.DEBT || record.debtIntent!=null || legacy)
        return if(record.settlementRoleWireValue=="resaleReceipt") record.reportingIncomeMinor ?: 0 else 0
    record.reportingIncomeMinor?.let {return it}
    return if(record.primaryKind==TransactionPrimaryKind.INCOME && !record.isOverviewAdjustment(titles)) record.amountMinor else 0
}

private fun LedgerTransactionRecord.isOverviewAdjustment(titles:Map<GeneratedTransactionTitle,Collection<String>>)=
    categoryId in setOf(TransactionCategoryRecord.BALANCE_ADJUSTMENT_EXPENSE_ID,TransactionCategoryRecord.BALANCE_ADJUSTMENT_INCOME_ID) ||
        title.matchesOverviewTitle(titles[GeneratedTransactionTitle.BALANCE_ADJUSTMENT].orEmpty())
private fun String.matchesOverviewTitle(titles:Collection<String>)=trim().isNotEmpty() && titles.any {it.trim().equals(trim(),ignoreCase=true)}
