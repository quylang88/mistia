package vn.com.quyln.mistia.core.model

import java.time.YearMonth
import java.time.ZoneId
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class InstallmentCyclePolicyTest {
    private val owner = UserId("11111111-1111-1111-1111-111111111111")
    private val id = "22222222-2222-2222-2222-222222222222"
    private val device = "33333333-3333-3333-3333-333333333333"
    private val created = "2026-01-15T00:00:00Z"
    private val now = "2026-02-14T00:00:00Z"
    private val plan = InstallmentPlanRecord(id, owner.value, "Loan", "mistia.plan.loan", 9007199254740993, 31, null, 1, null, "JPY",
        false, created, created, null, Long.MAX_VALUE, device)
    private fun due(index: Int, status: String = "pending") = DueOccurrenceRecord("70000000-0000-0000-0000-${index.toString().padStart(12, '0')}",
        owner.value, "installment", id, "2026-02", created, 9007199254740993, status, null, null, created, created, null, Long.MAX_VALUE, device)
    private fun snapshot(action: InstallmentCycleAction, vararg rows: CloudRecord) = InstallmentCycleSnapshot(
        InstallmentMutationSnapshot(owner, id, InstallmentMutationSnapshot.entities.associateWith { entity -> when (entity) {
            CloudEntity.INSTALLMENT_PLAN -> listOf(plan.toCloudRecord())
            CloudEntity.DUE_OCCURRENCE_RECORD -> rows.toList()
            else -> emptyList()
        } }), plan, YearMonth.of(2026, 2), ZoneId.of("Asia/Tokyo"), action)
    private fun writes(snapshot: InstallmentCycleSnapshot) = snapshot.buildMutations(device, device, now)
    private fun rejects(snapshot: InstallmentCycleSnapshot, writes: List<Pair<CloudRecord, PendingMutation>>) {
        assertTrue(runCatching { snapshot.requireValidMutations(writes) }.isFailure)
    }
    @Test fun `valid full duplicate skip permits order changes but rejects omissions duplicate writes and unrelated entities`() {
        val s = snapshot(InstallmentCycleAction.SKIP, due(1).toCloudRecord(), due(2).toCloudRecord()); val w = writes(s)
        s.requireValidMutations(w.reversed()); assertEquals(2, w.size)
        rejects(s, emptyList()); rejects(s, w.take(1)); rejects(s, w + w.first())
        rejects(s, w + (plan.toCloudRecord() to w.first().second.copy(entity = CloudEntity.INSTALLMENT_PLAN)))
        rejects(s, w.map { it.first.copy(entity = CloudEntity.LEDGER_TRANSACTION.table) to it.second })
    }
    @Test fun `altered base actor payload clock and frozen fields are rejected without rounding Long`() {
        val raw = due(1).toCloudRecord().copy(payload = JsonObject(due(1).toPayload() + ("future" to JsonPrimitive("keep"))))
        val s = snapshot(InstallmentCycleAction.SKIP, raw); val pair = writes(s).single()
        assertEquals(Long.MAX_VALUE, pair.second.baseVersion); s.requireValidMutations(listOf(pair))
        listOf("created_at" to JsonPrimitive(now), "sync_version" to JsonPrimitive(1), "future" to JsonNull,
            "user_id" to JsonPrimitive(device), "source_kind_raw_value" to JsonPrimitive("recurringBill"),
            "amount_minor_snapshot" to JsonPrimitive(500)).forEach { (key, value) ->
            val payload = JsonObject(pair.first.payload + (key to value))
            rejects(s, listOf(pair.first.copy(payload = payload) to pair.second.copy(payload = payload)))
        }
        rejects(s, listOf(pair.first to pair.second.copy(baseVersion = 1)))
        rejects(s, listOf(pair.first to pair.second.copy(deviceId = owner.value)))
        rejects(s, listOf(pair.first to pair.second.copy(modifiedAt = created)))
        rejects(s, listOf(pair.first.copy(syncVersion = 1) to pair.second))
    }
    @Test fun `undo is restricted to every skipped tombstone and preserves frozen paid fields and amounts`() {
        val s = snapshot(InstallmentCycleAction.UNDO_SKIP, due(1, "skipped").toCloudRecord(), due(2, "skipped").toCloudRecord(), due(3).toCloudRecord())
        val w = writes(s); s.requireValidMutations(w)
        assertEquals(2, w.size); assertTrue(w.all { it.second.kind == MutationKind.DELETE && it.first.deletedAt == now })
        assertEquals(9007199254740993L, DueOccurrenceRecord.fromCloudRecord(w.first().first).amountMinorSnapshot)
        rejects(s, w.take(1))
        val first = w.first(); val payload = JsonObject(first.first.payload + ("amount_minor_snapshot" to JsonNull))
        rejects(s, listOf(first.first.copy(payload = payload) to first.second.copy(payload = payload)) + w.drop(1))
    }
    @Test fun `new cycle cannot reuse an existing tombstone or a foreign alias UUID`() {
        val old = due(1).copy(deletedAt = created).toCloudRecord()
        val s = snapshot(InstallmentCycleAction.SKIP, old)
        assertTrue(runCatching { s.buildMutations(old.id, device, now) }.isFailure)
        val alias = old.copy(id = device)
        assertTrue(runCatching { snapshot(InstallmentCycleAction.SKIP, alias).buildMutations(device, device, now) }.isFailure)
    }
    @Test fun `incomplete or foreign table snapshot and mismatched source version fail closed`() {
        val s = snapshot(InstallmentCycleAction.SKIP)
        assertTrue(runCatching { writes(s.copy(base = s.base.copy(recordsByEntity = emptyMap()))) }.isFailure)
        val changed = s.base.recordsByEntity.toMutableMap().apply { put(CloudEntity.INSTALLMENT_PLAN, listOf(plan.toCloudRecord().copy(syncVersion = 1))) }
        assertTrue(runCatching { writes(s.copy(base = s.base.copy(recordsByEntity = changed))) }.isFailure)
        val foreign = s.base.recordsByEntity.toMutableMap().apply { put(CloudEntity.LEDGER_WALLET, listOf(plan.toCloudRecord().copy(ownerUserId = device))) }
        assertTrue(runCatching { writes(s.copy(base = s.base.copy(recordsByEntity = foreign))) }.isFailure)
    }
}
