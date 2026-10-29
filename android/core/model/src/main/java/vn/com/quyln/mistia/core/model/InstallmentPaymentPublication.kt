package vn.com.quyln.mistia.core.model

import java.time.ZoneId
import java.time.Instant
import java.time.Duration
import java.time.YearMonth
import kotlinx.serialization.json.*

/** Complete cycle authority plus investment dependencies; distinct from legacy ACK-only recovery. */
data class InstallmentPaymentPublicationSnapshot(val base:InstallmentPaymentAcknowledgementSnapshot,
    val postings:List<CloudRecord>,val postingQueues:List<QueuedMutation>,val dirtyKeys:Set<Pair<String,String>>) {
    fun requireCoherent() {
        require(base.recordsByEntity.keys==InstallmentPaymentAcknowledgementSnapshot.entities)
        val rows=base.recordsByEntity.values.flatten()+postings
        val byKey=rows.associateBy{it.entity to it.id};require(byKey.size==rows.size)
        for(row in rows) {
            val entity=requireNotNull(CloudEntity.fromTable(row.entity))
            require(row.financeRawIdentity(base.owner,entity,true) && row.payload.financeRawString("id")==row.id &&
                row.payload.financeRawString("user_id")==base.owner.value && row.payload.financeRawLong("sync_version")==row.syncVersion &&
                row.updatedAt==row.payload.financeRawString("updated_at") && row.deletedAt==row.payload.financeRawString("deleted_at"))
        }
        require(postings.all{it.entity==CloudEntity.INVESTMENT_POSTING.table})
        require(postingQueues.all{it.mutation.entity==CloudEntity.INVESTMENT_POSTING})
        val queues=base.queues+postingQueues
        require(queues.map{it.mutation.entity.table to it.mutation.recordId}.distinct().size==queues.size)
        require(dirtyKeys==queues.map{it.mutation.entity.table to it.mutation.recordId}.toSet())
        for(q in queues) {
            val m=q.mutation;val row=byKey.getValue(m.entity.table to m.recordId)
            require(m.subjectUserId==base.owner.value && m.payload==row.payload && m.baseVersion==row.syncVersion && m.modifiedAt==row.updatedAt &&
                m.deviceId==row.payload.financeRawString("last_modified_by_device_id") && q.attemptCount>=0 && q.nextAttemptAtEpochMillis>=0 &&
                m.kind==if(row.deletedAt==null)MutationKind.UPSERT else MutationKind.DELETE)
        }
    }
    fun requireUnchanged(current:InstallmentPaymentPublicationSnapshot) {
        requireCoherent();current.requireCoherent();base.requireUnchanged(current.base)
        require(postings.sortedBy{it.id}==current.postings.sortedBy{it.id} && postingQueues.sortedBy{it.mutation.recordId}==current.postingQueues.sortedBy{it.mutation.recordId} && dirtyKeys==current.dirtyKeys)
    }
}
data class InstallmentPaymentPublicationObservation(val plan:CloudRecord?,val cycles:List<CloudRecord>,
    val ledger:Map<String,CloudRecord?>,val wallets:Map<String,CloudRecord?>)
