package vn.com.quyln.mistia.feature.transactions

import androidx.compose.runtime.saveable.Saver
import androidx.compose.runtime.saveable.listSaver
import java.math.BigDecimal
import java.math.RoundingMode
import java.util.Currency
import java.util.Locale
import vn.com.quyln.mistia.core.model.CurrencyConversionMode
import vn.com.quyln.mistia.core.model.LedgerTransactionRecord
import vn.com.quyln.mistia.core.model.TransactionDraft
import vn.com.quyln.mistia.core.model.TransactionEntryStatus
import vn.com.quyln.mistia.core.model.TransactionPrimaryKind
import vn.com.quyln.mistia.core.model.TransactionTransferSubtype

data class TransactionEditorState(
    val id: String?,
    val primaryKind: TransactionPrimaryKind,
    val transferSubtype: TransactionTransferSubtype?,
    val entryStatus: TransactionEntryStatus,
    val title: String,
    val note: String,
    val amountText: String,
    val occurredAt: String,
    val sourceWalletId: String?,
    val destinationWalletId: String?,
    val categoryId: String?,
    val destinationAmountText: String,
    val conversionMode: CurrencyConversionMode?,
    val exchangeRateText: String,
    val exchangeRateProvider: String?,
    val exchangeRateDate: String?,
) {
    fun selectKind(selected: TransactionPrimaryKind): TransactionEditorState = when (selected) {
        TransactionPrimaryKind.TRANSFER -> copy(
            primaryKind = selected,
            transferSubtype = TransactionTransferSubtype.INTERNAL_TRANSFER,
            categoryId = null,
        )
        TransactionPrimaryKind.EXPENSE, TransactionPrimaryKind.INCOME -> copy(
            primaryKind = selected,
            transferSubtype = null,
            destinationWalletId = null,
            categoryId = null,
            destinationAmountText = "",
            conversionMode = null,
            exchangeRateText = "",
            exchangeRateProvider = null,
            exchangeRateDate = null,
        )
    }

    fun toDraft(
        sourceCurrencyCode: String?,
        destinationCurrencyCode: String?,
    ): TransactionEditorDraftResult {
        if (sourceWalletId == null) {
            return TransactionEditorDraftResult(validation = TransactionEditorValidation.SOURCE_WALLET_REQUIRED)
        }
        if (primaryKind != TransactionPrimaryKind.TRANSFER && categoryId == null) {
            return TransactionEditorDraftResult(validation = TransactionEditorValidation.CATEGORY_REQUIRED)
        }
        if (primaryKind == TransactionPrimaryKind.TRANSFER && destinationWalletId == null) {
            return TransactionEditorDraftResult(validation = TransactionEditorValidation.DESTINATION_WALLET_REQUIRED)
        }
        if (primaryKind == TransactionPrimaryKind.TRANSFER && sourceWalletId == destinationWalletId) {
            return TransactionEditorDraftResult(validation = TransactionEditorValidation.SAME_WALLET)
        }
        val amount = parseMinorInput(amountText, sourceCurrencyCode)
            ?: return TransactionEditorDraftResult(validation = TransactionEditorValidation.INVALID_AMOUNT)
        if (amount <= 0) {
            return TransactionEditorDraftResult(validation = TransactionEditorValidation.INVALID_AMOUNT)
        }
        val isCrossCurrency = primaryKind == TransactionPrimaryKind.TRANSFER &&
            sourceCurrencyCode != null && destinationCurrencyCode != null &&
            !sourceCurrencyCode.equals(destinationCurrencyCode, ignoreCase = true)
        val destinationAmount = if (isCrossCurrency) {
            parseMinorInput(destinationAmountText, destinationCurrencyCode)?.takeIf { it > 0 }
                ?: return TransactionEditorDraftResult(
                    validation = TransactionEditorValidation.INVALID_DESTINATION_AMOUNT,
                )
        } else {
            null
        }
        val rate = if (isCrossCurrency) exchangeRateText.trim().takeIf(String::isNotEmpty) else null
        if (isCrossCurrency && (conversionMode == null || rate == null ||
                runCatching { BigDecimal(rate) }.getOrNull()?.signum() != 1)
        ) {
            return TransactionEditorDraftResult(validation = TransactionEditorValidation.INVALID_EXCHANGE_RATE)
        }
        return TransactionEditorDraftResult(
            draft = TransactionDraft(
                id = id,
                primaryKind = primaryKind,
                transferSubtype = transferSubtype,
                entryStatus = entryStatus,
                title = title,
                note = note,
                amountMinor = amount,
                occurredAt = occurredAt,
                sourceWalletId = sourceWalletId,
                destinationWalletId = destinationWalletId,
                categoryId = categoryId,
                destinationAmountMinor = destinationAmount,
                conversionMode = if (isCrossCurrency) conversionMode else null,
                exchangeRateDecimalString = rate,
                exchangeRateProvider = if (isCrossCurrency) exchangeRateProvider else null,
                exchangeRateDate = if (isCrossCurrency) exchangeRateDate else null,
            ),
        )
    }

    companion object {
        fun new(now: String): TransactionEditorState = TransactionEditorState(
            id = null,
            primaryKind = TransactionPrimaryKind.EXPENSE,
            transferSubtype = null,
            entryStatus = TransactionEntryStatus.POSTED,
            title = "",
            note = "",
            amountText = "",
            occurredAt = now,
            sourceWalletId = null,
            destinationWalletId = null,
            categoryId = null,
            destinationAmountText = "",
            conversionMode = null,
            exchangeRateText = "",
            exchangeRateProvider = null,
            exchangeRateDate = null,
        )

        fun edit(transaction: LedgerTransactionRecord): TransactionEditorState {
            val primaryKind = requireNotNull(transaction.primaryKind) { "Unknown transaction kind cannot be edited" }
            val entryStatus = requireNotNull(transaction.entryStatus) { "Unknown transaction status cannot be edited" }
            return TransactionEditorState(
                id = transaction.id,
                primaryKind = primaryKind,
                transferSubtype = transaction.transferSubtype,
                entryStatus = entryStatus,
                title = transaction.title,
                note = transaction.note.orEmpty(),
                amountText = formatMinorInput(transaction.amountMinor, transaction.sourceCurrencyCode),
                occurredAt = transaction.occurredAt,
                sourceWalletId = transaction.sourceWalletId,
                destinationWalletId = transaction.destinationWalletId,
                categoryId = transaction.categoryId,
                destinationAmountText = transaction.destinationAmountMinor?.let {
                    formatMinorInput(it, transaction.destinationCurrencyCode)
                }.orEmpty(),
                conversionMode = transaction.conversionMode,
                exchangeRateText = transaction.exchangeRateDecimalString.orEmpty(),
                exchangeRateProvider = transaction.exchangeRateProvider,
                exchangeRateDate = transaction.exchangeRateDate,
            )
        }

        val Saver: Saver<TransactionEditorState, Any> = listSaver(
            save = {
                listOf(
                    it.id.orEmpty(),
                    it.primaryKind.wireValue,
                    it.transferSubtype?.wireValue.orEmpty(),
                    it.entryStatus.wireValue,
                    it.title,
                    it.note,
                    it.amountText,
                    it.occurredAt,
                    it.sourceWalletId.orEmpty(),
                    it.destinationWalletId.orEmpty(),
                    it.categoryId.orEmpty(),
                    it.destinationAmountText,
                    it.conversionMode?.wireValue.orEmpty(),
                    it.exchangeRateText,
                    it.exchangeRateProvider.orEmpty(),
                    it.exchangeRateDate.orEmpty(),
                )
            },
            restore = { values ->
                TransactionEditorState(
                    id = (values[0] as String).takeIf(String::isNotEmpty),
                    primaryKind = TransactionPrimaryKind.fromWireValue(values[1] as String)
                        ?: TransactionPrimaryKind.EXPENSE,
                    transferSubtype = TransactionTransferSubtype.fromWireValue(values[2] as String),
                    entryStatus = TransactionEntryStatus.fromWireValue(values[3] as String)
                        ?: TransactionEntryStatus.POSTED,
                    title = values[4] as String,
                    note = values[5] as String,
                    amountText = values[6] as String,
                    occurredAt = values[7] as String,
                    sourceWalletId = (values[8] as String).takeIf(String::isNotEmpty),
                    destinationWalletId = (values[9] as String).takeIf(String::isNotEmpty),
                    categoryId = (values[10] as String).takeIf(String::isNotEmpty),
                    destinationAmountText = values[11] as String,
                    conversionMode = CurrencyConversionMode.fromWireValue(values[12] as String),
                    exchangeRateText = values[13] as String,
                    exchangeRateProvider = (values[14] as String).takeIf(String::isNotEmpty),
                    exchangeRateDate = (values[15] as String).takeIf(String::isNotEmpty),
                )
            },
        )
    }
}

