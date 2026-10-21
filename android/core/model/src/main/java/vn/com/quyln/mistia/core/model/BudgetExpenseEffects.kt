package vn.com.quyln.mistia.core.model

import java.time.Instant

/** Read-only money comes from validated wire fields, never classifier marker amounts. */
data class BudgetExpenseEffect(
    val id:String,
    val ownerUserId:String,
    val categoryId:String?,
    val occurredAt:Instant?,
    val sourceCurrencyCode:String?,
    val expenseMinor:Long?,
    val categoryMayBeUnknown:Boolean=false,
    val branchMayBeUnknown:Boolean=false,
    val branchIdentityKnown:Boolean=true,
)

fun budgetExpenseSource(record:LedgerTransactionRecord,categorySystemKey:String?,walletKind:WalletKind?,adjustmentTitles:Set<String>):OverviewReportingSource {
    if(record.reportingExpenseMinor!=null) return OverviewReportingSource.EXPENSE_OVERRIDE
    if(categorySystemKey==TransactionCategoryRecord.BALANCE_ADJUSTMENT_EXPENSE_KEY ||
        categorySystemKey==TransactionCategoryRecord.BALANCE_ADJUSTMENT_INCOME_KEY || categorySystemKey=="loan_repayment") return OverviewReportingSource.NONE
    return if(isOverviewExpenseSpending(record,walletKind,mapOf(GeneratedTransactionTitle.BALANCE_ADJUSTMENT to adjustmentTitles)))
        OverviewReportingSource.ORIGINAL else OverviewReportingSource.NONE
}
