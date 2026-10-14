package vn.com.quyln.mistia.core.model

import java.time.Instant
import java.util.UUID
import kotlinx.serialization.json.*

class CategoryParentReconciliationRequired : IllegalArgumentException("Category parent reconciliation required")

/** Preparation only: identity installation/removal and dependent repairs must commit together. */
data class SystemCategoryAdoption(
    val source: CloudRecord,
    val selection: SystemCategoryRemoteSelection,
    val target: CloudRecord,
    val mutation: PendingMutation?,
    val translation: PendingCategoryTranslation?,
)
fun prepareSystemCategoryAdoption(snapshot:CategoryReferenceSnapshot,queued:QueuedMutation,remote:List<CloudRecord>,catalog:SystemCategoryCatalog,deviceId:String,now:String):SystemCategoryAdoption {
    snapshot.requireUnchanged(snapshot)
    UUID.fromString(deviceId); Instant.parse(now)
    require(!queued.remoteIdentityObserved) {"Observed remote identity is not a bootstrap seed"}
    val pending=queued.mutation
    require(pending.entity==CloudEntity.TRANSACTION_CATEGORY && pending.subjectUserId==snapshot.owner.value && pending.kind==MutationKind.UPSERT && pending.baseVersion==0L)
    require(snapshot.pending.singleOrNull {it.mutation.entity==pending.entity && it.mutation.recordId==pending.recordId}==queued) {"Stale queued seed"}
    val categories=snapshot.records.getValue(CloudEntity.TRANSACTION_CATEGORY)
    val source=requireNotNull(categories.singleOrNull {it.id==pending.recordId})
    require(source.payload==pending.payload && source.syncVersion==0L && source.deletedAt==null && source.updatedAt==pending.modifiedAt)
    val local=TransactionCategoryRecord.fromCloudRecord(source)
    val key=requireNotNull(local.systemKey)
    selectSystemCategoryRemote(snapshot.owner,key,listOf(source))
    val selection=requireNotNull(selectSystemCategoryRemote(snapshot.owner,key,remote))
    val identity=selection.identity
    if(identity.id!=source.id) {
        require(snapshot.pending.none {it.mutation.entity==CloudEntity.TRANSACTION_CATEGORY && it.mutation.recordId==identity.id}) {"Target has pending local edits"}
        require(snapshot.translations.none {it.translation.categoryId==identity.id}) {"Target has a pending translation"}
        categories.singleOrNull {it.id==identity.id}?.let {existing ->
            selectSystemCategoryRemote(snapshot.owner,key,listOf(existing))
            require(existing.syncVersion<=identity.syncVersion) {"Target advanced after remote lookup"}
        }
    }
    val definition=requireNotNull(catalog.definitions.singleOrNull {it.key==key})
    require(local.kind==definition.kind)
    val parent=local.parentCategoryId?.let {id ->
        val row=requireNotNull(categories.singleOrNull {it.id==id}) {"Source parent metadata missing"}
        val typed=TransactionCategoryRecord.fromCloudRecord(row)
        require(row.ownerUserId==snapshot.owner.value && typed.ownerUserId==snapshot.owner.value && typed.id==id)
        typed
    }
    val baselineParent=definition.parentKey?.let {parentKey ->
        parent?.takeIf {it.systemKey==parentKey && it.isSystem}?.id ?: SystemCategoryIdentity.cloudId(parentKey,snapshot.owner)
    }
    val baseline=definition.copy(isActive=true,sortOrder=definition.sortOrder ?: local.sortOrder)
        .seedRecord(snapshot.owner,baselineParent,deviceId,local.createdAt).copy(isArchived=!definition.isActive).toPayload()
    val metadata=setOf("id","user_id","sync_version","created_at","updated_at","last_modified_by_device_id")
    val changes=source.payload.filter { (field,value) -> field !in metadata && baseline[field]!=value }.toMutableMap()
    val sourceTask=snapshot.translations.singleOrNull {it.translation.categoryId==source.id}?.translation?.takeIf {task ->
        val field=task.sourceLanguage.categoryNameField()
        task.savedUpdatedAt==source.updatedAt && (source.payload[field] as? JsonPrimitive)?.contentOrNull?.trim()==task.inputName.trim()
    }
    sourceTask?.let {changes[it.sourceLanguage.categoryNameField()]=requireNotNull(source.payload[it.sourceLanguage.categoryNameField()])}
    require(selection.values.deletedAt==null || changes.isEmpty()) {"Edited seed conflicts with authoritative tombstone"}
    val fields=(identity.payload+selection.values.payload+changes+mapOf(
        "id" to JsonPrimitive(identity.id),"user_id" to JsonPrimitive(snapshot.owner.value),
        "sync_version" to JsonPrimitive(identity.syncVersion),"created_at" to requireNotNull(identity.payload["created_at"]),
    )).toMutableMap()
    // A child imported after its parent group was reconciled must use the real
    // preferred parent identity, including when the old parent is retained deleted metadata.
    (fields["parent_category_id"] as? JsonPrimitive)?.contentOrNull?.let {parentID ->
        val parentRow=requireNotNull(categories.singleOrNull {it.id==parentID}) {"Target parent metadata unavailable"}
        val parentCategory=TransactionCategoryRecord.fromCloudRecord(parentRow)
        require(parentRow.ownerUserId==snapshot.owner.value && parentCategory.ownerUserId==snapshot.owner.value &&
            parentCategory.hierarchyRole==CategoryHierarchyRole.PARENT && parentCategory.parentCategoryId==null &&
            parentCategory.kindWireValue==(fields["kind_raw_value"] as? JsonPrimitive)?.content)
        if(parentCategory.isSystem && parentCategory.systemKey!=null) {
            val parents=categories.filter {row ->
                if((row.payload["user_id"] as? JsonPrimitive)?.content!=snapshot.owner.value) false else {
                    val typed=TransactionCategoryRecord.fromCloudRecord(row)
                    val queuedParent=snapshot.pending.singleOrNull {it.mutation.entity==CloudEntity.TRANSACTION_CATEGORY && it.mutation.recordId==row.id}
                    typed.isSystem && typed.systemKey==parentCategory.systemKey &&
                        (queuedParent==null || queuedParent.remoteIdentityObserved || row.syncVersion>0)
                }
            }
            val selectedParent=requireNotNull(selectSystemCategoryRemote(snapshot.owner,requireNotNull(parentCategory.systemKey),parents)) {"Parent identity has not been observed remotely"}
            val preferredParent=TransactionCategoryRecord.fromCloudRecord(selectedParent.identity)
            require(preferredParent.hierarchyRole==CategoryHierarchyRole.PARENT && preferredParent.parentCategoryId==null && preferredParent.kindWireValue==parentCategory.kindWireValue)
            if(selectedParent.identity.deletedAt!=null && fields["deleted_at"]==JsonNull) throw CategoryParentReconciliationRequired()
            fields["parent_category_id"]=JsonPrimitive(selectedParent.identity.id)
        }
    }
    val ignored=setOf("updated_at","last_modified_by_device_id")
    val changed=fields.filterKeys {it !in ignored}!=identity.payload.filterKeys {it !in ignored}
    val target=if(!changed) identity else {
        val prior=listOf(source,identity,selection.values).maxOf {Instant.parse(requireNotNull(it.updatedAt))}
        val timestamp=maxOf(Instant.parse(now),prior.plusMillis(1)).toString()
        fields["updated_at"]=JsonPrimitive(timestamp)
        fields["last_modified_by_device_id"]=JsonPrimitive(deviceId)
        identity.copy(payload=JsonObject(fields),updatedAt=timestamp,deletedAt=(fields["deleted_at"] as? JsonPrimitive)?.contentOrNull)
    }
    val mutation=if(!changed) null else PendingMutation(CloudEntity.TRANSACTION_CATEGORY,target.id,snapshot.owner.value,
        MutationKind.UPSERT,target.payload,requireNotNull(target.updatedAt),identity.syncVersion,deviceId)
    val translation=sourceTask?.takeIf {target.deletedAt==null && (target.payload[it.sourceLanguage.categoryNameField()] as? JsonPrimitive)?.contentOrNull?.trim()==it.inputName.trim()}
        ?.copy(categoryId=target.id,savedUpdatedAt=requireNotNull(target.updatedAt),deviceId=deviceId)
    return SystemCategoryAdoption(source,selection,target,mutation,translation)
}

