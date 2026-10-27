package vn.com.quyln.mistia.core.sync

import java.time.Instant
import kotlinx.serialization.json.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import vn.com.quyln.mistia.core.model.*

class InvestmentChannelPushCoordinator(
    private val localStore:LocalStore,private val remoteStore:RemoteMutationStore,private val writesEnabled:Boolean,
    private val currentSession:()->AuthSession?,private val nowEpochMillis:()->Long=System::currentTimeMillis,
    private val retirementRemote:InvestmentRetirementRemote?=null,
):DomainPushCoordinator {
    override val entity=CloudEntity.INVESTMENT_CHANNEL
    override suspend fun pushPending(ownerUserId:UserId,accessToken:String):DomainPushSummary {
        if(!writesEnabled)return DomainPushSummary()
        val caller=currentCoroutineContext();caller.ensureActive()
        val captured=currentSession()
        if(captured==null || captured.userId!=ownerUserId || captured.accessToken!=accessToken || accessToken.isBlank())
            throw CancellationException("Investment channel session changed")
        fun checkSession() {
            caller.ensureActive()
            if(currentSession()!=captured)throw CancellationException("Investment channel session changed")
            caller.ensureActive()
        }
        val stager=InvestmentMetadataStager(entity,localStore,remoteStore,ownerUserId,accessToken,::checkSession,{currentSession()==captured})
        var selected:QueuedMutation?=null
        var archiveFailure:Pair<QueuedMutation,Exception>?=null
        suspend fun <T> archiveWrite(id:String,payload:JsonObject,write:suspend ()->T):T = try{write()}catch(error:Exception) {
            if(retirementRemote!=null && payload.financeRawArchived()==true)selected?.takeIf{it.mutation.recordId==id}?.let{archiveFailure=it to error}
            throw error
        }
        suspend fun preflight(queued:QueuedMutation,local:CloudRecord):MutationPreflight {
            checkSession()
            val source=localStore.investmentChannelPublicationSnapshot(ownerUserId,queued.mutation.recordId)
            checkSession()
            if(!source.matches(queued,local))return MutationPreflight.Stale
            selected=queued
            if(retirementRemote!=null && LOCAL_INVESTMENT_METADATA_STAGES_KEY in local.payload)
                stager.recover(queued,local)?.let{return it}
            if(retirementRemote!=null && local.deletedAt==null && local.payload.financeRawArchived()==true) {
                val full=localStore.investmentTradePublicationSnapshot(ownerUserId,local.id)
                checkSession();full.requireCoherent()
                if(full.rows.singleOrNull{it.entity==entity.table && it.id==local.id}!=local || queued !in full.pending)return MutationPreflight.Stale
                val history=try{retirementRemote.fetchRetirementHistory(ownerUserId,entity,local.id,accessToken)}catch(_:InvestmentRetirementHistoryChanged){checkSession();return MutationPreflight.Deferred}
                checkSession();require(history.owner==ownerUserId && history.entity==entity && history.id==local.id)
                val current=localStore.investmentTradePublicationSnapshot(ownerUserId,local.id);checkSession()
                if(runCatching{full.requireUnchanged(current)}.isFailure)return MutationPreflight.Stale
                if(!investmentRetirementHistoryIsClosed(history) || investmentRetirementHasPendingDependencies(full,history))
                    return stager.publishActive(full,queued,local)
            }
            return MutationPreflight.Continue
        }
        checkSession()
        val adapter=object:RemoteMutationStore {
            override suspend fun fetchRecord(entity:CloudEntity,recordId:String,accessToken:String,ownerUserId:UserId):CloudRecord? =
                remoteStore.fetchRecord(entity,recordId,accessToken,ownerUserId)
            override suspend fun createRecord(entity:CloudEntity,accessToken:String,ownerUserId:UserId,payload:JsonObject):CloudRecord =
                archiveWrite(requireNotNull(payload.financeRawString("id")),payload){remoteStore.createRecord(entity,accessToken,ownerUserId,payload)}
            override suspend fun conditionalUpdate(entity:CloudEntity,recordId:String,accessToken:String,ownerUserId:UserId,expectedVersion:Long,payload:JsonObject):CloudRecord? =
                archiveWrite(recordId,payload){remoteStore.conditionalUpdate(entity,recordId,accessToken,ownerUserId,expectedVersion,payload)}
        }
        val delegate=OutboxPushCoordinator(entity,localStore,adapter,writesEnabled,nowEpochMillis,
            orderMutations={first,owner->if(retirementRemote==null)first else
                investmentMetadataDueMutations(localStore,entity,first,owner,nowEpochMillis(),::checkSession)},
            allowTombstoneDeletes=true,
            retryableFailureOverride={q,error->if(archiveFailure?.first==q && archiveFailure?.second===error &&
                (error as? vn.com.quyln.mistia.core.network.SupabaseHttpException)?.statusCode==400)true else null},
            validateRecord={row->InvestmentChannelRecord.fromCloudRecord(row);localInvestmentMetadataStages(row)},
            normalizeSemanticPayload={payload->JsonObject(investmentMetadataPayloadForCloud(payload).mapValues{(key,value)->
                if(key=="archived_at" && value is JsonPrimitive && value.isString)JsonPrimitive(Instant.parse(value.content).toString()) else value
            })},
            preflight={q,row,_,_->preflight(q,row)},
            beforeRemoteWrite={q,row,_,_->preflight(q,row)},
            acknowledgeOverride={q,remote->
                checkSession()
                val accepted=localStore.acknowledgeInvestmentChannelMutation(q,remote){currentSession()==captured}
                checkSession()
                if(accepted)MutationAcknowledgement.Committed else MutationAcknowledgement.Stale
            },
            recordFailureOverride={q,next,code->
                checkSession()
                val recorded=localStore.recordInvestmentChannelMutationFailure(stager.failureQueue(q),next,code){currentSession()==captured}
                checkSession();recorded
            })
        return delegate.pushPending(ownerUserId,accessToken).also{checkSession()}
    }
}
