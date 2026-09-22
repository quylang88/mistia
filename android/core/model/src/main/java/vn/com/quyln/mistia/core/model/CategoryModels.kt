package vn.com.quyln.mistia.core.model

import java.time.Instant
import java.util.Locale
import java.util.UUID
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.longOrNull

enum class TransactionCategoryKind(
    val wireValue: String,
    val defaultIcon: String,
    val defaultColorHex: String,
) {
    EXPENSE("expense", "mistia.flow.expense", "#FF7A59"),
    INCOME("income", "mistia.flow.income", "#2DAA9E"),
    ;

    companion object {
        fun fromWireValue(value: String): TransactionCategoryKind? = entries.firstOrNull { it.wireValue == value }
    }
}

enum class CategoryHierarchyRole(val wireValue: String) {
    PARENT("parent"),
    CHILD("child"),
    ;

    companion object {
        fun fromWireValue(value: String?): CategoryHierarchyRole? = entries.firstOrNull { it.wireValue == value }
    }
}

enum class CategoryNameLanguage { VIETNAMESE, ENGLISH, JAPANESE }

data class TransactionCategoryRecord(
    val id: String,
    val ownerUserId: String,
    val name: String,
    val nameEnglish: String?,
    val nameJapanese: String?,
    val kindWireValue: String,
    val iconSymbolName: String,
    val iconColorHex: String,
    val isFavorite: Boolean,
    val familyBudgetSpendingEnabled: Boolean,
    val parentCategoryId: String?,
    val hierarchyRoleWireValue: String?,
    val systemKey: String?,
    val isSystem: Boolean,
    val sortOrder: Int,
    val isArchived: Boolean,
    val archivedAt: String?,
    val createdAt: String,
    val updatedAt: String,
    val deletedAt: String?,
    val syncVersion: Long,
    val lastModifiedByDeviceId: String?,
) {
    val kind: TransactionCategoryKind?
        get() = TransactionCategoryKind.fromWireValue(kindWireValue)
    val hierarchyRole: CategoryHierarchyRole
        get() = CategoryHierarchyRole.fromWireValue(hierarchyRoleWireValue)
            ?: if (parentCategoryId == null) CategoryHierarchyRole.PARENT else CategoryHierarchyRole.CHILD
    val isBalanceAdjustmentSystemCategory: Boolean
        get() = id == BALANCE_ADJUSTMENT_EXPENSE_ID ||
            id == BALANCE_ADJUSTMENT_INCOME_ID ||
            systemKey == BALANCE_ADJUSTMENT_EXPENSE_KEY ||
            systemKey == BALANCE_ADJUSTMENT_INCOME_KEY
    val hidesWhenEmpty: Boolean
        get() = systemKey == UNCATEGORIZED_EXPENSE_PARENT_KEY ||
            systemKey == UNCATEGORIZED_INCOME_PARENT_KEY

    fun toPayload(): JsonObject = buildJsonObject {
        put("user_id", JsonPrimitive(ownerUserId))
        put("id", JsonPrimitive(id))
        put("name", JsonPrimitive(name))
        putNullableCategoryString("name_english", nameEnglish)
        putNullableCategoryString("name_japanese", nameJapanese)
        put("kind_raw_value", JsonPrimitive(kindWireValue))
        put("icon_symbol_name", JsonPrimitive(iconSymbolName))
        put("icon_color_hex", JsonPrimitive(iconColorHex))
        put("is_favorite", JsonPrimitive(isFavorite))
        put("family_budget_spending_enabled", JsonPrimitive(familyBudgetSpendingEnabled))
        putNullableCategoryString("parent_category_id", parentCategoryId)
        putNullableCategoryString("hierarchy_role_raw_value", hierarchyRoleWireValue)
        putNullableCategoryString("system_key", systemKey)
        put("is_system", JsonPrimitive(isSystem))
        put("sort_order", JsonPrimitive(sortOrder))
        put("is_archived", JsonPrimitive(isArchived))
        putNullableCategoryString("archived_at", archivedAt)
        put("created_at", JsonPrimitive(createdAt))
        put("updated_at", JsonPrimitive(updatedAt))
        putNullableCategoryString("deleted_at", deletedAt)
        put("sync_version", JsonPrimitive(syncVersion))
        putNullableCategoryString("last_modified_by_device_id", lastModifiedByDeviceId)
    }

    fun toCloudRecord(): CloudRecord = CloudRecord(
        entity = CloudEntity.TRANSACTION_CATEGORY.table,
        id = id,
        ownerUserId = ownerUserId,
        payload = toPayload(),
        updatedAt = updatedAt,
        deletedAt = deletedAt,
        syncVersion = syncVersion,
    )

    fun toFavoriteMutation(isFavorite: Boolean, deviceId: String, now: String): CategoryMutation {
        if (hierarchyRole != CategoryHierarchyRole.CHILD && isFavorite) {
            throw CategoryValidationException(CategoryValidationError.FAVORITE_REQUIRES_CHILD)
        }
        return copy(
            isFavorite = isFavorite && hierarchyRole == CategoryHierarchyRole.CHILD,
            updatedAt = categoryUtc(now),
            lastModifiedByDeviceId = categoryUuid(deviceId),
        ).asMutation()
    }

    fun toArchiveMutation(deviceId: String, now: String): CategoryMutation = copy(
        isArchived = true,
        archivedAt = categoryUtc(now),
        updatedAt = categoryUtc(now),
        lastModifiedByDeviceId = categoryUuid(deviceId),
    ).asMutation()

    private fun asMutation(): CategoryMutation {
        val record = toCloudRecord()
        return CategoryMutation(
            this,
            PendingMutation(
                entity = CloudEntity.TRANSACTION_CATEGORY,
                recordId = id,
                subjectUserId = ownerUserId,
                kind = MutationKind.UPSERT,
                payload = record.payload,
                modifiedAt = updatedAt,
                baseVersion = syncVersion,
                deviceId = lastModifiedByDeviceId.orEmpty(),
            ),
        )
    }

    companion object {
        const val BALANCE_ADJUSTMENT_EXPENSE_KEY = "balance_adjustment_expense"
        const val BALANCE_ADJUSTMENT_INCOME_KEY = "balance_adjustment_income"
        const val BALANCE_ADJUSTMENT_EXPENSE_ID = "5da63bda-4125-58d5-a91f-2e20539169cf"
        const val BALANCE_ADJUSTMENT_INCOME_ID = "27b5a797-2851-5019-bf71-e180017159c9"
        private const val UNCATEGORIZED_EXPENSE_PARENT_KEY = "parent_expense_uncategorized"
        private const val UNCATEGORIZED_INCOME_PARENT_KEY = "parent_income_uncategorized"

        fun fromCloudRecord(record: CloudRecord): TransactionCategoryRecord {
            require(record.entity == CloudEntity.TRANSACTION_CATEGORY.table)
            val payload = record.payload
            return TransactionCategoryRecord(
                id = categoryUuid(payload.categoryString("id") ?: record.id),
                ownerUserId = categoryUuid(payload.categoryString("user_id") ?: record.ownerUserId),
                name = payload.categoryString("name").orEmpty(),
                nameEnglish = payload.categoryString("name_english"),
                nameJapanese = payload.categoryString("name_japanese"),
                kindWireValue = payload.categoryString("kind_raw_value").orEmpty(),
                iconSymbolName = payload.categoryString("icon_symbol_name").orEmpty(),
                iconColorHex = payload.categoryString("icon_color_hex").orEmpty(),
                isFavorite = payload.categoryBoolean("is_favorite"),
                familyBudgetSpendingEnabled = payload.categoryBoolean("family_budget_spending_enabled"),
                parentCategoryId = payload.categoryString("parent_category_id")?.let(::categoryUuid),
                hierarchyRoleWireValue = payload.categoryString("hierarchy_role_raw_value"),
                systemKey = payload.categoryString("system_key"),
                isSystem = payload.categoryBoolean("is_system"),
                sortOrder = payload.categoryInt("sort_order"),
                isArchived = payload.categoryBoolean("is_archived"),
                archivedAt = payload.categoryString("archived_at"),
                createdAt = payload.categoryString("created_at") ?: record.updatedAt.orEmpty(),
                updatedAt = payload.categoryString("updated_at") ?: record.updatedAt.orEmpty(),
                deletedAt = payload.categoryString("deleted_at") ?: record.deletedAt,
                syncVersion = payload.categoryLongOrNull("sync_version") ?: record.syncVersion,
                lastModifiedByDeviceId = payload.categoryString("last_modified_by_device_id"),
            )
        }
    }
}

