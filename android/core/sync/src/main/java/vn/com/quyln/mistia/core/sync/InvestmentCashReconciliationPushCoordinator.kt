package vn.com.quyln.mistia.core.sync

import java.io.IOException
import kotlinx.coroutines.*
import kotlinx.serialization.json.*
import vn.com.quyln.mistia.core.model.*
import vn.com.quyln.mistia.core.network.SupabaseHttpException

/** Prepare the confirmed real transfer, then compare its complete immutable allocation pair. */
class InvestmentCashReconciliationPushCoordinator(private val localStore:LocalStore,private val remote:InvestmentCashReconciliationRemote,
    private val writesEnabled:Boolean,private val currentSession:()->AuthSession?,private val nowEpochMillis:()->Long=System::currentTimeMillis):DomainPushCoordinator {
    override val entity=CloudEntity.INVESTMENT_POSTING
    override suspend fun pushPending(ownerUserId:UserId,accessToken:String):DomainPushSummary {
        if(!writesEnabled)return DomainPushSummary()
        val caller=currentCoroutineContext();caller.ensureActive();val captured=currentSession()
        if(captured==null || captured.userId!=ownerUserId || captured.accessToken!=accessToken || accessToken.isBlank())throw CancellationException("Reconciliation session changed")
        fun checkCurrent(){caller.ensureActive();if(currentSession()!=captured)throw CancellationException("Reconciliation session changed");caller.ensureActive()}
        suspend fun <T> persist(action:suspend ()->T):T=try{action()}catch(cancelled:CancellationException){throw cancelled}
            catch(error:Exception){throw PersistenceFailure(error)}
        suspend fun source(id:String):InvestmentCashEventPublicationSnapshot {
            checkCurrent();val s=localStore.investmentCashEventPublicationSnapshot(ownerUserId,id);checkCurrent()
            require(s.owner==ownerUserId && s.eventId==id);s.requireCoherent();return s
        }
        suspend fun unchanged(s:InvestmentCashEventPublicationSnapshot):Boolean=runCatching{s.requireUnchanged(persist{source(s.eventId)})}.fold({true},{error->
            if(error is CancellationException || error is PersistenceFailure)throw error;false
        })
        val now=nowEpochMillis();require(now>=0);var summary=DomainPushSummary()
        val initial=source("00000000-0000-0000-0000-000000000000")
        // Clean history is read once with the source; only groups with an actual queue
        // need another generation read. Clean postings can still identify a dirty ledger.
        val ids=initial.rows.filter{row->row.entity==entity.table && row.payload.financeRawString("role_raw_value")=="cashReconciliation" &&
            ((row.entity to row.id) in initial.dirtyKeys || row.payload.financeRawString("ledger_transaction_id")?.let{ledgerId->
                (CloudEntity.LEDGER_TRANSACTION.table to ledgerId) in initial.dirtyKeys
            }==true)}
            .mapNotNull{it.payload.financeRawString("event_id")?.takeIf{raw->financeRawUuid(raw)==raw}}.distinct().sorted()
        for(id in ids) {
            checkCurrent();val s=source(id)
            val group=runCatching{investmentCashReconciliationGroup(s)}.getOrNull() ?: continue
            val queues=investmentCashReconciliationQueues(s)
            if(queues.isEmpty() || queues.any{it.nextAttemptAtEpochMillis>now})continue
            val selected=queues.singleOrNull{it.mutation.entity==CloudEntity.LEDGER_TRANSACTION}
                ?: queues.minBy{it.mutation.recordId}
            if(selected !in initial.pending){summary=summary.copy(staleResponses=summary.staleResponses+1);continue}
            try {
                if(!ready(s,group))continue
                checkCurrent();var observed=remote.fetchEvent(ownerUserId,id,accessToken);checkCurrent()
                require(observed.owner==ownerUserId && observed.eventId==id)
                if(!unchanged(s)){summary=summary.copy(staleResponses=summary.staleResponses+1);continue}
                if(runCatching{planInvestmentCashReconciliationAcknowledgement(s,observed)}.isSuccess) {
                    val accepted=persist{localStore.acknowledgeInvestmentCashReconciliationResult(s,observed){currentSession()==captured}};checkCurrent()
                    summary=if(accepted)summary.copy(acknowledged=summary.acknowledged+1) else summary.copy(staleResponses=summary.staleResponses+1)
                    continue
                }
                var ledger=observed.ledger
                if(ledger==null) {
                    val localQueue=queues.singleOrNull{it.mutation.recordId==group.ledger.id}
                    if(group.ledger.syncVersion>0 || localQueue==null || localQueue.remoteIdentityObserved || observed.postings.isNotEmpty())throw Conflict("missing_ledger")
                    val sent=version(group.ledger,1,selected.mutation.deviceId)
                    checkCurrent();ledger=remote.createLedger(ownerUserId,id,sent,accessToken);checkCurrent()
                    if(!unchanged(s)){summary=summary.copy(staleResponses=summary.staleResponses+1);continue}
                    if(ledger==null)throw IOException("Reconciliation ledger result unavailable")
                }
                requireInvestmentCashReconciliationLedger(ownerUserId,id,ledger,true)
                if(!investmentCashReconciliationBusinessMatches(group.ledger,ledger))throw Conflict("different_ledger")
                val byId=observed.postings.associateBy{it.id}
                if(byId.size!=observed.postings.size || byId.keys.any{it !in setOf(group.holder.id,group.linked.id)})throw Conflict("different_postings")
                val expected=linkedMapOf<String,Long>()
                val proposals=listOf(group.holder,group.linked).map{local->
                    val existing=byId[local.id]
                    if(existing==null) {
                        val queued=queues.singleOrNull{it.mutation.recordId==local.id}
                        if(local.syncVersion>0 || queued==null || queued.remoteIdentityObserved)throw Conflict("missing_posting")
                    } else {
                        if(existing.syncVersion<=0 || !investmentCashReconciliationBusinessMatches(local,existing))throw Conflict("different_posting")
                    }
                    val base=existing?.syncVersion ?: 0L;require(base<Long.MAX_VALUE);expected[local.id]=base
                    version(local,base+1,selected.mutation.deviceId)
                }
                val proposal=InvestmentCashReconciliationGroup(ledger,proposals[0],proposals[1])
                requireInvestmentCashReconciliationGroup(ownerUserId,id,proposal,false)
                if(!unchanged(s)){summary=summary.copy(staleResponses=summary.staleResponses+1);continue}
                checkCurrent();remote.publishPostings(ownerUserId,id,proposal,expected,accessToken);checkCurrent()
                if(!unchanged(s)){summary=summary.copy(staleResponses=summary.staleResponses+1);continue}
                observed=remote.fetchEvent(ownerUserId,id,accessToken);checkCurrent()
                if(!unchanged(s)){summary=summary.copy(staleResponses=summary.staleResponses+1);continue}
                if(runCatching{planInvestmentCashReconciliationAcknowledgement(s,observed)}.isFailure)throw IOException("Incomplete reconciliation result")
                val accepted=persist{localStore.acknowledgeInvestmentCashReconciliationResult(s,observed){currentSession()==captured}};checkCurrent()
                summary=if(accepted)summary.copy(pushed=summary.pushed+1) else summary.copy(staleResponses=summary.staleResponses+1)
            }catch(cancelled:CancellationException){throw cancelled}
            catch(error:Exception) {
                if(error is PersistenceFailure)throw error.failure
                checkCurrent()
                val retry=when(error){is SupabaseHttpException->(error.statusCode==400 && error.serviceCode in INVESTMENT_CASH_RECONCILIATION_RETRY_CODES) || error.statusCode>=500 || error.statusCode in setOf(408,409,429);is IOException->true;else->false}
                val code=when(error){is SupabaseHttpException->error.serviceCode?.takeIf{error.statusCode==400 && it in INVESTMENT_CASH_RECONCILIATION_RETRY_CODES} ?: "http_${error.statusCode}";is IOException->"network_io";is Conflict->"reconciliation_conflict_${error.reason}";else->"invalid_reconciliation"}
                val delay=minOf(30_000L*(1L shl selected.attemptCount.coerceIn(0,10)),21_600_000L)
                val next=if(retry && now<=Long.MAX_VALUE-delay)now+delay else Long.MAX_VALUE
                val recorded=localStore.recordInvestmentCashReconciliationFailure(selected,next,code,s){currentSession()==captured};checkCurrent()
                summary=when{!recorded->summary.copy(staleResponses=summary.staleResponses+1);error is Conflict->summary.copy(conflicts=summary.conflicts+1)
                    retry->summary.copy(retryableFailures=summary.retryableFailures+1);else->summary.copy(permanentFailures=summary.permanentFailures+1)}
            }
        }
        checkCurrent();return summary
    }
    private fun version(row:CloudRecord,value:Long,device:String)=row.copy(syncVersion=value,payload=JsonObject(row.payload+buildJsonObject{put("sync_version",value);put("last_modified_by_device_id",device)}))
    private fun ready(s:InvestmentCashEventPublicationSnapshot,g:InvestmentCashReconciliationGroup):Boolean {
        val wallets=s.rows.filter{it.entity==CloudEntity.LEDGER_WALLET.table}.associateBy{it.id}
        val rootId=investmentSystemWalletId(s.owner);val root=wallets[rootId] ?: return false
        val system=canonicalInvestmentWalletForPublication(s.owner,root)
        val dependencies=setOfNotNull(rootId,g.ledger.payload.financeRawString("source_wallet_id"),g.ledger.payload.financeRawString("destination_wallet_id"))
        if(dependencies.any{CloudEntity.LEDGER_WALLET.table to it in s.dirtyKeys} || s.pending.any{it.mutation.entity==CloudEntity.INVESTMENT_TRADE})return false
        for(id in dependencies-rootId) {
            val wallet=wallets[id]?.let(::investmentLinkedWalletRecord) ?: return false
            if(wallet.deletedAt!=null || wallet.isArchived || wallet.kind in setOf(null,WalletKind.INVESTMENT,WalletKind.CREDIT_CARD) || wallet.systemPurposeRawValue!=null ||
                wallet.currencyCode!=system.currencyCode || wallet.currencyCode!=g.ledger.payload.financeRawString("reporting_currency_code"))return false
        }
        return true
    }
    private class PersistenceFailure(val failure:Exception):RuntimeException()
    private class Conflict(val reason:String):IllegalStateException()
}
