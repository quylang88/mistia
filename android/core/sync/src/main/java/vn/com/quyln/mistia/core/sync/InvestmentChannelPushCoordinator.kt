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
        suspend fun preflight(queued:QueuedMutation,local:CloudRecord):MutationPreflight {
            checkSession()
            val source=localStore.investmentChannelPublicationSnapshot(ownerUserId,queued.mutation.recordId)
            checkSession()
            return if(source.matches(queued,local))MutationPreflight.Continue else MutationPreflight.Stale
        }
        checkSession()
        val delegate=OutboxPushCoordinator(entity,localStore,remoteStore,writesEnabled,nowEpochMillis,
            allowTombstoneDeletes=true,
            validateRecord={row->InvestmentChannelRecord.fromCloudRecord(row)},
            normalizeSemanticPayload={payload->JsonObject(payload.mapValues{(key,value)->
                if(key=="archived_at" && value is JsonPrimitive && value.isString)JsonPrimitive(Instant.parse(value.content).toString()) else value
            })},
            preflight={q,row,_,_->preflight(q,row)},
            beforeRemoteWrite={q,row,_,_->preflight(q,row)},
            acknowledgeOverride={q,remote->
                checkSession()
                val accepted=localStore.acknowledgeInvestmentChannelMutation(q,remote)
                checkSession()
                if(accepted)MutationAcknowledgement.Committed else MutationAcknowledgement.Stale
            },
            recordFailureOverride={q,next,code->
                checkSession()
                val recorded=localStore.recordInvestmentChannelMutationFailure(q,next,code)
                checkSession();recorded
            })
        return delegate.pushPending(ownerUserId,accessToken).also{checkSession()}
    }
}
