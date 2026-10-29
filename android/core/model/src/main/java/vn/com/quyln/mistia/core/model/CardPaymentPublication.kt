package vn.com.quyln.mistia.core.model

import java.time.ZoneId
import java.time.YearMonth
import kotlinx.serialization.json.*

data class CardPaymentPublicationObservation(val cycles:List<CloudRecord>,val ledger:Map<String,CloudRecord?>,val wallets:Map<String,CloudRecord?>)
sealed interface CardPaymentPublicationDecision {
    data class NeedLedger(val id:String):CardPaymentPublicationDecision
    data class NeedWallet(val id:String):CardPaymentPublicationDecision
    data class Write(val payload:JsonObject,val expectedVersion:Long?):CardPaymentPublicationDecision
    data class Acknowledge(val record:CloudRecord):CardPaymentPublicationDecision
    data class Deferred(val reason:String):CardPaymentPublicationDecision
    data class Conflict(val reason:String):CardPaymentPublicationDecision
}
fun requireCardPaymentPublicationIntent(source:CardPaymentPublicationSnapshot,queued:QueuedMutation):DueOccurrenceRecord {
    source.requireCoherent()
    require(queued in source.queues && queued.mutation.entity==CloudEntity.DUE_OCCURRENCE_RECORD)
    val row=source.recordsByEntity.getValue(CloudEntity.DUE_OCCURRENCE_RECORD).single{it.id==queued.mutation.recordId}
    val local=cardPublicationCycle(row,source.owner,source.cardId)
    require(local.statusWireValue=="paid" && local.linkedTransactionId!=null && local.paidAt!=null)
    return local
}
fun planCardPaymentPublication(source:CardPaymentPublicationSnapshot,queued:QueuedMutation,
    observed:CardPaymentPublicationObservation,zone:ZoneId):CardPaymentPublicationDecision {
    val local=requireCardPaymentPublicationIntent(source,queued)
    val row=source.recordsByEntity.getValue(CloudEntity.DUE_OCCURRENCE_RECORD).single{it.id==local.id}
    val deleting=local.deletedAt!=null
    require(observed.cycles.map{it.id}.distinct().size==observed.cycles.size)
    val remoteCycles=observed.cycles.map{cardPublicationCycle(it,source.owner,source.cardId)}
    val localCycles=source.recordsByEntity.getValue(CloudEntity.DUE_OCCURRENCE_RECORD).filter{
        it.payload.financeRawString("source_kind_raw_value")=="creditCard" && it.payload.financeRawString("source_id")==source.cardId
    }.map{cardPublicationCycle(it,source.owner,source.cardId)}
    fun related(other:DueOccurrenceRecord)=other.selectedMonthKey==local.selectedMonthKey ||
        cashEventInstant(other.scheduledDate)==cashEventInstant(local.scheduledDate) ||
        other.linkedTransactionId!=null && other.linkedTransactionId==local.linkedTransactionId
    val siblings=(localCycles+remoteCycles).filter{it.id!=local.id && related(it)}
    val remote=remoteCycles.singleOrNull{it.id==local.id}
    if(remote!=null) {
        require(cashEventInstant(remote.createdAt)==cashEventInstant(local.createdAt)){"Cycle birth changed"}
        if(remote.syncVersion<local.syncVersion)return CardPaymentPublicationDecision.Conflict("cycle_version_regressed")
        val legacyMonth=YearMonth.from(cashEventInstant(local.scheduledDate).atZone(zone)).toString()
        val sameStatement=remote.selectedMonthKey==local.selectedMonthKey ||
            cashEventInstant(remote.scheduledDate)==cashEventInstant(local.scheduledDate) &&
            (remote.selectedMonthKey==legacyMonth || local.selectedMonthKey==legacyMonth)
        if(!sameStatement)return CardPaymentPublicationDecision.Conflict("cycle_statement_changed")
    }
    val links=(listOfNotNull(local.linkedTransactionId,remote?.linkedTransactionId)+siblings.mapNotNull{it.linkedTransactionId}).toSet()
    require(observed.ledger.keys.all{it in links}){"Unrequested ledger observation"}
    for((id,actual) in observed.ledger)actual?.let{cardPublicationLedger(it,source.owner,id,remote=true)}
    val localLedger=source.recordsByEntity.getValue(CloudEntity.LEDGER_TRANSACTION).singleOrNull{it.id==local.linkedTransactionId}
        ?: return CardPaymentPublicationDecision.Conflict("local_ledger_missing")
    val tx=cardPublicationLedger(localLedger,source.owner,requireNotNull(local.linkedTransactionId),remote=false)
    val walletIds=setOfNotNull(tx.sourceWalletId,source.cardId)
    require(observed.wallets.keys.all{it in walletIds}){"Unrequested wallet observation"}
    for((id,actual) in observed.wallets)actual?.let{cardPublicationWallet(it,source.owner,id)}
    cardPublicationFinancialProof(source,local,observed,deleting)?.let{return it}
    // A different live marker identity cannot be silently merged, even when its
    // transfer was undone. Its own tombstone must publish before a new birth.
    if(!deleting) {
        if(siblings.any{it.deletedAt==null})return CardPaymentPublicationDecision.Conflict("live_cycle_sibling_requires_reconciliation")
        for(sibling in siblings.filter{it.statusWireValue=="paid" || it.linkedTransactionId!=null || it.paidAt!=null}) {
            if(source.queues.any{it.mutation.entity==CloudEntity.DUE_OCCURRENCE_RECORD && it.mutation.recordId==sibling.id})
                return CardPaymentPublicationDecision.Deferred("predecessor_cycle_pending")
            cardPublicationPredecessor(source,local,sibling,observed)?.let{return it}
        }
    }
    val remoteRow=observed.cycles.singleOrNull{it.id==local.id}
    if(remoteRow!=null && cardPublicationBusiness(row)==cardPublicationBusiness(remoteRow))
        return CardPaymentPublicationDecision.Acknowledge(remoteRow)
    if(remote==null) {
        if(deleting && (local.syncVersion>0 || queued.remoteIdentityObserved))return CardPaymentPublicationDecision.Acknowledge(row)
        if(local.syncVersion!=0L || queued.remoteIdentityObserved)return CardPaymentPublicationDecision.Conflict("cycle_identity_missing")
    } else {
        val sameFinancial=cardPublicationBusiness(row,true)==cardPublicationBusiness(remoteRow!!,true)
        val knownBase=remote.syncVersion==local.syncVersion && (local.syncVersion>0 || queued.remoteIdentityObserved)
        val metadata=remote.statusWireValue in setOf("pending","skipped") && remote.linkedTransactionId==null && remote.paidAt==null && remote.deletedAt==null
        if(!(sameFinancial && remote.statusWireValue=="paid") && !(knownBase && metadata && !deleting)) {
            if(deleting || remote.statusWireValue!="paid")return CardPaymentPublicationDecision.Conflict("paid_cycle_changed")
            cardPublicationPredecessor(source,local,remote,observed)?.let{return it}
        } else if(!deleting && remote.deletedAt!=null) {
            // Same old footprint cannot resurrect a newer tombstone merely
            // because the desired payload still says paid.
            return CardPaymentPublicationDecision.Conflict("remote_cycle_deleted")
        }
    }
    val version=remote?.syncVersion ?: 0L
    require(version in 0 until Long.MAX_VALUE)
    return CardPaymentPublicationDecision.Write(JsonObject(row.payload+("sync_version" to JsonPrimitive(version+1))),remote?.syncVersion)
}

