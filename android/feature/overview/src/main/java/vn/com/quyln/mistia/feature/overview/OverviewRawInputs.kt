package vn.com.quyln.mistia.feature.overview

import java.util.UUID
import kotlinx.serialization.json.*
import vn.com.quyln.mistia.core.model.*

internal fun overviewRawUuid(value:String):String?=runCatching {UUID.fromString(value).toString().takeIf {it==value.lowercase(java.util.Locale.ROOT)}}.getOrNull()
internal fun JsonObject.overviewRawString(key:String)=(get(key) as? JsonPrimitive)?.takeIf {it.isString}?.contentOrNull
internal fun JsonObject.overviewRawLong(key:String)=(get(key) as? JsonPrimitive)?.takeIf {!it.isString}?.longOrNull
internal fun JsonObject.overviewRawArchived():Boolean?=if("is_archived" !in this) false else (get("is_archived") as? JsonPrimitive)?.takeIf {!it.isString}?.booleanOrNull
internal fun CloudRecord.overviewRawDeleted():Boolean? {
    if(deletedAt!=null) return true
    val value=payload["deleted_at"]
    if(value==null || value==JsonNull) return false
    return (value as? JsonPrimitive)?.takeIf {it.isString}?.contentOrNull?.takeIf {it.isNotBlank()}?.let {true}
}
internal fun CloudRecord.overviewRawIdentity(owner:UserId,expected:CloudEntity):Boolean {
    if(entity!=expected.table || ownerUserId!=owner.value || overviewRawUuid(id)==null) return false
    for((key,target) in listOf("id" to overviewRawUuid(id),"user_id" to owner.value)) {
        val value=payload[key]
        if(value==null || value==JsonNull) continue
        if(payload.overviewRawString(key)?.let(::overviewRawUuid)!=target) return false
    }
    return true
}
internal data class OverviewRawReference(val id:String?,val readable:Boolean) {
    fun mayReferTo(ids:Set<String>):Boolean=if(readable) id in ids else ids.isNotEmpty()
}
internal fun JsonObject.overviewRawReference(key:String):OverviewRawReference {
    val value=get(key)
    if(value==null || value==JsonNull) return OverviewRawReference(null,true)
    val id=overviewRawString(key)?.let(::overviewRawUuid)
    return OverviewRawReference(id,id!=null)
}
