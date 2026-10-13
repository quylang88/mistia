package vn.com.quyln.mistia.core.model

import java.time.Instant

/** Owned system categories share Swift's canonical identity, while wire FKs stay intact. */
class CategoryIdentityIndex(owner: UserId, categories: List<TransactionCategoryRecord>) {
    private val owned = categories.filter { it.ownerUserId == owner.value }
    private val actual = owned.associateBy { it.id }
    private val aliases = buildMap {
        owned.filter { it.isSystem && it.systemKey != null }.sortedWith(
            compareBy<TransactionCategoryRecord>({ it.deletedAt == null }, { !it.isArchived },
                { it.syncVersion }, { Instant.parse(it.updatedAt) }, { it.id })
        ).forEach { category ->
            put(category.canonicalSnapshotId, category)
            put(SystemCategoryIdentity.cloudId(requireNotNull(category.systemKey), owner), category)
        }
    }

    fun category(id: String?): TransactionCategoryRecord? = actual[id] ?: aliases[id]
    fun logical(id: String?): String? = category(id)?.canonicalSnapshotId ?: id
}

val TransactionCategoryRecord.canonicalSnapshotId: String
    get() = if (isSystem && systemKey != null) SystemCategoryIdentity.canonicalId(systemKey) else id

fun BudgetPlanRecord.logicalAllocation(index: CategoryIdentityIndex): BudgetAllocationSnapshot =
    allocationSnapshot(index.category(categoryId)).let { snapshot ->
        snapshot.copy(categoryId = index.logical(snapshot.categoryId), branchCategoryId = index.logical(snapshot.branchCategoryId))
    }
