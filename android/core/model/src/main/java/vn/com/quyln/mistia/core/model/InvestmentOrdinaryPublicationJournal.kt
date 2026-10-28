package vn.com.quyln.mistia.core.model

import java.time.Instant
import kotlinx.serialization.json.*

const val LOCAL_ORDINARY_PUBLICATION_JOURNAL_KEY = "_mistia_android_ordinary_investment_publication"
data class InvestmentOrdinaryIntentRow(val entity:CloudEntity,val id:String,val baseVersion:Long,val createdAt:String,val deviceId:String,val fingerprint:String,val expectedPresent:Boolean=false)
data class InvestmentOrdinaryIntent(val rows:List<InvestmentOrdinaryIntentRow>)
data class InvestmentOrdinaryLocalPlan(val changes:List<Pair<CloudRecord,QueuedMutation>>)
private val ordinaryJournalComponents=listOf("cash-consumption-booked","cash-consumption-unreconciled","cash-destination-booked","cash-destination-unreconciled")
private val ordinaryIntentOrder=compareBy<InvestmentOrdinaryIntentRow>{it.entity.table}.thenBy{it.id}

/** Local causal evidence only. Cloud reads reject this key before reaching this parser. */
fun localOrdinaryPublicationHistory(row:CloudRecord):List<InvestmentOrdinaryIntent> {
    val raw=row.payload[LOCAL_ORDINARY_PUBLICATION_JOURNAL_KEY] ?: return emptyList()
    val owner=UserId(row.ownerUserId)
    require(row.entity==CloudEntity.LEDGER_TRANSACTION.table && row.financeRawIdentity(owner,CloudEntity.LEDGER_TRANSACTION,true) &&
        financeRawUuid(row.id)==row.id && row.payload.financeRawString("id")==row.id && row.payload.financeRawString("user_id")==owner.value &&
        !requiresInvestmentLedgerDomain(row.payload) && LedgerTransactionRecord.fromCloudRecord(row).supportsOrdinaryTransactionLifecycle())
    val marker=raw.jsonObject
    require(marker.toString().toByteArray(Charsets.UTF_8).size<=131_072 && marker.keys==setOf("version","owner_user_id","event_id","created_at","intents") &&
        marker["version"]==JsonPrimitive(1) && marker.financeRawString("owner_user_id")==owner.value && marker.financeRawString("event_id")==row.id &&
        cashEventInstant(marker.financeRawString("created_at"))==cashEventInstant(row.payload.financeRawString("created_at")))
    val entries=marker.getValue("intents").jsonArray;require(entries.size in 1..64)
    val adjustmentId=investmentLedgerIdentity(row.id,"cash-unreconciled-adjustment")
    val postingIds=ordinaryJournalComponents.map{investmentLedgerIdentity(row.id,it)}.toSet()
    val intents=entries.map{entry->
        val p=entry.jsonObject;require(p.keys==setOf("rows"))
        val rows=p.getValue("rows").jsonArray;require(rows.size in 1..6)
        val descriptors=rows.map{r->
            val d=r.jsonObject;require(d.keys==setOf("entity","id","base_version","created_at","device_id","fingerprint","expected_present"))
            val entity=requireNotNull(CloudEntity.fromTable(requireNotNull(d.financeRawString("entity"))))
            val id=requireNotNull(d.financeRawString("id"));require(financeRawUuid(id)==id)
            require(entity==CloudEntity.LEDGER_TRANSACTION && id in setOf(row.id,adjustmentId) || entity==CloudEntity.INVESTMENT_POSTING && id in postingIds)
            val base=requireNotNull(d.financeRawLong("base_version"));require(base in 0 until Long.MAX_VALUE)
            val device=requireNotNull(d.financeRawString("device_id"));require(financeRawUuid(device)==device)
            val birth=cashEventInstant(d.financeRawString("created_at")).toString()
            val fingerprint=requireNotNull(d.financeRawString("fingerprint"));require(Regex("[0-9a-f]{64}").matches(fingerprint))
            val present=d["expected_present"];require(present==JsonPrimitive(true) || present==JsonPrimitive(false))
            require(base==0L || present==JsonPrimitive(true))
            InvestmentOrdinaryIntentRow(entity,id,base,birth,device,fingerprint,present==JsonPrimitive(true))
        }
        require(descriptors==descriptors.sortedWith(ordinaryIntentOrder) && descriptors.map{it.entity to it.id}.distinct().size==descriptors.size &&
            descriptors.map{it.deviceId}.distinct().size==1 && (descriptors.size==1 || descriptors.count{it.entity==CloudEntity.INVESTMENT_POSTING} in 1..4))
        val parent=requireNotNull(descriptors.singleOrNull{it.entity==CloudEntity.LEDGER_TRANSACTION && it.id==row.id})
        require(parent.createdAt==cashEventInstant(row.payload.financeRawString("created_at")).toString() && (descriptors.size==1 || parent.baseVersion<=row.syncVersion))
        InvestmentOrdinaryIntent(descriptors)
    }
    require(intents.distinct().size==intents.size)
    return intents
}

