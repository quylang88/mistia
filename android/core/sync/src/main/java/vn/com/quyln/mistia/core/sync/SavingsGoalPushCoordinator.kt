package vn.com.quyln.mistia.core.sync

import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.JsonObject
import java.time.Instant
import kotlinx.serialization.json.contentOrNull
import vn.com.quyln.mistia.core.model.MutationKind
import vn.com.quyln.mistia.core.model.CloudEntity
import vn.com.quyln.mistia.core.model.LocalStore
import vn.com.quyln.mistia.core.model.RemoteMutationStore
import vn.com.quyln.mistia.core.model.UserId

typealias SavingsGoalPushSummary = DomainPushSummary

class SavingsGoalPushCoordinator(
    localStore: LocalStore,
    remoteStore: RemoteMutationStore,
    writesEnabled: Boolean,
    nowEpochMillis: () -> Long = System::currentTimeMillis,
) : DomainPushCoordinator {
    private val delegate = OutboxPushCoordinator(
        entity = CloudEntity.SAVINGS_GOAL,
        localStore = localStore,
        remoteStore = remoteStore,
        writesEnabled = writesEnabled,
        nowEpochMillis = nowEpochMillis,
        allowTombstoneDeletes = true,
        normalizeSemanticPayload = { payload ->
            val raw = (payload["target_date"] as? JsonPrimitive)?.contentOrNull
            val instant = raw?.let { runCatching { Instant.parse(it).toString() }.getOrNull() }
            if (instant == null) payload else JsonObject(payload + ("target_date" to JsonPrimitive(instant)))
        },
        orderMutations = { mutations, owner ->
            val pendingWallets = localStore.pendingMutationRecordIds(owner, CloudEntity.LEDGER_WALLET.table)
            mutations.filter { queued ->
                if (queued.mutation.kind == MutationKind.DELETE) true
                else {
                    val payload = localStore.record(owner, CloudEntity.SAVINGS_GOAL.table, queued.mutation.recordId)?.payload
                        ?: queued.mutation.payload
                    val walletId = (payload?.get("linked_wallet_id") as? JsonPrimitive)?.contentOrNull
                    walletId == null || walletId !in pendingWallets
                }
            }
        },
    )

    override val entity: CloudEntity = CloudEntity.SAVINGS_GOAL

    override suspend fun pushPending(
        ownerUserId: UserId,
        accessToken: String,
    ): SavingsGoalPushSummary = delegate.pushPending(ownerUserId, accessToken)
}
