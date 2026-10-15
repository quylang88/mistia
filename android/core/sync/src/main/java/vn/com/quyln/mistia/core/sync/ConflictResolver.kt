package vn.com.quyln.mistia.core.sync

import kotlinx.serialization.json.JsonObject
import vn.com.quyln.mistia.core.model.CloudRecord
import vn.com.quyln.mistia.core.model.RecordConflictResolver

enum class ConflictWinner { LOCAL, REMOTE, UNRESOLVED }
data class ConflictDecision(val winner: ConflictWinner, val reason: String)

/** Keep the sync API while sharing the same policy with atomic model reconciliation. */
object ConflictResolver {
    fun resolve(local: CloudRecord, remote: CloudRecord): ConflictDecision {
        val result = RecordConflictResolver.resolve(local, remote)
        return ConflictDecision(ConflictWinner.valueOf(result.winner.name), result.reason)
    }
    fun semanticFingerprint(payload: JsonObject): String = RecordConflictResolver.semanticFingerprint(payload)
}