sealed interface InstallmentPaymentPublicationDecision {
    data class NeedLedger(val id:String):InstallmentPaymentPublicationDecision
    data class NeedWallet(val id:String):InstallmentPaymentPublicationDecision
    data class Write(val payload:JsonObject,val expectedVersion:Long?):InstallmentPaymentPublicationDecision
    data class Acknowledge(val record:CloudRecord):InstallmentPaymentPublicationDecision
    data class Deferred(val reason:String):InstallmentPaymentPublicationDecision
    data class Conflict(val reason:String):InstallmentPaymentPublicationDecision
}
fun planInstallmentPaymentPublication(source:InstallmentPaymentPublicationSnapshot,queued:QueuedMutation,
    observed:InstallmentPaymentPublicationObservation,zone:ZoneId):InstallmentPaymentPublicationDecision {
    source.requireCoherent()
    for(row in listOfNotNull(observed.plan)+observed.cycles+observed.ledger.values.filterNotNull()+observed.wallets.values.filterNotNull())
        require(row.payload.keys.none{it.startsWith("_mistia_android_")}) {"Remote local-only evidence"}
    val base=source.base;val (plan,local)=requireInstallmentPaymentAcknowledgementIntent(base,queued)
    val row=base.recordsByEntity.getValue(CloudEntity.DUE_OCCURRENCE_RECORD).single{it.id==local.id}
    require(row.payload==local.toPayload()) {"Unknown or private cycle fields cannot authorize a payment write"}
    if(base.batch!=null)return InstallmentPaymentPublicationDecision.Deferred("source_deletion_batch")
    fun pending(entity:CloudEntity,id:String)=base.queues.any{it.mutation.entity==entity && it.mutation.recordId==id}
    if(pending(CloudEntity.INSTALLMENT_PLAN,plan.id))return InstallmentPaymentPublicationDecision.Deferred("source_pending")
    val link=local.linkedTransactionId ?: return InstallmentPaymentPublicationDecision.Conflict("paid_link_missing")
    if(pending(CloudEntity.LEDGER_TRANSACTION,link))return InstallmentPaymentPublicationDecision.Deferred("ledger_pending")
    val reserved=source.postingQueues.any{q->
        val p=requireNotNull(q.mutation.payload)
        p.financeRawString("event_id")==link || p.financeRawString("ledger_transaction_id")==link ||
            q.mutation.recordId in listOf("cash-consumption-booked","cash-consumption-unreconciled","cash-destination-booked","cash-destination-unreconciled").map{investmentLedgerIdentity(link,it)}
    }
    if(reserved)return InstallmentPaymentPublicationDecision.Deferred("investment_allocation_pending")
    val locals=base.recordsByEntity.getValue(CloudEntity.DUE_OCCURRENCE_RECORD).filter{
        it.payload.financeRawString("source_kind_raw_value")=="installment" && it.payload.financeRawString("source_id")==plan.id && it.payload.financeRawString("selected_month_key")==local.selectedMonthKey
    }
    fun sibling(records:List<CloudRecord>)=installmentPaymentSiblingDecision(base.owner,plan.id,local,records)?.let{
        when(it) {
            is InstallmentPaymentAcknowledgement.Conflict->InstallmentPaymentPublicationDecision.Conflict(it.reason)
            is InstallmentPaymentAcknowledgement.Deferred->InstallmentPaymentPublicationDecision.Deferred(it.reason)
            else->error("Unexpected sibling authority")
        }
    }
    sibling(locals)?.let{return it};sibling(observed.cycles)?.let{return it}
    val remoteRow=observed.cycles.singleOrNull{it.id==local.id}
    val remote=remoteRow?.let{ackCycle(it,base.owner,plan.id,local.selectedMonthKey,local.id)}
    if(remote!=null) {
        require(remoteRow.payload==remote.toPayload()) {"Unknown cloud cycle fields"}
        require(Duration.between(Instant.parse(local.createdAt),Instant.parse(remote.createdAt)).abs()<Duration.ofNanos(1000)) {"Cycle birth changed"}
        if(remote.syncVersion<local.syncVersion)return InstallmentPaymentPublicationDecision.Conflict("cycle_version_regressed")
    }
    // Probe the existing, read-only financial authority with the intended marker.
    // This candidate never becomes an ACK: only an actual matching observation may.
    val proof=planInstallmentPaymentAcknowledgement(base,queued,observed.plan,row,observed.ledger,observed.wallets)
    when(proof) {
        is InstallmentPaymentAcknowledgement.NeedLedger->return InstallmentPaymentPublicationDecision.NeedLedger(proof.id)
        is InstallmentPaymentAcknowledgement.NeedWallet->return InstallmentPaymentPublicationDecision.NeedWallet(proof.id)
        is InstallmentPaymentAcknowledgement.Deferred->return InstallmentPaymentPublicationDecision.Deferred(proof.reason)
        is InstallmentPaymentAcknowledgement.Conflict->return InstallmentPaymentPublicationDecision.Conflict(proof.reason)
        is InstallmentPaymentAcknowledgement.Acknowledge->Unit
    }
    val localLedger=base.recordsByEntity.getValue(CloudEntity.LEDGER_TRANSACTION).singleOrNull{it.id==link}?.let{ackLedger(it,base.owner,link)}
        ?: return InstallmentPaymentPublicationDecision.Conflict("local_ledger_missing")
    require(localLedger.supportsOrdinaryTransactionLifecycle())
    val serverLedger=observed.ledger[link]?.let{ackLedger(it,base.owner,link)}
    if(serverLedger!=null)require(Duration.between(Instant.parse(localLedger.createdAt),Instant.parse(serverLedger.createdAt)).abs()<Duration.ofNanos(1000)){"Ledger birth changed"}
    val deleting=local.deletedAt!=null
    if((locals+observed.cycles).any{other->
        other.id!=local.id && other.deletedAt==null && (other.payload.financeRawString("status_raw_value")=="paid" ||
            other.payload.financeRawString("linked_transaction_id")!=null || other.payload.financeRawString("paid_at")!=null)
    })return InstallmentPaymentPublicationDecision.Conflict("paid_sibling_identity_requires_reconciliation")
    if(remoteRow!=null && installmentPaymentBusiness(row)==installmentPaymentBusiness(remoteRow)) {
        val actual=planInstallmentPaymentAcknowledgement(base,queued,observed.plan,remoteRow,observed.ledger,observed.wallets)
        if(actual is InstallmentPaymentAcknowledgement.Acknowledge)return InstallmentPaymentPublicationDecision.Acknowledge(remoteRow)
    }
    if(!deleting) {
        if(plan.isArchived)return InstallmentPaymentPublicationDecision.Conflict("source_archived")
        if(installmentDueRows(base.owner,listOf(plan),emptyList(),YearMonth.parse(local.selectedMonthKey),zone).none{
            Instant.parse(local.scheduledDate)==it.dueDate
        })return InstallmentPaymentPublicationDecision.Conflict("not_scheduled")
        if(cashEventInstant(local.paidAt)!=cashEventInstant(localLedger.occurredAt))return InstallmentPaymentPublicationDecision.Conflict("paid_ledger_date_mismatch")
    }
    if(remote==null) {
        if(deleting && (local.syncVersion>0L || queued.remoteIdentityObserved))return InstallmentPaymentPublicationDecision.Acknowledge(row)
        if(local.syncVersion!=0L || queued.remoteIdentityObserved)return InstallmentPaymentPublicationDecision.Conflict("cycle_identity_missing")
        // A tombstone birth fences every still-possible older active create and
        // prevents clean unobserved0 history from becoming an observed0 identity.
    } else {
        val comparedEdit=remote.syncVersion==local.syncVersion && (local.syncVersion>0 || queued.remoteIdentityObserved)
        val metadataOnly=remote.status in setOf(DueStatus.PENDING,DueStatus.SKIPPED) && remote.linkedTransactionId==null && remote.paidAt==null
        // A committed, clean expense is the causal authority after a lost old
        // marker reply. Re-pay reuses this ledger identity with a later occurredAt;
        // the RPC locks and compares that exact expense before changing the marker.
        val laterPayment=!deleting && remote.status==DueStatus.PAID && remote.linkedTransactionId==link &&
            local.paidAt!=null && remote.paidAt!=null && cashEventInstant(local.paidAt).isAfter(cashEventInstant(remote.paidAt)) &&
            (remote.deletedAt==null || cashEventInstant(local.paidAt).isAfter(cashEventInstant(remote.deletedAt)))
        if(!deleting && remote.deletedAt!=null && remote.syncVersion>local.syncVersion && !laterPayment)
            return InstallmentPaymentPublicationDecision.Conflict("remote_cycle_deleted")
        val sameFinancial=installmentPaymentBusiness(row,withoutDeletion=true)==installmentPaymentBusiness(remoteRow!!,withoutDeletion=true)
        if(!(metadataOnly && comparedEdit && !deleting) && !laterPayment &&
            (!sameFinancial || remote.status!=DueStatus.PAID || remote.linkedTransactionId!=link || remote.amountMinorSnapshot!=local.amountMinorSnapshot))
            return InstallmentPaymentPublicationDecision.Conflict("paid_cycle_changed")
    }
    val version=remote?.syncVersion ?: 0;require(version in 0 until Long.MAX_VALUE)
    val payload=JsonObject(row.payload+("sync_version" to JsonPrimitive(version+1)))
    return InstallmentPaymentPublicationDecision.Write(payload,remote?.syncVersion)
}
internal fun installmentPaymentBusiness(row:CloudRecord,withoutDeletion:Boolean=false):JsonObject {
    val p=DueOccurrenceRecord.fromCloudRecord(row).toPayload().filterKeys{it !in setOf("sync_version","updated_at","last_modified_by_device_id") && (!withoutDeletion || it!="deleted_at")}.toMutableMap()
    for(key in listOf("created_at","scheduled_date","paid_at","deleted_at"))p[key]?.takeUnless{it==JsonNull}?.let{p[key]=JsonPrimitive(cashEventInstant(it.jsonPrimitive.content).toString())}
    return JsonObject(p)
}

