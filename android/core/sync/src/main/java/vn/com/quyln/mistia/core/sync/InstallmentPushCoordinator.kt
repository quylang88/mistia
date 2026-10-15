package vn.com.quyln.mistia.core.sync

import java.time.Instant
import java.util.UUID
import kotlinx.serialization.json.*
import vn.com.quyln.mistia.core.model.*

/** Plan metadata only. Installment occurrence writes have a separate readiness gate. */
class InstallmentPushCoordinator(localStore: LocalStore, remoteStore: RemoteMutationStore, writesEnabled: Boolean,
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
                if (queued.mutation.kind == MutationKind.DELETE) pendingDue.none { dueId ->
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
    )
    override val entity = CloudEntity.INSTALLMENT_PLAN
    override suspend fun pushPending(ownerUserId: UserId, accessToken: String) = delegate.pushPending(ownerUserId, accessToken)
}