data class CategoryDraft(
    val id: String? = null,
    val name: String,
    val nameLanguage: CategoryNameLanguage = CategoryNameLanguage.VIETNAMESE,
    val kind: TransactionCategoryKind,
    val hierarchyRole: CategoryHierarchyRole,
    val parentCategoryId: String? = null,
    val isFavorite: Boolean = false,
    val iconSymbolName: String? = null,
    val iconColorHex: String? = null,
    val sortOrder: Int? = null,
) {
    fun toMutation(
        ownerUserId: UserId,
        existing: TransactionCategoryRecord?,
        parent: TransactionCategoryRecord?,
        deviceId: String,
        now: String,
    ): CategoryMutation {
        val owner = categoryUuid(ownerUserId.value)
        val device = categoryUuid(deviceId)
        val updatedAt = categoryUtc(now)
        val trimmedName = name.trim()
        if (trimmedName.isEmpty()) throw CategoryValidationException(CategoryValidationError.NAME_REQUIRED)
        if (existing != null && existing.ownerUserId != owner) {
            throw CategoryValidationException(CategoryValidationError.OWNER_MISMATCH)
        }
        if (existing != null && existing.hierarchyRole != hierarchyRole) {
            throw CategoryValidationException(CategoryValidationError.HIERARCHY_ROLE_IMMUTABLE)
        }
        val parentId = if (hierarchyRole == CategoryHierarchyRole.CHILD) {
            val selected = parent ?: throw CategoryValidationException(CategoryValidationError.PARENT_REQUIRED)
            if (selected.ownerUserId != owner) throw CategoryValidationException(CategoryValidationError.OWNER_MISMATCH)
            if (selected.kind != kind) throw CategoryValidationException(CategoryValidationError.PARENT_KIND_MISMATCH)
            if (selected.hierarchyRole != CategoryHierarchyRole.PARENT || selected.parentCategoryId != null) {
                throw CategoryValidationException(CategoryValidationError.PARENT_NOT_PARENT)
            }
            if (selected.isArchived || selected.deletedAt != null) {
                throw CategoryValidationException(CategoryValidationError.PARENT_NOT_ACTIVE)
            }
            if (selected.id == existing?.id) throw CategoryValidationException(CategoryValidationError.SELF_PARENT)
            if (parentCategoryId != null && categoryUuid(parentCategoryId) != selected.id) {
                throw CategoryValidationException(CategoryValidationError.PARENT_REQUIRED)
            }
            selected.id
        } else {
            null
        }
        val normalizedColor = (
            iconColorHex?.trim()?.takeIf(String::isNotEmpty)
                ?: existing?.iconColorHex
                ?: kind.defaultColorHex
            )
            .uppercase(Locale.ROOT)
        if (!normalizedColor.matches(Regex("^#[0-9A-F]{6}$"))) {
            throw CategoryValidationException(CategoryValidationError.INVALID_COLOR)
        }
        val names = localizedNames(trimmedName, existing)
        val record = TransactionCategoryRecord(
            id = categoryUuid(existing?.id ?: id ?: UUID.randomUUID().toString()),
            ownerUserId = owner,
            name = names.first,
            nameEnglish = names.second,
            nameJapanese = names.third,
            kindWireValue = kind.wireValue,
            iconSymbolName = iconSymbolName?.trim()?.takeIf(String::isNotEmpty)
                ?: existing?.iconSymbolName
                ?: kind.defaultIcon,
            iconColorHex = normalizedColor,
            isFavorite = hierarchyRole == CategoryHierarchyRole.CHILD && isFavorite,
            familyBudgetSpendingEnabled = existing?.familyBudgetSpendingEnabled ?: false,
            parentCategoryId = parentId,
            hierarchyRoleWireValue = hierarchyRole.wireValue,
            systemKey = existing?.systemKey,
            isSystem = existing?.isSystem ?: false,
            sortOrder = sortOrder ?: existing?.sortOrder ?: 0,
            isArchived = existing?.isArchived ?: false,
            archivedAt = existing?.archivedAt,
            createdAt = existing?.createdAt ?: updatedAt,
            updatedAt = updatedAt,
            deletedAt = null,
            syncVersion = existing?.syncVersion ?: 0,
            lastModifiedByDeviceId = device,
        )
        val cloud = record.toCloudRecord()
        return CategoryMutation(
            record,
            PendingMutation(
                CloudEntity.TRANSACTION_CATEGORY,
                record.id,
                owner,
                MutationKind.UPSERT,
                cloud.payload,
                updatedAt,
                record.syncVersion,
                device,
            ),
        )
    }

    private fun localizedNames(
        value: String,
        existing: TransactionCategoryRecord?,
    ): Triple<String, String?, String?> = when (nameLanguage) {
        CategoryNameLanguage.VIETNAMESE -> Triple(value, existing?.nameEnglish, existing?.nameJapanese)
        CategoryNameLanguage.ENGLISH -> Triple(existing?.name?.takeIf(String::isNotBlank) ?: value, value, existing?.nameJapanese)
        CategoryNameLanguage.JAPANESE -> Triple(existing?.name?.takeIf(String::isNotBlank) ?: value, existing?.nameEnglish, value)
    }
}

