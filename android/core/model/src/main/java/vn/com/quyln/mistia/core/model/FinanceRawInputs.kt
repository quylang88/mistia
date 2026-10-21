package vn.com.quyln.mistia.core.model

import java.util.UUID
import java.util.Locale
import java.text.Normalizer
import kotlinx.serialization.json.*

fun financeRawUuid(value:String):String?=runCatching {UUID.fromString(value).toString().takeIf {it==value.lowercase(java.util.Locale.ROOT)}}.getOrNull()
fun JsonObject.financeRawString(key:String)=(get(key) as? JsonPrimitive)?.takeIf {it.isString}?.contentOrNull
fun JsonObject.financeRawLong(key:String)=(get(key) as? JsonPrimitive)?.takeIf {!it.isString}?.longOrNull
fun JsonObject.financeRawArchived():Boolean?=if("is_archived" !in this) false else (get("is_archived") as? JsonPrimitive)?.takeIf {!it.isString}?.booleanOrNull
fun CloudRecord.financeRawDeleted(requireTimestamp:Boolean=false):Boolean? {
    fun valid(value:String)=!requireTimestamp || runCatching {java.time.Instant.parse(value)}.isSuccess
    if(deletedAt!=null) return if(valid(deletedAt)) true else null
    val value=payload["deleted_at"]
    if(value==null || value==JsonNull) return false
    return (value as? JsonPrimitive)?.takeIf {it.isString}?.contentOrNull?.takeIf {it.isNotBlank() && valid(it)}?.let {true}
}
fun CloudRecord.financeRawIdentity(owner:UserId,expected:CloudEntity,requireBodyIdentity:Boolean=false):Boolean {
    if(entity!=expected.table || ownerUserId!=owner.value || financeRawUuid(id)==null) return false
    for((key,target) in listOf("id" to financeRawUuid(id),"user_id" to owner.value)) {
        val value=payload[key]
        if(value==null || value==JsonNull) {if(requireBodyIdentity) return false else continue}
        if(payload.financeRawString(key)?.let(::financeRawUuid)!=target) return false
    }
    return true
}
data class FinanceRawReference(val id:String?,val readable:Boolean) {
    fun mayReferTo(ids:Set<String>):Boolean=if(readable) id in ids else ids.isNotEmpty()
}
fun JsonObject.financeRawReference(key:String):FinanceRawReference {
    val value=get(key)
    if(value==null || value==JsonNull) return FinanceRawReference(null,true)
    val id=financeRawString(key)?.let(::financeRawUuid)
    return FinanceRawReference(id,id!=null)
}

private val financeCodePattern=Regex("[A-Z]{3}")
fun String.financeReportingCode():String?=trim().uppercase(Locale.ROOT).takeIf {it.matches(financeCodePattern)}
fun JsonObject.financePresent(key:String):Boolean=get(key).let {it!=null && it!=JsonNull}

/** Swift String equality is canonical-equivalent; grouping also compacts Unicode whitespace. */
fun financeGroupingName(name:String?):String {
    val compact=buildString {
        var gap=false
        for(character in name.orEmpty()) {
            if(character.isFinanceWhitespace()) {if(isNotEmpty()) gap=true}
            else {if(gap) append(' ');append(character);gap=false}
        }
    }
    return Normalizer.normalize(compact.lowercase(Locale.ROOT),Normalizer.Form.NFC)
}
private fun Char.isFinanceWhitespace():Boolean=isWhitespace() || this=='\u0085'
internal fun financeTitleKey(title:String):String =
    Normalizer.normalize(title.trim {it.isFinanceWhitespace()}.lowercase(Locale.ROOT),Normalizer.Form.NFC)
private val financeCombiningMarks=Regex("\\p{M}+")
internal fun isFinanceCreditCardPaymentTitle(title:String):Boolean {
    val canonical=financeTitleKey(title)
    val folded=Normalizer.normalize(canonical,Normalizer.Form.NFD).replace(financeCombiningMarks,"")
    return folded.contains("card payment") || folded.contains("thanh toan the") || canonical.contains("カード支払い")
}
