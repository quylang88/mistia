package vn.com.quyln.mistia.core.sync

import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import vn.com.quyln.mistia.core.model.MutationKind
import vn.com.quyln.mistia.core.model.CloudEntity
import vn.com.quyln.mistia.core.model.LocalStore
import vn.com.quyln.mistia.core.model.RemoteMutationStore
import vn.com.quyln.mistia.core.model.UserId

typealias BudgetPushSummary = DomainPushSummary

class BudgetPushCoordinator(
    localStore: LocalStore,
    remoteStore: RemoteMutationStore,
    writesEnabled: Boolean,
    nowEpochMillis: () -> Long = System::currentTimeMillis,
) : DomainPushCoordinator {
    private val delegate = OutboxPushCoordinator(
        entity = CloudEntity.BUDGET_PLAN,
        localStore = localStore,
        remoteStore = remoteStore,
        writesEnabled = writesEnabled,
        nowEpochMillis = nowEpochMillis,
        allowTombstoneDeletes = true,
        orderMutations = { mutations, owner ->
            val pendingCategories = localStore.pendingMutationRecordIds(owner, CloudEntity.TRANSACTION_CATEGORY.table)
            mutations.filter { queued ->
                if (queued.mutation.kind == MutationKind.DELETE) true
                else {
                    val payload = localStore.record(owner, CloudEntity.BUDGET_PLAN.table, queued.mutation.recordId)?.payload
                        ?: queued.mutation.payload
                    val categoryId = (payload?.get("category_id") as? JsonPrimitive)?.contentOrNull
                    categoryId == null || categoryId !in pendingCategories
                }
            }
        },
    )

    override val entity: CloudEntity = CloudEntity.BUDGET_PLAN

    override suspend fun pushPending(
        ownerUserId: UserId,
        accessToken: String,
    ): BudgetPushSummary = delegate.pushPending(ownerUserId, accessToken)
}
