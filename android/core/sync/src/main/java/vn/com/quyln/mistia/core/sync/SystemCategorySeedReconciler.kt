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
        if(catalog==null || !category.isSystem || category.systemKey==null || queued.mutation.baseVersion!=0L ||
            local.syncVersion!=0L || queued.mutation.kind!=MutationKind.UPSERT || local.deletedAt!=null) return MutationPreflight.Continue
        val key=requireNotNull(category.systemKey)
        selectSystemCategoryRemote(owner,key,listOf(local))
        val snapshot=localStore.categoryReferenceSnapshot(owner)
        if(snapshot.pending.singleOrNull {it.mutation.entity==CloudEntity.TRANSACTION_CATEGORY && it.mutation.recordId==local.id}!=queued ||
            snapshot.records.getValue(CloudEntity.TRANSACTION_CATEGORY).singleOrNull {it.id==local.id}!=local) return MutationPreflight.Stale
        var offset=0
        val records=mutableListOf<CloudRecord>()
        while(true) {
            val page=remoteStore.fetchSystemCategoryPage(key,token,owner,offset,200)
            records+=page.records
            val next=page.nextOffset ?: break
            require(page.records.isNotEmpty() && next>offset && next==Math.addExact(offset,page.records.size)) {"Invalid category key pagination"}
            offset=next
        }
        selectSystemCategoryRemote(owner,key,records)
        if(records.size>1) return MutationPreflight.Conflict("system_category_duplicates_require_reconciliation")
        if(records.isEmpty()) {
            if(parentID!=null) {
                val parent=requireNotNull(snapshot.records.getValue(CloudEntity.TRANSACTION_CATEGORY).singleOrNull {it.id==parentID})
                require((parent.payload["user_id"] as? JsonPrimitive)?.content==owner.value)
                if(parent.deletedAt!=null) return MutationPreflight.Conflict("system_category_parent_deleted")
            }
            return MutationPreflight.Continue
        }
        val applied=localStore.commitSystemCategoryIdentityMigration(snapshot,queued,records,catalog,queued.mutation.deviceId,
            Instant.ofEpochMilli(nowEpochMillis()).toString())
        return if(applied) MutationPreflight.Reconciled else MutationPreflight.Stale
    }
}
