package vn.com.quyln.mistia.core.model

import java.time.Instant
import java.util.UUID
import java.util.Locale
import kotlinx.serialization.json.*

/** Local-only provenance. No field here is added to a PostgREST financial payload. */
data class InstallmentDeletionMember(val before: CloudRecord, val deletion: PendingMutation,
    val pendingBefore: QueuedMutation?, val remoteIdentityObservedBefore: Boolean)

data class InstallmentDeletionBatch(val batchId: String, val source: InstallmentDeletionMember, val cycles: List<InstallmentDeletionMember>) {
    val owner: UserId get() = UserId(source.before.ownerUserId)
    val planId: String get() = source.before.id

    fun requireValid() {
        require(canonicalUuid(batchId) == batchId && canonicalUuid(owner.value) == owner.value && canonicalUuid(planId) == planId)
        require(cycles.isNotEmpty() && cycles.map { it.before.id } == cycles.map { it.before.id }.distinct().sorted())
        require(source.before.entity == CloudEntity.INSTALLMENT_PLAN.table && cycles.all { it.before.entity == CloudEntity.DUE_OCCURRENCE_RECORD.table })
        val snapshot = InstallmentMutationSnapshot(owner, planId, InstallmentMutationSnapshot.entities.associateWith {
            when (it) {
                CloudEntity.INSTALLMENT_PLAN -> listOf(source.before)
                CloudEntity.DUE_OCCURRENCE_RECORD -> cycles.map(InstallmentDeletionMember::before)
                else -> emptyList()
            }
        })
        val members = listOf(source) + cycles
        snapshot.requireValidMutations(members.map { member ->
            val p = requireNotNull(member.deletion.payload)
            member.before.copy(payload = p, updatedAt = member.deletion.modifiedAt, deletedAt = p.text("deleted_at")) to member.deletion
        })
        members.forEach { member ->
            require(member.before.deletedAt == null)
            require(Instant.parse(member.before.payload.requiredText("updated_at")) == Instant.parse(requireNotNull(member.before.updatedAt)))
            val old = member.pendingBefore
            if (old != null) {
                val q = old.mutation
                require(q.entity.table == member.before.entity && q.recordId == member.before.id && q.subjectUserId == owner.value)
                require(q.kind == MutationKind.UPSERT && q.payload == member.before.payload && q.baseVersion == member.before.syncVersion)
                require(canonicalUuid(q.deviceId) == q.deviceId)
                require(canonicalUuid(member.before.payload.requiredText("last_modified_by_device_id").lowercase(Locale.ROOT)) == q.deviceId)
                require(Instant.parse(q.modifiedAt) == Instant.parse(member.before.updatedAt))
                require(old.attemptCount >= 0 && old.nextAttemptAtEpochMillis >= 0)
            }
            if (member.before.syncVersion > 0 || old?.remoteIdentityObserved == true) require(member.remoteIdentityObservedBefore)
        }
    }

    fun toJson(): JsonObject {
        requireValid()
        return buildJsonObject {
            put("format_version", 1); put("owner_user_id", owner.value); put("plan_id", planId); put("batch_id", batchId)
            put("cycle_ids", JsonArray(cycles.map { JsonPrimitive(it.before.id) }))
            put("source", source.toJson()); put("cycles", JsonArray(cycles.map { it.toJson() }))
        }
    }
    companion object {
        fun capture(snapshot: InstallmentMutationSnapshot, writes: List<Pair<CloudRecord, PendingMutation>>,
            previousQueues: List<QueuedMutation>, batchId: String, knownRemoteKeys: Set<Pair<CloudEntity, String>> = emptySet()): InstallmentDeletionBatch? {
            snapshot.requireValidMutations(writes)
            val root = writes.single { it.first.entity == CloudEntity.INSTALLMENT_PLAN.table }
            val children = writes.filter { it.first.entity == CloudEntity.DUE_OCCURRENCE_RECORD.table }.sortedBy { it.first.id }
            if (root.second.kind != MutationKind.DELETE || children.isEmpty()) return null
            val affected = (listOf(root) + children).map { it.second.entity to it.second.recordId }.toSet()
            val queued = previousQueues.associateBy { it.mutation.entity to it.mutation.recordId }
            require(queued.size == previousQueues.size && affected.containsAll(queued.keys) && affected.containsAll(knownRemoteKeys))
            fun member(write: Pair<CloudRecord, PendingMutation>): InstallmentDeletionMember {
                val key = write.second.entity to write.first.id
                val before = snapshot.recordsByEntity.getValue(write.second.entity).single { it.id == write.first.id }
                val pending = queued[key]
                return InstallmentDeletionMember(before, write.second, pending, key in knownRemoteKeys || before.syncVersion > 0 || pending?.remoteIdentityObserved == true)
            }
            return InstallmentDeletionBatch(batchId, member(root), children.map(::member)).also { it.requireValid() }
        }
        fun fromJson(owner: UserId, planId: String, payload: JsonObject): InstallmentDeletionBatch {
            require(payload.number("format_version") == 1L)
            require(payload.requiredText("owner_user_id") == owner.value && payload.requiredText("plan_id") == planId)
            val source = payload.getValue("source").jsonObject.toMember()
            val cycles = payload.getValue("cycles").jsonArray.map { it.jsonObject.toMember() }.sortedBy { it.before.id }
            val manifest = payload.getValue("cycle_ids").jsonArray.map { (it as JsonPrimitive).also { p -> require(p.isString) }.content }
            require(manifest == cycles.map { it.before.id })
            return InstallmentDeletionBatch(payload.requiredText("batch_id"), source, cycles).also {
                require(it.owner == owner && it.planId == planId); it.requireValid()
            }
        }
    }
}

