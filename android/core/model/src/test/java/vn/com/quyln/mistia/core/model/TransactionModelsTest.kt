package vn.com.quyln.mistia.core.model

import kotlinx.serialization.json.JsonNull
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class TransactionModelsTest {
    @Test
    fun `counterparty normalization matches Foundation folding vectors`() {
        assertEquals("đang", normalizeCounterpartyName("  Đặng  "))
        assertEquals("strasse", normalizeCounterpartyName("Straße"))
        assertEquals("ngoc a", normalizeCounterpartyName("ＮＧỌＣ！Ａ"))
        assertEquals("alpha beta", normalizeCounterpartyName("--Alpha___  Beta!!"))
        assertEquals("οσ", normalizeCounterpartyName("ΟΣ"))
        assertEquals("isık", normalizeCounterpartyName("Işık"))
        assertEquals("ısık", normalizeCounterpartyName("ışık"))
        assertEquals("ss", normalizeCounterpartyName("ẞ"))
        assertEquals("α", normalizeCounterpartyName("ᾲ"))
        assertNull(normalizeCounterpartyName("！ -- "))
    }

    @Test
    fun `transaction payload round trip preserves explicit nulls and signed longs`() {
        val record = transactionRecord(
            amountMinor = Long.MAX_VALUE,
            note = null,
            destinationAmountMinor = null,
            syncVersion = Long.MAX_VALUE - 1,
        )

        val payload = record.toPayload()
        val decoded = LedgerTransactionRecord.fromCloudRecord(record.toCloudRecord())

        assertEquals(JsonNull, payload["note"])
        assertEquals(JsonNull, payload["destination_amount_minor"])
        assertEquals(JsonNull, payload["settlement_group_id"])
        assertEquals(Long.MAX_VALUE, decoded.amountMinor)
        assertEquals(Long.MAX_VALUE - 1, decoded.syncVersion)
        assertEquals(record, decoded)
    }

    @Test
    fun `posted expense mutation links owner wallet and matching category`() {
        val mutation = TransactionDraft(
            id = TRANSACTION_ID,
            primaryKind = TransactionPrimaryKind.EXPENSE,
            title = "Lunch",
            note = " cafe ",
            amountMinor = 1_250,
            occurredAt = OCCURRED_AT,
            sourceWalletId = SOURCE_WALLET_ID,
            categoryId = CATEGORY_ID,
        ).toMutation(
            UserId(OWNER),
            existing = null,
            sourceWallet = wallet(SOURCE_WALLET_ID, WalletKind.CASH, "JPY"),
            destinationWallet = null,
            category = category(TransactionCategoryKind.EXPENSE),
            deviceId = DEVICE,
            now = NOW,
        )

        assertEquals(TransactionPrimaryKind.EXPENSE, mutation.record.primaryKind)
        assertEquals("cafe", mutation.record.note)
        assertEquals("JPY", mutation.record.sourceCurrencyCode)
        assertEquals(CATEGORY_ID, mutation.record.categoryId)
        assertEquals(0L, mutation.pending.baseVersion)
    }

    @Test
    fun `cross currency internal transfer keeps exact destination and fx metadata`() {
        val mutation = TransactionDraft(
            id = TRANSACTION_ID,
            primaryKind = TransactionPrimaryKind.TRANSFER,
            transferSubtype = TransactionTransferSubtype.INTERNAL_TRANSFER,
            title = "Exchange",
            amountMinor = 10_000,
            occurredAt = OCCURRED_AT,
            sourceWalletId = SOURCE_WALLET_ID,
            destinationWalletId = DESTINATION_WALLET_ID,
            destinationAmountMinor = 1_650_000,
            conversionMode = CurrencyConversionMode.MANUAL,
            exchangeRateDecimalString = "165.000000",
            exchangeRateProvider = "manual",
            exchangeRateDate = "2026-09-23",
        ).toMutation(
            UserId(OWNER),
            existing = null,
            sourceWallet = wallet(SOURCE_WALLET_ID, WalletKind.BANK, "JPY"),
            destinationWallet = wallet(DESTINATION_WALLET_ID, WalletKind.BANK, "VND"),
            category = null,
            deviceId = DEVICE,
            now = NOW,
        )

        assertEquals("JPY", mutation.record.sourceCurrencyCode)
        assertEquals("VND", mutation.record.destinationCurrencyCode)
        assertEquals(1_650_000L, mutation.record.destinationAmountMinor)
        assertEquals("165.000000", mutation.record.exchangeRateDecimalString)
        assertEquals(CurrencyConversionMode.MANUAL, mutation.record.conversionMode)
        assertNull(mutation.record.categoryId)
    }

    @Test
    fun `same currency transfer clears stale fx fields on edit`() {
        val existing = transactionRecord(
            primaryKindWireValue = TransactionPrimaryKind.TRANSFER.wireValue,
            transferSubtypeWireValue = TransactionTransferSubtype.INTERNAL_TRANSFER.wireValue,
            sourceCurrencyCode = "JPY",
            destinationCurrencyCode = "VND",
            destinationAmountMinor = 1_650_000,
            conversionModeWireValue = CurrencyConversionMode.APP_RATE.wireValue,
            exchangeRateDecimalString = "165",
            exchangeRateProvider = "app",
            exchangeRateDate = "2026-09-23",
        )
        val mutation = TransactionDraft(
            id = TRANSACTION_ID,
            primaryKind = TransactionPrimaryKind.TRANSFER,
            transferSubtype = TransactionTransferSubtype.INTERNAL_TRANSFER,
            title = "Move",
            amountMinor = 10_000,
            occurredAt = OCCURRED_AT,
            sourceWalletId = SOURCE_WALLET_ID,
            destinationWalletId = DESTINATION_WALLET_ID,
            destinationAmountMinor = 99,
            conversionMode = CurrencyConversionMode.MANUAL,
            exchangeRateDecimalString = "99",
        ).toMutation(
            UserId(OWNER),
            existing,
            wallet(SOURCE_WALLET_ID, WalletKind.BANK, "JPY"),
            wallet(DESTINATION_WALLET_ID, WalletKind.BANK, "JPY"),
            null,
            DEVICE,
            NOW,
        )

        assertNull(mutation.record.destinationAmountMinor)
        assertNull(mutation.record.conversionModeWireValue)
        assertNull(mutation.record.exchangeRateDecimalString)
        assertNull(mutation.record.exchangeRateProvider)
        assertNull(mutation.record.exchangeRateDate)
    }

    @Test
    fun `posted debt lend stores normalized counterparty and clears incompatible fields`() {
        val mutation = TransactionDraft(
            id = TRANSACTION_ID,
            primaryKind = TransactionPrimaryKind.TRANSFER,
            transferSubtype = TransactionTransferSubtype.DEBT,
            debtIntent = TransactionDebtIntent.LEND,
            title = "FamilyMart",
            amountMinor = 1_500,
            occurredAt = OCCURRED_AT,
            sourceWalletId = SOURCE_WALLET_ID,
            counterpartyName = "  Ngọc Đặng！Ａ  ",
        ).toMutation(
            UserId(OWNER),
            existing = null,
            sourceWallet = wallet(SOURCE_WALLET_ID, WalletKind.BANK, "JPY"),
            destinationWallet = null,
            category = null,
            deviceId = DEVICE,
            now = NOW,
        )

        assertEquals(TransactionTransferSubtype.DEBT, mutation.record.transferSubtype)
        assertEquals(TransactionDebtIntent.LEND, mutation.record.debtIntent)
        assertEquals("Ngọc Đặng！Ａ", mutation.record.counterpartyName)
        assertEquals("ngoc đang a", mutation.record.normalizedCounterpartyKey)
        assertEquals("JPY", mutation.record.sourceCurrencyCode)
        assertNull(mutation.record.destinationWalletId)
        assertNull(mutation.record.destinationCurrencyCode)
        assertNull(mutation.record.destinationAmountMinor)
        assertNull(mutation.record.categoryId)
        assertEquals("ngoc đang a", mutation.pending.payload?.get("normalized_counterparty_key")?.toString()?.trim('"'))
    }

    @Test
    fun `posted debt lend rejects missing counterparty and unsupported intents`() {
        val missingCounterparty = failureReason(
            draft = baseDraft(TransactionPrimaryKind.TRANSFER).copy(
                transferSubtype = TransactionTransferSubtype.DEBT,
                debtIntent = TransactionDebtIntent.LEND,
            ),
            sourceWallet = wallet(SOURCE_WALLET_ID, WalletKind.BANK, "JPY"),
        )
        val unsupportedIntent = failureReason(
            draft = baseDraft(TransactionPrimaryKind.TRANSFER).copy(
                transferSubtype = TransactionTransferSubtype.DEBT,
                debtIntent = TransactionDebtIntent.BORROW,
                counterpartyName = "Trang",
            ),
            sourceWallet = wallet(SOURCE_WALLET_ID, WalletKind.BANK, "JPY"),
        )
        val unsupportedDraft = failureReason(
            draft = baseDraft(TransactionPrimaryKind.TRANSFER).copy(
                transferSubtype = TransactionTransferSubtype.DEBT,
                debtIntent = TransactionDebtIntent.LEND,
                counterpartyName = "Trang",
                entryStatus = TransactionEntryStatus.DRAFT,
            ),
            sourceWallet = wallet(SOURCE_WALLET_ID, WalletKind.BANK, "JPY"),
        )

        assertEquals(TransactionValidationError.COUNTERPARTY_REQUIRED, missingCounterparty)
        assertEquals(TransactionValidationError.UNSUPPORTED_DEBT_INTENT, unsupportedIntent)
        assertEquals(TransactionValidationError.UNSUPPORTED_DEBT_DRAFT, unsupportedDraft)
    }

    @Test
    fun `standalone debt lend edit clears reporting fields and rejects settlement ownership`() {
        val existing = transactionRecord(
            primaryKindWireValue = TransactionPrimaryKind.TRANSFER.wireValue,
            transferSubtypeWireValue = TransactionTransferSubtype.INTERNAL_TRANSFER.wireValue,
        ).copy(
            reportingCurrencyCode = "VND",
            reportingAmountMinor = 25_000,
            destinationCurrencyCode = "VND",
            destinationAmountMinor = 25_000,
            conversionModeWireValue = CurrencyConversionMode.MANUAL.wireValue,
            exchangeRateDecimalString = "25",
            exchangeRateProvider = "manual",
            exchangeRateDate = "2026-09-23",
        )
        val draft = baseDraft(TransactionPrimaryKind.TRANSFER).copy(
            transferSubtype = TransactionTransferSubtype.DEBT,
            debtIntent = TransactionDebtIntent.LEND,
            counterpartyName = "Trang",
        )

        val mutation = draft.toMutation(
            UserId(OWNER),
            existing,
            wallet(SOURCE_WALLET_ID, WalletKind.BANK, "JPY"),
            null,
            null,
            DEVICE,
            NOW,
        )

        assertNull(mutation.record.reportingCurrencyCode)
        assertNull(mutation.record.reportingAmountMinor)
        assertNull(mutation.record.settlementGroupId)
        assertNull(mutation.record.settlementObligationId)
        assertNull(mutation.record.settlementRoleWireValue)
        assertNull(mutation.record.reportingExpenseMinor)
        assertNull(mutation.record.reportingIncomeMinor)
        assertEquals(JsonNull, mutation.pending.payload?.get("reporting_currency_code"))
        assertEquals(JsonNull, mutation.pending.payload?.get("settlement_group_id"))

        val failure = runCatching {
            draft.toMutation(
                UserId(OWNER),
                existing.copy(
                    settlementGroupId = PARENT_CATEGORY_ID,
                    settlementRoleWireValue = "sharedExpenseReceivable",
                    reportingExpenseMinor = 100,
                ),
                wallet(SOURCE_WALLET_ID, WalletKind.BANK, "JPY"),
                null,
                null,
                DEVICE,
                NOW,
            )
        }.exceptionOrNull() as TransactionValidationException
        assertEquals(TransactionValidationError.SETTLEMENT_OWNED_TRANSACTION, failure.reason)
    }

    @Test
    fun `invalid wallet and fx combinations are rejected`() {
        val incomeToCard = failureReason(
            draft = baseDraft(TransactionPrimaryKind.INCOME, categoryId = CATEGORY_ID),
            sourceWallet = wallet(SOURCE_WALLET_ID, WalletKind.CREDIT_CARD, "JPY"),
            category = category(TransactionCategoryKind.INCOME),
        )
        val sameWallet = failureReason(
            draft = baseDraft(TransactionPrimaryKind.TRANSFER).copy(
                transferSubtype = TransactionTransferSubtype.INTERNAL_TRANSFER,
                destinationWalletId = SOURCE_WALLET_ID,
            ),
            sourceWallet = wallet(SOURCE_WALLET_ID, WalletKind.BANK, "JPY"),
            destinationWallet = wallet(SOURCE_WALLET_ID, WalletKind.BANK, "JPY"),
        )
        val missingFx = failureReason(
            draft = baseDraft(TransactionPrimaryKind.TRANSFER).copy(
                transferSubtype = TransactionTransferSubtype.INTERNAL_TRANSFER,
                destinationWalletId = DESTINATION_WALLET_ID,
            ),
            sourceWallet = wallet(SOURCE_WALLET_ID, WalletKind.BANK, "JPY"),
            destinationWallet = wallet(DESTINATION_WALLET_ID, WalletKind.BANK, "VND"),
        )
        val parentCategory = failureReason(
            draft = baseDraft(TransactionPrimaryKind.EXPENSE, categoryId = CATEGORY_ID),
            sourceWallet = wallet(SOURCE_WALLET_ID, WalletKind.CASH, "JPY"),
            category = category(TransactionCategoryKind.EXPENSE, child = false),
        )

        assertEquals(TransactionValidationError.CREDIT_CARD_CANNOT_RECEIVE_INCOME, incomeToCard)
        assertEquals(TransactionValidationError.SAME_WALLET_TRANSFER, sameWallet)
        assertEquals(TransactionValidationError.CROSS_CURRENCY_DETAILS_REQUIRED, missingFx)
        assertEquals(TransactionValidationError.CATEGORY_CHILD_REQUIRED, parentCategory)
    }

    @Test
    fun `draft entry permits missing title wallet and category`() {
        val mutation = TransactionDraft(
            id = TRANSACTION_ID,
            primaryKind = TransactionPrimaryKind.EXPENSE,
            entryStatus = TransactionEntryStatus.DRAFT,
            title = "",
            amountMinor = 1,
            occurredAt = OCCURRED_AT,
        ).toMutation(UserId(OWNER), null, null, null, null, DEVICE, NOW)

        assertEquals(TransactionEntryStatus.DRAFT, mutation.record.entryStatus)
        assertNull(mutation.record.sourceWalletId)
        assertNull(mutation.record.categoryId)
    }

    private fun failureReason(
        draft: TransactionDraft,
        sourceWallet: LedgerWalletRecord? = null,
        destinationWallet: LedgerWalletRecord? = null,
        category: TransactionCategoryRecord? = null,
    ): TransactionValidationError {
        val failure = runCatching {
            draft.toMutation(UserId(OWNER), null, sourceWallet, destinationWallet, category, DEVICE, NOW)
        }.exceptionOrNull() as TransactionValidationException
        return failure.reason
    }

    private fun baseDraft(kind: TransactionPrimaryKind, categoryId: String? = null) = TransactionDraft(
        id = TRANSACTION_ID,
        primaryKind = kind,
        title = "Entry",
        amountMinor = 100,
        occurredAt = OCCURRED_AT,
        sourceWalletId = SOURCE_WALLET_ID,
        categoryId = categoryId,
    )

    private fun transactionRecord(
        primaryKindWireValue: String = TransactionPrimaryKind.EXPENSE.wireValue,
        transferSubtypeWireValue: String? = null,
        amountMinor: Long = 100,
        note: String? = null,
        sourceCurrencyCode: String? = "JPY",
        destinationCurrencyCode: String? = null,
        destinationAmountMinor: Long? = null,
        conversionModeWireValue: String? = null,
        exchangeRateDecimalString: String? = null,
        exchangeRateProvider: String? = null,
        exchangeRateDate: String? = null,
        syncVersion: Long = 0,
    ) = LedgerTransactionRecord(
        id = TRANSACTION_ID,
        ownerUserId = OWNER,
        primaryKindWireValue = primaryKindWireValue,
        transferSubtypeWireValue = transferSubtypeWireValue,
        debtIntentWireValue = null,
        entryStatusWireValue = TransactionEntryStatus.POSTED.wireValue,
        title = "Entry",
        note = note,
        amountMinor = amountMinor,
        sourceCurrencyCode = sourceCurrencyCode,
        destinationCurrencyCode = destinationCurrencyCode,
        destinationAmountMinor = destinationAmountMinor,
        reportingCurrencyCode = null,
        reportingAmountMinor = null,
        conversionModeWireValue = conversionModeWireValue,
        exchangeRateDecimalString = exchangeRateDecimalString,
        exchangeRateProvider = exchangeRateProvider,
        exchangeRateDate = exchangeRateDate,
        occurredAt = OCCURRED_AT,
        createdAt = NOW,
        updatedAt = NOW,
        createdByUserId = OWNER,
        lastModifiedByUserId = OWNER,
        counterpartyName = null,
        normalizedCounterpartyKey = null,
        settlementGroupId = null,
        settlementObligationId = null,
        settlementRoleWireValue = null,
        reportingExpenseMinor = null,
        reportingIncomeMinor = null,
        sourceWalletId = SOURCE_WALLET_ID,
        destinationWalletId = null,
        categoryId = CATEGORY_ID,
        deletedAt = null,
        isArchived = false,
        archivedAt = null,
        syncVersion = syncVersion,
        lastModifiedByDeviceId = DEVICE,
    )

    private fun wallet(id: String, kind: WalletKind, currency: String) = LedgerWalletRecord(
        id = id,
        ownerUserId = OWNER,
        name = "Wallet",
        kindWireValue = kind.wireValue,
        iconSymbolName = kind.defaultIcon,
        iconColorHex = kind.defaultColorHex,
        currencyCode = currency,
        openingBalanceMinor = 0,
        institutionDisplayName = null,
        institutionPresetKey = null,
        sortOrder = 0,
        isArchived = false,
        archivedAt = null,
        createdAt = NOW,
        updatedAt = NOW,
        deletedAt = null,
        syncVersion = 0,
        lastModifiedByDeviceId = DEVICE,
        systemPurposeRawValue = null,
        investmentLinkedWalletId = null,
    )

    private fun category(kind: TransactionCategoryKind, child: Boolean = true) = TransactionCategoryRecord(
        id = CATEGORY_ID,
        ownerUserId = OWNER,
        name = "Category",
        nameEnglish = null,
        nameJapanese = null,
        kindWireValue = kind.wireValue,
        iconSymbolName = kind.defaultIcon,
        iconColorHex = kind.defaultColorHex,
        isFavorite = false,
        familyBudgetSpendingEnabled = false,
        parentCategoryId = if (child) PARENT_CATEGORY_ID else null,
        hierarchyRoleWireValue = if (child) {
            CategoryHierarchyRole.CHILD.wireValue
        } else {
            CategoryHierarchyRole.PARENT.wireValue
        },
        systemKey = null,
        isSystem = false,
        sortOrder = 0,
        isArchived = false,
        archivedAt = null,
        createdAt = NOW,
        updatedAt = NOW,
        deletedAt = null,
        syncVersion = 0,
        lastModifiedByDeviceId = DEVICE,
    )

    private companion object {
        const val OWNER = "11111111-1111-1111-1111-111111111111"
        const val TRANSACTION_ID = "22222222-2222-2222-2222-222222222222"
        const val SOURCE_WALLET_ID = "33333333-3333-3333-3333-333333333333"
        const val DESTINATION_WALLET_ID = "44444444-4444-4444-4444-444444444444"
        const val CATEGORY_ID = "55555555-5555-5555-5555-555555555555"
        const val PARENT_CATEGORY_ID = "88888888-8888-8888-8888-888888888888"
        const val DEVICE = "66666666-6666-6666-6666-666666666666"
        const val OCCURRED_AT = "2026-09-23T09:30:00.000Z"
        const val NOW = "2026-09-23T12:00:00.000Z"
    }
}