data class CategoryMutation(val record: TransactionCategoryRecord, val pending: PendingMutation)

enum class CategoryValidationError {
    NAME_REQUIRED,
    DUPLICATE_NAME,
    CATEGORY_NOT_FOUND,
    PARENT_REQUIRED,
    PARENT_KIND_MISMATCH,
    PARENT_NOT_PARENT,
    PARENT_NOT_ACTIVE,
    SELF_PARENT,
    FAVORITE_REQUIRES_CHILD,
    HIERARCHY_ROLE_IMMUTABLE,
    INVALID_COLOR,
    OWNER_MISMATCH,
    BUDGET_BRANCH_CURRENT_MONTH_BLOCK,
    ARCHIVE_HAS_CHILDREN,
    ARCHIVE_HAS_TRANSACTIONS,
    ARCHIVE_HAS_BUDGETS,
    ARCHIVE_HAS_BILLS,
}

class CategoryValidationException(val reason: CategoryValidationError) : IllegalArgumentException(reason.name)

private fun categoryUuid(value: String): String = UUID.fromString(value.trim()).toString()
private fun categoryUtc(value: String): String = value.also { require(Instant.parse(it).toString().endsWith("Z")) }
private fun JsonObject.categoryString(key: String): String? =
    (get(key) as? JsonPrimitive)?.contentOrNull?.takeIf(String::isNotBlank)
private fun JsonObject.categoryBoolean(key: String): Boolean = (get(key) as? JsonPrimitive)?.booleanOrNull ?: false
private fun JsonObject.categoryInt(key: String): Int = (get(key) as? JsonPrimitive)?.intOrNull ?: 0
private fun JsonObject.categoryLongOrNull(key: String): Long? = (get(key) as? JsonPrimitive)?.longOrNull
private fun kotlinx.serialization.json.JsonObjectBuilder.putNullableCategoryString(key: String, value: String?) {
    put(key, value?.let(::JsonPrimitive) ?: JsonNull)
}
