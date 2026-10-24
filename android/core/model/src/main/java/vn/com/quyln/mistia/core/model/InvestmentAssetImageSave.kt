package vn.com.quyln.mistia.core.model

import java.time.Instant
import kotlinx.serialization.json.*

data class InvestmentAssetImageSaveRequest(val draft:InvestmentAssetDraft,val publication:InvestmentProductImagePublication)

/** Unsafe legacy values may be cleared, but never become object download/deletion authority. */
fun ownedInvestmentImagePathOrNull(owner:UserId,assetId:String,path:String?):String? =
    path?.let{runCatching{InvestmentProductImagePath.parse(owner,assetId,it).value}.getOrNull()}

fun planInvestmentAssetImageSave(snapshot:InvestmentAssetSnapshot,request:InvestmentAssetImageSaveRequest,deviceId:String,now:String):InvestmentAssetMutationPlan {
    fun stale():Nothing=investmentAssetFail(InvestmentAssetError.STALE_RECORD)
    val draft=request.draft;val publication=request.publication;val expected=draft.expected
    if(publication.ownerUserId!=snapshot.owner.value || publication.assetId!=draft.id || financeRawUuid(publication.revision)!=publication.revision ||
        publication.previousPath!=ownedInvestmentImagePathOrNull(snapshot.owner,draft.id,expected?.imagePath))stale()
    if(expected!=null && (expected.ownerUserId!=snapshot.owner.value || expected.id!=draft.id))stale()
    val target=when(val change=draft.imageChange) {
        InvestmentAssetImageChange.Keep->stale()
        InvestmentAssetImageChange.Remove->{if(publication.candidate!=null)stale();null}
        is InvestmentAssetImageChange.Replace->{
            val image=publication.candidate ?: stale()
            if(image.ownerUserId!=snapshot.owner.value || image.assetId!=draft.id || image.path!=change.path.value ||
                !Regex("[0-9a-f]{64}").matches(image.imageSha256) || !Regex("[0-9a-f]{64}").matches(image.thumbnailSha256))stale()
            InvestmentProductImagePath.parse(snapshot.owner,draft.id,image.path).value
        }
    }
    try{return planInvestmentAssetMutation(snapshot,InvestmentAssetRequest.Save(draft),deviceId,now)}
    catch(error:InvestmentAssetException){if(error.reason!=InvestmentAssetError.STALE_RECORD)throw error}
    // An old baseline is eligible only for an exact already committed proposal, never a rebase.
    val raw=snapshot.records(CloudEntity.INVESTMENT_ASSET).singleOrNull{it.id==draft.id} ?: stale()
    val current=investmentAssetDecode(raw)
    val unit=InvestmentUnitLabel.normalizedDisplay(draft.defaultUnitLabel) ?: stale()
    if(current.deletedAt!=null || current.name!=normalizedInvestmentChannelName(draft.name) || current.channelId!=draft.channelId ||
        current.currencyCode!=investmentAssetCurrency(draft.currencyCode) || current.defaultUnitLabel!=unit || current.imagePath!=target)stale()
    if(expected!=null && !expected.copy(name=current.name,channelId=current.channelId,currencyCode=current.currencyCode,
        defaultUnitLabel=current.defaultUnitLabel,imagePath=current.imagePath).matchesVisibleInvestmentAsset(current))stale()
    val probe=planInvestmentAssetMutation(snapshot,InvestmentAssetRequest.Save(draft.copy(expected=current)),deviceId,now)
    if(probe.mutations.any{row->snapshot.rows.singleOrNull{it.entity==row.first.entity && it.id==row.first.id}?.let{imageSemantic(it)==imageSemantic(row.first)}!=true})stale()
    // Legacy unit resolution can write financial history in the same transaction as the photo.
    if(expected?.defaultUnitLabel==null && expected!=null) {
        val history=investmentAssetHistory(snapshot,current.id)
        if(history.any{it.payload.financeRawString("unit_label")?.let(InvestmentUnitLabel::normalizedDisplay)==null})investmentAssetFail(InvestmentAssetError.INVALID_ACCOUNTING)
        val rebuilt=rebuildInvestmentAssetUnitHistory(snapshot,current,unit,deviceId,now)
        if(rebuilt.any{row->snapshot.rows.singleOrNull{it.entity==row.entity && it.id==row.id}?.let{imageSemantic(row)==imageSemantic(it)}!=true})investmentAssetFail(InvestmentAssetError.INVALID_ACCOUNTING)
    }
    return InvestmentAssetMutationPlan(current,emptyList())
}
private fun imageSemantic(raw:CloudRecord)=JsonObject(raw.payload.filterKeys{it !in setOf("updated_at","sync_version","last_modified_by_device_id","last_modified_by_user_id")}.mapValues{(key,value)->
    if(key in setOf("created_at","occurred_at","deleted_at","archived_at") && value is JsonPrimitive && value.isString)
        runCatching{JsonPrimitive(Instant.parse(value.content).toString())}.getOrDefault(value) else value
})
