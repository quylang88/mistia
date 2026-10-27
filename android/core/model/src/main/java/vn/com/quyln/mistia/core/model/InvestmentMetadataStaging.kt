package vn.com.quyln.mistia.core.model

import java.time.Instant
import kotlinx.serialization.json.*

const val LOCAL_INVESTMENT_METADATA_STAGES_KEY="_mistia_android_investment_metadata_stages"
data class InvestmentMetadataStage(val localBase:Long,val remoteBase:Long,val replyVersion:Long,val device:String,val fingerprint:String,
    val keepImage:Boolean,val imageIntentFingerprint:String?)
data class InvestmentMetadataStagePreparation(val source:InvestmentTradePublicationSnapshot,val entity:CloudEntity,val id:String,
    val proposal:CloudRecord,val stage:InvestmentMetadataStage,val preparedRecord:CloudRecord) {
    val preparedSource:InvestmentTradePublicationSnapshot get()=source.copy(
        rows=source.rows.map{if(it.entity==entity.table && it.id==id)preparedRecord else it},
        pending=source.pending.map{if(it.mutation.entity==entity && it.mutation.recordId==id)it.copy(mutation=it.mutation.copy(payload=preparedRecord.payload)) else it})
}
fun investmentMetadataPayloadForCloud(payload:JsonObject)=JsonObject(payload-LOCAL_ASSET_PUBLICATION_KEYS-LOCAL_INVESTMENT_METADATA_STAGES_KEY)
private fun stageInstant(value:String):String {
    val parsed=Instant.parse(value)
    return Instant.ofEpochSecond(parsed.epochSecond,Math.rint(parsed.nano.toDouble()/1000).toLong()*1000).toString()
}
fun investmentMetadataStageFingerprint(payload:JsonObject):String {
    val business=(investmentMetadataPayloadForCloud(payload)-setOf("updated_at","sync_version","last_modified_by_device_id")).mapValues{(key,value)->
        if(key in setOf("created_at","archived_at","deleted_at") && value!=JsonNull)
            JsonPrimitive(stageInstant(requireNotNull((value as? JsonPrimitive)?.takeIf{it.isString}?.content))) else value
    }
    return RecordConflictResolver.semanticFingerprint(buildJsonObject{put("business",JsonObject(business))})
}
private fun stageImageIntentFingerprint(row:CloudRecord)=RecordConflictResolver.semanticFingerprint(buildJsonObject{
    put("image_intent",row.payload[LOCAL_ASSET_IMAGE_INTENT_KEY] ?: JsonNull)
})
private fun requireStageMetadata(row:CloudRecord,owner:UserId,entity:CloudEntity,id:String,remote:Boolean) {
    require(entity in setOf(CloudEntity.INVESTMENT_ASSET,CloudEntity.INVESTMENT_CHANNEL) && row.entity==entity.table && row.id==id && row.ownerUserId==owner.value)
    require(row.payload.financeRawString("id")==id && row.payload.financeRawString("user_id")==owner.value && row.payload.financeRawLong("sync_version")==row.syncVersion &&
        row.updatedAt==row.payload.financeRawString("updated_at") && row.financeRawDeleted(true)!=null && row.deletedAt==row.payload.financeRawString("deleted_at"))
    if(remote)require(row.payload.keys.none{it.startsWith("_mistia_android_")})
    if(entity==CloudEntity.INVESTMENT_ASSET)InvestmentAssetRecord.fromCloudRecord(row) else InvestmentChannelRecord.fromCloudRecord(row)
}
fun localInvestmentMetadataStages(row:CloudRecord):List<InvestmentMetadataStage> {
    val value=row.payload[LOCAL_INVESTMENT_METADATA_STAGES_KEY] ?: return emptyList()
    val entity=requireNotNull(CloudEntity.fromTable(row.entity))
    requireStageMetadata(row,UserId(row.ownerUserId),entity,row.id,false)
    val marker=value as? JsonObject ?: error("Invalid local metadata stages")
    require(marker.keys==setOf("version","owner_user_id","entity","record_id","stages") && marker["version"]==JsonPrimitive(1))
    require(marker.financeRawString("owner_user_id")==row.ownerUserId && marker.financeRawString("record_id")==row.id && marker.financeRawString("entity")==row.entity)
    val entries=marker["stages"] as? JsonArray ?: error("Invalid local metadata stages")
    require(entries.size in 1..64)
    val result=entries.map{entry->
        val p=entry as? JsonObject ?: error("Invalid local metadata stage")
        require(p.keys==setOf("local_base","remote_base","reply_version","device_id","fingerprint","keep_image","image_intent_fingerprint"))
        val local=requireNotNull(p.financeRawLong("local_base"));val base=requireNotNull(p.financeRawLong("remote_base"));val version=requireNotNull(p.financeRawLong("reply_version"))
        require(local>=0 && base>=local && base<Long.MAX_VALUE && version==base+1)
        val device=requireNotNull(p.financeRawString("device_id"));require(financeRawUuid(device)==device)
        val fingerprint=requireNotNull(p.financeRawString("fingerprint"));require(Regex("[0-9a-f]{64}").matches(fingerprint))
        val keep=requireNotNull((p["keep_image"] as? JsonPrimitive)?.takeIf{!it.isString}?.booleanOrNull)
        val photo=if(p["image_intent_fingerprint"]==JsonNull)null else requireNotNull(p.financeRawString("image_intent_fingerprint")).also{require(Regex("[0-9a-f]{64}").matches(it))}
        require(if(entity==CloudEntity.INVESTMENT_CHANNEL)!keep && photo==null else photo!=null)
        InvestmentMetadataStage(local,base,version,device,fingerprint,keep,photo)
    }
    require(result.distinct().size==result.size)
    return result
}
private fun appendStage(row:CloudRecord,stage:InvestmentMetadataStage):CloudRecord {
    val stages=(localInvestmentMetadataStages(row)+stage).distinct().takeLast(64)
    val marker=buildJsonObject {
        put("version",1);put("owner_user_id",row.ownerUserId);put("entity",row.entity);put("record_id",row.id)
        put("stages",JsonArray(stages.map{s->buildJsonObject{
            put("local_base",s.localBase);put("remote_base",s.remoteBase);put("reply_version",s.replyVersion);put("device_id",s.device)
            put("fingerprint",s.fingerprint);put("keep_image",s.keepImage);put("image_intent_fingerprint",s.imageIntentFingerprint?.let(::JsonPrimitive) ?: JsonNull)
        }}))
    }
    return row.copy(payload=JsonObject(row.payload+(LOCAL_INVESTMENT_METADATA_STAGES_KEY to marker)))
}
fun prepareInvestmentMetadataStage(source:InvestmentTradePublicationSnapshot,entity:CloudEntity,id:String,compared:CloudRecord?,
    assetPublication:InvestmentAssetPublicationSnapshot?=null):InvestmentMetadataStagePreparation {
    source.requireCoherent();require(source.tradeId==id)
    val row=source.rows.single{it.entity==entity.table && it.id==id}
    val q=source.pending.single{it.mutation.entity==entity && it.mutation.recordId==id}
    requireStageMetadata(row,source.owner,entity,id,false);localInvestmentMetadataStages(row)
    require(row.deletedAt==null && row.payload.financeRawArchived()==true && q.mutation.kind==MutationKind.UPSERT)
    val base=compared?.let{
        requireStageMetadata(it,source.owner,entity,id,true)
        require(stageInstant(requireNotNull(it.payload.financeRawString("created_at")))==stageInstant(requireNotNull(row.payload.financeRawString("created_at"))))
        it.syncVersion
    } ?: 0L.also{require(row.syncVersion==0L && !q.remoteIdentityObserved)}
    require(base>=row.syncVersion && base<Long.MAX_VALUE)
    val keepImage=if(entity==CloudEntity.INVESTMENT_ASSET) {
        val authority=requireNotNull(assetPublication);require(authority.matches(q,row))
        val declared=localAssetImagePublication(row)
        require(declared==null || declared==authority.imagePublication)
        authority.imagePublication?.let{require(it.ownerUserId==source.owner.value && it.assetId==id && row.payload["image_path"]==(it.path?.let(::JsonPrimitive) ?: JsonNull))}
        authority.imagePublication==null || authority.imageAcknowledged
    } else false.also{require(assetPublication==null)}
    val payload=JsonObject(investmentMetadataPayloadForCloud(row.payload)+buildJsonObject{
        put("is_archived",false);put("archived_at",JsonNull);put("sync_version",base+1)
        if(keepImage && compared!=null)put("image_path",compared.payload["image_path"] ?: JsonNull)
    })
    if(entity==CloudEntity.INVESTMENT_ASSET)payload.financeRawString("image_path")?.let{InvestmentProductImagePath.parse(source.owner,id,it)}
    val proposal=row.copy(payload=payload,syncVersion=base+1)
    val stage=InvestmentMetadataStage(row.syncVersion,base,base+1,q.mutation.deviceId,investmentMetadataStageFingerprint(payload),keepImage,
        if(entity==CloudEntity.INVESTMENT_ASSET)stageImageIntentFingerprint(row) else null)
    return InvestmentMetadataStagePreparation(source,entity,id,proposal,stage,appendStage(row,stage)).also{it.preparedSource.requireCoherent()}
}
fun planInvestmentMetadataStageRebase(prepared:InvestmentTradePublicationSnapshot,entity:CloudEntity,id:String,stage:InvestmentMetadataStage,
    remote:CloudRecord,current:InvestmentTradePublicationSnapshot):Pair<CloudRecord,QueuedMutation>? {
    prepared.requireCoherent();current.requireCoherent();require(prepared.owner==current.owner)
    val prior=prepared.rows.single{it.entity==entity.table && it.id==id}
    require(stage in localInvestmentMetadataStages(prior))
    requireStageMetadata(remote,prepared.owner,entity,id,true)
    require(remote.deletedAt==null && remote.payload.financeRawArchived()==false && remote.payload["archived_at"]==JsonNull &&
        remote.syncVersion==stage.replyVersion && remote.payload.financeRawString("last_modified_by_device_id")==stage.device && investmentMetadataStageFingerprint(remote.payload)==stage.fingerprint)
    val row=current.rows.singleOrNull{it.entity==entity.table && it.id==id} ?: return null
    val queued=current.pending.singleOrNull{it.mutation.entity==entity && it.mutation.recordId==id} ?: return null
    if(stage !in localInvestmentMetadataStages(row) || row.syncVersion!=stage.localBase || queued.mutation.deviceId!=stage.device)return null
    require(stageInstant(requireNotNull(row.payload.financeRawString("created_at")))==stageInstant(requireNotNull(prior.payload.financeRawString("created_at"))))
    if(entity==CloudEntity.INVESTMENT_ASSET) {
        localAssetImagePublication(row)
        row.payload.financeRawString("image_path")?.let{InvestmentProductImagePath.parse(prepared.owner,id,it)}
    }
    val adoptPhoto=entity==CloudEntity.INVESTMENT_ASSET && stage.keepImage && stageImageIntentFingerprint(row)==stage.imageIntentFingerprint
    val fields=buildJsonObject {
        put("sync_version",remote.syncVersion)
        if(adoptPhoto)put("image_path",remote.payload["image_path"] ?: JsonNull)
    }
    val payload=row.payload+fields
    // The old declaration was already acknowledged; it cannot describe a different kept server photo.
    val changed=row.copy(syncVersion=remote.syncVersion,payload=JsonObject(if(adoptPhoto && row.payload["image_path"]!=fields["image_path"])
        payload-LOCAL_ASSET_IMAGE_INTENT_KEY else payload))
    return changed to queued.copy(mutation=queued.mutation.copy(baseVersion=remote.syncVersion,payload=changed.payload),remoteIdentityObserved=true)
}
