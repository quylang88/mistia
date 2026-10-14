package vn.com.quyln.mistia.core.sync

import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.serialization.json.*
import vn.com.quyln.mistia.core.model.*

data class CategoryMaintenanceSummary(val processedGroups:Int=0,val deferredGroups:Int=0,val staleGroups:Int=0)

/** Local repairs from a completed raw pull; no HTTP writes or synthetic remote rows. */
class CategoryMaintenanceCoordinator(private val localStore:LocalStore,private val catalog:SystemCategoryCatalog,
    private val deviceIdProvider:()->String,private val nowEpochMillis:()->Long=System::currentTimeMillis) {
    suspend fun reconcileObserved(owner:UserId,remoteCategories:List<CloudRecord>):CategoryMaintenanceSummary {
        UUID.fromString(owner.value)
        val definitions=catalog.definitions.associateBy {it.key}
        val groups=remoteCategories.filter {row ->
            require(row.ownerUserId==owner.value && row.entity==CloudEntity.TRANSACTION_CATEGORY.table)
            val payloadOwner=requireNotNull((row.payload["user_id"] as? JsonPrimitive)?.contentOrNull)
            UUID.fromString(payloadOwner)
            payloadOwner==owner.value && row.payload["is_system"]==JsonPrimitive(true)
        }.groupBy {row -> (row.payload["system_key"] as? JsonPrimitive)?.contentOrNull}
            .filterKeys {it!=null && it in definitions}
        val keys=groups.keys.filterNotNull().sortedWith(compareBy({if(definitions.getValue(it).parentKey==null) 0 else 1},
            {definitions.getValue(it).sortOrder ?: Int.MAX_VALUE},{it}))
        var processed=0;var deferred=0;var stale=0
        for(key in keys) {
            currentCoroutineContext().ensureActive()
            val rows=groups.getValue(key)
            selectSystemCategoryRemote(owner,key,rows)
            val snapshot=localStore.categoryReferenceSnapshot(owner)
            val categories=snapshot.records.getValue(CloudEntity.TRANSACTION_CATEGORY)
            val seed=snapshot.pending.singleOrNull {queued ->
                val mutation=queued.mutation
                !queued.remoteIdentityObserved && mutation.entity==CloudEntity.TRANSACTION_CATEGORY &&
                    mutation.recordId==SystemCategoryIdentity.cloudId(key,owner) && mutation.baseVersion==0L && mutation.kind==MutationKind.UPSERT &&
                    categories.any {it.id==mutation.recordId && it.syncVersion==0L && it.deletedAt==null && it.payload["system_key"]==JsonPrimitive(key) && it.payload["is_system"]==JsonPrimitive(true)}
            }
            if(seed!=null) {
                val ids=(rows+categories.filter {it.payload["system_key"]==JsonPrimitive(key) && it.payload["is_system"]==JsonPrimitive(true)}).map {it.id}.toSet()
                if(snapshot.pending.any {it!=seed && it.mutation.entity==CloudEntity.TRANSACTION_CATEGORY && it.mutation.recordId in ids} ||
                    snapshot.translations.any {it.translation.categoryId in ids && it.translation.categoryId!=seed.mutation.recordId}) {
                    deferred++;continue
                }
            }
            val applied=try {
                val device=deviceIdProvider()
                val now=Instant.ofEpochMilli(nowEpochMillis()).toString()
                if(seed!=null) localStore.commitSystemCategoryIdentityMigration(snapshot,seed,rows,catalog,device,now)
                else localStore.commitObservedSystemCategoryMaintenance(snapshot,key,rows,catalog,device,now)
            } catch (_:CategoryGroupEditsPending) {deferred++;continue}
              catch (_:CategoryParentReconciliationRequired) {deferred++;continue}
            if(applied) processed++ else stale++
        }
        return CategoryMaintenanceSummary(processed,deferred,stale)
    }
}
