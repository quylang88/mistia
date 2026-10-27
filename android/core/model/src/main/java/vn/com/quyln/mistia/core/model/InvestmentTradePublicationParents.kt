package vn.com.quyln.mistia.core.model

import kotlinx.serialization.json.*

/** Bounded local causal evidence, including definite replies for every row changed by a server rebuild. */
const val LOCAL_TRADE_PUBLICATION_PARENTS_KEY="_mistia_android_trade_publication_parents"
data class InvestmentTradePublicationParent(val baseVersion:Long,val confirmedVersion:Long?,val deviceId:String,val deleted:Boolean,val fingerprint:String,val assetId:String)
data class InvestmentTradePublicationReceipt(val source:InvestmentTradePublicationSnapshot,val sent:CloudRecord,val expectedVersion:Long,val returned:List<CloudRecord>,
    val affectedAssetIds:Set<String> = setOfNotNull(source.requestedRecord?.payload?.financeRawString("asset_id"),sent.payload.financeRawString("asset_id")),
    val deleteRebuild:InvestmentTradeDeleteRebuild?=null)
data class InvestmentTradeDeleteRebuild(val before:List<CloudRecord>,val after:List<CloudRecord>)
/** Read observations certify only a one-version rebuild following this definite delete, never a financial ACK. */
fun investmentTradeDeleteRebuildPeers(receipt:InvestmentTradePublicationReceipt):List<CloudRecord> {
    val trace=receipt.deleteRebuild ?: return emptyList()
    require(receipt.sent.deletedAt!=null)
    // Reuse closed-reply validation without the observation branch; this call cannot recurse into another trace.
    planInvestmentTradePublicationReceipt(receipt.copy(deleteRebuild=null),receipt.source)
    val saved=requireNotNull(receipt.returned.singleOrNull{it.id==receipt.sent.id})
    val owner=receipt.source.owner;val device=requireNotNull(receipt.source.requestedQueue).mutation.deviceId
    for(rows in listOf(trace.before,trace.after)) {
        require(rows.size<=10000 && rows.map{it.id}.distinct().size==rows.size)
        for(row in rows) {
            requireInvestmentTradeForPublication(owner,row,forWrite=false,allowLocalEvidence=false)
            require(row.payload.financeRawString("asset_id") in receipt.affectedAssetIds)
        }
    }
    val before=trace.before.associateBy{it.id};val after=trace.after.associateBy{it.id}
    val requested=requireNotNull(before[saved.id])
    require(requested.deletedAt==null && requested.syncVersion==receipt.expectedVersion && after[saved.id]==saved)
    val asset=requested.payload.financeRawString("asset_id")
    require(asset==saved.payload.financeRawString("asset_id"))
    val deletedBefore=requested.copy(deletedAt=saved.deletedAt,payload=JsonObject(requested.payload+("deleted_at" to JsonPrimitive(saved.deletedAt))))
    require(investmentTradeIntentFingerprint(deletedBefore.payload)==investmentTradeIntentFingerprint(saved.payload))
    val peers=trace.before.filter{it.id!=saved.id && it.deletedAt==null && it.payload.financeRawString("asset_id")==asset}
    require(trace.after.filter{it.deletedAt==null && it.payload.financeRawString("asset_id")==asset}.map{it.id}.toSet()==peers.map{it.id}.toSet())
    return peers.map{old->
        val rebuilt=requireNotNull(after[old.id])
        require(old.syncVersion<Long.MAX_VALUE && rebuilt.syncVersion==old.syncVersion+1 && rebuilt.deletedAt==null &&
            java.time.Instant.parse(rebuilt.updatedAt)==java.time.Instant.parse(saved.updatedAt) &&
            rebuilt.payload.financeRawString("last_modified_by_device_id")==device &&
            investmentTradeIntentFingerprint(rebuilt.payload)==investmentTradeIntentFingerprint(old.payload))
        rebuilt
    }
}
fun planInvestmentTradePublicationReceipt(receipt:InvestmentTradePublicationReceipt,current:InvestmentTradePublicationSnapshot):List<CloudRecord> {
    val source=receipt.source;source.requireCoherent();current.requireCoherent()
    require(source.owner==current.owner && source.tradeId==current.tradeId)
    val queued=requireNotNull(source.requestedQueue);val q=queued.mutation;val original=requireNotNull(source.requestedRecord)
    val sent=receipt.sent;val base=receipt.expectedVersion;val device=q.deviceId
    require(source.matches(queued) && sent.id==q.recordId && sent.ownerUserId==source.owner.value && sent.entity==q.entity.table)
    requireInvestmentTradeForPublication(source.owner,sent,forWrite=sent.deletedAt==null,allowLocalEvidence=false)
    require(base>=0 && base<Long.MAX_VALUE-1 && sent.payload.financeRawString("last_modified_by_device_id")==device)
    require(investmentTradeIntentFingerprint(original.payload)==investmentTradeIntentFingerprint(sent.payload))
    require(receipt.returned.isNotEmpty() && receipt.returned.map{it.id}.distinct().size==receipt.returned.size)
    val saved=requireNotNull(receipt.returned.singleOrNull{it.id==sent.id})
    val assets=receipt.affectedAssetIds
    require(assets.size in 1..2 && assets.all{financeRawUuid(it)==it} && original.payload.financeRawString("asset_id") in assets && sent.payload.financeRawString("asset_id") in assets)
    for(remote in receipt.returned) {
        requireInvestmentTradeForPublication(source.owner,remote,forWrite=false,allowLocalEvidence=false)
        require(remote.payload.financeRawString("asset_id") in assets && remote.payload.financeRawString("last_modified_by_device_id")==device)
    }
    if(sent.deletedAt==null) {
        require(sent.syncVersion==maxOf(base,q.baseVersion)+1 && sent.syncVersion<Long.MAX_VALUE)
        require(receipt.returned.all{it.deletedAt==null})
        require(if(base==0L)saved.syncVersion==2L || saved.syncVersion==sent.syncVersion+1 else saved.syncVersion==sent.syncVersion+1)
    } else {
        require(receipt.returned.size==1 && saved.deletedAt!=null && saved.syncVersion==base+1)
        fun postgresInstant(value:String):java.time.Instant {
            val instant=java.time.Instant.parse(value)
            return java.time.Instant.ofEpochSecond(instant.epochSecond,Math.rint(instant.nano.toDouble()/1000).toLong()*1000)
        }
        require(postgresInstant(requireNotNull(saved.deletedAt))==postgresInstant(requireNotNull(sent.deletedAt)))
    }
    require(investmentTradePublicationIntentsMatch(sent,saved))
    val currentRows=current.rows.associateBy{it.entity to it.id}
    val currentQueues=current.pending.associateBy{it.mutation.entity.table to it.mutation.recordId}
    val sourceRows=source.rows.associateBy{it.entity to it.id}
    val sourceQueues=source.pending.associateBy{it.mutation.entity.table to it.mutation.recordId}
    return (receipt.returned+investmentTradeDeleteRebuildPeers(receipt)).mapNotNull{remote->
        val key=remote.entity to remote.id
        val old=sourceRows[key] ?: return@mapNotNull null
        val oldQ=sourceQueues[key]?.mutation ?: return@mapNotNull null
        val row=currentRows[key] ?: return@mapNotNull null
        val currentQ=currentQueues[key]?.mutation ?: return@mapNotNull null
        if(currentQ.deviceId!=device || currentQ.baseVersion!=oldQ.baseVersion || row.syncVersion!=old.syncVersion || remote.syncVersion<=row.syncVersion)return@mapNotNull null
        val fingerprint=investmentTradeIntentFingerprint(remote.payload)
        // A rebuild can also include another device's intervening user proposal. Its actor stamp alone is insufficient.
        fun matchesParent(p:InvestmentTradePublicationParent)=p.baseVersion==old.syncVersion && p.fingerprint==fingerprint &&
            p.deleted==(remote.deletedAt!=null) && p.assetId==remote.payload.financeRawString("asset_id")
        // A queued sibling may already have been edited before this RPC began. Its captured local parent
        // proves the old server intent, even if that intent originally came from another device.
        val requestedDelete=remote.id==sent.id && remote.deletedAt!=null
        if(fingerprint!=investmentTradeIntentFingerprint(old.payload) && !(requestedDelete && investmentTradePublicationIntentsMatch(old,remote)) &&
            localInvestmentTradePublicationParents(old).none(::matchesParent))return@mapNotNull null
        val parents=localInvestmentTradePublicationParents(row)
        if(investmentTradeIntentFingerprint(row.payload)!=fingerprint && !(requestedDelete && investmentTradePublicationIntentsMatch(row,remote)) && parents.none(::matchesParent))return@mapNotNull null
        val parent=InvestmentTradePublicationParent(row.syncVersion,remote.syncVersion,device,remote.deletedAt!=null,fingerprint,requireNotNull(remote.payload.financeRawString("asset_id")))
        appendInvestmentTradePublicationParent(row,parent).takeIf{it.payload!=row.payload}
    }
}
fun localInvestmentTradePublicationParents(row:CloudRecord):List<InvestmentTradePublicationParent> {
    val value=row.payload[LOCAL_TRADE_PUBLICATION_PARENTS_KEY] ?: return emptyList()
    require(row.entity==CloudEntity.INVESTMENT_TRADE.table && financeRawUuid(row.id)==row.id && financeRawUuid(row.ownerUserId)==row.ownerUserId &&
        row.payload.financeRawString("id")==row.id && row.payload.financeRawString("user_id")==row.ownerUserId)
    val marker=value as? JsonObject ?: throw IllegalArgumentException("Invalid local trade parents")
    require(marker.keys==setOf("version","owner_user_id","trade_id","parents") && marker["version"]==JsonPrimitive(1))
    require(marker.financeRawString("owner_user_id")==row.ownerUserId && marker.financeRawString("trade_id")==row.id)
    val entries=marker["parents"] as? JsonArray ?: throw IllegalArgumentException("Invalid local trade parents")
    require(entries.size in 1..64)
    val parents=entries.map{raw->
        val p=raw as? JsonObject ?: throw IllegalArgumentException("Invalid local trade parent")
        require(p.keys==setOf("base_version","confirmed_version","device_id","deleted","fingerprint","asset_id"))
        val base=requireNotNull(p.financeRawLong("base_version")).also{require(it>=0 && it<Long.MAX_VALUE && it==row.syncVersion)}
        val confirmed=if(p["confirmed_version"]==JsonNull)null else requireNotNull(p.financeRawLong("confirmed_version")).also{require(it>base)}
        fun uuid(key:String)=requireNotNull(p.financeRawString(key)).also{require(financeRawUuid(it)==it)}
        val hash=requireNotNull(p.financeRawString("fingerprint")).also{require(Regex("[0-9a-f]{64}").matches(it))}
        val deleted=requireNotNull((p["deleted"] as? JsonPrimitive)?.takeIf{!it.isString}?.booleanOrNull)
        InvestmentTradePublicationParent(base,confirmed,uuid("device_id"),deleted,hash,uuid("asset_id"))
    }
    require(parents.distinct().size==parents.size)
    return parents
}
fun appendInvestmentTradePublicationParent(row:CloudRecord,parent:InvestmentTradePublicationParent):CloudRecord {
    val parents=(localInvestmentTradePublicationParents(row)+parent).distinct().takeLast(64)
    val marker=buildJsonObject {
        put("version",1);put("owner_user_id",row.ownerUserId);put("trade_id",row.id)
        put("parents",JsonArray(parents.map{p->buildJsonObject {
            put("base_version",p.baseVersion);put("confirmed_version",p.confirmedVersion?.let(::JsonPrimitive) ?: JsonNull)
            put("device_id",p.deviceId);put("deleted",p.deleted);put("fingerprint",p.fingerprint);put("asset_id",p.assetId)
        }}))
    }
    return row.copy(payload=JsonObject(row.payload+(LOCAL_TRADE_PUBLICATION_PARENTS_KEY to marker))).also{localInvestmentTradePublicationParents(it)}
}
internal fun CloudRecord.withPriorTradePublication(prior:CloudRecord):CloudRecord {
    if(entity!=CloudEntity.INVESTMENT_TRADE.table)return this
    localInvestmentTradePublicationParents(prior)
    val fingerprint=investmentTradeIntentFingerprint(prior.payload)
    if(fingerprint==investmentTradeIntentFingerprint(payload))return this
    val device=prior.payload.financeRawString("last_modified_by_device_id") ?: return this
    if(prior.syncVersion==Long.MAX_VALUE)return this
    return appendInvestmentTradePublicationParent(this,InvestmentTradePublicationParent(prior.syncVersion,null,device,
        prior.payload.financeRawString("deleted_at")!=null,fingerprint,requireNotNull(prior.payload.financeRawString("asset_id"))))
}
fun isKnownPriorInvestmentTradePublication(local:CloudRecord,remote:CloudRecord,device:String):Boolean {
    val parents=localInvestmentTradePublicationParents(local)
    if(remote.entity!=local.entity || remote.id!=local.id || remote.ownerUserId!=local.ownerUserId ||
        remote.payload.financeRawString("last_modified_by_device_id")!=device)return false
    if(runCatching{requireInvestmentTradeForPublication(UserId(local.ownerUserId),remote,forWrite=false,allowLocalEvidence=false)}.isFailure)return false
    val fingerprint=investmentTradeIntentFingerprint(remote.payload)
    return parents.any{p->p.deviceId==device && p.deleted==(remote.deletedAt!=null) && p.assetId==remote.payload.financeRawString("asset_id") && p.fingerprint==fingerprint &&
        if(p.confirmedVersion!=null)remote.syncVersion==p.confirmedVersion else
            remote.syncVersion>p.baseVersion && (remote.syncVersion-p.baseVersion in 1..2) && (p.baseVersion!=0L || remote.syncVersion==2L)}
}

