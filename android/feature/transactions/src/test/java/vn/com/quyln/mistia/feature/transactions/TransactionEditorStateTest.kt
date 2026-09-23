package vn.com.quyln.mistia.feature.transactions

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import vn.com.quyln.mistia.core.model.CurrencyConversionMode
import vn.com.quyln.mistia.core.model.ExchangeRateSnapshot
import vn.com.quyln.mistia.core.model.LedgerTransactionRecord
import vn.com.quyln.mistia.core.model.TransactionEntryStatus
import vn.com.quyln.mistia.core.model.TransactionPrimaryKind
import vn.com.quyln.mistia.core.model.TransactionTransferSubtype

class TransactionEditorStateTest {
    @Test
    fun `new editor defaults to posted expense at supplied time`() {
        val state = TransactionEditorState.new(NOW)

        assertEquals(TransactionPrimaryKind.EXPENSE, state.primaryKind)
        assertEquals(TransactionEntryStatus.POSTED, state.entryStatus)
        assertEquals(NOW, state.occurredAt)
    }

    @Test
    fun `selecting transfer clears category and selects internal flow`() {
        val state = TransactionEditorState.new(NOW).copy(categoryId = CATEGORY_ID)
            .selectKind(TransactionPrimaryKind.TRANSFER)

        assertNull(state.categoryId)
        assertEquals(TransactionTransferSubtype.INTERNAL_TRANSFER, state.transferSubtype)
    }

    @Test
    fun `selecting expense clears destination and fx`() {
        val state = TransactionEditorState.new(NOW).copy(
            primaryKind = TransactionPrimaryKind.TRANSFER,
            transferSubtype = TransactionTransferSubtype.INTERNAL_TRANSFER,
            destinationWalletId = DESTINATION_WALLET_ID,
            destinationAmountText = "1650000",
            conversionMode = CurrencyConversionMode.MANUAL,
            exchangeRateText = "165",
        ).selectKind(TransactionPrimaryKind.EXPENSE)

        assertNull(state.destinationWalletId)
        assertEquals("", state.destinationAmountText)
        assertNull(state.conversionMode)
        assertEquals("", state.exchangeRateText)
    }

    @Test
    fun `cross currency draft parses source and destination minor units exactly`() {
        val result = TransactionEditorState.new(NOW).copy(
            primaryKind = TransactionPrimaryKind.TRANSFER,
            transferSubtype = TransactionTransferSubtype.INTERNAL_TRANSFER,
            title = "Exchange",
            amountText = "10000",
            sourceWalletId = SOURCE_WALLET_ID,
            destinationWalletId = DESTINATION_WALLET_ID,
            destinationAmountText = "1650000",
            conversionMode = CurrencyConversionMode.MANUAL,
            exchangeRateText = "165.000000",
            exchangeRateProvider = "manual",
            exchangeRateDate = "2026-09-23",
        ).toDraft(sourceCurrencyCode = "JPY", destinationCurrencyCode = "VND")

        assertNull(result.validation)
        assertEquals(10_000L, result.draft?.amountMinor)
        assertEquals(1_650_000L, result.draft?.destinationAmountMinor)
        assertEquals("165.000000", result.draft?.exchangeRateDecimalString)
        assertEquals("manual", result.draft?.exchangeRateProvider)
        assertEquals("2026-09-23", result.draft?.exchangeRateDate)
    }

