package vn.com.quyln.mistia.core.model

import java.time.ZoneId
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Assert.assertThrows
import org.junit.Test

class BudgetModelsTest {
    @Test
    fun `budget cloud round trip preserves snapshots signed int64 and explicit nulls`() {
        val budget = budget()

        val payload = budget.toPayload()
        assertSame(JsonNull, payload["category_id"])
        assertSame(JsonNull, payload["deleted_at"])
        assertSame(JsonNull, payload["last_modified_by_device_id"])
        assertEquals(Long.MAX_VALUE.toString(), payload["limit_minor"].toString())

        assertEquals(budget, BudgetPlanRecord.fromCloudRecord(budget.toCloudRecord()))
        assertEquals(
            BudgetAllocationSnapshot(
                id = BUDGET_ID,
                categoryId = CATEGORY_ID,
                branchCategoryId = PARENT_ID,
                categoryIsParent = false,
                limitMinor = Long.MAX_VALUE,
                monthAnchor = "2026-09-01T00:00:00Z",
            ),
            budget.allocationSnapshot(),
        )
    }

    @Test
    fun `allocation snapshot prefers frozen category identity over live relation`() {
        val snapshot = budget().copy(
            categoryId = SECOND_CHILD_ID,
            categoryIdSnapshot = CATEGORY_ID,
        ).allocationSnapshot()

        assertEquals(CATEGORY_ID, snapshot.categoryId)
        assertEquals(PARENT_ID, snapshot.branchCategoryId)
    }

    @Test
    fun `cloud decode preserves empty optional snapshot strings`() {
        val budget = budget().copy(
            categoryNameSnapshot = "",
            categoryPathEnglishSnapshot = "",
            categoryIconSymbolNameSnapshot = "",
        )

        assertEquals(budget, BudgetPlanRecord.fromCloudRecord(budget.toCloudRecord()))
    }

    @Test
    fun `cloud decode rejects missing and malformed required fields but defaults legacy family flag`() {
        val cloud = budget().toCloudRecord()
        val requiredFields = listOf(
            "user_id",
            "id",
            "month_anchor",
            "limit_minor",
            "rollover_enabled",
            "currency_code",
            "is_archived",
            "created_at",
            "updated_at",
            "sync_version",
        )

        requiredFields.forEach { key ->
            assertThrows("missing $key", IllegalArgumentException::class.java) {
                BudgetPlanRecord.fromCloudRecord(
                    cloud.copy(payload = JsonObject(cloud.payload.filterKeys { it != key })),
                )
            }
        }

        listOf("limit_minor", "sync_version").forEach { key ->
            assertThrows("malformed $key", IllegalArgumentException::class.java) {
                BudgetPlanRecord.fromCloudRecord(
                    cloud.copy(payload = JsonObject(cloud.payload + (key to JsonPrimitive("not-a-number")))),
                )
            }
        }
        listOf("rollover_enabled", "is_archived").forEach { key ->
            assertThrows("malformed $key", IllegalArgumentException::class.java) {
                BudgetPlanRecord.fromCloudRecord(
                    cloud.copy(payload = JsonObject(cloud.payload + (key to JsonPrimitive("not-a-boolean")))),
                )
            }
        }

        val legacyPayload = JsonObject(cloud.payload.filterKeys { it != "includes_family_spending" })
        assertEquals(
            false,
            BudgetPlanRecord.fromCloudRecord(cloud.copy(payload = legacyPayload)).includesFamilySpending,
        )
    }

    @Test
    fun `budget allocation rejects child total above parent and excludes edited budget`() {
        val parent = allocation(
            id = PARENT_BUDGET_ID,
            categoryId = PARENT_ID,
            branchCategoryId = PARENT_ID,
            categoryIsParent = true,
            limitMinor = 1_000,
        )
        val existingChild = allocation(
            id = CHILD_BUDGET_ID,
            categoryId = CATEGORY_ID,
            branchCategoryId = PARENT_ID,
            categoryIsParent = false,
            limitMinor = 600,
        )

        assertEquals(
            BudgetAllocationValidation.ChildBudgetsExceedParent(
                childTotalMinor = 1_100,
                parentLimitMinor = 1_000,
            ),
            validateBudgetAllocation(
                categoryId = SECOND_CHILD_ID,
                branchCategoryId = PARENT_ID,
                categoryIsParent = false,
                categoryIsChild = true,
                limitMinor = 500,
                monthAnchor = MONTH,
                plans = listOf(parent, existingChild),
                zoneId = ZoneId.of("UTC"),
            ),
        )
        assertEquals(
            BudgetAllocationValidation.Valid,
            validateBudgetAllocation(
                categoryId = CATEGORY_ID,
                branchCategoryId = PARENT_ID,
                categoryIsParent = false,
                categoryIsChild = true,
                limitMinor = 500,
                monthAnchor = MONTH,
                plans = listOf(parent, existingChild),
                editingBudgetId = CHILD_BUDGET_ID,
                zoneId = ZoneId.of("UTC"),
            ),
        )
    }

