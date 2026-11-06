package vn.com.quyln.mistia.core.model

import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class PlanningCreditCardAccountsTest {
    private val owner = UserId("11111111-1111-1111-1111-111111111111")
    private val other = "99999999-9999-9999-9999-999999999999"
    private val birth = "2026-10-01T00:00:00Z"
    private val later = "2026-10-02T00:00:00Z"
    private val device = "22222222-2222-2222-2222-222222222222"
    private fun id(n: Int) = java.util.UUID(0, n.toLong()).toString()
    private val cash = LedgerWalletRecord.fromCloudRecord(WalletDraft(id = id(1), name = "Linked cash", kind = WalletKind.CASH,
        currencyCode = "JPY", openingBalanceMinor = 1000).toMutation(owner, null, device, birth).record)
    private val saved = CreditCardDraft(walletId = id(2), profileId = id(3), name = "Card", issuerName = "Issuer",
        last4 = "1234", creditLimitMinor = 1000, paymentSourceWalletId = cash.id)
        .toMutation(owner, null, null, cash, device, birth)
    private val card = saved.wallet.record
    private val profile = saved.profile.record
    private val charge = TransactionDraft(id = id(4), primaryKind = TransactionPrimaryKind.TRANSFER,
        transferSubtype = TransactionTransferSubtype.DEBT, debtIntent = TransactionDebtIntent.LEND,
        title = "Card lending", amountMinor = 70, occurredAt = birth, sourceWalletId = card.id, counterpartyName = "A")
        .toMutation(owner, null, card, null, null, device, birth).record
    private fun snapshot(wallets: List<LedgerWalletRecord> = listOf(cash, card),
        profiles: List<CreditCardProfileRecord> = listOf(profile), transactions: List<LedgerTransactionRecord> = listOf(charge)) =
        CreditCardAccountReadSnapshot(owner, wallets.map { it.toCloudRecord() } + profiles.map { it.toCloudRecord() } +
            transactions.map { it.toCloudRecord() })
    private fun rows(s: CreditCardAccountReadSnapshot = snapshot()) = planningCreditCardAccounts(s)
    private fun changed(row: CloudRecord, key: String, value: JsonElement) =
        row.copy(payload = JsonObject(row.payload + (key to value)))
    private fun rejected(s: CreditCardAccountReadSnapshot) =
        assertThrows(IllegalArgumentException::class.java) { rows(s) }

    @Test fun ownedAccountShowsCurrentDebtAvailableCreditAndOwnedSource() {
        val row = rows().single()
        assertEquals(card, row.wallet); assertEquals(profile, row.profile)
        assertEquals(70L, row.currentDebtMinor); assertEquals(930L, row.availableCreditMinor)
        assertEquals("Linked cash", row.paymentSourceWalletName)
        assertEquals(CreditCardNetwork.VISA, row.network); assertEquals("1234", row.last4)
    }

    @Test fun actualPaymentUsesDestinationAmountAndReducesCurrentDebt() {
        val payment = TransactionDraft(id = id(5), primaryKind = TransactionPrimaryKind.TRANSFER,
            transferSubtype = TransactionTransferSubtype.INTERNAL_TRANSFER, title = "Payment", amountMinor = 30,
            occurredAt = later, sourceWalletId = cash.id, destinationWalletId = card.id)
            .toMutation(owner, null, cash, card, null, device, later).record.copy(destinationAmountMinor = 20)
        val row = rows(snapshot(transactions = listOf(charge, payment))).single()
        assertEquals(50L, row.currentDebtMinor); assertEquals(950L, row.availableCreditMinor)
    }

    @Test fun overpaymentDoesNotMakeDebtNegativeOrIncreaseCreditBeyondLimit() {
        val income = charge.copy(primaryKindWireValue = "income", transferSubtypeWireValue = null,
            debtIntentWireValue = null, amountMinor = 170)
        val row = rows(snapshot(transactions = listOf(income))).single()
        assertEquals(0L, row.currentDebtMinor); assertEquals(1000L, row.availableCreditMinor)
    }

    @Test fun exactLongAboveDoubleRangeRemainsInAccountMinorUnits() {
        val amount = 9007199254740993L
        val row = rows(snapshot(profiles = listOf(profile.copy(creditLimitMinor = Long.MAX_VALUE)),
            transactions = listOf(charge.copy(amountMinor = amount)))).single()
        assertEquals(amount, row.currentDebtMinor)
        assertEquals(Long.MAX_VALUE - amount, row.availableCreditMinor)
        assertEquals("JPY", row.wallet.currencyCode)
    }

    @Test fun creditCardOpeningBalanceDoesNotReplacePostedDebt() {
        val row = rows(snapshot(wallets = listOf(cash, card.copy(openingBalanceMinor = 9000)))).single()
        assertEquals(70L, row.currentDebtMinor); assertEquals(930L, row.availableCreditMinor)
    }

    @Test fun draftArchivedAndDeletedMoneyDoNotAffectCurrentDebt() {
        val ignored = listOf(charge.copy(id = id(6), entryStatusWireValue = TransactionEntryStatus.DRAFT.wireValue),
            charge.copy(id = id(7), isArchived = true, archivedAt = later),
            charge.copy(id = id(8), deletedAt = later, updatedAt = later))
        assertEquals(70L, rows(snapshot(transactions = listOf(charge) + ignored)).single().currentDebtMinor)
    }

    @Test fun archivedAndDeletedCardsAreAbsentDespiteRetainedProfileAndMoney() {
        for (w in listOf(card.copy(isArchived = true, archivedAt = later), card.copy(deletedAt = later, updatedAt = later)))
            assertTrue(rows(snapshot(wallets = listOf(cash, w))).isEmpty())
    }

    @Test fun deletedProfileAndOrphanProfileDoNotInventAccounts() {
        assertTrue(rows(snapshot(profiles = listOf(profile.copy(deletedAt = later, updatedAt = later)))).isEmpty())
        assertTrue(rows(snapshot(profiles = listOf(profile.copy(walletId = id(88))))).isEmpty())
        assertTrue(rows(snapshot(wallets = listOf(cash))).isEmpty())
    }

    @Test fun missingDeletedSystemAndNonordinaryLinkedSourceHaveNoName() {
        assertNull(rows(snapshot(wallets = listOf(card))).single().paymentSourceWalletName)
        for (w in listOf(cash.copy(deletedAt = later, updatedAt = later), cash.copy(systemPurposeRawValue = "investmentProfit"),
            cash.copy(kindWireValue = "creditCard"), cash.copy(kindWireValue = "investment")))
            assertNull(rows(snapshot(wallets = listOf(w, card))).single().paymentSourceWalletName)
        assertNull(rows(snapshot(profiles = listOf(profile.copy(paymentSourceWalletId = id(88))))).single().paymentSourceWalletName)
    }

    @Test fun retainedArchivedOwnedSourceMayStillNameTheLink() {
        assertEquals("Linked cash", rows(snapshot(wallets = listOf(cash.copy(isArchived = true, archivedAt = later), card)))
            .single().paymentSourceWalletName)
    }

    @Test fun foreignEnvelopeRowsCannotInfluenceTheAccount() {
        val s = snapshot()
        for (row in s.rows) rejected(s.copy(rows = s.rows.filterNot { it === row } + row.copy(ownerUserId = other)))
    }

    @Test fun foreignBodyOwnerAndMismatchedBodyIdentityAreRejected() {
        val s = snapshot(); val row = s.rows.first()
        for ((key, value) in listOf("user_id" to JsonPrimitive(other), "id" to JsonPrimitive(id(88))))
            rejected(s.copy(rows = s.rows.drop(1) + changed(row, key, value)))
    }

    @Test fun numericVersionMustMatchItsEnvelopeAndStayNumeric() {
        val s = snapshot(); val row = s.rows.first()
        rejected(s.copy(rows = s.rows.drop(1) + row.copy(syncVersion = 99)))
        rejected(s.copy(rows = s.rows.drop(1) + changed(row, "sync_version", JsonPrimitive("0"))))
    }

    @Test fun deletionAndAuditEnvelopeCannotDisagreeWithBody() {
        val s = snapshot(); val row = s.rows.first()
        rejected(s.copy(rows = s.rows.drop(1) + row.copy(deletedAt = later)))
        rejected(s.copy(rows = s.rows.drop(1) + row.copy(updatedAt = later)))
    }

    @Test fun moneyStringsAndFractionalValuesCannotBecomeSuccessfulBalances() {
        val s = snapshot()
        for ((row, key) in listOf(profile.toCloudRecord() to "credit_limit_minor", charge.toCloudRecord() to "amount_minor"))
            for (value in listOf(JsonPrimitive("70"), JsonPrimitive(70.5)))
                rejected(s.copy(rows = s.rows.filterNot { it.entity == row.entity && it.id == row.id } + changed(row, key, value)))
    }

    @Test fun negativeChargeOrPaymentAmountsCannotArtificiallyIncreaseAvailableCredit() {
        val payment = TransactionDraft(id = id(5), primaryKind = TransactionPrimaryKind.TRANSFER,
            transferSubtype = TransactionTransferSubtype.INTERNAL_TRANSFER, title = "Payment", amountMinor = 30,
            occurredAt = later, sourceWalletId = cash.id, destinationWalletId = card.id)
            .toMutation(owner, null, cash, card, null, device, later).record.copy(destinationAmountMinor = 20)
        rejected(snapshot(transactions = listOf(charge.copy(amountMinor = -70))))
        rejected(snapshot(transactions = listOf(charge, payment.copy(destinationAmountMinor = -20))))
    }

    @Test fun duplicateRawIdentityAndAmbiguousLiveProfileLinkAreRejected() {
        val s = snapshot(); rejected(s.copy(rows = s.rows + s.rows.first()))
        rejected(snapshot(profiles = listOf(profile, profile.copy(id = id(9)))))
    }

    @Test fun unknownNetworkUsesOtherWithoutExposingAnUnmaskedCardNumber() {
        val row = rows(snapshot(profiles = listOf(profile.copy(networkWireValue = "future-network", last4 = "4111111111111234")))).single()
        assertEquals(CreditCardNetwork.OTHER, row.network); assertEquals("1234", row.last4)
    }

    @Test fun invalidLastDigitsNeverRenderArbitraryText() {
        for (value in listOf("123\n", "ABCD", "<x>"))
            assertEquals("", rows(snapshot(profiles = listOf(profile.copy(last4 = value)))).single().last4)
    }

    @Test fun orderingUsesPersistedSortOrderThenStableIdentity() {
        val second = card.copy(id = id(10), name = "Second", sortOrder = card.sortOrder - 1)
        val p = profile.copy(id = id(11), walletId = second.id)
        val row = rows(snapshot(wallets = listOf(card, cash, second), profiles = listOf(profile, p)))
        assertEquals(listOf(second.id, card.id), row.map { it.wallet.id })
    }

    @Test fun unknownCurrencyAndNegativeLimitFailExplicitly() {
        rejected(snapshot(wallets = listOf(cash, card.copy(currencyCode = "ZZZ"))))
        rejected(snapshot(profiles = listOf(profile.copy(creditLimitMinor = -1))))
    }

    @Test fun unknownActiveLedgerStatusCannotSilentlyProduceZeroDebt() {
        rejected(snapshot(transactions = listOf(charge.copy(entryStatusWireValue = "future-status"))))
    }

    @Test fun unsupportedEntityIsNotACompleteCardRead() {
        val s = snapshot(); rejected(s.copy(rows = s.rows + s.rows.first().copy(entity = CloudEntity.BUDGET_PLAN.table)))
    }

    @Test fun genuinelyEmptyOwnedSnapshotHasAnEmptyAccountList() {
        assertTrue(rows(CreditCardAccountReadSnapshot(owner, emptyList())).isEmpty())
    }
}
