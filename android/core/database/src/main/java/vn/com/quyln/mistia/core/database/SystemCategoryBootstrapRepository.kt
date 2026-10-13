package vn.com.quyln.mistia.core.database

import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import vn.com.quyln.mistia.core.model.*
import kotlinx.serialization.json.JsonPrimitive

/** Missing-default creation only. Never rewrites existing user metadata or references. */
internal class OfflineSystemCategoryBootstrapRepository(private val store:LocalStore):SystemCategoryBootstrapRepository {
    private val mutex=Mutex()
    override suspend fun ensureDefaultSystemCategories(owner:UserId,catalog:SystemCategoryCatalog,deviceId:String,now:String):Result<SystemCategoryBootstrapResult> = try {
        Result.success(mutex.withLock {
            val canonicalOwner=UserId(UUID.fromString(owner.value).toString())
            require(owner.value.equals(canonicalOwner.value,ignoreCase=true)) {"Invalid owner UUID shape"}
            val snapshot=store.recordsIncludingDeleted(canonicalOwner,CloudEntity.TRANSACTION_CATEGORY.table)
            val existing=snapshot.mapNotNull { row ->
                require(row.entity==CloudEntity.TRANSACTION_CATEGORY.table && row.ownerUserId==canonicalOwner.value)
                val payloadOwner=(row.payload["user_id"] as? JsonPrimitive)?.content ?: error("Missing category owner")
                if(UUID.fromString(payloadOwner).toString()!=canonicalOwner.value) return@mapNotNull null
                val decoded=TransactionCategoryRecord.fromCloudRecord(row)
                if(decoded.ownerUserId!=canonicalOwner.value) null else decoded.also {require(it.id==row.id)}
            }
            val byKey=existing.filter {it.systemKey!=null}.groupBy {it.systemKey!!}
            val byId=existing.associateBy {it.id}.toMutableMap()
            val preferred=byKey.mapValues { (key,rows) -> rows.maxWith(compareBy<TransactionCategoryRecord>(
                {it.deletedAt==null},{it.id==SystemCategoryIdentity.cloudId(key,canonicalOwner)},{it.syncVersion},{Instant.parse(it.updatedAt)},{it.id})) }.toMutableMap()
            val tombstones=byKey.filterValues {rows -> rows.all {it.deletedAt!=null}}.keys.toMutableSet()
            val created=mutableListOf<TransactionCategoryRecord>()
            val ordered=catalog.activeDefinitions.filter {it.parentKey==null}+catalog.activeDefinitions.filter {it.parentKey!=null}
            ordered.forEach { definition ->
                if(definition.key in preferred) return@forEach
                val parent=definition.parentKey?.let {preferred[it]}
                if(definition.parentKey!=null && (parent==null || parent.deletedAt!=null)) return@forEach
                if(parent!=null) require(parent.kind==definition.kind && parent.hierarchyRole==CategoryHierarchyRole.PARENT)
                val record=definition.seedRecord(canonicalOwner,parent?.id,deviceId,now)
                require(record.id !in byId && snapshot.none {it.id==record.id}) {"Default category identity is occupied by another record"}
                TransactionCategoryRecord.fromCloudRecord(record.toCloudRecord())
                created+=record;byId[record.id]=record;preferred[definition.key]=record
            }
            if(created.isNotEmpty()) store.commitMissingSystemCategories(created.map {it.toCloudRecord() to it.bootstrapMutation()})
            SystemCategoryBootstrapResult(created.size,byKey.filterValues {it.size>1}.keys.toSet(),tombstones.toSet())
        })
    } catch(cancelled:CancellationException) {throw cancelled}
      catch(error:Exception) {Result.failure(error)}
}
