package vn.com.quyln.mistia.feature.management

import androidx.compose.runtime.saveable.listSaver
import java.time.Instant
import java.time.YearMonth
import java.time.ZoneId
import vn.com.quyln.mistia.core.model.*

internal data class CreditCardStatementViewData(
    val wallet: LedgerWalletRecord,
    val statement: CreditCardStatement?,
    val charges: List<LedgerTransactionRecord>,
    val linkedWalletName: String?,
)

internal fun creditCardStatementViewData(
    owner: UserId,
    walletId: String,
    wallets: List<LedgerWalletRecord>,
    profiles: List<CreditCardProfileRecord>,
    transactions: List<LedgerTransactionRecord>,
    occurrences: List<DueOccurrenceRecord>,
    categories: List<TransactionCategoryRecord>,
    month: YearMonth,
    reference: Instant,
    zone: ZoneId,
): CreditCardStatementViewData? {
    val wallet = wallets.firstOrNull {
        it.id == walletId && it.ownerUserId == owner.value && it.deletedAt == null && it.kind == WalletKind.CREDIT_CARD
    } ?: return null
    val profile = profiles.firstOrNull { it.walletId == walletId && it.ownerUserId == owner.value && it.deletedAt == null }
    val statement = if (profile != null && !wallet.isArchived) {
        creditCardStatementItems(owner, listOf(CreditCardAccount(wallet, profile)), transactions, occurrences,
            listOf(month), reference, zone, categories).firstOrNull()
    } else null
    // Swift shows raw posted charges, including adjustment rows excluded from the payable total.
    val charges = if (statement == null) emptyList() else transactions.filter {
        it.ownerUserId == owner.value && it.deletedAt == null && !it.isArchived &&
            it.entryStatus == TransactionEntryStatus.POSTED && it.sourceWalletId == walletId &&
            YearMonth.from(Instant.parse(it.occurredAt).atZone(zone)) == month &&
            (it.primaryKind == TransactionPrimaryKind.EXPENSE ||
                (it.primaryKind == TransactionPrimaryKind.TRANSFER && it.transferSubtype == TransactionTransferSubtype.DEBT &&
                    it.debtIntent == TransactionDebtIntent.LEND))
    }.sortedByDescending { Instant.parse(it.occurredAt) }
    val linkedName = statement?.account?.profile?.paymentSourceWalletId?.let { linkedId ->
        wallets.firstOrNull { it.id == linkedId && it.ownerUserId == owner.value && it.deletedAt == null }
            ?.name?.trim()?.takeIf(String::isNotEmpty)
    }
    return CreditCardStatementViewData(wallet, statement, charges, linkedName)
}

internal data class StatementMonthBounds(val minimum: YearMonth, val maximum: YearMonth) {
    fun clamp(month: YearMonth): YearMonth = month.coerceIn(minimum, maximum)
    companion object {
        fun current(reference: Instant, zone: ZoneId): StatementMonthBounds {
            val current = YearMonth.from(reference.atZone(zone))
            return StatementMonthBounds(YearMonth.of(current.year - 10, 1), current)
        }
    }
}

internal data class CreditCardStatementNavigation(val owner: String, val wallet: String, val month: String) {
    companion object {
        fun saver(owner: String, wallet: String) = listSaver<CreditCardStatementNavigation, String>(
            save = { listOf(it.owner, it.wallet, it.month) },
            restore = { values ->
                if (values.size != 3 || values[0] != owner || values[1] != wallet || runCatching { YearMonth.parse(values[2]) }.isFailure) null
                else CreditCardStatementNavigation(owner, wallet, values[2])
            },
        )
    }
}
