package vn.com.quyln.mistia.core.model

import java.math.BigDecimal
import java.time.Instant
import java.time.LocalDate
import java.util.Locale
import java.util.UUID
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.longOrNull

enum class TransactionPrimaryKind(val wireValue: String) {
    EXPENSE("expense"),
    INCOME("income"),
    TRANSFER("transfer"),
    ;

    companion object {
        fun fromWireValue(value: String): TransactionPrimaryKind? = entries.firstOrNull { it.wireValue == value }
    }
}

enum class TransactionTransferSubtype(val wireValue: String) {
    INTERNAL_TRANSFER("internalTransfer"),
    FAMILY_TRANSFER("familyTransfer"),
    DEBT("debt"),
    ;

    companion object {
        fun fromWireValue(value: String?): TransactionTransferSubtype? = entries.firstOrNull { it.wireValue == value }
    }
}

enum class TransactionDebtIntent(val wireValue: String) {
    LEND("lend"),
    COLLECT("collect"),
    BORROW("borrow"),
    REPAY("repay"),
    ;

    companion object {
        fun fromWireValue(value: String?): TransactionDebtIntent? = entries.firstOrNull { it.wireValue == value }
    }
}

enum class TransactionEntryStatus(val wireValue: String) {
    POSTED("posted"),
    DRAFT("draft"),
    ;

    companion object {
        fun fromWireValue(value: String): TransactionEntryStatus? = entries.firstOrNull { it.wireValue == value }
    }
}

enum class CurrencyConversionMode(val wireValue: String) {
    APP_RATE("appRate"),
    MANUAL("manual"),
    ;

    companion object {
        fun fromWireValue(value: String?): CurrencyConversionMode? = entries.firstOrNull { it.wireValue == value }
    }
}

