package vn.com.quyln.mistia.core.sync

import kotlinx.serialization.json.JsonNull
import vn.com.quyln.mistia.core.model.CloudEntity
import vn.com.quyln.mistia.core.model.LocalStore
import vn.com.quyln.mistia.core.model.QueuedMutation
import vn.com.quyln.mistia.core.model.RemoteMutationStore
import vn.com.quyln.mistia.core.model.UserId
import vn.com.quyln.mistia.core.model.SystemCategoryCatalog
import vn.com.quyln.mistia.core.model.TransactionCategoryRecord
import vn.com.quyln.mistia.core.model.isUntouchedSystemCategorySeed

typealias CategoryPushSummary = DomainPushSummary

class CategoryPushCoordinator(
    localStore: LocalStore,
    remoteStore: RemoteMutationStore,
    writesEnabled: Boolean,
    catalog: SystemCategoryCatalog? = null,
    nowEpochMillis: () -> Long = System::currentTimeMillis,
) : DomainPushCoordinator {
    private val delegate = OutboxPushCoordinator(
        entity = CloudEntity.TRANSACTION_CATEGORY,
        localStore = localStore,
        remoteStore = remoteStore,
        writesEnabled = writesEnabled,
        nowEpochMillis = nowEpochMillis,
        preferRemoteRecord = { queued, local, remote ->
            if (catalog == null || queued.mutation.baseVersion != 0L || local.syncVersion != 0L) false else {
                val decoded=TransactionCategoryRecord.fromCloudRecord(local)
                val parent=decoded.parentCategoryId?.let { id ->
                    localStore.record(UserId(local.ownerUserId),CloudEntity.TRANSACTION_CATEGORY.table,id)?.let { row ->
                        TransactionCategoryRecord.fromCloudRecord(row).takeIf { it.id==row.id && row.ownerUserId==local.ownerUserId }
                    }
                }
                val untouched=decoded.ownerUserId==local.ownerUserId && decoded.id==local.id && decoded.toPayload()==local.payload &&
                    local.updatedAt==decoded.updatedAt && decoded.isUntouchedSystemCategorySeed(catalog,parent)
                if (untouched) TransactionCategoryRecord.fromCloudRecord(remote)
                untouched
            }
        },
        orderMutations = { mutations, ownerUserId ->
            val childRecordIds = mutableSetOf<String>()
            for (queued in mutations) {
                val mutation = queued.mutation
                val payload = localStore.record(
                    ownerUserId,
                    CloudEntity.TRANSACTION_CATEGORY.table,
                    mutation.recordId,
                )?.payload ?: mutation.payload
                if (payload?.get("parent_category_id") != null &&
                    payload["parent_category_id"] !is JsonNull
                ) {
                    childRecordIds.add(mutation.recordId)
                }
            }
            mutations.withIndex().sortedWith(
                compareBy<IndexedValue<QueuedMutation>>(
                    { if (it.value.mutation.recordId in childRecordIds) 1 else 0 },
                    { it.value.mutation.modifiedAt },
                    { it.index },
                )
            ).map(IndexedValue<QueuedMutation>::value)
        },
    )

    override val entity: CloudEntity = CloudEntity.TRANSACTION_CATEGORY

    override suspend fun pushPending(
        ownerUserId: UserId,
        accessToken: String,
    ): CategoryPushSummary = delegate.pushPending(ownerUserId, accessToken)
}
