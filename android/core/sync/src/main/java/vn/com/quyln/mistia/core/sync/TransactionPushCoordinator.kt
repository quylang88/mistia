package vn.com.quyln.mistia.core.sync

import vn.com.quyln.mistia.core.model.CloudEntity
import vn.com.quyln.mistia.core.model.LocalStore
import vn.com.quyln.mistia.core.model.RemoteMutationStore
import vn.com.quyln.mistia.core.model.UserId

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
    )

    override val entity: CloudEntity = CloudEntity.LEDGER_TRANSACTION

    override suspend fun pushPending(
        ownerUserId: UserId,
        accessToken: String,
    ): TransactionPushSummary = delegate.pushPending(ownerUserId, accessToken)
}
