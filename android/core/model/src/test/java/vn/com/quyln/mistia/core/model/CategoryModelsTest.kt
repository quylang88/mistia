package vn.com.quyln.mistia.core.model

import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CategoryModelsTest {
    @Test
    fun `new Vietnamese parent encodes every optional field explicitly`() {
        val mutation = CategoryDraft(
            name = " Ăn uống ",
            nameLanguage = CategoryNameLanguage.VIETNAMESE,
            kind = TransactionCategoryKind.EXPENSE,
            hierarchyRole = CategoryHierarchyRole.PARENT,
        ).toMutation(UserId(OWNER), null, null, DEVICE, NOW)

        assertEquals("Ăn uống", mutation.record.name)
        assertNull(mutation.record.nameEnglish)
        assertEquals(JsonNull, mutation.record.toPayload()["name_english"])
        assertEquals(JsonNull, mutation.record.toPayload()["parent_category_id"])
        assertEquals(JsonNull, mutation.record.toPayload()["system_key"])
        assertFalse(mutation.record.isFavorite)
        assertEquals("mistia.flow.expense", mutation.record.iconSymbolName)
    }

    @Test
    fun `English edit preserves other translations identity and system metadata`() {
        val existing = category(
            name = "Ăn uống",
            nameEnglish = "Food",
            nameJapanese = "食費",
            syncVersion = 7,
            systemKey = "food",
            isSystem = true,
        )

        val mutation = CategoryDraft(
            id = existing.id,
            name = "Dining",
            nameLanguage = CategoryNameLanguage.ENGLISH,
            kind = requireNotNull(existing.kind),
            hierarchyRole = existing.hierarchyRole,
        ).toMutation(UserId(OWNER), existing, null, DEVICE, NOW)

        assertEquals("Ăn uống", mutation.record.name)
        assertEquals("Dining", mutation.record.nameEnglish)
        assertEquals("食費", mutation.record.nameJapanese)
        assertEquals(existing.id, mutation.record.id)
        assertEquals(existing.createdAt, mutation.record.createdAt)
        assertEquals("food", mutation.record.systemKey)
        assertTrue(mutation.record.isSystem)
        assertEquals(7L, mutation.pending.baseVersion)
    }

    @Test
    fun `child requires active same-kind parent`() {
        val draft = CategoryDraft(
            name = "Lunch",
            kind = TransactionCategoryKind.EXPENSE,
            hierarchyRole = CategoryHierarchyRole.CHILD,
        )
        assertCategoryError(CategoryValidationError.PARENT_REQUIRED) {
            draft.toMutation(UserId(OWNER), null, null, DEVICE, NOW)
        }
        assertCategoryError(CategoryValidationError.PARENT_KIND_MISMATCH) {
            draft.copy(parentCategoryId = PARENT_ID).toMutation(
                UserId(OWNER),
                null,
                category(kind = TransactionCategoryKind.INCOME),
                DEVICE,
                NOW,
            )
        }
    }

    @Test
    fun `existing hierarchy role cannot change and parents cannot be favorite`() {
        val existing = category(role = CategoryHierarchyRole.PARENT)
        assertCategoryError(CategoryValidationError.HIERARCHY_ROLE_IMMUTABLE) {
            CategoryDraft(
                id = existing.id,
                name = existing.name,
                kind = requireNotNull(existing.kind),
                hierarchyRole = CategoryHierarchyRole.CHILD,
                parentCategoryId = PARENT_ID,
            ).toMutation(UserId(OWNER), existing, category(), DEVICE, NOW)
        }

        val parent = CategoryDraft(
            name = "Parent",
            kind = TransactionCategoryKind.INCOME,
            hierarchyRole = CategoryHierarchyRole.PARENT,
            isFavorite = true,
        ).toMutation(UserId(OWNER), null, null, DEVICE, NOW)
        assertFalse(parent.record.isFavorite)
    }

    @Test
    fun `contract round trip preserves all category fields`() {
        val original = category(
            name = "Salary",
            nameEnglish = "Salary",
            nameJapanese = "給与",
            kind = TransactionCategoryKind.INCOME,
            role = CategoryHierarchyRole.CHILD,
            parentId = PARENT_ID,
            syncVersion = 9,
        ).copy(
            isFavorite = true,
            familyBudgetSpendingEnabled = true,
            isArchived = true,
            archivedAt = NOW,
            deletedAt = LATER,
            lastModifiedByDeviceId = DEVICE,
        )

        val decoded = TransactionCategoryRecord.fromCloudRecord(original.toCloudRecord())

        assertEquals(original, decoded)
        assertEquals(JsonPrimitive(true), decoded.toPayload()["family_budget_spending_enabled"])
    }

    @Test
    fun `balance adjustment system categories are recognized by canonical id or system key`() {
        val canonical = category(role = CategoryHierarchyRole.CHILD).copy(
            id = TransactionCategoryRecord.BALANCE_ADJUSTMENT_EXPENSE_ID,
            parentCategoryId = PARENT_ID,
        )
        val scoped = canonical.copy(
            id = CHILD_ID,
            systemKey = TransactionCategoryRecord.BALANCE_ADJUSTMENT_INCOME_KEY,
        )

        assertTrue(canonical.isBalanceAdjustmentSystemCategory)
        assertTrue(scoped.isBalanceAdjustmentSystemCategory)
        assertFalse(category().isBalanceAdjustmentSystemCategory)
    }

    private fun category(
        name: String = "Parent",
        nameEnglish: String? = null,
        nameJapanese: String? = null,
        kind: TransactionCategoryKind = TransactionCategoryKind.EXPENSE,
        role: CategoryHierarchyRole = CategoryHierarchyRole.PARENT,
        parentId: String? = null,
        syncVersion: Long = 0,
        systemKey: String? = null,
        isSystem: Boolean = false,
    ) = TransactionCategoryRecord(
        id = if (role == CategoryHierarchyRole.PARENT) PARENT_ID else CHILD_ID,
        ownerUserId = OWNER,
        name = name,
        nameEnglish = nameEnglish,
        nameJapanese = nameJapanese,
        kindWireValue = kind.wireValue,
        iconSymbolName = kind.defaultIcon,
        iconColorHex = kind.defaultColorHex,
        isFavorite = false,
        familyBudgetSpendingEnabled = false,
        parentCategoryId = parentId,
        hierarchyRoleWireValue = role.wireValue,
        systemKey = systemKey,
        isSystem = isSystem,
        sortOrder = 0,
        isArchived = false,
        archivedAt = null,
        createdAt = CREATED,
        updatedAt = CREATED,
        deletedAt = null,
        syncVersion = syncVersion,
        lastModifiedByDeviceId = null,
    )

    private fun assertCategoryError(expected: CategoryValidationError, block: () -> Unit) {
        val error = runCatching(block).exceptionOrNull() as CategoryValidationException
        assertEquals(expected, error.reason)
    }

    private companion object {
        const val OWNER = "11111111-1111-1111-1111-111111111111"
        const val PARENT_ID = "22222222-2222-2222-2222-222222222222"
        const val CHILD_ID = "33333333-3333-3333-3333-333333333333"
        const val DEVICE = "44444444-4444-4444-4444-444444444444"
        const val CREATED = "2026-01-01T00:00:00.000Z"
        const val NOW = "2026-09-22T10:00:00.000Z"
        const val LATER = "2026-09-22T11:00:00.000Z"
    }
}
