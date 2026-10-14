package vn.com.quyln.mistia.core.database

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import vn.com.quyln.mistia.core.model.*

class InstallmentRepositoryTest {
    private val owner = UserId("11111111-1111-1111-1111-111111111111")
    private val id = "22222222-2222-2222-2222-222222222222"
    private val walletId = "33333333-3333-3333-3333-333333333333"
    private val device = "44444444-4444-4444-4444-444444444444"
    private val other = "99999999-9999-9999-9999-999999999999"
    private val created = "2026-01-15T00:00:00Z"
    private val now = "2026-10-14T01:00:00Z"
    private fun wallet() = LedgerWalletRecord.fromCloudRecord(WalletDraft(id = walletId, name = "Cash", kind = WalletKind.CASH, currencyCode = "JPY")
        .toMutation(owner, null, device, created).record)
    private fun plan() = InstallmentPlanRecord(id, owner.value, "Loan", "mistia.plan.installment", 5000, 15, 12, 1, walletId,
        "JPY", false, created, created, null, 9007199254740993L, device)
    private fun draft(expected: InstallmentPlanRecord? = null) = InstallmentDraft(id, " Updated ", 9007199254740993L, 31, 2, null, walletId,
        expected?.currencyCode ?: "JPY", "mistia.plan.loan", expected)
    private fun occurrence(index: Int, status: String = "pending") = DueOccurrenceRecord("70000000-0000-0000-0000-${index.toString().padStart(12, '0')}",
        owner.value, "installment", id, "2026-01", created, 5000, status, if (status == "paid") created else null,
        if (status == "paid") walletId else null, created, created, null, 9007199254740995L + index, device)
    private class Store(val memory: BudgetMemoryStore = BudgetMemoryStore()) : LocalStore by memory {
        var beforeCommit: (suspend () -> Unit)? = null
        var alwaysStale = false
        var attempts = 0
        var successful = 0
        override suspend fun installmentMutationSnapshot(owner: UserId, planId: String) = InstallmentMutationSnapshot(owner, planId,
            InstallmentMutationSnapshot.entities.associateWith { recordsIncludingDeleted(owner, it.table) })
        override suspend fun commitInstallmentMutations(expected: InstallmentMutationSnapshot, mutations: List<Pair<CloudRecord, PendingMutation>>): Boolean {
            attempts++
            beforeCommit?.let { beforeCommit = null; it() }
            if (alwaysStale) return false
            val current = InstallmentMutationSnapshot.entities.associateWith { recordsIncludingDeleted(expected.owner, it.table) }
            if (runCatching { expected.requireUnchanged(current) }.isFailure) return false
            expected.requireValidMutations(mutations)
            commitMutations(mutations); successful++; return true
        }
        suspend fun put(record: CloudRecord) {
            val owner = UserId(record.ownerUserId)
            replacePullSnapshot(owner, record.entity, recordsIncludingDeleted(owner, record.entity).filterNot { it.id == record.id } + record)
        }
    }
    private suspend fun ready(plan: CloudRecord? = null): Store = Store().also { it.put(wallet().toCloudRecord()); plan?.let { p -> it.put(p) } }
    private fun reason(result: Result<*>) = (result.exceptionOrNull() as? InstallmentValidationException)?.reason
    @Test fun `create atomically stores exact amount full nulls and one owned outbox row`() = runTest {
        val store = ready(); val saved = OfflineFirstFinanceRepository(store).saveInstallment(owner, draft(), device, now).getOrThrow()
        assertEquals(id, saved.id); assertEquals("Updated", saved.name); assertEquals(9007199254740993L, saved.amountPerCycleMinor)
        assertEquals(now, saved.createdAt); assertEquals(0L, saved.syncVersion); assertNull(saved.totalCycles)
        val pending = store.memory.outboxRows(owner.value).single()
        assertEquals(CloudEntity.INSTALLMENT_PLAN, pending.entity); assertEquals(0L, pending.baseVersion); assertSame(JsonNull, pending.payload!!["total_cycles"])
        assertEquals(1, store.successful)
    }
    @Test fun `edit preserves raw frozen metadata unknown fields and exact base version while clearing total cycles`() = runTest {
        val source = plan(); val raw = source.toCloudRecord().copy(payload = JsonObject(source.toPayload() + mapOf("future_flag" to JsonPrimitive(true),
            "currency_code" to JsonPrimitive("jpy"), "created_at" to JsonPrimitive("2026-01-15T09:00:00+09:00"))))
        val store = ready(raw); val saved = OfflineFirstFinanceRepository(store).saveInstallment(owner, draft(source), device, now).getOrThrow()
        assertEquals(source.syncVersion, saved.syncVersion); assertEquals("JPY", saved.currencyCode); assertEquals(9007199254740993L, saved.amountPerCycleMinor)
        val actual = store.record(owner, raw.entity, id)!!
        listOf("future_flag", "currency_code", "created_at", "sync_version", "id", "user_id").forEach { assertEquals(it, raw.payload[it], actual.payload[it]) }
        assertSame(JsonNull, actual.payload["total_cycles"]); assertEquals(source.syncVersion, store.memory.outboxRows(owner.value).single().baseVersion)
    }
    @Test fun `validation rejects empty name zero amount invalid schedule and malformed identity without writes`() = runTest {
        val store = ready(); val repo = OfflineFirstFinanceRepository(store)
        listOf(draft().copy(name = " ") to InstallmentValidationError.NAME_REQUIRED, draft().copy(amountPerCycleMinor = 0) to InstallmentValidationError.INVALID_AMOUNT,
            draft().copy(dueDay = 32) to InstallmentValidationError.INVALID_DAYS, draft().copy(frequencyMonths = 13) to InstallmentValidationError.INVALID_FREQUENCY,
            draft().copy(id = "x-x-x-x-x") to InstallmentValidationError.INVALID_IDENTITY).forEach { (request, wanted) ->
            assertEquals(wanted, reason(repo.saveInstallment(owner, request, device, now)))
        }
        assertEquals(0, store.attempts); assertTrue(store.memory.outboxRows(owner.value).isEmpty())
    }
    @Test fun `required wallet must be current owned known non card and new links cannot target archive`() = runTest {
        val store = ready(); val repo = OfflineFirstFinanceRepository(store)
        assertEquals(InstallmentValidationError.INVALID_WALLET, reason(repo.saveInstallment(owner, draft().copy(paymentWalletId = null), device, now)))
        for (invalid in listOf(wallet().copy(isArchived = true), wallet().copy(deletedAt = now), wallet().copy(kindWireValue = "creditCard"), wallet().copy(ownerUserId = other))) {
            store.put(invalid.toCloudRecord())
            if (invalid.ownerUserId == other) store.replacePullSnapshot(owner, CloudEntity.LEDGER_WALLET.table, emptyList())
            assertEquals(InstallmentValidationError.INVALID_WALLET, reason(repo.saveInstallment(owner, draft(), device, now)))
        }
        assertTrue(store.memory.outboxRows(owner.value).isEmpty())
    }
    @Test fun `existing archived linked wallet can be retained without paying it`() = runTest {
        val source = plan(); val store = ready(source.toCloudRecord()); store.put(wallet().copy(isArchived = true).toCloudRecord())
        assertEquals(walletId, OfflineFirstFinanceRepository(store).saveInstallment(owner, draft(source), device, now).getOrThrow().paymentWalletId)
    }
    @Test fun `edit cannot change imported currency or act on foreign missing archived and deleted plan`() = runTest {
        val source = plan(); val store = ready(source.toCloudRecord()); val repo = OfflineFirstFinanceRepository(store)
        assertEquals(InstallmentValidationError.INVALID_CURRENCY, reason(repo.saveInstallment(owner, draft(source).copy(currencyCode = "VND"), device, now)))
        assertEquals(InstallmentValidationError.NOT_FOUND, reason(repo.saveInstallment(owner, draft(source.copy(ownerUserId = other)), device, now)))
        for (invalid in listOf(source.copy(isArchived = true), source.copy(deletedAt = now))) {
            store.put(invalid.toCloudRecord()); assertEquals(InstallmentValidationError.NOT_FOUND, reason(repo.saveInstallment(owner, draft(source), device, now)))
        }
        store.replacePullSnapshot(owner, CloudEntity.INSTALLMENT_PLAN.table, emptyList())
        assertEquals(InstallmentValidationError.NOT_FOUND, reason(repo.saveInstallment(owner, draft(source), device, now)))
        assertTrue(store.memory.outboxRows(owner.value).isEmpty())
    }
    @Test fun `unchanged imported legacy schedule is preserved while new invalid values are rejected`() = runTest {
        for (source in listOf(plan().copy(dueDay = 99, frequencyMonths = 0), plan().copy(dueDay = 0, frequencyMonths = -3))) {
            val store = ready(source.toCloudRecord()); val repo = OfflineFirstFinanceRepository(store)
            val request = draft(source).copy(dueDay = source.dueDay, frequencyMonths = source.frequencyMonths)
            val saved = repo.saveInstallment(owner, request, device, now).getOrThrow()
            assertEquals(source.dueDay, saved.dueDay); assertEquals(source.frequencyMonths, saved.frequencyMonths)
            assertEquals(InstallmentValidationError.INVALID_DAYS, reason(repo.saveInstallment(owner, draft(saved).copy(dueDay = 100), device, now)))
            assertEquals(InstallmentValidationError.INVALID_FREQUENCY, reason(repo.saveInstallment(owner, draft(saved).copy(frequencyMonths = 99), device, now)))
        }
    }
    @Test fun `a semantic remote edit is stale and cannot be overwritten`() = runTest {
        val source = plan(); val store = ready(source.copy(name = "Remote edit").toCloudRecord())
        assertEquals(InstallmentValidationError.STALE_RECORD, reason(OfflineFirstFinanceRepository(store).saveInstallment(owner, draft(source), device, now)))
        assertTrue(store.memory.outboxRows(owner.value).isEmpty())
    }
    @Test fun `metadata only ACK does not stale the form and fresh version is used`() = runTest {
        val source = plan(); val ack = source.copy(syncVersion = source.syncVersion + 1, updatedAt = now, lastModifiedByDeviceId = other)
        val store = ready(ack.toCloudRecord()); val saved = OfflineFirstFinanceRepository(store).saveInstallment(owner, draft(source), device, now).getOrThrow()
        assertEquals(ack.syncVersion, saved.syncVersion); assertEquals(ack.syncVersion, store.memory.outboxRows(owner.value).single().baseVersion)
    }
    @Test fun `creation replay with stable ID is an ACK and cannot create a second record`() = runTest {
        val store = ready(); val repo = OfflineFirstFinanceRepository(store)
        val first = repo.saveInstallment(owner, draft(), device, now).getOrThrow()
        assertEquals(first, repo.saveInstallment(owner, draft(), device, "2026-10-15T00:00:00Z").getOrThrow())
        assertEquals(1, store.successful); assertEquals(1, store.memory.outboxRows(owner.value).size)
        assertEquals(InstallmentValidationError.STALE_RECORD, reason(repo.saveInstallment(owner, draft().copy(name = "Different"), device, now)))
    }
    @Test fun `two repository instances replaying the same create converge on one committed plan`() = runTest {
        val store = ready(); val outer = OfflineFirstFinanceRepository(store)
        val nestedNow = "2026-10-14T02:00:00Z"
        store.beforeCommit = { OfflineFirstFinanceRepository(store).saveInstallment(owner, draft(), device, nestedNow).getOrThrow() }
        val saved = outer.saveInstallment(owner, draft(), device, now).getOrThrow()
        assertEquals(nestedNow, saved.createdAt); assertEquals(1, store.successful); assertEquals(1, store.memory.outboxRows(owner.value).size)
    }
    @Test fun `editing replay acknowledges already committed desired fields without rewriting timestamps`() = runTest {
        val source = plan(); val store = ready(source.toCloudRecord()); val repo = OfflineFirstFinanceRepository(store)
        val saved = repo.saveInstallment(owner, draft(source), device, now).getOrThrow()
        assertEquals(saved, repo.saveInstallment(owner, draft(source), device, "2026-10-15T00:00:00Z").getOrThrow())
        assertEquals(1, store.successful); assertEquals(now, store.memory.outboxRows(owner.value).single().modifiedAt)
    }
    @Test fun `repeated edits coalesce the record identity without moving original creation anchor`() = runTest {
        val store = ready(); val repo = OfflineFirstFinanceRepository(store)
        val first = repo.saveInstallment(owner, draft(), device, now).getOrThrow()
        val next = repo.saveInstallment(owner, draft(first).copy(name = "Next"), device, "2026-11-01T00:00:00Z").getOrThrow()
        assertEquals(now, next.createdAt); assertEquals(0L, store.memory.outboxRows(owner.value).single().baseVersion)
    }
    @Test fun `delete tombstones every owned live installment occurrence atomically and preserves expense ledger`() = runTest {
        val source = plan(); val store = ready(source.toCloudRecord())
        val rows = listOf(occurrence(1), occurrence(2, "paid"), occurrence(3, "skipped"))
        rows.forEach { store.put(it.toCloudRecord()) }
        val unrelated = occurrence(4).copy(sourceId = other); store.put(unrelated.toCloudRecord())
        val otherKind = occurrence(5).copy(sourceKindWireValue = "recurringBill"); store.put(otherKind.toCloudRecord())
        val foreign = occurrence(6).copy(ownerUserId = other); store.put(foreign.toCloudRecord())
        val ledger = CloudRecord(CloudEntity.LEDGER_TRANSACTION.table, walletId, owner.value, buildJsonObject { put("kept", true) }, created, null, 7)
        store.put(ledger)
        OfflineFirstFinanceRepository(store).deleteInstallment(owner, source, device, now).getOrThrow()
        assertEquals(now, store.record(owner, CloudEntity.INSTALLMENT_PLAN.table, id)!!.deletedAt)
        rows.forEach { before -> val actual = DueOccurrenceRecord.fromCloudRecord(store.record(owner, CloudEntity.DUE_OCCURRENCE_RECORD.table, before.id)!!)
            assertEquals(now, actual.deletedAt); assertEquals(before.amountMinorSnapshot, actual.amountMinorSnapshot); assertEquals(before.linkedTransactionId, actual.linkedTransactionId)
            assertEquals(before.status, actual.status); assertEquals(before.syncVersion, actual.syncVersion) }
        assertEquals(unrelated.toCloudRecord(), store.record(owner, CloudEntity.DUE_OCCURRENCE_RECORD.table, unrelated.id))
        assertEquals(otherKind.toCloudRecord(), store.record(owner, CloudEntity.DUE_OCCURRENCE_RECORD.table, otherKind.id))
        assertEquals(foreign.toCloudRecord(), store.record(UserId(other), CloudEntity.DUE_OCCURRENCE_RECORD.table, foreign.id))
        assertEquals(ledger, store.record(owner, ledger.entity, ledger.id)); assertEquals(4, store.memory.outboxRows(owner.value).size)
        assertTrue(store.memory.outboxRows(owner.value).all { it.kind == MutationKind.DELETE })
    }
    @Test fun `delete preserves raw occurrence unknown fields and existing tombstones and is idempotent`() = runTest {
        val source = plan(); val store = ready(source.toCloudRecord()); val occurrence = occurrence(1, "paid")
        val raw = occurrence.toCloudRecord().copy(payload = JsonObject(occurrence.toPayload() + ("future_flag" to JsonPrimitive("retain"))))
        val old = occurrence(2).copy(deletedAt = created); store.put(raw); store.put(old.toCloudRecord())
        val repo = OfflineFirstFinanceRepository(store); repo.deleteInstallment(owner, source, device, now).getOrThrow()
        assertEquals(JsonPrimitive("retain"), store.record(owner, raw.entity, raw.id)!!.payload["future_flag"])
        assertEquals(old.toCloudRecord(), store.record(owner, raw.entity, old.id))
        repo.deleteInstallment(owner, source, device, now).getOrThrow(); assertEquals(1, store.successful)
    }
    @Test fun `atomic failure leaves plan all occurrences and outbox unchanged`() = runTest {
        val source = plan(); val store = ready(source.toCloudRecord()); val row = occurrence(1, "paid"); store.put(row.toCloudRecord())
        store.memory.failBatch = true
        assertTrue(OfflineFirstFinanceRepository(store).deleteInstallment(owner, source, device, now).isFailure)
        assertEquals(source.toCloudRecord(), store.record(owner, CloudEntity.INSTALLMENT_PLAN.table, id))
        assertEquals(row.toCloudRecord(), store.record(owner, CloudEntity.DUE_OCCURRENCE_RECORD.table, row.id)); assertTrue(store.memory.outboxRows(owner.value).isEmpty())
    }
    @Test fun `new occurrence between snapshot and delete is retried and included rather than orphaned`() = runTest {
        val source = plan(); val store = ready(source.toCloudRecord()); val row = occurrence(1, "paid")
        store.beforeCommit = { store.put(row.toCloudRecord()) }
        OfflineFirstFinanceRepository(store).deleteInstallment(owner, source, device, now).getOrThrow()
        assertEquals(2, store.attempts); assertEquals(now, store.record(owner, CloudEntity.DUE_OCCURRENCE_RECORD.table, row.id)!!.deletedAt)
    }
    @Test fun `wallet archive race rejects new plan after fresh validation`() = runTest {
        val store = ready(); store.beforeCommit = { store.put(wallet().copy(isArchived = true).toCloudRecord()) }
        assertEquals(InstallmentValidationError.INVALID_WALLET, reason(OfflineFirstFinanceRepository(store).saveInstallment(owner, draft(), device, now)))
        assertEquals(1, store.attempts); assertTrue(store.memory.outboxRows(owner.value).isEmpty())
    }
    @Test fun `plan edit race refuses overwriting a new remote value`() = runTest {
        val source = plan(); val store = ready(source.toCloudRecord()); store.beforeCommit = { store.put(source.copy(name = "Remote").toCloudRecord()) }
        assertEquals(InstallmentValidationError.STALE_RECORD, reason(OfflineFirstFinanceRepository(store).saveInstallment(owner, draft(source), device, now)))
        assertEquals("Remote", InstallmentPlanRecord.fromCloudRecord(store.record(owner, CloudEntity.INSTALLMENT_PLAN.table, id)!!).name)
    }
    @Test fun `persistent CAS conflicts stop after three attempts without writing`() = runTest {
        val store = ready(); store.alwaysStale = true
        assertEquals(InstallmentValidationError.STALE_RECORD, reason(OfflineFirstFinanceRepository(store).saveInstallment(owner, draft(), device, now)))
        assertEquals(3, store.attempts); assertTrue(store.memory.outboxRows(owner.value).isEmpty())
    }
    @Test fun `delete refuses stale source and leaves malformed owned history intact on failure`() = runTest {
        val source = plan(); val store = ready(source.copy(name = "Remote").toCloudRecord()); val repo = OfflineFirstFinanceRepository(store)
        assertEquals(InstallmentValidationError.STALE_RECORD, reason(repo.deleteInstallment(owner, source, device, now)))
        store.put(source.toCloudRecord())
        val bad = occurrence(1).toCloudRecord().let { it.copy(payload = JsonObject(it.payload + ("amount_minor_snapshot" to JsonPrimitive("bad")))) }
        store.put(bad)
        assertTrue(repo.deleteInstallment(owner, source, device, now).isFailure)
        assertEquals(source.toCloudRecord(), store.record(owner, CloudEntity.INSTALLMENT_PLAN.table, id))
        assertEquals(bad, store.record(owner, bad.entity, bad.id)); assertTrue(store.memory.outboxRows(owner.value).isEmpty())
    }
    @Test fun `foreign payload occurrence is not rewritten while deleting owned plan`() = runTest {
        val source = plan(); val store = ready(source.toCloudRecord())
        val foreign = occurrence(1).toCloudRecord().let { it.copy(payload = JsonObject(it.payload + ("user_id" to JsonPrimitive(other)))) }
        store.put(foreign)
        OfflineFirstFinanceRepository(store).deleteInstallment(owner, source, device, now).getOrThrow()
        assertEquals(foreign, store.record(owner, foreign.entity, foreign.id)); assertEquals(1, store.memory.outboxRows(owner.value).size)
    }
    @Test fun `store without conditional snapshot support cannot fall back to an unsafe batch`() = runTest {
        val store = BudgetMemoryStore()
        val result = OfflineFirstFinanceRepository(store).saveInstallment(owner, draft(), device, now)
        assertTrue(result.exceptionOrNull() is UnsupportedOperationException); assertTrue(store.outboxRows(owner.value).isEmpty())
    }
    @Test fun `cancellation at commit propagates without being converted to form error`() = runTest {
        val store = ready(); store.beforeCommit = { throw CancellationException("Account changed") }
        try { OfflineFirstFinanceRepository(store).saveInstallment(owner, draft(), device, now); fail("Cancellation expected") }
        catch (_: CancellationException) { assertTrue(store.memory.outboxRows(owner.value).isEmpty()) }
    }
}
