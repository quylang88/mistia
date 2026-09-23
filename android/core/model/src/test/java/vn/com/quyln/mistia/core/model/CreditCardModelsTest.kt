package vn.com.quyln.mistia.core.model

import kotlinx.serialization.json.JsonNull
import org.junit.Assert.assertEquals
import org.junit.Test

class CreditCardModelsTest {
    @Test
    fun `profile payload round trip keeps explicit nulls and signed long values`() {
        val profile = profile(
            creditLimitMinor = Long.MAX_VALUE,
            notes = null,
            paymentSourceWalletId = null,
            syncVersion = Long.MAX_VALUE - 1,
        )

        val payload = profile.toPayload()
        val decoded = CreditCardProfileRecord.fromCloudRecord(profile.toCloudRecord())

        assertEquals(JsonNull, payload["notes"])
        assertEquals(JsonNull, payload["payment_source_wallet_id"])
        assertEquals(Long.MAX_VALUE, decoded.creditLimitMinor)
        assertEquals(Long.MAX_VALUE - 1, decoded.syncVersion)
        assertEquals(profile, decoded)
    }

    @Test
    fun `draft creates linked wallet and profile mutations with independent base versions`() {
        val paymentSource = wallet(PAYMENT_WALLET_ID, WalletKind.BANK, syncVersion = 8)
        val result = CreditCardDraft(
            walletId = CARD_WALLET_ID,
            profileId = PROFILE_ID,
            name = "Travel Card",
            issuerName = "Mistia Bank",
            network = CreditCardNetwork.VISA,
            last4 = "1234",
            creditLimitMinor = 350_000,
            statementClosingDay = 10,
            paymentDueDay = 26,
            notes = " Main card ",
            paymentSourceWalletId = PAYMENT_WALLET_ID,
            currencyCode = "jpy",
            sortOrder = 4,
        ).toMutation(
            ownerUserId = UserId(OWNER),
            existingWallet = wallet(CARD_WALLET_ID, WalletKind.CREDIT_CARD, syncVersion = 6),
            existingProfile = profile(syncVersion = 7),
            paymentSourceWallet = paymentSource,
            deviceId = DEVICE,
            now = LATER,
        )

        assertEquals(WalletKind.CREDIT_CARD, result.wallet.record.kind)
        assertEquals(6L, result.wallet.pending.baseVersion)
        assertEquals(7L, result.profile.pending.baseVersion)
        assertEquals(CARD_WALLET_ID, result.profile.record.walletId)
        assertEquals(PAYMENT_WALLET_ID, result.profile.record.paymentSourceWalletId)
        assertEquals("Main card", result.profile.record.notes)
        assertEquals("JPY", result.wallet.record.currencyCode)
    }

    @Test
    fun `draft rejects invalid billing order and a credit card payment source`() {
        val invalidDays = runCatching {
            draft(statementClosingDay = 26, paymentDueDay = 10).toMutation(
                UserId(OWNER), null, null, null, DEVICE, NOW,
            )
        }.exceptionOrNull() as CreditCardValidationException
        val invalidSource = runCatching {
            draft(paymentSourceWalletId = PAYMENT_WALLET_ID).toMutation(
                UserId(OWNER),
                null,
                null,
                wallet(PAYMENT_WALLET_ID, WalletKind.CREDIT_CARD),
                DEVICE,
                NOW,
            )
        }.exceptionOrNull() as CreditCardValidationException
        val selfSource = runCatching {
            draft(paymentSourceWalletId = CARD_WALLET_ID).toMutation(
                UserId(OWNER),
                null,
                null,
                wallet(CARD_WALLET_ID, WalletKind.BANK),
                DEVICE,
                NOW,
            )
        }.exceptionOrNull() as CreditCardValidationException

        assertEquals(CreditCardValidationError.INVALID_BILLING_DAYS, invalidDays.reason)
        assertEquals(CreditCardValidationError.INVALID_PAYMENT_SOURCE, invalidSource.reason)
        assertEquals(CreditCardValidationError.INVALID_PAYMENT_SOURCE, selfSource.reason)
    }

