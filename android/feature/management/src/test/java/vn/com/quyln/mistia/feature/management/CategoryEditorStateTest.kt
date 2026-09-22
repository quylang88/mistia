package vn.com.quyln.mistia.feature.management

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import vn.com.quyln.mistia.core.model.CategoryHierarchyRole
import vn.com.quyln.mistia.core.model.CategoryNameLanguage
import vn.com.quyln.mistia.core.model.TransactionCategoryKind
import vn.com.quyln.mistia.core.model.TransactionCategoryRecord

class CategoryEditorStateTest {
    @Test
    fun `kind change updates untouched defaults and clears parent`() {
        val changed = CategoryEditorState.new(TransactionCategoryKind.EXPENSE)
            .selectRole(CategoryHierarchyRole.CHILD)
            .copy(parentCategoryId = PARENT)
            .selectKind(TransactionCategoryKind.INCOME)

        assertEquals("mistia.flow.income", changed.iconSymbolName)
        assertEquals("#2DAA9E", changed.iconColorHex)
        assertNull(changed.parentCategoryId)
    }

    @Test
    fun `custom icon and color survive kind change`() {
        val changed = CategoryEditorState.new(TransactionCategoryKind.EXPENSE)
            .customizeIcon("restaurant", "#123456")
            .selectKind(TransactionCategoryKind.INCOME)

        assertEquals("restaurant", changed.iconSymbolName)
        assertEquals("#123456", changed.iconColorHex)
    }

    @Test
    fun `parent role clears parent and favorite`() {
        val changed = CategoryEditorState.new(TransactionCategoryKind.EXPENSE)
            .selectRole(CategoryHierarchyRole.CHILD)
            .copy(parentCategoryId = PARENT, isFavorite = true)
            .selectRole(CategoryHierarchyRole.PARENT)

        assertNull(changed.parentCategoryId)
        assertFalse(changed.isFavorite)
    }

    @Test
    fun `existing hierarchy role is immutable`() {
        val state = CategoryEditorState.edit(category(CategoryHierarchyRole.PARENT))

        assertEquals(CategoryHierarchyRole.PARENT, state.selectRole(CategoryHierarchyRole.CHILD).hierarchyRole)
    }

    @Test
    fun `child draft requires a parent and preserves locale`() {
        val missing = CategoryEditorState.new(TransactionCategoryKind.EXPENSE)
            .selectRole(CategoryHierarchyRole.CHILD)
            .copy(name = "Lunch")
            .toDraft(CategoryNameLanguage.ENGLISH)
        val valid = CategoryEditorState.new(TransactionCategoryKind.EXPENSE)
            .selectRole(CategoryHierarchyRole.CHILD)
            .copy(name = "Lunch", parentCategoryId = PARENT, isFavorite = true)
            .toDraft(CategoryNameLanguage.ENGLISH)

        assertEquals(CategoryEditorValidation.PARENT_REQUIRED, missing.validation)
        assertEquals(CategoryNameLanguage.ENGLISH, valid.draft?.nameLanguage)
        assertTrue(valid.draft?.isFavorite == true)
    }

    private fun category(role: CategoryHierarchyRole) = TransactionCategoryRecord(
        id = CATEGORY,
        ownerUserId = OWNER,
        name = "Food",
        nameEnglish = "Food",
        nameJapanese = null,
        kindWireValue = TransactionCategoryKind.EXPENSE.wireValue,
        iconSymbolName = TransactionCategoryKind.EXPENSE.defaultIcon,
        iconColorHex = TransactionCategoryKind.EXPENSE.defaultColorHex,
        isFavorite = false,
        familyBudgetSpendingEnabled = false,
        parentCategoryId = null,
        hierarchyRoleWireValue = role.wireValue,
        systemKey = null,
        isSystem = false,
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
        const val CATEGORY = "22222222-2222-2222-2222-222222222222"
        const val PARENT = "33333333-3333-3333-3333-333333333333"
    }
}
