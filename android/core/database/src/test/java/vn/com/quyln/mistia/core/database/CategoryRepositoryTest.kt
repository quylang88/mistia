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
import vn.com.quyln.mistia.core.model.CategoryDraft
import vn.com.quyln.mistia.core.model.CategoryHierarchyRole
import vn.com.quyln.mistia.core.model.CategoryValidationError
import vn.com.quyln.mistia.core.model.CategoryValidationException
import vn.com.quyln.mistia.core.model.CloudEntity
import vn.com.quyln.mistia.core.model.CloudRecord
import vn.com.quyln.mistia.core.model.EntityCount
import vn.com.quyln.mistia.core.model.LocalStore
import vn.com.quyln.mistia.core.model.PendingMutation
import vn.com.quyln.mistia.core.model.PendingCategoryTranslation
import vn.com.quyln.mistia.core.model.QueuedMutation
import vn.com.quyln.mistia.core.model.RecordId
import vn.com.quyln.mistia.core.model.TransactionCategoryKind
import vn.com.quyln.mistia.core.model.UserId

class CategoryRepositoryTest {
    @Test
    fun `categories are owner scoped and sorted by sort order then creation`() = runTest {
        val store = CategoryMemoryStore()
        val repository = OfflineFirstFinanceRepository(store)

        repository.saveCategory(UserId(OWNER_A), parent(PARENT_B, "Later", sortOrder = 2), DEVICE, LATER).getOrThrow()
        repository.saveCategory(UserId(OWNER_A), parent(PARENT_A, "First", sortOrder = 1), DEVICE, NOW).getOrThrow()
        repository.saveCategory(UserId(OWNER_B), parent(OTHER_PARENT, "Other", sortOrder = 0), DEVICE, NOW).getOrThrow()

        assertEquals(
            listOf("First", "Later"),
            repository.observeCategories(UserId(OWNER_A)).first().map { it.name },
        )
        assertEquals(listOf("Other"), repository.observeCategories(UserId(OWNER_B)).first().map { it.name })
        assertEquals(2, store.outboxRows(OWNER_A).size)
        assertEquals(listOf("Later", "First"), store.translationRows(OWNER_A).map { it.inputName })
    }

    @Test
    fun `save rejects a whitespace and case normalized duplicate in the editing locale`() = runTest {
        val repository = OfflineFirstFinanceRepository(CategoryMemoryStore())
        repository.saveCategory(UserId(OWNER_A), parent(PARENT_A, "Ăn   uống"), DEVICE, NOW).getOrThrow()

        val failure = repository.saveCategory(
            UserId(OWNER_A),
            parent(PARENT_B, "  ĂN uống  "),
            DEVICE,
            LATER,
        ).exceptionOrNull() as CategoryValidationException

        assertEquals(CategoryValidationError.DUPLICATE_NAME, failure.reason)
    }

    @Test
    fun `archived category names remain reserved like iOS`() = runTest {
        val repository = OfflineFirstFinanceRepository(CategoryMemoryStore())
        repository.saveCategory(UserId(OWNER_A), parent(PARENT_A, "Food"), DEVICE, NOW).getOrThrow()
        repository.archiveCategory(UserId(OWNER_A), RecordId(PARENT_A), DEVICE, LATER).getOrThrow()

        val failure = repository.saveCategory(
            UserId(OWNER_A),
            parent(PARENT_B, " food "),
            DEVICE,
            ARCHIVED,
        ).exceptionOrNull() as CategoryValidationException

        assertEquals(CategoryValidationError.DUPLICATE_NAME, failure.reason)
    }

    @Test
    fun `child favorite is account scoped and keeps pulled base version`() = runTest {
        val store = CategoryMemoryStore()
        val repository = OfflineFirstFinanceRepository(store)
        val parent = repository.saveCategory(
            UserId(OWNER_A),
            parent(PARENT_A, "Food"),
            DEVICE,
            NOW,
        ).getOrThrow()
        val child = CategoryDraft(
            id = CHILD,
            name = "Lunch",
            kind = TransactionCategoryKind.EXPENSE,
            hierarchyRole = CategoryHierarchyRole.CHILD,
            parentCategoryId = parent.id,
        ).toMutation(UserId(OWNER_A), null, parent, DEVICE, NOW).record.copy(syncVersion = 6)
        store.seed(child.toCloudRecord())

        repository.setCategoryFavorite(UserId(OWNER_A), RecordId(CHILD), true, DEVICE, LATER).getOrThrow()

        val updated = repository.observeCategories(UserId(OWNER_A)).first().single { it.id == CHILD }
        assertTrue(updated.isFavorite)
        assertEquals(6L, store.outboxRows(OWNER_A).single { it.recordId == CHILD }.baseVersion)
        assertTrue(repository.setCategoryFavorite(UserId(OWNER_B), RecordId(CHILD), true, DEVICE, LATER).isFailure)
    }