    @Test
    fun `app rate draft derives destination and exact snapshot metadata`() {
        val result = TransactionEditorState.new(NOW).copy(
            primaryKind = TransactionPrimaryKind.TRANSFER,
            transferSubtype = TransactionTransferSubtype.INTERNAL_TRANSFER,
            title = "Exchange",
            amountText = "10000",
            sourceWalletId = SOURCE_WALLET_ID,
            destinationWalletId = DESTINATION_WALLET_ID,
            destinationAmountText = "1",
            conversionMode = CurrencyConversionMode.APP_RATE,
            exchangeRateText = "stale-manual-rate",
            exchangeRateProvider = "manual",
        ).toDraft(
            sourceCurrencyCode = "JPY",
            destinationCurrencyCode = "VND",
            rates = listOf(rate()),
        )

        assertNull(result.validation)
        assertEquals(1_655_000L, result.draft?.destinationAmountMinor)
        assertEquals(CurrencyConversionMode.APP_RATE, result.draft?.conversionMode)
        assertEquals("165.5", result.draft?.exchangeRateDecimalString)
        assertEquals("frankfurter", result.draft?.exchangeRateProvider)
        assertEquals("2026-09-22", result.draft?.exchangeRateDate)
    }

    @Test
    fun `app rate draft fails when selected pair has no cached rate`() {
        val result = TransactionEditorState.new(NOW).copy(
            primaryKind = TransactionPrimaryKind.TRANSFER,
            transferSubtype = TransactionTransferSubtype.INTERNAL_TRANSFER,
            amountText = "10000",
            sourceWalletId = SOURCE_WALLET_ID,
            destinationWalletId = DESTINATION_WALLET_ID,
            conversionMode = CurrencyConversionMode.APP_RATE,
        ).toDraft("JPY", "VND", emptyList())

        assertNull(result.draft)
        assertEquals(TransactionEditorValidation.INVALID_EXCHANGE_RATE, result.validation)
    }

    @Test
    fun `wallet pair change clears stale app metadata and falls back to manual`() {
        val state = TransactionEditorState.new(NOW).copy(
            primaryKind = TransactionPrimaryKind.TRANSFER,
            transferSubtype = TransactionTransferSubtype.INTERNAL_TRANSFER,
            amountText = "10000",
            destinationAmountText = "1655000",
            conversionMode = CurrencyConversionMode.APP_RATE,
            exchangeRateText = "165.5",
            exchangeRateProvider = "frankfurter",
            exchangeRateDate = "2026-09-22",
        )

        val changed = state.withFxPair("USD", "VND", listOf(rate()))

        assertEquals(CurrencyConversionMode.MANUAL, changed.conversionMode)
        assertEquals("", changed.destinationAmountText)
        assertEquals("", changed.exchangeRateText)
        assertEquals("manual", changed.exchangeRateProvider)
        assertNull(changed.exchangeRateDate)
    }

    @Test
    fun `same currency pair clears every conversion field`() {
        val changed = TransactionEditorState.new(NOW).copy(
            destinationAmountText = "1655000",
            conversionMode = CurrencyConversionMode.APP_RATE,
            exchangeRateText = "165.5",
            exchangeRateProvider = "frankfurter",
            exchangeRateDate = "2026-09-22",
        ).withFxPair("JPY", "JPY", listOf(rate()))

        assertEquals("", changed.destinationAmountText)
        assertNull(changed.conversionMode)
        assertEquals("", changed.exchangeRateText)
        assertNull(changed.exchangeRateProvider)
        assertNull(changed.exchangeRateDate)
    }

    @Test
    fun `display state refreshes an existing app rate from the current snapshot`() {
        val stale = TransactionEditorState.new(NOW).copy(
            amountText = "10000",
            conversionMode = CurrencyConversionMode.APP_RATE,
            destinationAmountText = "1655000",
            exchangeRateText = "165.5",
            exchangeRateProvider = "frankfurter",
            exchangeRateDate = "2026-09-22",
        )
        val current = rate().copy(rateDecimalString = "164.77", rateDate = "2026-09-23")

        val refreshed = stale.withCurrentAppRate("JPY", "VND", listOf(current))

        assertEquals(CurrencyConversionMode.APP_RATE, refreshed.conversionMode)
        assertEquals("1647700", refreshed.destinationAmountText)
        assertEquals("164.77", refreshed.exchangeRateText)
        assertEquals("2026-09-23", refreshed.exchangeRateDate)
    }

