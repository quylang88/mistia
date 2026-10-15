package vn.com.quyln.mistia.core.model

import java.time.Instant
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class InstallmentDeletionCompletionTest {
    private val owner = UserId("11111111-1111-1111-1111-111111111111")
    private val id = "22222222-2222-2222-2222-222222222222"
    private val device = "33333333-3333-3333-3333-333333333333"
    private val wallet = "44444444-4444-4444-4444-444444444444"
    private val tx = "55555555-5555-5555-5555-555555555555"
    private val child = "77777777-7777-7777-7777-777777777777"
    private val other = "99999999-9999-9999-9999-999999999999"
    private val created = "2026-01-15T00:00:00Z"
    private val deleted = "2026-10-15T00:00:00Z"
    private val later = "2026-10-16T00:00:00Z"
    private val now = "2026-10-17T00:00:00Z"
    private val plan = InstallmentPlanRecord(id, owner.value, "Loan", "mistia.plan.loan", 1000, 15, null, 1, wallet, "JPY", false,
        created, created, null, 3, device).toCloudRecord()
    private fun cycle(status: String = "paid", linked: String? = tx) = DueOccurrenceRecord(child, owner.value, "installment", id,
        "2026-01", created, 1000, status, if (status == "paid") created else null, linked, created, created, null, 5, device).toCloudRecord()
    private fun tombstone(r: CloudRecord) = r.copy(updatedAt = deleted, deletedAt = deleted, payload = JsonObject(r.payload + mapOf(
        "updated_at" to JsonPrimitive(deleted), "deleted_at" to JsonPrimitive(deleted), "last_modified_by_device_id" to JsonPrimitive(device))))
    private fun queued(r: CloudRecord) = QueuedMutation(PendingMutation(CloudEntity.fromTable(r.entity)!!, r.id, owner.value,
        if (r.deletedAt == null) MutationKind.UPSERT else MutationKind.DELETE, r.payload, r.updatedAt!!, r.syncVersion, device), 0, 0, null, true)
    private fun ledger(amount: Long = 1000, time: String = created) = CloudRecord(CloudEntity.LEDGER_TRANSACTION.table, tx, owner.value,
        buildJsonObject { put("id", tx); put("user_id", owner.value); put("primary_kind_raw_value", "expense"); put("entry_status_raw_value", "posted")
            put("title", "Loan payment"); put("amount_minor", amount); put("source_currency_code", "JPY"); put("source_wallet_id", wallet)
            put("occurred_at", created); put("created_at", created); put("updated_at", time); put("deleted_at", JsonNull); put("is_archived", false)
            put("sync_version", 11); put("created_by_user_id", owner.value); put("last_modified_by_user_id", owner.value); put("last_modified_by_device_id", device) }, time, null, 11)
    private fun snapshot(before: CloudRecord = cycle(), prior: QueuedMutation? = null, source: CloudRecord = plan): InstallmentAcknowledgementSnapshot {
        val original = InstallmentMutationSnapshot(owner, id, InstallmentMutationSnapshot.entities.associateWith {
            when (it) { CloudEntity.INSTALLMENT_PLAN -> listOf(source); CloudEntity.DUE_OCCURRENCE_RECORD -> listOf(before); else -> emptyList() }
        })
        val deletedRows = listOf(source, before).map(::tombstone)
        val writes = deletedRows.map { it to queued(it).mutation }
        val batch = InstallmentDeletionBatch.capture(original, writes, listOfNotNull(prior), wallet)!!
        return InstallmentAcknowledgementSnapshot(owner, id, batch, InstallmentAcknowledgementSnapshot.entities.associateWith {
            when (it) { CloudEntity.INSTALLMENT_PLAN -> listOf(deletedRows[0]); CloudEntity.DUE_OCCURRENCE_RECORD -> listOf(deletedRows[1]); else -> listOf(ledger()) }
        }, deletedRows.map(::queued))
    }
    private val millis get() = Instant.parse(now).toEpochMilli()
    private fun acknowledged() = snapshot().let { it.copy(queues = it.queues.filterNot { q -> q.mutation.entity == CloudEntity.INSTALLMENT_PLAN }) }
    private fun decide(s: InstallmentAcknowledgementSnapshot = acknowledged(), source: CloudRecord? = tombstone(plan), cycles: Map<String, CloudRecord?> = mapOf(child to tombstone(cycle()))) =
        planInstallmentDeletionCompletion(s, source, cycles, millis)
    private fun rejects(block: () -> Unit) { assertTrue(runCatching(block).isFailure) }
    @Test fun `source queue must finish before child batch can complete`() {
        assertTrue(decide(snapshot(), cycles = emptyMap()) is InstallmentDeletionCompletion.Deferred)
    }
    @Test fun `missing causal batch is held without guessing from clocks`() {
        assertTrue(decide(acknowledged().copy(batch = null), cycles = emptyMap()) is InstallmentDeletionCompletion.Deferred)
    }
    @Test fun `active remote source remains held for deliberate history reconciliation`() {
        assertTrue(decide(source = plan, cycles = emptyMap()) is InstallmentDeletionCompletion.Conflict)
    }
    @Test fun `required child reads distinguish not fetched from confirmed absence`() {
        assertEquals(InstallmentDeletionCompletion.NeedCycles(setOf(child)), decide(cycles = emptyMap()))
        val result = decide(source = null, cycles = mapOf(child to null)) as InstallmentDeletionCompletion.Ready
        assertEquals(tombstone(cycle()), result.cycles.single()); assertNotNull(result.source.deletedAt)
    }
    @Test fun `authoritative deleted child is acknowledged without removing its live expense`() {
        val s = acknowledged(); val result = decide(s) as InstallmentDeletionCompletion.Ready
        assertEquals(listOf(tombstone(cycle())), result.cycles)
        assertEquals(listOf(ledger()), s.recordsByEntity.getValue(CloudEntity.LEDGER_TRANSACTION))
    }
    @Test fun `same base active paid child needs only a sparse metadata delete`() {
        val result = decide(cycles = mapOf(child to cycle())) as InstallmentDeletionCompletion.NeedDeletes
        val q = result.mutations.single()
        assertEquals(MutationKind.DELETE, q.kind); assertEquals(5L, q.baseVersion)
        assertEquals(setOf("id", "user_id", "updated_at", "deleted_at", "sync_version", "last_modified_by_device_id", "source_kind_raw_value"), q.payload!!.keys)
        assertEquals(JsonPrimitive(6), q.payload!!["sync_version"]); assertEquals(JsonPrimitive(deleted), q.payload!!["deleted_at"])
        assertFalse(q.payload!!.containsKey("linked_transaction_id")); assertFalse(q.payload!!.containsKey("amount_minor_snapshot"))
    }
    @Test fun `remote later child winner stays intact beneath the deleted source`() {
        val server = DueOccurrenceRecord.fromCloudRecord(cycle()).copy(updatedAt = later, syncVersion = 6, amountMinorSnapshot = 800).toCloudRecord()
        val result = decide(cycles = mapOf(child to server)) as InstallmentDeletionCompletion.Ready
        assertEquals(server, result.cycles.single())
    }
    @Test fun `local delete winner uses current exact remote Long version`() {
        val version = 9007199254740993L
        val server = DueOccurrenceRecord.fromCloudRecord(cycle()).copy(syncVersion = version).toCloudRecord()
        val q = (decide(cycles = mapOf(child to server)) as InstallmentDeletionCompletion.NeedDeletes).mutations.single()
        assertEquals(version, q.baseVersion); assertEquals(JsonPrimitive(version + 1), q.payload!!["sync_version"])
    }
    @Test fun `overflow rejects before a wrapped version can be sent`() {
        val server = DueOccurrenceRecord.fromCloudRecord(cycle()).copy(syncVersion = Long.MAX_VALUE).toCloudRecord()
        rejects { decide(cycles = mapOf(child to server)) }
    }
    @Test fun `newer child mutation remains outside the completed batch write set`() {
        val s = acknowledged(); val newer = DueOccurrenceRecord.fromCloudRecord(cycle()).copy(updatedAt = later).toCloudRecord()
        val changed = s.copy(recordsByEntity = s.recordsByEntity + (CloudEntity.DUE_OCCURRENCE_RECORD to listOf(newer)), queues = listOf(queued(newer)))
        assertTrue((decide(changed, cycles = emptyMap()) as InstallmentDeletionCompletion.Ready).cycles.isEmpty())
    }
    @Test fun `missing exact causal child queue is a conflict rather than a clean completion`() {
        assertTrue(decide(acknowledged().copy(queues = emptyList()), cycles = emptyMap()) is InstallmentDeletionCompletion.Conflict)
    }
    @Test fun `missing causal local child is a conflict rather than a remote repair guess`() {
        val s = acknowledged().let { it.copy(recordsByEntity = it.recordsByEntity + (CloudEntity.DUE_OCCURRENCE_RECORD to emptyList())) }
        assertTrue(decide(s, cycles = emptyMap()) is InstallmentDeletionCompletion.Conflict)
    }
    @Test fun `blocked or not yet due child retries defer the whole atomic completion`() {
        val s = acknowledged(); val q = s.queues.single()
        for (time in listOf(millis + 1, Long.MAX_VALUE)) assertTrue(decide(s.copy(queues = listOf(q.copy(nextAttemptAtEpochMillis = time))), cycles = emptyMap()) is InstallmentDeletionCompletion.Deferred)
    }
    @Test fun `foreign source child and moved child identity fail closed`() {
        rejects { decide(source = tombstone(plan).copy(ownerUserId = other)) }
        rejects { decide(cycles = mapOf(child to tombstone(cycle()).copy(ownerUserId = other))) }
        rejects { decide(cycles = mapOf(child to DueOccurrenceRecord.fromCloudRecord(cycle()).copy(selectedMonthKey = "2026-02").toCloudRecord())) }
        rejects { decide(cycles = mapOf(child to DueOccurrenceRecord.fromCloudRecord(cycle()).copy(sourceId = other).toCloudRecord())) }
    }
    @Test fun `local child queue must match raw payload base clock and actor`() {
        val s = acknowledged(); val q = s.queues.single()
        for (changed in listOf(q.copy(mutation = q.mutation.copy(payload = cycle().payload)), q.copy(mutation = q.mutation.copy(deviceId = other))))
            rejects { decide(s.copy(queues = listOf(changed)), cycles = emptyMap()) }
    }
    @Test fun `extra remote responses and version envelope mismatches are rejected`() {
        rejects { decide(cycles = mapOf(other to null)) }
        rejects { decide(cycles = mapOf(child to tombstone(cycle()).copy(syncVersion = 99))) }
    }
}