/** Strip only validated local evidence; arbitrary private fields remain invalid. */
fun ordinaryPublicationPayloadForCloud(row:CloudRecord):JsonObject {
    if(row.payload.containsKey(LOCAL_ORDINARY_PUBLICATION_JOURNAL_KEY))localOrdinaryPublicationHistory(row)
    if(row.payload.containsKey(LOCAL_ORDINARY_CONFLICT_KEY))localInvestmentOrdinaryConflict(row)
    return JsonObject(row.payload-setOf(LOCAL_ORDINARY_PUBLICATION_JOURNAL_KEY,LOCAL_ORDINARY_CONFLICT_KEY))
}

private fun ordinaryIntentFingerprint(row:CloudRecord):String = RecordConflictResolver.semanticFingerprint(buildJsonObject {
    // Nest the payload so the generic fingerprint cannot discard audit metadata.
    put("entity",row.entity);put("wire",ordinaryPublicationBusiness(ordinaryPublicationPayloadForCloud(row)))
})
private fun ordinaryIntent(rows:List<CloudRecord>,presence:Map<String,Boolean>)=InvestmentOrdinaryIntent(rows.map{row->
    val device=requireNotNull(row.payload.financeRawString("last_modified_by_device_id"));require(financeRawUuid(device)==device)
    require(row.syncVersion in 0 until Long.MAX_VALUE)
    InvestmentOrdinaryIntentRow(requireNotNull(CloudEntity.fromTable(row.entity)),row.id,row.syncVersion,
        cashEventInstant(row.payload.financeRawString("created_at")).toString(),device,ordinaryIntentFingerprint(row),presence.getValue(row.id))
}.sortedWith(ordinaryIntentOrder))
internal fun CloudRecord.withOrdinaryHistory(history:List<InvestmentOrdinaryIntent>):CloudRecord {
    if(history.isEmpty())return copy(payload=JsonObject(payload-LOCAL_ORDINARY_PUBLICATION_JOURNAL_KEY))
    require(history.size<=64)
    val marker=buildJsonObject {
        put("version",1);put("owner_user_id",ownerUserId);put("event_id",id);put("created_at",cashEventInstant(payload.financeRawString("created_at")).toString())
        put("intents",JsonArray(history.map{intent->buildJsonObject {
            put("rows",JsonArray(intent.rows.map{r->buildJsonObject {
                put("entity",r.entity.table);put("id",r.id);put("base_version",r.baseVersion);put("created_at",r.createdAt);put("device_id",r.deviceId);put("fingerprint",r.fingerprint);put("expected_present",r.expectedPresent)
            }}))
        }}))
    }
    return copy(payload=JsonObject(payload+(LOCAL_ORDINARY_PUBLICATION_JOURNAL_KEY to marker))).also{localOrdinaryPublicationHistory(it)}
}
private fun ordinaryLocalChanges(source:InvestmentOrdinaryPublicationSnapshot,rows:List<CloudRecord>,observed:Set<Pair<String,String>> = emptySet()):InvestmentOrdinaryLocalPlan {
    val current=source.rows.associateBy{it.entity to it.id};val queues=source.pending.associateBy{it.mutation.entity.table to it.mutation.recordId}
    return InvestmentOrdinaryLocalPlan(rows.mapNotNull{row->
        val key=row.entity to row.id;require(key in current)
        val device=requireNotNull(row.payload.financeRawString("last_modified_by_device_id"));require(financeRawUuid(device)==device)
        val mutation=PendingMutation(requireNotNull(CloudEntity.fromTable(row.entity)),row.id,source.owner.value,
            if(row.deletedAt==null)MutationKind.UPSERT else MutationKind.DELETE,row.payload,requireNotNull(row.updatedAt),row.syncVersion,device)
        val present=queues[key]?.remoteIdentityObserved==true || row.syncVersion>0 || key in observed || key !in source.dirtyKeys
        val queued=queues[key]?.copy(mutation=mutation,remoteIdentityObserved=present) ?: QueuedMutation(mutation,0,0,null,remoteIdentityObserved=present)
        if(current.getValue(key)==row && queues[key]==queued)null else row to queued
    })
}

