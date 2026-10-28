package vn.com.quyln.mistia.core.sync

import java.io.IOException
import kotlinx.coroutines.*
import kotlinx.serialization.json.*
import vn.com.quyln.mistia.core.model.*
import vn.com.quyln.mistia.core.network.SupabaseHttpException

/** Cash events use their atomic RPC. Financial ACK and failure bookkeeping retain the captured generation. */
class InvestmentCashEventPushCoordinator(private val localStore:LocalStore,private val remote:InvestmentCashEventRemote,
    private val writesEnabled:Boolean,private val currentSession:()->AuthSession?,private val nowEpochMillis:()->Long=System::currentTimeMillis):DomainPushCoordinator {
    override val entity=CloudEntity.LEDGER_TRANSACTION
    override suspend fun pushPending(ownerUserId:UserId,accessToken:String):DomainPushSummary {
        if(!writesEnabled)return DomainPushSummary()
        val caller=currentCoroutineContext();caller.ensureActive();val captured=currentSession()
        if(captured==null || captured.userId!=ownerUserId || captured.accessToken!=accessToken || accessToken.isBlank())throw CancellationException("Cash event session changed")
        fun checkCurrent(){caller.ensureActive();if(currentSession()!=captured)throw CancellationException("Cash event session changed");caller.ensureActive()}
        suspend fun source(id:String):InvestmentCashEventPublicationSnapshot {
            checkCurrent();val s=localStore.investmentCashEventPublicationSnapshot(ownerUserId,id);checkCurrent()
            require(s.owner==ownerUserId && s.eventId==id);s.requireCoherent();return s
        }
        suspend fun <T> persist(action:suspend ()->T):T=try{action()}catch(cancelled:CancellationException){throw cancelled}
            catch(error:Exception){throw CashEventPersistenceFailure(error)}
        suspend fun unchanged(s:InvestmentCashEventPublicationSnapshot):Boolean {
            val current=persist{source(s.eventId)};return runCatching{s.requireUnchanged(current)}.isSuccess
        }
        val now=nowEpochMillis();require(now>=0);var summary=DomainPushSummary()
        val initial=source("00000000-0000-0000-0000-000000000000")
        val rows=initial.rows.associateBy{it.entity to it.id}
        val due=initial.pending.filter{q->q.mutation.entity==entity && q.nextAttemptAtEpochMillis<=now &&
            rows[q.mutation.entity.table to q.mutation.recordId]?.payload?.financeRawString("settlement_role_raw_value") in setOf("investmentCashDeposit","investmentCashWithdrawal")}
            .sortedWith(compareBy<QueuedMutation>{it.mutation.modifiedAt}.thenBy{it.mutation.recordId})
        for(selected in due) {
            checkCurrent();val s=source(selected.mutation.recordId)
            if(!s.matches(selected)){summary=summary.copy(staleResponses=summary.staleResponses+1);continue}
            try {
                val local=requireNotNull(s.requestedRecord);val q=selected.mutation
                if(!ready(s,local))continue
                checkCurrent();val observed=remote.fetchEvent(ownerUserId,s.eventId,accessToken);checkCurrent()
                require(observed.owner==ownerUserId && observed.eventId==s.eventId)
                if(!unchanged(s)){summary=summary.copy(staleResponses=summary.staleResponses+1);continue}
                val same=runCatching{planInvestmentCashEventResultAcknowledgement(s,observed)}.isSuccess
                if(same) {
                    checkCurrent();val accepted=persist{localStore.acknowledgeInvestmentCashEventResult(s,observed,q.deviceId,q.modifiedAt){currentSession()==captured}};checkCurrent()
                    summary=if(accepted)summary.copy(acknowledged=summary.acknowledged+1) else summary.copy(staleResponses=summary.staleResponses+1)
                    continue
                }
                val server=observed.transaction
                val canonical=investmentLedgerIdentity(s.eventId,"cash-transfer-posting")
                val remotePost=observed.postings.singleOrNull{it.id==canonical}
                if(server==null && (q.baseVersion>0 || selected.remoteIdentityObserved || observed.postings.isNotEmpty()))throw CashEventConflict("missing_event")
                if(server!=null) {
                    require(server.entity==entity.table && server.id==local.id && server.ownerUserId==ownerUserId.value)
                    if(server.syncVersion<q.baseVersion)throw CashEventConflict("regressed_event")
                    if(remotePost==null)throw IOException("Incomplete cash event result")
                    if(server.syncVersion>q.baseVersion) {
                        when(resolveInvestmentCashEventPublication(local,server,q.deviceId).winner) {
                            RecordConflictWinner.UNRESOLVED->throw CashEventConflict("unproven_remote_change")
                            RecordConflictWinner.LOCAL->Unit
                            RecordConflictWinner.REMOTE->{
                                val winner=observed.copy(remoteIntentWinner=true)
                                if(runCatching{planInvestmentCashEventResultAcknowledgement(s,winner)}.isFailure)throw IOException("Incomplete cash event winner")
                                checkCurrent();val accepted=persist{localStore.acknowledgeInvestmentCashEventResult(s,winner,q.deviceId,q.modifiedAt){currentSession()==captured}};checkCurrent()
                                summary=if(accepted)summary.copy(acknowledged=summary.acknowledged+1) else summary.copy(staleResponses=summary.staleResponses+1)
                                continue
                            }
                        }
                    }
                }
                val base=server?.syncVersion ?: 0L;require(base<Long.MAX_VALUE)
                val postingBase=remotePost?.syncVersion;require(postingBase==null || postingBase in 1 until Long.MAX_VALUE)
                val sent=local.copy(syncVersion=base+1,payload=JsonObject(cashEventPayloadForCloud(local)+buildJsonObject{put("sync_version",base+1);put("last_modified_by_device_id",q.deviceId)}))
                checkCurrent()
                val saved=if(local.deletedAt!=null) {
                    if(server==null)throw IOException("Incomplete absent event proof")
                    remote.deleteEvent(ownerUserId,s.eventId,base,postingBase,requireNotNull(local.deletedAt),q.deviceId,accessToken)
                } else {
                    val post=requireNotNull(s.rows.singleOrNull{it.entity==CloudEntity.INVESTMENT_POSTING.table && it.id==canonical})
                    require(post.deletedAt==null && post.payload.keys.none{it.startsWith("_mistia_android_")})
                    val next=(postingBase ?: 0L)+1
                    val proposal=post.copy(syncVersion=next,updatedAt=local.updatedAt,payload=JsonObject(post.payload+buildJsonObject {
                        put("sync_version",next);put("updated_at",q.modifiedAt);put("last_modified_by_device_id",q.deviceId)
                    }))
                    remote.mutateEvent(ownerUserId,InvestmentCashEventProposal(sent,proposal),base,postingBase,accessToken)
                }
                checkCurrent()
                if(saved!=null) {
                    persist{localStore.recordInvestmentCashEventPublicationReceipt(InvestmentCashEventPublicationReceipt(s,sent,base,postingBase,saved)){currentSession()==captured}}
                    checkCurrent()
                }
                if(!unchanged(s)){summary=summary.copy(staleResponses=summary.staleResponses+1);continue}
                if(saved==null)throw IOException("Cash event comparison changed")
                val result=remote.fetchEvent(ownerUserId,s.eventId,accessToken);checkCurrent()
                if(!unchanged(s)){summary=summary.copy(staleResponses=summary.staleResponses+1);continue}
                if(runCatching{planInvestmentCashEventResultAcknowledgement(s,result)}.isFailure)throw IOException("Inconsistent cash event result")
                checkCurrent();val accepted=persist{localStore.acknowledgeInvestmentCashEventResult(s,result,q.deviceId,q.modifiedAt){currentSession()==captured}};checkCurrent()
                summary=if(accepted)summary.copy(pushed=summary.pushed+1) else summary.copy(staleResponses=summary.staleResponses+1)
            }catch(cancelled:CancellationException){throw cancelled}
            catch(error:Exception) {
                if(error is CashEventPersistenceFailure)throw error.failure
                checkCurrent()
                val retry=when(error){is SupabaseHttpException->(error.statusCode==400 && error.serviceCode in INVESTMENT_CASH_EVENT_RETRY_CODES) || error.statusCode>=500 || error.statusCode in setOf(408,429);is IOException->true;else->false}
                val code=when(error){is SupabaseHttpException->error.serviceCode?.takeIf{error.statusCode==400 && it in INVESTMENT_CASH_EVENT_RETRY_CODES} ?: "http_${error.statusCode}";is IOException->"network_io";is CashEventConflict->"cash_conflict_${error.reason}";else->"invalid_cash_event"}
                val delay=minOf(30_000L*(1L shl selected.attemptCount.coerceIn(0,10)),21_600_000L)
                val next=if(retry && now<=Long.MAX_VALUE-delay)now+delay else Long.MAX_VALUE
                val recorded=localStore.recordInvestmentCashEventMutationFailure(selected,next,code,s){currentSession()==captured};checkCurrent()
                summary=when{!recorded->summary.copy(staleResponses=summary.staleResponses+1);error is CashEventConflict->summary.copy(conflicts=summary.conflicts+1)
                    retry->summary.copy(retryableFailures=summary.retryableFailures+1);else->summary.copy(permanentFailures=summary.permanentFailures+1)}
            }
        }
        checkCurrent();return summary
    }
    private fun ready(s:InvestmentCashEventPublicationSnapshot,ledger:CloudRecord):Boolean {
        val wallets=s.rows.filter{it.entity==CloudEntity.LEDGER_WALLET.table}.associateBy{it.id}
        val rootId=investmentSystemWalletId(s.owner);val root=wallets[rootId] ?: return false
        val system=canonicalInvestmentWalletForPublication(s.owner,root)
        val p=ledger.payload
        // The real ledger and canonical allocation already capture this event's
        // route. A later default preference cannot redirect or strand it.
        val dependencies=setOfNotNull(rootId,p.financeRawString("source_wallet_id"),p.financeRawString("destination_wallet_id"))
        val proven=walletInvestmentActivePrerequisites(s,dependencies-rootId)
        if(dependencies.any{CloudEntity.LEDGER_WALLET.table to it in s.dirtyKeys && it !in proven})return false
        if(s.pending.any{it.mutation.entity==CloudEntity.INVESTMENT_TRADE})return false
        for(id in dependencies-rootId) {
            val row=proven[id] ?: wallets[id] ?: return false;val wallet=investmentLinkedWalletRecord(row)
            if(wallet.deletedAt!=null || wallet.isArchived || wallet.kind in setOf(null,WalletKind.INVESTMENT,WalletKind.CREDIT_CARD) || wallet.systemPurposeRawValue!=null || wallet.currencyCode!=system.currencyCode)return false
        }
        return true
    }
    private class CashEventPersistenceFailure(val failure:Exception):RuntimeException()
    private class CashEventConflict(val reason:String):IllegalStateException()
}
