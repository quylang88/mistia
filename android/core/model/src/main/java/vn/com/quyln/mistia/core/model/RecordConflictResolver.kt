package vn.com.quyln.mistia.core.model

import java.security.MessageDigest
import java.time.Instant
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import vn.com.quyln.mistia.core.model.CloudRecord

enum class RecordConflictWinner { LOCAL, REMOTE, UNRESOLVED }

data class RecordConflictDecision(
    val winner: RecordConflictWinner,
    val reason: String,
)

object RecordConflictResolver {
    private val metadataKeys = setOf(
        "id",
        "user_id",
        "created_at",
        "updated_at",
        "deleted_at",
        "sync_version",
        "last_modified_by_device_id",
    )

    fun resolve(local: CloudRecord, remote: CloudRecord): RecordConflictDecision {
        require(local.entity == remote.entity && local.id == remote.id)
        val localFingerprint = semanticFingerprint(local.payload)
        val remoteFingerprint = semanticFingerprint(remote.payload)
        val localUpdatedAt = local.updatedAt.asInstant()
        val remoteUpdatedAt = remote.updatedAt.asInstant()

        if (localUpdatedAt != remoteUpdatedAt) {
            return if (localUpdatedAt > remoteUpdatedAt) {
                RecordConflictDecision(RecordConflictWinner.LOCAL, "later_updated_at")
            } else {
                RecordConflictDecision(RecordConflictWinner.REMOTE, "later_updated_at")
            }
        }
        if ((local.deletedAt != null) != (remote.deletedAt != null)) {
            return if (local.deletedAt != null) {
                RecordConflictDecision(RecordConflictWinner.LOCAL, "delete_wins_timestamp_tie")
            } else {
                RecordConflictDecision(RecordConflictWinner.REMOTE, "delete_wins_timestamp_tie")
            }
        }
        if (local.syncVersion != remote.syncVersion) {
            return if (local.syncVersion > remote.syncVersion) {
                RecordConflictDecision(RecordConflictWinner.LOCAL, "higher_sync_version")
            } else {
                RecordConflictDecision(RecordConflictWinner.REMOTE, "higher_sync_version")
            }
        }
        if (localFingerprint == remoteFingerprint) {
            return RecordConflictDecision(RecordConflictWinner.REMOTE, "semantically_equal")
        }
        return RecordConflictDecision(RecordConflictWinner.UNRESOLVED, "same_clock_version_different_payload")
    }

    fun semanticFingerprint(payload: JsonObject): String {
        val semanticPayload = JsonObject(payload.filterKeys { it !in metadataKeys })
        val canonical = canonicalJson(semanticPayload)
        val digest = MessageDigest.getInstance("SHA-256").digest(canonical.toByteArray(Charsets.UTF_8))
        return digest.joinToString(separator = "") { byte -> "%02x".format(byte) }
    }

    private fun canonicalJson(element: JsonElement): String = when (element) {
        is JsonObject -> element.keys.sorted().joinToString(prefix = "{", postfix = "}") { key ->
            "${jsonString(key)}:${canonicalJson(element.getValue(key))}"
        }
        is JsonArray -> element.joinToString(prefix = "[", postfix = "]") { canonicalJson(it) }
        JsonNull -> "null"
        else -> element.toString()
    }

    private fun jsonString(value: String): String = JsonObject(mapOf(value to JsonNull)).toString()
        .removePrefix("{")
        .substringBefore(":")

    private fun String?.asInstant(): Instant =
        this?.let { runCatching { Instant.parse(it) }.getOrNull() } ?: Instant.MIN
}
