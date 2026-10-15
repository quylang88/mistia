package vn.com.quyln.mistia.core.database

import java.time.YearMonth
import java.time.ZoneId
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import vn.com.quyln.mistia.core.model.*

class InstallmentCycleRepositoryTest {
    private val owner = UserId("11111111-1111-1111-1111-111111111111")
    private val id = "22222222-2222-2222-2222-222222222222"
    private val walletId = "33333333-3333-3333-3333-333333333333"
    private val device = "44444444-4444-4444-4444-444444444444"
    private val other = "99999999-9999-9999-9999-999999999999"
    private val created = "2026-01-15T00:00:00Z"
    private val now = "2026-02-14T01:00:00Z"
    private val later = "2026-02-15T01:00:00Z"
    private val month = YearMonth.of(2026, 2)
    private val zone = ZoneId.of("Asia/Tokyo")
    private fun plan() = InstallmentPlanRecord(id, owner.value, "Loan", "mistia.plan.installment", 9007199254740993L, 31, 12, 1, walletId,
        "JPY", false, created, created, null, 9007199254740995L, device)
    private fun occurrence(index: Int, status: String = "pending") = DueOccurrenceRecord("70000000-0000-0000-0000-${index.toString().padStart(12, '0')}",
        owner.value, "installment", id, month.toString(), created, 9007199254740993L, status, null, null, created, created, null,
        9007199254740995L + index, device)
    private class Store(val memory: BudgetMemoryStore = BudgetMemoryStore()) : LocalStore by memory {
        var beforeCommit: (suspend () -> Unit)? = null
        var alwaysStale = false
        var attempts = 0
        var successful = 0
        val creationIds = mutableListOf<String>()
        override suspend fun installmentMutationSnapshot(owner: UserId, planId: String) = InstallmentMutationSnapshot(owner, planId,
            InstallmentMutationSnapshot.entities.associateWith { recordsIncludingDeleted(owner, it.table) })
        override suspend fun commitInstallmentCycleMutations(expected: InstallmentCycleSnapshot, mutations: List<Pair<CloudRecord, PendingMutation>>): Boolean {
            attempts++; creationIds += mutations.map { it.first.id }
            beforeCommit?.let { beforeCommit = null; it() }
            if (alwaysStale) return false
            val current = InstallmentMutationSnapshot.entities.associateWith { recordsIncludingDeleted(expected.base.owner, it.table) }
            if (runCatching { expected.base.requireUnchanged(current) }.isFailure) return false
            expected.requireValidMutations(mutations)
            commitMutations(mutations); successful++; return true
        }
        suspend fun put(record: CloudRecord) { val user = UserId(record.ownerUserId)
            replacePullSnapshot(user, record.entity, recordsIncludingDeleted(user, record.entity).filterNot { it.id == record.id } + record) }
    }
    private suspend fun ready(vararg occurrences: CloudRecord) = Store().also { s -> s.put(plan().toCloudRecord()); occurrences.forEach { s.put(it) } }
    private fun repo(store: LocalStore, zone: ZoneId = this.zone) = OfflineFirstFinanceRepository(store, zone)
    private fun reason(result: Result<*>) = (result.exceptionOrNull() as? InstallmentValidationException)?.reason
    private suspend fun Store.cycles() = recordsIncludingDeleted(owner, CloudEntity.DUE_OCCURRENCE_RECORD.table)

