package vn.com.quyln.mistia.feature.management

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import vn.com.quyln.mistia.core.model.CreditCardNetwork
import vn.com.quyln.mistia.core.model.CreditCardProfileRecord
import vn.com.quyln.mistia.core.model.LedgerWalletRecord
import vn.com.quyln.mistia.core.model.WalletKind

class CreditCardEditorStateTest {
    @Test
    fun `new card uses iOS billing defaults and card appearance`() {
        val state = CreditCardEditorState.new(nextSortOrder = 3)

        assertEquals(10, state.statementClosingDay)
        assertEquals(26, state.paymentDueDay)
        assertEquals(WalletKind.CREDIT_CARD.defaultIcon, state.iconSymbolName)
        assertEquals(3, state.sortOrder)
    }

    @Test
    fun `last four input keeps only four digits`() {
        val state = CreditCardEditorState.new().withLast4("12a345")

        assertEquals("1234", state.last4)
    }

    @Test
    fun `draft parses exact minor units and reports invalid billing order`() {
        val valid = CreditCardEditorState.new().copy(
            name = "Card",
            creditLimitText = "123456",
            currencyCode = "VND",
            statementClosingDay = 10,
            paymentDueDay = 26,
        ).toDraft()
        val invalid = CreditCardEditorState.new().copy(
            name = "Card",
            creditLimitText = "100000",
            statementClosingDay = 26,
            paymentDueDay = 10,
        ).toDraft()

        assertEquals(123_456L, valid.draft?.creditLimitMinor)
        assertNull(valid.validation)
        assertEquals(CreditCardEditorValidation.INVALID_BILLING_DAYS, invalid.validation)
    }

    @Test
    fun `edit maps profile and linked payment source`() {
        val state = CreditCardEditorState.edit(wallet(), profile())

        assertEquals("Issuer", state.issuerName)
        assertEquals(CreditCardNetwork.JCB, state.network)
        assertEquals("1234", state.last4)
        assertEquals(PAYMENT_WALLET_ID, state.paymentSourceWalletId)
        assertEquals(PROFILE_ID, state.profileId)
    }

    private fun wallet() = LedgerWalletRecord(
        id = CARD_WALLET_ID,
        ownerUserId = OWNER,
        name = "Card",
        kindWireValue = WalletKind.CREDIT_CARD.wireValue,
        iconSymbolName = WalletKind.CREDIT_CARD.defaultIcon,
        iconColorHex = WalletKind.CREDIT_CARD.defaultColorHex,
        currencyCode = "JPY",
        openingBalanceMinor = 0,
        institutionDisplayName = null,
        institutionPresetKey = null,
        sortOrder = 2,
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

    private fun profile() = CreditCardProfileRecord(
        id = PROFILE_ID,
        ownerUserId = OWNER,
        issuerName = "Issuer",
        networkWireValue = CreditCardNetwork.JCB.wireValue,
        last4 = "1234",
        creditLimitMinor = 350_000,
        statementClosingDay = 10,
        paymentDueDay = 26,
        notes = "memo",
        walletId = CARD_WALLET_ID,
        paymentSourceWalletId = PAYMENT_WALLET_ID,
        autoPayEnabled = true,
        createdAt = NOW,
        updatedAt = NOW,
        deletedAt = null,
        syncVersion = 0,
        lastModifiedByDeviceId = DEVICE,
    )

    private companion object {
        const val OWNER = "11111111-1111-1111-1111-111111111111"
        const val CARD_WALLET_ID = "22222222-2222-2222-2222-222222222222"
        const val PROFILE_ID = "33333333-3333-3333-3333-333333333333"
        const val PAYMENT_WALLET_ID = "44444444-4444-4444-4444-444444444444"
        const val DEVICE = "55555555-5555-5555-5555-555555555555"
        const val NOW = "2026-09-23T10:00:00.000Z"
    }
}
