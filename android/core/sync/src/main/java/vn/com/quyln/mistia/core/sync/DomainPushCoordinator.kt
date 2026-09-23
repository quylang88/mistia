package vn.com.quyln.mistia.core.sync

import java.io.IOException
import kotlin.math.min
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
)

interface DomainPushCoordinator {
    val entity: CloudEntity
    suspend fun pushPending(ownerUserId: UserId, accessToken: String): DomainPushSummary
}

internal class OutboxPushCoordinator(
    override val entity: CloudEntity,
    private val localStore: LocalStore,
    private val remoteStore: RemoteMutationStore,
    private val writesEnabled: Boolean,
    private val nowEpochMillis: () -> Long,
    private val orderMutations: suspend (List<QueuedMutation>, UserId) -> List<QueuedMutation> = { rows, _ -> rows },
) : DomainPushCoordinator {
    override suspend fun pushPending(ownerUserId: UserId, accessToken: String): DomainPushSummary {
        if (!writesEnabled) return DomainPushSummary()

        var summary = DomainPushSummary()
        val now = nowEpochMillis()
        val pending = localStore.pendingMutations(ownerUserId, entity, now)
        for (queued in orderMutations(pending, ownerUserId)) {
            summary = try {
                when (pushOne(queued, ownerUserId, accessToken)) {
                    PushOutcome.PUSHED -> summary.copy(pushed = summary.pushed + 1)
                    PushOutcome.ACKNOWLEDGED -> summary.copy(acknowledged = summary.acknowledged + 1)
                    PushOutcome.CONFLICT -> summary.copy(conflicts = summary.conflicts + 1)
                    PushOutcome.STALE -> summary.copy(staleResponses = summary.staleResponses + 1)
                }
            } catch (error: Exception) {
                if (error is CancellationException) throw error
                val retryable = error.isRetryable()
                val retryAt = if (retryable) now + retryDelayMillis(queued.attemptCount) else Long.MAX_VALUE
                val recorded = localStore.recordMutationFailure(queued, retryAt, error.safeCode())
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
    ): PushOutcome {
        val mutation = queued.mutation
        require(mutation.subjectUserId == ownerUserId.value) { "Outbox owner does not match session" }
        require(mutation.entity == entity) { "${entity.table} push received another domain" }
        require(mutation.kind == MutationKind.UPSERT) { "${entity.table} must sync as upserts" }
        val local = requireNotNull(localStore.record(ownerUserId, entity.table, mutation.recordId)) {
            "Pending ${entity.table} row is missing locally"
        }
        require(local.ownerUserId == ownerUserId.value && local.id == mutation.recordId) {
            "Local ${entity.table} identity does not match outbox"
        }

        val remote = remoteStore.fetchRecord(entity, mutation.recordId, accessToken, ownerUserId)
        if (remote != null &&
            ConflictResolver.semanticFingerprint(remote.payload) ==
            ConflictResolver.semanticFingerprint(local.payload)
        ) {
            return acknowledge(queued, remote, PushOutcome.ACKNOWLEDGED)
        }

        if (remote == null) {
            val nextVersion = maxOf(mutation.baseVersion, local.syncVersion, 0) + 1
            val created = try {
                remoteStore.createRecord(
                    entity,
                    accessToken,
                    ownerUserId,
                    local.preparedPayload(nextVersion, mutation.deviceId),
                )
            } catch (error: SupabaseHttpException) {
                if (error.statusCode != 409) throw error
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
            val updated = remoteStore.conditionalUpdate(
                entity,
                mutation.recordId,
                accessToken,
                ownerUserId,
                mutation.baseVersion,
                local.preparedPayload(mutation.baseVersion + 1, mutation.deviceId),
            )
            if (updated != null) return acknowledge(queued, updated, PushOutcome.PUSHED)
            val latest = remoteStore.fetchRecord(entity, mutation.recordId, accessToken, ownerUserId)
            if (latest == null) return retainConflict(queued, "conditional_update_missing")
            return resolveConflict(queued, local, latest, ownerUserId, accessToken)
        }

        return resolveConflict(queued, local, remote, ownerUserId, accessToken)
    }

    private suspend fun resolveConflict(
        queued: QueuedMutation,
        local: CloudRecord,
        remote: CloudRecord,
        ownerUserId: UserId,
        accessToken: String,
    ): PushOutcome {
        val decision = ConflictResolver.resolve(local, remote)
        return when (decision.winner) {
            ConflictWinner.REMOTE -> acknowledge(queued, remote, PushOutcome.ACKNOWLEDGED)
            ConflictWinner.UNRESOLVED -> retainConflict(queued, decision.reason)
            ConflictWinner.LOCAL -> {
                val nextVersion = maxOf(remote.syncVersion, local.syncVersion, 0) + 1
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
        if (localStore.recordMutationFailure(queued, Long.MAX_VALUE, "conflict_$reason")) {
            PushOutcome.CONFLICT
        } else {
            PushOutcome.STALE
        }

    private suspend fun acknowledge(
        queued: QueuedMutation,
        remote: CloudRecord,
        outcome: PushOutcome,
    ): PushOutcome = if (localStore.acknowledgeMutation(queued, remote)) outcome else PushOutcome.STALE

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

    private enum class PushOutcome { PUSHED, ACKNOWLEDGED, CONFLICT, STALE }
}
