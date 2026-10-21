package vn.com.quyln.mistia.core.database

import java.time.YearMonth
import java.time.ZoneId
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.json.*
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test
import vn.com.quyln.mistia.core.model.*

class InstallmentPaymentRepositoryTest {
    private val owner = UserId("11111111-1111-1111-1111-111111111111")
    private val device = "22222222-2222-2222-2222-222222222222"
    private val id = "33333333-3333-3333-3333-333333333333"
    private val other = UserId("99999999-9999-9999-9999-999999999999")
    private val now = "2026-10-15T00:00:00Z"
    private val later = "2026-10-15T01:00:00Z"
    private val month = YearMonth.of(2026, 10)
    private val zone = ZoneId.of("Asia/Tokyo")
    private val store = BudgetMemoryStore()
    private val catalog = SystemCategoryCatalog.parse("""[
        {"id":"parent_expense_financial_obligations","kind":"expense","active":true,"icon":"house.fill","fallbackIcon":"house.fill","color":"#123456","translations":{"vi":"Nợ","en":"Debt","ja":"債務"},"aliases":[],"children":[
          {"id":"loan_repayment","active":true,"icon":"mistia.category.expense.financial_obligations.loan_repayment","fallbackIcon":"house.fill","color":"#123456","translations":{"vi":"Trả nợ","en":"Loan repayment","ja":"返済"},"aliases":[]}
        ]}
    ]""")
    private val repo = OfflineFirstFinanceRepository(store, zone, catalog)
    private suspend fun prepare(amount: Long = 5000, balance: Long = 10000): InstallmentPlanRecord {
        val wallet = repo.saveWallet(owner, WalletDraft(name = "Cash", kind = WalletKind.CASH, currencyCode = "JPY", openingBalanceMinor = balance), device, now).getOrThrow()
        return InstallmentPlanRecord(id, owner.value, "Loan", "mistia.plan.loan", amount, 15, 12, 1, wallet.id, "JPY", false, now, now, null, 0, device).also { putPlan(it) }
    }
    private suspend fun putPlan(plan: InstallmentPlanRecord) {
        val row = plan.toCloudRecord()
        store.commitMutation(row, PendingMutation(CloudEntity.INSTALLMENT_PLAN, row.id, owner.value, if (row.deletedAt == null) MutationKind.UPSERT else MutationKind.DELETE, row.payload, row.updatedAt!!, row.syncVersion, device))
    }
    private fun request(plan: InstallmentPlanRecord, wallet: String? = null, amount: Long? = null) = InstallmentPaymentRequest(plan, month, wallet?.let(::RecordId), amount)
    private fun reason(result: Result<*>) = (result.exceptionOrNull() as? BillPaymentException)?.reason
    @Test fun `changed effective cycle cannot accept old amount under an unchanged plan`()=runTest {
        val visible=prepare()
        val pending=DueOccurrenceRecord(other.value,owner.value,"installment",visible.id,month.toString(),now,6000,"pending",null,null,now,now,null,0,device)
        store.commitMutation(pending.toCloudRecord(),pending.pendingMutation())
        val before=CloudEntity.entries.associateWith {store.recordsIncludingDeleted(owner,it.table)};val queue=store.outboxRows(owner.value)
        val result=repo.payInstallment(owner,request(visible,amount=5000),device,now)
        assertEquals("paid=${result.getOrNull()?.transaction?.amountMinor}",BillPaymentError.SOURCE_CHANGED,reason(result))
        assertEquals(before,CloudEntity.entries.associateWith {store.recordsIncludingDeleted(owner,it.table)})
        assertEquals(queue,store.outboxRows(owner.value))
    }
    @Test fun `fresh effective cycle baseline permits its exact snapshot amount`()=runTest {
        val visible=prepare()
        val pending=DueOccurrenceRecord(other.value,owner.value,"installment",visible.id,month.toString(),now,6000,"pending",null,null,now,now,null,0,device)
        store.commitMutation(pending.toCloudRecord(),pending.pendingMutation())
        val paid=repo.payInstallment(owner,request(visible,amount=6000).copy(expectedDueAmountMinor=6000),device,now).getOrThrow()
        assertEquals(6000L,paid.transaction.amountMinor);assertEquals(6000L,paid.occurrences.single().amountMinorSnapshot)
    }
    @Test fun `native installment payment atomically posts loan repayment expense and owned paid cycle`() = runTest {
        val plan = prepare(); val saved = repo.payInstallment(owner, request(plan), device, now).getOrThrow()
        assertEquals(TransactionPrimaryKind.EXPENSE, saved.transaction.primaryKind); assertEquals(5000L, saved.transaction.amountMinor); assertEquals("JPY", saved.transaction.sourceCurrencyCode)
        assertEquals(plan.paymentWalletId, saved.transaction.sourceWalletId)
        val category = repo.observeCategories(owner).first().single { it.id == saved.transaction.categoryId }
        assertEquals("loan_repayment", category.systemKey)
        val due = saved.occurrences.single(); assertEquals("installment", due.sourceKindWireValue); assertEquals(plan.id, due.sourceId)
        assertEquals(DueStatus.PAID, due.status); assertEquals(saved.transaction.id, due.linkedTransactionId); assertEquals(5000L, due.amountMinorSnapshot)
        assertEquals(plan, repo.observeInstallments(owner).first().single())
        assertEquals(1, repo.observeTransactions(owner).first().size)
        assertTrue(store.outboxRows(owner.value).any { it.entity == CloudEntity.DUE_OCCURRENCE_RECORD && it.recordId == due.id })
    }
    @Test fun `payment keeps exact Long amounts above IEEE integer precision and permits explicit positive override`() = runTest {
        val amount = 9007199254740993L; val plan = prepare(amount, amount)
        val saved = repo.payInstallment(owner, request(plan), device, now).getOrThrow()
        assertEquals(amount, saved.transaction.amountMinor); assertEquals(amount, saved.occurrences.single().amountMinorSnapshot)
    }
    @Test fun `same currency rule applies to selected override and stale default before any money write`() = runTest {
        val plan = prepare(); val wrong = repo.saveWallet(owner, WalletDraft(name = "VND", kind = WalletKind.CASH, currencyCode = "VND", openingBalanceMinor = 1000000), device, now).getOrThrow()
        val before = store.outboxRows(owner.value)
        assertEquals(BillPaymentError.WALLET_CURRENCY_MISMATCH, reason(repo.payInstallment(owner, request(plan, wrong.id), device, now)))
        assertEquals(before, store.outboxRows(owner.value)); assertTrue(repo.observeTransactions(owner).first().isEmpty()); assertTrue(repo.observeDueOccurrences(owner).first().isEmpty())
    }
    @Test fun `payment rejects insufficient current balance without writing an expense or cycle`() = runTest {
        val plan = prepare(balance = 4999); val before = store.outboxRows(owner.value)
        val result = repo.payInstallment(owner, request(plan), device, now)
        assertTrue(result.exceptionOrNull() is TransactionValidationException); assertTrue(repo.observeTransactions(owner).first().isEmpty()); assertEquals(before, store.outboxRows(owner.value))
    }
    @Test fun `paid and skipped cycles cannot produce duplicate expenses`() = runTest {
        val plan = prepare(); val paid = repo.payInstallment(owner, request(plan), device, now).getOrThrow()
        assertEquals(BillPaymentError.CYCLE_NOT_PENDING, reason(repo.payInstallment(owner, request(plan), device, later)))
        assertEquals(listOf(paid.transaction), repo.observeTransactions(owner).first())
    }
    @Test fun `skipped installment must be undone before payment`() = runTest {
        val plan = prepare(); val skipped = DueOccurrenceRecord(device, owner.value, "installment", id, month.toString(), now, null, "skipped", null, null, now, now, null, 0, device)
        store.commitMutation(skipped.toCloudRecord(), skipped.pendingMutation())
        assertEquals(BillPaymentError.CYCLE_NOT_PENDING, reason(repo.payInstallment(owner, request(plan), device, later)))
        assertTrue(repo.observeTransactions(owner).first().isEmpty())
    }
    @Test fun `unscheduled month or non positive override cannot create any money record`() = runTest {
        val plan = prepare()
        assertEquals(BillPaymentError.NOT_SCHEDULED, reason(repo.payInstallment(owner, request(plan).copy(month = month.minusMonths(1)), device, now)))
        for (amount in listOf(0L, -1L)) assertEquals(BillPaymentError.MISSING_AMOUNT, reason(repo.payInstallment(owner, request(plan, amount = amount), device, now)))
        assertTrue(repo.observeTransactions(owner).first().isEmpty())
    }
    @Test fun `foreign owner and deleted source cannot pay a retained default wallet`() = runTest {
        val plan = prepare()
        assertTrue(repo.payInstallment(other, request(plan), device, now).isFailure)
        putPlan(plan.copy(deletedAt = now))
        assertEquals(BillPaymentError.NOT_FOUND, reason(repo.payInstallment(owner, request(plan), device, now)))
        assertTrue(repo.observeTransactions(owner).first().isEmpty())
    }
    @Test fun `source amount changed since confirmation blocks payment`() = runTest {
        val plan = prepare(); val changed = plan.copy(amountPerCycleMinor = 6000, updatedAt = later).also { putPlan(it) }
        assertTrue(repo.payInstallment(owner, request(plan), device, later).isFailure)
        assertTrue(repo.observeTransactions(owner).first().isEmpty()); assertEquals(changed, repo.observeInstallments(owner).first().single())
    }
    @Test fun `undo and repay reuse one expense ID preserve exact ledger base and never duplicate debt spending`() = runTest {
        val plan = prepare(); val first = repo.payInstallment(owner, request(plan), device, now).getOrThrow()
        repo.undoInstallmentPayment(owner, plan, month, device, later).getOrThrow()
        assertTrue(repo.observeTransactions(owner).first().isEmpty()); assertTrue(repo.observeDueOccurrences(owner).first().isEmpty())
        val again = repo.payInstallment(owner, request(plan), device, "2026-10-15T02:00:00Z").getOrThrow()
        assertEquals(first.transaction.id, again.transaction.id); assertEquals(first.occurrences.single().id, again.occurrences.single().id)
        assertEquals(1, repo.observeTransactions(owner).first().size)
    }
    @Test fun `repeated undo is idempotent and no currency conversion is attempted for old historical data`() = runTest {
        val plan = prepare(); repo.payInstallment(owner, request(plan), device, now).getOrThrow()
        repo.undoInstallmentPayment(owner, plan, month, device, later).getOrThrow()
        val before = store.outboxRows(owner.value)
        repo.undoInstallmentPayment(owner, plan, month, device, later).getOrThrow(); assertEquals(before, store.outboxRows(owner.value))
    }
    @Test fun `wallet change during commit invalidates full money dependencies`() = runTest {
        val plan = prepare()
        val racing = object : LocalStore by store {
            override suspend fun commitBillMoneyMutations(snapshot: BillMoneySnapshot, mutations: List<Pair<CloudRecord, PendingMutation>>) {
                val cash = repo.observeWallets(owner).first().single()
                store.commitMutation(cash.copy(currencyCode = "USD").toCloudRecord(), PendingMutation(CloudEntity.LEDGER_WALLET, cash.id, owner.value, MutationKind.UPSERT, cash.copy(currencyCode = "USD").toPayload(), later, cash.syncVersion, device))
                store.commitBillMoneyMutations(snapshot, mutations)
            }
        }
        val raced = OfflineFirstFinanceRepository(racing, zone, catalog)
        assertTrue(raced.payInstallment(owner, request(plan), device, now).isFailure); assertTrue(repo.observeTransactions(owner).first().isEmpty()); assertTrue(repo.observeDueOccurrences(owner).first().isEmpty())
    }
    @Test fun `selected override keeps exact raw minor units and source currency`() = runTest {
        val plan = prepare(); val paid = repo.payInstallment(owner, request(plan, amount = 1375), device, now).getOrThrow()
        assertEquals(1375L, paid.transaction.amountMinor); assertEquals(1375L, paid.occurrences.single().amountMinorSnapshot)
        assertEquals(8625L, TransactionWalletBalanceIndex(repo.observeWallets(owner).first(), repo.observeTransactions(owner).first()).balance(plan.paymentWalletId!!))
    }
    @Test fun `same currency credit card archived deleted and investment wallets cannot be used as installment payment source`() = runTest {
        val plan = prepare(); val cash = repo.observeWallets(owner).first().single()
        for (wallet in listOf(cash.copy(kindWireValue = "creditCard"), cash.copy(isArchived = true), cash.copy(deletedAt = now), cash.copy(kindWireValue = "investment"))) {
            store.commitMutation(wallet.toCloudRecord(), PendingMutation(CloudEntity.LEDGER_WALLET, wallet.id, owner.value, MutationKind.UPSERT, wallet.toPayload(), now, wallet.syncVersion, device))
            assertTrue(repo.payInstallment(owner, request(plan), device, now).isFailure)
            assertTrue(repo.observeTransactions(owner).first().isEmpty()); assertTrue(repo.observeDueOccurrences(owner).first().isEmpty())
        }
    }
    @Test fun `metadata only source ACK retains the visible financial baseline`() = runTest {
        val plan = prepare(); putPlan(plan.copy(syncVersion = 9007199254740993, updatedAt = later, lastModifiedByDeviceId = other.value))
        assertEquals(5000L, repo.payInstallment(owner, request(plan), device, later).getOrThrow().transaction.amountMinor)
    }
    @Test fun `failed atomic money write leaves both tables and category bootstrap unchanged`() = runTest {
        val plan = prepare(); val before = store.outboxRows(owner.value); store.failBatch = true
        assertTrue(repo.payInstallment(owner, request(plan), device, now).isFailure)
        assertTrue(repo.observeTransactions(owner).first().isEmpty()); assertTrue(repo.observeDueOccurrences(owner).first().isEmpty()); assertTrue(repo.observeCategories(owner).first().isEmpty()); assertEquals(before, store.outboxRows(owner.value))
    }
    @Test fun `undo refuses an expense referenced by another live occurrence`() = runTest {
        val plan = prepare(); val paid = repo.payInstallment(owner, request(plan), device, now).getOrThrow()
        val shared = paid.occurrences.single().copy(id = other.value, sourceKindWireValue = "recurringBill", sourceId = device)
        store.commitMutation(shared.toCloudRecord(), shared.pendingMutation()); val before = store.outboxRows(owner.value)
        assertEquals(BillPaymentError.UNSUPPORTED_LINKED_STATE, reason(repo.undoInstallmentPayment(owner, plan, month, device, later)))
        assertEquals(listOf(paid.transaction), repo.observeTransactions(owner).first()); assertEquals(before, store.outboxRows(owner.value))
    }
    @Test fun `undo refuses receipt and settlement linked expenses without deleting paid markers`() = runTest {
        val plan = prepare(); val paid = repo.payInstallment(owner, request(plan), device, now).getOrThrow()
        val tx = paid.transaction.copy(settlementGroupId = other.value)
        store.commitMutation(tx.toCloudRecord(), PendingMutation(CloudEntity.LEDGER_TRANSACTION, tx.id, owner.value, MutationKind.UPSERT, tx.toPayload(), now, tx.syncVersion, device))
        assertEquals(BillPaymentError.UNSUPPORTED_LINKED_STATE, reason(repo.undoInstallmentPayment(owner, plan, month, device, later)))
        store.commitMutation(paid.transaction.toCloudRecord(), PendingMutation(CloudEntity.LEDGER_TRANSACTION, tx.id, owner.value, MutationKind.UPSERT, paid.transaction.toPayload(), now, tx.syncVersion, device))
        val receiptStore = object : LocalStore by store { override suspend fun billMoneyReceiptTransactionIds(owner: UserId) = setOf(tx.id) }
        assertEquals(BillPaymentError.UNSUPPORTED_LINKED_STATE, reason(OfflineFirstFinanceRepository(receiptStore, zone, catalog).undoInstallmentPayment(owner, plan, month, device, later)))
        assertEquals(DueStatus.PAID, repo.observeDueOccurrences(owner).first().single().status)
    }
    @Test fun `request cannot switch financial currency or schedule after the user confirmation`() = runTest {
        val plan = prepare()
        for (changed in listOf(plan.copy(currencyCode = "VND"), plan.copy(dueDay = 31), plan.copy(frequencyMonths = 2), plan.copy(totalCycles = 0))) {
            putPlan(changed)
            assertEquals(BillPaymentError.SOURCE_CHANGED, reason(repo.payInstallment(owner, request(plan), device, now)))
        }
        assertTrue(repo.observeTransactions(owner).first().isEmpty())
    }
    @Test fun `same ID belonging to a bill cannot satisfy installment source lookup`() = runTest {
        val plan = prepare(); putPlan(plan.copy(deletedAt = now))
        repo.ensureDefaultSystemCategories(owner, catalog, device, now).getOrThrow()
        val category = repo.observeCategories(owner).first().single { it.systemKey == "loan_repayment" }
        repo.saveRecurringBill(owner, RecurringBillDraft("Bill", category.id, 5000, plan.paymentWalletId, "JPY", id = id, zoneId = zone), device, now).getOrThrow()
        assertEquals(BillPaymentError.NOT_FOUND, reason(repo.payInstallment(owner, request(plan), device, now))); assertTrue(repo.observeTransactions(owner).first().isEmpty())
    }
    @Test fun `cancellation during dependency read propagates and never becomes a payment error`() = runTest {
        val plan = prepare(); val cancelled = object : LocalStore by store {
            override suspend fun recordsIncludingDeleted(ownerUserId: UserId, entity: String): List<CloudRecord> = throw CancellationException("fixture")
        }
        var thrown = false
        try { OfflineFirstFinanceRepository(cancelled, zone, catalog).payInstallment(owner, request(plan), device, now) } catch (_: CancellationException) { thrown = true }
        assertTrue(thrown); assertTrue(repo.observeTransactions(owner).first().isEmpty())
    }

