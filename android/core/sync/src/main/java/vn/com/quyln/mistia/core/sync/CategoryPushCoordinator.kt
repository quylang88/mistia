package vn.com.quyln.mistia.core.sync

import kotlinx.serialization.json.JsonNull
import vn.com.quyln.mistia.core.model.CloudEntity
import vn.com.quyln.mistia.core.model.LocalStore
import vn.com.quyln.mistia.core.model.QueuedMutation
import vn.com.quyln.mistia.core.model.RemoteMutationStore
import vn.com.quyln.mistia.core.model.UserId

typealias CategoryPushSummary = DomainPushSummary

class CategoryPushCoordinator(
    localStore: LocalStore,
    remoteStore: RemoteMutationStore,
    writesEnabled: Boolean,
    nowEpochMillis: () -> Long = System::currentTimeMillis,
) : DomainPushCoordinator {
    private val delegate = OutboxPushCoordinator(
        entity = CloudEntity.TRANSACTION_CATEGORY,
        localStore = localStore,
        remoteStore = remoteStore,
        writesEnabled = writesEnabled,
        nowEpochMillis = nowEpochMillis,
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
