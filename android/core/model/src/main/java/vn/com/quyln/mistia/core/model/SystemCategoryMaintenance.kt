package vn.com.quyln.mistia.core.model

import java.time.Instant
import java.util.UUID
import kotlinx.serialization.json.JsonPrimitive

class CategoryGroupEditsPending : IllegalArgumentException("Category group has pending local edits")

/** Reconciles actual observed rows without inventing a bootstrap queue or cloud ID. */
fun planObservedSystemCategoryMaintenance(snapshot:CategoryReferenceSnapshot,key:String,remote:List<CloudRecord>,
    catalog:SystemCategoryCatalog,deviceId:String,now:String):SystemCategoryIdentityMigration? {
    snapshot.requireUnchanged(snapshot)
    UUID.fromString(deviceId);Instant.parse(now)
    val selection=selectSystemCategoryRemote(snapshot.owner,key,remote) ?: return null
    val definition=requireNotNull(catalog.definitions.singleOrNull {it.key==key})
    val role=if(definition.parentKey==null) CategoryHierarchyRole.PARENT else CategoryHierarchyRole.CHILD
    remote.forEach {row ->
        val category=TransactionCategoryRecord.fromCloudRecord(row)
        require(category.kind==definition.kind && category.hierarchyRole==role)
    }
    val stored=snapshot.records.getValue(CloudEntity.TRANSACTION_CATEGORY)
    val localGroup=stored.filter {it.payload["system_key"]==JsonPrimitive(key) && it.payload["is_system"]==JsonPrimitive(true)}
    val ids=(remote+localGroup).map {it.id}.toSet()
    if(snapshot.pending.any {it.mutation.entity==CloudEntity.TRANSACTION_CATEGORY && it.mutation.recordId in ids} ||
        snapshot.translations.any {it.translation.categoryId in ids}) throw CategoryGroupEditsPending()
    remote.forEach {row ->
        stored.singleOrNull {it.id==row.id}?.let {existing ->
            selectSystemCategoryRemote(snapshot.owner,key,listOf(existing))
            require(existing.syncVersion<=row.syncVersion) {"Category group advanced after lookup"}
        }
    }
    val (target,mutation)=mergeSystemCategoryValues(snapshot,selection.identity,selection,emptyMap(),deviceId,now)
    val adoption=SystemCategoryAdoption(selection.identity,selection,target,mutation,null)
    return planSystemCategoryIdentityChanges(snapshot,adoption,deviceId,now)
}
