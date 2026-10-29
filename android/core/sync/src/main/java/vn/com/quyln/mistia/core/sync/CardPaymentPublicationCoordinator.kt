package vn.com.quyln.mistia.core.sync

import java.io.IOException
import java.time.ZoneId
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import vn.com.quyln.mistia.core.model.*
import vn.com.quyln.mistia.core.network.CARD_PAYMENT_PUBLICATION_RETRY_CODES
import vn.com.quyln.mistia.core.network.SupabaseHttpException

/** Publishes only a cycle marker after its financial dependencies are confirmed. */
class CardPaymentPublicationCoordinator(
    private val localStore:LocalStore,
    private val remoteStore:RemoteMutationStore,
    private val remote:CardPaymentPublicationRemote,
    private val writesEnabled:Boolean,
    private val currentSession:()->AuthSession?,
    private val nowEpochMillis:()->Long=System::currentTimeMillis,
    private val currentZone:()->ZoneId=ZoneId::systemDefault,
):DomainPushCoordinator {
    override val entity=CloudEntity.DUE_OCCURRENCE_RECORD
    override suspend fun pushPending(ownerUserId:UserId,accessToken:String):DomainPushSummary {
        if(!writesEnabled)return DomainPushSummary()
        val caller=currentCoroutineContext();caller.ensureActive()
        val captured=currentSession();val zone=currentZone()
        if(captured==null || captured.userId!=ownerUserId || captured.accessToken!=accessToken || accessToken.isBlank())
            throw CancellationException("Card payment session changed")
        fun isCurrent():Boolean {caller.ensureActive();return currentSession()==captured && currentZone()==zone}
        fun checkCurrent(){if(!isCurrent())throw CancellationException("Card payment authorization changed");caller.ensureActive()}
        suspend fun <T> persist(action:suspend ()->T):T {
            checkCurrent()
            val result=try{action()}catch(cancelled:CancellationException){throw cancelled}catch(error:Exception){throw PersistenceFailure(error)}
            checkCurrent();return result
        }
        suspend fun source(cardId:String):CardPaymentPublicationSnapshot=persist {
            localStore.cardPaymentPublicationSnapshot(ownerUserId,cardId).also{
                require(it.owner==ownerUserId && it.cardId==cardId);it.requireCoherent()
            }
        }
        suspend fun unchanged(expected:CardPaymentPublicationSnapshot):Boolean {
            val current=source(expected.cardId)
            return runCatching{expected.requireUnchanged(current)}.isSuccess
        }
        suspend fun fetch(entity:CloudEntity,id:String):CloudRecord? {
            checkCurrent();val row=remoteStore.fetchRecord(entity,id,accessToken,ownerUserId);checkCurrent();return row
        }
        suspend fun cycles(cardId:String):List<CloudRecord> {
            val records=mutableListOf<CloudRecord>();var offset=0
            repeat(10001) {
                checkCurrent();val page=remoteStore.fetchCardCyclePage(cardId,accessToken,ownerUserId,offset,100);checkCurrent()
                require(page.records.size<=100);records+=page.records
                require(records.size<=10000){"Card cycle membership limit exceeded"}
                require(records.map{it.id}.distinct().size==records.size)
                val next=page.nextOffset ?: return records
                require(page.records.isNotEmpty() && next==offset+page.records.size && next>offset)
                offset=next
            }
            error("Card cycle page limit exceeded")
        }
        suspend fun publish(s:CardPaymentPublicationSnapshot,q:QueuedMutation):Outcome {
            requireCardPaymentPublicationIntent(s,q)
            var observed=CardPaymentPublicationObservation(cycles(s.cardId),emptyMap(),emptyMap())
            if(!unchanged(s))return Outcome.Stale
            var decision=planCardPaymentPublication(s,q,observed,zone)
            while(decision is CardPaymentPublicationDecision.NeedLedger || decision is CardPaymentPublicationDecision.NeedWallet) {
                observed=when(val needed=decision) {
                    is CardPaymentPublicationDecision.NeedLedger->{require(!observed.ledger.containsKey(needed.id));observed.copy(ledger=observed.ledger+(needed.id to fetch(CloudEntity.LEDGER_TRANSACTION,needed.id)))}
                    is CardPaymentPublicationDecision.NeedWallet->{require(!observed.wallets.containsKey(needed.id));observed.copy(wallets=observed.wallets+(needed.id to fetch(CloudEntity.LEDGER_WALLET,needed.id)))}
                    else->error("Dependency required")
                }
                if(!unchanged(s))return Outcome.Stale
                decision=planCardPaymentPublication(s,q,observed,zone)
            }
            if(decision is CardPaymentPublicationDecision.Acknowledge) {
                // A read-only recovery has no RPC commit boundary. Observe all
                // dependencies and complete card membership again before ACK.
                val ledger=observed.ledger.keys.associateWith{fetch(CloudEntity.LEDGER_TRANSACTION,it)}
                val wallets=observed.wallets.keys.associateWith{fetch(CloudEntity.LEDGER_WALLET,it)}
                observed=CardPaymentPublicationObservation(cycles(s.cardId),ledger,wallets)
                if(!unchanged(s))return Outcome.Stale
                decision=planCardPaymentPublication(s,q,observed,zone)
                if(decision !is CardPaymentPublicationDecision.Acknowledge)return decision.outcome()
                return if(persist{localStore.acknowledgeCardPaymentPublication(s,q,observed,zone,::isCurrent)})Outcome.Acknowledged else Outcome.Stale
            }
            if(decision !is CardPaymentPublicationDecision.Write)return decision.outcome()
            if(!unchanged(s))return Outcome.Stale
            checkCurrent();val result=remote.publish(s,q,observed,zone,accessToken);checkCurrent()
            if(!unchanged(s))return Outcome.Stale
            // The RPC locks and compares this exact ledger/wallet/card membership
            // in its transaction. Scope the ACK proof to its actual receipt;
            // a replaced target no longer depends on the old payment identity.
            val confirmed=try{cardPaymentPublicationReceiptObservation(s,q,observed,zone,requireNotNull(result))}
                catch(error:IllegalArgumentException){throw IOException("Card payment result unavailable")}
            return if(persist{localStore.acknowledgeCardPaymentPublication(s,q,confirmed,zone,::isCurrent)})Outcome.Pushed else Outcome.Stale
        }
        try {
            val now=nowEpochMillis();require(now>=0);var total=DomainPushSummary()
            val initial=source("00000000-0000-0000-0000-000000000000")
            val candidates=initial.queues.filter{q->
                q.mutation.entity==entity && q.nextAttemptAtEpochMillis<=now && q.mutation.subjectUserId==ownerUserId.value &&
                    initial.recordsByEntity.getValue(entity).any{r->r.id==q.mutation.recordId && supported(r)}
            }
            for(q in candidates) {
                checkCurrent()
                val row=initial.recordsByEntity.getValue(entity).single{it.id==q.mutation.recordId}
                val cardId=DueOccurrenceRecord.fromCloudRecord(row).sourceId
                val s=source(cardId)
                if(q !in s.queues){total=total.copy(staleResponses=total.staleResponses+1);continue}
                val outcome=try{publish(s,q)}catch(cancelled:CancellationException){throw cancelled}catch(error:Exception){
                    if(error is PersistenceFailure)throw error
                    checkCurrent()
                    val retry=when(error) {
                        is SupabaseHttpException->error.statusCode>=500 || error.statusCode in setOf(408,409,429) || error.statusCode==400 && error.serviceCode in CARD_PAYMENT_PUBLICATION_RETRY_CODES
                        is IOException->true
                        else->false
                    }
                    val code=when(error) {
                        is SupabaseHttpException->error.serviceCode?.takeIf{error.statusCode==400 && it in CARD_PAYMENT_PUBLICATION_RETRY_CODES} ?: "http_${error.statusCode}"
                        is IOException->"network_io"
                        else->"invalid_card_payment_publication"
                    }
                    Outcome.Failure(code,retry)
                }
                total=when(outcome) {
                    Outcome.Pushed->total.copy(pushed=total.pushed+1)
                    Outcome.Acknowledged->total.copy(acknowledged=total.acknowledged+1)
                    Outcome.Stale->total.copy(staleResponses=total.staleResponses+1)
                    Outcome.Deferred->total
                    is Outcome.Conflict,is Outcome.Failure->{
                        val retry=outcome is Outcome.Failure && outcome.retryable
                        val delay=minOf(30_000L*(1L shl q.attemptCount.coerceIn(0,10)),21_600_000L)
                        val next=if(retry && now<=Long.MAX_VALUE-delay)now+delay else Long.MAX_VALUE
                        val code=when(outcome){is Outcome.Conflict->"card_payment_conflict_${outcome.reason}";is Outcome.Failure->outcome.code;else->error("Failure expected")}
                        val accepted=persist{localStore.recordCardPaymentPublicationFailure(s,q,next,code,::isCurrent)}
                        when{!accepted->total.copy(staleResponses=total.staleResponses+1);outcome is Outcome.Conflict->total.copy(conflicts=total.conflicts+1)
                            retry->total.copy(retryableFailures=total.retryableFailures+1);else->total.copy(permanentFailures=total.permanentFailures+1)}
                    }
                }
            }
            checkCurrent();return total
        }catch(error:PersistenceFailure){throw error.failure}
    }
    internal fun handles(row:CloudRecord):Boolean = writesEnabled && supported(row)

    /** Unknown legacy payloads remain queued for reconciliation. */
    private fun supported(row:CloudRecord):Boolean=runCatching {
        val c=DueOccurrenceRecord.fromCloudRecord(row)
        c.sourceKindWireValue=="creditCard" && c.statusWireValue=="paid" && c.linkedTransactionId!=null && c.paidAt!=null && row.payload==c.toPayload()
    }.getOrDefault(false)
    private fun CardPaymentPublicationDecision.outcome():Outcome=when(this) {
        is CardPaymentPublicationDecision.Conflict->Outcome.Conflict(reason)
        is CardPaymentPublicationDecision.Deferred,is CardPaymentPublicationDecision.NeedLedger,is CardPaymentPublicationDecision.NeedWallet->Outcome.Deferred
        // A changed read-only recovery waits for the next complete observation.
        is CardPaymentPublicationDecision.Write->Outcome.Deferred
        is CardPaymentPublicationDecision.Acknowledge->error("Typed ACK required")
    }
    private sealed interface Outcome {
        data object Pushed:Outcome
        data object Acknowledged:Outcome
        data object Stale:Outcome
        data object Deferred:Outcome
        data class Conflict(val reason:String):Outcome
        data class Failure(val code:String,val retryable:Boolean):Outcome
    }
    private class PersistenceFailure(val failure:Exception):RuntimeException()
}
