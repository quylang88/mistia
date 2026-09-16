package vn.com.quyln.mistia.core.sync

import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.junit.Assert.assertEquals
import org.junit.Test
import vn.com.quyln.mistia.core.model.CloudRecord

class ConflictResolverTest {
    @Test
    fun laterUpdatedAtWinsForDifferentSemanticPayload() {
        val local = record("2026-09-17T01:00:00Z", version = 2, title = "local")
        val remote = record("2026-09-17T01:00:01Z", version = 1, title = "remote")
        assertEquals(ConflictWinner.REMOTE, ConflictResolver.resolve(local, remote).winner)
    }

    @Test
    fun tombstoneWinsAnExactTimestampTie() {
        val local = record("2026-09-17T01:00:00Z", version = 2, title = "same")
        val remote = record(
            "2026-09-17T01:00:00Z",
            version = 2,
            title = "same",
            deletedAt = "2026-09-17T01:00:00Z",
        )
        assertEquals(ConflictWinner.REMOTE, ConflictResolver.resolve(local, remote).winner)
    }

    @Test
    fun exactClockAndVersionWithDifferentPayloadNeedsUserReview() {
        val local = record("2026-09-17T01:00:00Z", version = 2, title = "local")
        val remote = record("2026-09-17T01:00:00Z", version = 2, title = "remote")
        assertEquals(ConflictWinner.UNRESOLVED, ConflictResolver.resolve(local, remote).winner)
    }

    @Test
    fun syncMetadataDoesNotChangeSemanticFingerprint() {
        val local = record("2026-09-17T01:00:00Z", version = 1, title = "same")
        val remote = record("2026-09-18T01:00:00Z", version = 99, title = "same")
        assertEquals(
            ConflictResolver.semanticFingerprint(local.payload),
            ConflictResolver.semanticFingerprint(remote.payload),
        )
    }

    private fun record(
        updatedAt: String,
        version: Long,
        title: String,
        deletedAt: String? = null,
    ) = CloudRecord(
        entity = "ledger_transactions",
        id = "11111111-1111-1111-1111-111111111111",
        ownerUserId = "22222222-2222-2222-2222-222222222222",
        payload = buildJsonObject {
            put("id", "11111111-1111-1111-1111-111111111111")
            put("title", title)
            put("updated_at", updatedAt)
            put("sync_version", version)
        },
        updatedAt = updatedAt,
        deletedAt = deletedAt,
        syncVersion = version,
    )
}
