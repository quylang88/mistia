package vn.com.quyln.mistia.core.database

import java.time.YearMonth
import java.time.ZoneId
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test
import vn.com.quyln.mistia.core.model.*

class BillPaymentRepositoryTest {
    private val owner = UserId("11111111-1111-1111-1111-111111111111")
    private val other = UserId("99999999-9999-9999-9999-999999999999")
    private val device = "22222222-2222-2222-2222-222222222222"
    private val now = "2026-10-13T00:00:00Z"
    private val month = YearMonth.of(2026, 10)
    private val zone = ZoneId.of("Asia/Tokyo")
    private val store = BudgetMemoryStore()
    private val catalog = SystemCategoryCatalog.parse("""[
      {"id":"parent_expense_home_bills","kind":"expense","active":true,"icon":"mistia.category.parent.expense.home_bills","fallbackIcon":"house.fill","color":"#FF8A4C","translations":{"vi":"Nhà","en":"Home","ja":"住まい"},"aliases":[],"children":[
        {"id":"internet","active":true,"icon":"mistia.category.expense.home_bills.internet","fallbackIcon":"wifi","color":"#5B7BFF","translations":{"vi":"Internet","en":"Internet","ja":"インターネット"},"aliases":[]}
      ]},
      {"id":"parent_expense_living","kind":"expense","active":false,"icon":"mistia.category.parent.expense.living","fallbackIcon":"house.fill","color":"#FF8A4C","translations":{"vi":"Sinh hoạt","en":"Living","ja":"生活"},"aliases":[],"children":[
        {"id":"billing","active":false,"icon":"mistia.category.legacy.billing","fallbackIcon":"doc.text.fill","color":"#FF9F1C","translations":{"vi":"Hóa đơn","en":"Bills","ja":"請求"},"aliases":[]}
      ]}
    ]""")
    private val repo = OfflineFirstFinanceRepository(store, zone, catalog)
    private suspend fun prepare(amount: Long? = 5000, balance: Long = 10000): RecurringBillPlanRecord {
        repo.ensureDefaultSystemCategories(owner, catalog, device, now).getOrThrow()
        val category = repo.observeCategories(owner).first().single { it.systemKey == "internet" }
        val wallet = repo.saveWallet(owner, WalletDraft(name="Cash", kind=WalletKind.CASH,
            currencyCode="JPY", openingBalanceMinor=balance), device, now).getOrThrow()
        return repo.saveRecurringBill(owner, RecurringBillDraft("Internet", category.id, amount,
            wallet.id, "JPY", paymentStartDay=10, zoneId=zone), device, now).getOrThrow()
    }
    private fun request(bill: RecurringBillPlanRecord) = BillPaymentRequest(RecordId(bill.id), month)
    private fun reason(result: Result<*>) = (result.exceptionOrNull() as? BillPaymentException)?.reason