    @Test
    fun `edit maps exact fx and identifiers`() {
        val state = TransactionEditorState.edit(transaction())

        assertEquals(TransactionPrimaryKind.TRANSFER, state.primaryKind)
        assertEquals(SOURCE_WALLET_ID, state.sourceWalletId)
        assertEquals(DESTINATION_WALLET_ID, state.destinationWalletId)
        assertEquals("1650000", state.destinationAmountText)
        assertEquals(CurrencyConversionMode.MANUAL, state.conversionMode)
        assertEquals("165.000000", state.exchangeRateText)
    }

    @Test
    fun `posted expense reports missing wallet before amount and category`() {
        val result = TransactionEditorState.new(NOW).toDraft(null, null)

        assertNull(result.draft)
        assertEquals(TransactionEditorValidation.SOURCE_WALLET_REQUIRED, result.validation)
    }

    @Test
    fun `posted expense requires a category after wallet is selected`() {
        val result = TransactionEditorState.new(NOW).copy(
            sourceWalletId = SOURCE_WALLET_ID,
            amountText = "100",
        ).toDraft("JPY", null)

        assertNull(result.draft)
        assertEquals(TransactionEditorValidation.CATEGORY_REQUIRED, result.validation)
    }

    @Test
    fun `editor only opens ordinary records without settlement ownership`() {
        assertTrue(transaction().supportsNativeTransactionEditor())
        assertFalse(
            transaction().copy(
                transferSubtypeWireValue = TransactionTransferSubtype.FAMILY_TRANSFER.wireValue,
            ).supportsNativeTransactionEditor()
        )
        assertFalse(
            transaction().copy(settlementGroupId = CATEGORY_ID).supportsNativeTransactionEditor()
        )
    }

    private fun transaction() = LedgerTransactionRecord(
        id = TRANSACTION_ID,
        ownerUserId = OWNER,
        primaryKindWireValue = TransactionPrimaryKind.TRANSFER.wireValue,
        transferSubtypeWireValue = TransactionTransferSubtype.INTERNAL_TRANSFER.wireValue,
        debtIntentWireValue = null,
        entryStatusWireValue = TransactionEntryStatus.POSTED.wireValue,
        title = "Exchange",
        note = null,
        amountMinor = 10_000,
        sourceCurrencyCode = "JPY",
        destinationCurrencyCode = "VND",
        destinationAmountMinor = 1_650_000,
        reportingCurrencyCode = null,
        reportingAmountMinor = null,
        conversionModeWireValue = CurrencyConversionMode.MANUAL.wireValue,
        exchangeRateDecimalString = "165.000000",
        exchangeRateProvider = "manual",
        exchangeRateDate = "2026-09-23",
        occurredAt = NOW,
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
        destinationWalletId = DESTINATION_WALLET_ID,
        categoryId = null,
        deletedAt = null,
        isArchived = false,
        archivedAt = null,
        syncVersion = 0,
        lastModifiedByDeviceId = DEVICE,
    )

    private fun rate() = ExchangeRateSnapshot(
        baseCurrencyCode = "JPY",
        quoteCurrencyCode = "VND",
        rateDecimalString = "165.5",
        provider = "frankfurter",
        fetchedAtEpochMillis = 1L,
        rateDate = "2026-09-22",
    )

    private companion object {
        const val OWNER = "11111111-1111-1111-1111-111111111111"
        const val TRANSACTION_ID = "22222222-2222-2222-2222-222222222222"
        const val SOURCE_WALLET_ID = "33333333-3333-3333-3333-333333333333"
        const val DESTINATION_WALLET_ID = "44444444-4444-4444-4444-444444444444"
        const val CATEGORY_ID = "55555555-5555-5555-5555-555555555555"
        const val DEVICE = "66666666-6666-6666-6666-666666666666"
        const val NOW = "2026-09-23T12:00:00Z"
    }
}
