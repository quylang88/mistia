package vn.com.quyln.mistia.core.model

import java.time.Instant
import java.time.YearMonth
import java.time.ZoneId
import java.util.Locale
import java.util.UUID
import kotlinx.coroutines.flow.Flow

interface BudgetRepository {
    fun observeBudgets(ownerUserId: UserId): Flow<List<BudgetPlanRecord>>
    suspend fun saveBudget(ownerUserId: UserId, draft: BudgetDraft, deviceId: String, now: String): Result<BudgetPlanRecord>
    suspend fun archiveBudget(ownerUserId: UserId, budgetId: RecordId, deviceId: String, now: String): Result<Unit>
    suspend fun deleteBudget(ownerUserId: UserId, budgetId: RecordId, deviceId: String, now: String): Result<Unit>
}

data class BudgetDraft(
    val categoryId: String?,
    val monthAnchor: String,
    val limitMinor: Long,
    val currencyCode: String,
    val id: String? = null,
    val editingExisting: Boolean = false,
    val rolloverEnabled: Boolean = false,
    val zoneId: ZoneId = ZoneId.systemDefault(),
)

enum class BudgetValidationError {
    CATEGORY_REQUIRED, INVALID_AMOUNT, INVALID_CURRENCY, DUPLICATE_CATEGORY,
    ALLOCATION_EXCEEDED, PAST_READ_ONLY, NOT_FOUND, INVALID_CATEGORY, AMOUNT_OVERFLOW,
}

class BudgetValidationException(val reason: BudgetValidationError) : IllegalArgumentException(reason.name)

fun budgetMonth(value: String, zoneId: ZoneId): YearMonth = YearMonth.from(Instant.parse(value).atZone(zoneId))

fun BudgetDraft.toBudgetRecord(
    ownerUserId: UserId,
    category: TransactionCategoryRecord,
    parent: TransactionCategoryRecord?,
    existing: BudgetPlanRecord?,
    includesFamilySpending: Boolean,
    deviceId: String,
    now: String,
): BudgetPlanRecord {
    val owner = UUID.fromString(ownerUserId.value).toString()
    require(category.ownerUserId == owner && (parent == null || parent.ownerUserId == owner))
    require(existing == null || existing.ownerUserId == owner)
    require(Instant.parse(now).toString().endsWith("Z"))
    val currency = (existing?.currencyCode ?: currencyCode).trim().uppercase(Locale.ROOT)
    if (!currency.matches(Regex("[A-Z]{3}"))) throw BudgetValidationException(BudgetValidationError.INVALID_CURRENCY)
    if (limitMinor <= 0) throw BudgetValidationException(BudgetValidationError.INVALID_AMOUNT)
    fun path(parentName: String?, childName: String?): String? {
        val p = parentName?.trim()?.takeIf(String::isNotEmpty) ?: return null
        val c = childName?.trim()?.takeIf(String::isNotEmpty) ?: return null
        return "$p / $c"
    }
    return BudgetPlanRecord(
        id = UUID.fromString(existing?.id ?: id ?: UUID.randomUUID().toString()).toString(),
        ownerUserId = owner,
        categoryId = category.id,
        categoryIdSnapshot = category.id,
        categoryNameSnapshot = category.name,
        categoryNameEnglishSnapshot = category.nameEnglish,
        categoryNameJapaneseSnapshot = category.nameJapanese,
        categoryPathSnapshot = parent?.let { "${it.name} / ${category.name}" } ?: category.name,
        categoryPathEnglishSnapshot = if (parent == null) category.nameEnglish else path(parent.nameEnglish, category.nameEnglish),
        categoryPathJapaneseSnapshot = if (parent == null) category.nameJapanese else path(parent.nameJapanese, category.nameJapanese),
        categoryIconSymbolNameSnapshot = category.iconSymbolName,
        categoryColorHexSnapshot = category.iconColorHex,
        categoryParentIdSnapshot = parent?.id,
        categoryParentNameSnapshot = parent?.name,
        categoryParentNameEnglishSnapshot = parent?.nameEnglish,
        categoryParentNameJapaneseSnapshot = parent?.nameJapanese,
        categoryParentIconSymbolNameSnapshot = parent?.iconSymbolName,
        categoryParentColorHexSnapshot = parent?.iconColorHex,
        categoryHierarchyRoleSnapshotWireValue = category.hierarchyRole.wireValue,
        categoryIsParentSnapshot = category.hierarchyRole == CategoryHierarchyRole.PARENT,
        includesFamilySpending = includesFamilySpending,
        monthAnchor = budgetMonth(monthAnchor, zoneId).atDay(1).atStartOfDay(zoneId).toInstant().toString(),
        limitMinor = limitMinor,
        rolloverEnabled = rolloverEnabled,
        currencyCode = currency,
        isArchived = false,
        createdAt = existing?.createdAt ?: now,
        updatedAt = now,
        deletedAt = null,
        syncVersion = existing?.syncVersion ?: 0,
        lastModifiedByDeviceId = UUID.fromString(deviceId).toString(),
    )
}

fun BudgetPlanRecord.pendingMutation(kind: MutationKind = MutationKind.UPSERT): PendingMutation = PendingMutation(
    entity = CloudEntity.BUDGET_PLAN,
    recordId = id,
    subjectUserId = ownerUserId,
    kind = kind,
    payload = toPayload(),
    modifiedAt = updatedAt,
    baseVersion = syncVersion,
    deviceId = requireNotNull(lastModifiedByDeviceId),
)
