package vn.com.quyln.mistia.core.database

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import vn.com.quyln.mistia.core.model.CloudEntity
import vn.com.quyln.mistia.core.model.CloudRecord
import vn.com.quyln.mistia.core.model.EntityCount
import vn.com.quyln.mistia.core.model.LedgerWalletRecord
import vn.com.quyln.mistia.core.model.LocalStore
import vn.com.quyln.mistia.core.model.PendingMutation
import vn.com.quyln.mistia.core.model.RecordId
import vn.com.quyln.mistia.core.model.QueuedMutation
import vn.com.quyln.mistia.core.model.UserId
import vn.com.quyln.mistia.core.model.*
import org.junit.Assert.assertFalse
import java.time.ZoneId
import kotlinx.serialization.json.JsonNull
import vn.com.quyln.mistia.core.model.WalletDraft
import vn.com.quyln.mistia.core.model.WalletKind

class BudgetRepositoryTest {
    private val owner = UserId(OWNER)
    private val store = BudgetMemoryStore()
    private val zone = ZoneId.of("Asia/Tokyo")
    private val repo = OfflineFirstFinanceRepository(store, zone)

    @Test fun `default budget save accepts the device zone changed after repository construction`()=runTest {
        seedCategories();val original=java.util.TimeZone.getDefault()
        try {
            java.util.TimeZone.setDefault(java.util.TimeZone.getTimeZone("UTC"))
            val live=OfflineFirstFinanceRepository(store)
            java.util.TimeZone.setDefault(java.util.TimeZone.getTimeZone(zone))
            assertEquals("2026-09-30T15:00:00Z",live.saveBudget(owner,draft(),DEVICE,NOW).getOrThrow().monthAnchor)
        } finally {java.util.TimeZone.setDefault(original)}
    }
    @Test fun `create snapshots category and writes owner scoped budget outbox`() = runTest {
        seedCategories()
        val result = repo.saveBudget(owner, draft(), DEVICE, NOW).getOrThrow()
        assertEquals("Living / Food", result.categoryPathSnapshot)
        assertEquals("生活 / 食費", result.categoryPathJapaneseSnapshot)
        assertEquals(PARENT, result.categoryParentIdSnapshot)
        assertEquals("2026-09-30T15:00:00Z", result.monthAnchor)
        assertEquals(result.id, store.outboxRows(OWNER).filter { it.entity == CloudEntity.BUDGET_PLAN }.single().recordId)
        assertTrue(repo.observeBudgets(UserId(OTHER)).first().isEmpty())
    }

    @Test fun `edit preserves currency created date remote version and coalesces outbox`() = runTest {
        seedCategories()
        val saved = repo.saveBudget(owner, draft(), DEVICE, NOW).getOrThrow().copy(syncVersion = 9007199254740993L)
        store.commitMutation(saved.toCloudRecord(), pending(saved))
        repo.saveBudget(owner, draft().copy(limitMinor = 600, currencyCode = "VND"), DEVICE, LATER).getOrThrow()
        val result = repo.saveBudget(owner, draft().copy(limitMinor = 700), DEVICE, LATER).getOrThrow()
        assertEquals("JPY", result.currencyCode)
        assertEquals(saved.createdAt, result.createdAt)
        assertEquals(9007199254740993L, store.outboxRows(OWNER).single { it.entity == CloudEntity.BUDGET_PLAN }.baseVersion)
        assertEquals(700, result.limitMinor)
    }

    @Test fun `duplicate invalid amount foreign dependency and parent cap leave no mutation`() = runTest {
        seedCategories()
        repo.saveBudget(owner, draft(), DEVICE, NOW).getOrThrow()
        assertTrue(repo.saveBudget(owner, draft().copy(id = NEW_ID), DEVICE, NOW).isFailure)
        assertTrue(repo.saveBudget(owner, draft().copy(limitMinor = 0), DEVICE, NOW).isFailure)
        assertTrue(repo.saveBudget(UserId(OTHER), draft(), DEVICE, NOW).isFailure)
        repo.saveBudget(owner, draft().copy(id = PARENT_BUDGET, categoryId = PARENT, limitMinor = 500), DEVICE, NOW).getOrThrow()
        assertTrue(repo.saveBudget(owner, draft().copy(limitMinor = 501), DEVICE, NOW).isFailure)
        assertEquals(2, repo.observeBudgets(owner).first().size)
    }

