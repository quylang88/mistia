package vn.com.quyln.mistia.feature.management

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import vn.com.quyln.mistia.core.model.CategoryHierarchyRole
import vn.com.quyln.mistia.core.model.TransactionCategoryKind
import vn.com.quyln.mistia.core.model.TransactionCategoryRecord

class CategoryHierarchyRowsTest {
    @Test
    fun `balance adjustments stay hidden and empty uncategorized parent collapses`() {
        val parent = category(
            id = PARENT,
            role = CategoryHierarchyRole.PARENT,
            systemKey = "parent_expense_uncategorized",
        )
        val adjustment = category(
            id = TransactionCategoryRecord.BALANCE_ADJUSTMENT_EXPENSE_ID,
            role = CategoryHierarchyRole.CHILD,
            parentId = PARENT,
            systemKey = TransactionCategoryRecord.BALANCE_ADJUSTMENT_EXPENSE_KEY,
        )

        val rows = visibleCategoryHierarchy(listOf(parent, adjustment), TransactionCategoryKind.EXPENSE)

        assertTrue(rows.parents.isEmpty())
        assertTrue(rows.children.isEmpty())
    }

    @Test
    fun `ordinary child keeps its parent visible while hidden adjustment is omitted`() {
        val parent = category(PARENT, CategoryHierarchyRole.PARENT)
        val child = category(CHILD, CategoryHierarchyRole.CHILD, parentId = PARENT)
        val adjustment = category(
            id = "99999999-9999-9999-9999-999999999999",
            role = CategoryHierarchyRole.CHILD,
            parentId = PARENT,
            systemKey = TransactionCategoryRecord.BALANCE_ADJUSTMENT_INCOME_KEY,
        )

        val rows = visibleCategoryHierarchy(listOf(parent, adjustment, child), TransactionCategoryKind.EXPENSE)

        assertEquals(listOf(PARENT), rows.parents.map { it.id })
        assertEquals(listOf(CHILD), rows.children.map { it.id })
    }

    private fun category(
        id: String,
        role: CategoryHierarchyRole,
        parentId: String? = null,
        systemKey: String? = null,
    ) = TransactionCategoryRecord(
        id = id,
        ownerUserId = OWNER,
        name = id,
        nameEnglish = null,
        nameJapanese = null,
        kindWireValue = TransactionCategoryKind.EXPENSE.wireValue,
        iconSymbolName = TransactionCategoryKind.EXPENSE.defaultIcon,
        iconColorHex = TransactionCategoryKind.EXPENSE.defaultColorHex,
        isFavorite = false,
        familyBudgetSpendingEnabled = false,
        parentCategoryId = parentId,
        hierarchyRoleWireValue = role.wireValue,
        systemKey = systemKey,
        isSystem = systemKey != null,
        sortOrder = 0,
        isArchived = false,
        archivedAt = null,
        createdAt = "2026-01-01T00:00:00Z",
        updatedAt = "2026-01-01T00:00:00Z",
        deletedAt = null,
        syncVersion = 0,
        lastModifiedByDeviceId = null,
    )

    private companion object {
        const val OWNER = "11111111-1111-1111-1111-111111111111"
        const val PARENT = "22222222-2222-2222-2222-222222222222"
        const val CHILD = "33333333-3333-3333-3333-333333333333"
    }
}
