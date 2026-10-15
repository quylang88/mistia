package vn.com.quyln.mistia.core.model

import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class InstallmentSourceAcknowledgementTest {
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
    private fun remotePlan() = plan.copy(updatedAt = later, syncVersion = 4, payload = JsonObject(plan.payload + mapOf("name" to JsonPrimitive("Remote"), "updated_at" to JsonPrimitive(later), "sync_version" to JsonPrimitive(4))))
    private fun remoteCycle() = cycle().copy(updatedAt = later, syncVersion = 6, payload = JsonObject(cycle().payload + mapOf("updated_at" to JsonPrimitive(later), "sync_version" to JsonPrimitive(6))))
    private fun root(s: InstallmentAcknowledgementSnapshot) = s.queues.single { it.mutation.entity == CloudEntity.INSTALLMENT_PLAN }
    private fun decide(s: InstallmentAcknowledgementSnapshot = snapshot(), remote: CloudRecord = remotePlan(), cycles: Map<String, CloudRecord?> = mapOf(child to remoteCycle()),
        ledgers: Map<String, CloudRecord?> = mapOf(tx to ledger()), q: QueuedMutation = root(s)) = planInstallmentSourceAcknowledgement(s, q, remote, cycles, ledgers, now)
    private fun ready(d: InstallmentSourceAckDecision) = (d as InstallmentSourceAckDecision.Ready)
    private fun rejects(block: () -> Unit) { assertTrue(runCatching(block).isFailure) }

    @Test fun `remote active source and owned paid cycle ACK together without a ledger write`() {
        val result = ready(decide()); assertEquals(remotePlan(), result.source); assertTrue(result.clearBatch)
        assertEquals(listOf(remoteCycle()), result.cycles.map { it.record }); assertNull(result.cycles.single().queue)
    }
    @Test fun `required cycle and ledger reads distinguish confirmed absence from not fetched`() {
        val s = snapshot()
        assertEquals(InstallmentSourceAckDecision.NeedCycles(setOf(child)), decide(s, cycles = emptyMap(), ledgers = emptyMap()))
        assertEquals(InstallmentSourceAckDecision.NeedLedger(setOf(tx)), decide(s, ledgers = emptyMap()))
    }
    @Test fun `deleted authoritative source ACK keeps pending child intent and durable batch`() {
        val result = ready(decide(remote = tombstone(remotePlan()), cycles = emptyMap(), ledgers = emptyMap()))
        assertFalse(result.clearBatch); assertTrue(result.cycles.isEmpty()); assertNotNull(result.source.deletedAt)
    }
    @Test fun `later child mutation is preserved without fetching or restoring it`() {
        val s = snapshot(); val newer = cycle().copy(updatedAt = later, payload = JsonObject(cycle().payload + ("updated_at" to JsonPrimitive(later))))
        val changed = s.copy(recordsByEntity = s.recordsByEntity + (CloudEntity.DUE_OCCURRENCE_RECORD to listOf(newer)),
            queues = s.queues.filterNot { it.mutation.recordId == child } + queued(newer))
        val result = ready(decide(changed, cycles = emptyMap(), ledgers = emptyMap()))
        assertTrue(result.clearBatch); assertTrue(result.cycles.isEmpty())
    }
    @Test fun `late source response cannot consume a newer source queue`() {
        val s = snapshot(); val old = root(s); val newQueue = old.copy(mutation = old.mutation.copy(modifiedAt = later))
        assertEquals(InstallmentSourceAckDecision.Stale, decide(s.copy(queues = s.queues.filterNot { it == old } + newQueue), q = old))
    }
    @Test fun `prior local child winner restores its exact retry and observed identity metadata`() {
        val before = cycle().copy(updatedAt = later, payload = JsonObject(cycle().payload + ("updated_at" to JsonPrimitive(later))))
        val prior = queued(before).copy(attemptCount = 7, nextAttemptAtEpochMillis = Long.MAX_VALUE, lastError = "http_503")
        val s = snapshot(before, prior)
        val remote = cycle("pending", null)
        val action = ready(decide(s, cycles = mapOf(child to remote))).cycles.single()
        assertEquals(before, action.record); assertEquals(prior, action.queue)
    }
    @Test fun `later remote child winner cancels the old prior pending intent`() {
        val before = cycle(); val prior = queued(before); val s = snapshot(before, prior)
        val remote = remoteCycle().copy(payload = JsonObject(remoteCycle().payload + ("amount_minor_snapshot" to JsonPrimitive(500))))
        val action = ready(decide(s, cycles = mapOf(child to remote))).cycles.single()
        assertEquals(remote, action.record); assertNull(action.queue)
    }
    @Test fun `missing remote paid cycle restores frozen history as a metadata repair mutation`() {
        val s = snapshot(); val action = ready(decide(s, cycles = mapOf(child to null))).cycles.single()
        val decoded = DueOccurrenceRecord.fromCloudRecord(action.record)
        assertEquals(DueStatus.PAID, decoded.status); assertEquals(1000L, decoded.amountMinorSnapshot); assertEquals(tx, decoded.linkedTransactionId)
        assertEquals(now, decoded.updatedAt); assertEquals(5L, action.queue!!.mutation.baseVersion); assertEquals(MutationKind.UPSERT, action.queue!!.mutation.kind)
        assertTrue(action.queue!!.remoteIdentityObserved)
    }
    @Test fun `same clock version different child business remains an unresolved conflict`() {
        val before = cycle(); val s = snapshot(before, queued(before))
        val changed = before.copy(payload = JsonObject(before.payload + ("amount_minor_snapshot" to JsonPrimitive(500))))
        assertTrue(decide(s, cycles = mapOf(child to changed), ledgers = emptyMap()) is InstallmentSourceAckDecision.Conflict)
    }
    @Test fun `ledger drift defers ACK until normal pull refreshes the local footprint`() {
        assertTrue(decide(ledgers = mapOf(tx to ledger(900))) is InstallmentSourceAckDecision.Deferred)
        val s = snapshot().let { it.copy(recordsByEntity = it.recordsByEntity + (CloudEntity.LEDGER_TRANSACTION to listOf(ledger(900)))) }
        assertTrue(decide(s, ledgers = mapOf(tx to ledger(900))) is InstallmentSourceAckDecision.Ready)
    }
    @Test fun `missing or deleted financial footprint cannot silently expose paid marker`() {
        val empty = snapshot().let { it.copy(recordsByEntity = it.recordsByEntity + (CloudEntity.LEDGER_TRANSACTION to emptyList())) }
        assertTrue(decide(empty, ledgers = mapOf(tx to null)) is InstallmentSourceAckDecision.Conflict)
        val gone = tombstone(ledger())
        val s = snapshot().let { it.copy(recordsByEntity = it.recordsByEntity + (CloudEntity.LEDGER_TRANSACTION to listOf(gone))) }
        assertTrue(decide(s, ledgers = mapOf(tx to gone)) is InstallmentSourceAckDecision.Conflict)
    }
    @Test fun `deleted cycle with a live posted expense cannot hide paid history under active source`() {
        assertTrue(decide(cycles = mapOf(child to tombstone(remoteCycle()))) is InstallmentSourceAckDecision.Conflict)
    }
    @Test fun `foreign source cycle ledger and moved month are rejected`() {
        rejects { decide(remote = remotePlan().copy(ownerUserId = other)) }
        rejects { decide(cycles = mapOf(child to remoteCycle().copy(ownerUserId = other))) }
        rejects { decide(ledgers = mapOf(tx to ledger().copy(ownerUserId = other))) }
        rejects { decide(cycles = mapOf(child to remoteCycle().let { it.copy(payload = JsonObject(it.payload + ("selected_month_key" to JsonPrimitive("2026-02")))) })) }
    }
    @Test fun `source currency and creation anchor changes are conflicts rather than reinterpretations`() {
        for ((field, value) in listOf("currency_code" to "USD", "created_at" to later)) {
            assertTrue(decide(remote = remotePlan().let { it.copy(payload = JsonObject(it.payload + (field to JsonPrimitive(value)))) }) is InstallmentSourceAckDecision.Conflict)
        }
    }
    @Test fun `batch identity queue retry and ledger changes invalidate the complete CAS snapshot`() {
        val s = snapshot(); s.requireUnchanged(s)
        rejects { s.requireUnchanged(s.copy(batch = s.batch!!.copy(batchId = other))) }
        rejects { s.requireUnchanged(s.copy(queues = s.queues.map { it.copy(attemptCount = 1) })) }
        rejects { s.requireUnchanged(s.copy(recordsByEntity = s.recordsByEntity + (CloudEntity.LEDGER_TRANSACTION to emptyList()))) }
    }
    @Test fun `legacy source delete without causal proof remains deferred`() {
        assertTrue(decide(snapshot().copy(batch = null), cycles = emptyMap(), ledgers = emptyMap()) is InstallmentSourceAckDecision.Deferred)
    }
    @Test fun `unrelated earlier undo remains untouched despite identical delete clock and actor`() {
        val s = snapshot(); val independent = tombstone(cycle("skipped", null).copy(id = other, payload = JsonObject(cycle("skipped", null).payload + ("id" to JsonPrimitive(other)))))
        val state = s.copy(recordsByEntity = s.recordsByEntity + (CloudEntity.DUE_OCCURRENCE_RECORD to (s.recordsByEntity.getValue(CloudEntity.DUE_OCCURRENCE_RECORD) + independent)),
            queues = s.queues + queued(independent))
        assertEquals(listOf(child), ready(decide(state)).cycles.map { it.record.id })
    }
    @Test fun `legacy paid nil and zero snapshots remain exact without a fabricated ledger link`() {
        for (amount in listOf<JsonElement>(JsonNull, JsonPrimitive(0))) {
            val before = cycle(linked = null).let { it.copy(payload = JsonObject(it.payload + ("amount_minor_snapshot" to amount))) }
            val action = ready(decide(snapshot(before), cycles = mapOf(child to null), ledgers = emptyMap())).cycles.single()
            assertEquals(amount, action.record.payload["amount_minor_snapshot"]); assertSame(JsonNull, action.record.payload["linked_transaction_id"])
        }
    }
    @Test fun `database microsecond representation of creation time is accepted without accepting a real anchor edit`() {
        val source = plan.copy(payload = JsonObject(plan.payload + ("created_at" to JsonPrimitive("2026-01-15T00:00:00.123456789Z"))))
        val s = snapshot(source = source)
        for (stamp in listOf("2026-01-15T00:00:00.123456Z", "2026-01-15T00:00:00.123457Z")) {
            val remote = remotePlan().let { it.copy(payload = JsonObject(it.payload + ("created_at" to JsonPrimitive(stamp)))) }
            assertTrue(decide(s, remote = remote) is InstallmentSourceAckDecision.Ready)
        }
        val edited = remotePlan().let { it.copy(payload = JsonObject(it.payload + ("created_at" to JsonPrimitive("2026-01-15T00:00:00.123455Z")))) }
        assertTrue(decide(s, remote = edited) is InstallmentSourceAckDecision.Conflict)
    }

    @Test fun `valid pending local posted expense proves footprint before its remote creation`() {
        val s = snapshot(); val current = ledger(900)
        val owned = s.copy(recordsByEntity = s.recordsByEntity + (CloudEntity.LEDGER_TRANSACTION to listOf(current)), queues = s.queues + queued(current))
        assertTrue(decide(owned, ledgers = mapOf(tx to null)) is InstallmentSourceAckDecision.Ready)
    }
    @Test fun `pending ledger proof must match its version clock and actor`() {
        val s = snapshot(); val current = ledger(); val pending = queued(current)
        for (q in listOf(pending.copy(mutation = pending.mutation.copy(baseVersion = 99)),
            pending.copy(mutation = pending.mutation.copy(modifiedAt = later)), pending.copy(mutation = pending.mutation.copy(deviceId = other)))) {
            rejects { decide(s.copy(queues = s.queues + q), ledgers = mapOf(tx to null)) }
        }
    }
    @Test fun `metadata only ledger ACK does not defer financial history restoration`() {
        val changed = ledger(time = later).let { it.copy(payload = JsonObject(it.payload + ("title" to JsonPrimitive("Renamed")))) }
        assertTrue(decide(ledgers = mapOf(tx to changed)) is InstallmentSourceAckDecision.Ready)
    }
    @Test fun `draft income and archived ledger cannot prove paid footprint`() {
        for ((key, value) in listOf("entry_status_raw_value" to JsonPrimitive("draft"), "primary_kind_raw_value" to JsonPrimitive("income"), "is_archived" to JsonPrimitive(true))) {
            val current = ledger().let { it.copy(payload = JsonObject(it.payload + (key to value))) }
            val s = snapshot().let { it.copy(recordsByEntity = it.recordsByEntity + (CloudEntity.LEDGER_TRANSACTION to listOf(current))) }
            assertTrue(decide(s, ledgers = mapOf(tx to current)) is InstallmentSourceAckDecision.Conflict)
        }
    }

}
