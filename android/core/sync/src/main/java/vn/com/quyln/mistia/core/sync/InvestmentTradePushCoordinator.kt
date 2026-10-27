package vn.com.quyln.mistia.core.sync

import java.io.IOException
import java.time.Instant
import kotlinx.coroutines.*
import kotlinx.serialization.json.*
import vn.com.quyln.mistia.core.model.*
import vn.com.quyln.mistia.core.network.SupabaseHttpException

/** Trade intents use atomic RPCs; their derived rows are acknowledged only as a complete financial result. */
class InvestmentTradePushCoordinator(
    private val localStore:LocalStore,private val remote:InvestmentTradeRemote,private val writesEnabled:Boolean,
    private val currentSession:()->AuthSession?,private val nowEpochMillis:()->Long=System::currentTimeMillis,
    private val metadataRemote:InvestmentTradeMetadataRemote?=null,
):DomainPushCoordinator {
    override val entity=CloudEntity.INVESTMENT_TRADE
    override suspend fun pushPending(ownerUserId:UserId,accessToken:String):DomainPushSummary {
        if(!writesEnabled)return DomainPushSummary()
        val caller=currentCoroutineContext();caller.ensureActive();val captured=currentSession()
        if(captured==null || captured.userId!=ownerUserId || captured.accessToken!=accessToken || accessToken.isBlank())throw CancellationException("Investment trade session changed")
        fun checkSession() {caller.ensureActive();if(currentSession()!=captured)throw CancellationException("Investment trade session changed");caller.ensureActive()}
        suspend fun source(id:String):InvestmentTradePublicationSnapshot {
            checkSession();val result=localStore.investmentTradePublicationSnapshot(ownerUserId,id);checkSession()
            require(result.owner==ownerUserId && result.tradeId==id);result.requireCoherent();return result
        }
        var summary=DomainPushSummary();val now=nowEpochMillis();require(now>=0)
        val groups=linkedMapOf<Set<String>,String>();val written=mutableMapOf<String,String>()
        suspend fun failure(expected:InvestmentTradePublicationSnapshot,error:Exception) {
            checkSession();val q=expected.requestedQueue ?: return
            val retry=when(error) {
                is SupabaseHttpException->error.statusCode>=500 || error.statusCode in setOf(408,429)
                is IOException,is InvestmentTradeResultException->true
                else->false
            }
            val code=when(error) {
                is SupabaseHttpException->"http_${error.statusCode}"
                is TradePublicationDependency->"investment_trade_dependency_pending"
                is IOException->"network_io"
                is InvestmentTradeResultException->"investment_trade_result_inconsistent"
                is TradePublicationConflict->"conflict_${error.reason}"
                else->"invalid_investment_trade_publication"
            }
            val delay=minOf(30_000L*(1L shl q.attemptCount.coerceIn(0,10)),21_600_000L)
            val next=if(retry && now<=Long.MAX_VALUE-delay)now+delay else Long.MAX_VALUE
            // Storage errors propagate. Never fall back to an unfenced generic failure write.
            val accepted=localStore.recordInvestmentTradeMutationFailure(q,next,code,expected,{currentSession()==captured})
            checkSession()
            summary=when {
                !accepted->summary.copy(staleResponses=summary.staleResponses+1)
                error is TradePublicationConflict->summary.copy(conflicts=summary.conflicts+1)
                retry->summary.copy(retryableFailures=summary.retryableFailures+1)
                else->summary.copy(permanentFailures=summary.permanentFailures+1)
            }
        }
        fun assets(local:CloudRecord,server:CloudRecord?)=setOfNotNull(local.payload.financeRawString("asset_id"),server?.payload?.financeRawString("asset_id"))
        suspend fun observeHistory(s:InvestmentTradePublicationSnapshot,affected:Set<String>):List<CloudRecord> {
            val known=s.rows.filter{it.entity==entity.table && it.payload.financeRawString("asset_id") in affected}.map{it.id}.toSet()+s.tradeId
            checkSession();val candidate=remote.fetchTradeResult(ownerUserId,affected,known,accessToken);checkSession()
            require(candidate.owner==ownerUserId && candidate.affectedAssetIds==affected && candidate.remoteIntentWinners.isEmpty())
            return candidate.rows.filter{it.entity==entity.table}
        }
        suspend fun validateDependencies(s:InvestmentTradePublicationSnapshot,affected:Set<String>,device:String):List<CloudRecord> {
            val metadata=mutableListOf<CloudRecord>()
            if(metadataRemote!=null) {
                val dependencies=linkedSetOf<Pair<CloudEntity,String>>()
                for(id in affected) {
                    dependencies+=CloudEntity.INVESTMENT_ASSET to id
                    val asset=s.rows.singleOrNull{it.entity==CloudEntity.INVESTMENT_ASSET.table && it.id==id}
                    asset?.payload?.financeRawString("channel_id")?.let{dependencies+=CloudEntity.INVESTMENT_CHANNEL to it}
                }
                for((entity,id) in dependencies) {
                    val local=s.rows.singleOrNull{it.entity==entity.table && it.id==id} ?: continue
                    if(entity.table to id in s.dirtyKeys && local.deletedAt==null && local.payload.financeRawArchived()==true) {
                        checkSession();val active=metadataRemote.fetchMetadata(ownerUserId,entity,id,accessToken);checkSession()
                        active?.let(metadata::add)
                    }
                }
            }
            val trades=s.rows.filter{it.entity==entity.table && it.payload.financeRawString("asset_id") in affected}
                .map{it.copy(payload=JsonObject(it.payload-LOCAL_TRADE_PUBLICATION_PARENTS_KEY))}
            projectInvestmentTradePublicationResult(s,trades,affected,device,Instant.ofEpochMilli(now).toString(),metadata)
            return metadata
        }
        val initial=source("00000000-0000-0000-0000-000000000000")
        val initialRows=initial.rows.filter{it.entity==entity.table}.associateBy{it.id}
        fun date(q:QueuedMutation,key:String)=runCatching{Instant.parse(initialRows[q.mutation.recordId]?.payload?.financeRawString(key))}.getOrDefault(Instant.MIN)
        val chronological=compareBy<QueuedMutation>{date(it,"occurred_at")}.thenBy{date(it,"created_at")}.thenBy{it.mutation.recordId}
        val due=initial.pending.filter{it.mutation.entity==entity && it.nextAttemptAtEpochMillis<=now}
            .sortedWith(compareBy<QueuedMutation>{if(it.mutation.kind==MutationKind.DELETE)0 else 1}.thenComparator{a,b->
                // Remove later sales before their acquisitions; publish live history in FIFO input order.
                if(a.mutation.kind==MutationKind.DELETE)chronological.compare(b,a) else chronological.compare(a,b)
            })
        var remaining=due
        var rounds=0
        while(remaining.isNotEmpty()) {
            val deferred=linkedMapOf<String,InvestmentTradePublicationSnapshot>()
            var progressed=false
            for(selected in remaining) {
                var expected=source(selected.mutation.recordId)
                val q=expected.requestedQueue ?: continue
                if(q.nextAttemptAtEpochMillis>now)continue
                try {
                    val local=requireNotNull(expected.requestedRecord);requireInvestmentTradeForPublication(ownerUserId,local,forWrite=false)
                    val localAssets=assets(local,null);validateDependencies(expected,localAssets,q.mutation.deviceId)
                    checkSession();var server=remote.fetchTrade(ownerUserId,local.id,accessToken);checkSession()
                    server?.let{require(it.id==local.id);requireInvestmentTradeForPublication(ownerUserId,it,forWrite=false,allowLocalEvidence=false)}
                    val fresh=source(local.id)
                    if(runCatching{expected.requireUnchanged(fresh)}.isFailure) {summary=summary.copy(staleResponses=summary.staleResponses+1);continue}
                    var affected=assets(local,server)
                    var observed=server!=null || q.remoteIdentityObserved || q.mutation.baseVersion>0
                    var completed=false
                    for(attempt in 0..1) {
                        val compared=server
                        affected=assets(local,compared);validateDependencies(fresh,affected,q.mutation.deviceId)
                        if(compared==null && observed)throw TradePublicationConflict("investment_trade_missing")
                        if(compared==null && local.deletedAt!=null || compared!=null && investmentTradePublicationIntentsMatch(local,compared)) {
                            completed=true;break
                        }
                        if(compared!=null)when(resolveInvestmentTradePublication(local,compared,q.mutation.deviceId).winner) {
                            RecordConflictWinner.REMOTE->{completed=true;break}
                            RecordConflictWinner.UNRESOLVED->throw TradePublicationConflict("investment_trade_unresolved")
                            RecordConflictWinner.LOCAL->Unit
                        }
                        val base=compared?.syncVersion ?: 0L;require(maxOf(base,local.syncVersion)<Long.MAX_VALUE-1)
                        val version=if(local.deletedAt==null)maxOf(base,local.syncVersion)+1 else local.syncVersion
                        val sent=local.copy(syncVersion=version,payload=JsonObject(investmentTradePayloadForCloud(local.payload)+("sync_version" to JsonPrimitive(version))))
                        val history=observeHistory(expected,affected)
                        expected.requireUnchanged(source(local.id))
                        val observedTarget=history.singleOrNull{it.id==local.id}
                        if(observedTarget!=compared) {
                            server=observedTarget;observed=observed || server!=null;continue
                        }
                        if(!canApplyInvestmentTradeToCloudHistory(ownerUserId,history,local))throw TradePublicationDependency()
                        val deleteBefore=history.takeIf{local.deletedAt!=null}
                        checkSession()
                        val returned=try {
                            if(local.deletedAt==null) {
                                val result=remote.mutateTrade(ownerUserId,sent,base,affected,accessToken)
                                result?.also{require(it.requested==it.trades.single{row->row.id==sent.id})}?.trades
                            } else remote.deleteTrade(ownerUserId,local.id,base,requireNotNull(local.deletedAt),q.mutation.deviceId,accessToken)?.let{listOf(it)}
                        }catch(http:SupabaseHttpException) {
                            if(http.statusCode!=409)throw http
                            null
                        }
                        checkSession()
                        if(returned!=null) {
                            val trace=deleteBefore?.let{InvestmentTradeDeleteRebuild(it,observeHistory(expected,affected))}
                            val receipt=InvestmentTradePublicationReceipt(expected,sent,base,returned,affected,trace)
                            if(trace!=null)try {investmentTradeDeleteRebuildPeers(receipt)}catch(invalid:IllegalArgumentException) {
                                throw InvestmentTradeResultException(InvestmentTradeResultError.INCOMPLETE_RESULT)
                            }
                            localStore.recordInvestmentTradePublicationReceipt(receipt,{currentSession()==captured})
                            checkSession();written[local.id]=investmentTradeIntentFingerprint(sent.payload);completed=true;break
                        }
                        server=remote.fetchTrade(ownerUserId,local.id,accessToken);checkSession()
                        server?.let{require(it.id==local.id);requireInvestmentTradeForPublication(ownerUserId,it,forWrite=false,allowLocalEvidence=false)}
                        observed=observed || server!=null
                        if(runCatching{expected.requireUnchanged(source(local.id))}.isFailure)break
                    }
                    if(!completed)throw TradePublicationConflict("investment_trade_compare_race")
                    groups[affected]=local.id;progressed=true
                }catch(cancelled:CancellationException){throw cancelled}
                catch(dependency:TradePublicationDependency){deferred[selected.mutation.recordId]=expected}
                catch(error:InvestmentTradeResultException) {
                    if(error.reason!=InvestmentTradeResultError.DEPENDENCY_PENDING)failure(expected,error)
                }catch(http:SupabaseHttpException) {
                    if(http.statusCode==400 && remaining.any{it.mutation.recordId!=selected.mutation.recordId})deferred[selected.mutation.recordId]=expected
                    else failure(expected,http)
                }catch(error:Exception){failure(expected,error)}
            }
            if(deferred.isEmpty())break
            if(!progressed || rounds++>=due.size) {
                for(decisionSource in deferred.values)failure(decisionSource,TradePublicationDependency())
                break
            }
            remaining=deferred.values.mapNotNull{it.requestedQueue}
        }
        // Finish all due user proposals before proving a whole affected asset's derived result.
        for((affected,requested) in groups) {
            var expected=source(requested)
            try {
                val q=expected.requestedQueue ?: continue
                if(expected.pending.any{queued->queued.mutation.entity==entity && queued.mutation.recordId in written &&
                        expected.rows.singleOrNull{it.entity==entity.table && it.id==queued.mutation.recordId}?.let{investmentTradeIntentFingerprint(it.payload)}!=written[queued.mutation.recordId]}) {
                    summary=summary.copy(staleResponses=summary.staleResponses+1);continue
                }
                val metadata=validateDependencies(expected,affected,q.mutation.deviceId)
                val known=expected.rows.filter{it.entity==entity.table && it.payload.financeRawString("asset_id") in affected}.map{it.id}.toSet()+requested
                checkSession();var candidate=remote.fetchTradeResult(ownerUserId,affected,known,accessToken);checkSession()
                require(candidate.owner==ownerUserId && candidate.affectedAssetIds==affected && candidate.remoteIntentWinners.isEmpty())
                val winners=candidate.rows.filter{it.entity==entity.table}.filter{row->
                    val local=expected.rows.singleOrNull{it.entity==row.entity && it.id==row.id}
                    val queue=expected.pending.singleOrNull{it.mutation.entity==entity && it.mutation.recordId==row.id}
                    local!=null && queue!=null && !investmentTradePublicationIntentsMatch(local,row) &&
                        resolveInvestmentTradePublication(local,row,queue.mutation.deviceId).winner==RecordConflictWinner.REMOTE
                }.map{it.id}.toSet()
                candidate=candidate.copy(remoteIntentWinners=winners,metadata=metadata)
                val plan=planInvestmentTradeResultAcknowledgement(expected,candidate,q.mutation.deviceId,Instant.ofEpochMilli(now).toString())
                val tradeIds=(plan.acknowledgements.map{it.first}+plan.absentAcknowledgements).filter{it.mutation.entity==entity}.map{it.mutation.recordId}.toSet()
                checkSession()
                if(localStore.acknowledgeInvestmentTradeResult(expected,candidate,q.mutation.deviceId,Instant.ofEpochMilli(now).toString(),{currentSession()==captured}))
                    summary=summary.copy(pushed=summary.pushed+tradeIds.count{it in written},acknowledged=summary.acknowledged+tradeIds.count{it !in written})
                else summary=summary.copy(staleResponses=summary.staleResponses+1)
                checkSession()
            }catch(cancelled:CancellationException){throw cancelled}
            catch(error:InvestmentTradeResultException) {
                if(error.reason!=InvestmentTradeResultError.DEPENDENCY_PENDING)failure(expected,error)
            }catch(error:Exception){failure(expected,error)}
        }
        checkSession();return summary
    }
}

private class TradePublicationConflict(val reason:String):IllegalStateException(reason)

private class TradePublicationDependency:IOException("Investment trade intermediate history is waiting for a prerequisite")
