package vn.com.quyln.mistia.core.model

import java.math.BigInteger
import java.time.Instant
import java.time.YearMonth
import java.time.ZoneId
import java.util.Locale
import java.util.UUID
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.longOrNull

data class BudgetPlanRecord(
    val id: String,
    val ownerUserId: String,
    val categoryId: String?,
    val categoryIdSnapshot: String?,
    val categoryNameSnapshot: String?,
    val categoryNameEnglishSnapshot: String?,
    val categoryNameJapaneseSnapshot: String?,
    val categoryPathSnapshot: String?,
    val categoryPathEnglishSnapshot: String?,
    val categoryPathJapaneseSnapshot: String?,
    val categoryIconSymbolNameSnapshot: String?,
    val categoryColorHexSnapshot: String?,
    val categoryParentIdSnapshot: String?,
    val categoryParentNameSnapshot: String?,
    val categoryParentNameEnglishSnapshot: String?,
    val categoryParentNameJapaneseSnapshot: String?,
    val categoryParentIconSymbolNameSnapshot: String?,
    val categoryParentColorHexSnapshot: String?,
    val categoryHierarchyRoleSnapshotWireValue: String?,
    val categoryIsParentSnapshot: Boolean?,
    val includesFamilySpending: Boolean,
    val monthAnchor: String,
    val limitMinor: Long,
    val rolloverEnabled: Boolean,
    val currencyCode: String,
    val isArchived: Boolean,
    val createdAt: String,
    val updatedAt: String,
    val deletedAt: String?,
    val syncVersion: Long,
    val lastModifiedByDeviceId: String?,
) {
    fun toPayload(): JsonObject = buildJsonObject {
        put("user_id", JsonPrimitive(ownerUserId))
        put("id", JsonPrimitive(id))
        putBudgetString("category_id", categoryId)
        putBudgetString("category_id_snapshot", categoryIdSnapshot)
        putBudgetString("category_name_snapshot", categoryNameSnapshot)
        putBudgetString("category_name_english_snapshot", categoryNameEnglishSnapshot)
        putBudgetString("category_name_japanese_snapshot", categoryNameJapaneseSnapshot)
        putBudgetString("category_path_snapshot", categoryPathSnapshot)
        putBudgetString("category_path_english_snapshot", categoryPathEnglishSnapshot)
        putBudgetString("category_path_japanese_snapshot", categoryPathJapaneseSnapshot)
        putBudgetString("category_icon_symbol_name_snapshot", categoryIconSymbolNameSnapshot)
        putBudgetString("category_color_hex_snapshot", categoryColorHexSnapshot)
        putBudgetString("category_parent_id_snapshot", categoryParentIdSnapshot)
        putBudgetString("category_parent_name_snapshot", categoryParentNameSnapshot)
        putBudgetString("category_parent_name_english_snapshot", categoryParentNameEnglishSnapshot)
        putBudgetString("category_parent_name_japanese_snapshot", categoryParentNameJapaneseSnapshot)
        putBudgetString("category_parent_icon_symbol_name_snapshot", categoryParentIconSymbolNameSnapshot)
        putBudgetString("category_parent_color_hex_snapshot", categoryParentColorHexSnapshot)
        putBudgetString("category_hierarchy_role_snapshot_raw_value", categoryHierarchyRoleSnapshotWireValue)
        put(
            "category_is_parent_snapshot",
            categoryIsParentSnapshot?.let(::JsonPrimitive) ?: JsonNull,
        )
        put("includes_family_spending", JsonPrimitive(includesFamilySpending))
        put("month_anchor", JsonPrimitive(monthAnchor))
        put("limit_minor", JsonPrimitive(limitMinor))
        put("rollover_enabled", JsonPrimitive(rolloverEnabled))
        put("currency_code", JsonPrimitive(currencyCode))
        put("is_archived", JsonPrimitive(isArchived))
        put("created_at", JsonPrimitive(createdAt))
        put("updated_at", JsonPrimitive(updatedAt))
        putBudgetString("deleted_at", deletedAt)
        put("sync_version", JsonPrimitive(syncVersion))
        putBudgetString("last_modified_by_device_id", lastModifiedByDeviceId)
    }

    fun toCloudRecord(): CloudRecord = CloudRecord(
        entity = CloudEntity.BUDGET_PLAN.table,
        id = id,
        ownerUserId = ownerUserId,
        payload = toPayload(),
        updatedAt = updatedAt,
        deletedAt = deletedAt,
        syncVersion = syncVersion,
    )

    fun allocationSnapshot(): BudgetAllocationSnapshot {
        val snapshotCategoryId = categoryIdSnapshot ?: categoryId
        val isParent = categoryIsParentSnapshot
            ?: (categoryHierarchyRoleSnapshotWireValue == CategoryHierarchyRole.PARENT.wireValue)
        return BudgetAllocationSnapshot(
            id = id,
            categoryId = snapshotCategoryId,
            branchCategoryId = if (isParent) {
                snapshotCategoryId
            } else {
                categoryParentIdSnapshot ?: snapshotCategoryId
            },
            categoryIsParent = isParent,
            limitMinor = limitMinor,
            monthAnchor = monthAnchor,
        )
    }

    companion object {
        fun fromCloudRecord(record: CloudRecord): BudgetPlanRecord {
            require(record.entity == CloudEntity.BUDGET_PLAN.table)
            val payload = record.payload
            return BudgetPlanRecord(
                id = budgetUuid(payload.requiredBudgetString("id")),
                ownerUserId = budgetUuid(payload.requiredBudgetString("user_id")),
                categoryId = payload.budgetString("category_id")?.let(::budgetUuid),
                categoryIdSnapshot = payload.budgetString("category_id_snapshot")?.let(::budgetUuid),
                categoryNameSnapshot = payload.budgetString("category_name_snapshot"),
                categoryNameEnglishSnapshot = payload.budgetString("category_name_english_snapshot"),
                categoryNameJapaneseSnapshot = payload.budgetString("category_name_japanese_snapshot"),
                categoryPathSnapshot = payload.budgetString("category_path_snapshot"),
                categoryPathEnglishSnapshot = payload.budgetString("category_path_english_snapshot"),
                categoryPathJapaneseSnapshot = payload.budgetString("category_path_japanese_snapshot"),
                categoryIconSymbolNameSnapshot = payload.budgetString("category_icon_symbol_name_snapshot"),
                categoryColorHexSnapshot = payload.budgetString("category_color_hex_snapshot"),
                categoryParentIdSnapshot = payload.budgetString("category_parent_id_snapshot")?.let(::budgetUuid),
                categoryParentNameSnapshot = payload.budgetString("category_parent_name_snapshot"),
                categoryParentNameEnglishSnapshot = payload.budgetString("category_parent_name_english_snapshot"),
                categoryParentNameJapaneseSnapshot = payload.budgetString("category_parent_name_japanese_snapshot"),
                categoryParentIconSymbolNameSnapshot = payload.budgetString(
                    "category_parent_icon_symbol_name_snapshot",
                ),
                categoryParentColorHexSnapshot = payload.budgetString("category_parent_color_hex_snapshot"),
                categoryHierarchyRoleSnapshotWireValue = payload.budgetString(
                    "category_hierarchy_role_snapshot_raw_value",
                ),
                categoryIsParentSnapshot = payload.optionalBudgetBoolean("category_is_parent_snapshot"),
                includesFamilySpending = payload.optionalBudgetBoolean("includes_family_spending") ?: false,
                monthAnchor = budgetUtc(payload.requiredBudgetString("month_anchor")),
                limitMinor = payload.requiredBudgetLong("limit_minor"),
                rolloverEnabled = payload.requiredBudgetBoolean("rollover_enabled"),
                currencyCode = payload.requiredBudgetString("currency_code").uppercase(Locale.ROOT),
                isArchived = payload.requiredBudgetBoolean("is_archived"),
                createdAt = budgetUtc(payload.requiredBudgetString("created_at")),
                updatedAt = budgetUtc(payload.requiredBudgetString("updated_at")),
                deletedAt = (payload.budgetString("deleted_at") ?: record.deletedAt)?.let(::budgetUtc),
                syncVersion = payload.requiredBudgetLong("sync_version"),
                lastModifiedByDeviceId = payload.budgetString("last_modified_by_device_id")?.let(::budgetUuid),
            )
        }
    }
}

