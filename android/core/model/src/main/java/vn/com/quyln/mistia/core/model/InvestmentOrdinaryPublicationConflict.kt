package vn.com.quyln.mistia.core.model

import kotlinx.serialization.json.*

sealed interface InvestmentOrdinaryConflictPlan {
    data class Local(val plan:InvestmentOrdinaryLocalPlan):InvestmentOrdinaryConflictPlan
    data class Remote(val records:List<CloudRecord>,val removals:Set<Pair<String,String>>,val queues:List<QueuedMutation>):InvestmentOrdinaryConflictPlan
    data class Unresolved(val reason:String,val localRows:List<CloudRecord>,val observed:InvestmentOrdinaryCloudSnapshot):InvestmentOrdinaryConflictPlan
}

/** Policy authority is separate from proving an exact response to a sent proposal. */
fun planInvestmentOrdinaryConflict(source:InvestmentOrdinaryPublicationSnapshot,observed:InvestmentOrdinaryCloudSnapshot):InvestmentOrdinaryConflictPlan {
    val group=investmentOrdinaryPublicationGroup(source);require(group.queues.isNotEmpty())
    val records=requireOrdinaryCloud(source,observed)
    val primary=requireNotNull(observed.transaction)
    val local=group.rows.associateBy{it.entity to it.id}
    val remote=records.associateBy{it.entity to it.id}
    val queues=source.pending.associateBy{it.mutation.entity.table to it.mutation.recordId}
    for((key,row) in local) {
        val actual=remote[key]
        if(actual==null) {
            val q=requireNotNull(queues[key])
            require(row.syncVersion==0L && !q.remoteIdentityObserved){"Compared ordinary identity disappeared"}
        } else {
            require(actual.syncVersion>=row.syncVersion){"Ordinary conflict version regressed"}
            require(cashEventInstant(row.payload.financeRawString("created_at"))==cashEventInstant(actual.payload.financeRawString("created_at"))){"Ordinary conflict identity birth changed"}
        }
    }
    val keys=local.keys+remote.keys
    val projection=source.rows.filterNot{it.entity to it.id in keys}+records
    // Reconstitute a queue-free view for structural validation. It grants no ACK.
    if(observed.postings.isNotEmpty())investmentOrdinaryPublicationGroup(source.copy(rows=projection,pending=emptyList(),dirtyKeys=emptySet()))
    else require(observed.adjustment==null)
    try {requireStableInvestmentOrdinaryProjection(source,projection)}
    catch(_:InvestmentOrdinaryRelatedAllocationChanged) {
        return InvestmentOrdinaryConflictPlan.Unresolved("other_event_allocation_changed",group.rows,observed)
    }
    val decision=RecordConflictResolver.resolve(group.primary,primary)
    if(decision.winner==RecordConflictWinner.REMOTE) {
        val parent=source.rows.single{it.entity==CloudEntity.LEDGER_TRANSACTION.table && it.id==source.eventId}
        val stillPossible=localOrdinaryPublicationHistory(parent).any{intent->
            intent.rows.single{it.entity==CloudEntity.LEDGER_TRANSACTION && it.id==source.eventId}.baseVersion>=primary.syncVersion
        }
        if(stillPossible)return InvestmentOrdinaryConflictPlan.Unresolved("pending_own_proposal",group.rows,observed)
    }
    return when(decision.winner) {
        RecordConflictWinner.UNRESOLVED->InvestmentOrdinaryConflictPlan.Unresolved(decision.reason,group.rows,observed)
        RecordConflictWinner.REMOTE->InvestmentOrdinaryConflictPlan.Remote(records,local.keys-remote.keys,group.queues)
        RecordConflictWinner.LOCAL->{
            val device=group.queues.first().mutation.deviceId
            val date=(group.rows.map{cashEventInstant(it.updatedAt)}+records.map{cashEventInstant(it.updatedAt)}).maxOrNull()!!.toString()
            val rawParent=source.rows.single{it.entity==CloudEntity.LEDGER_TRANSACTION.table && it.id==source.eventId}
            val remaining=localOrdinaryPublicationHistory(rawParent).filter{intent->
                intent.rows.single{it.entity==CloudEntity.LEDGER_TRANSACTION && it.id==source.eventId}.baseVersion>=primary.syncVersion
            }
            val desired=group.rows.map{row->
                val actual=remote[row.entity to row.id]
                val payload=if(row.id==source.eventId)ordinaryPublicationPayloadForCloud(row) else row.payload
                val next=if(actual==null)row.copy(payload=payload) else row.copy(syncVersion=actual.syncVersion,payload=JsonObject(payload+("sync_version" to JsonPrimitive(actual.syncVersion))))
                if(row.entity==CloudEntity.LEDGER_TRANSACTION.table && row.id==source.eventId)next.withOrdinaryHistory(remaining)else next
            }+records.filter{it.entity to it.id !in local}.map{row->
                // Complete server history must be compared even when LOCAL no
                // longer needs that canonical component. Retire it explicitly.
                if(row.deletedAt!=null)row else investmentAssetChanged(row,buildJsonObject{put("deleted_at",date)},device,date).copy(deletedAt=date)
            }
            val changes=desired.mapNotNull{row->
                val key=row.entity to row.id;val old=source.rows.singleOrNull{it.entity to it.id==key}
                val prior=queues[key]
                val actor=requireNotNull(row.payload.financeRawString("last_modified_by_device_id"))
                val mutation=PendingMutation(requireNotNull(CloudEntity.fromTable(row.entity)),row.id,source.owner.value,
                    if(row.deletedAt==null)MutationKind.UPSERT else MutationKind.DELETE,row.payload,requireNotNull(row.updatedAt),row.syncVersion,actor)
                val present=key in remote || prior?.remoteIdentityObserved==true || row.syncVersion>0 || key !in source.dirtyKeys && old!=null
                val q=prior?.copy(mutation=mutation,remoteIdentityObserved=present) ?: QueuedMutation(mutation,0,0,null,remoteIdentityObserved=present)
                if(old==row && prior==q)null else row to q
            }
            val updated=changes.associateBy{it.first.entity to it.first.id}
            val nextRows=source.rows.map{updated[it.entity to it.id]?.first ?: it}+changes.map{it.first}.filter{it.entity to it.id !in source.rows.map{r->r.entity to r.id}.toSet()}
            val nextPending=source.pending.filterNot{it.mutation.entity.table to it.mutation.recordId in updated}+changes.map{it.second}
            val next=source.copy(rows=nextRows,pending=nextPending,dirtyKeys=nextPending.map{it.mutation.entity.table to it.mutation.recordId}.toSet())
            investmentOrdinaryPublicationGroup(next);requireStableInvestmentOrdinaryProjection(next,nextRows)
            InvestmentOrdinaryConflictPlan.Local(InvestmentOrdinaryLocalPlan(changes))
        }
    }
}

