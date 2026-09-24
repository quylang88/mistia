package vn.com.quyln.mistia.core.model

import java.text.Normalizer
import java.time.Instant
import java.time.YearMonth
import java.time.ZoneId
import java.util.Locale
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull

fun LedgerTransactionRecord.isLockedByPaidCreditCardStatement(
    wallets: List<LedgerWalletRecord>,
    creditCardProfiles: List<CreditCardProfileRecord>,
    categories: List<TransactionCategoryRecord> = emptyList(),
    transactions: List<LedgerTransactionRecord>,
    dueOccurrences: List<CloudRecord>,
    zoneId: ZoneId = ZoneId.systemDefault(),
): Boolean {
    val kind = primaryKind ?: return false
    if (kind != TransactionPrimaryKind.EXPENSE && kind != TransactionPrimaryKind.TRANSFER) {
        return false
    }
    if (isLinkedToPaidCreditCardOccurrence(dueOccurrences)) return true

    val walletKinds = wallets.asSequence()
        .filter { it.ownerUserId == ownerUserId && it.deletedAt == null }
        .associate { it.id to it.kind }
    val creditCardWalletId = when (kind) {
        TransactionPrimaryKind.EXPENSE -> sourceWalletId?.takeIf {
            walletKinds[it] == WalletKind.CREDIT_CARD
        }
        TransactionPrimaryKind.TRANSFER -> when (transferSubtype) {
            TransactionTransferSubtype.INTERNAL_TRANSFER -> destinationWalletId?.takeIf {
                walletKinds[it] == WalletKind.CREDIT_CARD
            }
            TransactionTransferSubtype.DEBT -> sourceWalletId?.takeIf {
                debtIntent == TransactionDebtIntent.LEND && walletKinds[it] == WalletKind.CREDIT_CARD
            }
            TransactionTransferSubtype.FAMILY_TRANSFER, null -> null
        }
        TransactionPrimaryKind.INCOME -> null
    } ?: return false

    val isStatementCharge = kind == TransactionPrimaryKind.EXPENSE ||
        (transferSubtype == TransactionTransferSubtype.DEBT && debtIntent == TransactionDebtIntent.LEND)
    if (isStatementCharge &&
        isPaidStatementExpense(
            cardWalletId = creditCardWalletId,
            creditCardProfiles = creditCardProfiles,
            categories = categories,
            transactions = transactions,
            zoneId = zoneId,
        )
    ) {
        return true
    }

    return transactions.asSequence()
        .filter { it.ownerUserId == ownerUserId && it.isActivePostedTransaction() }
        .filter {
            it.primaryKind == TransactionPrimaryKind.TRANSFER &&
                it.transferSubtype == TransactionTransferSubtype.INTERNAL_TRANSFER &&
                it.destinationWalletId == creditCardWalletId &&
                isCreditCardPaymentTitle(it.title)
        }
        .any { payment ->
            paidStatementMonth(payment, zoneId) == occurredYearMonth(zoneId)
        }
}

private fun LedgerTransactionRecord.isLinkedToPaidCreditCardOccurrence(
    dueOccurrences: List<CloudRecord>,
): Boolean = dueOccurrences.any { occurrence ->
    occurrence.entity == CloudEntity.DUE_OCCURRENCE_RECORD.table &&
        occurrence.ownerUserId == ownerUserId &&
        occurrence.deletedAt == null &&
        occurrence.payload.stringValue("source_kind_raw_value") == "creditCard" &&
        occurrence.payload.stringValue("status_raw_value") == "paid" &&
        occurrence.payload.stringValue("linked_transaction_id") == id
}

private fun LedgerTransactionRecord.isPaidStatementExpense(
    cardWalletId: String,
    creditCardProfiles: List<CreditCardProfileRecord>,
    categories: List<TransactionCategoryRecord>,
    transactions: List<LedgerTransactionRecord>,
    zoneId: ZoneId,
): Boolean {
    val profile = creditCardProfiles.firstOrNull {
        it.ownerUserId == ownerUserId && it.walletId == cardWalletId && it.deletedAt == null
    } ?: return false
    val statementMonth = occurredYearMonth(zoneId) ?: return false
    val excludedExpenseCategoryIds = categories.asSequence()
        .filter { it.ownerUserId == ownerUserId && it.deletedAt == null }
        .filter { it.isBalanceAdjustmentSystemCategory || it.systemKey == LOAN_REPAYMENT_CATEGORY_KEY }
        .mapTo(mutableSetOf(), TransactionCategoryRecord::id)
    val amount = transactions.asSequence()
        .filter { it.ownerUserId == ownerUserId && it.isActivePostedTransaction() }
        .filter {
            it.isCreditCardStatementCharge(cardWalletId, excludedExpenseCategoryIds) &&
                it.occurredYearMonth(zoneId) == statementMonth
        }
        .fold(0L) { total, charge -> saturatingStatementAdd(total, charge.amountMinor) }
    if (amount <= 0) return false

    val closingDay = minOf(profile.statementClosingDay, statementMonth.lengthOfMonth())
    val closingInstant = statementMonth.atDay(closingDay).atStartOfDay(zoneId).toInstant()
    return transactions.asSequence()
        .filter { it.ownerUserId == ownerUserId && it.isActivePostedTransaction() }
        .filter {
            it.primaryKind == TransactionPrimaryKind.TRANSFER &&
                it.transferSubtype == TransactionTransferSubtype.INTERNAL_TRANSFER &&
                it.destinationWalletId == cardWalletId
        }
        .any { payment ->
            val paymentInstant = runCatching { Instant.parse(payment.occurredAt) }.getOrNull()
                ?: return@any false
            val paidAmount = payment.destinationAmountMinor ?: payment.amountMinor
            !paymentInstant.isBefore(closingInstant) && paidAmount >= amount
        }
}

