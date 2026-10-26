package vn.com.quyln.mistia.core.model

import kotlinx.serialization.json.*

/** Local provenance only; this reserved field must never reach a backend row. */
const val LOCAL_ASSET_IMAGE_INTENT_KEY="_mistia_android_asset_image_intent"

/** Missing is legacy/Keep; malformed intent is never interpreted as permission to publish. */
fun localAssetImagePublication(row:CloudRecord):InvestmentProductImagePublication? {
    val value=row.payload[LOCAL_ASSET_IMAGE_INTENT_KEY] ?: return null
    require(row.entity==CloudEntity.INVESTMENT_ASSET.table && financeRawUuid(row.ownerUserId)==row.ownerUserId && financeRawUuid(row.id)==row.id)
    require(row.payload.financeRawString("id")==row.id && row.payload.financeRawString("user_id")==row.ownerUserId)
    val marker=value as? JsonObject ?: throw IllegalArgumentException("Invalid local image intent")
    require(marker.keys==setOf("version","owner_user_id","asset_id","revision","previous_path","candidate"))
    require(marker["version"]==JsonPrimitive(1))
    fun text(objectValue:JsonObject,key:String):String=requireNotNull((objectValue[key] as? JsonPrimitive)?.takeIf{it.isString}?.content)
    val owner=UserId(row.ownerUserId)
    require(text(marker,"owner_user_id")==owner.value && text(marker,"asset_id")==row.id)
    val revision=text(marker,"revision").also{require(financeRawUuid(it)==it)}
    val previous=if(marker["previous_path"]==JsonNull)null else text(marker,"previous_path").also{InvestmentProductImagePath.parse(owner,row.id,it)}
    val candidate=if(marker["candidate"]==JsonNull)null else {
        val entry=marker["candidate"] as? JsonObject ?: throw IllegalArgumentException("Invalid local image candidate")
        require(entry.keys==setOf("path","image_sha256","thumbnail_sha256"))
        val path=text(entry,"path").also{InvestmentProductImagePath.parse(owner,row.id,it);require(it!=previous)}
        val imageHash=text(entry,"image_sha256").also{require(Regex("[0-9a-f]{64}").matches(it))}
        val thumbHash=text(entry,"thumbnail_sha256").also{require(Regex("[0-9a-f]{64}").matches(it))}
        InvestmentProductImageCandidate(owner.value,row.id,path,imageHash,thumbHash)
    }
    require(row.payload["image_path"]==(candidate?.path?.let(::JsonPrimitive) ?: JsonNull))
    return InvestmentProductImagePublication(owner.value,row.id,revision,previous,candidate)
}

fun assetPayloadForCloud(payload:JsonObject):JsonObject = JsonObject(payload-LOCAL_ASSET_PUBLICATION_KEYS)

internal fun InvestmentAssetMutationPlan.withLocalImagePublication(publication:InvestmentProductImagePublication):InvestmentAssetMutationPlan {
    val marker=buildJsonObject {
        put("version",1);put("owner_user_id",publication.ownerUserId);put("asset_id",publication.assetId);put("revision",publication.revision)
        put("previous_path",publication.previousPath?.let(::JsonPrimitive) ?: JsonNull)
        put("candidate",publication.candidate?.let{candidate->buildJsonObject {
            put("path",candidate.path);put("image_sha256",candidate.imageSha256);put("thumbnail_sha256",candidate.thumbnailSha256)
        }} ?: JsonNull)
    }
    return copy(mutations=mutations.map{(row,queued)->
        if(row.entity!=CloudEntity.INVESTMENT_ASSET.table || row.id!=publication.assetId)row to queued
        else {
            val changed=row.copy(payload=JsonObject(row.payload+(LOCAL_ASSET_IMAGE_INTENT_KEY to marker)))
            require(localAssetImagePublication(changed)==publication)
            changed to queued.copy(payload=changed.payload)
        }
    })
}