    @Test fun `past edit is read only archive upserts and current delete creates tombstone`() = runTest {
        seedCategories()
        val old = repo.saveBudget(owner, draft().copy(monthAnchor = "2026-09-10T00:00:00Z"), DEVICE, NOW).getOrThrow()
        assertTrue(repo.saveBudget(owner, draft().copy(monthAnchor = old.monthAnchor), DEVICE, NOW).isFailure)
        repo.archiveBudget(owner, RecordId(old.id), DEVICE, NOW).getOrThrow()
        assertTrue(repo.observeBudgets(owner).first().isEmpty())
        assertEquals(MutationKind.UPSERT, store.outboxRows(OWNER).single { it.entity == CloudEntity.BUDGET_PLAN }.kind)
        val current = repo.saveBudget(owner, draft().copy(id = NEW_ID), DEVICE, NOW).getOrThrow()
        repo.deleteBudget(owner, RecordId(current.id), DEVICE, LATER).getOrThrow()
        assertTrue(repo.observeBudgets(owner).first().isEmpty())
        assertEquals(LATER, store.record(owner, CloudEntity.BUDGET_PLAN.table, current.id)!!.deletedAt)
        assertEquals(MutationKind.DELETE, store.outboxRows(OWNER).single { it.recordId == current.id }.kind)
        assertTrue(repo.deleteBudget(UserId(OTHER), RecordId(current.id), DEVICE, LATER).isFailure)
    }

    @Test fun `carried forward edit creates new record without rewriting old month`() = runTest {
        seedCategories()
        val old = repo.saveBudget(owner, draft(), DEVICE, NOW).getOrThrow()
        val carried = repo.saveBudget(owner, draft().copy(monthAnchor = "2026-11-15T00:00:00Z", limitMinor = 800), DEVICE, NOW).getOrThrow()
        assertFalse(old.id == carried.id)
        assertEquals(0, carried.syncVersion)
        assertEquals(old, BudgetPlanRecord.fromCloudRecord(store.record(owner, CloudEntity.BUDGET_PLAN.table, old.id)!!))
    }

    @Test fun `second child auto creates parent in one atomic batch and overflow fails safely`() = runTest {
        seedCategories()
        repo.saveBudget(owner, draft(), DEVICE, NOW).getOrThrow()
        repo.saveBudget(owner, draft().copy(id = NEW_ID, categoryId = CHILD2, limitMinor = 600), DEVICE, NOW).getOrThrow()
        val parent = repo.observeBudgets(owner).first().single { it.categoryId == PARENT }
        assertEquals(1100, parent.limitMinor)
        assertFalse(parent.rolloverEnabled)
        assertEquals(2, store.batches.last().size)
        val fresh = BudgetMemoryStore()
        val r = OfflineFirstFinanceRepository(fresh, zone)
        seedCategories(fresh)
        r.saveBudget(owner, draft().copy(limitMinor = Long.MAX_VALUE), DEVICE, NOW).getOrThrow()
        assertTrue(r.saveBudget(owner, draft().copy(id = NEW_ID, categoryId = CHILD2, limitMinor = 1), DEVICE, NOW).isFailure)
        assertEquals(1, r.observeBudgets(owner).first().size)
    }

    @Test fun `failed batch leaves both budgets and outbox unchanged`() = runTest {
        seedCategories()
        repo.saveBudget(owner, draft(), DEVICE, NOW).getOrThrow()
        store.failBatch = true
        assertTrue(repo.saveBudget(owner, draft().copy(id = NEW_ID, categoryId = CHILD2), DEVICE, NOW).isFailure)
        assertEquals(1, repo.observeBudgets(owner).first().size)
        assertEquals(1, store.outboxRows(OWNER).count { it.entity == CloudEntity.BUDGET_PLAN })
    }

