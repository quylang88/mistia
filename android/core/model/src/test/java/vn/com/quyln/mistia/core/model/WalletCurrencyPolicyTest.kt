package vn.com.quyln.mistia.core.model

import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class WalletCurrencyPolicyTest {
    private val owner = UserId("11111111-1111-1111-1111-111111111111")
    private val wallet = "abcdefab-cdef-abcd-efab-cdefabcdefab"
    private fun row(source: String? = wallet, destination: String? = null, archived: JsonElement = JsonPrimitive(false), deleted: String? = null) = CloudRecord(
        CloudEntity.LEDGER_TRANSACTION.table, "22222222-2222-2222-2222-222222222222", owner.value,
        buildJsonObject { put("user_id", owner.value); put("source_wallet_id", source?.let(::JsonPrimitive) ?: JsonNull); put("destination_wallet_id", destination?.let(::JsonPrimitive) ?: JsonNull)
            put("is_archived", archived); put("deleted_at", deleted?.let(::JsonPrimitive) ?: JsonNull) }, "2026-10-15T00:00:00Z", deleted, 0)
    private fun locks(vararg rows: CloudRecord) = walletHasLiveLedgerHistory(owner, wallet, rows.toList())
    @Test fun `source reference locks currency`() { assertTrue(locks(row())) }
    @Test fun `destination reference also locks currency`() { assertTrue(locks(row(source = null, destination = wallet))) }
    @Test fun `archived and consistent deleted history does not lock currency`() { assertFalse(locks(row(archived = JsonPrimitive(true)), row(deleted = "2026-10-15T01:00:00Z"))) }
    @Test fun `unrelated foreign owner and nonledger rows do not lock currency`() {
        assertFalse(locks(row(source = "33333333-3333-3333-3333-333333333333"), row().copy(ownerUserId = "99999999-9999-9999-9999-999999999999"), row().copy(entity = CloudEntity.RECURRING_BILL_PLAN.table)))
    }
    @Test fun `malformed archive flag cannot hide a linked row`() { assertTrue(locks(row(archived = JsonPrimitive("true")))); assertTrue(locks(row(archived = JsonNull))) }
    @Test fun `disagreeing tombstones hold linked currency changes`() {
        assertTrue(locks(row(deleted = "2026-10-15T01:00:00Z").copy(deletedAt = null)))
        assertTrue(locks(row().copy(deletedAt = "2026-10-15T01:00:00Z")))
    }
    @Test fun `missing archive field and foreign payload inside owner partition stay conservative`() {
        val raw = row(); assertTrue(locks(raw.copy(payload = JsonObject(raw.payload - "is_archived"))))
        assertTrue(locks(raw.copy(payload = JsonObject(raw.payload + ("user_id" to JsonPrimitive("99999999-9999-9999-9999-999999999999"))))))
    }
    @Test fun `canonical UUID case does not lose the relation`() { assertTrue(locks(row(source = wallet.uppercase()))) }
    @Test fun `invalid deletion clocks cannot hide a linked row`() {
        assertTrue(locks(row(deleted = "not-a-date")))
        val deleted = row(deleted = "2026-10-15T01:00:00Z")
        assertTrue(locks(deleted.copy(payload = JsonObject(deleted.payload + ("deleted_at" to JsonPrimitive(123))))))
    }
}
