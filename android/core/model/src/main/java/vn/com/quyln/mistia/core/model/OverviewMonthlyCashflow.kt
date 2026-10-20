package vn.com.quyln.mistia.core.model

import java.time.Instant
import java.time.YearMonth
import java.time.ZoneId
import java.math.BigInteger
import java.util.Locale

data class OverviewMonthlyCashflow(val month:YearMonth,val incomeMinor:BigInteger?,val expenseMinor:BigInteger?) {
    constructor(month:YearMonth,incomeMinor:Long,expenseMinor:Long):this(month,BigInteger.valueOf(incomeMinor),BigInteger.valueOf(expenseMinor))
}

/** Read-only report effect: null money/currency/calendar retains an unreadable required dependency. */
data class OverviewReportingEffect(val occurredAt:Instant?,val sourceCurrencyCode:String?,val incomeMinor:Long?,val expenseMinor:Long?)

fun overviewMonthlyCashflowEffects(effects:List<OverviewReportingEffect>,reportingCurrency:String,
    rates:List<ExchangeRateSnapshot> = emptyList(),reference:Instant,zone:ZoneId):List<OverviewMonthlyCashflow> {
    val current=YearMonth.from(reference.atZone(zone))
    data class Totals(var income:BigInteger?=BigInteger.ZERO,var expense:BigInteger?=BigInteger.ZERO)
    val totals=mutableMapOf<YearMonth,Totals>()
    var undatedIncome=false;var undatedExpense=false
    fun convert(amount:Long?,source:String?):BigInteger? {
        if(amount==0L) return BigInteger.ZERO
        return if(amount==null || source==null) null else overviewMoneyMinorExact(amount,source,reportingCurrency,rates)
    }
    for(effect in effects) {
        if(effect.incomeMinor==0L && effect.expenseMinor==0L) continue
        val month=runCatching {effect.occurredAt?.let {YearMonth.from(it.atZone(zone))}}.getOrNull()
        if(month==null) {
            if(effect.incomeMinor!=0L) undatedIncome=true
            if(effect.expenseMinor!=0L) undatedExpense=true
            continue
        }
        if(month>current) continue
        val total=totals.getOrPut(month) {Totals()}
        total.income=total.income?.let {sum ->convert(effect.incomeMinor,effect.sourceCurrencyCode)?.let(sum::plus)}
        total.expense=total.expense?.let {sum ->convert(effect.expenseMinor,effect.sourceCurrencyCode)?.let(sum::plus)}
    }
    val result=mutableListOf<OverviewMonthlyCashflow>()
    var month=totals.keys.minOrNull() ?: current
    while(month<=current) {
        val total=totals[month] ?: Totals()
        result+=OverviewMonthlyCashflow(month,if(undatedIncome) null else total.income,if(undatedExpense) null else total.expense)
        month=month.plusMonths(1)
    }
    return result
}

fun overviewMonthlyCashflow(owner:UserId,records:List<LedgerTransactionRecord>,wallets:List<LedgerWalletRecord>,
    reportingCurrency:String,rates:List<ExchangeRateSnapshot> = emptyList(),knownTitles:Map<GeneratedTransactionTitle,Collection<String>> = emptyMap(),
    reference:Instant,zone:ZoneId):List<OverviewMonthlyCashflow> {
    val ownedWallets=wallets.filter {it.ownerUserId==owner.value && it.deletedAt==null}.associateBy {it.id}
    val effects=mutableListOf<OverviewReportingEffect>()
    for(record in records) {
        if(record.ownerUserId!=owner.value || record.deletedAt!=null || record.isArchived || record.entryStatus!=TransactionEntryStatus.POSTED || record.primaryKind==null) continue
        val wallet=ownedWallets[record.sourceWalletId]
        val expense=reportedOverviewExpense(record,wallet?.kind,knownTitles)
        val income=reportedOverviewIncome(record,knownTitles)
        if(expense==0L && income==0L) continue
        val occurred=runCatching {Instant.parse(record.occurredAt)}.getOrNull() ?: continue
        val source=record.sourceCurrencyCode?.takeIf(String::isNotBlank) ?: wallet?.currencyCode ?: "JPY"
        effects+=OverviewReportingEffect(occurred,source,income,expense)
    }
    return overviewMonthlyCashflowEffects(effects,reportingCurrency,rates,reference,zone)
}

