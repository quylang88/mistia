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
    referenceDate:Instant = Instant.now(),
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
            wallets = wallets,
            creditCardProfiles = creditCardProfiles,
            categories = categories,
            transactions = transactions,
            dueOccurrences = dueOccurrences,
            zoneId = zoneId,
            referenceDate = referenceDate,
        )
    ) {
        return true
    }

    if(isStatementCharge) {
        if(dueOccurrences.any {it.isOwnedCreditOccurrence(ownerUserId) && it.payload.stringValue("source_id")==creditCardWalletId}) return false
        // Swift's legacy title heuristic deliberately excludes debt lending.
        if(transferSubtype==TransactionTransferSubtype.DEBT) return false
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

private fun CloudRecord.isOwnedCreditOccurrence(owner:String):Boolean =
    entity==CloudEntity.DUE_OCCURRENCE_RECORD.table && ownerUserId==owner && deletedAt==null &&
        payload.stringValue("user_id")==owner && payload.stringValue("deleted_at")==null &&
        payload.stringValue("source_kind_raw_value")=="creditCard"

private fun LedgerTransactionRecord.isLinkedToPaidCreditCardOccurrence(dueOccurrences:List<CloudRecord>):Boolean = dueOccurrences.any {
    it.isOwnedCreditOccurrence(ownerUserId) && it.payload.stringValue("status_raw_value")=="paid" && it.payload.stringValue("linked_transaction_id")==id
}

private fun LedgerTransactionRecord.isPaidStatementExpense(
    cardWalletId:String, wallets:List<LedgerWalletRecord>, creditCardProfiles:List<CreditCardProfileRecord>,
    categories:List<TransactionCategoryRecord>, transactions:List<LedgerTransactionRecord>, dueOccurrences:List<CloudRecord>,zoneId:ZoneId,referenceDate:Instant,
):Boolean {
    val wallet=wallets.firstOrNull {it.ownerUserId==ownerUserId && it.id==cardWalletId && it.deletedAt==null} ?: return false
    val profile=creditCardProfiles.firstOrNull {it.ownerUserId==ownerUserId && it.walletId==cardWalletId && it.deletedAt==null} ?: return false
    val month=occurredYearMonth(zoneId) ?: return false
    val occurrences=dueOccurrences.filter {it.isOwnedCreditOccurrence(ownerUserId)}.mapNotNull {runCatching {DueOccurrenceRecord.fromCloudRecord(it)}.getOrNull()}
    return creditCardStatementItems(UserId(ownerUserId),listOf(CreditCardAccount(wallet,profile)),transactions,occurrences,listOf(month),referenceDate,zoneId,categories)
        .firstOrNull()?.state==CreditCardStatementState.PAID
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