    @Test
    fun `changing category kind assigns the next sort order in its new branch`() = runTest {
        val store = CategoryMemoryStore()
        val repository = OfflineFirstFinanceRepository(store)
        repository.saveCategory(
            UserId(OWNER_A),
            parent(PARENT_B, "Salary", sortOrder = 4).copy(kind = TransactionCategoryKind.INCOME),
            DEVICE,
            NOW,
        ).getOrThrow()
        repository.saveCategory(UserId(OWNER_A), parent(PARENT_A, "Food", sortOrder = 9), DEVICE, NOW).getOrThrow()

        val changed = repository.saveCategory(
            UserId(OWNER_A),
            parent(PARENT_A, "Food", sortOrder = 9).copy(kind = TransactionCategoryKind.INCOME),
            DEVICE,
            LATER,
        ).getOrThrow()

        assertEquals(5, changed.sortOrder)
    }

    @Test
    fun `current month budget blocks category name or structure edits like iOS`() = runTest {
        val store = CategoryMemoryStore()
        val repository = OfflineFirstFinanceRepository(store)
        repository.saveCategory(UserId(OWNER_A), parent(PARENT_A, "Food"), DEVICE, NOW).getOrThrow()
        store.seed(
            reference(CloudEntity.BUDGET_PLAN, "00000000-0000-0000-0000-000000000099").copy(
                payload = JsonObject(
                    reference(CloudEntity.BUDGET_PLAN, "00000000-0000-0000-0000-000000000099").payload +
                        ("month_anchor" to JsonPrimitive("2026-09-01T00:00:00.000Z"))
                )
            )
        )

        val failure = repository.saveCategory(
            UserId(OWNER_A),
            parent(PARENT_A, "Dining"),
            DEVICE,
            LATER,
        ).exceptionOrNull() as CategoryValidationException

        assertEquals(CategoryValidationError.BUDGET_BRANCH_CURRENT_MONTH_BLOCK, failure.reason)
    }

    @Test
    fun `archive is blocked by active children and each direct active reference`() = runTest {
        val blockers = listOf(
            CloudEntity.LEDGER_TRANSACTION to CategoryValidationError.ARCHIVE_HAS_TRANSACTIONS,
            CloudEntity.BUDGET_PLAN to CategoryValidationError.ARCHIVE_HAS_BUDGETS,
            CloudEntity.RECURRING_BILL_PLAN to CategoryValidationError.ARCHIVE_HAS_BILLS,
        )

        run {
            val store = CategoryMemoryStore()
            val repository = OfflineFirstFinanceRepository(store)
            repository.saveCategory(UserId(OWNER_A), parent(PARENT_A, "Food"), DEVICE, NOW).getOrThrow()
            repository.saveCategory(
                UserId(OWNER_A),
                CategoryDraft(
                    id = CHILD,
                    name = "Lunch",
                    kind = TransactionCategoryKind.EXPENSE,
                    hierarchyRole = CategoryHierarchyRole.CHILD,
                    parentCategoryId = PARENT_A,
                ),
                DEVICE,
                LATER,
            ).getOrThrow()
            assertCategoryFailure(CategoryValidationError.ARCHIVE_HAS_CHILDREN) {
                repository.archiveCategory(UserId(OWNER_A), RecordId(PARENT_A), DEVICE, ARCHIVED)
            }
        }

        blockers.forEachIndexed { index, (entity, expected) ->
            val store = CategoryMemoryStore()
            val repository = OfflineFirstFinanceRepository(store)
            repository.saveCategory(UserId(OWNER_A), parent(PARENT_A, "Food"), DEVICE, NOW).getOrThrow()
            store.seed(reference(entity, "00000000-0000-0000-0000-00000000000${index + 1}"))
            assertCategoryFailure(expected) {
                repository.archiveCategory(UserId(OWNER_A), RecordId(PARENT_A), DEVICE, ARCHIVED)
            }
        }
    }

    @Test
    fun `unreferenced category archives through an upsert and leaves active flow`() = runTest {
        val store = CategoryMemoryStore()
        val repository = OfflineFirstFinanceRepository(store)
        repository.saveCategory(UserId(OWNER_A), parent(PARENT_A, "Food"), DEVICE, NOW).getOrThrow()

        repository.archiveCategory(UserId(OWNER_A), RecordId(PARENT_A), DEVICE, ARCHIVED).getOrThrow()

        assertTrue(repository.observeCategories(UserId(OWNER_A)).first().isEmpty())
        assertEquals("UPSERT", store.outboxRows(OWNER_A).single().kind.name)
    }

    private fun parent(id: String, name: String, sortOrder: Int? = null) = CategoryDraft(
        id = id,
        name = name,
        kind = TransactionCategoryKind.EXPENSE,
        hierarchyRole = CategoryHierarchyRole.PARENT,
        sortOrder = sortOrder,
    )

