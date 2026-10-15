package vn.com.quyln.mistia.core.sync

import java.util.UUID
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import vn.com.quyln.mistia.core.model.CloudEntity
import vn.com.quyln.mistia.core.model.LocalStore
import vn.com.quyln.mistia.core.model.RemoteMutationStore
import vn.com.quyln.mistia.core.model.UserId
import vn.com.quyln.mistia.core.model.MutationKind
import vn.com.quyln.mistia.core.model.CloudRecord
import vn.com.quyln.mistia.core.model.QueuedMutation

typealias TransactionPushSummary = DomainPushSummary

class TransactionPushCoordinator(
    localStore: LocalStore,
    remoteStore: RemoteMutationStore,
    writesEnabled: Boolean,
    nowEpochMillis: () -> Long = System::currentTimeMillis,
) : DomainPushCoordinator {
    private val delegate = OutboxPushCoordinator(
        entity = CloudEntity.LEDGER_TRANSACTION,
        localStore = localStore,
        remoteStore = remoteStore,
        writesEnabled = writesEnabled,
        nowEpochMillis = nowEpochMillis,
        allowTombstoneDeletes = true,
        preflight = { queued, local, owner, _ -> transactionDependencyPreflight(localStore, queued, local, owner) },
        beforeRemoteWrite = { queued, local, owner, _ -> transactionDependencyPreflight(localStore, queued, local, owner) },
        validateRecord = { record ->
            val role=(record.payload["settlement_role_raw_value"] as? JsonPrimitive)?.contentOrNull
            require(role!="investmentCashDeposit" && role!="investmentCashWithdrawal") {
                "Investment cash events require their atomic RPC"
            }
        },
    )

    override val entity: CloudEntity = CloudEntity.LEDGER_TRANSACTION

    override suspend fun pushPending(
        ownerUserId: UserId,
        accessToken: String,
    ): TransactionPushSummary = delegate.pushPending(ownerUserId, accessToken)
}

/** Includes blocked/future retries; domain ordering alone does not prove a parent was acknowledged. */
private suspend fun transactionDependencyPreflight(store: LocalStore, queued: QueuedMutation, local: CloudRecord, owner: UserId): MutationPreflight {
    if (queued.mutation.kind == MutationKind.DELETE) return MutationPreflight.Continue
    val wallets = listOfNotNull(local.payload.dependencyReference("source_wallet_id"), local.payload.dependencyReference("destination_wallet_id")).toSet()
    val category = local.payload.dependencyReference("category_id")
    if (wallets.isNotEmpty()) {
        val pending = store.pendingMutationRecordIds(owner, CloudEntity.LEDGER_WALLET.table).map(::canonicalDependencyId).toSet()
        if (wallets.any { it in pending }) return MutationPreflight.Deferred
    }
    if (category != null && category in store.pendingMutationRecordIds(owner, CloudEntity.TRANSACTION_CATEGORY.table).map(::canonicalDependencyId))
        return MutationPreflight.Deferred
    return MutationPreflight.Continue
}
private fun JsonObject.dependencyReference(key: String): String? {
    val value = get(key) ?: return null
    if (value == JsonNull) return null
    require(value is JsonPrimitive && value.isString)
    return canonicalDependencyId(value.content)
}
private fun canonicalDependencyId(id: String): String = runCatching { UUID.fromString(id).toString() }.getOrDefault(id)