data class LedgerTransactionRecord(
    val id: String,
    val ownerUserId: String,
    val primaryKindWireValue: String,
    val transferSubtypeWireValue: String?,
    val debtIntentWireValue: String?,
    val entryStatusWireValue: String,
    val title: String,
    val note: String?,
    val amountMinor: Long,
    val sourceCurrencyCode: String?,
    val destinationCurrencyCode: String?,
    val destinationAmountMinor: Long?,
    val reportingCurrencyCode: String?,
    val reportingAmountMinor: Long?,
    val conversionModeWireValue: String?,
    val exchangeRateDecimalString: String?,
    val exchangeRateProvider: String?,
    val exchangeRateDate: String?,
    val occurredAt: String,
    val createdAt: String,
    val updatedAt: String,
    val createdByUserId: String,
    val lastModifiedByUserId: String,
    val counterpartyName: String?,
    val normalizedCounterpartyKey: String?,
    val settlementGroupId: String?,
    val settlementObligationId: String?,
    val settlementRoleWireValue: String?,
    val reportingExpenseMinor: Long?,
    val reportingIncomeMinor: Long?,
    val sourceWalletId: String?,
    val destinationWalletId: String?,
    val categoryId: String?,
    val deletedAt: String?,
    val isArchived: Boolean,
    val archivedAt: String?,
    val syncVersion: Long,
    val lastModifiedByDeviceId: String?,
) {
    val primaryKind: TransactionPrimaryKind?
        get() = TransactionPrimaryKind.fromWireValue(primaryKindWireValue)
    val transferSubtype: TransactionTransferSubtype?
        get() = TransactionTransferSubtype.fromWireValue(transferSubtypeWireValue)
    val debtIntent: TransactionDebtIntent?
        get() = TransactionDebtIntent.fromWireValue(debtIntentWireValue)
    val entryStatus: TransactionEntryStatus?
        get() = TransactionEntryStatus.fromWireValue(entryStatusWireValue)
    val conversionMode: CurrencyConversionMode?
        get() = CurrencyConversionMode.fromWireValue(conversionModeWireValue)

    fun toPayload(): JsonObject = buildJsonObject {
        put("user_id", JsonPrimitive(ownerUserId))
        put("id", JsonPrimitive(id))
        put("primary_kind_raw_value", JsonPrimitive(primaryKindWireValue))
        putNullableTransactionString("transfer_subtype_raw_value", transferSubtypeWireValue)
        putNullableTransactionString("debt_intent_raw_value", debtIntentWireValue)
        put("entry_status_raw_value", JsonPrimitive(entryStatusWireValue))
        put("title", JsonPrimitive(title))
        putNullableTransactionString("note", note)
        put("amount_minor", JsonPrimitive(amountMinor))
        putNullableTransactionString("source_currency_code", sourceCurrencyCode)
        putNullableTransactionString("destination_currency_code", destinationCurrencyCode)
        putNullableTransactionLong("destination_amount_minor", destinationAmountMinor)
        putNullableTransactionString("reporting_currency_code", reportingCurrencyCode)
        putNullableTransactionLong("reporting_amount_minor", reportingAmountMinor)
        putNullableTransactionString("conversion_mode_raw_value", conversionModeWireValue)
        putNullableTransactionString("exchange_rate_decimal_string", exchangeRateDecimalString)
        putNullableTransactionString("exchange_rate_provider", exchangeRateProvider)
        putNullableTransactionString("exchange_rate_date", exchangeRateDate)
        put("occurred_at", JsonPrimitive(occurredAt))
        put("created_at", JsonPrimitive(createdAt))
        put("updated_at", JsonPrimitive(updatedAt))
        put("created_by_user_id", JsonPrimitive(createdByUserId))
        put("last_modified_by_user_id", JsonPrimitive(lastModifiedByUserId))
        putNullableTransactionString("counterparty_name", counterpartyName)
        putNullableTransactionString("normalized_counterparty_key", normalizedCounterpartyKey)
        putNullableTransactionString("settlement_group_id", settlementGroupId)
        putNullableTransactionString("settlement_obligation_id", settlementObligationId)
        putNullableTransactionString("settlement_role_raw_value", settlementRoleWireValue)
        putNullableTransactionLong("reporting_expense_minor", reportingExpenseMinor)
        putNullableTransactionLong("reporting_income_minor", reportingIncomeMinor)
        putNullableTransactionString("source_wallet_id", sourceWalletId)
        putNullableTransactionString("destination_wallet_id", destinationWalletId)
        putNullableTransactionString("category_id", categoryId)
        putNullableTransactionString("deleted_at", deletedAt)
        put("is_archived", JsonPrimitive(isArchived))
        putNullableTransactionString("archived_at", archivedAt)
        put("sync_version", JsonPrimitive(syncVersion))
        putNullableTransactionString("last_modified_by_device_id", lastModifiedByDeviceId)
    }

    fun toCloudRecord(): CloudRecord = CloudRecord(
        entity = CloudEntity.LEDGER_TRANSACTION.table,
        id = id,
        ownerUserId = ownerUserId,
        payload = toPayload(),
        updatedAt = updatedAt,
        deletedAt = deletedAt,
        syncVersion = syncVersion,
    )

    companion object {
        fun fromCloudRecord(record: CloudRecord): LedgerTransactionRecord {
            require(record.entity == CloudEntity.LEDGER_TRANSACTION.table)
            val payload = record.payload
            val owner = transactionUuid(payload.transactionString("user_id") ?: record.ownerUserId)
            return LedgerTransactionRecord(
                id = transactionUuid(payload.transactionString("id") ?: record.id),
                ownerUserId = owner,
                primaryKindWireValue = payload.transactionString("primary_kind_raw_value").orEmpty(),
                transferSubtypeWireValue = payload.transactionString("transfer_subtype_raw_value"),
                debtIntentWireValue = payload.transactionString("debt_intent_raw_value"),
                entryStatusWireValue = payload.transactionString("entry_status_raw_value").orEmpty(),
                title = payload.transactionString("title").orEmpty(),
                note = payload.transactionString("note"),
                amountMinor = payload.transactionLong("amount_minor"),
                sourceCurrencyCode = payload.transactionString("source_currency_code"),
                destinationCurrencyCode = payload.transactionString("destination_currency_code"),
                destinationAmountMinor = payload.transactionLongOrNull("destination_amount_minor"),
                reportingCurrencyCode = payload.transactionString("reporting_currency_code"),
                reportingAmountMinor = payload.transactionLongOrNull("reporting_amount_minor"),
                conversionModeWireValue = payload.transactionString("conversion_mode_raw_value"),
                exchangeRateDecimalString = payload.transactionString("exchange_rate_decimal_string"),
                exchangeRateProvider = payload.transactionString("exchange_rate_provider"),
                exchangeRateDate = payload.transactionString("exchange_rate_date"),
                occurredAt = payload.transactionString("occurred_at").orEmpty(),
                createdAt = payload.transactionString("created_at").orEmpty(),
                updatedAt = payload.transactionString("updated_at") ?: record.updatedAt.orEmpty(),
                createdByUserId = transactionUuid(payload.transactionString("created_by_user_id") ?: owner),
                lastModifiedByUserId = transactionUuid(
                    payload.transactionString("last_modified_by_user_id")
                        ?: payload.transactionString("created_by_user_id")
                        ?: owner
                ),
                counterpartyName = payload.transactionString("counterparty_name"),
                normalizedCounterpartyKey = payload.transactionString("normalized_counterparty_key"),
                settlementGroupId = payload.transactionUuidOrNull("settlement_group_id"),
                settlementObligationId = payload.transactionUuidOrNull("settlement_obligation_id"),
                settlementRoleWireValue = payload.transactionString("settlement_role_raw_value"),
                reportingExpenseMinor = payload.transactionLongOrNull("reporting_expense_minor"),
                reportingIncomeMinor = payload.transactionLongOrNull("reporting_income_minor"),
                sourceWalletId = payload.transactionUuidOrNull("source_wallet_id"),
                destinationWalletId = payload.transactionUuidOrNull("destination_wallet_id"),
                categoryId = payload.transactionUuidOrNull("category_id"),
                deletedAt = payload.transactionString("deleted_at") ?: record.deletedAt,
                isArchived = payload.transactionBoolean("is_archived"),
                archivedAt = payload.transactionString("archived_at"),
                syncVersion = payload.transactionLongOrNull("sync_version") ?: record.syncVersion,
                lastModifiedByDeviceId = payload.transactionUuidOrNull("last_modified_by_device_id"),
            )
        }
    }
}

