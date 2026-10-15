package vn.com.quyln.mistia.feature.management

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import vn.com.quyln.mistia.core.model.LedgerWalletRecord
import vn.com.quyln.mistia.core.model.WalletKind

class WalletEditorStateTest {
    @Test fun `supported wallet balances group exact signed minor input`() {
        for (currency in listOf("JPY", "VND")) {
            val state = WalletEditorState.new().copy(currencyCode = currency).withOpeningBalance("9007199254740993")
            assertEquals("9,007,199,254,740,993", state.openingBalanceText)
            assertEquals(9007199254740993L, state.toDraft("Cash").draft?.openingBalanceMinor)
            val negative = state.withOpeningBalance(Long.MIN_VALUE.toString())
            assertEquals("-9,223,372,036,854,775,808", negative.openingBalanceText)
            assertEquals(Long.MIN_VALUE, negative.toDraft("Cash").draft?.openingBalanceMinor)
        }
    }

    @Test fun `blank malformed and overflow balances retain existing validation`() {
        val state = WalletEditorState.new()
        assertEquals(0L, state.withOpeningBalance("").toDraft("Cash").draft?.openingBalanceMinor)
        assertEquals("-", state.withOpeningBalance("-").openingBalanceText)
        assertEquals(WalletEditorValidation.INVALID_OPENING_BALANCE, state.withOpeningBalance("-").toDraft("Cash").validation)
        assertEquals("1.5", state.withOpeningBalance("1.5").openingBalanceText)
        assertEquals(WalletEditorValidation.INVALID_OPENING_BALANCE, state.withOpeningBalance("1.5").toDraft("Cash").validation)
        val overflow = state.withOpeningBalance("9223372036854775808")
        assertEquals("9,223,372,036,854,775,808", overflow.openingBalanceText)
        assertEquals(WalletEditorValidation.INVALID_OPENING_BALANCE, overflow.toDraft("Cash").validation)
    }

    @Test fun `imported fractional wallet input preserves decimal units`() {
        val state = WalletEditorState.new().copy(currencyCode = "USD").withOpeningBalance("12.34")
        assertEquals("12.34", state.openingBalanceText)
        assertEquals(1234L, state.toDraft("Cash").draft?.openingBalanceMinor)
    }

    @Test fun `existing wallet groups display text while original balance stays immutable`() {
        val state = WalletEditorState.edit(wallet(9007199254740993L))
        assertEquals("9,007,199,254,740,993", state.openingBalanceText)
        assertEquals(9007199254740993L, state.withOpeningBalance("0").toDraft("Cash").draft?.openingBalanceMinor)
    }

    @Test
    fun `selecting a kind applies its default icon until customized`() {
        val changed = WalletEditorState.new().selectKind(WalletKind.BANK)

        assertEquals("mistia.wallet.bank", changed.iconSymbolName)
        assertEquals("#5B7BFF", changed.iconColorHex)
    }

    @Test
    fun `custom icon survives later kind change`() {
        val changed = WalletEditorState.new()
            .customizeIcon("account_balance", "#123456")
            .selectKind(WalletKind.BANK)

        assertEquals("account_balance", changed.iconSymbolName)
        assertEquals("#123456", changed.iconColorHex)
    }

    @Test
    fun `bank save exposes validation reason`() {
        val result = WalletEditorState.new().selectKind(WalletKind.BANK).toDraft("Bank")

        assertEquals(WalletEditorValidation.BANK_INSTITUTION_REQUIRED, result.validation)
    }

    @Test
    fun `leaving bank kind clears bank-only fields`() {
        val changed = WalletEditorState.new()
            .selectKind(WalletKind.BANK)
            .copy(institutionDisplayName = "MUFG", institutionPresetKey = "mufg")
            .selectKind(WalletKind.CASH)

        assertEquals("", changed.institutionDisplayName)
        assertEquals(null, changed.institutionPresetKey)
    }

    @Test
    fun `editing metadata cannot rewrite the existing opening balance`() {
        val result = WalletEditorState.edit(wallet(openingBalanceMinor = 12_345L))
            .copy(name = "Renamed", openingBalanceText = "999999")
            .toDraft("Cash")

        assertEquals(12_345L, result.draft?.openingBalanceMinor)
    }

    @Test
    fun `opening balance parses exact minor units for JPY and USD`() {
        val jpy = WalletEditorState.new()
            .copy(name = "Cash", currencyCode = "JPY", openingBalanceText = "9007199254740993")
            .toDraft("Cash")
        val usd = WalletEditorState.new()
            .copy(name = "Cash", currencyCode = "USD", openingBalanceText = "12.34")
            .toDraft("Cash")

        assertEquals(9_007_199_254_740_993L, jpy.draft?.openingBalanceMinor)
        assertEquals(1_234L, usd.draft?.openingBalanceMinor)
    }

    @Test
    fun `fractional JPY balance is rejected instead of rounded`() {
        val result = WalletEditorState.new()
            .copy(name = "Cash", currencyCode = "JPY", openingBalanceText = "1.5")
            .toDraft("Cash")

        assertEquals(WalletEditorValidation.INVALID_OPENING_BALANCE, result.validation)
    }

    @Test
    fun `regular flow excludes credit card and investment kinds`() {
        assertFalse(WalletEditorState.supportedKinds.contains(WalletKind.CREDIT_CARD))
        assertFalse(WalletEditorState.supportedKinds.contains(WalletKind.INVESTMENT))
        assertTrue(WalletEditorState.supportedKinds.contains(WalletKind.CASH))
        assertTrue(WalletEditorState.supportedKinds.contains(WalletKind.BANK))
    }

    private fun wallet(openingBalanceMinor: Long) = LedgerWalletRecord(
        id = "11111111-1111-1111-1111-111111111111",
        ownerUserId = "22222222-2222-2222-2222-222222222222",
        name = "Cash",
        kindWireValue = WalletKind.CASH.wireValue,
        iconSymbolName = WalletKind.CASH.defaultIcon,
        iconColorHex = WalletKind.CASH.defaultColorHex,
        currencyCode = "JPY",
        openingBalanceMinor = openingBalanceMinor,
        institutionDisplayName = null,
        institutionPresetKey = null,
        sortOrder = 0,
        isArchived = false,
        archivedAt = null,
        createdAt = "2026-01-01T00:00:00Z",
        updatedAt = "2026-01-01T00:00:00Z",
        deletedAt = null,
        syncVersion = 0,
        lastModifiedByDeviceId = null,
        systemPurposeRawValue = null,
        investmentLinkedWalletId = null,
    )
}