data class BudgetAllocationSnapshot(
    val id: String,
    val categoryId: String?,
    val branchCategoryId: String?,
    val categoryIsParent: Boolean,
    val limitMinor: Long,
    val monthAnchor: String,
)

sealed interface BudgetAllocationValidation {
    data object Valid : BudgetAllocationValidation

    data class ChildBudgetsExceedParent(
        val childTotalMinor: Long,
        val parentLimitMinor: Long,
    ) : BudgetAllocationValidation

    data class ParentLimitBelowChildren(
        val childTotalMinor: Long,
        val parentLimitMinor: Long,
    ) : BudgetAllocationValidation
}

@Suppress("UNUSED_PARAMETER")
fun validateBudgetAllocation(
    categoryId: String?,
    branchCategoryId: String?,
    categoryIsParent: Boolean,
    categoryIsChild: Boolean,
    limitMinor: Long,
    monthAnchor: String,
    plans: List<BudgetAllocationSnapshot>,
    editingBudgetId: String? = null,
    zoneId: ZoneId = ZoneId.systemDefault(),
): BudgetAllocationValidation {
    branchCategoryId ?: return BudgetAllocationValidation.Valid
    val selectedMonth = budgetYearMonth(monthAnchor, zoneId)
    val branchPlans = plans.filter { plan ->
        plan.id != editingBudgetId &&
            plan.branchCategoryId == branchCategoryId &&
            budgetYearMonth(plan.monthAnchor, zoneId) == selectedMonth
    }
    val childTotal = branchPlans
        .filterNot(BudgetAllocationSnapshot::categoryIsParent)
        .fold(BigInteger.ZERO) { total, plan -> total.add(BigInteger.valueOf(plan.limitMinor)) }

    if (categoryIsParent) {
        return if (BigInteger.valueOf(limitMinor) >= childTotal) {
            BudgetAllocationValidation.Valid
        } else {
            BudgetAllocationValidation.ParentLimitBelowChildren(childTotal.toBudgetLongClamped(), limitMinor)
        }
    }
    if (!categoryIsChild) return BudgetAllocationValidation.Valid
    val parent = branchPlans.firstOrNull(BudgetAllocationSnapshot::categoryIsParent)
        ?: return BudgetAllocationValidation.Valid
    val projectedChildTotal = childTotal.add(BigInteger.valueOf(limitMinor))
    return if (projectedChildTotal <= BigInteger.valueOf(parent.limitMinor)) {
        BudgetAllocationValidation.Valid
    } else {
        BudgetAllocationValidation.ChildBudgetsExceedParent(
            childTotalMinor = projectedChildTotal.toBudgetLongClamped(),
            parentLimitMinor = parent.limitMinor,
        )
    }
}