data class TransactionDraft(
    val id: String? = null,
    val primaryKind: TransactionPrimaryKind,
    val transferSubtype: TransactionTransferSubtype? = null,
    val debtIntent: TransactionDebtIntent? = null,
    val entryStatus: TransactionEntryStatus = TransactionEntryStatus.POSTED,
    val title: String,
    val note: String? = null,
    val amountMinor: Long,
    val occurredAt: String,
    val sourceWalletId: String? = null,
    val destinationWalletId: String? = null,
    val categoryId: String? = null,
    val destinationAmountMinor: Long? = null,
    val conversionMode: CurrencyConversionMode? = null,
    val exchangeRateDecimalString: String? = null,
    val exchangeRateProvider: String? = null,
    val exchangeRateDate: String? = null,
) {
    fun toMutation(
        ownerUserId: UserId,
        existing: LedgerTransactionRecord?,
        sourceWallet: LedgerWalletRecord?,
        destinationWallet: LedgerWalletRecord?,
        category: TransactionCategoryRecord?,
        deviceId: String,
        now: String,
    ): TransactionMutation {
        val owner = transactionUuid(ownerUserId.value)
        val device = transactionUuid(deviceId)
        val timestamp = transactionInstant(now)
        val occurred = transactionInstant(occurredAt)
        if (existing != null && existing.ownerUserId != owner) transactionFail(TransactionValidationError.OWNER_MISMATCH)
        val canonicalId = transactionUuid(existing?.id ?: id ?: UUID.randomUUID().toString())
        val sourceId = sourceWalletId?.let(::transactionUuid)
        val destinationId = destinationWalletId?.let(::transactionUuid)
        val canonicalCategoryId = categoryId?.let(::transactionUuid)
        validateTransactionDependency(sourceId, sourceWallet, owner, TransactionValidationError.INVALID_SOURCE_WALLET)
        validateTransactionDependency(
            destinationId,
            destinationWallet,
            owner,
            TransactionValidationError.INVALID_DESTINATION_WALLET,
        )
        validateTransactionCategory(canonicalCategoryId, category, owner)
        if (amountMinor <= 0) transactionFail(TransactionValidationError.INVALID_AMOUNT)

        val normalizedTitle = title.trim()
        val isPosted = entryStatus == TransactionEntryStatus.POSTED
        if (isPosted && primaryKind != TransactionPrimaryKind.TRANSFER && normalizedTitle.isEmpty()) {
            transactionFail(TransactionValidationError.TITLE_REQUIRED)
        }
        if (isPosted && sourceWallet == null) transactionFail(TransactionValidationError.SOURCE_WALLET_REQUIRED)

        val normalizedSourceCurrency = sourceWallet?.currencyCode?.transactionCurrency()
        var normalizedDestinationCurrency: String? = null
        var normalizedDestinationAmount: Long? = null
        var normalizedConversionMode: String? = null
        var normalizedRate: String? = null
        var normalizedProvider: String? = null
        var normalizedRateDate: String? = null

        when (primaryKind) {
            TransactionPrimaryKind.EXPENSE, TransactionPrimaryKind.INCOME -> {
                if (transferSubtype != null || debtIntent != null || destinationId != null || destinationWallet != null) {
                    transactionFail(TransactionValidationError.INVALID_KIND_FIELDS)
                }
                if (isPosted && category == null) transactionFail(TransactionValidationError.CATEGORY_REQUIRED)
                if (category != null) {
                    if (category.hierarchyRole != CategoryHierarchyRole.CHILD) {
                        transactionFail(TransactionValidationError.CATEGORY_CHILD_REQUIRED)
                    }
                    val expected = if (primaryKind == TransactionPrimaryKind.EXPENSE) {
                        TransactionCategoryKind.EXPENSE
                    } else {
                        TransactionCategoryKind.INCOME
                    }
                    if (category.kind != expected) transactionFail(TransactionValidationError.CATEGORY_KIND_MISMATCH)
                }
                if (primaryKind == TransactionPrimaryKind.INCOME && sourceWallet?.kind == WalletKind.CREDIT_CARD) {
                    transactionFail(TransactionValidationError.CREDIT_CARD_CANNOT_RECEIVE_INCOME)
                }
            }
            TransactionPrimaryKind.TRANSFER -> {
                if (category != null || canonicalCategoryId != null) transactionFail(TransactionValidationError.INVALID_KIND_FIELDS)
                if (isPosted && transferSubtype == null) transactionFail(TransactionValidationError.TRANSFER_SUBTYPE_REQUIRED)
                if (transferSubtype != null && transferSubtype != TransactionTransferSubtype.INTERNAL_TRANSFER) {
                    transactionFail(TransactionValidationError.UNSUPPORTED_TRANSFER_SUBTYPE)
                }
                if (transferSubtype == TransactionTransferSubtype.INTERNAL_TRANSFER) {
                    if (isPosted && destinationWallet == null) {
                        transactionFail(TransactionValidationError.DESTINATION_WALLET_REQUIRED)
                    }
                    if (sourceId != null && sourceId == destinationId) {
                        transactionFail(TransactionValidationError.SAME_WALLET_TRANSFER)
                    }
                    if (sourceWallet?.kind == WalletKind.CREDIT_CARD) {
                        transactionFail(TransactionValidationError.CREDIT_CARD_CANNOT_SEND_TRANSFER)
                    }
                    normalizedDestinationCurrency = destinationWallet?.currencyCode?.transactionCurrency()
                    if (normalizedSourceCurrency != null && normalizedDestinationCurrency != null &&
                        normalizedSourceCurrency != normalizedDestinationCurrency
                    ) {
                        val destinationAmount = destinationAmountMinor?.takeIf { it > 0 }
                            ?: transactionFail(TransactionValidationError.CROSS_CURRENCY_DETAILS_REQUIRED)
                        val mode = conversionMode
                            ?: transactionFail(TransactionValidationError.CROSS_CURRENCY_DETAILS_REQUIRED)
                        val rate = exchangeRateDecimalString.transactionOptional()
                            ?: transactionFail(TransactionValidationError.CROSS_CURRENCY_DETAILS_REQUIRED)
                        if (runCatching { BigDecimal(rate) }.getOrNull()?.signum() != 1) {
                            transactionFail(TransactionValidationError.INVALID_EXCHANGE_RATE)
                        }
                        val rateDate = exchangeRateDate.transactionOptional()
                        if (rateDate != null && runCatching { LocalDate.parse(rateDate) }.isFailure) {
                            transactionFail(TransactionValidationError.INVALID_EXCHANGE_RATE_DATE)
                        }
                        normalizedDestinationAmount = destinationAmount
                        normalizedConversionMode = mode.wireValue
                        normalizedRate = rate
                        normalizedProvider = exchangeRateProvider.transactionOptional()
                        normalizedRateDate = rateDate
                    }
                }
            }
        }

        val record = LedgerTransactionRecord(
            id = canonicalId,
            ownerUserId = owner,
            primaryKindWireValue = primaryKind.wireValue,
            transferSubtypeWireValue = if (primaryKind == TransactionPrimaryKind.TRANSFER) transferSubtype?.wireValue else null,
            debtIntentWireValue = if (transferSubtype == TransactionTransferSubtype.DEBT) debtIntent?.wireValue else null,
            entryStatusWireValue = entryStatus.wireValue,
            title = normalizedTitle,
            note = note.transactionOptional(),
            amountMinor = amountMinor,
            sourceCurrencyCode = normalizedSourceCurrency,
            destinationCurrencyCode = normalizedDestinationCurrency,
            destinationAmountMinor = normalizedDestinationAmount,
            reportingCurrencyCode = existing?.reportingCurrencyCode,
            reportingAmountMinor = existing?.reportingAmountMinor,
            conversionModeWireValue = normalizedConversionMode,
            exchangeRateDecimalString = normalizedRate,
            exchangeRateProvider = normalizedProvider,
            exchangeRateDate = normalizedRateDate,
            occurredAt = occurred,
            createdAt = existing?.createdAt ?: timestamp,
            updatedAt = timestamp,
            createdByUserId = existing?.createdByUserId ?: owner,
            lastModifiedByUserId = owner,
            counterpartyName = existing?.counterpartyName,
            normalizedCounterpartyKey = existing?.normalizedCounterpartyKey,
            settlementGroupId = existing?.settlementGroupId,
            settlementObligationId = existing?.settlementObligationId,
            settlementRoleWireValue = existing?.settlementRoleWireValue,
            reportingExpenseMinor = existing?.reportingExpenseMinor,
            reportingIncomeMinor = existing?.reportingIncomeMinor,
            sourceWalletId = sourceId,
            destinationWalletId = if (primaryKind == TransactionPrimaryKind.TRANSFER) destinationId else null,
            categoryId = if (primaryKind == TransactionPrimaryKind.TRANSFER) null else canonicalCategoryId,
            deletedAt = null,
            isArchived = existing?.isArchived ?: false,
            archivedAt = existing?.archivedAt,
            syncVersion = existing?.syncVersion ?: 0,
            lastModifiedByDeviceId = device,
        )
        return TransactionMutation(
            record = record,
            pending = PendingMutation(
                CloudEntity.LEDGER_TRANSACTION,
                record.id,
                owner,
                MutationKind.UPSERT,
                record.toPayload(),
                timestamp,
                record.syncVersion,
                device,
            ),
        )
    }
}