    @Test
    fun `draft rejects a malformed last four and negative credit limit`() {
        val invalidLast4 = runCatching { draft(last4 = "12x4").toMutation(UserId(OWNER), null, null, null, DEVICE, NOW) }
            .exceptionOrNull() as CreditCardValidationException
        val invalidLimit = runCatching { draft(creditLimitMinor = -1).toMutation(UserId(OWNER), null, null, null, DEVICE, NOW) }
            .exceptionOrNull() as CreditCardValidationException

        assertEquals(CreditCardValidationError.INVALID_LAST4, invalidLast4.reason)
        assertEquals(CreditCardValidationError.INVALID_CREDIT_LIMIT, invalidLimit.reason)
    }

    private fun draft(
        statementClosingDay: Int = 10,
        paymentDueDay: Int = 26,
        paymentSourceWalletId: String? = null,
        last4: String = "1234",
        creditLimitMinor: Long = 100_000,
    ) = CreditCardDraft(
        walletId = CARD_WALLET_ID,
        profileId = PROFILE_ID,
        name = "Card",
        issuerName = "Issuer",
        network = CreditCardNetwork.JCB,
        last4 = last4,
        creditLimitMinor = creditLimitMinor,
        statementClosingDay = statementClosingDay,
        paymentDueDay = paymentDueDay,
        paymentSourceWalletId = paymentSourceWalletId,
        currencyCode = "JPY",
    )

    private fun profile(
        creditLimitMinor: Long = 100_000,
        notes: String? = null,
        paymentSourceWalletId: String? = PAYMENT_WALLET_ID,
        syncVersion: Long = 0,
    ) = CreditCardProfileRecord(
        id = PROFILE_ID,
        ownerUserId = OWNER,
        issuerName = "Issuer",
        networkWireValue = "visa",
        last4 = "1234",
        creditLimitMinor = creditLimitMinor,
        statementClosingDay = 10,
        paymentDueDay = 26,
        notes = notes,
        walletId = CARD_WALLET_ID,
        paymentSourceWalletId = paymentSourceWalletId,
        autoPayEnabled = true,
        createdAt = NOW,
        updatedAt = NOW,
        deletedAt = null,
        syncVersion = syncVersion,
        lastModifiedByDeviceId = DEVICE,
    )

    private fun wallet(id: String, kind: WalletKind, syncVersion: Long = 0) = LedgerWalletRecord(
        id = id,
        ownerUserId = OWNER,
        name = "Wallet",
        kindWireValue = kind.wireValue,
        iconSymbolName = kind.defaultIcon,
        iconColorHex = kind.defaultColorHex,
        currencyCode = "JPY",
        openingBalanceMinor = 0,
        institutionDisplayName = if (kind == WalletKind.BANK) "Bank" else null,
        institutionPresetKey = null,
        sortOrder = 0,
        isArchived = false,
        archivedAt = null,
        createdAt = NOW,
        updatedAt = NOW,
        deletedAt = null,
        syncVersion = syncVersion,
        lastModifiedByDeviceId = DEVICE,
        systemPurposeRawValue = null,
        investmentLinkedWalletId = null,
    )

    private companion object {
        const val OWNER = "11111111-1111-1111-1111-111111111111"
        const val CARD_WALLET_ID = "22222222-2222-2222-2222-222222222222"
        const val PROFILE_ID = "33333333-3333-3333-3333-333333333333"
        const val PAYMENT_WALLET_ID = "44444444-4444-4444-4444-444444444444"
        const val DEVICE = "55555555-5555-5555-5555-555555555555"
        const val NOW = "2026-09-23T10:00:00.000Z"
        const val LATER = "2026-09-23T11:00:00.000Z"
    }
}
