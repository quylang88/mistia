package vn.com.quyln.mistia.core.sync

import vn.com.quyln.mistia.core.model.CloudEntity
import vn.com.quyln.mistia.core.model.LocalStore
import vn.com.quyln.mistia.core.model.RemoteMutationStore
import vn.com.quyln.mistia.core.model.UserId

typealias CreditCardPushSummary = DomainPushSummary

class CreditCardPushCoordinator(
    localStore: LocalStore,
    remoteStore: RemoteMutationStore,
    writesEnabled: Boolean,
    nowEpochMillis: () -> Long = System::currentTimeMillis,
) : DomainPushCoordinator {
    private val delegate = OutboxPushCoordinator(
        entity = CloudEntity.CREDIT_CARD_PROFILE,
        localStore = localStore,
        remoteStore = remoteStore,
        writesEnabled = writesEnabled,
        nowEpochMillis = nowEpochMillis,
    )

    override val entity: CloudEntity = CloudEntity.CREDIT_CARD_PROFILE

    override suspend fun pushPending(
        ownerUserId: UserId,
        accessToken: String,
    ): CreditCardPushSummary = delegate.pushPending(ownerUserId, accessToken)
}