    @Test fun `skip creates clamped local due with explicit nulls and only occurrence outbox`() = runTest {
        val s = ready(); val saved = repo(s).skipInstallment(owner, plan(), month, device, now).getOrThrow()
        assertEquals("2026-02-27T15:00:00Z", saved.scheduledDate); assertEquals(DueStatus.SKIPPED, saved.status)
        assertEquals(month.toString(), saved.selectedMonthKey); assertNull(saved.amountMinorSnapshot); assertNull(saved.linkedTransactionId); assertNull(saved.paidAt)
        assertEquals(0L, saved.syncVersion); assertEquals(now, saved.createdAt)
        assertEquals(listOf(CloudEntity.DUE_OCCURRENCE_RECORD), s.memory.outboxRows(owner.value).map { it.entity })
        assertSame(JsonNull, s.cycles().single().payload["amount_minor_snapshot"])
        assertEquals(plan().toCloudRecord(), s.record(owner, CloudEntity.INSTALLMENT_PLAN.table, id))
        assertTrue(s.recordsIncludingDeleted(owner, CloudEntity.LEDGER_TRANSACTION.table).isEmpty())
    }
    @Test fun `skip is idempotent without rewriting timestamps or base versions`() = runTest {
        val s = ready(); val r = repo(s); val first = r.skipInstallment(owner, plan(), month, device, now).getOrThrow()
        val again = r.skipInstallment(owner, plan(), month, device, later).getOrThrow()
        assertEquals(first, again); assertEquals(1, s.successful); assertEquals(1, s.attempts)
    }
    @Test fun `pending duplicates all skip preserving Long base creation and unknown fields`() = runTest {
        val original = listOf(occurrence(1), occurrence(2))
        val raw = original.map { it.toCloudRecord().copy(payload = JsonObject(it.toPayload() + ("future" to JsonPrimitive("keep")))) }
        val s = ready(*raw.toTypedArray()); repo(s).skipInstallment(owner, plan(), month, device, now).getOrThrow()
        assertEquals(2, s.cycles().size)
        s.cycles().forEach { row ->
            val before = raw.single { it.id == row.id }
            assertEquals(before.syncVersion, row.syncVersion); assertEquals(before.payload["future"], row.payload["future"])
            assertEquals(before.payload["created_at"], row.payload["created_at"])
            assertEquals(DueStatus.SKIPPED, DueOccurrenceRecord.fromCloudRecord(row).status)
        }
        assertEquals(original.map { it.syncVersion }.toSet(), s.memory.outboxRows(owner.value).map { it.baseVersion }.toSet())
    }
    @Test fun `undo tombstones all skipped duplicates while preserving frozen amounts and pending records`() = runTest {
        val skipped = listOf(occurrence(1, "skipped"), occurrence(2, "skipped")); val pending = occurrence(3)
        val s = ready(*(skipped + pending).map { it.toCloudRecord() }.toTypedArray())
        repo(s).undoInstallmentSkip(owner, plan(), month, device, now).getOrThrow()
        skipped.forEach { old -> val row = s.cycles().single { it.id == old.id }
            assertEquals(now, row.deletedAt); assertEquals(old.amountMinorSnapshot, DueOccurrenceRecord.fromCloudRecord(row).amountMinorSnapshot)
            assertEquals(old.syncVersion, row.syncVersion)
        }
        assertEquals(pending.toCloudRecord(), s.cycles().single { it.id == pending.id })
        assertTrue(s.memory.outboxRows(owner.value).all { it.kind == MutationKind.DELETE })
    }
    @Test fun `undo missing skip is acknowledged without a write and new skip after undo uses a new live ID`() = runTest {
        val s = ready(); val r = repo(s)
        r.undoInstallmentSkip(owner, plan(), month, device, now).getOrThrow(); assertEquals(0, s.attempts)
        val first = r.skipInstallment(owner, plan(), month, device, now).getOrThrow()
        r.undoInstallmentSkip(owner, plan(), month, device, later).getOrThrow()
        val next = r.skipInstallment(owner, plan(), month, device, later).getOrThrow()
        assertNotEquals(first.id, next.id); assertEquals(1, s.cycles().count { it.deletedAt == null })
    }
    @Test fun `any paid duplicate or linked pending or paid time blocks skip and undo without touching ledger`() = runTest {
        for (protected in listOf(occurrence(2, "paid"), occurrence(2).copy(linkedTransactionId = walletId), occurrence(2).copy(paidAt = now))) {
            val s = ready(occurrence(1, "skipped").toCloudRecord(), protected.toCloudRecord()); val r = repo(s)
            assertEquals(InstallmentValidationError.SETTLED_CYCLE, reason(r.skipInstallment(owner, plan(), month, device, now)))
            assertEquals(InstallmentValidationError.SETTLED_CYCLE, reason(r.undoInstallmentSkip(owner, plan(), month, device, now)))
            assertEquals(0, s.attempts); assertTrue(s.memory.outboxRows(owner.value).isEmpty())
        }
    }
    @Test fun `only owned installment selected month participates and foreign aliases remain untouched`() = runTest {
        val ignored = listOf(occurrence(1).copy(ownerUserId = other).toCloudRecord().copy(ownerUserId = owner.value),
            occurrence(2).copy(sourceKindWireValue = "recurringBill").toCloudRecord(), occurrence(3).copy(selectedMonthKey = "2026-03").toCloudRecord(),
            occurrence(4).toCloudRecord().copy(id = other), occurrence(5).copy(deletedAt = created).toCloudRecord())
        val s = ready(*ignored.toTypedArray()); repo(s).skipInstallment(owner, plan(), month, device, now).getOrThrow()
        ignored.forEach { assertEquals(it, s.cycles().single { actual -> actual.id == it.id }) }
        assertEquals(1, s.memory.outboxRows(owner.value).size)
    }
    @Test fun `semantic source edits are stale while metadata ACK accepts current base`() = runTest {
        val s = ready(); s.put(plan().copy(name = "Remote edit").toCloudRecord())
        assertEquals(InstallmentValidationError.STALE_RECORD, reason(repo(s).skipInstallment(owner, plan(), month, device, now)))
        s.put(plan().copy(syncVersion = Long.MAX_VALUE, updatedAt = now, lastModifiedByDeviceId = other).toCloudRecord())
        repo(s).skipInstallment(owner, plan(), month, device, now).getOrThrow()
        assertEquals(Long.MAX_VALUE, s.record(owner, CloudEntity.INSTALLMENT_PLAN.table, id)!!.syncVersion)
    }
    @Test fun `foreign archived deleted and absent source reject before cycle writes`() = runTest {
        for (source in listOf(plan().copy(ownerUserId = other), plan().copy(isArchived = true), plan().copy(deletedAt = created))) {
            val s = ready(); s.put(source.toCloudRecord().copy(ownerUserId = owner.value))
            assertEquals(InstallmentValidationError.NOT_FOUND, reason(repo(s).skipInstallment(owner, plan(), month, device, now)))
            assertEquals(0, s.attempts)
        }
        val s = Store()
        assertEquals(InstallmentValidationError.NOT_FOUND, reason(repo(s).skipInstallment(owner, plan(), month, device, now)))
    }
    @Test fun `finite and frequency and pre anchor months cannot invent skipped cycles`() = runTest {
        for ((source, selected) in listOf(plan() to month.minusMonths(2), plan().copy(frequencyMonths = 2) to month,
            plan().copy(totalCycles = 1) to month, plan().copy(totalCycles = 0) to month)) {
            val s = ready(); s.put(source.toCloudRecord())
            assertEquals(InstallmentValidationError.NOT_SCHEDULED, reason(repo(s).skipInstallment(owner, source, selected, device, now)))
            assertEquals(0, s.attempts)
        }
    }
    @Test fun `malformed owned related cycle fails closed without a partial duplicate update`() = runTest {
        val bad = occurrence(2).toCloudRecord().copy(payload = JsonObject(occurrence(2).toPayload() + ("sync_version" to JsonPrimitive("bad"))))
        val s = ready(occurrence(1).toCloudRecord(), bad)
        assertTrue(repo(s).skipInstallment(owner, plan(), month, device, now).isFailure)
        assertEquals(0, s.attempts); assertTrue(s.memory.outboxRows(owner.value).isEmpty())
    }
    @Test fun `paid insert racing commit is recaptured and cannot be overwritten`() = runTest {
        val s = ready(); s.beforeCommit = { s.put(occurrence(1, "paid").toCloudRecord()) }
        assertEquals(InstallmentValidationError.SETTLED_CYCLE, reason(repo(s).skipInstallment(owner, plan(), month, device, now)))
        assertEquals(1, s.attempts); assertEquals(0, s.successful); assertEquals(DueStatus.PAID, DueOccurrenceRecord.fromCloudRecord(s.cycles().single()).status)
    }
    @Test fun `CAS retry retains one allocated occurrence UUID and exact clock`() = runTest {
        val s = ready(); s.beforeCommit = { s.put(plan().copy(updatedAt = later, syncVersion = Long.MAX_VALUE).toCloudRecord()) }
        val result = repo(s).skipInstallment(owner, plan(), month, device, now).getOrThrow()
        assertEquals(2, s.attempts); assertEquals(listOf(result.id, result.id), s.creationIds); assertEquals(now, result.updatedAt)
    }
    @Test fun `persistent CAS failure stops after three attempts with no fallback write`() = runTest {
        val s = ready(); s.alwaysStale = true
        assertEquals(InstallmentValidationError.STALE_RECORD, reason(repo(s).skipInstallment(owner, plan(), month, device, now)))
        assertEquals(3, s.attempts); assertTrue(s.cycles().isEmpty()); assertTrue(s.memory.outboxRows(owner.value).isEmpty())
    }
    @Test fun `cancellation propagates and unsupported atomic store has no unsafe fallback`() = runTest {
        val s = ready(); s.beforeCommit = { throw CancellationException("fixture") }
        var cancelled = false
        try { repo(s).skipInstallment(owner, plan(), month, device, now) } catch (_: CancellationException) { cancelled = true }
        assertTrue(cancelled); assertTrue(s.memory.outboxRows(owner.value).isEmpty())
        val unsupported = object : LocalStore by s {
            override suspend fun commitInstallmentCycleMutations(expected: InstallmentCycleSnapshot, mutations: List<Pair<CloudRecord, PendingMutation>>): Boolean = throw UnsupportedOperationException("fixture")
        }
        assertTrue(repo(unsupported).skipInstallment(owner, plan(), month, device, now).isFailure)
        assertTrue(s.memory.outboxRows(owner.value).isEmpty())
    }
    @Test fun `repository captures injected Japan and Vietnam calendar for same UTC month boundary`() = runTest {
        val source = plan().copy(createdAt = "2026-01-31T16:00:00Z", dueDay = 1, totalCycles = 1)
        val jp = ready(); jp.put(source.toCloudRecord())
        assertEquals("2026-01-31T15:00:00Z", repo(jp).skipInstallment(owner, source, month, device, now).getOrThrow().scheduledDate)
        val vn = ready(); vn.put(source.toCloudRecord())
        assertEquals(InstallmentValidationError.NOT_SCHEDULED, reason(repo(vn, ZoneId.of("Asia/Ho_Chi_Minh")).skipInstallment(owner, source, month, device, now)))
    }
    @Test fun `timezone change during CAS retry cannot change the captured cycle calendar`() = runTest {
        val source = plan().copy(createdAt = "2026-01-31T16:00:00Z", dueDay = 1, totalCycles = 1)
        val s = ready(); s.put(source.toCloudRecord())
        var current = zone; var reads = 0
        val repository = OfflineInstallmentRepository(s) { reads++; current }
        s.beforeCommit = { current = ZoneId.of("Asia/Ho_Chi_Minh"); s.put(source.copy(syncVersion = Long.MAX_VALUE).toCloudRecord()) }
        val result = repository.skipInstallment(owner, source, month, device, now).getOrThrow()
        assertEquals(1, reads); assertEquals(2, s.attempts); assertEquals("2026-01-31T15:00:00Z", result.scheduledDate)
    }

