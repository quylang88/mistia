package vn.com.quyln.mistia.core.model

import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.longOrNull

/** Matches TransactionsView's source amount/currency projection. Internal transfers
 * have zero cashflow in TransactionLogic, so the list also uses their source leg.
 * Reporting currency is only meaningful alongside reporting_amount_minor. */
fun CloudRecord.transactionDisplayMoney(
    sourceWalletCurrency: String? = null,
    destinationWalletCurrency: String? = null,
): Money? {
    val amount = (payload["amount_minor"] as? JsonPrimitive)?.longOrNull ?: return null
    val currency = (payload["source_currency_code"] as? JsonPrimitive)?.contentOrNull?.takeIf { it.isNotBlank() }
        ?: sourceWalletCurrency?.takeIf { it.isNotBlank() }
        ?: destinationWalletCurrency?.takeIf { it.isNotBlank() }
        ?: "JPY"
    return Money(amount, currency)
}

fun LedgerTransactionRecord.transactionDisplayMoney(
    sourceWalletCurrency: String? = null,
    destinationWalletCurrency: String? = null,
): Money = Money(
    amountMinor,
    sourceCurrencyCode?.takeIf(String::isNotBlank)
        ?: sourceWalletCurrency?.takeIf(String::isNotBlank)
        ?: destinationWalletCurrency?.takeIf(String::isNotBlank)
        ?: "JPY",
)
