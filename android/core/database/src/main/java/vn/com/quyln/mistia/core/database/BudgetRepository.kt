package vn.com.quyln.mistia.core.database

import java.time.Instant
import java.time.ZoneId
import java.util.UUID
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import vn.com.quyln.mistia.core.model.*

/** Local mutations only; remote family enablement belongs to the cloud-first family flow. */
internal class OfflineBudgetRepository(private val store: LocalStore, private val currentZone: ()->ZoneId = {ZoneId.systemDefault()}) : BudgetRepository {
    constructor(store:LocalStore,zoneId:ZoneId):this(store,{zoneId})
    private val mutex = Mutex()

    override fun observeBudgets(ownerUserId: UserId): Flow<List<BudgetPlanRecord>> =
        store.observeOwnedFinanceRows(CloudEntity.BUDGET_PLAN, ownerUserId).map { rows ->
            rows.filter { it.ownerUserId == ownerUserId.value && it.deletedAt == null }
                .mapNotNull { runCatching { BudgetPlanRecord.fromCloudRecord(it) }.getOrNull() }
                .filterNot { it.ownerUserId != ownerUserId.value || it.isArchived || it.deletedAt != null }
                .sortedWith(compareByDescending(BudgetPlanRecord::monthAnchor).thenBy(BudgetPlanRecord::createdAt).thenBy(BudgetPlanRecord::id))
        }

    override fun observeBudgetCategories(ownerUserId: UserId): Flow<List<TransactionCategoryRecord>> =
        store.observeOwnedFinanceRows(CloudEntity.TRANSACTION_CATEGORY, ownerUserId).map { rows ->
            rows.mapNotNull { runCatching { TransactionCategoryRecord.fromCloudRecord(it) }.getOrNull() }
                .filter { it.ownerUserId == ownerUserId.value && it.deletedAt == null }
                .sortedWith(compareBy(TransactionCategoryRecord::sortOrder, TransactionCategoryRecord::createdAt, TransactionCategoryRecord::id))
        }

    override fun observeBudgetCategoryMetadata(ownerUserId: UserId): Flow<List<TransactionCategoryRecord>> =
        store.observe(CloudEntity.TRANSACTION_CATEGORY.table, ownerUserId).map { categoryMetadata(ownerUserId) }

    private suspend fun categoryMetadata(owner: UserId): List<TransactionCategoryRecord> =
        store.recordsIncludingDeleted(owner, CloudEntity.TRANSACTION_CATEGORY.table).mapNotNull { row ->
            if (!row.matchesFinanceReadScope(owner, CloudEntity.TRANSACTION_CATEGORY, includingDeleted = true)) return@mapNotNull null
            runCatching { TransactionCategoryRecord.fromCloudRecord(row) }.getOrNull()?.takeIf { it.ownerUserId == owner.value }
        }