    @Test fun `concurrent repository skip wins once and older callback ACK cannot rewrite its newer mutation`() = runTest {
        val s = ready(); val first = repo(s); val second = repo(s)
        var concurrent: DueOccurrenceRecord? = null
        s.beforeCommit = { concurrent = second.skipInstallment(owner, plan(), month, device, later).getOrThrow() }
        val result = first.skipInstallment(owner, plan(), month, device, now).getOrThrow()
        assertEquals(concurrent, result); assertEquals(later, result.updatedAt)
        assertEquals(1, s.successful); assertEquals(1, s.cycles().size)
        assertEquals(later, s.memory.outboxRows(owner.value).single().modifiedAt)
    }
    @Test fun `payment racing undo skip prevents tombstoning the newer paid occurrence`() = runTest {
        val skipped = occurrence(1, "skipped"); val s = ready(skipped.toCloudRecord())
        val paid = skipped.copy(statusWireValue = "paid", paidAt = later, linkedTransactionId = walletId, updatedAt = later, syncVersion = Long.MAX_VALUE)
        s.beforeCommit = { s.put(paid.toCloudRecord()) }
        assertEquals(InstallmentValidationError.SETTLED_CYCLE, reason(repo(s).undoInstallmentSkip(owner, plan(), month, device, now)))
        assertEquals(paid.toCloudRecord(), s.cycles().single()); assertEquals(0, s.successful)
        assertTrue(s.memory.outboxRows(owner.value).isEmpty())
    }

}
