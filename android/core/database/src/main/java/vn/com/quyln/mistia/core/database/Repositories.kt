package vn.com.quyln.mistia.core.database

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import java.time.Instant
import java.time.LocalDate
import java.time.YearMonth
import java.time.ZoneId
import java.util.Locale
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import vn.com.quyln.mistia.core.model.CategoryDraft
import vn.com.quyln.mistia.core.model.CategoryHierarchyRole
import vn.com.quyln.mistia.core.model.CategoryNameLanguage
import vn.com.quyln.mistia.core.model.CategoryValidationError
import vn.com.quyln.mistia.core.model.CategoryValidationException
import vn.com.quyln.mistia.core.model.CloudEntity
import vn.com.quyln.mistia.core.model.CloudRecord
import vn.com.quyln.mistia.core.model.EntityCount
import vn.com.quyln.mistia.core.model.FamilyRepository
import vn.com.quyln.mistia.core.model.FinanceRepository
import vn.com.quyln.mistia.core.model.InvestmentRepository
import vn.com.quyln.mistia.core.model.LocalStore
import vn.com.quyln.mistia.core.model.PendingCategoryTranslation
import vn.com.quyln.mistia.core.model.LedgerWalletRecord
import vn.com.quyln.mistia.core.model.ReadOnlyCloudCollection
import vn.com.quyln.mistia.core.model.RecordId
import vn.com.quyln.mistia.core.model.TransactionCategoryRecord
import vn.com.quyln.mistia.core.model.UserId
import vn.com.quyln.mistia.core.model.WalletDraft

class OfflineFirstFinanceRepository(private val localStore: LocalStore) : FinanceRepository {
    override fun observe(entity: CloudEntity, ownerUserId: UserId): Flow<List<CloudRecord>> =
        localStore.observe(entity.table, ownerUserId)

    override fun observeEntityCounts(ownerUserId: UserId): Flow<List<EntityCount>> =
        localStore.observeEntityCounts(ownerUserId)

    override fun observeWallets(ownerUserId: UserId): Flow<List<LedgerWalletRecord>> =
        localStore.observe(CloudEntity.LEDGER_WALLET.table, ownerUserId).map { records ->
            records.mapNotNull { record ->
                runCatching { LedgerWalletRecord.fromCloudRecord(record) }.getOrNull()
            }.filterNot(LedgerWalletRecord::isArchived)
                .sortedWith(compareBy(LedgerWalletRecord::sortOrder, LedgerWalletRecord::createdAt, LedgerWalletRecord::id))
        }

    override fun observeCategories(ownerUserId: UserId): Flow<List<TransactionCategoryRecord>> =
        localStore.observe(CloudEntity.TRANSACTION_CATEGORY.table, ownerUserId).map { records ->
            records.mapNotNull { record ->
                runCatching { TransactionCategoryRecord.fromCloudRecord(record) }.getOrNull()
            }.filterNot(TransactionCategoryRecord::isArchived)
                .sortedWith(
                    compareBy(
                        TransactionCategoryRecord::sortOrder,
                        TransactionCategoryRecord::createdAt,
                        TransactionCategoryRecord::id,
                    )
                )
        }

    override suspend fun saveWallet(
        ownerUserId: UserId,
        draft: WalletDraft,
        deviceId: String,
        now: String,
    ): Result<LedgerWalletRecord> = runCatching {
        val existing = draft.id?.let { recordId ->
            localStore.record(ownerUserId, CloudEntity.LEDGER_WALLET.table, recordId.lowercase())
                ?.let(LedgerWalletRecord::fromCloudRecord)
        }
        val mutation = draft.toMutation(ownerUserId, existing, deviceId, now)
        localStore.commitMutation(mutation.record, mutation.pending)
        LedgerWalletRecord.fromCloudRecord(mutation.record)
    }

    override suspend fun archiveWallet(
        ownerUserId: UserId,
        walletId: RecordId,
        deviceId: String,
        now: String,
    ): Result<Unit> = runCatching {
        val record = localStore.record(
            ownerUserId,
            CloudEntity.LEDGER_WALLET.table,
            walletId.value.lowercase(),
        ) ?: error("Wallet not found")
        val mutation = LedgerWalletRecord.fromCloudRecord(record).toArchiveMutation(deviceId, now)
        localStore.commitMutation(mutation.record, mutation.pending)
    }