    @Test fun `payment atomically creates posted expense and linked paid cycle with exact amounts`() = runTest {
        val exact = 9007199254740993L
        val bill = prepare(exact, exact)
        val batchesBefore = store.batches.size
        val paid = repo.payRecurringBill(owner, request(bill), device, now).getOrThrow()
        assertEquals(batchesBefore+1, store.batches.size)
        assertEquals(2, store.batches.last().size)
        assertEquals(exact, paid.transaction.amountMinor)
        assertEquals("JPY", paid.transaction.sourceCurrencyCode)
        assertNull(paid.transaction.reportingExpenseMinor)
        assertEquals(owner.value, paid.transaction.createdByUserId)
        assertEquals(bill.paymentWalletId, paid.transaction.sourceWalletId)
        assertEquals(bill.categoryId, paid.transaction.categoryId)
        assertEquals(TransactionEntryStatus.POSTED, paid.transaction.entryStatus)
        val occurrence = paid.occurrences.single()
        assertEquals(DueStatus.PAID, occurrence.status)
        assertEquals(exact, occurrence.amountMinorSnapshot)
        assertEquals(paid.transaction.id, occurrence.linkedTransactionId)
        assertEquals(now, occurrence.paidAt)
        assertEquals(0L, TransactionWalletBalanceIndex(repo.observeWallets(owner).first(), repo.observeTransactions(owner).first()).balance(bill.paymentWalletId!!))
    }
    @Test fun `nil bill amount requires positive override and preserves original bill`() = runTest {
        val bill = prepare(null)
        assertEquals(BillPaymentError.MISSING_AMOUNT, reason(repo.payRecurringBill(owner, request(bill), device, now)))
        val paid = repo.payRecurringBill(owner, request(bill).copy(amountMinorOverride=6000), device, now).getOrThrow()
        assertEquals(6000L, paid.transaction.amountMinor)
        assertNull(repo.observeRecurringBills(owner).first().single().amountMinor)
    }
    @Test fun `mismatched wallet is rejected before any money or occurrence writes`() = runTest {
        val bill = prepare()
        val foreignCurrency = repo.saveWallet(owner, WalletDraft(name="VND", kind=WalletKind.CASH,
            currencyCode="VND", openingBalanceMinor=1000000), device, now).getOrThrow()
        val count = store.batches.size
        assertEquals(BillPaymentError.WALLET_CURRENCY_MISMATCH, reason(repo.payRecurringBill(owner,
            request(bill).copy(walletId=RecordId(foreignCurrency.id)), device, now)))
        assertEquals(count, store.batches.size)
        assertTrue(repo.observeTransactions(owner).first().isEmpty())
        assertTrue(repo.observeDueOccurrences(owner).first().isEmpty())
    }
    @Test fun `insufficient ordinary funds leaves cycle pending and outbox unchanged`() = runTest {
        val bill = prepare(balance=4999)
        val count = store.batches.size
        val result = repo.payRecurringBill(owner, request(bill), device, now)
        assertEquals(TransactionValidationError.INSUFFICIENT_WALLET_BALANCE,
            (result.exceptionOrNull() as? TransactionValidationException)?.reason)
        assertEquals(count, store.batches.size)
        assertTrue(repo.observeDueOccurrences(owner).first().isEmpty())
    }
    @Test fun `paid and skipped cycles cannot create a second ledger transaction`() = runTest {
        val bill = prepare()
        repo.payRecurringBill(owner, request(bill), device, now).getOrThrow()
        assertEquals(BillPaymentError.CYCLE_NOT_PENDING, reason(repo.payRecurringBill(owner, request(bill), device, now)))
        assertEquals(1, repo.observeTransactions(owner).first().size)
        val next = month.plusMonths(1)
        repo.skipRecurringBill(owner, RecordId(bill.id), next, device, now).getOrThrow()
        assertEquals(BillPaymentError.CYCLE_NOT_PENDING,
            reason(repo.payRecurringBill(owner, request(bill).copy(month=next), device, now)))
    }
    @Test fun `foreign owner paused and unscheduled cycles cannot be paid`() = runTest {
        val bill = prepare()
        assertEquals(BillPaymentError.NOT_FOUND, reason(repo.payRecurringBill(other, request(bill), device, now)))
        assertEquals(BillPaymentError.NOT_SCHEDULED,
            reason(repo.payRecurringBill(owner, request(bill).copy(month=month.minusMonths(1)), device, now)))
        repo.pauseRecurringBill(owner, RecordId(bill.id), device, now).getOrThrow()
        assertEquals(BillPaymentError.NOT_SCHEDULED, reason(repo.payRecurringBill(owner, request(bill), device, now)))
        assertTrue(repo.observeTransactions(owner).first().isEmpty())
    }
    @Test fun `undo tombstones ledger and every paid duplicate atomically retaining large versions`() = runTest {
        val bill = prepare()
        val paid = repo.payRecurringBill(owner, request(bill), device, now).getOrThrow()
        val tx = paid.transaction.copy(syncVersion=9007199254740993L)
        store.commitMutation(tx.toCloudRecord(), PendingMutation(CloudEntity.LEDGER_TRANSACTION, tx.id, owner.value,
            MutationKind.UPSERT, tx.toPayload(), now, tx.syncVersion, device))
        val duplicate = paid.occurrences.single().copy(id="44444444-4444-4444-4444-444444444444", syncVersion=9007199254740995L)
        store.commitMutation(duplicate.toCloudRecord(), duplicate.pendingMutation())
        repo.undoRecurringBillPayment(owner, RecordId(bill.id), month, device, "2026-10-14T00:00:00Z").getOrThrow()
        assertEquals(3, store.batches.last().size)
        assertTrue(repo.observeTransactions(owner).first().isEmpty())
        assertTrue(repo.observeDueOccurrences(owner).first().isEmpty())
        val outbox = store.outboxRows(owner.value).filter { it.entity in setOf(CloudEntity.LEDGER_TRANSACTION, CloudEntity.DUE_OCCURRENCE_RECORD) }
        assertEquals(3, outbox.size)
        assertTrue(outbox.all { it.kind==MutationKind.DELETE })
        assertEquals(tx.syncVersion, outbox.single { it.recordId==tx.id }.baseVersion)
        assertEquals(duplicate.syncVersion, outbox.single { it.recordId==duplicate.id }.baseVersion)
    }
    @Test fun `wallet currency race is rejected by atomic dependency check`() = runTest {
        val bill = prepare()
        val racing = object : LocalStore by store {
            override suspend fun commitBillMoneyMutations(snapshot: BillMoneySnapshot, mutations: List<Pair<CloudRecord, PendingMutation>>) {
                val wallet = LedgerWalletRecord.fromCloudRecord(store.record(owner, CloudEntity.LEDGER_WALLET.table, bill.paymentWalletId!!)!!)
                    .copy(currencyCode="VND")
                store.commitMutation(wallet.toCloudRecord(), PendingMutation(CloudEntity.LEDGER_WALLET, wallet.id, owner.value, MutationKind.UPSERT, wallet.toPayload(), now, wallet.syncVersion, device))
                store.commitBillMoneyMutations(snapshot, mutations)
            }
        }
        val result = OfflineFirstFinanceRepository(racing, zone, catalog).payRecurringBill(owner, request(bill), device, now)
        assertTrue(result.isFailure)
        assertTrue(repo.observeTransactions(owner).first().isEmpty())
        assertTrue(repo.observeDueOccurrences(owner).first().isEmpty())
    }
    @Test fun `concurrent ledger insertion cannot overwrite the captured money snapshot`() = runTest {
        val bill = prepare()
        val racing = object : LocalStore by store {
            override suspend fun commitBillMoneyMutations(snapshot: BillMoneySnapshot, mutations: List<Pair<CloudRecord, PendingMutation>>) {
                store.commitMutation(mutations.first().first, mutations.first().second)
                store.commitBillMoneyMutations(snapshot, mutations)
            }
        }
        assertTrue(OfflineFirstFinanceRepository(racing, zone, catalog).payRecurringBill(owner, request(bill), device, now).isFailure)
        assertEquals(1, repo.observeTransactions(owner).first().size)
        assertTrue(repo.observeDueOccurrences(owner).first().isEmpty())
    }
    @Test fun `atomic storage failure creates neither ledger nor paid occurrence`() = runTest {
        val bill = prepare()
        val outbox = store.outboxRows(owner.value)
        store.failBatch = true
        assertTrue(repo.payRecurringBill(owner, request(bill), device, now).isFailure)
        assertEquals(outbox, store.outboxRows(owner.value))
        assertTrue(repo.observeTransactions(owner).first().isEmpty())
        assertTrue(repo.observeDueOccurrences(owner).first().isEmpty())
    }
    @Test fun `archived source wallet is not permitted for payment`() = runTest {
        val bill = prepare()
        repo.archiveWallet(owner, RecordId(bill.paymentWalletId!!), device, now).getOrThrow()
        assertEquals(BillPaymentError.INVALID_WALLET, reason(repo.payRecurringBill(owner, request(bill), device, now)))
    }
    @Test fun `viewer envelope cannot confer bill or wallet ownership`() = runTest {
        val bill = prepare()
        val row = bill.copy(ownerUserId=other.value).toCloudRecord().copy(ownerUserId=owner.value)
        store.commitMutation(row, bill.pendingMutation().copy(payload=row.payload))
        assertEquals(BillPaymentError.NOT_FOUND, reason(repo.payRecurringBill(owner, request(bill), device, now)))
        assertTrue(repo.observeTransactions(owner).first().isEmpty())
    }
    @Test fun `undo refuses shared transaction links without tombstoning money or occurrences`() = runTest {
        val bill = prepare()
        val paid = repo.payRecurringBill(owner, request(bill), device, now).getOrThrow()
        val shared = paid.transaction.copy(settlementGroupId="44444444-4444-4444-4444-444444444444")
        store.commitMutation(shared.toCloudRecord(), PendingMutation(CloudEntity.LEDGER_TRANSACTION, shared.id, owner.value,
            MutationKind.UPSERT, shared.toPayload(), now, shared.syncVersion, device))
        assertEquals(BillPaymentError.UNSUPPORTED_LINKED_STATE,
            reason(repo.undoRecurringBillPayment(owner, RecordId(bill.id), month, device, now)))
        assertEquals(listOf(shared), repo.observeTransactions(owner).first())
        assertEquals(paid.occurrences, repo.observeDueOccurrences(owner).first())
    }
    @Test fun `undo is idempotent after paid records were tombstoned`() = runTest {
        val bill = prepare()
        repo.payRecurringBill(owner, request(bill), device, now).getOrThrow()
        repo.undoRecurringBillPayment(owner, RecordId(bill.id), month, device, now).getOrThrow()
        val batches = store.batches.size
        repo.undoRecurringBillPayment(owner, RecordId(bill.id), month, device, now).getOrThrow()
        assertEquals(batches, store.batches.size)
    }