data class TransactionMutation(
    val record: LedgerTransactionRecord,
    val pending: PendingMutation,
)

enum class TransactionValidationError {
    OWNER_MISMATCH,
    INVALID_AMOUNT,
    TITLE_REQUIRED,
    SOURCE_WALLET_REQUIRED,
    DESTINATION_WALLET_REQUIRED,
    CATEGORY_REQUIRED,
    TRANSFER_SUBTYPE_REQUIRED,
    INVALID_SOURCE_WALLET,
    INVALID_DESTINATION_WALLET,
    INVALID_CATEGORY,
    CATEGORY_KIND_MISMATCH,
    CATEGORY_CHILD_REQUIRED,
    SAME_WALLET_TRANSFER,
    CREDIT_CARD_CANNOT_RECEIVE_INCOME,
    CREDIT_CARD_CANNOT_SEND_TRANSFER,
    CREDIT_CARD_PROFILE_REQUIRED,
    CREDIT_LIMIT_EXCEEDED,
    INSUFFICIENT_WALLET_BALANCE,
    CROSS_CURRENCY_DETAILS_REQUIRED,
    INVALID_EXCHANGE_RATE,
    INVALID_EXCHANGE_RATE_DATE,
    INVALID_KIND_FIELDS,
    UNSUPPORTED_TRANSFER_SUBTYPE,
}

