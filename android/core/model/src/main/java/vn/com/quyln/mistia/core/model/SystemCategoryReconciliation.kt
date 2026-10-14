package vn.com.quyln.mistia.core.model

import java.time.Instant
import java.util.UUID
import kotlinx.serialization.json.*

/** Identity is a real stored row; values can come from a different duplicate. */
data class SystemCategoryRemoteSelection(val identity:CloudRecord,val values:CloudRecord,val candidates:List<CloudRecord>)
data class CategoryReferenceMutation(val record:CloudRecord,val mutation:PendingMutation)

fun selectSystemCategoryRemote(owner:UserId,key:String,rows:List<CloudRecord>):SystemCategoryRemoteSelection? {
    require(key.isNotBlank() && key==key.trim())
    val cloudID=SystemCategoryIdentity.cloudId(key,owner)
    require(rows.map {it.id}.distinct().size==rows.size) {"Duplicate remote identity in category pages"}
    rows.forEach {row ->
        require(row.entity==CloudEntity.TRANSACTION_CATEGORY.table && row.ownerUserId==owner.value)
        require((row.payload["id"] as? JsonPrimitive)?.content==row.id && (row.payload["user_id"] as? JsonPrimitive)?.content==owner.value)
        val category=TransactionCategoryRecord.fromCloudRecord(row)
        require(category.id==row.id && category.ownerUserId==owner.value && category.isSystem && category.systemKey==key)
        val version=row.payload["sync_version"] as? JsonPrimitive
        require(version!=null && !version.isString && version.longOrNull==row.syncVersion)
        require(row.syncVersion>=0 && category.syncVersion==row.syncVersion)
        require(Instant.parse(category.updatedAt)==Instant.parse(requireNotNull(row.updatedAt)))
        require("deleted_at" in row.payload)
        val deletion=row.payload["deleted_at"]
        require(if(deletion==JsonNull) row.deletedAt==null else deletion is JsonPrimitive && deletion.isString && deletion.content==row.deletedAt)
        require(category.deletedAt==row.deletedAt)
    }
    val candidates=rows.filter {it.deletedAt==null}.ifEmpty {rows}
    // Swift remoteCategoryPriority truncates fractional timestamp seconds and
    // adds 1000 for the existing owner-cloud ID. Active values are chosen first.
    fun score(row:CloudRecord):Long {
        val instant=Instant.parse(requireNotNull(row.updatedAt))
        val whole=instant.epochSecond+if(instant.epochSecond<0 && instant.nano!=0) 1 else 0
        return whole+if(row.id==cloudID) 1000 else 0
    }
    val values=candidates.maxWithOrNull(compareBy(::score)) ?: return null
    val identity=rows.firstOrNull {it.id==cloudID} ?: values
    return SystemCategoryRemoteSelection(identity,values,rows.toList())
}

/** Lossless FK repair only: never decodes/re-encodes financial or future fields. */
fun rewriteOwnedCategoryReference(owner:UserId,record:CloudRecord,pending:PendingMutation?,oldId:String,newId:String,deviceId:String,now:String):CategoryReferenceMutation? {
    if(record.ownerUserId!=owner.value || (record.payload["user_id"] as? JsonPrimitive)?.content!=owner.value || oldId==newId) return null
    val entity=CloudEntity.fromTable(record.entity) ?: return null
    val field=when(entity) {
        CloudEntity.TRANSACTION_CATEGORY -> "parent_category_id"
        CloudEntity.LEDGER_TRANSACTION,CloudEntity.BUDGET_PLAN,CloudEntity.RECURRING_BILL_PLAN -> "category_id"
        else -> return null
    }
    if((record.payload[field] as? JsonPrimitive)?.takeIf {it.isString}?.content!=oldId) return null
    require((record.payload["id"] as? JsonPrimitive)?.content==record.id)
    UUID.fromString(oldId);UUID.fromString(newId)
    val device=UUID.fromString(deviceId).toString()
    val version=record.payload["sync_version"] as? JsonPrimitive
    require(version!=null && !version.isString && version.longOrNull==record.syncVersion && record.syncVersion>=0)
    val payloadUpdated=record.payload["updated_at"] as? JsonPrimitive
    require(payloadUpdated!=null && payloadUpdated.isString && Instant.parse(payloadUpdated.content)==Instant.parse(requireNotNull(record.updatedAt)))
    require("deleted_at" in record.payload)
    val deletion=record.payload["deleted_at"]
    require(if(deletion==JsonNull) record.deletedAt==null else deletion is JsonPrimitive && deletion.isString && deletion.content==record.deletedAt)
    pending?.let {
        require(it.subjectUserId==owner.value && it.entity==entity && it.recordId==record.id && it.payload==record.payload)
        require(it.baseVersion>=0)
        require(it.kind!=MutationKind.DELETE || record.deletedAt!=null)
    }
    val timestamp=maxOf(Instant.parse(now),Instant.parse(requireNotNull(record.updatedAt))).toString()
    val payload=JsonObject(record.payload+mapOf(field to JsonPrimitive(newId),"updated_at" to JsonPrimitive(timestamp),
        "last_modified_by_device_id" to JsonPrimitive(device)))
    val changed=record.copy(payload=payload,updatedAt=timestamp)
    val mutation=PendingMutation(entity,record.id,owner.value,pending?.kind ?: if(record.deletedAt!=null) MutationKind.DELETE else MutationKind.UPSERT,
        payload,timestamp,pending?.baseVersion ?: record.syncVersion,device)
    return CategoryReferenceMutation(changed,mutation)
}