    override suspend fun saveCategory(
        ownerUserId: UserId,
        draft: CategoryDraft,
        deviceId: String,
        now: String,
    ): Result<TransactionCategoryRecord> = runCatching {
        val categories = categorySnapshot(ownerUserId)
        val existing = draft.id?.let { id -> categories.firstOrNull { it.id == id.lowercase() } }
        val normalizedInput = normalizeCategoryName(draft.name)
        if (categories.any { category ->
                category.id != existing?.id &&
                    category.deletedAt == null &&
                    normalizeCategoryName(categoryName(category, draft.nameLanguage)) == normalizedInput
            }
        ) {
            throw CategoryValidationException(CategoryValidationError.DUPLICATE_NAME)
        }
        val parent = draft.parentCategoryId?.let { parentId ->
            categories.firstOrNull { it.id == parentId.lowercase() }
        }
        val parentId = if (draft.hierarchyRole == CategoryHierarchyRole.CHILD) parent?.id else null
        val shouldKeepSort = existing != null &&
            existing.kind == draft.kind &&
            existing.parentCategoryId == parentId
        if (existing != null) {
            val hasRestrictedChanges = draft.name.trim() != categoryName(existing, draft.nameLanguage) ||
                existing.kind != draft.kind ||
                existing.parentCategoryId != parentId
            if (hasRestrictedChanges && hasCurrentMonthBudget(ownerUserId, existing, categories, now)) {
                throw CategoryValidationException(CategoryValidationError.BUDGET_BRANCH_CURRENT_MONTH_BLOCK)
            }
        }
        val nextSortOrder = when {
            existing == null && draft.sortOrder != null -> draft.sortOrder
            shouldKeepSort -> draft.sortOrder ?: existing?.sortOrder
            else -> {
                categories.asSequence()
                    .filterNot(TransactionCategoryRecord::isArchived)
                    .filter { it.id != existing?.id && it.kind == draft.kind && it.parentCategoryId == parentId }
                    .maxOfOrNull(TransactionCategoryRecord::sortOrder)
                    ?.plus(1) ?: 0
            }
        }
        val mutation = draft.copy(sortOrder = nextSortOrder).toMutation(
            ownerUserId = ownerUserId,
            existing = existing,
            parent = parent,
            deviceId = deviceId,
            now = now,
        )
        localStore.commitCategoryMutation(
            record = mutation.record.toCloudRecord(),
            mutation = mutation.pending,
            translation = PendingCategoryTranslation(
                ownerUserId = ownerUserId.value,
                categoryId = mutation.record.id,
                inputName = draft.name.trim(),
                sourceLanguage = draft.nameLanguage,
                savedUpdatedAt = mutation.record.updatedAt,
                deviceId = deviceId,
            ),
        )
        mutation.record
    }

    override suspend fun setCategoryFavorite(
        ownerUserId: UserId,
        categoryId: RecordId,
        isFavorite: Boolean,
        deviceId: String,
        now: String,
    ): Result<Unit> = runCatching {
        val category = categoryRecord(ownerUserId, categoryId)
        val mutation = category.toFavoriteMutation(isFavorite, deviceId, now)
        localStore.commitMutation(mutation.record.toCloudRecord(), mutation.pending)
    }

    override suspend fun archiveCategory(
        ownerUserId: UserId,
        categoryId: RecordId,
        deviceId: String,
        now: String,
    ): Result<Unit> = runCatching {
        val category = categoryRecord(ownerUserId, categoryId)
        val categories = categorySnapshot(ownerUserId)
        if (categories.any { it.parentCategoryId == category.id && !it.isArchived && it.deletedAt == null }) {
            throw CategoryValidationException(CategoryValidationError.ARCHIVE_HAS_CHILDREN)
        }
        val referenceBlockers = listOf(
            CloudEntity.LEDGER_TRANSACTION to CategoryValidationError.ARCHIVE_HAS_TRANSACTIONS,
            CloudEntity.BUDGET_PLAN to CategoryValidationError.ARCHIVE_HAS_BUDGETS,
            CloudEntity.RECURRING_BILL_PLAN to CategoryValidationError.ARCHIVE_HAS_BILLS,
        )
        referenceBlockers.forEach { (entity, reason) ->
            val hasReference = localStore.observe(entity.table, ownerUserId).first().any { record ->
                record.deletedAt == null &&
                    (record.payload["category_id"] as? JsonPrimitive)?.contentOrNull == category.id
            }
            if (hasReference) throw CategoryValidationException(reason)
        }
        val mutation = category.toArchiveMutation(deviceId, now)
        localStore.commitMutation(mutation.record.toCloudRecord(), mutation.pending)
    }

