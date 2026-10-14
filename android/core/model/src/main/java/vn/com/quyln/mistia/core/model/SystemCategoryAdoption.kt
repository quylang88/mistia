package vn.com.quyln.mistia.core.model

import java.time.Instant
import java.util.UUID
import kotlinx.serialization.json.*

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