    private fun reference(entity: CloudEntity, id: String) = CloudRecord(
        entity = entity.table,
        id = id,
        ownerUserId = OWNER_A,
        payload = JsonObject(
            mapOf(
                "id" to JsonPrimitive(id),
                "user_id" to JsonPrimitive(OWNER_A),
                "category_id" to JsonPrimitive(PARENT_A),
                "is_archived" to JsonPrimitive(false),
            )
        ),
        updatedAt = NOW,
        deletedAt = null,
        syncVersion = 0,
    )

    private suspend fun assertCategoryFailure(
        reason: CategoryValidationError,
        block: suspend () -> Result<Unit>,
    ) {
        val error = block().exceptionOrNull() as CategoryValidationException
        assertEquals(reason, error.reason)
    }

    private class CategoryMemoryStore : LocalStore {
        private val records = MutableStateFlow<Map<Triple<String, String, String>, CloudRecord>>(emptyMap())
        private val outbox = linkedMapOf<Triple<String, String, String>, PendingMutation>()
        private val translations = linkedMapOf<Pair<String, String>, PendingCategoryTranslation>()

        override fun observe(entity: String, ownerUserId: UserId): Flow<List<CloudRecord>> = records.map { rows ->
            rows.values.filter { it.ownerUserId == ownerUserId.value && it.entity == entity && it.deletedAt == null }
        }

        override fun observeEntityCounts(ownerUserId: UserId): Flow<List<EntityCount>> = records.map { rows ->
            rows.values.filter { it.ownerUserId == ownerUserId.value && it.deletedAt == null }
                .groupingBy(CloudRecord::entity).eachCount().map { EntityCount(it.key, it.value) }
        }

        override suspend fun record(ownerUserId: UserId, entity: String, recordId: String): CloudRecord? =
            records.value[Triple(ownerUserId.value, entity, recordId)]

        override suspend fun commitMutation(record: CloudRecord, mutation: PendingMutation) {
            val key = Triple(record.ownerUserId, record.entity, record.id)
            require(key == Triple(mutation.subjectUserId, mutation.entity.table, mutation.recordId))
            records.value = records.value + (key to record)
            outbox[key] = mutation
        }

        override suspend fun commitCategoryMutation(
            record: CloudRecord,
            mutation: PendingMutation,
            translation: PendingCategoryTranslation,
        ) {
            commitMutation(record, mutation)
            translations[translation.ownerUserId to translation.categoryId] = translation
        }

        override suspend fun pendingMutations(
            ownerUserId: UserId,
            entity: CloudEntity,
            dueAtEpochMillis: Long,
            limit: Int,
        ): List<QueuedMutation> = emptyList()

        override suspend fun acknowledgeMutation(mutation: QueuedMutation, remoteRecord: CloudRecord) = false
        override suspend fun recordMutationFailure(
            mutation: QueuedMutation,
            nextAttemptAtEpochMillis: Long,
            errorCode: String,
        ) = false

        override suspend fun replacePullSnapshot(ownerUserId: UserId, entity: String, records: List<CloudRecord>) {
            this.records.value = this.records.value.filterKeys { it.first != ownerUserId.value || it.second != entity } +
                records.associateBy { Triple(ownerUserId.value, entity, it.id) }
        }

        override suspend fun pendingMutationRecordIds(ownerUserId: UserId, entity: String): Set<String> = emptySet()
        override suspend fun clearAccount(ownerUserId: UserId) {
            records.value = records.value.filterKeys { it.first != ownerUserId.value }
            outbox.keys.removeAll { it.first == ownerUserId.value }
            translations.keys.removeAll { it.first == ownerUserId.value }
        }

        fun seed(record: CloudRecord) {
            records.value = records.value + (Triple(record.ownerUserId, record.entity, record.id) to record)
        }

        fun outboxRows(owner: String): List<PendingMutation> =
            outbox.filterKeys { it.first == owner }.values.toList()

        fun translationRows(owner: String): List<PendingCategoryTranslation> =
            translations.filterKeys { it.first == owner }.values.toList()
    }

    private companion object {
        const val OWNER_A = "11111111-1111-1111-1111-111111111111"
        const val OWNER_B = "22222222-2222-2222-2222-222222222222"
        const val DEVICE = "33333333-3333-3333-3333-333333333333"
        const val PARENT_A = "44444444-4444-4444-4444-444444444444"
        const val PARENT_B = "55555555-5555-5555-5555-555555555555"
        const val OTHER_PARENT = "66666666-6666-6666-6666-666666666666"
        const val CHILD = "77777777-7777-7777-7777-777777777777"
        const val NOW = "2026-09-22T10:00:00.000Z"
        const val LATER = "2026-09-22T11:00:00.000Z"
        const val ARCHIVED = "2026-09-22T12:00:00.000Z"
    }
}
