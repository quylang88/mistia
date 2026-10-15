package vn.com.quyln.mistia.core.model

import kotlinx.serialization.json.*

/** Mirrors Swift's live, unarchived source/destination relationship test. */
fun walletHasLiveLedgerHistory(owner: UserId, walletId: String, records: List<CloudRecord>): Boolean = records.any { row ->
    if (row.ownerUserId != owner.value || row.entity != CloudEntity.LEDGER_TRANSACTION.table) return@any false
    fun links(key: String): Boolean = (row.payload[key] as? JsonPrimitive)?.takeIf { it.isString }?.content?.trim()?.equals(walletId, ignoreCase = true) == true
    if (!links("source_wallet_id") && !links("destination_wallet_id")) return@any false
    val archived = row.payload["is_archived"] as? JsonPrimitive
    if (archived?.isString == false && archived.booleanOrNull == true) return@any false
    // Inconsistent legacy envelopes must not silently remove a live dependency.
    val outerDeleted = row.deletedAt?.let { runCatching { java.time.Instant.parse(it) }.getOrNull() }
    val wireDeleted = (row.payload["deleted_at"] as? JsonPrimitive)?.takeIf { it.isString }?.content?.let {
        runCatching { java.time.Instant.parse(it) }.getOrNull()
    }
    !(outerDeleted != null && outerDeleted == wireDeleted)
}