/** Prepare every compared row before dispatch, including a formerly clean parent. */
fun planInvestmentOrdinaryPreparation(source:InvestmentOrdinaryPublicationSnapshot,deviceId:String,now:String):InvestmentOrdinaryLocalPlan {
    require(financeRawUuid(deviceId)==deviceId);Instant.parse(now)
    val group=investmentOrdinaryPublicationGroup(source);require(group.queues.isNotEmpty())
    val rawParent=source.rows.single{it.entity==CloudEntity.LEDGER_TRANSACTION.table && it.id==source.eventId}
    val history=localOrdinaryPublicationHistory(rawParent)
    val presence=investmentOrdinaryExpectedPresence(source)
    val existing=runCatching{ordinaryIntent(group.rows,presence)}.getOrNull()
    val alreadyPrepared=existing!=null && existing in history && existing.rows.all{it.deviceId==deviceId}
    val wire=if(alreadyPrepared)group.rows else {
        val time=(group.rows.map{Instant.parse(it.updatedAt)}+Instant.parse(now)).maxOrNull()!!.toString()
        group.rows.map{row->row.copy(updatedAt=time,payload=JsonObject(row.payload+buildJsonObject {
            put("updated_at",time);put("last_modified_by_device_id",deviceId)
            if(row.entity==CloudEntity.LEDGER_TRANSACTION.table)put("last_modified_by_user_id",source.owner.value)
        }))}
    }
    val intent=ordinaryIntent(wire,presence)
    val nextHistory=if(intent in history)history else (history+intent).also{require(it.size<=64){"Unresolved ordinary publication history is full"}}
    val staged=wire.map{if(it.entity==CloudEntity.LEDGER_TRANSACTION.table && it.id==source.eventId)it.withOrdinaryHistory(nextHistory)else it}
    return ordinaryLocalChanges(source,staged)
}
internal fun requireOrdinaryCloud(source:InvestmentOrdinaryPublicationSnapshot,cloud:InvestmentOrdinaryCloudSnapshot):List<CloudRecord> {
    require(cloud.owner==source.owner && cloud.eventId==source.eventId)
    val rows=listOfNotNull(cloud.transaction,cloud.adjustment)+cloud.postings
    require(rows.size==rows.map{it.entity to it.id}.distinct().size && cloud.postings.size<=4)
    for(row in rows) {
        require(row.payload.keys.none{it.startsWith("_mistia_android_")})
        // A legacy observed0 remains an existing identity; mutation results are >=1.
        requireCashEventRow(source.owner,row,requireNotNull(CloudEntity.fromTable(row.entity)),remote=row.syncVersion>0)
    }
    cloud.transaction?.let{require(it.entity==CloudEntity.LEDGER_TRANSACTION.table && it.id==source.eventId && !requiresInvestmentLedgerDomain(it.payload) && LedgerTransactionRecord.fromCloudRecord(it).supportsOrdinaryTransactionLifecycle())}
    cloud.adjustment?.let{require(it.entity==CloudEntity.LEDGER_TRANSACTION.table && it.id==investmentLedgerIdentity(source.eventId,"cash-unreconciled-adjustment") && it.payload.financeRawString("settlement_role_raw_value")=="investmentReserveUse")}
    val ids=ordinaryJournalComponents.map{investmentLedgerIdentity(source.eventId,it)}.toSet()
    for(row in cloud.postings)require(row.entity==CloudEntity.INVESTMENT_POSTING.table && row.id in ids && row.payload.financeRawString("event_id")==source.eventId &&
        row.payload.financeRawString("ledger_transaction_id")==source.eventId && row.payload.financeRawString("cash_origin_raw_value")=="derived")
    return rows
}