    @Test fun `family scope is inherited and final current delete clears category scope atomically`() = runTest {
        seedCategories()
        val parentCloud = store.record(owner, CloudEntity.TRANSACTION_CATEGORY.table, PARENT)!!
        val parent = TransactionCategoryRecord.fromCloudRecord(parentCloud).copy(familyBudgetSpendingEnabled = true)
        store.replacePullSnapshot(owner, CloudEntity.TRANSACTION_CATEGORY.table,
            repo.observeCategories(owner).first().filter { it.id != PARENT }.map { it.toCloudRecord() } + parent.toCloudRecord())
        val saved = repo.saveBudget(owner, draft(), DEVICE, NOW).getOrThrow()
        assertTrue(saved.includesFamilySpending)
        repo.deleteBudget(owner, RecordId(saved.id), DEVICE, LATER).getOrThrow()
        assertFalse(repo.observeCategories(owner).first().single { it.id == PARENT }.familyBudgetSpendingEnabled)
        assertEquals(2, store.batches.last().size)
    }

    @Test fun `switching from child to parent clears stale optional snapshots`() = runTest {
        seedCategories()
        repo.saveBudget(owner, draft(), DEVICE, NOW).getOrThrow()
        val saved = repo.saveBudget(owner, draft().copy(categoryId = PARENT), DEVICE, LATER).getOrThrow()
        assertEquals(null, saved.categoryParentIdSnapshot)
        assertEquals(null, saved.categoryParentNameSnapshot)
        assertEquals(JsonNull, saved.toPayload()["category_parent_id_snapshot"])
        assertEquals("Living", saved.categoryPathSnapshot)
    }

    @Test fun `editing parent into second child recreates parent from effective children`() = runTest {
        seedCategories()
        val parent = repo.saveBudget(owner, draft().copy(id = PARENT_BUDGET, categoryId = PARENT, limitMinor = 2000), DEVICE, NOW).getOrThrow()
        repo.saveBudget(owner, draft(), DEVICE, NOW).getOrThrow()
        repo.saveBudget(owner, draft().copy(id = parent.id, categoryId = CHILD2, limitMinor = 600), DEVICE, LATER).getOrThrow()
        val budgets = repo.observeBudgets(owner).first()
        assertEquals(3, budgets.size)
        assertEquals(1100, budgets.single { it.categoryId == PARENT }.limitMinor)
    }

    @Test fun `viewer envelope cannot expose or mutate foreign payload owner budgets or categories`() = runTest {
        seedCategories()
        val saved = repo.saveBudget(owner, draft(), DEVICE, NOW).getOrThrow()
        val foreign = saved.copy(id = NEW_ID, ownerUserId = OTHER, limitMinor = Long.MAX_VALUE).toCloudRecord().copy(ownerUserId = OWNER)
        store.replacePullSnapshot(owner, CloudEntity.BUDGET_PLAN.table, listOf(saved.toCloudRecord(), foreign))
        assertEquals(listOf(saved.id), repo.observeBudgets(owner).first().map { it.id })
        val category = repo.observeCategories(owner).first().single { it.id == CHILD2 }
        val foreignCategory = category.copy(ownerUserId = OTHER).toCloudRecord().copy(ownerUserId = OWNER)
        val rows = repo.observeCategories(owner).first().filter { it.id != CHILD2 }.map { it.toCloudRecord() } + foreignCategory
        store.replacePullSnapshot(owner, CloudEntity.TRANSACTION_CATEGORY.table, rows)
        assertTrue(repo.saveBudget(owner, draft().copy(id = PARENT_BUDGET, categoryId = CHILD2), DEVICE, NOW).isFailure)
        assertEquals(1, store.outboxRows(OWNER).count { it.entity == CloudEntity.BUDGET_PLAN })
    }

    @Test fun `promoting sibling family scope refreshes only selected month category snapshots`() = runTest {
        seedCategories()
        repo.saveBudget(owner, draft(), DEVICE, NOW).getOrThrow()
        val categories = repo.observeCategories(owner).first().map { cat ->
            when (cat.id) {
                PARENT -> cat.copy(familyBudgetSpendingEnabled = true)
                CHILD -> cat.copy(name = "Dining")
                else -> cat
            }.toCloudRecord()
        }
        store.replacePullSnapshot(owner, CloudEntity.TRANSACTION_CATEGORY.table, categories)
        repo.saveBudget(owner, draft().copy(id = NEW_ID, categoryId = CHILD2), DEVICE, NOW).getOrThrow()
        val sibling = repo.observeBudgets(owner).first().single { it.id == BUDGET }
        assertTrue(sibling.includesFamilySpending)
        assertEquals("Living / Dining", sibling.categoryPathSnapshot)
    }

