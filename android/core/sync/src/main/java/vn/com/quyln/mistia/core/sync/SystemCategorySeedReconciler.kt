package vn.com.quyln.mistia.core.sync

import java.time.Instant
import vn.com.quyln.mistia.core.model.*
import kotlinx.serialization.json.JsonPrimitive

/** Lookup completes before any create; a 409 invokes the same guarded path again. */
internal class SystemCategorySeedReconciler(
    private val localStore:LocalStore,
    private val remoteStore:RemoteMutationStore,
    private val catalog:SystemCategoryCatalog?,
    private val nowEpochMillis:()->Long,
) {
    suspend fun prepare(queued:QueuedMutation,local:CloudRecord,owner:UserId,token:String):MutationPreflight {
        val category=TransactionCategoryRecord.fromCloudRecord(local)
        require(local.entity==CloudEntity.TRANSACTION_CATEGORY.table && local.ownerUserId==owner.value &&
            category.id==local.id && category.ownerUserId==owner.value)
        val parentID=category.parentCategoryId
        require(parentID!=local.id) {"Category cannot parent itself"}
        if(parentID!=null && parentID in localStore.pendingMutationRecordIds(owner,CloudEntity.TRANSACTION_CATEGORY.table))
            return MutationPreflight.Deferred
        if(catalog==null || !category.isSystem || category.systemKey==null ||
            queued.mutation.kind!=MutationKind.UPSERT || local.deletedAt!=null) return MutationPreflight.Continue
        val seed=!queued.remoteIdentityObserved && queued.mutation.baseVersion==0L && local.syncVersion==0L
        val key=requireNotNull(category.systemKey)
        selectSystemCategoryRemote(owner,key,listOf(local))
        val snapshot=localStore.categoryReferenceSnapshot(owner)
        if(snapshot.pending.singleOrNull {it.mutation.entity==CloudEntity.TRANSACTION_CATEGORY && it.mutation.recordId==local.id}!=queued ||
            snapshot.records.getValue(CloudEntity.TRANSACTION_CATEGORY).singleOrNull {it.id==local.id}!=local) return MutationPreflight.Stale
        val categories=snapshot.records.getValue(CloudEntity.TRANSACTION_CATEGORY)
        if(!seed && snapshot.pending.any {pending ->
            pending.mutation.entity==CloudEntity.TRANSACTION_CATEGORY && pending.mutation.recordId!=local.id &&
                categories.any {row -> row.id==pending.mutation.recordId && row.deletedAt!=null &&
                    (row.payload["user_id"] as? JsonPrimitive)?.content==owner.value &&
                    (row.payload["system_key"] as? JsonPrimitive)?.content==key && row.payload["is_system"]==JsonPrimitive(true)}
        }) return MutationPreflight.Deferred
        var offset=0
        val records=mutableListOf<CloudRecord>()
        while(true) {
            val page=remoteStore.fetchSystemCategoryPage(key,token,owner,offset,200)
            records+=page.records
            val next=page.nextOffset ?: break
            require(page.records.isNotEmpty() && next>offset && next==Math.addExact(offset,page.records.size)) {"Invalid category key pagination"}
            offset=next
        }
        val selection=selectSystemCategoryRemote(owner,key,records)
        try {snapshot.requireUnchanged(localStore.categoryReferenceSnapshot(owner))} catch (_:IllegalArgumentException) {return MutationPreflight.Stale}
        if(!seed) return if(records.any {it.id!=local.id && it.deletedAt==null})
            MutationPreflight.Conflict("system_category_active_identity_conflict") else MutationPreflight.Continue
        if(records.count {it.deletedAt==null}>1)
            return MutationPreflight.Conflict("system_category_duplicates_require_reconciliation")
        if(selection!=null) {
            val aliases=records.filter {it.id!=local.id}.map {it.id}.toSet()
            if(snapshot.pending.any {it.mutation.entity==CloudEntity.TRANSACTION_CATEGORY && it.mutation.recordId in aliases} ||
                snapshot.translations.any {it.translation.categoryId in aliases}) return MutationPreflight.Deferred
        }
        if(records.isEmpty()) {
            if(parentID!=null) {
                val parent=requireNotNull(snapshot.records.getValue(CloudEntity.TRANSACTION_CATEGORY).singleOrNull {it.id==parentID})
                require((parent.payload["user_id"] as? JsonPrimitive)?.content==owner.value)
                if(parent.deletedAt!=null) return MutationPreflight.Conflict("system_category_parent_deleted")
            }
            return MutationPreflight.Continue
        }
        val applied=try {
            localStore.commitSystemCategoryIdentityMigration(snapshot,queued,records,catalog,queued.mutation.deviceId,
                Instant.ofEpochMilli(nowEpochMillis()).toString())
        } catch (_:CategoryParentReconciliationRequired) {return MutationPreflight.Deferred}
        return if(applied) MutationPreflight.Reconciled else MutationPreflight.Stale
    }
}