    override suspend fun saveBudget(ownerUserId: UserId, draft: BudgetDraft, deviceId: String, now: String): Result<BudgetPlanRecord> =
        result { mutex.withLock {
            val zoneId=currentZone()
            require(draft.zoneId == zoneId) { "Budget draft must use the repository calendar zone" }
            val existing = draft.id?.let { find(ownerUserId, it) }
            if (draft.editingExisting && existing == null) fail(BudgetValidationError.NOT_FOUND)
            if (existing?.isArchived == true || existing?.deletedAt != null) fail(BudgetValidationError.NOT_FOUND)
            val month = budgetMonth(draft.monthAnchor, draft.zoneId)
            if (existing != null && month < budgetMonth(now, draft.zoneId)) fail(BudgetValidationError.PAST_READ_ONLY)
            val metadata = categoryMetadata(ownerUserId)
            val index = CategoryIdentityIndex(ownerUserId, metadata)
            fun allocation(plan: BudgetPlanRecord) = plan.logicalAllocation(index)
            val category = index.category(draft.categoryId)?.takeIf { it.deletedAt == null }
                ?: fail(BudgetValidationError.CATEGORY_REQUIRED)
            val parent = index.category(category.parentCategoryId)?.takeIf { it.deletedAt == null }
            if (category.kind != TransactionCategoryKind.EXPENSE || category.deletedAt != null ||
                category.isBalanceAdjustmentSystemCategory ||
                (category.isArchived && index.logical(existing?.categoryId) != category.canonicalSnapshotId) ||
                (category.hierarchyRole == CategoryHierarchyRole.CHILD &&
                    (parent == null || parent.kind != TransactionCategoryKind.EXPENSE || parent.hierarchyRole != CategoryHierarchyRole.PARENT))) {
                fail(BudgetValidationError.INVALID_CATEGORY)
            }
            val active = observeBudgets(ownerUserId).first()
            if (active.any { it.id != existing?.id && index.logical(it.categoryId) == category.canonicalSnapshotId && budgetMonth(it.monthAnchor, draft.zoneId) == month }) {
                fail(BudgetValidationError.DUPLICATE_CATEGORY)
            }
            val selectedBranchId = parent?.canonicalSnapshotId ?: category.canonicalSnapshotId
            val proposedCurrency = (existing?.currencyCode ?: draft.currencyCode).trim().uppercase(java.util.Locale.ROOT)
            if (budgetCurrencyConstraints(ownerUserId, active, month, draft.zoneId, metadata).any { it.id != existing?.id &&
                    allocation(it).branchCategoryId == selectedBranchId &&
                    it.currencyCode.trim().uppercase(java.util.Locale.ROOT) != proposedCurrency }) {
                fail(BudgetValidationError.BRANCH_CURRENCY_MISMATCH)
            }
            if (validateBudgetAllocation(category.canonicalSnapshotId, selectedBranchId,
                    category.hierarchyRole == CategoryHierarchyRole.PARENT, category.hierarchyRole == CategoryHierarchyRole.CHILD,
                    draft.limitMinor, draft.monthAnchor, active.map { allocation(it) }, existing?.id, draft.zoneId)
                != BudgetAllocationValidation.Valid) fail(BudgetValidationError.ALLOCATION_EXCEEDED)
            val carried = existing != null && budgetMonth(existing.monthAnchor, draft.zoneId) < month
            val edited = existing.takeUnless { carried }
            val family = existing?.includesFamilySpending == true || category.familyBudgetSpendingEnabled || parent?.familyBudgetSpendingEnabled == true
            val saved = (if (carried) draft.copy(id = null, currencyCode = existing!!.currencyCode) else draft)
                .toBudgetRecord(ownerUserId, category, parent, edited, family, deviceId, now)
            val records = mutableListOf(saved)
            val branchId = selectedBranchId
            if (family) {
                active.filter { it.id != saved.id && allocation(it).branchCategoryId == branchId &&
                    budgetMonth(it.monthAnchor, draft.zoneId) == month && !it.includesFamilySpending }
                    .forEach { sibling ->
                        val siblingCategory = index.category(sibling.categoryId)?.takeIf { it.deletedAt == null }
                        val refreshed = if (siblingCategory == null) {
                            sibling.copy(includesFamilySpending = true, updatedAt = now, lastModifiedByDeviceId = saved.lastModifiedByDeviceId)
                        } else {
                            val siblingParent = index.category(siblingCategory.parentCategoryId)?.takeIf { it.deletedAt == null }
                            BudgetDraft(categoryId = siblingCategory.id, monthAnchor = sibling.monthAnchor,
                                limitMinor = sibling.limitMinor, currencyCode = sibling.currencyCode, id = sibling.id,
                                rolloverEnabled = sibling.rolloverEnabled, zoneId = draft.zoneId)
                                .toBudgetRecord(ownerUserId, siblingCategory, siblingParent, sibling, true, deviceId, now)
                        }
                        records.add(refreshed)
                    }
            }
            if (parent != null && active.none { it.id != edited?.id && index.logical(it.categoryId) == parent.canonicalSnapshotId && budgetMonth(it.monthAnchor, draft.zoneId) == month }) {
                val children = active.filter { it.id != edited?.id && index.logical(it.categoryId) != parent.canonicalSnapshotId &&
                    allocation(it).branchCategoryId == parent.canonicalSnapshotId && budgetMonth(it.monthAnchor, draft.zoneId) == month } + saved
                if (children.size >= 2) {
                    val total = try { children.fold(0L) { sum, child -> Math.addExact(sum, child.limitMinor) } }
                        catch (_: ArithmeticException) { fail(BudgetValidationError.AMOUNT_OVERFLOW) }
                    records.add(draft.copy(id = null, categoryId = parent.id, limitMinor = total, rolloverEnabled = false, currencyCode = saved.currencyCode)
                        .toBudgetRecord(ownerUserId, parent, null, null, family, deviceId, now))
                }
            }
            val mutations = records.map { it.toCloudRecord() to it.pendingMutation() }.toMutableList()
            if (family) {
                val branch = parent ?: category
                val updated = branch.copy(familyBudgetSpendingEnabled = true, updatedAt = now, lastModifiedByDeviceId = saved.lastModifiedByDeviceId)
                mutations.add(categoryMutation(updated))
            }
            store.commitMutations(mutations)
            saved
        } }