/** Adopt compared bases from a known proposal or identical financial rows; never ACK a queue. */
fun planInvestmentOrdinaryRebase(source:InvestmentOrdinaryPublicationSnapshot,observed:InvestmentOrdinaryCloudSnapshot):InvestmentOrdinaryLocalPlan {
    val group=investmentOrdinaryPublicationGroup(source);require(group.queues.isNotEmpty())
    val remote=requireOrdinaryCloud(source,observed).associateBy{it.entity to it.id}
    val local=group.rows.associateBy{it.entity to it.id}
    require(remote.keys.all{it in local})
    val queued=source.pending.associateBy{it.mutation.entity.table to it.mutation.recordId}
    fun requireAbsentBirth(row:CloudRecord) {
        val q=requireNotNull(queued[row.entity to row.id]);require(row.syncVersion==0L && !q.remoteIdentityObserved)
    }
    if(observed.transaction==null) {
        require(remote.isEmpty());group.rows.forEach(::requireAbsentBirth)
        return InvestmentOrdinaryLocalPlan(emptyList())
    }
    for((key,row) in local) {
        val actual=remote[key]
        if(actual==null)requireAbsentBirth(row)
        else require(cashEventInstant(row.payload.financeRawString("created_at"))==cashEventInstant(actual.payload.financeRawString("created_at")))
    }
    val rawParent=source.rows.single{it.entity==CloudEntity.LEDGER_TRANSACTION.table && it.id==source.eventId}
    val history=localOrdinaryPublicationHistory(rawParent)
    fun financial(payload:JsonObject)=ordinaryPublicationBusiness(payload).let {
        JsonObject(it-setOf("updated_at","last_modified_by_device_id","last_modified_by_user_id"))
    }
    fun matches(d:InvestmentOrdinaryIntentRow,actual:CloudRecord)=
        actual.syncVersion==d.baseVersion+1 && actual.payload.financeRawString("last_modified_by_device_id")==d.deviceId &&
            cashEventInstant(actual.payload.financeRawString("created_at")).toString()==d.createdAt && ordinaryIntentFingerprint(actual)==d.fingerprint
    val presence=investmentOrdinaryExpectedPresence(source)
    val known=history.any{intent->
        if(intent.rows.size==1) {
            // A generic request writes the primary only. Already observed
            // sibling bases still prove what the next full RPC must compare.
            val d=intent.rows.single();val key=d.entity.table to d.id
            remote[key]?.let{matches(d,it)}==true && remote.all{(other,row)->other==key ||
                row.syncVersion==local.getValue(other).syncVersion &&
                    (presence.getValue(row.id) || financial(local.getValue(other).payload)==financial(row.payload))}
        } else intent.rows.map{it.entity.table to it.id}.toSet()==remote.keys && intent.rows.all{d->matches(d,remote.getValue(d.entity.table to d.id))}
    }

    // A legacy generic parent may already exist while allocations are still
    // unpublished. Identical financial intent permits a CAS base observation,
    // regardless of sync-only audit stamps; it does not prove a complete result.

    val sameFinancial=remote.all{(key,actual)->
        val expected=local.getValue(key)
        actual.syncVersion>=expected.syncVersion && financial(expected.payload)==financial(actual.payload)
    }
    if(!known && !sameFinancial) {
        require(remote.all{(key,row)->row.syncVersion==local.getValue(key).syncVersion}){"Unknown ordinary remote winner"}
        require(remote.all{(key,row)->presence.getValue(row.id) || financial(local.getValue(key).payload)==financial(row.payload)}){
            "Unobserved zero ordinary identity has different financial intent"
        }
        val raw=source.rows.associateBy{it.entity to it.id}
        return ordinaryLocalChanges(source,group.rows.filter{it.entity to it.id in queued && it.entity to it.id in remote}.map{raw.getValue(it.entity to it.id)},remote.keys)
    }
    for((key,actual) in remote)require(local.getValue(key).syncVersion<=actual.syncVersion){"Ordinary remote version regressed"}
    val observedVersion=observed.transaction.syncVersion
    val remaining=history.filter{intent->intent.rows.single{it.entity==CloudEntity.LEDGER_TRANSACTION && it.id==source.eventId}.baseVersion>=observedVersion}
    val rebased=group.rows.map{row->
        val actual=remote[row.entity to row.id]
        val next=if(actual==null)row else row.copy(syncVersion=actual.syncVersion,payload=JsonObject(row.payload+("sync_version" to JsonPrimitive(actual.syncVersion))))
        if(row.entity==CloudEntity.LEDGER_TRANSACTION.table && row.id==source.eventId)next.withOrdinaryHistory(remaining)else next
    }
    return ordinaryLocalChanges(source,rebased,remote.keys)
}

