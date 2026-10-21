package vn.com.quyln.mistia.core.model

import java.time.Instant
import kotlinx.serialization.json.*

/** Read-only category facts; normalization here never reaches an editor or a stored payload. */
internal data class BudgetCategoryReadMetadata(
    val records:List<TransactionCategoryRecord>,
    val rawById:Map<String,CloudRecord>,
    val unknownNames:Set<String>,
    val unknownParents:Set<String>,
    val unknownRoles:Set<String>,
    val uncertainAliasRefs:Set<String>,
    val allAliasesUncertain:Boolean,
)

internal fun budgetCategoryReadMetadata(owner:UserId,rows:List<CloudRecord>,language:CategoryNameLanguage):BudgetCategoryReadMetadata {
    val owned=rows.filter {it.financeRawIdentity(owner,CloudEntity.TRANSACTION_CATEGORY,requireBodyIdentity=true)}.associateBy {financeRawUuid(it.id)!!}
    val records=mutableListOf<TransactionCategoryRecord>();val names=mutableSetOf<String>();val parents=mutableSetOf<String>();val roles=mutableSetOf<String>();val aliasRefs=mutableSetOf<String>()
    var allAliases=false
    for((id,raw) in owned) {
        val p=raw.payload;val read=p.toMutableMap()
        val parent=p.financeRawReference("parent_category_id")
        if(!parent.readable){parents+=id;read["parent_category_id"]=JsonNull}
        val preferred=when(language){CategoryNameLanguage.ENGLISH -> "name_english";CategoryNameLanguage.JAPANESE -> "name_japanese";else -> "name"}
        fun badString(key:String)=p.financePresent(key) && p.financeRawString(key)==null
        val effective=if(!badString(preferred)) p.financeRawString(preferred)?.takeIf {it.isNotBlank()} else null
        val nameKnown=!badString(preferred) && (effective!=null || (!badString("name") && !p.financeRawString("name").isNullOrBlank()))
        for(key in listOf("name","name_english","name_japanese")) if(badString(key)) read[key]=JsonNull
        if(!nameKnown){names+=id;for(key in listOf("name","name_english","name_japanese")) read[key]=JsonPrimitive("")}
        val role=p.financeRawString("hierarchy_role_raw_value")?.let(CategoryHierarchyRole::fromWireValue)
        if((p.financePresent("hierarchy_role_raw_value") && role==null) || (!p.financePresent("hierarchy_role_raw_value") && !parent.readable)) {
            roles+=id;read["hierarchy_role_raw_value"]=JsonNull
        }
        fun boolean(key:String):Boolean?=if(!p.financePresent(key)) false else (p[key] as? JsonPrimitive)?.takeUnless {it.isString}?.booleanOrNull
        val system=boolean("is_system");val key=p.financeRawString("system_key");val badKey=badString("system_key")
        fun taintAlias() {
            if(system==false) return
            if(badKey){allAliases=true;return}
            if(key!=null){aliasRefs+=id;aliasRefs+=SystemCategoryIdentity.canonicalId(key);aliasRefs+=SystemCategoryIdentity.cloudId(key,owner)}
        }
        if(system==null || badKey) taintAlias()
        read["is_system"]=JsonPrimitive(system ?: false)
        if(badKey) read["system_key"]=JsonNull
        val archived=boolean("is_archived")
        if(archived==null) taintAlias()
        read["is_archived"]=JsonPrimitive(archived ?: false)
        if(raw.financeRawDeleted(requireTimestamp=true)==null){taintAlias();read["deleted_at"]=JsonNull}
        val update=p.financeRawString("updated_at") ?: raw.updatedAt
        if(update==null || runCatching {Instant.parse(update)}.isFailure) {
            taintAlias();read["updated_at"]=JsonPrimitive(raw.updatedAt?.takeIf {runCatching {Instant.parse(it)}.isSuccess} ?: Instant.EPOCH.toString())
        } else if(badString("updated_at")) read["updated_at"]=JsonPrimitive(update)
        if(p.financePresent("sync_version") && p.financeRawLong("sync_version")==null){taintAlias();read["sync_version"]=JsonPrimitive(raw.syncVersion)}
        for(field in listOf("created_at","icon_symbol_name","icon_color_hex","archived_at","last_modified_by_device_id","kind_raw_value")) if(badString(field)) read[field]=JsonNull
        for(field in listOf("is_favorite","family_budget_spending_enabled")) if(boolean(field)==null) read[field]=JsonPrimitive(false)
        if(p.financePresent("sort_order") && p.financeRawLong("sort_order")==null) read["sort_order"]=JsonPrimitive(0)
        runCatching {TransactionCategoryRecord.fromCloudRecord(raw.copy(payload=JsonObject(read)))}.getOrNull()?.let(records::add)
    }
    return BudgetCategoryReadMetadata(records,owned,names,parents,roles,aliasRefs,allAliases)
}
