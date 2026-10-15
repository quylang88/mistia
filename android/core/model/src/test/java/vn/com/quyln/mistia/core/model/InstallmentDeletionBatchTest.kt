package vn.com.quyln.mistia.core.model

import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class InstallmentDeletionBatchTest {
    private val owner = UserId("11111111-1111-1111-1111-111111111111")
    private val id = "22222222-2222-2222-2222-222222222222"
    private val device = "33333333-3333-3333-3333-333333333333"
    private val batchId = "44444444-4444-4444-4444-444444444444"
    private val other = "99999999-9999-9999-9999-999999999999"
    private val created = "2026-01-15T00:00:00Z"
    private val now = "2026-10-15T00:00:00Z"
    private val source = InstallmentPlanRecord(id, owner.value, "Loan", "mistia.plan.loan", 9007199254740993, 31, null, 1, null,
        "JPY", false, created, created, null, Long.MAX_VALUE, device).toCloudRecord()
    private fun due(index: Int, deleted: Boolean = false) = DueOccurrenceRecord("70000000-0000-0000-0000-${index.toString().padStart(12, '0')}",
        owner.value, "installment", id, "2026-01", created, 9007199254740993, "paid", created, other,
        created, if (deleted) now else created, if (deleted) now else null, 9007199254740995, device).toCloudRecord().let {
            it.copy(payload = JsonObject(it.payload + ("future" to JsonPrimitive("keep"))))
        }
    private fun snapshot(vararg cycles: CloudRecord) = InstallmentMutationSnapshot(owner, id, InstallmentMutationSnapshot.entities.associateWith {
        when (it) { CloudEntity.INSTALLMENT_PLAN -> listOf(source); CloudEntity.DUE_OCCURRENCE_RECORD -> cycles.toList(); else -> emptyList() }
    })
    private fun writes(s: InstallmentMutationSnapshot): List<Pair<CloudRecord, PendingMutation>> = (s.liveOccurrencesForDeletion() + source).map { before ->
        val payload = JsonObject(before.payload + mapOf("deleted_at" to JsonPrimitive(now), "updated_at" to JsonPrimitive(now), "last_modified_by_device_id" to JsonPrimitive(device)))
        val row = before.copy(payload = payload, deletedAt = now, updatedAt = now)
        row to PendingMutation(CloudEntity.fromTable(row.entity)!!, row.id, owner.value, MutationKind.DELETE, payload, now, row.syncVersion, device)
    }
    private fun queued(row: CloudRecord) = QueuedMutation(PendingMutation(CloudEntity.fromTable(row.entity)!!, row.id, owner.value, MutationKind.UPSERT,
        row.payload, row.updatedAt!!, row.syncVersion, device), 7, Long.MAX_VALUE, "http_503", true)
    private fun capture(s: InstallmentMutationSnapshot = snapshot(due(1)), queues: List<QueuedMutation> = emptyList()) =
        requireNotNull(InstallmentDeletionBatch.capture(s, writes(s), queues, batchId))
    private fun roundTrip(b: InstallmentDeletionBatch) = InstallmentDeletionBatch.fromJson(owner, id, Json.parseToJsonElement(b.toJson().toString()).jsonObject)
    private fun rejected(block: () -> Unit) { assertTrue(runCatching(block).isFailure) }

    @Test fun `explicit batch captures exact source and paid cycle before-images without changing ledger fields`() {
        val before = due(1); val batch = capture()
        assertEquals(batchId, batch.batchId); assertEquals(owner, batch.owner); assertEquals(id, batch.planId)
        assertEquals(source, batch.source.before); assertEquals(before, batch.cycles.single().before)
        assertEquals(MutationKind.DELETE, batch.cycles.single().deletion.kind)
        assertEquals(9007199254740993L, DueOccurrenceRecord.fromCloudRecord(batch.cycles.single().before).amountMinorSnapshot)
        assertEquals(other, DueOccurrenceRecord.fromCloudRecord(batch.cycles.single().before).linkedTransactionId)
        assertEquals(before.payload["future"], batch.cycles.single().deletion.payload!!["future"])
    }
    @Test fun `codec round trip retains unknown payload explicit null and exact Long versions`() {
        val batch = capture(); assertEquals(batch, roundTrip(batch))
        assertEquals(Long.MAX_VALUE, roundTrip(batch).source.deletion.baseVersion)
        assertEquals(JsonNull, roundTrip(batch).source.before.payload["total_cycles"])
        assertFalse(batch.source.deletion.payload!!.containsKey("batch_id"))
        assertFalse(batch.cycles.single().deletion.payload!!.containsKey("pending_before"))
    }
    @Test fun `previous source and child queues retain retry provenance and remote identity even at zero version`() {
        val row = due(1); val queues = listOf(queued(source), queued(row)); val batch = capture(queues = queues)
        assertEquals(queues[0], batch.source.pendingBefore); assertEquals(queues[1], batch.cycles.single().pendingBefore)
        assertEquals(batch, roundTrip(batch)); assertTrue(batch.cycles.single().remoteIdentityObservedBefore)
        val zero = row.copy(syncVersion = 0, payload = JsonObject(row.payload + ("sync_version" to JsonPrimitive(0))))
        val s = snapshot(zero); val q = queued(zero)
        val b = capture(s, listOf(q)); assertTrue(roundTrip(b).cycles.single().remoteIdentityObservedBefore)
        assertEquals(0L, roundTrip(b).cycles.single().pendingBefore!!.mutation.baseVersion)
    }
    @Test fun `clean observed zero version is retained without a fabricated prior queue`() {
        val row = due(1).copy(syncVersion = 0, payload = JsonObject(due(1).payload + ("sync_version" to JsonPrimitive(0))))
        val s = snapshot(row)
        val batch = InstallmentDeletionBatch.capture(s, writes(s), emptyList(), batchId, setOf(CloudEntity.DUE_OCCURRENCE_RECORD to row.id))!!
        assertNull(batch.cycles.single().pendingBefore); assertTrue(roundTrip(batch).cycles.single().remoteIdentityObservedBefore)
    }
    @Test fun `same clock and device on an earlier undo tombstone never establishes batch membership`() {
        val existingUndo = due(2, deleted = true); val s = snapshot(due(1), existingUndo)
        val batch = capture(s)
        assertEquals(listOf(due(1).id), batch.cycles.map { it.before.id })
        assertFalse(batch.cycles.any { it.before.id == existingUndo.id })
    }
    @Test fun `unrelated kinds foreign payloads and aliases remain outside captured source deletion`() {
        val unrelated = due(2).copy(payload = JsonObject(due(2).payload + ("source_kind_raw_value" to JsonPrimitive("recurringBill"))))
        val foreign = due(3).copy(payload = JsonObject(due(3).payload + ("user_id" to JsonPrimitive(other))))
        val alias = due(4).copy(id = other)
        assertEquals(listOf(due(1).id), capture(snapshot(due(1), unrelated, foreign, alias)).cycles.map { it.before.id })
    }
    @Test fun `independent source deletion does not create an empty causal batch`() {
        val s = snapshot(); assertNull(InstallmentDeletionBatch.capture(s, writes(s), emptyList(), batchId))
    }
    @Test fun `wrong previous queue owner actor identity base payload or delete kind is rejected`() {
        val original = queued(due(1))
        for (q in listOf(original.copy(mutation = original.mutation.copy(subjectUserId = other)),
            original.copy(mutation = original.mutation.copy(recordId = other)), original.copy(mutation = original.mutation.copy(deviceId = other)), original.copy(mutation = original.mutation.copy(baseVersion = 1)),
            original.copy(mutation = original.mutation.copy(payload = JsonObject(emptyMap()))), original.copy(mutation = original.mutation.copy(kind = MutationKind.DELETE)))) {
            rejected { capture(queues = listOf(q)) }
        }
    }
    @Test fun `omitted child deletion and changed frozen paid amount cannot be captured as valid provenance`() {
        val s = snapshot(due(1), due(2)); val w = writes(s)
        rejected { InstallmentDeletionBatch.capture(s, w.drop(1), emptyList(), batchId) }
        val changed = w.first().let { (row, mutation) ->
            val p = JsonObject(row.payload + ("amount_minor_snapshot" to JsonPrimitive(1)))
            row.copy(payload = p) to mutation.copy(payload = p)
        }
        rejected { InstallmentDeletionBatch.capture(s, listOf(changed) + w.drop(1), emptyList(), batchId) }
    }
    @Test fun `restoration requires matching owner plan canonical batch ID and supported format`() {
        val b = capture(); val p = b.toJson()
        rejected { InstallmentDeletionBatch.fromJson(UserId(other), id, p) }
        rejected { InstallmentDeletionBatch.fromJson(owner, other, p) }
        rejected { InstallmentDeletionBatch.fromJson(owner, id, JsonObject(p + ("format_version" to JsonPrimitive(99)))) }
        rejected { InstallmentDeletionBatch.capture(snapshot(due(1)), writes(snapshot(due(1))), emptyList(), "4-4-4-4-4") }
    }
    @Test fun `manifest rejects missing or duplicate child entries and invalid scalar representation`() {
        val p = capture(snapshot(due(1), due(2))).toJson(); val entries = p.getValue("cycles").jsonArray
        rejected { InstallmentDeletionBatch.fromJson(owner, id, JsonObject(p + ("cycles" to JsonArray(entries.take(1))))) }
        rejected { InstallmentDeletionBatch.fromJson(owner, id, JsonObject(p + ("cycles" to JsonArray(listOf(entries[0], entries[0]))))) }
        rejected { InstallmentDeletionBatch.fromJson(owner, id, JsonObject(p + ("format_version" to JsonPrimitive("1")))) }
    }
    @Test fun `negative retry metadata and unrelated queue cannot contaminate causal snapshot`() {
        rejected { capture(queues = listOf(queued(due(1)).copy(attemptCount = -1))) }
        rejected { capture(queues = listOf(queued(due(2)))) }
    }
    @Test fun `large causal payload round trips with bounded individual storage values`() {
        val before = due(1).let { it.copy(payload = JsonObject(it.payload + ("future" to JsonPrimitive("界".repeat(250000))))) }
        val batch = capture(snapshot(before), listOf(queued(before)))
        val blob = InstallmentDeletionStorage.pack(batch)
        assertTrue(blob.chunks.sumOf { it.bytes.size } > 2 * 1024 * 1024)
        assertTrue(blob.chunks.size > 1); assertTrue(blob.chunks.all { it.bytes.size in 1..InstallmentDeletionStorage.CHUNK_BYTES })
        assertEquals(batch, InstallmentDeletionStorage.unpack(owner, id, batchId, blob))
    }
    @Test fun `chunk manifest rejects missing duplicate corrupted data and accepts reordered exact indices`() {
        val batch = capture(); val blob = InstallmentDeletionStorage.pack(batch)
        assertEquals(batch, InstallmentDeletionStorage.unpack(owner, id, batchId, blob.copy(chunks = blob.chunks.reversed())))
        rejected { InstallmentDeletionStorage.unpack(owner, id, batchId, blob.copy(chunks = emptyList())) }
        rejected { InstallmentDeletionStorage.unpack(owner, id, batchId, blob.copy(chunks = blob.chunks + blob.chunks.first())) }
        val corrupted = blob.chunks.first().bytes.copyOf().apply { this[0] = (this[0].toInt() xor 1).toByte() }
        rejected { InstallmentDeletionStorage.unpack(owner, id, batchId, blob.copy(chunks = listOf(InstallmentDeletionChunk(0, corrupted)) + blob.chunks.drop(1))) }
    }
    @Test fun `stored chunks bind source batch owner identity and strict header scalar types`() {
        val blob = InstallmentDeletionStorage.pack(capture())
        rejected { InstallmentDeletionStorage.unpack(UserId(other), id, batchId, blob) }
        rejected { InstallmentDeletionStorage.unpack(owner, other, batchId, blob) }
        rejected { InstallmentDeletionStorage.unpack(owner, id, other, blob) }
        for ((key, value) in listOf("format_version" to JsonPrimitive(99), "chunk_count" to JsonPrimitive("1"), "byte_count" to JsonPrimitive(Long.MAX_VALUE), "sha256" to JsonPrimitive("bad"))) {
            rejected { InstallmentDeletionStorage.unpack(owner, id, batchId, blob.copy(header = JsonObject(blob.header + (key to value)))) }
        }
    }
    @Test fun `chunk indices and individual size cannot be silently normalized`() {
        val blob = InstallmentDeletionStorage.pack(capture()); val first = blob.chunks.first()
        rejected { InstallmentDeletionStorage.unpack(owner, id, batchId, blob.copy(chunks = listOf(first.copy(index = -1)))) }
        rejected { InstallmentDeletionStorage.unpack(owner, id, batchId, blob.copy(chunks = listOf(first.copy(bytes = ByteArray(0))))) }
        rejected { InstallmentDeletionStorage.unpack(owner, id, batchId, blob.copy(chunks = listOf(first.copy(bytes = ByteArray(InstallmentDeletionStorage.CHUNK_BYTES + 1))))) }
    }

}
