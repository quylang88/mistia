package vn.com.quyln.mistia.core.sync

import java.io.IOException
import kotlin.math.min
import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.EmptyCoroutineContext
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import vn.com.quyln.mistia.core.model.CloudEntity
import vn.com.quyln.mistia.core.model.CloudRecord
import vn.com.quyln.mistia.core.model.LocalStore
import vn.com.quyln.mistia.core.model.MutationKind
import vn.com.quyln.mistia.core.model.QueuedMutation
import vn.com.quyln.mistia.core.model.RemoteMutationStore
import vn.com.quyln.mistia.core.model.UserId
import vn.com.quyln.mistia.core.network.SupabaseHttpException

data class DomainPushSummary(
    val pushed: Int = 0,
    val acknowledged: Int = 0,
    val conflicts: Int = 0,
    val retryableFailures: Int = 0,
    val permanentFailures: Int = 0,
    val staleResponses: Int = 0,
    val reconciled: Int = 0,
)

interface DomainPushCoordinator {
    val entity: CloudEntity
    suspend fun pushPending(ownerUserId: UserId, accessToken: String): DomainPushSummary
}

internal sealed interface MutationPreflight {
    data object Continue : MutationPreflight
    data object Reconciled : MutationPreflight
    data object Stale : MutationPreflight
    data object Deferred : MutationPreflight
    data class Acknowledge(val record: CloudRecord) : MutationPreflight
    data class Conflict(val reason: String) : MutationPreflight
}

internal sealed interface MutationAcknowledgement {
    data object Default : MutationAcknowledgement
    data object Committed : MutationAcknowledgement
    data object Stale : MutationAcknowledgement
    data object Deferred : MutationAcknowledgement
    data class Conflict(val reason: String) : MutationAcknowledgement
}