private fun CategoryNameLanguage.categoryNameField()=when(this) {
    CategoryNameLanguage.VIETNAMESE -> "name"
    CategoryNameLanguage.ENGLISH -> "name_english"
    CategoryNameLanguage.JAPANESE -> "name_japanese"
}

data class SystemCategoryIdentityMigration(val adoption:SystemCategoryAdoption,val references:CategoryReferenceRepairs,val removesSourceIdentity:Boolean,val retainedCategories:List<CloudRecord> = emptyList())

/** Retains deleted aliases; an active competing identity needs ordered cloud cleanup. */
fun planSystemCategoryIdentityMigration(snapshot:CategoryReferenceSnapshot,queued:QueuedMutation,remote:List<CloudRecord>,catalog:SystemCategoryCatalog,deviceId:String,now:String):SystemCategoryIdentityMigration {
    val adoption=prepareSystemCategoryAdoption(snapshot,queued,remote,catalog,deviceId,now)
    val retained=remote.filter {it.id!=adoption.target.id}
    require(retained.all {it.deletedAt!=null}) {"Active competing identity requires cloud cleanup before adoption"}
    val storedCategories=snapshot.records.getValue(CloudEntity.TRANSACTION_CATEGORY)
    retained.forEach {row ->
        require(snapshot.pending.none {it.mutation.entity==CloudEntity.TRANSACTION_CATEGORY && it.mutation.recordId==row.id}) {"Retained alias has pending local edits"}
        require(snapshot.translations.none {it.translation.categoryId==row.id}) {"Retained alias has pending translation"}
        storedCategories.singleOrNull {it.id==row.id}?.let {existing ->
            selectSystemCategoryRemote(snapshot.owner,requireNotNull(TransactionCategoryRecord.fromCloudRecord(row).systemKey),listOf(existing))
            require(existing.syncVersion<=row.syncVersion) {"Retained alias advanced after lookup"}
        }
    }
    val removes=adoption.source.id!=adoption.target.id
    if(removes) {
        val category=TransactionCategoryRecord.fromCloudRecord(adoption.source)
        require(adoption.source.id==SystemCategoryIdentity.cloudId(requireNotNull(category.systemKey),snapshot.owner)) {"Only unpersisted owner-cloud seeds may be removed"}
        require(remote.none {it.id==adoption.source.id}) {"Persisted source requires cloud cleanup"}
        snapshot.records.forEach { (entity,rows) ->
            val field=if(entity==CloudEntity.TRANSACTION_CATEGORY) "parent_category_id" else "category_id"
            require(rows.none {row -> (row.payload["user_id"] as? JsonPrimitive)?.content!=snapshot.owner.value &&
                (row.payload[field] as? JsonPrimitive)?.content==adoption.source.id}) {"Viewer reference prevents source identity removal"}
        }
    }
    val imported=retained+adoption.target
    val categories=storedCategories.filterNot {row -> imported.any {it.id==row.id}}+imported
    var working=snapshot.copy(records=snapshot.records+mapOf(CloudEntity.TRANSACTION_CATEGORY to categories))
    val mutations=linkedMapOf<Pair<CloudEntity,String>,CategoryReferenceMutation>()
    val tasks=linkedMapOf<String,PendingCategoryTranslation>()
    val aliases=(if(removes) listOf(adoption.source.id) else emptyList())+retained.map {it.id}
    for(alias in aliases) {
        val changes=planCategoryReferenceRepairs(working,alias,adoption.target.id,deviceId,now,allowDeletedTarget=true)
        changes.mutations.forEach {change -> mutations[requireNotNull(CloudEntity.fromTable(change.record.entity)) to change.record.id]=change}
        changes.translations.forEach {tasks[it.categoryId]=it}
        val updatedRecords=working.records.mapValues { (entity,rows) -> rows.map {row -> mutations[entity to row.id]?.record ?: row} }
        val updatedPending=working.pending.filterNot {mutations.containsKey(it.mutation.entity to it.mutation.recordId)}+
            mutations.values.map {QueuedMutation(it.mutation,0,0,null)}
        val updatedTasks=working.translations.map {task -> tasks[task.translation.categoryId]?.let {QueuedCategoryTranslation(it,0,0,null)} ?: task}
        working=working.copy(records=updatedRecords,pending=updatedPending,translations=updatedTasks)
    }
    return SystemCategoryIdentityMigration(adoption,CategoryReferenceRepairs(mutations.values.toList(),tasks.values.toList()),removes,retained)
}
