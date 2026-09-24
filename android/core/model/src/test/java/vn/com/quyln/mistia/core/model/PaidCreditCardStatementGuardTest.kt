package vn.com.quyln.mistia.core.model

import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PaidCreditCardStatementGuardTest {
    @Test
    fun `card expense is locked when a post-closing payment covers its statement month`() {
        val expense = transaction(
            id = EXPENSE_ID,
            kind = TransactionPrimaryKind.EXPENSE,
            amountMinor = 7_000,
            occurredAt = "2026-02-12T03:00:00Z",
            sourceWalletId = CARD_ID,
        )
        val payment = transaction(
            id = PAYMENT_ID,
            kind = TransactionPrimaryKind.TRANSFER,
            transferSubtype = TransactionTransferSubtype.INTERNAL_TRANSFER,
            amountMinor = 7_000,
            occurredAt = "2026-02-26T03:00:00Z",
            sourceWalletId = CASH_ID,
            destinationWalletId = CARD_ID,
            title = "Transfer",
        )

        assertTrue(
            expense.isLockedByPaidCreditCardStatement(
                wallets = listOf(cardWallet()),
                creditCardProfiles = listOf(cardProfile()),
                transactions = listOf(expense, payment),
                dueOccurrences = emptyList(),
            )
        )
    }

    @Test
    fun `card expense stays editable when payment does not cover statement total`() {
        val expense = transaction(
            id = EXPENSE_ID,
            kind = TransactionPrimaryKind.EXPENSE,
            amountMinor = 7_000,
            occurredAt = "2026-02-12T03:00:00Z",
            sourceWalletId = CARD_ID,
        )
        val payment = transaction(
            id = PAYMENT_ID,
            kind = TransactionPrimaryKind.TRANSFER,
            transferSubtype = TransactionTransferSubtype.INTERNAL_TRANSFER,
            amountMinor = 6_999,
            occurredAt = "2026-02-26T03:00:00Z",
            sourceWalletId = CASH_ID,
            destinationWalletId = CARD_ID,
            title = "Transfer",
        )

        assertFalse(
            expense.isLockedByPaidCreditCardStatement(
                wallets = listOf(cardWallet()),
                creditCardProfiles = listOf(cardProfile()),
                transactions = listOf(expense, payment),
                dueOccurrences = emptyList(),
            )
        )
    }

    @Test
    fun `paid credit card occurrence locks its linked payment transaction`() {
        val payment = transaction(
            id = PAYMENT_ID,
            kind = TransactionPrimaryKind.TRANSFER,
            transferSubtype = TransactionTransferSubtype.INTERNAL_TRANSFER,
            amountMinor = 7_000,
            occurredAt = "2026-02-26T03:00:00Z",
            sourceWalletId = CASH_ID,
            destinationWalletId = CARD_ID,
        )

        assertTrue(
            payment.isLockedByPaidCreditCardStatement(
                wallets = listOf(cardWallet()),
                creditCardProfiles = listOf(cardProfile()),
                transactions = listOf(payment),
                dueOccurrences = listOf(paidOccurrence(PAYMENT_ID)),
            )
        )
    }

    @Test
    fun `occurrence from another account cannot lock transaction`() {
        val payment = transaction(
            id = PAYMENT_ID,
            kind = TransactionPrimaryKind.TRANSFER,
            transferSubtype = TransactionTransferSubtype.INTERNAL_TRANSFER,
            amountMinor = 7_000,
            occurredAt = "2026-02-26T03:00:00Z",
            sourceWalletId = CASH_ID,
            destinationWalletId = CARD_ID,
            title = "Transfer",
        )

        assertFalse(
            payment.isLockedByPaidCreditCardStatement(
                wallets = listOf(cardWallet()),
                creditCardProfiles = listOf(cardProfile()),
                transactions = listOf(payment),
                dueOccurrences = listOf(paidOccurrence(PAYMENT_ID, owner = OTHER_OWNER)),
            )
        )
    }

    @Test
    fun `balance adjustment does not inflate paid statement charges`() {
        val expense = transaction(
            id = EXPENSE_ID,
            kind = TransactionPrimaryKind.EXPENSE,
            amountMinor = 7_000,
            occurredAt = "2026-02-12T03:00:00Z",
            sourceWalletId = CARD_ID,
        )
        val adjustment = transaction(
            id = ADJUSTMENT_ID,
            kind = TransactionPrimaryKind.EXPENSE,
            amountMinor = 1_000,
            occurredAt = "2026-02-13T03:00:00Z",
            sourceWalletId = CARD_ID,
            categoryId = TransactionCategoryRecord.BALANCE_ADJUSTMENT_EXPENSE_ID,
        )
        val payment = transaction(
            id = PAYMENT_ID,
            kind = TransactionPrimaryKind.TRANSFER,
            transferSubtype = TransactionTransferSubtype.INTERNAL_TRANSFER,
            amountMinor = 7_000,
            occurredAt = "2026-02-26T03:00:00Z",
            sourceWalletId = CASH_ID,
            destinationWalletId = CARD_ID,
            title = "Transfer",
        )

        assertTrue(
            expense.isLockedByPaidCreditCardStatement(
                wallets = listOf(cardWallet()),
                creditCardProfiles = listOf(cardProfile()),
                categories = listOf(balanceAdjustmentCategory()),
                transactions = listOf(expense, adjustment, payment),
                dueOccurrences = emptyList(),
            )
        )
    }

    @Test
    fun `credit card debt lending contributes to statement total`() {
        val expense = transaction(
            id = EXPENSE_ID,
            kind = TransactionPrimaryKind.EXPENSE,
            amountMinor = 6_000,
            occurredAt = "2026-02-12T03:00:00Z",
            sourceWalletId = CARD_ID,
        )
        val lending = transaction(
            id = LENDING_ID,
            kind = TransactionPrimaryKind.TRANSFER,
            transferSubtype = TransactionTransferSubtype.DEBT,
            debtIntent = TransactionDebtIntent.LEND,
            amountMinor = 1_000,
            occurredAt = "2026-02-13T03:00:00Z",
            sourceWalletId = CARD_ID,
        )
        val payment = transaction(
            id = PAYMENT_ID,
            kind = TransactionPrimaryKind.TRANSFER,
            transferSubtype = TransactionTransferSubtype.INTERNAL_TRANSFER,
            amountMinor = 6_500,
            occurredAt = "2026-02-26T03:00:00Z",
            sourceWalletId = CASH_ID,
            destinationWalletId = CARD_ID,
            title = "Transfer",
        )

        assertFalse(
            expense.isLockedByPaidCreditCardStatement(
                wallets = listOf(cardWallet()),
                creditCardProfiles = listOf(cardProfile()),
                transactions = listOf(expense, lending, payment),
                dueOccurrences = emptyList(),
            )
        )

        val coveringPayment = payment.copy(amountMinor = 7_000)
        assertTrue(
            lending.isLockedByPaidCreditCardStatement(
                wallets = listOf(cardWallet()),
                creditCardProfiles = listOf(cardProfile()),
                transactions = listOf(expense, lending, coveringPayment),
                dueOccurrences = emptyList(),
            )
        )
    }

    private fun transaction(
        id: String,
        kind: TransactionPrimaryKind,
        amountMinor: Long,
        occurredAt: String,
        sourceWalletId: String?,
        destinationWalletId: String? = null,
        transferSubtype: TransactionTransferSubtype? = null,
        debtIntent: TransactionDebtIntent? = null,
        categoryId: String? = null,
        title: String = if (kind == TransactionPrimaryKind.TRANSFER) "Card payment" else "Lunch",
    ) = LedgerTransactionRecord(
        id = id,
        ownerUserId = OWNER,
        primaryKindWireValue = kind.wireValue,
        transferSubtypeWireValue = transferSubtype?.wireValue,
        debtIntentWireValue = debtIntent?.wireValue,
        entryStatusWireValue = TransactionEntryStatus.POSTED.wireValue,
        title = title,
        note = null,
        amountMinor = amountMinor,
        sourceCurrencyCode = "JPY",
        destinationCurrencyCode = if (destinationWalletId == null) null else "JPY",
        destinationAmountMinor = null,
        reportingCurrencyCode = null,
        reportingAmountMinor = null,
        conversionModeWireValue = null,
        exchangeRateDecimalString = null,
        exchangeRateProvider = null,
        exchangeRateDate = null,
        occurredAt = occurredAt,
        createdAt = occurredAt,
        updatedAt = occurredAt,
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
        categoryId = categoryId,
        deletedAt = null,
        isArchived = false,
        archivedAt = null,
        syncVersion = 0,
        lastModifiedByDeviceId = DEVICE,
    )

    private fun cardWallet() = LedgerWalletRecord(
        id = CARD_ID,
        ownerUserId = OWNER,
        name = "Card",
        kindWireValue = WalletKind.CREDIT_CARD.wireValue,
        iconSymbolName = WalletKind.CREDIT_CARD.defaultIcon,
        iconColorHex = WalletKind.CREDIT_CARD.defaultColorHex,
        currencyCode = "JPY",
        openingBalanceMinor = 0,
        institutionDisplayName = null,
        institutionPresetKey = null,
        sortOrder = 0,
        isArchived = false,
        archivedAt = null,
        createdAt = "2026-01-01T00:00:00Z",
        updatedAt = "2026-01-01T00:00:00Z",
        deletedAt = null,
        syncVersion = 0,
        lastModifiedByDeviceId = DEVICE,
        systemPurposeRawValue = null,
        investmentLinkedWalletId = null,
    )

    private fun cardProfile() = CreditCardProfileRecord(
        id = PROFILE_ID,
        ownerUserId = OWNER,
        issuerName = "Issuer",
        networkWireValue = CreditCardNetwork.VISA.wireValue,
        last4 = "1234",
        creditLimitMinor = 100_000,
        statementClosingDay = 10,
        paymentDueDay = 26,
        notes = null,
        walletId = CARD_ID,
        paymentSourceWalletId = CASH_ID,
        autoPayEnabled = true,
        createdAt = "2026-01-01T00:00:00Z",
        updatedAt = "2026-01-01T00:00:00Z",
        deletedAt = null,
        syncVersion = 0,
        lastModifiedByDeviceId = DEVICE,
    )

    private fun balanceAdjustmentCategory() = TransactionCategoryRecord(
        id = TransactionCategoryRecord.BALANCE_ADJUSTMENT_EXPENSE_ID,
        ownerUserId = OWNER,
        name = "Balance adjustment",
        nameEnglish = "Balance adjustment",
        nameJapanese = null,
        kindWireValue = TransactionCategoryKind.EXPENSE.wireValue,
        iconSymbolName = "plusminus",
        iconColorHex = "#888888",
        isFavorite = false,
        familyBudgetSpendingEnabled = false,
        parentCategoryId = null,
        hierarchyRoleWireValue = CategoryHierarchyRole.CHILD.wireValue,
        systemKey = TransactionCategoryRecord.BALANCE_ADJUSTMENT_EXPENSE_KEY,
        isSystem = true,
        sortOrder = 0,
        isArchived = false,
        archivedAt = null,
        createdAt = "2026-01-01T00:00:00Z",
        updatedAt = "2026-01-01T00:00:00Z",
        deletedAt = null,
        syncVersion = 0,
        lastModifiedByDeviceId = DEVICE,
    )

    private fun paidOccurrence(linkedTransactionId: String, owner: String = OWNER) = CloudRecord(
        entity = CloudEntity.DUE_OCCURRENCE_RECORD.table,
        id = OCCURRENCE_ID,
        ownerUserId = owner,
        payload = JsonObject(
            mapOf(
                "user_id" to JsonPrimitive(owner),
                "id" to JsonPrimitive(OCCURRENCE_ID),
                "source_kind_raw_value" to JsonPrimitive("creditCard"),
                "source_id" to JsonPrimitive(CARD_ID),
                "selected_month_key" to JsonPrimitive("2026-02"),
                "scheduled_date" to JsonPrimitive("2026-02-26T00:00:00Z"),
                "amount_minor_snapshot" to JsonPrimitive(7_000),
                "status_raw_value" to JsonPrimitive("paid"),
                "paid_at" to JsonPrimitive("2026-02-26T03:00:00Z"),
                "linked_transaction_id" to JsonPrimitive(linkedTransactionId),
                "created_at" to JsonPrimitive("2026-02-26T03:00:00Z"),
                "updated_at" to JsonPrimitive("2026-02-26T03:00:00Z"),
                "deleted_at" to JsonNull,
                "sync_version" to JsonPrimitive(1),
                "last_modified_by_device_id" to JsonPrimitive(DEVICE),
            )
        ),
        updatedAt = "2026-02-26T03:00:00Z",
        deletedAt = null,
        syncVersion = 1,
    )

    private companion object {
        const val OWNER = "11111111-1111-1111-1111-111111111111"
        const val OTHER_OWNER = "99999999-9999-9999-9999-999999999999"
        const val CARD_ID = "22222222-2222-2222-2222-222222222222"
        const val CASH_ID = "33333333-3333-3333-3333-333333333333"
        const val EXPENSE_ID = "44444444-4444-4444-4444-444444444444"
        const val ADJUSTMENT_ID = "45454545-4545-4545-4545-454545454545"
        const val LENDING_ID = "46464646-4646-4646-4646-464646464646"
        const val PAYMENT_ID = "55555555-5555-5555-5555-555555555555"
        const val PROFILE_ID = "66666666-6666-6666-6666-666666666666"
        const val OCCURRENCE_ID = "77777777-7777-7777-7777-777777777777"
        const val DEVICE = "88888888-8888-8888-8888-888888888888"
    }
}
