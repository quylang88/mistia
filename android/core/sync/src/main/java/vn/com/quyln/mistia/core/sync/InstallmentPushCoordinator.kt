package vn.com.quyln.mistia.core.sync

import java.time.Instant
import java.util.UUID
import kotlin.coroutines.AbstractCoroutineContextElement
import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.EmptyCoroutineContext
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.serialization.json.*
import vn.com.quyln.mistia.core.model.*

/** Plan metadata only. Installment occurrence writes have a separate readiness gate. */
class InstallmentPushCoordinator(localStore: LocalStore, remoteStore: RemoteMutationStore, writesEnabled: Boolean,
    dependentDeletionReady: Boolean = false,
    nowEpochMillis: () -> Long = System::currentTimeMillis) : DomainPushCoordinator {
    private val delegate = OutboxPushCoordinator(
        entity = CloudEntity.INSTALLMENT_PLAN, localStore = localStore, remoteStore = remoteStore,
        writesEnabled = writesEnabled, nowEpochMillis = nowEpochMillis, allowTombstoneDeletes = true,
        validateRecord = { row ->
            val typed = InstallmentPlanRecord.fromCloudRecord(row)
            require(typed.id == row.id && typed.ownerUserId == row.ownerUserId && typed.syncVersion == row.syncVersion)
            require(typed.deletedAt == row.deletedAt)
            require(Instant.parse(typed.updatedAt) == Instant.parse(requireNotNull(row.updatedAt)))
        },
        normalizeSemanticPayload = { payload ->
            val id = payload.getValue("id").jsonPrimitive.content
            val owner = payload.getValue("user_id").jsonPrimitive.content
            val typed = InstallmentPlanRecord.fromCloudRecord(CloudRecord(CloudEntity.INSTALLMENT_PLAN.table, id, owner, payload, null, null, 0))
            // Swift fingerprints the raw currency string; UUIDs and optional values are typed.
            JsonObject(typed.toPayload() + ("currency_code" to payload.getValue("currency_code")))
        },
        orderMutations = { mutations, owner ->
            val pendingWallets = localStore.pendingMutationRecordIds(owner, CloudEntity.LEDGER_WALLET.table)
            val pendingDue = localStore.pendingMutationRecordIds(owner, CloudEntity.DUE_OCCURRENCE_RECORD.table)
            mutations.filter { queued ->
                if (queued.mutation.kind == MutationKind.DELETE && dependentDeletionReady) true
                else if (queued.mutation.kind == MutationKind.DELETE) pendingDue.none { dueId ->
                    // Dependent cycle deletion needs its own source-conflict/ledger-preservation preflight.
                    val row = localStore.record(owner, CloudEntity.DUE_OCCURRENCE_RECORD.table, dueId)
                    if (row == null || row.id != dueId || row.entity != CloudEntity.DUE_OCCURRENCE_RECORD.table || row.ownerUserId != owner.value) true
                    else {
                        val kind = (row.payload["source_kind_raw_value"] as? JsonPrimitive)?.contentOrNull
                        val source = (row.payload["source_id"] as? JsonPrimitive)?.contentOrNull
                        val subject = (row.payload["user_id"] as? JsonPrimitive)?.contentOrNull
                        kind == "installment" && source.equals(queued.mutation.recordId, ignoreCase = true) &&
                            (subject == null || subject.equals(owner.value, ignoreCase = true))
                    }
                }
                else {
                    val payload = localStore.record(owner, CloudEntity.INSTALLMENT_PLAN.table, queued.mutation.recordId)?.payload ?: queued.mutation.payload
                    val wallet = (payload?.get("payment_wallet_id") as? JsonPrimitive)?.contentOrNull?.let { raw ->
                        runCatching { UUID.fromString(raw).toString() }.getOrNull()?.takeIf { it.equals(raw, ignoreCase = true) } ?: raw
                    }
                    wallet == null || wallet !in pendingWallets
                }
            }
        },
        acknowledgementContext = { queued, local, owner, token ->
            if (!dependentDeletionReady || queued.mutation.kind != MutationKind.DELETE) EmptyCoroutineContext
            else {
                val snapshot = localStore.installmentAcknowledgementSnapshot(owner, queued.mutation.recordId)
                val clock = Instant.ofEpochMilli(nowEpochMillis()).toString()
                val current = snapshot.recordsByEntity.getValue(CloudEntity.INSTALLMENT_PLAN).singleOrNull { it.id == local.id }
                val decision = if (current != local) InstallmentSourceAckDecision.Stale else
                    // Local feasibility only; this tombstone is never acknowledged as a remote response here.
                    planInstallmentSourceAcknowledgement(snapshot, queued, local, emptyMap(), emptyMap(), clock)
                SourceAcknowledgementContext(owner, token, snapshot.batch?.batchId, clock, decision.toPreflight())
            }
        },
        preflight = { _, _, _, _ -> currentCoroutineContext()[SourceAcknowledgementContext]?.preflight ?: MutationPreflight.Continue },
        recordFailureOverride = { queued, next, code ->
            currentCoroutineContext()[SourceAcknowledgementContext]?.let { context ->
                localStore.recordInstallmentSourceFailure(queued, context.batchId, next, code)
            }
        },
        acknowledgeOverride = { queued, remote ->
            val context = currentCoroutineContext()[SourceAcknowledgementContext]
            if (context == null) MutationAcknowledgement.Default else {
                val snapshot = localStore.installmentAcknowledgementSnapshot(context.owner, queued.mutation.recordId)
                if (snapshot.batch?.batchId != context.batchId) MutationAcknowledgement.Stale else {
                    val cycles = mutableMapOf<String, CloudRecord?>()
                    val ledger = mutableMapOf<String, CloudRecord?>()
                    var decision = planInstallmentSourceAcknowledgement(snapshot, queued, remote, cycles, ledger, context.clock)
                    while (decision is InstallmentSourceAckDecision.NeedCycles || decision is InstallmentSourceAckDecision.NeedLedger) {
                        val requestedEntity = if (decision is InstallmentSourceAckDecision.NeedCycles) CloudEntity.DUE_OCCURRENCE_RECORD else CloudEntity.LEDGER_TRANSACTION
                        val ids = when (decision) {
                            is InstallmentSourceAckDecision.NeedCycles -> decision.ids
                            is InstallmentSourceAckDecision.NeedLedger -> decision.ids
                            else -> error("Read request expected")
                        }
                        val target = if (requestedEntity == CloudEntity.DUE_OCCURRENCE_RECORD) cycles else ledger
                        ids.forEach { id ->
                            currentCoroutineContext().ensureActive()
                            target[id] = remoteStore.fetchRecord(requestedEntity, id, context.token, context.owner)
                        }
                        decision = planInstallmentSourceAcknowledgement(snapshot, queued, remote, cycles, ledger, context.clock)
                    }
                    currentCoroutineContext().ensureActive()
                    when (decision) {
                        is InstallmentSourceAckDecision.Ready -> if (localStore.commitInstallmentSourceAcknowledgement(snapshot, queued,
                            context.batchId, remote, cycles, ledger, context.clock)) MutationAcknowledgement.Committed else MutationAcknowledgement.Stale
                        InstallmentSourceAckDecision.Stale -> MutationAcknowledgement.Stale
                        is InstallmentSourceAckDecision.Deferred -> MutationAcknowledgement.Deferred
                        is InstallmentSourceAckDecision.Conflict -> MutationAcknowledgement.Conflict(decision.reason)
                        else -> error("Unfulfilled read request")
                    }
                }
            }
        },
    )
    override val entity = CloudEntity.INSTALLMENT_PLAN
    override suspend fun pushPending(ownerUserId: UserId, accessToken: String) = delegate.pushPending(ownerUserId, accessToken)
}

/** Per-request identity survives nested conflict/refetch paths and cannot be overwritten by another push. */
private class SourceAcknowledgementContext(val owner: UserId, val token: String, val batchId: String?, val clock: String,
    val preflight: MutationPreflight) : AbstractCoroutineContextElement(Key) {
    companion object Key : CoroutineContext.Key<SourceAcknowledgementContext>
}
private fun InstallmentSourceAckDecision.toPreflight(): MutationPreflight = when (this) {
    InstallmentSourceAckDecision.Stale -> MutationPreflight.Stale
    is InstallmentSourceAckDecision.Deferred -> MutationPreflight.Deferred
    is InstallmentSourceAckDecision.Conflict -> MutationPreflight.Conflict(reason)
    is InstallmentSourceAckDecision.Ready -> MutationPreflight.Continue
    else -> error("Local deletion preflight must not require remote reads")
}
