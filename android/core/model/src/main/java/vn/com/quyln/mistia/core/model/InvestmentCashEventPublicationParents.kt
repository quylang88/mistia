package vn.com.quyln.mistia.core.model

import kotlinx.serialization.json.*

/** Private causal ancestry, never a cloud field or financial acknowledgement. */
const val LOCAL_CASH_EVENT_PUBLICATION_PARENTS_KEY="_mistia_android_cash_event_publication_parents"
data class InvestmentCashEventPublicationParent(val baseVersion:Long,val confirmedVersion:Long?,val deviceId:String,val deleted:Boolean,val fingerprint:String)
data class InvestmentCashEventPublicationReceipt(val source:InvestmentCashEventPublicationSnapshot,val sent:CloudRecord,val expectedVersion:Long,val expectedPostingVersion:Long?,val returned:CloudRecord)

fun localCashEventPublicationParents(row:CloudRecord):List<InvestmentCashEventPublicationParent> {
    val raw=row.payload[LOCAL_CASH_EVENT_PUBLICATION_PARENTS_KEY] ?: return emptyList()
    require(row.entity==CloudEntity.LEDGER_TRANSACTION.table && financeRawUuid(row.ownerUserId)==row.ownerUserId && financeRawUuid(row.id)==row.id &&
        row.payload.financeRawString("id")==row.id && row.payload.financeRawString("user_id")==row.ownerUserId &&
        row.payload.financeRawString("settlement_role_raw_value") in setOf("investmentCashDeposit","investmentCashWithdrawal"))
    val marker=raw as? JsonObject ?: throw IllegalArgumentException("Invalid private cash event ancestry")
    require(marker.keys==setOf("version","owner_user_id","event_id","parents") && marker["version"]==JsonPrimitive(1) &&
        marker.financeRawString("owner_user_id")==row.ownerUserId && marker.financeRawString("event_id")==row.id)
    val entries=marker["parents"] as? JsonArray ?: throw IllegalArgumentException("Invalid private cash event parents")
    require(entries.size in 1..64)
    val parents=entries.map{entry->
        val p=entry as? JsonObject ?: throw IllegalArgumentException("Invalid private cash event parent")
        require(p.keys==setOf("base_version","confirmed_version","device_id","deleted","fingerprint"))
        val base=requireNotNull(p.financeRawLong("base_version"));require(base in 0 until Long.MAX_VALUE)
        val confirmed=if(p["confirmed_version"]==JsonNull)null else requireNotNull(p.financeRawLong("confirmed_version")).also{require(it>base)}
        val device=requireNotNull(p.financeRawString("device_id"));require(financeRawUuid(device)==device)
        val deleted=requireNotNull((p["deleted"] as? JsonPrimitive)?.takeUnless{it.isString}?.booleanOrNull)
        val fp=requireNotNull(p.financeRawString("fingerprint"));require(Regex("[0-9a-f]{64}").matches(fp))
        InvestmentCashEventPublicationParent(base,confirmed,device,deleted,fp)
    }
    require(parents.distinct().size==parents.size);return parents
}
fun cashEventPayloadForCloud(row:CloudRecord):JsonObject {
    localCashEventPublicationParents(row)
    require(row.payload.keys.none{it.startsWith("_mistia_android_") && it!=LOCAL_CASH_EVENT_PUBLICATION_PARENTS_KEY})
    val payload=JsonObject(row.payload-LOCAL_CASH_EVENT_PUBLICATION_PARENTS_KEY)
    requireCashEventLedger(UserId(row.ownerUserId),row.id,row.copy(payload=payload),false)
    return payload
}
fun cashEventIntentFingerprint(row:CloudRecord):String = RecordConflictResolver.semanticFingerprint(buildJsonObject {
    // Nest identity, immutable created-at, tombstone and opaque keys so the generic metadata exclusion cannot discard them.
    put("cash_event_intent",cashEventBusiness(cashEventPayloadForCloud(row)))
})
private fun CloudRecord.withCashEventParent(parent:InvestmentCashEventPublicationParent):CloudRecord {
    val entries=(localCashEventPublicationParents(this)+parent).distinct().takeLast(64)
    val marker=buildJsonObject {
        put("version",1);put("owner_user_id",ownerUserId);put("event_id",id)
        put("parents",JsonArray(entries.map{p->buildJsonObject {
            put("base_version",p.baseVersion);put("confirmed_version",p.confirmedVersion?.let(::JsonPrimitive) ?: JsonNull)
            put("device_id",p.deviceId);put("deleted",p.deleted);put("fingerprint",p.fingerprint)
        }}))
    }
    return copy(payload=JsonObject(payload+(LOCAL_CASH_EVENT_PUBLICATION_PARENTS_KEY to marker))).also{localCashEventPublicationParents(it)}
}
internal fun CloudRecord.withPriorCashEventPublication(prior:CloudRecord):CloudRecord {
    require(entity==prior.entity && id==prior.id && ownerUserId==prior.ownerUserId)
    cashEventPayloadForCloud(prior);cashEventPayloadForCloud(this)
    if(cashEventIntentFingerprint(this)==cashEventIntentFingerprint(prior))return this
    val device=prior.payload.financeRawString("last_modified_by_device_id") ?: return this
    require(financeRawUuid(device)==device)
    if(prior.syncVersion==Long.MAX_VALUE)return this
    return withCashEventParent(InvestmentCashEventPublicationParent(prior.syncVersion,null,device,prior.deletedAt!=null,cashEventIntentFingerprint(prior)))
}
fun isKnownPriorCashEventPublication(local:CloudRecord,remote:CloudRecord,deviceId:String):Boolean {
    require(local.entity==remote.entity && local.id==remote.id && local.ownerUserId==remote.ownerUserId)
    requireCashEventLedger(UserId(remote.ownerUserId),remote.id,remote,true)
    if(remote.payload.financeRawString("last_modified_by_device_id")!=deviceId)return false
    val fp=cashEventIntentFingerprint(remote)
    return localCashEventPublicationParents(local).any{p->p.deviceId==deviceId && p.deleted==(remote.deletedAt!=null) &&
        remote.syncVersion==(p.confirmedVersion ?: (p.baseVersion+1)) && p.fingerprint==fp}
}
fun planInvestmentCashEventPublicationReceipt(receipt:InvestmentCashEventPublicationReceipt,current:InvestmentCashEventPublicationSnapshot):List<CloudRecord> {
    val source=receipt.source;source.requireCoherent();current.requireCoherent()
    require(source.owner==current.owner && source.eventId==current.eventId)
    val queued=requireNotNull(source.requestedQueue);require(source.matches(queued));val q=queued.mutation
    val original=requireNotNull(source.requestedRecord);val sent=receipt.sent;val remote=receipt.returned;val base=receipt.expectedVersion
    require(base in q.baseVersion until Long.MAX_VALUE && sent.syncVersion==base+1 && remote.syncVersion==base+1)
    receipt.expectedPostingVersion?.let{require(it in 0 until Long.MAX_VALUE)}
    requireCashEventLedger(source.owner,source.eventId,sent,false);requireCashEventLedger(source.owner,source.eventId,remote,true)
    require(sent.payload.keys.none{it.startsWith("_mistia_android_")} && sent.payload.financeRawString("last_modified_by_device_id")==q.deviceId &&
        remote.payload.financeRawString("last_modified_by_device_id")==q.deviceId && cashEventIntentFingerprint(original)==cashEventIntentFingerprint(sent))
    if(sent.deletedAt==null)require(cashEventIntentFingerprint(sent)==cashEventIntentFingerprint(remote))
    else require(remote.deletedAt!=null && cashEventInstant(remote.deletedAt)==cashEventInstant(sent.deletedAt) &&
        cashEventInstant(remote.updatedAt)==cashEventInstant(sent.deletedAt) &&
        cashEventInstant(remote.payload.financeRawString("created_at"))==cashEventInstant(sent.payload.financeRawString("created_at")))
    val row=current.requestedRecord ?: return emptyList();val currentQ=current.requestedQueue ?: return emptyList()
    if(currentQ==queued || currentQ.mutation.deviceId!=q.deviceId || currentQ.mutation.baseVersion!=q.baseVersion || row.syncVersion!=original.syncVersion)return emptyList()
    val parent=InvestmentCashEventPublicationParent(original.syncVersion,null,q.deviceId,original.deletedAt!=null,cashEventIntentFingerprint(original))
    if(localCashEventPublicationParents(row).none{it.baseVersion==parent.baseVersion && it.deviceId==parent.deviceId && it.deleted==parent.deleted && it.fingerprint==parent.fingerprint})return emptyList()
    val confirmed=InvestmentCashEventPublicationParent(original.syncVersion,remote.syncVersion,q.deviceId,remote.deletedAt!=null,cashEventIntentFingerprint(remote))
    return listOf(row.withCashEventParent(confirmed)).filter{it.payload!=row.payload}
}

