package vn.com.quyln.mistia.feature.transactions

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import vn.com.quyln.mistia.core.model.CurrencyConversionMode
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
        ).toDraft(sourceCurrencyCode = "JPY", destinationCurrencyCode = "VND")

        assertNull(result.validation)
        assertEquals(10_000L, result.draft?.amountMinor)
        assertEquals(1_650_000L, result.draft?.destinationAmountMinor)
        assertEquals("165.000000", result.draft?.exchangeRateDecimalString)
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