private fun budgetYearMonth(value: String, zoneId: ZoneId): YearMonth =
    YearMonth.from(Instant.parse(value).atZone(zoneId))

private fun BigInteger.toBudgetLongClamped(): Long = when {
    this > BigInteger.valueOf(Long.MAX_VALUE) -> Long.MAX_VALUE
    this < BigInteger.valueOf(Long.MIN_VALUE) -> Long.MIN_VALUE
    else -> toLong()
}

private fun budgetUuid(value: String): String = UUID.fromString(value.trim()).toString()
private fun budgetUtc(value: String): String = value.also {
    require(Instant.parse(it).toString().endsWith("Z"))
}
private fun JsonObject.budgetString(key: String): String? =
    when (val value = get(key)) {
        null, JsonNull -> null
        is JsonPrimitive -> value.takeIf(JsonPrimitive::isString)?.contentOrNull
            ?: throw IllegalArgumentException("Budget field $key must be a string")
        else -> throw IllegalArgumentException("Budget field $key must be a string")
    }
private fun JsonObject.requiredBudgetString(key: String): String =
    budgetString(key)?.takeIf(String::isNotBlank)
        ?: throw IllegalArgumentException("Missing required budget field $key")
private fun JsonObject.requiredBudgetLong(key: String): Long =
    (get(key) as? JsonPrimitive)
        ?.takeUnless(JsonPrimitive::isString)
        ?.longOrNull
        ?: throw IllegalArgumentException("Budget field $key must be an Int64")
private fun JsonObject.requiredBudgetBoolean(key: String): Boolean =
    optionalBudgetBoolean(key)
        ?: throw IllegalArgumentException("Missing required budget field $key")
private fun JsonObject.optionalBudgetBoolean(key: String): Boolean? =
    when (val value = get(key)) {
        null, JsonNull -> null
        is JsonPrimitive -> value.takeUnless(JsonPrimitive::isString)?.booleanOrNull
            ?: throw IllegalArgumentException("Budget field $key must be a boolean")
        else -> throw IllegalArgumentException("Budget field $key must be a boolean")
    }
private fun kotlinx.serialization.json.JsonObjectBuilder.putBudgetString(key: String, value: String?) {
    put(key, value?.let(::JsonPrimitive) ?: JsonNull)
}
