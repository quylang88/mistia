package vn.com.quyln.mistia.core.model

import java.time.Instant
import java.util.UUID

interface SystemCategoryBootstrapRepository {
    suspend fun ensureDefaultSystemCategories(owner:UserId,catalog:SystemCategoryCatalog,deviceId:String,now:String):Result<SystemCategoryBootstrapResult>
}
data class SystemCategoryBootstrapResult(val createdCount:Int,val duplicateSystemKeys:Set<String>,val preservedTombstoneKeys:Set<String>)

fun SystemCategoryDefinition.seedRecord(owner:UserId,parentId:String?,deviceId:String,now:String):TransactionCategoryRecord {
    require(isActive && sortOrder!=null)
    require((parentKey==null)==(parentId==null))
    Instant.parse(now)
    return TransactionCategoryRecord(SystemCategoryIdentity.cloudId(key,owner),UUID.fromString(owner.value).toString(),name,nameEnglish,nameJapanese,
        kind.wireValue,iconSymbolName,iconColorHex,false,false,parentId,
        if(parentKey==null) CategoryHierarchyRole.PARENT.wireValue else CategoryHierarchyRole.CHILD.wireValue,
        key,true,sortOrder,false,null,now,now,null,0,UUID.fromString(deviceId).toString())
}
fun TransactionCategoryRecord.bootstrapMutation()=PendingMutation(CloudEntity.TRANSACTION_CATEGORY,id,ownerUserId,MutationKind.UPSERT,
    toPayload(),updatedAt,syncVersion,requireNotNull(lastModifiedByDeviceId))

/** Narrow provenance check: a semantically exact, unmodified, never-uploaded default. */
fun TransactionCategoryRecord.isUntouchedSystemCategorySeed(catalog:SystemCategoryCatalog,parent:TransactionCategoryRecord?):Boolean = runCatching {
    if(syncVersion!=0L || deletedAt!=null || lastModifiedByDeviceId==null || Instant.parse(createdAt)!=Instant.parse(updatedAt)) return@runCatching false
    val definition=catalog.activeDefinitions.firstOrNull {it.key==systemKey} ?: return@runCatching false
    if(definition.parentKey==null) {
        if(parentCategoryId!=null) return@runCatching false
    } else {
        if(parent==null || parent.id!=parentCategoryId || parent.ownerUserId!=ownerUserId || parent.systemKey!=definition.parentKey ||
            parent.hierarchyRole!=CategoryHierarchyRole.PARENT || parent.kind!=definition.kind) return@runCatching false
    }
    copy(updatedAt=createdAt)==definition.seedRecord(UserId(ownerUserId),parentCategoryId,lastModifiedByDeviceId,createdAt)
}.getOrDefault(false)