    override suspend fun archiveBudget(ownerUserId: UserId, budgetId: RecordId, deviceId: String, now: String): Result<Unit> =
        result { mutex.withLock {
            val existing = requireBudget(ownerUserId, budgetId)
            val archived = existing.copy(isArchived = true, updatedAt = utc(now), lastModifiedByDeviceId = UUID.fromString(deviceId).toString())
            store.commitMutations(listOf(archived.toCloudRecord() to archived.pendingMutation()))
        } }

    override suspend fun deleteBudget(ownerUserId: UserId, budgetId: RecordId, deviceId: String, now: String): Result<Unit> =
        result { mutex.withLock {
            val existing = requireBudget(ownerUserId, budgetId)
            val deleted = existing.copy(deletedAt = utc(now), updatedAt = now, lastModifiedByDeviceId = UUID.fromString(deviceId).toString())
            val mutations = mutableListOf(deleted.toCloudRecord() to deleted.pendingMutation(MutationKind.DELETE))
            val zone = currentZone()
            val index = CategoryIdentityIndex(ownerUserId, categoryMetadata(ownerUserId))
            fun allocation(plan: BudgetPlanRecord) = plan.logicalAllocation(index)
            val branchId = allocation(existing).branchCategoryId
            if (budgetMonth(existing.monthAnchor, zone) == budgetMonth(now, zone) && branchId != null &&
                observeBudgets(ownerUserId).first().none { it.id != existing.id && allocation(it).branchCategoryId == branchId &&
                    budgetMonth(it.monthAnchor, zone) == budgetMonth(existing.monthAnchor, zone) }) {
                index.category(branchId)?.let { category ->
                    if (category.deletedAt == null) mutations.add(categoryMutation(category.copy(
                        familyBudgetSpendingEnabled = false, updatedAt = now, lastModifiedByDeviceId = deleted.lastModifiedByDeviceId)))
                }
            }
            store.commitMutations(mutations)
        } }

    private suspend fun find(owner: UserId, id: String): BudgetPlanRecord? =
        store.record(owner, CloudEntity.BUDGET_PLAN.table, UUID.fromString(id).toString())?.let {
            require(it.ownerUserId == owner.value)
            BudgetPlanRecord.fromCloudRecord(it).also { budget -> require(budget.ownerUserId == owner.value) }
        }

    private suspend fun requireBudget(owner: UserId, id: RecordId): BudgetPlanRecord =
        find(owner, id.value)?.takeIf { it.deletedAt == null && !it.isArchived } ?: fail(BudgetValidationError.NOT_FOUND)

    private fun categoryMutation(category: TransactionCategoryRecord): Pair<CloudRecord, PendingMutation> =
        category.toCloudRecord() to PendingMutation(CloudEntity.TRANSACTION_CATEGORY, category.id, category.ownerUserId,
            MutationKind.UPSERT, category.toPayload(), category.updatedAt, category.syncVersion, requireNotNull(category.lastModifiedByDeviceId))

    private fun fail(reason: BudgetValidationError): Nothing = throw BudgetValidationException(reason)
    private fun utc(value: String): String = value.also { require(Instant.parse(it).toString().endsWith("Z")) }
    private suspend fun <T> result(block: suspend () -> T): Result<T> = try { Result.success(block()) }
        catch (cancelled: CancellationException) { throw cancelled }
        catch (error: Exception) { Result.failure(error) }
}