const val LOCAL_ORDINARY_CONFLICT_KEY="_mistia_android_ordinary_investment_conflict"

private fun conflictRows(owner:UserId,event:String,raw:JsonElement):List<CloudRecord> {
    val entries=raw.jsonArray;require(entries.size in 1..6)
    val rows=entries.map{element->
        val item=element.jsonObject;require(item.keys==setOf("entity","payload"))
        val entity=requireNotNull(CloudEntity.fromTable(requireNotNull(item.financeRawString("entity"))))
        require(entity in setOf(CloudEntity.LEDGER_TRANSACTION,CloudEntity.INVESTMENT_POSTING))
        val p=item.getValue("payload").jsonObject;require(p.keys.none{it.startsWith("_mistia_android_")})
        CloudRecord(entity.table,requireNotNull(p.financeRawString("id")),owner.value,p,p.financeRawString("updated_at"),p.financeRawString("deleted_at"),requireNotNull(p.financeRawLong("sync_version")))
    }
    val eventRow=rows.single{it.entity==CloudEntity.LEDGER_TRANSACTION.table && it.id==event}
    val adjustment=rows.singleOrNull{it.entity==CloudEntity.LEDGER_TRANSACTION.table && it.id!=event}
    val cloud=InvestmentOrdinaryCloudSnapshot(owner,event,eventRow,adjustment,rows.filter{it.entity==CloudEntity.INVESTMENT_POSTING.table})
    requireOrdinaryCloud(InvestmentOrdinaryPublicationSnapshot(owner,event,emptyList(),emptyList(),emptySet()),cloud)
    require(requireNotNull(eventRow.payload.financeRawLong("amount_minor"))>0)
    for(post in cloud.postings)requireCashEventPosting(owner,event,post,remote=post.syncVersion>0)
    return rows
}
fun localInvestmentOrdinaryConflict(row:CloudRecord):InvestmentOrdinaryConflictPlan.Unresolved? {
    val raw=row.payload[LOCAL_ORDINARY_CONFLICT_KEY] ?: return null
    val owner=UserId(row.ownerUserId);require(row.financeRawIdentity(owner,CloudEntity.LEDGER_TRANSACTION,true))
    require(financeRawUuid(row.id)==row.id && !requiresInvestmentLedgerDomain(row.payload) && LedgerTransactionRecord.fromCloudRecord(row).supportsOrdinaryTransactionLifecycle())
    val marker=raw.jsonObject
    require(marker.toString().toByteArray(Charsets.UTF_8).size<=262144 && marker.keys==setOf("version","owner_user_id","event_id","created_at","reason","local","remote"))
    require(marker["version"]==JsonPrimitive(1) && marker.financeRawString("owner_user_id")==owner.value && marker.financeRawString("event_id")==row.id &&
        cashEventInstant(marker.financeRawString("created_at"))==cashEventInstant(row.payload.financeRawString("created_at")))
    val reason=requireNotNull(marker.financeRawString("reason"));require(reason in setOf("same_clock_version_different_payload","pending_own_proposal","other_event_allocation_changed"))
    val local=conflictRows(owner,row.id,marker.getValue("local"))
    val remote=conflictRows(owner,row.id,marker.getValue("remote"))
    for(rows in listOf(local,remote))require(cashEventInstant(rows.single{it.entity==CloudEntity.LEDGER_TRANSACTION.table && it.id==row.id}.payload.financeRawString("created_at"))==cashEventInstant(row.payload.financeRawString("created_at")))
    val primary=remote.single{it.entity==CloudEntity.LEDGER_TRANSACTION.table && it.id==row.id}
    return InvestmentOrdinaryConflictPlan.Unresolved(reason,local,InvestmentOrdinaryCloudSnapshot(owner,row.id,primary,
        remote.singleOrNull{it.entity==CloudEntity.LEDGER_TRANSACTION.table && it.id!=row.id},remote.filter{it.entity==CloudEntity.INVESTMENT_POSTING.table}))
}
fun planInvestmentOrdinaryUnresolved(source:InvestmentOrdinaryPublicationSnapshot,plan:InvestmentOrdinaryConflictPlan.Unresolved):InvestmentOrdinaryLocalPlan {
    require(planInvestmentOrdinaryConflict(source,plan.observed)==plan)
    val group=investmentOrdinaryPublicationGroup(source)
    val parent=source.rows.single{it.entity==CloudEntity.LEDGER_TRANSACTION.table && it.id==source.eventId}
    fun rows(items:List<CloudRecord>)=JsonArray(items.map{row->buildJsonObject{put("entity",row.entity);put("payload",row.payload)}})
    val marker=buildJsonObject {
        put("version",1);put("owner_user_id",source.owner.value);put("event_id",source.eventId)
        put("created_at",requireNotNull(parent.payload.financeRawString("created_at")));put("reason",plan.reason)
        put("local",rows(plan.localRows));put("remote",rows(listOfNotNull(plan.observed.transaction,plan.observed.adjustment)+plan.observed.postings))
    }
    val queues=group.queues.associateBy{it.mutation.entity.table to it.mutation.recordId}
    val retained=parent.copy(payload=JsonObject(parent.payload+(LOCAL_ORDINARY_CONFLICT_KEY to marker))).also{localInvestmentOrdinaryConflict(it)}
    val originals=source.rows.associateBy{it.entity to it.id}
    val keys=queues.keys+(parent.entity to parent.id)
    val changes=keys.map{key->
        var row=if(key==parent.entity to parent.id)retained else originals.getValue(key)
        val prior=queues[key]
        if(prior==null)row=row.copy(payload=JsonObject(row.payload+buildJsonObject {
            put("last_modified_by_device_id",group.queues.first().mutation.deviceId);put("last_modified_by_user_id",source.owner.value)
        }))
        val mutation=PendingMutation(requireNotNull(CloudEntity.fromTable(row.entity)),row.id,source.owner.value,
            if(row.deletedAt==null)MutationKind.UPSERT else MutationKind.DELETE,row.payload,requireNotNull(row.updatedAt),row.syncVersion,requireNotNull(row.payload.financeRawString("last_modified_by_device_id")))
        val queue=(prior ?: QueuedMutation(mutation,0,0,null,remoteIdentityObserved=true)).copy(mutation=mutation,
            nextAttemptAtEpochMillis=Long.MAX_VALUE,lastError="ordinary_conflict_${plan.reason}")
        row to queue
    }
    return InvestmentOrdinaryLocalPlan(changes)
}