class TransactionValidationException(val reason: TransactionValidationError) :
    IllegalArgumentException(reason.name)

private fun transactionFail(reason: TransactionValidationError): Nothing =
    throw TransactionValidationException(reason)

private fun validateTransactionDependency(
    requestedId: String?,
    wallet: LedgerWalletRecord?,
    owner: String,
    reason: TransactionValidationError,
) {
    if (requestedId == null) {
        if (wallet != null) transactionFail(reason)
        return
    }
    if (wallet == null || wallet.id != requestedId || wallet.ownerUserId != owner ||
        wallet.kind == null || wallet.isArchived || wallet.deletedAt != null
    ) {
        transactionFail(reason)
    }
}

private fun validateTransactionCategory(
    requestedId: String?,
    category: TransactionCategoryRecord?,
    owner: String,
) {
    if (requestedId == null) {
        if (category != null) transactionFail(TransactionValidationError.INVALID_CATEGORY)
        return
    }
    if (category == null || category.id != requestedId || category.ownerUserId != owner ||
        category.kind == null || category.isArchived || category.deletedAt != null
    ) {
        transactionFail(TransactionValidationError.INVALID_CATEGORY)
    }
}

private fun transactionUuid(value: String): String = UUID.fromString(value.trim()).toString()
private fun transactionInstant(value: String): String = Instant.parse(value.trim()).toString()
private fun String?.transactionOptional(): String? = this?.trim()?.takeIf(String::isNotEmpty)
private fun String.transactionCurrency(): String {
    val value = trim().uppercase(Locale.ROOT)
    if (!value.matches(Regex("^[A-Z]{3}$"))) transactionFail(TransactionValidationError.INVALID_KIND_FIELDS)
    return value
}
private fun JsonObject.transactionString(key: String): String? =
    (get(key) as? JsonPrimitive)?.contentOrNull?.takeIf(String::isNotBlank)
private fun JsonObject.transactionLong(key: String): Long =
    (get(key) as? JsonPrimitive)?.longOrNull ?: 0L
private fun JsonObject.transactionLongOrNull(key: String): Long? =
    (get(key) as? JsonPrimitive)?.longOrNull
private fun JsonObject.transactionBoolean(key: String): Boolean =
    (get(key) as? JsonPrimitive)?.booleanOrNull ?: false
private fun JsonObject.transactionUuidOrNull(key: String): String? = transactionString(key)?.let(::transactionUuid)
private fun kotlinx.serialization.json.JsonObjectBuilder.putNullableTransactionString(key: String, value: String?) {
    put(key, value?.let(::JsonPrimitive) ?: JsonNull)
}
private fun kotlinx.serialization.json.JsonObjectBuilder.putNullableTransactionLong(key: String, value: Long?) {
    put(key, value?.let(::JsonPrimitive) ?: JsonNull)
}