interface InstallmentPaymentPublicationRemote {
    suspend fun publish(source:InstallmentPaymentPublicationSnapshot,queued:QueuedMutation,
        observed:InstallmentPaymentPublicationObservation,zone:ZoneId,accessToken:String):CloudRecord?
}

/** A submitted marker response is exact; policy/legacy ACKs use the separate decision path. */
fun requireInstallmentPaymentPublicationResult(source:InstallmentPaymentPublicationSnapshot,queued:QueuedMutation,
    observed:InstallmentPaymentPublicationObservation,zone:ZoneId,result:CloudRecord) {
    val write=planInstallmentPaymentPublication(source,queued,observed,zone)
    require(write is InstallmentPaymentPublicationDecision.Write)
    val expected=write.payload
    require(result.entity==CloudEntity.DUE_OCCURRENCE_RECORD.table && result.ownerUserId==source.base.owner.value &&
        result.id==queued.mutation.recordId && result.payload.keys==expected.keys && result.payload.financeRawString("id")==result.id &&
        result.payload.financeRawString("user_id")==source.base.owner.value && result.syncVersion==expected.financeRawLong("sync_version") &&
        result.payload.financeRawLong("sync_version")==result.syncVersion && result.updatedAt==result.payload.financeRawString("updated_at") &&
        result.deletedAt==result.payload.financeRawString("deleted_at"))
    fun normalize(p:JsonObject)=JsonObject(p.mapValues{(key,value)->
        if(value!=JsonNull && key in setOf("created_at","updated_at","scheduled_date","paid_at","deleted_at"))
            JsonPrimitive(cashEventInstant(value.jsonPrimitive.content).toString()) else value
    })
    require(normalize(result.payload)==normalize(expected)) {"Submitted installment cycle result differs"}
}
