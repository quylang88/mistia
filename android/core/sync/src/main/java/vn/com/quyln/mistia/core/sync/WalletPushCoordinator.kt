package vn.com.quyln.mistia.core.sync

import vn.com.quyln.mistia.core.model.CloudEntity
import vn.com.quyln.mistia.core.model.LocalStore
import vn.com.quyln.mistia.core.model.RemoteMutationStore
import vn.com.quyln.mistia.core.model.UserId

typealias WalletPushSummary = DomainPushSummary

class WalletPushCoordinator(
    localStore: LocalStore,
    remoteStore: RemoteMutationStore,
    writesEnabled: Boolean,
    nowEpochMillis: () -> Long = System::currentTimeMillis,
) : DomainPushCoordinator {
    private val delegate = OutboxPushCoordinator(
        entity = CloudEntity.LEDGER_WALLET,
        localStore = localStore,
        remoteStore = remoteStore,
        writesEnabled = writesEnabled,
        nowEpochMillis = nowEpochMillis,
        preflight = {queued,local,owner,_ ->
            if(vn.com.quyln.mistia.core.model.requiresInvestmentWalletDomain(owner,local.id,local.payload) ||
                vn.com.quyln.mistia.core.model.requiresInvestmentWalletDomain(owner,queued.mutation.recordId,queued.mutation.payload)) MutationPreflight.Deferred
            else MutationPreflight.Continue
        },
        beforeRemoteWrite = {queued,local,owner,_ ->
            val current=localStore.record(owner,CloudEntity.LEDGER_WALLET.table,local.id)
            if(current==null) MutationPreflight.Stale
            else if(vn.com.quyln.mistia.core.model.requiresInvestmentWalletDomain(owner,current.id,current.payload) ||
                vn.com.quyln.mistia.core.model.requiresInvestmentWalletDomain(owner,queued.mutation.recordId,queued.mutation.payload)) MutationPreflight.Deferred
            else MutationPreflight.Continue
        },
    )

    override val entity: CloudEntity = CloudEntity.LEDGER_WALLET

    override suspend fun pushPending(
        ownerUserId: UserId,
        accessToken: String,
    ): WalletPushSummary = delegate.pushPending(ownerUserId, accessToken)
}