private fun InstallmentDeletionMember.toJson() = buildJsonObject {
    put("before", before.toJson()); put("deletion", deletion.toJson())
    put("remote_identity_observed_before", remoteIdentityObservedBefore)
    put("pending_before", pendingBefore?.let { q -> buildJsonObject {
        put("mutation", q.mutation.toJson()); put("attempt_count", q.attemptCount); put("next_attempt_at_epoch_millis", q.nextAttemptAtEpochMillis)
        put("last_error", q.lastError?.let(::JsonPrimitive) ?: JsonNull); put("remote_identity_observed", q.remoteIdentityObserved)
    } } ?: JsonNull)
}
private fun CloudRecord.toJson() = buildJsonObject {
    put("entity", entity); put("id", id); put("owner_user_id", ownerUserId); put("payload", payload)
    put("updated_at", updatedAt?.let(::JsonPrimitive) ?: JsonNull); put("deleted_at", deletedAt?.let(::JsonPrimitive) ?: JsonNull); put("sync_version", syncVersion)
}
private fun PendingMutation.toJson() = buildJsonObject {
    put("entity", entity.table); put("record_id", recordId); put("subject_user_id", subjectUserId); put("kind", kind.name)
    put("payload", payload ?: JsonNull); put("modified_at", modifiedAt); put("base_version", baseVersion); put("device_id", deviceId)
}
private fun JsonObject.toMember(): InstallmentDeletionMember {
    val p = getValue("before").jsonObject
    val before = CloudRecord(p.requiredText("entity"), p.requiredText("id"), p.requiredText("owner_user_id"), p.getValue("payload").jsonObject,
        p.text("updated_at"), p.text("deleted_at"), p.number("sync_version"))
    val pending = when (val value = getValue("pending_before")) {
        JsonNull -> null
        else -> value.jsonObject.let { q ->
            val count = q.number("attempt_count"); require(count in 0..Int.MAX_VALUE.toLong())
            QueuedMutation(q.getValue("mutation").jsonObject.toPending(), count.toInt(), q.number("next_attempt_at_epoch_millis"),
                q.text("last_error"), q.flag("remote_identity_observed"))
        }
    }
    return InstallmentDeletionMember(before, getValue("deletion").jsonObject.toPending(), pending, flag("remote_identity_observed_before"))
}
private fun JsonObject.toPending() = PendingMutation(requireNotNull(CloudEntity.fromTable(requiredText("entity"))), requiredText("record_id"),
    requiredText("subject_user_id"), MutationKind.valueOf(requiredText("kind")), when (val p = getValue("payload")) { JsonNull -> null; else -> p.jsonObject },
    requiredText("modified_at"), number("base_version"), requiredText("device_id"))
private fun JsonObject.text(key: String): String? = when (val p = getValue(key)) {
    JsonNull -> null
    is JsonPrimitive -> p.also { require(it.isString) }.content
    else -> throw IllegalArgumentException("Expected text")
}
private fun JsonObject.requiredText(key: String) = requireNotNull(text(key))
private fun JsonObject.number(key: String) = (getValue(key) as JsonPrimitive).also { require(!it.isString) }.longOrNull ?: throw IllegalArgumentException("Expected Int64")
private fun JsonObject.flag(key: String) = (getValue(key) as JsonPrimitive).also { require(!it.isString) }.booleanOrNull ?: throw IllegalArgumentException("Expected Boolean")
private val uuidPattern = Regex("[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")
private fun canonicalUuid(value: String) = value.takeIf { uuidPattern.matches(it) }?.let { UUID.fromString(it).toString() }
