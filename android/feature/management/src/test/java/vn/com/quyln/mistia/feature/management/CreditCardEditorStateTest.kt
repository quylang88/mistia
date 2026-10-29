package vn.com.quyln.mistia.feature.management

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import androidx.compose.runtime.saveable.SaverScope
import vn.com.quyln.mistia.core.model.CreditCardNetwork
import vn.com.quyln.mistia.core.model.CreditCardProfileRecord
import vn.com.quyln.mistia.core.model.LedgerWalletRecord
import vn.com.quyln.mistia.core.model.WalletKind

class CreditCardEditorStateTest {
    @Test fun `restored credit card draft rejects foreign owner or mismatched identity`() {
        val state = CreditCardEditorState.edit(wallet(), profile())
        val saver = CreditCardEditorState.scopedSaver(OWNER, CARD_WALLET_ID, PROFILE_ID)
        val saved = with(saver) { SaverScope { true }.save(state) }!!
        assertEquals(state, saver.restore(saved))
        assertNull(CreditCardEditorState.scopedSaver("other", CARD_WALLET_ID, PROFILE_ID).restore(saved))
        assertNull(CreditCardEditorState.scopedSaver(OWNER, PAYMENT_WALLET_ID, PROFILE_ID).restore(saved))
        assertNull(CreditCardEditorState.scopedSaver(OWNER, CARD_WALLET_ID, PAYMENT_WALLET_ID).restore(saved))
        assertNull(CreditCardEditorState.scopedSaver(OWNER, null, null).restore(saved))
    }

    @Test fun `malformed or legacy unowned card draft fails restoration safely`() {
        val saver = CreditCardEditorState.scopedSaver(OWNER, null, null)
        assertNull(saver.restore(listOf("bad")))
        assertNull(saver.restore(listOf(OWNER, "", "", listOf("bad"))))
        val legacy = with(CreditCardEditorState.Saver) { SaverScope { true }.save(CreditCardEditorState.new()) }!!
        assertNull(saver.restore(legacy))
    }

    @Test fun `opening a supported currency card groups an exact large limit`() {
        for (currency in listOf("JPY", "VND")) {
            val state = CreditCardEditorState.edit(wallet().copy(currencyCode = currency), profile().copy(creditLimitMinor = 9007199254740993L))
            assertEquals("9,007,199,254,740,993", state.creditLimitText)
            assertEquals(9007199254740993L, state.toDraft().draft?.creditLimitMinor)
        }
    }

    @Test fun `opening the maximum credit limit keeps every digit`() {
        val state = CreditCardEditorState.edit(wallet(), profile().copy(creditLimitMinor = Long.MAX_VALUE))
        assertEquals("9,223,372,036,854,775,807", state.creditLimitText)
        assertEquals(Long.MAX_VALUE, state.toDraft().draft?.creditLimitMinor)
    }

    @Test fun `zero blank negative malformed and overflowing credit limits retain validation`() {
        val state = CreditCardEditorState.new().copy(name = "Card")
        for (text in listOf("", "0")) assertEquals(0L, state.copy(creditLimitText = text).toDraft().draft?.creditLimitMinor)
        for (text in listOf("-1", "1.5", "bad", "9,223,372,036,854,775,808")) {
            assertEquals(CreditCardEditorValidation.INVALID_CREDIT_LIMIT, state.copy(creditLimitText = text).toDraft().validation)
        }
    }

    @Test fun `imported fractional card limit preserves existing decimal semantics`() {
        val state = CreditCardEditorState.edit(wallet().copy(currencyCode = "USD"), profile().copy(creditLimitMinor = 1234))
        assertEquals("12.34", state.creditLimitText)
        assertEquals(1234L, state.toDraft().draft?.creditLimitMinor)
    }

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


    @Test fun `payment choices contain only owned live same currency normal wallets`() {
        val cash=wallet().copy(id=PAYMENT_WALLET_ID,kindWireValue="cash")
        val foreign=cash.copy(id="foreign",ownerUserId="other")
        val other=cash.copy(id="other-currency",currencyCode="VND")
        val system=cash.copy(id="system",kindWireValue="investment")
        val deleted=cash.copy(id="deleted",deletedAt=NOW)
        val archived=cash.copy(id="archived",isArchived=true)
        assertEquals(listOf(cash),creditCardPaymentWalletChoices(OWNER,"JPY",listOf(cash,foreign,other,system,deleted,archived),null))
    }
    @Test fun `legacy selected mismatch is retained without adding new foreign choices`() {
        val cash=wallet().copy(id=PAYMENT_WALLET_ID,kindWireValue="cash")
        val retained=cash.copy(id="legacy",currencyCode="VND")
        val other=cash.copy(id="other",currencyCode="USD")
        assertEquals(listOf(cash,retained),creditCardPaymentWalletChoices(OWNER,"JPY",listOf(cash,retained,other),retained.id))
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