    @Test fun `explicit edit intent rejects missing or foreign budget id even with owned category`() = runTest {
        seedCategories()
        assertTrue(repo.saveBudget(owner, draft().copy(id = NEW_ID, editingExisting = true), DEVICE, NOW).isFailure)
        assertTrue(repo.observeBudgets(owner).first().isEmpty())
        assertTrue(store.outboxRows(OWNER).none { it.entity == CloudEntity.BUDGET_PLAN })
    }

    @Test fun `enabled child category family scope is inherited even if parent is disabled`() = runTest {
        seedCategories()
        val rows = repo.observeCategories(owner).first().map {
            (if (it.id == CHILD) it.copy(familyBudgetSpendingEnabled = true) else it).toCloudRecord()
        }
        store.replacePullSnapshot(owner, CloudEntity.TRANSACTION_CATEGORY.table, rows)
        val saved = repo.saveBudget(owner, draft(), DEVICE, NOW).getOrThrow()
        assertTrue(saved.includesFamilySpending)
        assertTrue(repo.observeCategories(owner).first().single { it.id == PARENT }.familyBudgetSpendingEnabled)
    }

    @Test fun `legacy category hierarchy snapshots still enforce child allocation cap`() = runTest {
        seedCategories()
        repo.saveBudget(owner,draft().copy(id=PARENT_BUDGET,categoryId=PARENT,limitMinor=1000),DEVICE,NOW).getOrThrow()
        val child=repo.saveBudget(owner,draft(),DEVICE,NOW).getOrThrow().copy(categoryParentIdSnapshot=null,
            categoryIsParentSnapshot=null,categoryHierarchyRoleSnapshotWireValue=null)
        store.replacePullSnapshot(owner,CloudEntity.BUDGET_PLAN.table,repo.observeBudgets(owner).first()
            .filter { it.id!=child.id }.map { it.toCloudRecord() }+child.toCloudRecord())
        assertTrue(repo.saveBudget(owner,draft().copy(id=NEW_ID,categoryId=CHILD2,limitMinor=501),DEVICE,NOW).isFailure)
    }

    @Test fun `mixed currencies in the same branch month are rejected without automatic parent or mutation`() = runTest {
        seedCategories()
        repo.saveBudget(owner,draft().copy(currencyCode="VND",limitMinor=1000000),DEVICE,NOW).getOrThrow()
        val failure=repo.saveBudget(owner,draft().copy(id=NEW_ID,categoryId=CHILD2,currencyCode="JPY",limitMinor=1000),DEVICE,NOW).exceptionOrNull()
        assertTrue(failure is BudgetValidationException)
        assertEquals(BudgetValidationError.BRANCH_CURRENCY_MISMATCH,(failure as BudgetValidationException).reason)
        assertEquals(1,repo.observeBudgets(owner).first().size)
        assertEquals(1,store.outboxRows(OWNER).count { it.entity==CloudEntity.BUDGET_PLAN })
        assertTrue(repo.saveBudget(owner,draft().copy(id=NEW_ID,categoryId=CHILD2,currencyCode="VND",limitMinor=1000),DEVICE,NOW).isSuccess)
        assertEquals(1001000,repo.observeBudgets(owner).first().single { it.categoryId==PARENT }.limitMinor)
    }

    @Test fun `carried forward branch currency also constrains new budgets in its displayed month`() = runTest {
        seedCategories()
        repo.saveBudget(owner,draft().copy(currencyCode="VND",monthAnchor="2026-09-01T00:00:00Z"),DEVICE,NOW).getOrThrow()
        val failure=repo.saveBudget(owner,draft().copy(id=NEW_ID,categoryId=CHILD2,currencyCode="JPY"),DEVICE,NOW).exceptionOrNull()
        assertTrue(failure is BudgetValidationException)
        assertEquals(BudgetValidationError.BRANCH_CURRENCY_MISMATCH,(failure as BudgetValidationException).reason)
        assertEquals(1,repo.observeBudgets(owner).first().size)
    }

