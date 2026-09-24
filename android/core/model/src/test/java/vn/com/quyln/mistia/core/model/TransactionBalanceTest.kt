package vn.com.quyln.mistia.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class TransactionBalanceTest {
    @Test
    fun `current balance includes posted records regardless of occurred date`() {
        val source = wallet(SOURCE_WALLET_ID, WalletKind.BANK, openingBalanceMinor = 5_000)
        val destination = wallet(DESTINATION_WALLET_ID, WalletKind.BANK, openingBalanceMinor = 0)
        val records = listOf(
            transaction("10000000-0000-0000-0000-000000000001", TransactionPrimaryKind.EXPENSE, 1_000),
            transaction("10000000-0000-0000-0000-000000000002", TransactionPrimaryKind.INCOME, 250),
            transaction(
                id = "10000000-0000-0000-0000-000000000003",
                kind = TransactionPrimaryKind.TRANSFER,
                amount = 500,
                destinationWalletId = DESTINATION_WALLET_ID,
                destinationAmount = 750,
            ),
        )

        val index = TransactionWalletBalanceIndex(listOf(source, destination), records)

        assertEquals(3_750L, index.balance(SOURCE_WALLET_ID))
        assertEquals(750L, index.balance(DESTINATION_WALLET_ID))
    }

    @Test
    fun `draft affordability uses current balance and excludes edited record`() {
        val source = wallet(SOURCE_WALLET_ID, WalletKind.BANK, openingBalanceMinor = 1_000)
        val existing = transaction(TRANSACTION_ID, TransactionPrimaryKind.EXPENSE, 400)
        val edited = existing.copy(amountMinor = 800)

        edited.requireAffordable(
            wallets = listOf(source),
            records = listOf(existing),
            creditCardProfiles = emptyList(),
            excludingTransactionId = existing.id,
        )

        assertEquals(
            TransactionValidationError.INSUFFICIENT_WALLET_BALANCE,
            affordabilityFailure(
                edited.copy(amountMinor = 1_001),
                wallets = listOf(source),
                records = listOf(existing),
                excludingTransactionId = existing.id,
            ),
        )
    }

    @Test
    fun `credit card affordability uses limit minus current debt`() {
        val card = wallet(SOURCE_WALLET_ID, WalletKind.CREDIT_CARD, openingBalanceMinor = 99_999)
        val profile = creditCardProfile(limit = 10_000)
        val existing = transaction(
            id = "10000000-0000-0000-0000-000000000001",
            kind = TransactionPrimaryKind.EXPENSE,
            amount = 7_000,
        )
        val candidate = transaction(TRANSACTION_ID, TransactionPrimaryKind.EXPENSE, 3_000)

        candidate.requireAffordable(listOf(card), listOf(existing), listOf(profile), null)
        assertEquals(
            TransactionValidationError.CREDIT_LIMIT_EXCEEDED,
            affordabilityFailure(
                candidate.copy(amountMinor = 3_001),
                wallets = listOf(card),
                records = listOf(existing),
                profiles = listOf(profile),
            ),
        )
    }

    @Test
    fun `debt lending uses current cash balance and credit card available credit`() {
        val cash = wallet(SOURCE_WALLET_ID, WalletKind.BANK, openingBalanceMinor = 1_000)
        val cashLend = debtLend(TRANSACTION_ID, 1_001)
        assertEquals(
            TransactionValidationError.INSUFFICIENT_WALLET_BALANCE,
            affordabilityFailure(cashLend, wallets = listOf(cash), records = emptyList()),
        )

        val card = wallet(SOURCE_WALLET_ID, WalletKind.CREDIT_CARD, openingBalanceMinor = 0)
        val existingCharge = transaction(
            id = "10000000-0000-0000-0000-000000000001",
            kind = TransactionPrimaryKind.EXPENSE,
            amount = 7_000,
        )
        val cardLend = debtLend(TRANSACTION_ID, 3_001)
        assertEquals(
            TransactionValidationError.CREDIT_LIMIT_EXCEEDED,
            affordabilityFailure(
                cardLend,
                wallets = listOf(card),
                records = listOf(existingCharge),
                profiles = listOf(creditCardProfile(limit = 10_000)),
            ),
        )
    }

    @Test
    fun `transfer into credit card reduces debt by destination amount`() {
        val card = wallet(DESTINATION_WALLET_ID, WalletKind.CREDIT_CARD, openingBalanceMinor = 0)
        val debt = transaction(
            id = "10000000-0000-0000-0000-000000000001",
            kind = TransactionPrimaryKind.EXPENSE,
            amount = 7_000,
            sourceWalletId = DESTINATION_WALLET_ID,
        )
        val payment = transaction(
            id = "10000000-0000-0000-0000-000000000002",
            kind = TransactionPrimaryKind.TRANSFER,
            amount = 100,
            destinationWalletId = DESTINATION_WALLET_ID,
            destinationAmount = 2_000,
        )

        val index = TransactionWalletBalanceIndex(listOf(card), listOf(debt, payment))

        assertEquals(5_000L, index.balance(DESTINATION_WALLET_ID))
    }

    @Test
    fun `draft and archived records do not affect balance`() {
        val source = wallet(SOURCE_WALLET_ID, WalletKind.BANK, openingBalanceMinor = 1_000)
        val draft = transaction(TRANSACTION_ID, TransactionPrimaryKind.EXPENSE, 800)
            .copy(entryStatusWireValue = TransactionEntryStatus.DRAFT.wireValue)
        val archived = transaction(
            "10000000-0000-0000-0000-000000000001",
            TransactionPrimaryKind.EXPENSE,
            800,
        ).copy(isArchived = true)

        val index = TransactionWalletBalanceIndex(listOf(source), listOf(draft, archived))

        assertEquals(1_000L, index.balance(SOURCE_WALLET_ID))
        assertNull(
            runCatching {
                transaction(
                    "10000000-0000-0000-0000-000000000002",
                    TransactionPrimaryKind.EXPENSE,
                    1_000,
                ).requireAffordable(listOf(source), listOf(draft, archived), emptyList(), null)
            }.exceptionOrNull()
        )
    }

    private fun affordabilityFailure(
        record: LedgerTransactionRecord,
        wallets: List<LedgerWalletRecord>,
        records: List<LedgerTransactionRecord>,
        profiles: List<CreditCardProfileRecord> = emptyList(),
        excludingTransactionId: String? = null,
    ): TransactionValidationError? = runCatching {
        record.requireAffordable(wallets, records, profiles, excludingTransactionId)
    }.exceptionOrNull().let { (it as? TransactionValidationException)?.reason }

    private fun wallet(id: String, kind: WalletKind, openingBalanceMinor: Long) = LedgerWalletRecord(
        id = id,
        ownerUserId = OWNER,
        name = kind.wireValue,
        kindWireValue = kind.wireValue,
        iconSymbolName = kind.defaultIcon,
        iconColorHex = kind.defaultColorHex,
        currencyCode = "JPY",
        openingBalanceMinor = openingBalanceMinor,
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

    private fun transaction(
        id: String,
        kind: TransactionPrimaryKind,
        amount: Long,
        sourceWalletId: String = SOURCE_WALLET_ID,
        destinationWalletId: String? = null,
        destinationAmount: Long? = null,
    ) = LedgerTransactionRecord(
        id = id,
        ownerUserId = OWNER,
        primaryKindWireValue = kind.wireValue,
        transferSubtypeWireValue = if (kind == TransactionPrimaryKind.TRANSFER) {
            TransactionTransferSubtype.INTERNAL_TRANSFER.wireValue
        } else null,
        debtIntentWireValue = null,
        entryStatusWireValue = TransactionEntryStatus.POSTED.wireValue,
        title = "Record",
        note = null,
        amountMinor = amount,
        sourceCurrencyCode = "JPY",
        destinationCurrencyCode = destinationWalletId?.let { "JPY" },
        destinationAmountMinor = destinationAmount,
        reportingCurrencyCode = null,
        reportingAmountMinor = null,
        conversionModeWireValue = null,
        exchangeRateDecimalString = null,
        exchangeRateProvider = null,
        exchangeRateDate = null,
        occurredAt = if (id == TRANSACTION_ID) "2030-01-01T00:00:00Z" else "2020-01-01T00:00:00Z",
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
        sourceWalletId = sourceWalletId,
        destinationWalletId = destinationWalletId,
        categoryId = null,
        deletedAt = null,
        isArchived = false,
        archivedAt = null,
        syncVersion = 0,
        lastModifiedByDeviceId = DEVICE,
    )

    private fun debtLend(id: String, amount: Long) =
        transaction(id, TransactionPrimaryKind.TRANSFER, amount).copy(
            transferSubtypeWireValue = TransactionTransferSubtype.DEBT.wireValue,
            debtIntentWireValue = TransactionDebtIntent.LEND.wireValue,
            destinationWalletId = null,
            destinationCurrencyCode = null,
        )

    private fun creditCardProfile(limit: Long) = CreditCardProfileRecord(
        id = PROFILE_ID,
        ownerUserId = OWNER,
        issuerName = "Issuer",
        networkWireValue = CreditCardNetwork.VISA.wireValue,
        last4 = "1234",
        creditLimitMinor = limit,
        statementClosingDay = 10,
        paymentDueDay = 26,
        notes = null,
        walletId = SOURCE_WALLET_ID,
        paymentSourceWalletId = null,
        autoPayEnabled = true,
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
        const val PROFILE_ID = "55555555-5555-5555-5555-555555555555"
        const val DEVICE = "66666666-6666-6666-6666-666666666666"
        const val NOW = "2026-09-23T12:00:00Z"
    }
}