    @Test
    fun `budget allocation rejects parent below same month children only`() {
        val sameMonthChild = allocation(
            id = CHILD_BUDGET_ID,
            categoryId = CATEGORY_ID,
            branchCategoryId = PARENT_ID,
            categoryIsParent = false,
            limitMinor = 600,
        )
        val otherMonthChild = sameMonthChild.copy(
            id = SECOND_CHILD_BUDGET_ID,
            monthAnchor = "2026-08-01T00:00:00Z",
            limitMinor = 9_000,
        )
        val otherBranchChild = sameMonthChild.copy(
            id = THIRD_CHILD_BUDGET_ID,
            branchCategoryId = OTHER_PARENT_ID,
            limitMinor = 9_000,
        )

        assertEquals(
            BudgetAllocationValidation.ParentLimitBelowChildren(
                childTotalMinor = 600,
                parentLimitMinor = 500,
            ),
            validateBudgetAllocation(
                categoryId = PARENT_ID,
                branchCategoryId = PARENT_ID,
                categoryIsParent = true,
                categoryIsChild = false,
                limitMinor = 500,
                monthAnchor = MONTH,
                plans = listOf(sameMonthChild, otherMonthChild, otherBranchChild),
                zoneId = ZoneId.of("UTC"),
            ),
        )
    }

    @Test
    fun `budget allocation rejects child total that exceeds signed int64`() {
        val parent = allocation(
            id = PARENT_BUDGET_ID,
            categoryId = PARENT_ID,
            branchCategoryId = PARENT_ID,
            categoryIsParent = true,
            limitMinor = Long.MAX_VALUE,
        )
        val existingChild = allocation(
            id = CHILD_BUDGET_ID,
            categoryId = CATEGORY_ID,
            branchCategoryId = PARENT_ID,
            categoryIsParent = false,
            limitMinor = Long.MAX_VALUE,
        )

        assertEquals(
            BudgetAllocationValidation.ChildBudgetsExceedParent(
                childTotalMinor = Long.MAX_VALUE,
                parentLimitMinor = Long.MAX_VALUE,
            ),
            validateBudgetAllocation(
                categoryId = SECOND_CHILD_ID,
                branchCategoryId = PARENT_ID,
                categoryIsParent = false,
                categoryIsChild = true,
                limitMinor = 1,
                monthAnchor = MONTH,
                plans = listOf(parent, existingChild),
                zoneId = ZoneId.of("UTC"),
            ),
        )
    }

    private fun budget() = BudgetPlanRecord(
        id = BUDGET_ID,
        ownerUserId = OWNER_ID,
        categoryId = null,
        categoryIdSnapshot = CATEGORY_ID,
        categoryNameSnapshot = "Ăn uống",
        categoryNameEnglishSnapshot = "Food",
        categoryNameJapaneseSnapshot = "食費",
        categoryPathSnapshot = "Sinh hoạt / Ăn uống",
        categoryPathEnglishSnapshot = "Living / Food",
        categoryPathJapaneseSnapshot = "生活 / 食費",
        categoryIconSymbolNameSnapshot = "mistia.category.food",
        categoryColorHexSnapshot = "#FF7A59",
        categoryParentIdSnapshot = PARENT_ID,
        categoryParentNameSnapshot = "Sinh hoạt",
        categoryParentNameEnglishSnapshot = "Living",
        categoryParentNameJapaneseSnapshot = "生活",
        categoryParentIconSymbolNameSnapshot = "mistia.category.living",
        categoryParentColorHexSnapshot = "#5B7BFF",
        categoryHierarchyRoleSnapshotWireValue = "child",
        categoryIsParentSnapshot = false,
        includesFamilySpending = true,
        monthAnchor = MONTH,
        limitMinor = Long.MAX_VALUE,
        rolloverEnabled = true,
        currencyCode = "JPY",
        isArchived = false,
        createdAt = MONTH,
        updatedAt = "2026-09-25T01:02:03Z",
        deletedAt = null,
        syncVersion = Long.MAX_VALUE,
        lastModifiedByDeviceId = null,
    )

    private fun allocation(
        id: String,
        categoryId: String,
        branchCategoryId: String,
        categoryIsParent: Boolean,
        limitMinor: Long,
    ) = BudgetAllocationSnapshot(
        id = id,
        categoryId = categoryId,
        branchCategoryId = branchCategoryId,
        categoryIsParent = categoryIsParent,
        limitMinor = limitMinor,
        monthAnchor = MONTH,
    )

    private companion object {
        const val OWNER_ID = "11111111-1111-4111-8111-111111111111"
        const val BUDGET_ID = "22222222-2222-4222-8222-222222222222"
        const val PARENT_BUDGET_ID = "33333333-3333-4333-8333-333333333333"
        const val CHILD_BUDGET_ID = "44444444-4444-4444-8444-444444444444"
        const val SECOND_CHILD_BUDGET_ID = "55555555-5555-4555-8555-555555555555"
        const val THIRD_CHILD_BUDGET_ID = "66666666-6666-4666-8666-666666666666"
        const val PARENT_ID = "77777777-7777-4777-8777-777777777777"
        const val OTHER_PARENT_ID = "88888888-8888-4888-8888-888888888888"
        const val CATEGORY_ID = "99999999-9999-4999-8999-999999999999"
        const val SECOND_CHILD_ID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        const val MONTH = "2026-09-01T00:00:00Z"
    }
}
