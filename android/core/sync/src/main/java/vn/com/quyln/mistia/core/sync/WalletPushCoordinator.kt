package vn.com.quyln.mistia.core.sync

import vn.com.quyln.mistia.core.model.CloudEntity
import vn.com.quyln.mistia.core.model.LocalStore
import vn.com.quyln.mistia.core.model.RemoteMutationStore
import vn.com.quyln.mistia.core.model.UserId
import vn.com.quyln.mistia.core.model.QueuedMutation
import vn.com.quyln.mistia.core.model.CloudRecord
import vn.com.quyln.mistia.core.model.InvestmentWalletPublicationSnapshot
import vn.com.quyln.mistia.core.model.InvestmentWalletPublicationDependency

typealias WalletPushSummary = DomainPushSummary

class WalletPushCoordinator(
    localStore: LocalStore,
    remoteStore: RemoteMutationStore,
    writesEnabled: Boolean,
    private val investmentWalletSource:(suspend (UserId)->InvestmentWalletPublicationSnapshot)?=null,
    nowEpochMillis: () -> Long = System::currentTimeMillis,
) : DomainPushCoordinator {
    private suspend fun rootSource(owner:UserId)=investmentWalletSource?.invoke(owner)?.also{require(it.owner==owner)}
    private fun allows(source:InvestmentWalletPublicationSnapshot?,row:CloudRecord,q:QueuedMutation):Boolean {
        if(source==null || source.pending==null && !source.hasPendingMutation)return true
        val root=source.pending ?: return false
        return source.matches(root) && source.linkedRecord==row && source.linkedPending==q &&
            source.dependency()==InvestmentWalletPublicationDependency.WAITING_FOR_LINKED_WALLET
    }
    private val scopedStore=object:LocalStore by localStore {
        override suspend fun pendingMutations(ownerUserId:UserId,entity:CloudEntity,dueAtEpochMillis:Long,limit:Int):List<QueuedMutation> {
            val source=rootSource(ownerUserId)
            if(source==null || source.pending==null && !source.hasPendingMutation)
                return localStore.pendingMutations(ownerUserId,entity,dueAtEpochMillis,limit)
            // Select the exact current target directly; an unrelated due100 backlog cannot starve it.
            require(entity==CloudEntity.LEDGER_WALLET && limit>0)
            val row=source.linkedRecord ?: return emptyList()
            val queued=source.linkedPending ?: return emptyList()
            return if(queued.nextAttemptAtEpochMillis<=dueAtEpochMillis && allows(source,row,queued))listOf(queued) else emptyList()
        }
    }
    private val delegate = OutboxPushCoordinator(
        entity = CloudEntity.LEDGER_WALLET,
        localStore = scopedStore,
        remoteStore = remoteStore,
        writesEnabled = writesEnabled,
        nowEpochMillis = nowEpochMillis,
        preflight = {queued,local,owner,_ ->
            if(vn.com.quyln.mistia.core.model.requiresInvestmentWalletDomain(owner,local.id,local.payload) ||
                vn.com.quyln.mistia.core.model.requiresInvestmentWalletDomain(owner,queued.mutation.recordId,queued.mutation.payload)) MutationPreflight.Deferred
            else if(!allows(rootSource(owner),local,queued)) MutationPreflight.Deferred
            else MutationPreflight.Continue
        },
        beforeRemoteWrite = {queued,local,owner,_ ->
            val current=localStore.record(owner,CloudEntity.LEDGER_WALLET.table,local.id)
            if(current==null) MutationPreflight.Stale
            else if(vn.com.quyln.mistia.core.model.requiresInvestmentWalletDomain(owner,current.id,current.payload) ||
                vn.com.quyln.mistia.core.model.requiresInvestmentWalletDomain(owner,queued.mutation.recordId,queued.mutation.payload)) MutationPreflight.Deferred
            else if(!allows(rootSource(owner),current,queued)) MutationPreflight.Deferred
            else MutationPreflight.Continue
        },
    )

    override val entity: CloudEntity = CloudEntity.LEDGER_WALLET

    override suspend fun pushPending(
        ownerUserId: UserId,
        accessToken: String,
    ): WalletPushSummary = delegate.pushPending(ownerUserId, accessToken)
}