    @Test fun `credit card payment obeys available credit and undo restores debt`() = runTest {
        val bill = prepare()
        val card = repo.saveCreditCard(owner, CreditCardDraft(name="Card", creditLimitMinor=5000,
            paymentSourceWalletId=bill.paymentWalletId), device, now).getOrThrow()
        val request = request(bill).copy(walletId=RecordId(card.wallet.id))
        val paid = repo.payRecurringBill(owner, request, device, now).getOrThrow()
        assertEquals(5000L, TransactionWalletBalanceIndex(repo.observeWallets(owner).first(), repo.observeTransactions(owner).first()).balance(card.wallet.id))
        val result = repo.payRecurringBill(owner, request.copy(month=month.plusMonths(1)), device, now)
        assertEquals(TransactionValidationError.CREDIT_LIMIT_EXCEEDED,
            (result.exceptionOrNull() as? TransactionValidationException)?.reason)
        repo.undoRecurringBillPayment(owner, RecordId(bill.id), month, device, now).getOrThrow()
        assertEquals(0L, TransactionWalletBalanceIndex(repo.observeWallets(owner).first(), repo.observeTransactions(owner).first()).balance(card.wallet.id))
        assertEquals(paid.transaction.id, store.batches.last().first().first.id)
    }
    @Test fun `concurrent skip wins without being replaced by payment`() = runTest {
        val bill = prepare()
        val racing = object : LocalStore by store {
            override suspend fun commitBillMoneyMutations(snapshot: BillMoneySnapshot, mutations: List<Pair<CloudRecord, PendingMutation>>) {
                repo.skipRecurringBill(owner, RecordId(bill.id), month, device, now).getOrThrow()
                store.commitBillMoneyMutations(snapshot, mutations)
            }
        }
        assertTrue(OfflineFirstFinanceRepository(racing, zone, catalog).payRecurringBill(owner, request(bill), device, now).isFailure)
        assertTrue(repo.observeTransactions(owner).first().isEmpty())
        assertEquals(DueStatus.SKIPPED, repo.observeDueOccurrences(owner).first().single().status)
    }
    @Test fun `cancellation propagates without conversion into failure result`() = runTest {
        val bill = prepare()
        val cancelling = object : LocalStore by store {
            override suspend fun commitBillMoneyMutations(snapshot: BillMoneySnapshot, mutations: List<Pair<CloudRecord, PendingMutation>>) {
                throw kotlinx.coroutines.CancellationException("cancelled")
            }
        }
        try {
            OfflineFirstFinanceRepository(cancelling, zone, catalog).payRecurringBill(owner, request(bill), device, now)
            fail("Cancellation swallowed")
        } catch (_: kotlinx.coroutines.CancellationException) { }
        assertTrue(repo.observeTransactions(owner).first().isEmpty())
    }

