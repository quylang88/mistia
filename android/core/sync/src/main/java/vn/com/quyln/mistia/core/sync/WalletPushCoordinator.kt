package vn.com.quyln.mistia.core.sync

import vn.com.quyln.mistia.core.model.CloudEntity
import vn.com.quyln.mistia.core.model.LocalStore
import vn.com.quyln.mistia.core.model.RemoteMutationStore
import vn.com.quyln.mistia.core.model.UserId
import vn.com.quyln.mistia.core.model.QueuedMutation
import vn.com.quyln.mistia.core.model.CloudRecord
import vn.com.quyln.mistia.core.model.InvestmentWalletPublicationSnapshot
import vn.com.quyln.mistia.core.model.InvestmentWalletPublicationDependency
import vn.com.quyln.mistia.core.model.*

typealias WalletPushSummary = DomainPushSummary

class WalletPushCoordinator(
    private val localStore: LocalStore,
    private val remoteStore: RemoteMutationStore,
    private val writesEnabled: Boolean,
    private val investmentWalletSource:(suspend (UserId)->InvestmentWalletPublicationSnapshot)?=null,
    private val investmentRetirementSource:(suspend (UserId,String)->InvestmentTradePublicationSnapshot)?=null,
    private val investmentPrerequisites:WalletInvestmentPrerequisiteCoordinator?=null,
    private val nowEpochMillis: () -> Long = System::currentTimeMillis,
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
            if(source==null || source.pending==null && !source.hasPendingMutation) {
                val ordinary=localStore.pendingMutations(ownerUserId,entity,dueAtEpochMillis,limit)
                val financial=investmentRetirementSource?.invoke(ownerUserId,"00000000-0000-0000-0000-000000000000") ?: return ordinary
                require(financial.owner==ownerUserId);financial.requireCoherent()
                // One reserved priority slot prevents a due100 ordinary backlog from
                // starving preparation without starving unrelated metadata themselves.
                val reserved=financial.pending.firstOrNull{q->q.mutation.entity==entity && q.nextAttemptAtEpochMillis<=dueAtEpochMillis &&
                    financial.rows.single{it.entity==entity.table && it.id==q.mutation.recordId}.payload.financeRawArchived()==true &&
                    walletHasPendingInvestmentFinancialDependency(financial,q.mutation.recordId)}
                return (listOfNotNull(reserved)+ordinary).distinct().take(limit)
            }
            // Select the exact current target directly; an unrelated due100 backlog cannot starve it.
            require(entity==CloudEntity.LEDGER_WALLET && limit>0)
            val row=source.linkedRecord ?: return emptyList()
            val queued=source.linkedPending ?: return emptyList()
            return if(queued.nextAttemptAtEpochMillis<=dueAtEpochMillis && allows(source,row,queued))listOf(queued) else emptyList()
        }
    }
    private suspend fun retirement(queued:QueuedMutation,row:CloudRecord,owner:UserId,run:WalletInvestmentPrerequisiteRun?,beforeWrite:Boolean):MutationPreflight {
        if(row.payload.financeRawArchived()!=true)return MutationPreflight.Continue
        val s=try{investmentRetirementSource?.invoke(owner,row.id)}catch(cancelled:kotlinx.coroutines.CancellationException){throw cancelled}
            catch(error:Exception){throw MutationFailurePersistenceException(error)} ?: return MutationPreflight.Continue
        run?.checkCurrent();require(s.owner==owner);s.requireCoherent()
        if(queued !in s.pending || s.rows.singleOrNull{it.entity==row.entity && it.id==row.id}!=row)return MutationPreflight.Stale
        if(!walletHasPendingInvestmentFinancialDependency(s,row.id))return MutationPreflight.Continue
        return if(beforeWrite || run==null)MutationPreflight.Deferred else run.prepare(s,queued,row)
    }
    private fun delegate(run:WalletInvestmentPrerequisiteRun?) = OutboxPushCoordinator(
        entity = CloudEntity.LEDGER_WALLET,
        localStore = scopedStore,
        remoteStore = object:RemoteMutationStore by remoteStore {
            override suspend fun createRecord(entity:CloudEntity,accessToken:String,ownerUserId:UserId,payload:kotlinx.serialization.json.JsonObject)=
                remoteStore.createRecord(entity,accessToken,ownerUserId,walletInvestmentPayloadForCloud(payload))
            override suspend fun conditionalUpdate(entity:CloudEntity,recordId:String,accessToken:String,ownerUserId:UserId,expectedVersion:Long,payload:kotlinx.serialization.json.JsonObject)=
                remoteStore.conditionalUpdate(entity,recordId,accessToken,ownerUserId,expectedVersion,walletInvestmentPayloadForCloud(payload))
        },
        writesEnabled = writesEnabled,
        nowEpochMillis = nowEpochMillis,
        normalizeSemanticPayload=::walletInvestmentPayloadForCloud,
        validateRecord=::validateWalletInvestmentPrerequisiteJournal,
        recordFailureOverride={q,next,code->run?.failure(q,next,code)},
        preflight = {queued,local,owner,_ ->
            run?.checkCurrent()
            if(vn.com.quyln.mistia.core.model.requiresInvestmentWalletDomain(owner,local.id,local.payload) ||
                vn.com.quyln.mistia.core.model.requiresInvestmentWalletDomain(owner,queued.mutation.recordId,queued.mutation.payload)) MutationPreflight.Deferred
            else if(!allows(rootSource(owner),local,queued)) MutationPreflight.Deferred
            else retirement(queued,local,owner,run,false)
        },
        beforeRemoteWrite = {queued,local,owner,_ ->
            run?.checkCurrent()
            val current=localStore.record(owner,CloudEntity.LEDGER_WALLET.table,local.id)
            if(current==null || current!=local) MutationPreflight.Stale
            else if(vn.com.quyln.mistia.core.model.requiresInvestmentWalletDomain(owner,current.id,current.payload) ||
                vn.com.quyln.mistia.core.model.requiresInvestmentWalletDomain(owner,queued.mutation.recordId,queued.mutation.payload)) MutationPreflight.Deferred
            else if(!allows(rootSource(owner),current,queued)) MutationPreflight.Deferred
            else retirement(queued,current,owner,run,true)
        },
    )

    override val entity: CloudEntity = CloudEntity.LEDGER_WALLET

    override suspend fun pushPending(
        ownerUserId: UserId,
        accessToken: String,
    ): WalletPushSummary {
        if(!writesEnabled)return WalletPushSummary()
        val run=investmentPrerequisites?.begin(ownerUserId,accessToken)
        return delegate(run).pushPending(ownerUserId,accessToken).also{run?.checkCurrent()}
    }
}