internal class OutboxPushCoordinator(
    override val entity: CloudEntity,
    private val localStore: LocalStore,
    private val remoteStore: RemoteMutationStore,
    private val writesEnabled: Boolean,
    private val nowEpochMillis: () -> Long,
    private val allowTombstoneDeletes: Boolean = false,
    private val normalizeSemanticPayload: (JsonObject) -> JsonObject = { it },
    private val validateRecord: (CloudRecord) -> Unit = {},
    private val preferRemoteRecord: suspend (QueuedMutation, CloudRecord, CloudRecord) -> Boolean = { _, _, _ -> false },
    private val orderMutations: suspend (List<QueuedMutation>, UserId) -> List<QueuedMutation> = { rows, _ -> rows },
    private val preflight: suspend (QueuedMutation, CloudRecord, UserId, String) -> MutationPreflight = { _, _, _, _ -> MutationPreflight.Continue },
    private val acknowledgementContext: suspend (QueuedMutation, CloudRecord, UserId, String) -> CoroutineContext = { _, _, _, _ -> EmptyCoroutineContext },
    private val recordFailureOverride: suspend (QueuedMutation, Long, String) -> Boolean? = { _, _, _ -> null },
    private val acknowledgeOverride: suspend (QueuedMutation, CloudRecord) -> MutationAcknowledgement = { _, _ -> MutationAcknowledgement.Default },
    private val conflictDecisionOverride: (CloudRecord, CloudRecord) -> ConflictDecision? = { _, _ -> null },
    private val beforeRemoteWrite: suspend (QueuedMutation, CloudRecord, UserId, String) -> MutationPreflight = { _, _, _, _ -> MutationPreflight.Continue },
) : DomainPushCoordinator {
    private fun semanticDecision(local: CloudRecord, remote: CloudRecord): ConflictDecision =
        conflictDecisionOverride(local, remote) ?: ConflictResolver.resolve(local.copy(payload = normalizeSemanticPayload(local.payload)),
            remote.copy(payload = normalizeSemanticPayload(remote.payload)))

    override suspend fun pushPending(ownerUserId: UserId, accessToken: String): DomainPushSummary {
        if (!writesEnabled) return DomainPushSummary()

        var summary = DomainPushSummary()
        val now = nowEpochMillis()
        val pending = localStore.pendingMutations(ownerUserId, entity, now)
        for (queued in orderMutations(pending, ownerUserId)) {
            summary = try {
                when (pushOne(queued, ownerUserId, accessToken, now)) {
                    PushOutcome.PUSHED -> summary.copy(pushed = summary.pushed + 1)
                    PushOutcome.RECONCILED -> summary.copy(reconciled = summary.reconciled + 1)
                    PushOutcome.DEFERRED -> summary
                    PushOutcome.ACKNOWLEDGED -> summary.copy(acknowledged = summary.acknowledged + 1)
                    PushOutcome.CONFLICT -> summary.copy(conflicts = summary.conflicts + 1)
                    PushOutcome.STALE -> summary.copy(staleResponses = summary.staleResponses + 1)
                    PushOutcome.RETRYABLE_FAILURE -> summary.copy(retryableFailures = summary.retryableFailures + 1)
                    PushOutcome.PERMANENT_FAILURE -> summary.copy(permanentFailures = summary.permanentFailures + 1)
                }
            } catch (error: Exception) {
                if (error is CancellationException) throw error
                if (error is MutationFailurePersistenceException) throw requireNotNull(error.cause)
                val retryable = error.isRetryable()
                val retryAt = if (retryable) now + retryDelayMillis(queued.attemptCount) else Long.MAX_VALUE
                val recorded = recordFailure(queued, retryAt, error.safeCode())
                if (!recorded) summary.copy(staleResponses = summary.staleResponses + 1)
                else if (retryable) summary.copy(retryableFailures = summary.retryableFailures + 1)
                else summary.copy(permanentFailures = summary.permanentFailures + 1)
            }
        }
        return summary
    }

    private suspend fun pushOne(
        queued: QueuedMutation,
        ownerUserId: UserId,
        accessToken: String,
        now: Long,
    ): PushOutcome {
        val mutation = queued.mutation
        require(mutation.subjectUserId == ownerUserId.value) { "Outbox owner does not match session" }
        require(mutation.entity == entity) { "${entity.table} push received another domain" }
        require(mutation.kind == MutationKind.UPSERT || allowTombstoneDeletes && mutation.kind == MutationKind.DELETE) {
            "${entity.table} does not support this mutation kind"
        }
        val local = requireNotNull(localStore.record(ownerUserId, entity.table, mutation.recordId)) {
            "Pending ${entity.table} row is missing locally"
        }
        require(local.ownerUserId == ownerUserId.value && local.id == mutation.recordId) {
            "Local ${entity.table} identity does not match outbox"
        }
        validateRecord(local)

        return withContext(acknowledgementContext(queued, local, ownerUserId, accessToken)) {
            try {
                pushValidated(queued, local, ownerUserId, accessToken)
            } catch (error: Exception) {
                currentCoroutineContext().ensureActive()
                if (error is CancellationException || error is MutationFailurePersistenceException) throw error
                val retryable = error.isRetryable()
                val retryAt = if (retryable) now + retryDelayMillis(queued.attemptCount) else Long.MAX_VALUE
                if (!recordFailure(queued, retryAt, error.safeCode())) PushOutcome.STALE
                else if (retryable) PushOutcome.RETRYABLE_FAILURE else PushOutcome.PERMANENT_FAILURE
            }
        }
    }

    private suspend fun pushValidated(queued: QueuedMutation, local: CloudRecord, ownerUserId: UserId, accessToken: String): PushOutcome {
        val mutation = queued.mutation
        preflightOutcome(queued, local, ownerUserId, accessToken)?.let {return it}

        if (mutation.kind == MutationKind.DELETE) return pushDelete(queued, local, ownerUserId, accessToken)

        val remote = remoteStore.fetchRecord(entity, mutation.recordId, accessToken, ownerUserId)
        remote?.requireMutationIdentity(queued)
        if (remote != null && preferRemoteRecord(queued, local, remote)) return acknowledge(queued, remote, PushOutcome.ACKNOWLEDGED)
        if (remote != null && local.deletedAt == remote.deletedAt &&
            ConflictResolver.semanticFingerprint(normalizeSemanticPayload(remote.payload)) ==
            ConflictResolver.semanticFingerprint(normalizeSemanticPayload(local.payload))
        ) {
            return acknowledge(queued, remote, PushOutcome.ACKNOWLEDGED)
        }

        if (remote == null) {
            preflightOutcome(queued, local, ownerUserId, accessToken, beforeWriting = true)?.let { return it }
            val nextVersion = nextVersion(maxOf(mutation.baseVersion, local.syncVersion, 0))
            val created = try {
                remoteStore.createRecord(
                    entity,
                    accessToken,
                    ownerUserId,
                    local.preparedPayload(nextVersion, mutation.deviceId),
                )
            } catch (error: SupabaseHttpException) {
                if (error.statusCode != 409) throw error
                preflightOutcome(queued, local, ownerUserId, accessToken)?.let {return it}
                val winner = remoteStore.fetchRecord(entity, mutation.recordId, accessToken, ownerUserId)
                    ?: throw error
                return resolveConflict(queued, local, winner, ownerUserId, accessToken)
            }
            return acknowledge(queued, created, PushOutcome.PUSHED)
        }

        if (mutation.baseVersion > 0 &&
            remote.syncVersion == mutation.baseVersion &&
            remote.deletedAt == null
        ) {
            preflightOutcome(queued, local, ownerUserId, accessToken, beforeWriting = true)?.let { return it }
            val updated = remoteStore.conditionalUpdate(
                entity,
                mutation.recordId,
                accessToken,
                ownerUserId,
                mutation.baseVersion,
                local.preparedPayload(nextVersion(mutation.baseVersion), mutation.deviceId),
            )
            if (updated != null) return acknowledge(queued, updated, PushOutcome.PUSHED)
            val latest = remoteStore.fetchRecord(entity, mutation.recordId, accessToken, ownerUserId)
            if (latest == null) return retainConflict(queued, "conditional_update_missing")
            return resolveConflict(queued, local, latest, ownerUserId, accessToken)
        }

        return resolveConflict(queued, local, remote, ownerUserId, accessToken)
    }

    private suspend fun preflightOutcome(queued: QueuedMutation, local: CloudRecord, owner: UserId, token: String, beforeWriting: Boolean = false): PushOutcome? {
        currentCoroutineContext().ensureActive()
        val decision = if (beforeWriting) beforeRemoteWrite(queued, local, owner, token) else preflight(queued, local, owner, token)
        currentCoroutineContext().ensureActive()
        return when (decision) {
            MutationPreflight.Continue -> null
            MutationPreflight.Reconciled -> PushOutcome.RECONCILED
            MutationPreflight.Stale -> PushOutcome.STALE
            MutationPreflight.Deferred -> PushOutcome.DEFERRED
            is MutationPreflight.Acknowledge -> acknowledge(queued, decision.record, PushOutcome.ACKNOWLEDGED)
            is MutationPreflight.Conflict -> retainConflict(queued, decision.reason)
        }
    }

    private suspend fun pushDelete(
        queued: QueuedMutation,
        local: CloudRecord,
        owner: UserId,
        token: String,
    ): PushOutcome {
        require(local.deletedAt != null) { "Delete mutation must retain a local tombstone" }
        require((local.payload["deleted_at"] as? JsonPrimitive)?.content == local.deletedAt)
        val remote = remoteStore.fetchRecord(entity, queued.mutation.recordId, token, owner)
            ?: return acknowledge(queued, local, PushOutcome.ACKNOWLEDGED)
        remote.requireMutationIdentity(queued)
        if (remote.deletedAt != null) return acknowledge(queued, remote, PushOutcome.ACKNOWLEDGED)
        if (remote.syncVersion != queued.mutation.baseVersion) {
            return resolveDeleteConflict(queued, local, remote, owner, token)
        }
        preflightOutcome(queued, local, owner, token, beforeWriting = true)?.let { return it }
        val next = nextVersion(remote.syncVersion)
        val deleted = remoteStore.conditionalUpdate(entity, queued.mutation.recordId, token, owner,
            remote.syncVersion, local.deletePatch(next, queued.mutation.deviceId))
        if (deleted != null) return acknowledge(queued, deleted, PushOutcome.PUSHED)
        val latest = remoteStore.fetchRecord(entity, queued.mutation.recordId, token, owner)
            ?: return acknowledge(queued, local.copy(syncVersion = next,
                payload = local.preparedPayload(next, queued.mutation.deviceId)), PushOutcome.ACKNOWLEDGED)
        latest.requireMutationIdentity(queued)
        if (latest.deletedAt != null) return acknowledge(queued, latest, PushOutcome.ACKNOWLEDGED)
        return resolveDeleteConflict(queued, local, latest, owner, token)
    }

    private suspend fun resolveDeleteConflict(
        queued: QueuedMutation,
        local: CloudRecord,
        remote: CloudRecord,
        owner: UserId,
        token: String,
    ): PushOutcome {
        val decision = semanticDecision(local, remote)
        return when (decision.winner) {
            ConflictWinner.REMOTE -> acknowledge(queued, remote, PushOutcome.ACKNOWLEDGED)
            ConflictWinner.UNRESOLVED -> retainConflict(queued, "delete_${decision.reason}")
            ConflictWinner.LOCAL -> {
                preflightOutcome(queued, local, owner, token, beforeWriting = true)?.let { return it }
                val next = nextVersion(maxOf(remote.syncVersion, local.syncVersion, 0))
                val deleted = remoteStore.conditionalUpdate(entity, queued.mutation.recordId, token, owner,
                    remote.syncVersion, local.deletePatch(next, queued.mutation.deviceId))
                    ?: return retainConflict(queued, "force_delete_race")
                acknowledge(queued, deleted, PushOutcome.PUSHED)
            }
        }
    }

    /** Deletion metadata changes; an immutable due-source discriminator pins its permitted domain. */
    private fun CloudRecord.deletePatch(version: Long, device: String): JsonObject = JsonObject(mapOf(
        "id" to JsonPrimitive(id),
        "user_id" to JsonPrimitive(ownerUserId),
        "updated_at" to JsonPrimitive(requireNotNull(updatedAt)),
        "deleted_at" to JsonPrimitive(requireNotNull(deletedAt)),
        "sync_version" to JsonPrimitive(version),
        "last_modified_by_device_id" to JsonPrimitive(device),
    ) + when (entity) {
        CloudEntity.LEDGER_TRANSACTION.table -> mapOf("last_modified_by_user_id" to JsonPrimitive(ownerUserId))
        CloudEntity.DUE_OCCURRENCE_RECORD.table -> mapOf("source_kind_raw_value" to requireNotNull(payload["source_kind_raw_value"]))
        else -> emptyMap()
    })

    private fun nextVersion(current: Long): Long {
        require(current >= 0 && current < Long.MAX_VALUE) { "Sync version cannot be incremented" }
        return current + 1
    }

    private fun CloudRecord.requireMutationIdentity(queued: QueuedMutation) {
        require(entity == queued.mutation.entity.table && id == queued.mutation.recordId && ownerUserId == queued.mutation.subjectUserId) {
            "Remote identity does not match mutation"
        }
        require((payload["user_id"] as? JsonPrimitive)?.content == ownerUserId)
        require((payload["id"] as? JsonPrimitive)?.content == id)
        validateRecord(this)
    }

    private suspend fun resolveConflict(
        queued: QueuedMutation,
        local: CloudRecord,
        remote: CloudRecord,
        ownerUserId: UserId,
        accessToken: String,
    ): PushOutcome {
        remote.requireMutationIdentity(queued)
        if (preferRemoteRecord(queued, local, remote)) return acknowledge(queued, remote, PushOutcome.ACKNOWLEDGED)
        val decision = semanticDecision(local, remote)
        return when (decision.winner) {
            ConflictWinner.REMOTE -> acknowledge(queued, remote, PushOutcome.ACKNOWLEDGED)
            ConflictWinner.UNRESOLVED -> retainConflict(queued, decision.reason)
            ConflictWinner.LOCAL -> {
                preflightOutcome(queued, local, ownerUserId, accessToken, beforeWriting = true)?.let { return it }
                val nextVersion = nextVersion(maxOf(remote.syncVersion, local.syncVersion, 0))
                val updated = remoteStore.conditionalUpdate(
                    entity,
                    queued.mutation.recordId,
                    accessToken,
                    ownerUserId,
                    remote.syncVersion,
                    local.preparedPayload(nextVersion, queued.mutation.deviceId),
                ) ?: return retainConflict(queued, "force_update_race")
                acknowledge(queued, updated, PushOutcome.PUSHED)
            }
        }
    }

    private suspend fun retainConflict(queued: QueuedMutation, reason: String): PushOutcome =
        if (recordFailure(queued, Long.MAX_VALUE, "conflict_$reason")) {
            PushOutcome.CONFLICT
        } else {
            PushOutcome.STALE
        }

    private suspend fun recordFailure(queued: QueuedMutation, next: Long, code: String): Boolean = try {
        recordFailureOverride(queued, next, code) ?: localStore.recordMutationFailure(queued, next, code)
    } catch (error: Exception) {
        if (error is CancellationException) throw error
        // A scoped storage failure must never fall back to an unfenced generic write.
        throw MutationFailurePersistenceException(error)
    }

    private suspend fun acknowledge(
        queued: QueuedMutation,
        remote: CloudRecord,
        outcome: PushOutcome,
    ): PushOutcome {
        currentCoroutineContext().ensureActive()
        remote.requireMutationIdentity(queued)
        return when (val decision = acknowledgeOverride(queued, remote)) {
            MutationAcknowledgement.Default -> if (localStore.acknowledgeMutation(queued, remote)) outcome else PushOutcome.STALE
            MutationAcknowledgement.Committed -> outcome
            MutationAcknowledgement.Stale -> PushOutcome.STALE
            MutationAcknowledgement.Deferred -> PushOutcome.DEFERRED
            is MutationAcknowledgement.Conflict -> retainConflict(queued, decision.reason)
        }
    }

    private fun CloudRecord.preparedPayload(nextVersion: Long, deviceId: String): JsonObject = JsonObject(
        payload + mapOf(
            "sync_version" to JsonPrimitive(nextVersion),
            "last_modified_by_device_id" to JsonPrimitive(deviceId),
        )
    )

    private fun Throwable.isRetryable(): Boolean = when (this) {
        is SupabaseHttpException -> statusCode >= 500 || statusCode == 408 || statusCode == 429
        is IOException -> true
        else -> false
    }

    private fun Throwable.safeCode(): String = when (this) {
        is SupabaseHttpException -> "http_$statusCode"
        is IOException -> "network_io"
        is IllegalArgumentException -> "invalid_mutation"
        is IllegalStateException -> "invalid_state"
        else -> "unexpected_failure"
    }

    private fun retryDelayMillis(attemptCount: Int): Long {
        val exponent = min(attemptCount.coerceAtLeast(0), 10)
        return min(30_000L * (1L shl exponent), 6L * 60L * 60L * 1_000L)
    }

    private enum class PushOutcome { PUSHED, ACKNOWLEDGED, CONFLICT, STALE, RECONCILED, DEFERRED, RETRYABLE_FAILURE, PERMANENT_FAILURE }
}

private class MutationFailurePersistenceException(cause: Exception) : Exception(cause)