    @Test fun `custom bill creates legacy billing fallback and parent in same money batch`() = runTest {
        val bill = prepare()
        val custom = repo.saveCategory(owner, CategoryDraft(name="Custom bill", kind=TransactionCategoryKind.EXPENSE,
            hierarchyRole=CategoryHierarchyRole.CHILD, parentCategoryId=repo.observeCategories(owner).first().single { it.hierarchyRole==CategoryHierarchyRole.PARENT }.id,
            iconSymbolName="custom.bill.icon"), device, now).getOrThrow()
        val customBill = bill.copy(categoryId=custom.id, iconSymbolName=custom.iconSymbolName)
        store.commitMutation(customBill.toCloudRecord(), customBill.pendingMutation())
        val paid = repo.payRecurringBill(owner, request(bill), device, now).getOrThrow()
        assertEquals(4, store.batches.last().size)
        val fallback = store.recordsIncludingDeleted(owner, CloudEntity.TRANSACTION_CATEGORY.table)
            .map(TransactionCategoryRecord::fromCloudRecord).single { it.systemKey=="billing" }
        assertTrue(fallback.isArchived)
        assertEquals(fallback.id, paid.transaction.categoryId)
        assertEquals(SystemCategoryIdentity.cloudId("parent_expense_living", owner), fallback.parentCategoryId)
        assertEquals(custom.id, repo.observeRecurringBills(owner).first().single().categoryId)
    }

