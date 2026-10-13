package vn.com.quyln.mistia.core.database

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.model.*

@RunWith(AndroidJUnit4::class)
class BudgetRoomTest {
    private lateinit var db: MistiaDatabase
    private lateinit var store: RoomLocalStore
    private val owner = UserId("11111111-1111-1111-1111-111111111111")
    private val device = "22222222-2222-2222-2222-222222222222"
    private val now = "2026-10-13T01:00:00Z"

    @Before fun setup() {
        db = Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(), MistiaDatabase::class.java)
            .allowMainThreadQueries().build()
        store = RoomLocalStore(db)
    }
    @After fun close() = db.close()

    @Test fun secondChildAndAutomaticParentPersistTogetherAndSurviveRepositoryRecreation() = runTest {
        val repo = OfflineFirstFinanceRepository(store)
        val parent = repo.saveCategory(owner, CategoryDraft(name = "Living", kind = TransactionCategoryKind.EXPENSE,
            hierarchyRole = CategoryHierarchyRole.PARENT), device, now).getOrThrow()
        val children = listOf("Food", "Travel").map { name ->
            repo.saveCategory(owner, CategoryDraft(name = name, kind = TransactionCategoryKind.EXPENSE,
                hierarchyRole = CategoryHierarchyRole.CHILD, parentCategoryId = parent.id), device, now).getOrThrow()
        }
        children.forEach { child -> repo.saveBudget(owner, BudgetDraft(categoryId = child.id, monthAnchor = now,
            limitMinor = 500, currencyCode = "JPY"), device, now).getOrThrow() }
        val restored = OfflineFirstFinanceRepository(RoomLocalStore(db))
        assertEquals(3, restored.observeBudgets(owner).first().size)
        assertEquals(1000, restored.observeBudgets(owner).first().single { it.categoryId == parent.id }.limitMinor)
        assertEquals(3, store.pendingMutations(owner, CloudEntity.BUDGET_PLAN, Long.MAX_VALUE).size)
        val other = UserId("33333333-3333-3333-3333-333333333333")
        assertTrue(restored.observeBudgets(other).first().isEmpty())
        assertTrue(store.pendingMutations(other, CloudEntity.BUDGET_PLAN, Long.MAX_VALUE).isEmpty())
    }

    @Test fun invalidSecondMutationRollsBackFirstRecordAndOutbox() = runTest {
        val first = CategoryDraft(name = "Living", kind = TransactionCategoryKind.EXPENSE,
            hierarchyRole = CategoryHierarchyRole.PARENT).toMutation(owner, null, null, device, now)
        val second = CategoryDraft(name = "Food", kind = TransactionCategoryKind.EXPENSE,
            hierarchyRole = CategoryHierarchyRole.PARENT).toMutation(owner, null, null, device, now)
        val result = runCatching {
            store.commitMutations(listOf(first.record.toCloudRecord() to first.pending, second.record.toCloudRecord() to second.pending.copy(payload = null)))
        }
        assertTrue(result.isFailure)
        assertEquals(null, store.record(owner, CloudEntity.TRANSACTION_CATEGORY.table, first.record.id))
        assertTrue(store.pendingMutations(owner, CloudEntity.TRANSACTION_CATEGORY, Long.MAX_VALUE).isEmpty())
    }
}
