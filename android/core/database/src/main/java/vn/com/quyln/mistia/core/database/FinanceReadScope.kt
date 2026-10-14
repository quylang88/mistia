package vn.com.quyln.mistia.core.database

import java.util.UUID
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import vn.com.quyln.mistia.core.model.CloudEntity
import vn.com.quyln.mistia.core.model.CloudRecord
import vn.com.quyln.mistia.core.model.LocalStore
import vn.com.quyln.mistia.core.model.UserId

/** Personal finance identity. Family viewer/subject collections use their own repository rules. */
internal fun CloudRecord.matchesFinanceReadScope(owner: UserId, expected: CloudEntity, includingDeleted: Boolean = false): Boolean {
    if (entity != expected.table || ownerUserId != owner.value) return false
    val expectedOwner = readUuid(owner.value) ?: return false
    val expectedId = readUuid(id) ?: return false
    fun payloadUuid(key: String): String? = (payload[key] as? JsonPrimitive)?.takeIf { it.isString }?.content?.let(::readUuid)
    if (payloadUuid("user_id") != expectedOwner || payloadUuid("id") != expectedId) return false
    return includingDeleted || (deletedAt == null && (payload["deleted_at"] == null || payload["deleted_at"] == JsonNull))
}

internal fun LocalStore.observeOwnedFinanceRows(entity: CloudEntity, owner: UserId): Flow<List<CloudRecord>> =
    observe(entity.table, owner).map { records -> records.filter { it.matchesFinanceReadScope(owner, entity) } }

private val fullUuid = Regex("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")
private fun readUuid(value: String): String? {
    val trimmed = value.trim()
    if (!fullUuid.matches(trimmed)) return null
    return runCatching { UUID.fromString(trimmed).toString() }.getOrNull()
}