    @Test fun `future branch currency constrains a new earlier carried budget`() = runTest {
        seedCategories()
        repo.saveBudget(owner,draft().copy(currencyCode="VND",monthAnchor="2026-11-01T00:00:00Z"),DEVICE,NOW).getOrThrow()
        val failure=repo.saveBudget(owner,draft().copy(id=NEW_ID,categoryId=CHILD2,currencyCode="JPY"),DEVICE,NOW).exceptionOrNull()
        assertTrue(failure is BudgetValidationException)
        assertEquals(BudgetValidationError.BRANCH_CURRENCY_MISMATCH,(failure as BudgetValidationException).reason)
        assertEquals(1,repo.observeBudgets(owner).first().size)
    }

    private suspend fun seedSystemCategories() {
        seedCategories()
        repo.observeCategories(owner).first().forEach { category ->
            val system=category.copy(isSystem=true,systemKey=when(category.id) {PARENT -> "parent_expense_housing";CHILD -> "rent";else -> "internet"})
            store.commitMutation(system.toCloudRecord(),system.bootstrapMutation())
        }
    }
    @Test fun `imported canonical branch snapshot still rejects another currency`()=runTest {
        seedSystemCategories()
        val saved=repo.saveBudget(owner,draft(),DEVICE,NOW).getOrThrow().copy(categoryIdSnapshot=SystemCategoryIdentity.canonicalId("rent"),categoryParentIdSnapshot=SystemCategoryIdentity.canonicalId("parent_expense_housing"))
        store.commitMutation(saved.toCloudRecord(),pending(saved))
        val error=repo.saveBudget(owner,draft().copy(id=NEW_ID,categoryId=CHILD2,currencyCode="VND"),DEVICE,NOW).exceptionOrNull()
        assertTrue(error is BudgetValidationException)
        assertEquals(BudgetValidationError.BRANCH_CURRENCY_MISMATCH,(error as BudgetValidationException).reason)
        assertEquals(1,repo.observeBudgets(owner).first().size)
    }
    @Test fun `imported canonical parent snapshot still enforces child cap`()=runTest {
        seedSystemCategories()
        val saved=repo.saveBudget(owner,draft().copy(id=PARENT_BUDGET,categoryId=PARENT,limitMinor=100),DEVICE,NOW).getOrThrow()
            .copy(categoryIdSnapshot=SystemCategoryIdentity.canonicalId("parent_expense_housing"))
        store.commitMutation(saved.toCloudRecord(),pending(saved))
        val error=repo.saveBudget(owner,draft().copy(limitMinor=101),DEVICE,NOW).exceptionOrNull()
        assertTrue(error is BudgetValidationException)
        assertEquals(BudgetValidationError.ALLOCATION_EXCEEDED,(error as BudgetValidationException).reason)
    }
    @Test fun `last canonical snapshot budget disables actual wire parent family flag`()=runTest {
        seedSystemCategories()
        val parent=repo.observeCategories(owner).first().single {it.id==PARENT}.copy(familyBudgetSpendingEnabled=true)
        store.commitMutation(parent.toCloudRecord(),parent.bootstrapMutation())
        val saved=repo.saveBudget(owner,draft(),DEVICE,NOW).getOrThrow().copy(categoryIdSnapshot=SystemCategoryIdentity.canonicalId("rent"),categoryParentIdSnapshot=SystemCategoryIdentity.canonicalId("parent_expense_housing"))
        store.commitMutation(saved.toCloudRecord(),pending(saved))
        repo.deleteBudget(owner,RecordId(saved.id),DEVICE,NOW).getOrThrow()
        assertFalse(repo.observeCategories(owner).first().single {it.id==PARENT}.familyBudgetSpendingEnabled)
    }
    @Test fun `new system budget snapshots canonical identity while live FK remains actual record id`()=runTest {
        seedSystemCategories()
        val saved=repo.saveBudget(owner,draft(),DEVICE,NOW).getOrThrow()
        assertEquals(CHILD,saved.categoryId)
        assertEquals(SystemCategoryIdentity.canonicalId("rent"),saved.categoryIdSnapshot)
        assertEquals(SystemCategoryIdentity.canonicalId("parent_expense_housing"),saved.categoryParentIdSnapshot)
    }