    @Test fun `undo refuses receipt cleanup dependency without deleting money`() = runTest {
        val bill = prepare()
        val paid = repo.payRecurringBill(owner, request(bill), device, now).getOrThrow()
        store.billReceiptIds = setOf(paid.transaction.id)
        assertEquals(BillPaymentError.UNSUPPORTED_LINKED_STATE,
            reason(repo.undoRecurringBillPayment(owner, RecordId(bill.id), month, device, now)))
        assertEquals(listOf(paid.transaction), repo.observeTransactions(owner).first())
        assertEquals(paid.occurrences, repo.observeDueOccurrences(owner).first())
    }
    @Test fun `archived bill history cannot be undone by stale payment request`() = runTest {
        val bill = prepare()
        val paid = repo.payRecurringBill(owner, request(bill), device, now).getOrThrow()
        repo.archiveRecurringBill(owner, RecordId(bill.id), device, now).getOrThrow()
        val outbox = store.outboxRows(owner.value)
        assertEquals(BillPaymentError.NOT_FOUND,
            reason(repo.undoRecurringBillPayment(owner, RecordId(bill.id), month, device, now)))
        assertEquals(outbox, store.outboxRows(owner.value))
        assertEquals(listOf(paid.transaction), repo.observeTransactions(owner).first())
        assertEquals(paid.occurrences, repo.observeDueOccurrences(owner).first())
    }

    @Test fun `paid card statement locks bill payment undo without changing history`() = runTest {
        val bill = prepare()
        val card = repo.saveCreditCard(owner, CreditCardDraft(name="Card", creditLimitMinor=10000,
            paymentSourceWalletId=bill.paymentWalletId), device, now).getOrThrow()
        val paid = repo.payRecurringBill(owner, request(bill).copy(walletId=RecordId(card.wallet.id)), device, now).getOrThrow()
        repo.saveTransaction(owner, TransactionDraft(primaryKind=TransactionPrimaryKind.TRANSFER,
            transferSubtype=TransactionTransferSubtype.INTERNAL_TRANSFER, title="Card payment 10/2026",
            amountMinor=5000, occurredAt=now, sourceWalletId=bill.paymentWalletId, destinationWalletId=card.wallet.id), device, now).getOrThrow()
        val outbox = store.outboxRows(owner.value)
        val result = repo.undoRecurringBillPayment(owner, RecordId(bill.id), month, device, now)
        assertEquals(TransactionValidationError.PAID_CREDIT_CARD_STATEMENT,
            (result.exceptionOrNull() as? TransactionValidationException)?.reason)
        assertEquals(outbox, store.outboxRows(owner.value))
        assertEquals(paid.occurrences, repo.observeDueOccurrences(owner).first())
        assertEquals(2, repo.observeTransactions(owner).first().size)
    }
    @Test fun `receipt added while undo is pending invalidates whole money batch`() = runTest {
        val bill = prepare()
        val paid = repo.payRecurringBill(owner, request(bill), device, now).getOrThrow()
        val racing = object : LocalStore by store {
            override suspend fun commitBillMoneyMutations(snapshot: BillMoneySnapshot, mutations: List<Pair<CloudRecord, PendingMutation>>) {
                store.billReceiptIds = setOf(paid.transaction.id)
                store.commitBillMoneyMutations(snapshot, mutations)
            }
        }
        assertTrue(OfflineFirstFinanceRepository(racing, zone, catalog)
            .undoRecurringBillPayment(owner, RecordId(bill.id), month, device, now).isFailure)
        assertEquals(listOf(paid.transaction), repo.observeTransactions(owner).first())
        assertEquals(paid.occurrences, repo.observeDueOccurrences(owner).first())
    }

    @Test fun `investment wallet requires fund usage implementation before any money writes`() = runTest {
        val bill = prepare()
        val wallet = LedgerWalletRecord.fromCloudRecord(store.record(owner, CloudEntity.LEDGER_WALLET.table, bill.paymentWalletId!!)!!)
            .copy(kindWireValue=WalletKind.INVESTMENT.wireValue)
        store.commitMutation(wallet.toCloudRecord(), PendingMutation(CloudEntity.LEDGER_WALLET, wallet.id, owner.value,
            MutationKind.UPSERT, wallet.toPayload(), now, wallet.syncVersion, device))
        assertEquals(BillPaymentError.INVESTMENT_USAGE_UNAVAILABLE, reason(repo.payRecurringBill(owner, request(bill), device, now)))
        assertTrue(repo.observeTransactions(owner).first().isEmpty())
        assertTrue(repo.observeDueOccurrences(owner).first().isEmpty())
    }

}