data class TransactionEditorDraftResult(
    val draft: TransactionDraft? = null,
    val validation: TransactionEditorValidation? = null,
)

enum class TransactionEditorValidation {
    SOURCE_WALLET_REQUIRED,
    DESTINATION_WALLET_REQUIRED,
    CATEGORY_REQUIRED,
    SAME_WALLET,
    INVALID_AMOUNT,
    INVALID_DESTINATION_AMOUNT,
    INVALID_EXCHANGE_RATE,
}

private fun parseMinorInput(text: String, currencyCode: String?): Long? {
    val code = currencyCode?.trim()?.uppercase(Locale.ROOT)?.takeIf { it.length == 3 } ?: return null
    val fractionDigits = runCatching { Currency.getInstance(code).defaultFractionDigits }.getOrNull()
        ?.takeIf { it >= 0 } ?: return null
    return runCatching {
        BigDecimal(text.trim())
            .movePointRight(fractionDigits)
            .setScale(0, RoundingMode.UNNECESSARY)
            .longValueExact()
    }.getOrNull()
}

private fun formatMinorInput(minor: Long, currencyCode: String?): String {
    val fractionDigits = currencyCode?.let { code ->
        runCatching { Currency.getInstance(code.uppercase(Locale.ROOT)).defaultFractionDigits }.getOrNull()
    }?.takeIf { it >= 0 } ?: 0
    return BigDecimal.valueOf(minor, fractionDigits).stripTrailingZeros().toPlainString()
}

internal fun LedgerTransactionRecord.supportsNativeTransactionEditor(): Boolean {
    val kind = primaryKind ?: return false
    if (isArchived || deletedAt != null || entryStatus == null) return false
    if (settlementGroupId != null || settlementObligationId != null || settlementRoleWireValue != null) return false
    return when (kind) {
        TransactionPrimaryKind.EXPENSE, TransactionPrimaryKind.INCOME ->
            transferSubtype == null && debtIntent == null
        TransactionPrimaryKind.TRANSFER ->
            transferSubtype == TransactionTransferSubtype.INTERNAL_TRANSFER && debtIntent == null
    }
}