/** Shared by the publisher and the in-transaction winner proof; derived caches never break a user-intent tie. */
fun resolveInvestmentTradePublication(local:CloudRecord,remote:CloudRecord,device:String):RecordConflictDecision {
    requireInvestmentTradeForPublication(UserId(local.ownerUserId),local,forWrite=false)
    requireInvestmentTradeForPublication(UserId(local.ownerUserId),remote,forWrite=false,allowLocalEvidence=false)
    require(local.entity==remote.entity && local.id==remote.id && local.ownerUserId==remote.ownerUserId)
    if(remote.syncVersion<local.syncVersion)return RecordConflictDecision(RecordConflictWinner.UNRESOLVED,"trade_remote_version_regressed")
    val a=investmentTradeIntentFingerprint(local.payload);val b=investmentTradeIntentFingerprint(remote.payload)
    if(investmentTradePublicationIntentsMatch(local,remote))return RecordConflictDecision(RecordConflictWinner.REMOTE,"same_trade_user_intent")
    if(isKnownPriorInvestmentTradePublication(local,remote,device))return RecordConflictDecision(RecordConflictWinner.LOCAL,"own_prior_trade_publication")
    if(local.syncVersion==remote.syncVersion)return RecordConflictDecision(RecordConflictWinner.LOCAL,"same_trade_base")
    val decision=RecordConflictResolver.resolve(local.copy(payload=buildJsonObject{put("intent",a)}),remote.copy(payload=buildJsonObject{put("intent",b)}))
    if(decision.winner==RecordConflictWinner.REMOTE && remote.payload.financeRawString("last_modified_by_device_id")==device)
        return RecordConflictDecision(RecordConflictWinner.UNRESOLVED,"unproven_own_trade_publication")
    return decision
}
