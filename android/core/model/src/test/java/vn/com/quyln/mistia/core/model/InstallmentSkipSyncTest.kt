package vn.com.quyln.mistia.core.model

import java.time.ZoneId
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class InstallmentSkipSyncTest {
    private val owner = UserId("11111111-1111-1111-1111-111111111111")
    private val id = "22222222-2222-2222-2222-222222222222"
    private val child = "33333333-3333-3333-3333-333333333333"
    private val device = "44444444-4444-4444-4444-444444444444"
    private val other = "99999999-9999-9999-9999-999999999999"
    private val now = "2026-10-15T00:00:00Z"
    private val earlier = "2026-10-14T00:00:00Z"
    private val later = "2026-10-16T00:00:00Z"
    private val zone = ZoneId.of("Asia/Tokyo")
    private val plan = InstallmentPlanRecord(id, owner.value, "Loan", "mistia.plan.loan", 9007199254740993, 15, 12, 1, null, "JPY", false, earlier, earlier, null, 9007199254740995, device)
    private fun cycle(deleted: Boolean = false) = DueOccurrenceRecord(child, owner.value, "installment", id, "2026-10", now, null, "skipped", null, null, earlier, now, if (deleted) now else null, 9007199254740995, device)
    private fun queued(r: DueOccurrenceRecord) = QueuedMutation(r.pendingMutation(if (r.deletedAt == null) MutationKind.UPSERT else MutationKind.DELETE), 0, 0, null)
    private fun snapshot(c: DueOccurrenceRecord = cycle()) = InstallmentAcknowledgementSnapshot(owner, id, null,
        InstallmentAcknowledgementSnapshot.entities.associateWith { when (it) {
            CloudEntity.INSTALLMENT_PLAN -> listOf(plan.toCloudRecord()); CloudEntity.DUE_OCCURRENCE_RECORD -> listOf(c.toCloudRecord()); else -> emptyList()
        } }, listOf(queued(c)))
    private fun decide(c: DueOccurrenceRecord = cycle(), remote: DueOccurrenceRecord? = null, source: InstallmentPlanRecord? = plan, s: InstallmentAcknowledgementSnapshot = snapshot(c)) =
        planInstallmentSkipSync(s, queued(c), source?.toCloudRecord(), remote?.toCloudRecord(), zone)
    @Test fun `new skip creates only unlinked metadata with explicit nulls and exact Long version`() {
        val d = decide() as InstallmentSkipSyncDecision.Write
        assertNull(d.expectedVersion); assertEquals(9007199254740996, d.payload["sync_version"]!!.jsonPrimitive.long)
        listOf("paid_at", "linked_transaction_id", "amount_minor_snapshot", "deleted_at").forEach { assertEquals(JsonNull, d.payload[it]) }
        assertEquals("skipped", d.payload["status_raw_value"]!!.jsonPrimitive.content)
    }
    @Test fun `semantic same skip ACK accepts normalized dates and metadata only source ACK`() {
        val remote = cycle().copy(scheduledDate = "2026-10-15T09:00:00+09:00", syncVersion = 9007199254740996, updatedAt = later)
        val d = decide(remote = remote, source = plan.copy(syncVersion = 9007199254740996, updatedAt = later)) as InstallmentSkipSyncDecision.Acknowledge
        assertEquals(remote.toCloudRecord(), d.record)
    }
    @Test fun `owned unlinked pending at matching base can become skipped without a ledger write`() {
        val remote = cycle().copy(statusWireValue = "pending", amountMinorSnapshot = 1375, updatedAt = earlier)
        val d = decide(remote = remote) as InstallmentSkipSyncDecision.Write
        assertEquals(remote.syncVersion, d.expectedVersion); assertEquals(JsonNull, d.payload["amount_minor_snapshot"])
    }
    @Test fun `undo missing or already tombstoned skip acknowledges without recreation`() {
        val deleted = cycle(true)
        assertEquals(deleted.toCloudRecord(), (decide(c = deleted) as InstallmentSkipSyncDecision.Acknowledge).record)
        val remote = deleted.copy(updatedAt = later, deletedAt = later, syncVersion = 9007199254740996)
        assertEquals(remote.toCloudRecord(), (decide(c = deleted, remote = remote) as InstallmentSkipSyncDecision.Acknowledge).record)
    }
    @Test fun `undo uses metadata patch with explicit nonfinancial discriminator and exact CAS version`() {
        val remote = cycle().copy(updatedAt = earlier)
        val d = decide(c = cycle(true), remote = remote) as InstallmentSkipSyncDecision.Write
        assertEquals(remote.syncVersion, d.expectedVersion)
        assertEquals(setOf("id", "user_id", "source_kind_raw_value", "status_raw_value", "amount_minor_snapshot", "paid_at", "linked_transaction_id", "updated_at", "deleted_at", "sync_version", "last_modified_by_device_id"), d.payload.keys)
    }
    @Test fun `paid linked or financial remote state always holds including remote tombstone`() {
        val c = cycle()
        for (r in listOf(c.copy(statusWireValue = "paid"), c.copy(linkedTransactionId = other), c.copy(paidAt = now), c.copy(amountMinorSnapshot = 100), c.copy(statusWireValue = "paid", deletedAt = later)))
            for (local in listOf(c, cycle(true))) assertTrue(decide(local, r) is InstallmentSkipSyncDecision.Conflict)
    }
    @Test fun `pending source queue defers and unavailable archived or changed server source cannot be skipped`() {
        val c = cycle(); val s = snapshot().copy(queues = listOf(queued(c), QueuedMutation(PendingMutation(CloudEntity.INSTALLMENT_PLAN, id, owner.value, MutationKind.UPSERT, plan.toPayload(), now, plan.syncVersion, device), 0, 0, null)))
        assertTrue(decide(s = s) is InstallmentSkipSyncDecision.Deferred)
        for (p in listOf(null, plan.copy(isArchived = true), plan.copy(deletedAt = later))) assertTrue(decide(source = p) is InstallmentSkipSyncDecision.Conflict)
        assertTrue(decide(source = plan.copy(currencyCode = "VND")) is InstallmentSkipSyncDecision.Deferred)
        assertTrue(decide(source = plan.copy(dueDay = 20)) is InstallmentSkipSyncDecision.Deferred)
    }
    @Test fun `wrong owner source month or record identity is rejected before accepting any remote metadata`() {
        for (r in listOf(cycle().copy(ownerUserId = other), cycle().copy(id = other), cycle().copy(sourceId = other), cycle().copy(selectedMonthKey = "2026-11"), cycle().copy(sourceKindWireValue = "recurringBill")))
            assertTrue(runCatching { decide(remote = r) }.isFailure)
    }
    @Test fun `later remote skip or pending wins while unresolved same clock version payload remains a conflict`() {
        val remote = cycle().copy(scheduledDate = later, syncVersion = 9007199254740996, updatedAt = later)
        assertEquals(remote.toCloudRecord(), (decide(remote = remote) as InstallmentSkipSyncDecision.Acknowledge).record)
        assertTrue(decide(c = cycle().copy(syncVersion = 0), remote = cycle().copy(syncVersion = 0, scheduledDate = later)) is InstallmentSkipSyncDecision.Conflict)
    }
    @Test fun `local stale payload actor and unsupported paid intent cannot reach a write decision`() {
        val c = cycle()
        for (s in listOf(snapshot().copy(queues = listOf(queued(c).copy(mutation = queued(c).mutation.copy(deviceId = other)))),
            snapshot().copy(recordsByEntity = snapshot().recordsByEntity + (CloudEntity.DUE_OCCURRENCE_RECORD to listOf(c.copy(updatedAt = later).toCloudRecord())))))
            assertTrue(runCatching { decide(s = s) }.isFailure)
        assertTrue(runCatching { decide(c = c.copy(statusWireValue = "paid", linkedTransactionId = other)) }.isFailure)
    }
    @Test fun `overflowing sync version fails instead of wrapping version`() {
        val c = cycle().copy(syncVersion = Long.MAX_VALUE)
        assertTrue(runCatching { decide(c = c) }.isFailure)
    }
    @Test fun `undo does not delete a server cycle that has already returned to pending`() {
        val pending = cycle().copy(statusWireValue = "pending", amountMinorSnapshot = 1375)
        assertEquals(pending.toCloudRecord(), (decide(c = cycle(true), remote = pending) as InstallmentSkipSyncDecision.Acknowledge).record)
    }

    @Test fun `local financial sibling including tombstoned history holds ACK until ledger reconciliation`() {
        for (deleted in listOf(null, later)) {
            val sibling = cycle().copy(id = other, statusWireValue = "paid", amountMinorSnapshot = 1000, paidAt = now, linkedTransactionId = device, deletedAt = deleted)
            val s = snapshot().let { it.copy(recordsByEntity = it.recordsByEntity + (CloudEntity.DUE_OCCURRENCE_RECORD to (it.recordsByEntity.getValue(CloudEntity.DUE_OCCURRENCE_RECORD) + sibling.toCloudRecord()))) }
            assertTrue(decide(s = s, remote = cycle()) is InstallmentSkipSyncDecision.Conflict)
        }
    }

}