fun investmentOrdinaryExpectedPresence(source:InvestmentOrdinaryPublicationSnapshot):Map<String,Boolean> {
    val group=investmentOrdinaryPublicationGroup(source)
    val queues=source.pending.associateBy{it.mutation.entity.table to it.mutation.recordId}
    val flags=group.rows.associate{row->row.id to (row.syncVersion>0 || queues[row.entity to row.id]?.remoteIdentityObserved==true || row.entity to row.id !in source.dirtyKeys)}
    require(flags.size==group.rows.size)
    return flags
}


/** Persist the exact generic wire target before dispatch, including conflict-version jumps. */
fun planTransactionPublicationPreparation(queued:QueuedMutation,local:CloudRecord,proposal:JsonObject):Pair<CloudRecord,QueuedMutation> {
    val q=queued.mutation;val owner=UserId(q.subjectUserId)
    require(q.entity==CloudEntity.LEDGER_TRANSACTION && q.kind==MutationKind.UPSERT && q.recordId==local.id &&
        local.financeRawIdentity(owner,CloudEntity.LEDGER_TRANSACTION,true) && local.payload==q.payload &&
        local.syncVersion==q.baseVersion && local.updatedAt==q.modifiedAt && local.deletedAt==null &&
        q.deviceId==local.payload.financeRawString("last_modified_by_device_id"))
    require(LedgerTransactionRecord.fromCloudRecord(local).supportsOrdinaryTransactionLifecycle() && !requiresInvestmentLedgerDomain(local.payload))
    val wire=ordinaryPublicationPayloadForCloud(local)
    require(wire.keys.none{it.startsWith("_mistia_android_")} && proposal.keys.none{it.startsWith("_mistia_android_")})
    val target=requireNotNull(proposal.financeRawLong("sync_version"))
    require(target>local.syncVersion && target>0 && proposal.financeRawString("last_modified_by_device_id")==q.deviceId)
    require(proposal==JsonObject(wire+buildJsonObject{put("sync_version",target);put("last_modified_by_device_id",q.deviceId)}))
    val history=localOrdinaryPublicationHistory(local)
    // The generic writer may select max(remote,local)+1. Store that actual
    // target, rather than deriving it later from the original local base.
    val descriptor=InvestmentOrdinaryIntentRow(CloudEntity.LEDGER_TRANSACTION,local.id,target-1,
        cashEventInstant(wire.financeRawString("created_at")).toString(),q.deviceId,
        ordinaryIntentFingerprint(local.copy(payload=proposal)),expectedPresent=target>1 || queued.remoteIdentityObserved)
    val intent=InvestmentOrdinaryIntent(listOf(descriptor))
    val next=local.withOrdinaryHistory(if(intent in history)history else (history+intent).also{require(it.size<=64)})
    return next to queued.copy(mutation=q.copy(payload=next.payload))
}

/** Financial comparison ignores validated local evidence and sync-only audit stamps. */
fun ordinaryPublicationHasFinancialDifferences(left:CloudRecord,right:CloudRecord):Boolean {
    require(left.entity==CloudEntity.LEDGER_TRANSACTION.table && right.entity==left.entity && left.id==right.id && left.ownerUserId==right.ownerUserId)
    fun financial(row:CloudRecord)=JsonObject(ordinaryPublicationBusiness(ordinaryPublicationPayloadForCloud(row))-
        setOf("updated_at","last_modified_by_device_id","last_modified_by_user_id"))
    return financial(left)!=financial(right)
}
