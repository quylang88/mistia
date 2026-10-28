package vn.com.quyln.mistia.core.sync

import vn.com.quyln.mistia.core.model.*
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive

/** One engine entry keeps prerequisite publication and retirement in their required phases. */
class InvestmentPublicationPushCoordinator(private val channel:DomainPushCoordinator,private val asset:DomainPushCoordinator,
    private val trade:DomainPushCoordinator,private val cash:DomainPushCoordinator?=null,private val reconciliation:DomainPushCoordinator?=null,private val linkedMove:DomainPushCoordinator?=null):DomainPushCoordinator {
    override val entity=CloudEntity.INVESTMENT_CHANNEL
    init {require(channel.entity==entity && asset.entity==CloudEntity.INVESTMENT_ASSET && trade.entity==CloudEntity.INVESTMENT_TRADE && (cash==null || cash.entity==CloudEntity.LEDGER_TRANSACTION) && (reconciliation==null || reconciliation.entity==CloudEntity.INVESTMENT_POSTING) && (linkedMove==null || linkedMove.entity==CloudEntity.INVESTMENT_POSTING))}
    override suspend fun pushPending(ownerUserId:UserId,accessToken:String):DomainPushSummary {
        val caller=currentCoroutineContext();var total=DomainPushSummary()
        for(publisher in listOfNotNull(channel,asset,trade,cash,reconciliation,linkedMove,asset,channel)) {
            caller.ensureActive();val next=publisher.pushPending(ownerUserId,accessToken);caller.ensureActive()
            total=DomainPushSummary(total.pushed+next.pushed,total.acknowledged+next.acknowledged,total.conflicts+next.conflicts,
                total.retryableFailures+next.retryableFailures,total.permanentFailures+next.permanentFailures,
                total.staleResponses+next.staleResponses,total.reconciled+next.reconciled)
        }
        return total
    }
}

/** Each due metadata proposal gets one turn. Deferred archives cannot permanently hide later dependencies. */
internal suspend fun investmentMetadataDueMutations(local:LocalStore,entity:CloudEntity,firstBatch:List<QueuedMutation>,
    owner:UserId,dueAt:Long,checkCurrent:()->Unit):List<QueuedMutation> {
    require(entity in setOf(CloudEntity.INVESTMENT_CHANNEL,CloudEntity.INVESTMENT_ASSET))
    val seed=firstBatch.firstOrNull() ?: return emptyList()
    checkCurrent()
    val full=local.investmentTradePublicationSnapshot(owner,seed.mutation.recordId)
    checkCurrent();require(full.owner==owner && full.tradeId==seed.mutation.recordId);full.requireCoherent()
    return full.pending.filter{it.mutation.entity==entity && it.nextAttemptAtEpochMillis<=dueAt}
        .sortedWith(compareBy<QueuedMutation>{it.mutation.modifiedAt}.thenBy{it.mutation.recordId})
}