    @Test fun `tombstone metadata survives for currency checks but never enters picker or mutation`()=runTest {
        seedSystemCategories()
        val saved=repo.saveBudget(owner,draft(),DEVICE,NOW).getOrThrow()
        val child=repo.observeCategories(owner).first().single {it.id==CHILD}.copy(deletedAt=NOW)
        store.commitMutation(child.toCloudRecord(),child.bootstrapMutation().copy(kind=MutationKind.DELETE))
        assertFalse(repo.observeBudgetCategories(owner).first().any {it.id==CHILD})
        assertTrue(repo.observeBudgetCategoryMetadata(owner).first().any {it.id==CHILD && it.deletedAt==NOW})
        val raw=saved.copy(categoryIdSnapshot=CHILD,categoryParentIdSnapshot=PARENT)
        store.commitMutation(raw.toCloudRecord(),pending(raw))
        val error=repo.saveBudget(owner,draft().copy(id=NEW_ID,categoryId=CHILD2,currencyCode="VND"),DEVICE,NOW).exceptionOrNull()
        assertEquals(BudgetValidationError.BRANCH_CURRENCY_MISMATCH,(error as BudgetValidationException).reason)
        assertTrue(repo.saveBudget(owner,draft(),DEVICE,NOW).isFailure)
        assertEquals(child,TransactionCategoryRecord.fromCloudRecord(store.record(owner,CloudEntity.TRANSACTION_CATEGORY.table,CHILD)!!))
    }
    @Test fun `viewer envelope foreign system metadata cannot alias owned category`()=runTest {
        seedSystemCategories()
        val foreign=repo.observeCategories(owner).first().single {it.id==CHILD}
            .copy(id=SystemCategoryIdentity.cloudId("rent",UserId(OTHER)),ownerUserId=OTHER)
        val viewer=foreign.toCloudRecord().copy(ownerUserId=OWNER,payload=JsonObject(foreign.toPayload()+ ("sync_version" to JsonPrimitive("malformed foreign version"))))
        store.replacePullSnapshot(owner,CloudEntity.TRANSACTION_CATEGORY.table,
            repo.observeBudgetCategoryMetadata(owner).first().map {it.toCloudRecord()}+viewer)
        val metadata=repo.observeBudgetCategoryMetadata(owner).first()
        assertEquals(3,metadata.size)
        assertEquals(foreign.id,CategoryIdentityIndex(owner,metadata).logical(foreign.id))
        assertTrue(repo.saveBudget(owner,draft().copy(categoryId=foreign.id),DEVICE,NOW).isFailure)
    }
    @Test fun `system canonical parent prevents duplicate auto parent and propagates family to legacy child`()=runTest {
        seedSystemCategories()
        val child=repo.saveBudget(owner,draft(),DEVICE,NOW).getOrThrow()
            .copy(categoryIdSnapshot=CHILD,categoryParentIdSnapshot=PARENT)
        store.commitMutation(child.toCloudRecord(),pending(child))
        val parent=repo.saveBudget(owner,draft().copy(id=PARENT_BUDGET,categoryId=PARENT,limitMinor=1500),DEVICE,NOW).getOrThrow()
        val parentCategory=repo.observeCategories(owner).first().single {it.id==PARENT}.copy(familyBudgetSpendingEnabled=true)
        store.commitMutation(parentCategory.toCloudRecord(),parentCategory.bootstrapMutation())
        repo.saveBudget(owner,draft().copy(id=NEW_ID,categoryId=CHILD2),DEVICE,NOW).getOrThrow()
        val plans=repo.observeBudgets(owner).first()
        assertEquals(3,plans.size)
        assertEquals(parent.id,plans.single {it.categoryId==PARENT}.id)
        assertTrue(plans.all {it.includesFamilySpending})
        assertEquals(SystemCategoryIdentity.canonicalId("rent"),plans.single {it.id==child.id}.categoryIdSnapshot)
    }

    @Test fun `metadata accepts UUID casing already normalized by typed category contract`()=runTest {
        val scoped=UserId("abcdefab-cdef-abcd-efab-cdefabcdefab")
        val category=CategoryDraft(id=PARENT,name="Housing",kind=TransactionCategoryKind.EXPENSE,hierarchyRole=CategoryHierarchyRole.PARENT)
            .toMutation(scoped,null,null,DEVICE,NOW).record
        val wire=category.toCloudRecord().copy(payload=JsonObject(category.toPayload()+ ("user_id" to JsonPrimitive(scoped.value.uppercase()))))
        store.replacePullSnapshot(scoped,CloudEntity.TRANSACTION_CATEGORY.table,listOf(wire))
        assertEquals(listOf(category),repo.observeBudgetCategoryMetadata(scoped).first())
        assertTrue(repo.saveBudget(scoped,draft().copy(categoryId=PARENT),DEVICE,NOW).isSuccess)
    }