/** Shared by conflict selection and the in-transaction financial winner proof. */
fun resolveInvestmentCashEventPublication(local:CloudRecord,remote:CloudRecord,device:String):RecordConflictDecision {
    val owner=UserId(local.ownerUserId)
    requireCashEventLedger(owner,local.id,local,false);requireCashEventLedger(owner,local.id,remote,true)
    require(cashEventInstant(local.payload.financeRawString("created_at"))==cashEventInstant(remote.payload.financeRawString("created_at")))
    if(remote.syncVersion<local.syncVersion)return RecordConflictDecision(RecordConflictWinner.UNRESOLVED,"cash_remote_version_regressed")
    if(cashEventIntentFingerprint(local)==cashEventIntentFingerprint(remote))return RecordConflictDecision(RecordConflictWinner.REMOTE,"same_cash_intent")
    if(isKnownPriorCashEventPublication(local,remote,device))return RecordConflictDecision(RecordConflictWinner.LOCAL,"own_prior_cash_publication")
    if(remote.syncVersion==local.syncVersion)return RecordConflictDecision(RecordConflictWinner.LOCAL,"same_cash_base")
    if(remote.payload.financeRawString("last_modified_by_device_id")==device)return RecordConflictDecision(RecordConflictWinner.UNRESOLVED,"unproven_own_cash_publication")
    return RecordConflictResolver.resolve(local.copy(payload=buildJsonObject{put("intent",cashEventIntentFingerprint(local))}),
        remote.copy(payload=buildJsonObject{put("intent",cashEventIntentFingerprint(remote))}))
}
