package vn.com.quyln.mistia.core.model

import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class InstallmentMutationSnapshotTest {
    private val owner = UserId("11111111-1111-1111-1111-111111111111")
    private val id = "22222222-2222-2222-2222-222222222222"
    private val wallet = "33333333-3333-3333-3333-333333333333"
    private val device = "44444444-4444-4444-4444-444444444444"
    private val other = "99999999-9999-9999-9999-999999999999"
    private val before = "2026-01-15T00:00:00Z"
    private val now = "2026-10-14T01:00:00Z"
    private val source = InstallmentPlanRecord(id, owner.value, "Loan", "mistia.plan.installment", 5000, 15, null, 1, wallet, "JPY", false,
        before, before, null, 9007199254740993L, device).toCloudRecord()
    private val occurrence = DueOccurrenceRecord(other, owner.value, "installment", id, "2026-01", before, 5000, "paid", before,
        wallet, before, before, null, 9007199254740995L, device).toCloudRecord()
    private fun snapshot() = InstallmentMutationSnapshot(owner, id, mapOf(CloudEntity.INSTALLMENT_PLAN to listOf(source),
        CloudEntity.DUE_OCCURRENCE_RECORD to listOf(occurrence), CloudEntity.LEDGER_WALLET to emptyList()))
    private fun tombstone(row: CloudRecord): Pair<CloudRecord, PendingMutation> {
        val payload = JsonObject(row.payload + mapOf("updated_at" to JsonPrimitive(now), "deleted_at" to JsonPrimitive(now), "last_modified_by_device_id" to JsonPrimitive(device)))
        val saved = row.copy(payload = payload, updatedAt = now, deletedAt = now)
        return saved to PendingMutation(CloudEntity.fromTable(row.entity)!!, row.id, owner.value, MutationKind.DELETE, payload, now, row.syncVersion, device)
    }
    private fun changed(pair: Pair<CloudRecord, PendingMutation>, key: String, value: JsonElement): Pair<CloudRecord, PendingMutation> {
        val payload = JsonObject(pair.first.payload + (key to value))
        return pair.first.copy(payload = payload) to pair.second.copy(payload = payload)
    }
    @Test fun `complete deletion permits only source and every owned live occurrence`() {
        snapshot().requireValidMutations(listOf(tombstone(source), tombstone(occurrence)))
        assertThrows(IllegalArgumentException::class.java) { snapshot().requireValidMutations(listOf(tombstone(source))) }
    }
    @Test fun `frozen financial amounts links currency creation metadata and versions cannot change in deletion`() {
        val plan = tombstone(source); val due = tombstone(occurrence)
        mapOf("currency_code" to JsonPrimitive("VND"), "created_at" to JsonPrimitive(now), "sync_version" to JsonPrimitive(1L),
            "amount_per_cycle_minor" to JsonPrimitive(1L)).forEach { (key, value) ->
            assertThrows(key, IllegalArgumentException::class.java) { snapshot().requireValidMutations(listOf(changed(plan, key, value), due)) }
        }
        listOf("amount_minor_snapshot", "linked_transaction_id", "status_raw_value").forEach { key ->
            assertThrows(key, IllegalArgumentException::class.java) { snapshot().requireValidMutations(listOf(plan, changed(due, key, JsonNull))) }
        }
    }
    @Test fun `foreign owner aliased source and incorrect outbox base cannot be committed`() {
        val plan = tombstone(source); val due = tombstone(occurrence)
        listOf("user_id", "id").forEach { key ->
            assertThrows(IllegalArgumentException::class.java) { snapshot().requireValidMutations(listOf(changed(plan, key, JsonPrimitive(other)), due)) }
        }
        assertThrows(IllegalArgumentException::class.java) { snapshot().requireValidMutations(listOf(plan.first to plan.second.copy(baseVersion = 1), due)) }
    }
    @Test fun `ledger transactions and mismatched device batch are prohibited`() {
        val plan = tombstone(source); val due = tombstone(occurrence)
        val ledger = due.first.copy(entity = CloudEntity.LEDGER_TRANSACTION.table)
        assertThrows(IllegalArgumentException::class.java) { snapshot().requireValidMutations(listOf(plan, ledger to due.second.copy(entity = CloudEntity.LEDGER_TRANSACTION))) }
        val payload = JsonObject(due.first.payload + ("last_modified_by_device_id" to JsonPrimitive(other)))
        assertThrows(IllegalArgumentException::class.java) { snapshot().requireValidMutations(listOf(plan, due.first.copy(payload = payload) to due.second.copy(payload = payload, deviceId = other))) }
    }
    @Test fun `unknown fields cannot be removed and complete snapshot catches insertion and wallet changes`() {
        val extra = source.copy(payload = JsonObject(source.payload + ("future_metadata" to buildJsonObject { put("keep", true) })))
        val snap = snapshot().copy(recordsByEntity = snapshot().recordsByEntity + (CloudEntity.INSTALLMENT_PLAN to listOf(extra)))
        assertThrows(IllegalArgumentException::class.java) { snap.requireValidMutations(listOf(tombstone(source), tombstone(occurrence))) }
        assertThrows(IllegalArgumentException::class.java) { snapshot().requireUnchanged(snapshot().recordsByEntity + (CloudEntity.DUE_OCCURRENCE_RECORD to emptyList())) }
        val cash = WalletDraft(id = wallet, name = "Cash", kind = WalletKind.CASH, currencyCode = "JPY").toMutation(owner, null, device, before).record
        assertThrows(IllegalArgumentException::class.java) { snapshot().requireUnchanged(snapshot().recordsByEntity + (CloudEntity.LEDGER_WALLET to listOf(cash))) }
    }
}
