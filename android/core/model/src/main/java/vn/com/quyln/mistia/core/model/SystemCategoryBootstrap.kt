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