    private suspend fun categoryRecord(ownerUserId: UserId, categoryId: RecordId): TransactionCategoryRecord {
        val record = localStore.record(
            ownerUserId,
            CloudEntity.TRANSACTION_CATEGORY.table,
            categoryId.value.lowercase(),
        ) ?: throw CategoryValidationException(CategoryValidationError.CATEGORY_NOT_FOUND)
        return TransactionCategoryRecord.fromCloudRecord(record)
    }

    private suspend fun categorySnapshot(ownerUserId: UserId): List<TransactionCategoryRecord> =
        localStore.observe(CloudEntity.TRANSACTION_CATEGORY.table, ownerUserId).first()
            .map(TransactionCategoryRecord::fromCloudRecord)

    private fun normalizeCategoryName(value: String): String = value.trim()
        .split(Regex("\\s+"))
        .joinToString(" ")
        .lowercase(Locale.ROOT)

    private fun categoryName(
        category: TransactionCategoryRecord,
        language: CategoryNameLanguage,
    ): String = when (language) {
        CategoryNameLanguage.VIETNAMESE -> category.name
        CategoryNameLanguage.ENGLISH -> category.nameEnglish?.takeIf(String::isNotBlank) ?: category.name
        CategoryNameLanguage.JAPANESE -> category.nameJapanese?.takeIf(String::isNotBlank) ?: category.name
    }

    private suspend fun hasCurrentMonthBudget(
        ownerUserId: UserId,
        category: TransactionCategoryRecord,
        categories: List<TransactionCategoryRecord>,
        now: String,
    ): Boolean {
        val zone = ZoneId.systemDefault()
        val currentMonth = YearMonth.from(Instant.parse(now).atZone(zone))
        val branchId = category.parentCategoryId ?: category.id
        return localStore.observe(CloudEntity.BUDGET_PLAN.table, ownerUserId).first().any { budget ->
            if ((budget.payload["is_archived"] as? JsonPrimitive)?.booleanOrNull == true) return@any false
            val anchor = (budget.payload["month_anchor"] as? JsonPrimitive)?.contentOrNull ?: return@any false
            if (budgetMonth(anchor, zone) != currentMonth) return@any false
            val categoryId = (budget.payload["category_id"] as? JsonPrimitive)?.contentOrNull ?: return@any false
            val budgetCategory = categories.firstOrNull { it.id == categoryId } ?: return@any false
            (budgetCategory.parentCategoryId ?: budgetCategory.id) == branchId
        }
    }

    private fun budgetMonth(value: String, zone: ZoneId): YearMonth? = runCatching {
        YearMonth.from(Instant.parse(value).atZone(zone))
    }.recoverCatching {
        YearMonth.from(LocalDate.parse(value.take(10)))
    }.getOrNull()
}

class OfflineFirstFamilyRepository(private val localStore: LocalStore) : FamilyRepository {
    override fun observeFamilyRows(ownerUserId: UserId): Flow<List<CloudRecord>> = combine(
        ReadOnlyCloudCollection.entries
            .filter { it.name.startsWith("FAMILY") }
            .map { localStore.observe(it.table, ownerUserId) }
    ) { rows -> rows.flatMap { it } }
}

class OfflineFirstInvestmentRepository(private val localStore: LocalStore) : InvestmentRepository {
    override fun observeAssets(ownerUserId: UserId): Flow<List<CloudRecord>> =
        localStore.observe(CloudEntity.INVESTMENT_ASSET.table, ownerUserId)

    override fun observeTrades(ownerUserId: UserId): Flow<List<CloudRecord>> =
        localStore.observe(CloudEntity.INVESTMENT_TRADE.table, ownerUserId)
}
