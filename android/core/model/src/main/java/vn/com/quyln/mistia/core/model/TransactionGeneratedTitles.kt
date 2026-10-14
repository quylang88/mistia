package vn.com.quyln.mistia.core.model

import java.util.Locale

enum class GeneratedTransactionTitle(val localizationKey: String) {
    INTERNAL_TRANSFER("transactions.transactioneditor.internalTransfer"),
    FAMILY_TRANSFER_SENT("transactions.generatedTitle.familyTransferSent"),
    FAMILY_TRANSFER_RECEIVED("transactions.generatedTitle.familyTransferReceived"),
    BALANCE_ADJUSTMENT("transactions.generatedTitle.balanceAdjustment"),
    LEND("shared.corelogic.financeenums.lend"),
    COLLECT("shared.corelogic.financeenums.collectDebt"),
    BORROW("shared.corelogic.financeenums.borrow"),
    REPAY("shared.corelogic.financeenums.repay"),
}

fun generatedTransactionTitle(
    rawTitle: String,
    primaryKind: TransactionPrimaryKind?,
    transferSubtype: TransactionTransferSubtype?,
    debtIntent: TransactionDebtIntent?,
    categoryId: String?,
    categorySystemKey: String?,
    knownTitles: Map<GeneratedTransactionTitle, Collection<String>>,
): GeneratedTransactionTitle? {
    val normalized = rawTitle.trim().lowercase(Locale.ROOT)
    if (normalized.isEmpty()) return null
    val candidates = when (primaryKind) {
        TransactionPrimaryKind.TRANSFER -> when (transferSubtype) {
            TransactionTransferSubtype.INTERNAL_TRANSFER -> listOf(GeneratedTransactionTitle.INTERNAL_TRANSFER)
            TransactionTransferSubtype.FAMILY_TRANSFER -> listOf(GeneratedTransactionTitle.FAMILY_TRANSFER_SENT, GeneratedTransactionTitle.FAMILY_TRANSFER_RECEIVED)
            TransactionTransferSubtype.DEBT -> if (debtIntent == null) listOf(GeneratedTransactionTitle.LEND, GeneratedTransactionTitle.COLLECT,
                GeneratedTransactionTitle.BORROW, GeneratedTransactionTitle.REPAY) else listOf(when (debtIntent) {
                    TransactionDebtIntent.LEND -> GeneratedTransactionTitle.LEND
                    TransactionDebtIntent.COLLECT -> GeneratedTransactionTitle.COLLECT
                    TransactionDebtIntent.BORROW -> GeneratedTransactionTitle.BORROW
                    TransactionDebtIntent.REPAY -> GeneratedTransactionTitle.REPAY
                })
            null -> emptyList()
        }
        TransactionPrimaryKind.EXPENSE, TransactionPrimaryKind.INCOME -> {
            val adjustment = categoryId?.lowercase(Locale.ROOT) in setOf(TransactionCategoryRecord.BALANCE_ADJUSTMENT_EXPENSE_ID,
                TransactionCategoryRecord.BALANCE_ADJUSTMENT_INCOME_ID) || categorySystemKey in setOf(
                    TransactionCategoryRecord.BALANCE_ADJUSTMENT_EXPENSE_KEY, TransactionCategoryRecord.BALANCE_ADJUSTMENT_INCOME_KEY)
            if (adjustment) listOf(GeneratedTransactionTitle.BALANCE_ADJUSTMENT) else emptyList()
        }
        null -> emptyList()
    }
    return candidates.firstOrNull { candidate -> knownTitles[candidate].orEmpty().any { it.trim().lowercase(Locale.ROOT) == normalized } }
}