private fun LedgerTransactionRecord.isCreditCardStatementCharge(
    cardWalletId: String,
    excludedExpenseCategoryIds: Set<String>,
): Boolean = sourceWalletId == cardWalletId && when (primaryKind) {
    TransactionPrimaryKind.EXPENSE -> categoryId !in excludedExpenseCategoryIds
    TransactionPrimaryKind.TRANSFER ->
        transferSubtype == TransactionTransferSubtype.DEBT && debtIntent == TransactionDebtIntent.LEND
    TransactionPrimaryKind.INCOME, null -> false
}

private fun LedgerTransactionRecord.isActivePostedTransaction(): Boolean =
    entryStatus == TransactionEntryStatus.POSTED && !isArchived && deletedAt == null

private fun LedgerTransactionRecord.occurredYearMonth(zoneId: ZoneId): YearMonth? =
    runCatching { YearMonth.from(Instant.parse(occurredAt).atZone(zoneId)) }.getOrNull()

private fun paidStatementMonth(payment: LedgerTransactionRecord, zoneId: ZoneId): YearMonth? =
    explicitStatementMonth(payment.title) ?: payment.occurredYearMonth(zoneId)

private fun explicitStatementMonth(title: String): YearMonth? {
    val folded = Normalizer.normalize(title, Normalizer.Form.NFD)
        .replace(Regex("\\p{M}+"), "")
        .lowercase(Locale.ROOT)
    Regex("(?:thang|month)?\\s*(\\d{1,2})\\s*/\\s*(\\d{4})")
        .find(folded)?.groupValues?.drop(1)?.let(::monthYear)?.let { return it }
    Regex("thang\\s*(\\d{1,2})\\s*(?:nam)?\\s*(\\d{4})")
        .find(folded)?.groupValues?.drop(1)?.let(::monthYear)?.let { return it }
    Regex("(\\d{4})\\s*年\\s*(\\d{1,2})\\s*月")
        .find(title)?.groupValues?.drop(1)?.let { values ->
            yearMonth(values.getOrNull(0), values.getOrNull(1))
        }?.let { return it }
    val english = Regex(
        "\\b(january|jan|february|feb|march|mar|april|apr|may|june|jun|" +
            "july|jul|august|aug|september|sep|october|oct|november|nov|december|dec)\\s+(\\d{4})\\b"
    ).find(folded)?.groupValues?.drop(1)
    if (english != null) {
        val month = ENGLISH_MONTHS[english[0]]
        if (month != null) return validYearMonth(english[1].toIntOrNull(), month)
    }
    return null
}

private fun monthYear(values: List<String>): YearMonth? =
    validYearMonth(values.getOrNull(1)?.toIntOrNull(), values.getOrNull(0)?.toIntOrNull())

private fun yearMonth(year: String?, month: String?): YearMonth? =
    validYearMonth(year?.toIntOrNull(), month?.toIntOrNull())

private fun validYearMonth(year: Int?, month: Int?): YearMonth? =
    if (year != null && month != null && month in 1..12) YearMonth.of(year, month) else null

private fun isCreditCardPaymentTitle(title: String): Boolean {
    if (title.isBlank()) return false
    val folded = Normalizer.normalize(title, Normalizer.Form.NFD)
        .replace(Regex("\\p{M}+"), "")
        .lowercase(Locale.ROOT)
    return folded.contains("card payment") || folded.contains("thanh toan the") ||
        title.contains("カード支払い")
}

private fun JsonObject.stringValue(key: String): String? =
    (get(key) as? JsonPrimitive)?.contentOrNull

private fun saturatingStatementAdd(left: Long, right: Long): Long = runCatching {
    Math.addExact(left, right)
}.getOrElse { Long.MAX_VALUE }

private val ENGLISH_MONTHS = mapOf(
    "january" to 1, "jan" to 1,
    "february" to 2, "feb" to 2,
    "march" to 3, "mar" to 3,
    "april" to 4, "apr" to 4,
    "may" to 5,
    "june" to 6, "jun" to 6,
    "july" to 7, "jul" to 7,
    "august" to 8, "aug" to 8,
    "september" to 9, "sep" to 9,
    "october" to 10, "oct" to 10,
    "november" to 11, "nov" to 11,
    "december" to 12, "dec" to 12,
)

private const val LOAN_REPAYMENT_CATEGORY_KEY = "loan_repayment"
