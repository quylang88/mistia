package vn.com.quyln.mistia.core.model

import java.time.Instant
import kotlinx.serialization.json.*

/** Bounded local causal evidence, stored with the row and its exact queued proposal. Never wire data. */
const val LOCAL_ASSET_PUBLICATION_PARENTS_KEY="_mistia_android_asset_publication_parents"
val LOCAL_ASSET_PUBLICATION_KEYS=setOf(LOCAL_ASSET_IMAGE_INTENT_KEY,LOCAL_ASSET_PUBLICATION_PARENTS_KEY)

data class InvestmentAssetPublicationParent(
    val baseVersion:Long,val confirmedVersion:Long?,val deviceId:String,val deleted:Boolean,
    val fingerprint:String,val metadataFingerprint:String,
)

fun investmentAssetPublicationFingerprint(payload:JsonObject,ignoreImage:Boolean=false):String {
    val stripped=assetPayloadForCloud(payload)
    val semantic=if(ignoreImage)stripped-"image_path" else stripped
    return RecordConflictResolver.semanticFingerprint(JsonObject(semantic.mapValues{(key,value)->
        if(key=="archived_at" && value is JsonPrimitive && value.isString)JsonPrimitive(Instant.parse(value.content).toString()) else value
    }))
}

fun localAssetPublicationParents(row:CloudRecord):List<InvestmentAssetPublicationParent> {
    val value=row.payload[LOCAL_ASSET_PUBLICATION_PARENTS_KEY] ?: return emptyList()
    require(row.entity==CloudEntity.INVESTMENT_ASSET.table && financeRawUuid(row.ownerUserId)==row.ownerUserId && financeRawUuid(row.id)==row.id)
    require(row.payload.financeRawString("id")==row.id && row.payload.financeRawString("user_id")==row.ownerUserId)
    val marker=value as? JsonObject ?: throw IllegalArgumentException("Invalid local asset parents")
    require(marker.keys==setOf("version","owner_user_id","asset_id","parents") && marker["version"]==JsonPrimitive(1))
    require(marker.financeRawString("owner_user_id")==row.ownerUserId && marker.financeRawString("asset_id")==row.id)
    val entries=marker["parents"] as? JsonArray ?: throw IllegalArgumentException("Invalid local asset parents")
    require(entries.size in 1..64)
    val result=entries.map{entry->
        val p=entry as? JsonObject ?: throw IllegalArgumentException("Invalid local asset parent")
        require(p.keys==setOf("base_version","confirmed_version","device_id","deleted","fingerprint","metadata_fingerprint"))
        val base=requireNotNull(p.financeRawLong("base_version")).also{require(it>=0 && it<Long.MAX_VALUE)}
        val confirmed=if(p["confirmed_version"]==JsonNull)null else requireNotNull(p.financeRawLong("confirmed_version")).also{require(it>base)}
        val device=requireNotNull(p.financeRawString("device_id")).also{require(financeRawUuid(it)==it)}
        val deleted=requireNotNull((p["deleted"] as? JsonPrimitive)?.takeIf{!it.isString}?.booleanOrNull)
        fun hash(key:String)=requireNotNull(p.financeRawString(key)).also{require(Regex("[0-9a-f]{64}").matches(it))}
        InvestmentAssetPublicationParent(base,confirmed,device,deleted,hash("fingerprint"),hash("metadata_fingerprint"))
    }
    require(result.distinct().size==result.size)
    return result
}

fun CloudRecord.withAssetPublicationParent(parent:InvestmentAssetPublicationParent):CloudRecord {
    val entries=(localAssetPublicationParents(this)+parent).distinct().takeLast(64)
    val marker=buildJsonObject {
        put("version",1);put("owner_user_id",ownerUserId);put("asset_id",id)
        put("parents",JsonArray(entries.map{p->buildJsonObject {
            put("base_version",p.baseVersion);put("confirmed_version",p.confirmedVersion?.let(::JsonPrimitive) ?: JsonNull)
            put("device_id",p.deviceId);put("deleted",p.deleted);put("fingerprint",p.fingerprint);put("metadata_fingerprint",p.metadataFingerprint)
        }}))
    }
    return copy(payload=JsonObject(payload+(LOCAL_ASSET_PUBLICATION_PARENTS_KEY to marker))).also{localAssetPublicationParents(it)}
}

internal fun CloudRecord.withPriorAssetPublication(prior:CloudRecord):CloudRecord {
    if(entity!=CloudEntity.INVESTMENT_ASSET.table)return this
    localAssetPublicationParents(prior) // Invalid evidence cannot be silently replaced.
    if(deletedAt==prior.deletedAt && investmentAssetPublicationFingerprint(payload)==investmentAssetPublicationFingerprint(prior.payload))return this
    val device=prior.payload.financeRawString("last_modified_by_device_id") ?: return this
    if(prior.syncVersion==Long.MAX_VALUE)return this
    return withAssetPublicationParent(InvestmentAssetPublicationParent(prior.syncVersion,null,device,prior.deletedAt!=null,
        investmentAssetPublicationFingerprint(prior.payload),investmentAssetPublicationFingerprint(prior.payload,true)))
}

fun isKnownPriorAssetPublication(local:CloudRecord,remote:CloudRecord,device:String,ignoreImage:Boolean):Boolean {
    require(local.entity==remote.entity && local.id==remote.id && local.ownerUserId==remote.ownerUserId)
    if(remote.payload.financeRawString("last_modified_by_device_id")!=device)return false
    val fingerprint=investmentAssetPublicationFingerprint(remote.payload,ignoreImage)
    return localAssetPublicationParents(local).any{p->p.deviceId==device && p.deleted==(remote.deletedAt!=null) &&
        remote.syncVersion==(p.confirmedVersion ?: (p.baseVersion+1)) &&
        fingerprint==(if(ignoreImage)p.metadataFingerprint else p.fingerprint)}
}

fun appendAssetPublicationParent(row:CloudRecord,parent:InvestmentAssetPublicationParent):CloudRecord = row.withAssetPublicationParent(parent)