enum class OverviewReportingSource { NONE, ORIGINAL, EXPENSE_OVERRIDE, INCOME_OVERRIDE }

fun overviewExpenseSource(record:LedgerTransactionRecord,walletKind:WalletKind?,titles:Map<GeneratedTransactionTitle,Collection<String>> = emptyMap()):OverviewReportingSource =
    if(record.reportingExpenseMinor!=null) OverviewReportingSource.EXPENSE_OVERRIDE
    else if(isOverviewExpenseSpending(record,walletKind,titles)) OverviewReportingSource.ORIGINAL else OverviewReportingSource.NONE

private fun OverviewReportingSource.amount(record:LedgerTransactionRecord):Long=when(this) {
    OverviewReportingSource.NONE -> 0
    OverviewReportingSource.ORIGINAL -> record.amountMinor
    OverviewReportingSource.EXPENSE_OVERRIDE -> checkNotNull(record.reportingExpenseMinor)
    OverviewReportingSource.INCOME_OVERRIDE -> checkNotNull(record.reportingIncomeMinor)
}

internal fun reportedOverviewExpense(record:LedgerTransactionRecord,walletKind:WalletKind?,titles:Map<GeneratedTransactionTitle,Collection<String>>):Long =
    overviewExpenseSource(record,walletKind,titles).amount(record)

fun isOverviewExpenseSpending(record:LedgerTransactionRecord,walletKind:WalletKind?,titles:Map<GeneratedTransactionTitle,Collection<String>> = emptyMap()):Boolean {
    val adjustment=record.isOverviewAdjustment(titles)
    val installment=record.categoryId==SystemCategoryIdentity.canonicalId("loan_repayment")
    val paidFor=record.primaryKind==TransactionPrimaryKind.TRANSFER && record.transferSubtype==TransactionTransferSubtype.DEBT &&
        record.debtIntent==TransactionDebtIntent.BORROW && record.sourceWalletId==null && record.categoryId!=null
    if(paidFor && !adjustment && !installment) return true
    val payment=walletKind!=WalletKind.CREDIT_CARD && listOf("card payment","thanh toan the","thanh toán thẻ","カード支払い").any {record.title.lowercase(Locale.ROOT).contains(it)}
    return record.primaryKind==TransactionPrimaryKind.EXPENSE && !adjustment && !installment && !payment
}

fun overviewIncomeSource(record:LedgerTransactionRecord,titles:Map<GeneratedTransactionTitle,Collection<String>> = emptyMap()):OverviewReportingSource {
    val legacy=record.primaryKind==TransactionPrimaryKind.INCOME && (record.categoryId==SystemCategoryIdentity.canonicalId("people_repayment") ||
        record.title.matchesOverviewTitle(titles[GeneratedTransactionTitle.COLLECT].orEmpty()+titles[GeneratedTransactionTitle.BORROW].orEmpty()))
    if(record.transferSubtype==TransactionTransferSubtype.DEBT || record.debtIntent!=null || legacy)
        return if(record.settlementRoleWireValue=="resaleReceipt" && record.reportingIncomeMinor!=null) OverviewReportingSource.INCOME_OVERRIDE else OverviewReportingSource.NONE
    if(record.reportingIncomeMinor!=null) return OverviewReportingSource.INCOME_OVERRIDE
    return if(record.primaryKind==TransactionPrimaryKind.INCOME && !record.isOverviewAdjustment(titles)) OverviewReportingSource.ORIGINAL else OverviewReportingSource.NONE
}

private fun reportedOverviewIncome(record:LedgerTransactionRecord,titles:Map<GeneratedTransactionTitle,Collection<String>>):Long = overviewIncomeSource(record,titles).amount(record)

private fun LedgerTransactionRecord.isOverviewAdjustment(titles:Map<GeneratedTransactionTitle,Collection<String>>)=
    categoryId in setOf(TransactionCategoryRecord.BALANCE_ADJUSTMENT_EXPENSE_ID,TransactionCategoryRecord.BALANCE_ADJUSTMENT_INCOME_ID) ||
        title.matchesOverviewTitle(titles[GeneratedTransactionTitle.BALANCE_ADJUSTMENT].orEmpty())
private fun String.matchesOverviewTitle(titles:Collection<String>)=trim().isNotEmpty() && titles.any {it.trim().equals(trim(),ignoreCase=true)}