    private fun draft() = BudgetDraft(id = BUDGET, categoryId = CHILD, monthAnchor = NOW,
        limitMinor = 500, currencyCode = "JPY", rolloverEnabled = true, zoneId = zone)

    private suspend fun seedCategories(target: BudgetMemoryStore = store) {
        val r = OfflineFirstFinanceRepository(target)
        r.saveCategory(owner, CategoryDraft(id = PARENT, name = "Living", kind = TransactionCategoryKind.EXPENSE,
            hierarchyRole = CategoryHierarchyRole.PARENT), DEVICE, NOW).getOrThrow()
        r.saveCategory(owner, CategoryDraft(id = CHILD, name = "Food", kind = TransactionCategoryKind.EXPENSE,
            hierarchyRole = CategoryHierarchyRole.CHILD, parentCategoryId = PARENT), DEVICE, NOW).getOrThrow()
        r.saveCategory(owner, CategoryDraft(id = CHILD2, name = "Travel", kind = TransactionCategoryKind.EXPENSE,
            hierarchyRole = CategoryHierarchyRole.CHILD, parentCategoryId = PARENT), DEVICE, NOW).getOrThrow()
        val rows = r.observeCategories(owner).first().map { it.copy(nameJapanese = if (it.id == PARENT) "生活" else "食費").toCloudRecord() }
        target.replacePullSnapshot(owner, CloudEntity.TRANSACTION_CATEGORY.table, rows)
    }

    private fun pending(record: BudgetPlanRecord) = PendingMutation(CloudEntity.BUDGET_PLAN, record.id,
        record.ownerUserId, MutationKind.UPSERT, record.toPayload(), record.updatedAt, record.syncVersion, DEVICE)