    @Test fun `undo repay retain exact remote Long bases unknown payload fields and monotonic clock`() = runTest {
        val plan = prepare(); val paid = repo.payInstallment(owner, request(plan), device, now).getOrThrow(); val version = 9007199254740993L
        val tx = paid.transaction.copy(syncVersion = version); val occurrence = paid.occurrences.single().copy(syncVersion = version)
        val rawTx = tx.toCloudRecord().let { it.copy(payload = JsonObject(it.payload + ("future_financial_metadata" to JsonPrimitive("keep")))) }
        store.commitMutation(rawTx, PendingMutation(CloudEntity.LEDGER_TRANSACTION, tx.id, owner.value, MutationKind.UPSERT, rawTx.payload, now, version, device))
        store.commitMutation(occurrence.toCloudRecord(), occurrence.pendingMutation())
        repo.undoInstallmentPayment(owner, plan, month, device, now).getOrThrow()
        val again = repo.payInstallment(owner, request(plan, amount = 6000), device, now).getOrThrow()
        assertEquals(tx.id, again.transaction.id); assertEquals(version, again.transaction.syncVersion); assertEquals(version, again.occurrences.single().syncVersion)
        assertTrue(java.time.Instant.parse(again.transaction.updatedAt).isAfter(java.time.Instant.parse(now)))
        assertEquals(JsonPrimitive("keep"), store.record(owner, rawTx.entity, rawTx.id)!!.payload["future_financial_metadata"])
        assertTrue(store.outboxRows(owner.value).filter { it.entity in setOf(CloudEntity.LEDGER_TRANSACTION, CloudEntity.DUE_OCCURRENCE_RECORD) }.all { it.baseVersion == version && it.kind == MutationKind.UPSERT })
    }

}
