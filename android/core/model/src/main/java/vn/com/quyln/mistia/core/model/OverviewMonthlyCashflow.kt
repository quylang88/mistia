package vn.com.quyln.mistia.core.model

import java.time.Instant
import java.time.YearMonth
import java.time.ZoneId
import java.math.BigInteger
import java.util.Locale

data class OverviewMonthlyCashflow(val month:YearMonth,val incomeMinor:Long,val expenseMinor:Long)

fun overviewMonthlyCashflow(owner:UserId,records:List<LedgerTransactionRecord>,wallets:List<LedgerWalletRecord>,
    reportingCurrency:String,rates:List<ExchangeRateSnapshot> = emptyList(),knownTitles:Map<GeneratedTransactionTitle,Collection<String>> = emptyMap(),
    reference:Instant,zone:ZoneId):List<OverviewMonthlyCashflow> {
    val current=YearMonth.from(reference.atZone(zone))
    val walletKinds=wallets.filter {it.ownerUserId==owner.value && it.deletedAt==null}.associate {it.id to it.kind}
    val totals=mutableMapOf<YearMonth,Pair<BigInteger,BigInteger>>()
    for(record in records) {
        if(record.ownerUserId!=owner.value || record.deletedAt!=null || record.isArchived || record.entryStatus!=TransactionEntryStatus.POSTED || record.primaryKind==null) continue
        val expense=reportedOverviewExpense(record,walletKinds[record.sourceWalletId],knownTitles)
        val income=reportedOverviewIncome(record,knownTitles)
        if(expense==0L && income==0L) continue
        val month=runCatching {YearMonth.from(Instant.parse(record.occurredAt).atZone(zone))}.getOrNull() ?: continue
        if(month>current) continue
        val previous=totals[month] ?: (BigInteger.ZERO to BigInteger.ZERO)
        totals[month]=(previous.first+planningMoneyMinorExact(income,record.sourceCurrencyCode,reportingCurrency,rates)) to
            (previous.second+planningMoneyMinorExact(expense,record.sourceCurrencyCode,reportingCurrency,rates))
    }
    val result=mutableListOf<OverviewMonthlyCashflow>()
    var month=totals.keys.minOrNull() ?: current
    while(month<=current) {
        val total=totals[month] ?: (BigInteger.ZERO to BigInteger.ZERO)
        result+=OverviewMonthlyCashflow(month,total.first.overviewClamped(),total.second.overviewClamped())
        month=month.plusMonths(1)
    }
    return result
}

internal fun reportedOverviewExpense(record:LedgerTransactionRecord,walletKind:WalletKind?,titles:Map<GeneratedTransactionTitle,Collection<String>>):Long {
    record.reportingExpenseMinor?.let {return it}
    val adjustment=record.isOverviewAdjustment(titles)
    val installment=record.categoryId==SystemCategoryIdentity.canonicalId("loan_repayment")
    val paidFor=record.primaryKind==TransactionPrimaryKind.TRANSFER && record.transferSubtype==TransactionTransferSubtype.DEBT &&
        record.debtIntent==TransactionDebtIntent.BORROW && record.sourceWalletId==null && record.categoryId!=null
    if(paidFor && !adjustment && !installment) return record.amountMinor
    val payment=walletKind!=WalletKind.CREDIT_CARD && listOf("card payment","thanh toan the","thanh toán thẻ","カード支払い").any {record.title.lowercase(Locale.ROOT).contains(it)}
    return if(record.primaryKind==TransactionPrimaryKind.EXPENSE && !adjustment && !installment && !payment) record.amountMinor else 0
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
private fun BigInteger.overviewClamped():Long=max(BigInteger.valueOf(Long.MIN_VALUE)).min(BigInteger.valueOf(Long.MAX_VALUE)).toLong()