    companion object {
        const val OWNER = "11111111-1111-1111-1111-111111111111"
        const val OTHER = "22222222-2222-2222-2222-222222222222"
        const val DEVICE = "33333333-3333-3333-3333-333333333333"
        const val PARENT = "44444444-4444-4444-4444-444444444444"
        const val CHILD = "55555555-5555-5555-5555-555555555555"
        const val CHILD2 = "66666666-6666-6666-6666-666666666666"
        const val BUDGET = "77777777-7777-7777-7777-777777777777"
        const val NEW_ID = "88888888-8888-8888-8888-888888888888"
        const val PARENT_BUDGET = "99999999-9999-9999-9999-999999999999"
        const val NOW = "2026-10-13T01:00:00Z"
        const val LATER = "2026-10-13T02:00:00Z"
    }
}

    internal class BudgetMemoryStore : LocalStore {
        var billReceiptIds: Set<String> = emptySet()
        override suspend fun billMoneyReceiptTransactionIds(owner: UserId): Set<String> = billReceiptIds
        private val records = MutableStateFlow<Map<Triple<String, String, String>, CloudRecord>>(emptyMap())
        private val outbox = linkedMapOf<Triple<String, String, String>, PendingMutation>()

        override suspend fun recordsIncludingDeleted(ownerUserId: UserId, entity: String): List<CloudRecord> =
            records.value.values.filter { it.ownerUserId==ownerUserId.value && it.entity==entity }

        override fun observe(entity: String, ownerUserId: UserId): Flow<List<CloudRecord>> =
            records.map { values ->
                values.values.filter {
                    it.ownerUserId == ownerUserId.value && it.entity == entity && it.deletedAt == null
                }
            }

        override fun observeEntityCounts(ownerUserId: UserId): Flow<List<EntityCount>> =
            records.map { values ->
                values.values
                    .filter { it.ownerUserId == ownerUserId.value && it.deletedAt == null }
                    .groupingBy(CloudRecord::entity)
                    .eachCount()
                    .map { EntityCount(it.key, it.value) }
            }

        override suspend fun record(ownerUserId: UserId, entity: String, recordId: String): CloudRecord? =
            records.value[Triple(ownerUserId.value, entity, recordId)]

        override suspend fun commitMutations(mutations: List<Pair<CloudRecord, PendingMutation>>) {
            batches.add(mutations)
            if (failBatch) throw IllegalStateException("simulated storage failure")
            mutations.forEach { (record, mutation) -> commitMutation(record, mutation) }
        }
        override suspend fun commitBillCycleMutations(bill:CloudRecord,monthKey:String,expectedOccurrences:List<CloudRecord>,mutations:List<Pair<CloudRecord,PendingMutation>>) {
            require(record(UserId(bill.ownerUserId),bill.entity,bill.id)==bill)
            require(billCycleRecords(recordsIncludingDeleted(UserId(bill.ownerUserId),CloudEntity.DUE_OCCURRENCE_RECORD.table),bill,monthKey)==expectedOccurrences.sortedBy {it.id})
            commitMutations(mutations)
        }
        override suspend fun commitBillMoneyMutations(snapshot:BillMoneySnapshot,mutations:List<Pair<CloudRecord,PendingMutation>>) {
            snapshot.requireValidMutations(mutations)
            snapshot.requireUnchanged(CloudEntity.entries.associateWith { recordsIncludingDeleted(snapshot.owner,it.table) })
            require(snapshot.receiptTransactionIds==billMoneyReceiptTransactionIds(snapshot.owner))
            commitMutations(mutations)
        }
        override suspend fun commitMissingSystemCategories(mutations:List<Pair<CloudRecord,PendingMutation>>) {
            require(mutations.none { (candidate,_) -> records.value.values.any {row -> row.ownerUserId==candidate.ownerUserId && row.entity==candidate.entity &&
                (row.id==candidate.id || (row.payload["user_id"]==candidate.payload["user_id"] && row.payload["system_key"]==candidate.payload["system_key"])) }})
            commitMutations(mutations)
        }
        val batches = mutableListOf<List<Pair<CloudRecord, PendingMutation>>>()
        var failBatch = false

        override suspend fun commitMutation(record: CloudRecord, mutation: PendingMutation) {
            val key = Triple(record.ownerUserId, record.entity, record.id)
            require(key == Triple(mutation.subjectUserId, mutation.entity.table, mutation.recordId))
            records.value = records.value + (key to record)
            outbox[key] = mutation
        }

        override suspend fun pendingMutations(
            ownerUserId: UserId,
            entity: CloudEntity,
            dueAtEpochMillis: Long,
            limit: Int,
        ): List<QueuedMutation> = outbox
            .filterKeys { it.first == ownerUserId.value && it.second == entity.table }
            .values
            .sortedBy(PendingMutation::modifiedAt)
            .take(limit)
            .map { QueuedMutation(it, 0, 0, null) }

        override suspend fun acknowledgeMutation(
            mutation: QueuedMutation,
            remoteRecord: CloudRecord,
        ): Boolean {
            val key = Triple(
                mutation.mutation.subjectUserId,
                mutation.mutation.entity.table,
                mutation.mutation.recordId,
            )
            if (outbox[key] != mutation.mutation) return false
            outbox.remove(key)
            records.value = records.value + (key to remoteRecord)
            return true
        }

        override suspend fun recordMutationFailure(
            mutation: QueuedMutation,
            nextAttemptAtEpochMillis: Long,
            errorCode: String,
        ): Boolean = outbox.values.contains(mutation.mutation)

        override suspend fun replacePullSnapshot(
            ownerUserId: UserId,
            entity: String,
            records: List<CloudRecord>,
        ) {
            val retained = this.records.value.filterKeys { key ->
                key.first != ownerUserId.value || key.second != entity || outbox.containsKey(key)
            }
            this.records.value = retained + records.associateBy {
                Triple(ownerUserId.value, entity, it.id)
            }
        }

        override suspend fun pendingMutationRecordIds(ownerUserId: UserId, entity: String): Set<String> =
            outbox.keys.filter { it.first == ownerUserId.value && it.second == entity }.mapTo(mutableSetOf()) { it.third }

        override suspend fun clearAccount(ownerUserId: UserId) {
            records.value = records.value.filterKeys { it.first != ownerUserId.value }
            outbox.keys.removeAll { it.first == ownerUserId.value }
        }

        fun outboxRows(ownerUserId: String): List<PendingMutation> =
            outbox.filterKeys { it.first == ownerUserId }.values.toList()
    }

