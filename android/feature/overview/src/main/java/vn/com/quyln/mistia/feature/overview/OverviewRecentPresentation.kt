package vn.com.quyln.mistia.feature.overview

import java.time.Instant
import java.time.Duration
import java.time.temporal.ChronoUnit
import java.time.ZoneId
import vn.com.quyln.mistia.core.model.*

internal enum class OverviewCashflow { INCOME, EXPENSE, NEUTRAL }
internal sealed interface OverviewRelativeTime {
    data class Minutes(val count: Long): OverviewRelativeTime
    data class Hours(val count: Long): OverviewRelativeTime
    data object Today: OverviewRelativeTime
    data object Yesterday: OverviewRelativeTime
    data object TwoDaysAgo: OverviewRelativeTime
    data class Date(val value: java.time.LocalDate): OverviewRelativeTime
}
internal fun overviewCashflow(transaction: LedgerTransactionRecord): OverviewCashflow = when (transaction.primaryKind) {
    TransactionPrimaryKind.EXPENSE -> OverviewCashflow.EXPENSE
    TransactionPrimaryKind.INCOME -> OverviewCashflow.INCOME
    TransactionPrimaryKind.TRANSFER -> when (transaction.transferSubtype) {
        TransactionTransferSubtype.FAMILY_TRANSFER -> if (transaction.destinationWalletId == null) OverviewCashflow.INCOME else OverviewCashflow.EXPENSE
        TransactionTransferSubtype.DEBT -> {
            val paidFor = transaction.debtIntent == TransactionDebtIntent.BORROW && transaction.sourceWalletId == null
            val expenseCategory = transaction.categoryId != null && transaction.categoryId !in setOf(
                TransactionCategoryRecord.BALANCE_ADJUSTMENT_EXPENSE_ID, TransactionCategoryRecord.BALANCE_ADJUSTMENT_INCOME_ID,
                "d872b8af-d28a-5b90-8822-839dfa097b23",
            )
            when {
                paidFor && expenseCategory -> OverviewCashflow.EXPENSE
                paidFor -> OverviewCashflow.NEUTRAL
                transaction.debtIntent in setOf(TransactionDebtIntent.BORROW, TransactionDebtIntent.COLLECT) -> OverviewCashflow.INCOME
                transaction.debtIntent in setOf(TransactionDebtIntent.LEND, TransactionDebtIntent.REPAY) -> OverviewCashflow.EXPENSE
                else -> OverviewCashflow.NEUTRAL
            }
        }
        else -> OverviewCashflow.NEUTRAL
    }
    null -> OverviewCashflow.NEUTRAL
}

internal fun overviewRecentIcon(transaction: LedgerTransactionRecord, category: TransactionCategoryRecord?): String =
    category?.takeIf { transaction.categoryId != null && it.id == transaction.categoryId && it.ownerUserId == transaction.ownerUserId && it.deletedAt == null }
        ?.iconSymbolName ?: when (transaction.primaryKind) {
            TransactionPrimaryKind.EXPENSE -> "mistia.flow.expense"
            TransactionPrimaryKind.INCOME -> "mistia.flow.income"
            else -> "mistia.flow.transfer"
        }

internal fun overviewRelativeTime(date: Instant, reference: Instant, zone: ZoneId): OverviewRelativeTime {
    val day = date.atZone(zone).toLocalDate()
    val dayDelta = ChronoUnit.DAYS.between(day, reference.atZone(zone).toLocalDate())
    val elapsed = Duration.between(date, reference)
    if (dayDelta == 0L && elapsed < Duration.ofHours(1)) return OverviewRelativeTime.Minutes(maxOf(elapsed.seconds / 60, 1))
    if (dayDelta == 0L && elapsed < Duration.ofHours(6)) return OverviewRelativeTime.Hours(maxOf(elapsed.seconds / 3600, 1))
    return when (dayDelta) {
        0L -> OverviewRelativeTime.Today
        1L -> OverviewRelativeTime.Yesterday
        2L -> OverviewRelativeTime.TwoDaysAgo
        else -> OverviewRelativeTime.Date(day)
    }
}
