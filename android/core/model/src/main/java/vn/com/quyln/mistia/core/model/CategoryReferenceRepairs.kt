package vn.com.quyln.mistia.core.model

import java.time.Instant
import java.util.UUID

/** Complete snapshots, including failed/future outbox and translation tasks. */
data class CategoryReferenceSnapshot(
    val owner: UserId,
    val records: Map<CloudEntity,List<CloudRecord>>,
    val pending: List<QueuedMutation>,
    val translations: List<QueuedCategoryTranslation>,
)
data class CategoryReferenceRepairs(
    val mutations: List<CategoryReferenceMutation>,
    val translations: List<PendingCategoryTranslation>,
)
val categoryReferenceEntities = setOf(CloudEntity.TRANSACTION_CATEGORY,CloudEntity.LEDGER_TRANSACTION,CloudEntity.BUDGET_PLAN,CloudEntity.RECURRING_BILL_PLAN)

fun CategoryReferenceSnapshot.requireUnchanged(current: CategoryReferenceSnapshot) {
    validate()
    current.validate()
    require(owner==current.owner && records.keys==current.records.keys)
    require(records.all { (entity, rows) -> rows.associateBy {it.id}==current.records.getValue(entity).associateBy {it.id} }) {"Category reference records changed"}
    require(pending.associateBy {it.mutation.entity to it.mutation.recordId}==current.pending.associateBy {it.mutation.entity to it.mutation.recordId}) {"Category reference outbox changed"}
    require(translations.associateBy {it.translation.categoryId}==current.translations.associateBy {it.translation.categoryId}) {"Category translation tasks changed"}
}
fun planCategoryReferenceRepairs(snapshot:CategoryReferenceSnapshot,oldId:String,newId:String,deviceId:String,now:String,allowDeletedTarget:Boolean=false):CategoryReferenceRepairs {
    snapshot.validate()
    UUID.fromString(oldId); UUID.fromString(newId); UUID.fromString(deviceId); Instant.parse(now)
    require(oldId!=newId)
    val categories=snapshot.records.getValue(CloudEntity.TRANSACTION_CATEGORY)
    val source=requireNotNull(categories.singleOrNull {it.id==oldId})
    val target=requireNotNull(categories.singleOrNull {it.id==newId})
    val sourceCategory=TransactionCategoryRecord.fromCloudRecord(source)
    val targetCategory=TransactionCategoryRecord.fromCloudRecord(target)
    require(sourceCategory.kind!=null && sourceCategory.kind==targetCategory.kind && sourceCategory.hierarchyRole==targetCategory.hierarchyRole)
    if(targetCategory.hierarchyRole==CategoryHierarchyRole.PARENT) {
        require(sourceCategory.parentCategoryId==null && targetCategory.parentCategoryId==null) {"Parent category cannot have a parent reference"}
    } else {
        listOf(sourceCategory,targetCategory).forEach {category ->
            require(category.parentCategoryId!=oldId && category.parentCategoryId!=newId)
            val parent=categories.singleOrNull {it.id==category.parentCategoryId}?.let(TransactionCategoryRecord::fromCloudRecord)
            require(parent!=null && parent.ownerUserId==snapshot.owner.value && parent.hierarchyRole==CategoryHierarchyRole.PARENT && parent.parentCategoryId==null && parent.kind==category.kind)
        }
    }
    val key=requireNotNull(sourceCategory.systemKey)
    selectSystemCategoryRemote(snapshot.owner,key,listOf(source,target)) // Validate both actual stored identities.
    require(target.deletedAt==null || allowDeletedTarget) {"Reference target must already be live"}
    val pending=snapshot.pending.associateBy {it.mutation.entity to it.mutation.recordId}
    val changes=snapshot.records.flatMap { (entity,rows) -> rows.mapNotNull {row ->
        val timestamp=if(entity==CloudEntity.TRANSACTION_CATEGORY && row.updatedAt!=null)
            maxOf(Instant.parse(now),Instant.parse(row.updatedAt).plusMillis(1)).toString() else now
        rewriteOwnedCategoryReference(snapshot.owner,row,pending[entity to row.id]?.mutation,oldId,newId,deviceId,timestamp)
    } }
    val changedCategories=changes.filter {it.record.entity==CloudEntity.TRANSACTION_CATEGORY.table}.associateBy {it.record.id}
    val tasks=snapshot.translations.mapNotNull {queued ->
        val task=queued.translation
        val change=changedCategories[task.categoryId] ?: return@mapNotNull null
        val original=categories.single {it.id==task.categoryId}
        if(task.savedUpdatedAt!=original.updatedAt) return@mapNotNull null
        task.copy(savedUpdatedAt=requireNotNull(change.record.updatedAt),deviceId=deviceId)
    }
    return CategoryReferenceRepairs(changes,tasks)
}

private fun CategoryReferenceSnapshot.validate() {
    require(records.keys==categoryReferenceEntities) {"Incomplete category reference snapshot"}
    records.forEach { (entity,rows) ->
        require(rows.all {it.entity==entity.table && it.ownerUserId==owner.value})
        require(rows.map {it.id}.distinct().size==rows.size)
    }
    require(pending.all {it.mutation.subjectUserId==owner.value && it.mutation.entity in categoryReferenceEntities})
    require(pending.map {it.mutation.entity to it.mutation.recordId}.distinct().size==pending.size)
    require(translations.all {it.translation.ownerUserId==owner.value})
    require(translations.map {it.translation.categoryId}.distinct().size==translations.size)
}