fun requireCardPaymentPublicationResult(source:CardPaymentPublicationSnapshot,queued:QueuedMutation,
    observed:CardPaymentPublicationObservation,zone:ZoneId,result:CloudRecord) {
    val decision=planCardPaymentPublication(source,queued,observed,zone)
    require(decision is CardPaymentPublicationDecision.Write)
    cardPublicationCycle(result,source.owner,source.cardId)
    // The existing PostgreSQL update trigger owns updated_at. Its valid actual
    // timestamp is retained in the receipt; every other submitted field is exact.
    require(result.id==queued.mutation.recordId && cardPublicationNormalize(JsonObject(result.payload-"updated_at"))==
        cardPublicationNormalize(JsonObject(decision.payload-"updated_at"))){
        "Submitted card cycle result differs"
    }
}

/** Keep only dependencies needed by the actual compared receipt. A replaced
 * target no longer refers to its predecessor ledger; retained siblings still do.
 * All supplied values come from the RPC's original compared observation. */
fun cardPaymentPublicationReceiptObservation(source:CardPaymentPublicationSnapshot,queued:QueuedMutation,
    observed:CardPaymentPublicationObservation,zone:ZoneId,result:CloudRecord):CardPaymentPublicationObservation {
    requireCardPaymentPublicationResult(source,queued,observed,zone,result)
    var confirmed=CardPaymentPublicationObservation(observed.cycles.filterNot{it.id==result.id}+result,emptyMap(),emptyMap())
    repeat(observed.ledger.size+observed.wallets.size+1) {
        when(val decision=planCardPaymentPublication(source,queued,confirmed,zone)) {
            is CardPaymentPublicationDecision.NeedLedger->{
                require(observed.ledger.containsKey(decision.id) && !confirmed.ledger.containsKey(decision.id))
                confirmed=confirmed.copy(ledger=confirmed.ledger+(decision.id to observed.ledger[decision.id]))
            }
            is CardPaymentPublicationDecision.NeedWallet->{
                require(observed.wallets.containsKey(decision.id) && !confirmed.wallets.containsKey(decision.id))
                confirmed=confirmed.copy(wallets=confirmed.wallets+(decision.id to observed.wallets[decision.id]))
            }
            is CardPaymentPublicationDecision.Acknowledge->{require(decision.record==result);return confirmed}
            else->throw IllegalArgumentException("Compared card receipt cannot acknowledge this intent")
        }
    }
    throw IllegalArgumentException("Compared card receipt dependencies incomplete")
}

interface CardPaymentPublicationRemote {
    suspend fun publish(source:CardPaymentPublicationSnapshot,queued:QueuedMutation,
        observed:CardPaymentPublicationObservation,zone:ZoneId,accessToken:String):CloudRecord?
}
