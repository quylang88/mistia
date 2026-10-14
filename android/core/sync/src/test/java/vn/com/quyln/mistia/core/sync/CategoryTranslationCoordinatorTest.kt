package vn.com.quyln.mistia.core.sync

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import vn.com.quyln.mistia.core.model.CategoryNameLanguage
import vn.com.quyln.mistia.core.model.CategoryNameTranslations
import vn.com.quyln.mistia.core.model.CategoryNameTranslator
import vn.com.quyln.mistia.core.model.CloudEntity
import vn.com.quyln.mistia.core.model.CloudRecord
import vn.com.quyln.mistia.core.model.EntityCount
import vn.com.quyln.mistia.core.model.LocalStore
import vn.com.quyln.mistia.core.model.PendingCategoryTranslation
import vn.com.quyln.mistia.core.model.PendingMutation
import vn.com.quyln.mistia.core.model.QueuedCategoryTranslation
import vn.com.quyln.mistia.core.model.QueuedMutation
import vn.com.quyln.mistia.core.model.UserId
import vn.com.quyln.mistia.core.network.SupabaseHttpException

class CategoryTranslationCoordinatorTest {
    @Test
    fun `successful translation atomically updates category and queues new cloud mutation`() = runTest {
        val task = task()
        val local = FakeLocalStore(categoryRecord(), task)
        val translator = FakeTranslator(CategoryNameTranslations("Ăn ngoài", "Dining", "外食"))

        val result = coordinator(local, translator).translatePending(UserId(OWNER), TOKEN)

        assertEquals(1, result.translated)
        assertNull(local.task)
        assertEquals("Dining", local.record.payload.string("name_english"))
        assertEquals("外食", local.record.payload.string("name_japanese"))
        assertEquals(java.time.Instant.parse(LATER), java.time.Instant.parse(local.record.updatedAt))
        assertEquals(NOW, local.appliedExpectedUpdatedAt)
        assertEquals("Ăn ngoài", translator.inputName)
    }

    @Test
    fun `stale edit discards old translation request without calling network`() = runTest {
        val original = task()
        val local = FakeLocalStore(categoryRecord(updatedAt = LATER), original)
        val translator = FakeTranslator(CategoryNameTranslations("x", "x", "x"))

        val result = coordinator(local, translator).translatePending(UserId(OWNER), TOKEN)

        assertEquals(1, result.staleResponses)
        assertNull(local.task)
        assertEquals(0, translator.calls)
        assertEquals(java.time.Instant.parse(LATER), java.time.Instant.parse(local.record.updatedAt))
    }

    @Test
    fun `transient translation failure keeps account scoped task for bounded retry`() = runTest {
        val original = task()
        val local = FakeLocalStore(categoryRecord(), original)
        val translator = FakeTranslator(failure = SupabaseHttpException(503, "private"))

        val result = coordinator(local, translator).translatePending(UserId(OWNER), TOKEN)

        assertEquals(1, result.retryableFailures)
        assertEquals(1, local.task?.attemptCount)
        assertEquals(NOW_MILLIS + 30_000, local.task?.nextAttemptAtEpochMillis)
        assertEquals("http_503", local.task?.lastError)
        assertEquals(NOW, local.record.updatedAt)
    }

    @Test
    fun `authentication failure remains pending for retry with a refreshed session`() = runTest {
        val original = task()
        val local = FakeLocalStore(categoryRecord(), original)
        val translator = FakeTranslator(failure = SupabaseHttpException(401, "private"))

        val result = coordinator(local, translator).translatePending(UserId(OWNER), TOKEN)

        assertEquals(1, result.retryableFailures)
        assertEquals(1, local.task?.attemptCount)
        assertEquals(NOW_MILLIS + 30_000, local.task?.nextAttemptAtEpochMillis)
        assertEquals("http_401", local.task?.lastError)
    }

    @Test
    fun `maintenance seeds a missing pulled category before translating it`() = runTest {
        val missing = task()
        val local = FakeLocalStore(categoryRecord(), task = null, seedTask = missing)
        val translator = FakeTranslator(CategoryNameTranslations("Ăn ngoài", "Dining", "外食"))

        val result = coordinator(local, translator).translatePending(UserId(OWNER), TOKEN)

        assertEquals(DEVICE, local.seededDeviceId)
        assertEquals(1, result.translated)
        assertNull(local.task)
    }

    @Test
    fun `concurrent maintenance calls coalesce instead of translating one task twice`() = runTest {
        val local = FakeLocalStore(categoryRecord(), task())
        val translator = FakeTranslator(
            result = CategoryNameTranslations("Ăn ngoài", "Dining", "外食"),
            delayMillis = 10,
        )
        val coordinator = coordinator(local, translator)

        awaitAll(
            async { coordinator.translatePending(UserId(OWNER), TOKEN) },
            async { coordinator.translatePending(UserId(OWNER), TOKEN) },
        )

        assertEquals(1, translator.calls)
    }

    @Test
    fun `cancellation propagates without changing translation task`() = runTest {
        val original = task()
        val local = FakeLocalStore(categoryRecord(), original)
        val translator = FakeTranslator(failure = CancellationException("cancelled"))

        val failure = runCatching {
            coordinator(local, translator).translatePending(UserId(OWNER), TOKEN)
        }.exceptionOrNull()

        assertTrue(failure is CancellationException)
        assertSame(original, local.task)
    }

    @Test fun `translation preserves unknown payload fields and cannot move a future clock backwards`()=runTest {
        val future="2027-01-01T00:00:00Z"
        val extra=JsonObject(mapOf("minor" to JsonPrimitive(9007199254740993L)))
        val row=categoryRecord(future).let {it.copy(payload=JsonObject(it.payload+("future_metadata" to extra)))}
        val pending=task().let {it.copy(translation=it.translation.copy(savedUpdatedAt=future))}
        val local=FakeLocalStore(row,pending)
        val translator=FakeTranslator(CategoryNameTranslations("Ăn ngoài","Dining","外食"))
        assertEquals(1,coordinator(local,translator).translatePending(UserId(OWNER),TOKEN).translated)
        assertEquals(extra,local.record.payload["future_metadata"])
        assertTrue(!java.time.Instant.parse(local.record.updatedAt).isBefore(java.time.Instant.parse(future)))
    }
    @Test fun `viewer envelope cannot send another owners category text to translation service`()=runTest {
        val row=categoryRecord().let {it.copy(payload=JsonObject(it.payload+("user_id" to JsonPrimitive(DEVICE))))}
        val local=FakeLocalStore(row,task())
        val translator=FakeTranslator(CategoryNameTranslations("x","x","x"))
        coordinator(local,translator).translatePending(UserId(OWNER),TOKEN)
        assertEquals(0,translator.calls)
        assertEquals(row,local.record)
    }
    @Test fun `deleted category cannot be resurrected by a queued translation`()=runTest {
        val row=categoryRecord().let {it.copy(deletedAt=NOW,payload=JsonObject(it.payload+("deleted_at" to JsonPrimitive(NOW))))}
        val local=FakeLocalStore(row,task())
        val translator=FakeTranslator(CategoryNameTranslations("x","x","x"))
        coordinator(local,translator).translatePending(UserId(OWNER),TOKEN)
        assertEquals(0,translator.calls)
        assertEquals(row,local.record)
    }
    @Test fun `same clock FK replacement during HTTP cannot be overwritten by old translation`()=runTest {
        val local=FakeLocalStore(categoryRecord(),task())
        val changed=local.record.let {it.copy(payload=JsonObject(it.payload+("parent_category_id" to JsonPrimitive(DEVICE))))}
        val translator=object:CategoryNameTranslator {
            override suspend fun translate(inputName:String,sourceLanguage:CategoryNameLanguage,accessToken:String):CategoryNameTranslations {
                local.record=changed
                return CategoryNameTranslations("Ăn ngoài","Dining","外食")
            }
        }
        assertEquals(1,coordinator(local,translator).translatePending(UserId(OWNER),TOKEN).staleResponses)
        assertEquals(changed,local.record)
        assertEquals(task(),local.task)
    }
    @Test fun `same clock changed source name discards stale task before HTTP`()=runTest {
        val changed=categoryRecord().let {it.copy(payload=JsonObject(it.payload+("name" to JsonPrimitive("Nhà hàng mới"))))}
        val local=FakeLocalStore(changed,task())
        val translator=FakeTranslator(CategoryNameTranslations("Ăn ngoài","Dining","外食"))
        assertEquals(1,coordinator(local,translator).translatePending(UserId(OWNER),TOKEN).staleResponses)
        assertEquals(0,translator.calls)
        assertNull(local.task)
        assertEquals(changed,local.record)
    }
    @Test fun `explicit English edit can refresh existing complete translations`()=runTest {
        val row=categoryRecord().let {it.copy(payload=JsonObject(it.payload+mapOf(
            "name_english" to JsonPrimitive("New dining"),"name_japanese" to JsonPrimitive("古い名前"))))}
        val english=task().let {it.copy(translation=it.translation.copy(inputName="New dining",sourceLanguage=CategoryNameLanguage.ENGLISH))}
        val local=FakeLocalStore(row,english)
        val translator=FakeTranslator(CategoryNameTranslations("Nhà hàng mới","New dining","新しい名前"))
        assertEquals(1,coordinator(local,translator).translatePending(UserId(OWNER),TOKEN).translated)
        assertEquals("Nhà hàng mới",local.record.payload.string("name"))
        assertEquals(1,translator.calls)
    }
    private fun coordinator(local: LocalStore, translator: CategoryNameTranslator) =
        CategoryTranslationCoordinator(
            localStore = local,
            translator = translator,
            deviceIdProvider = { DEVICE },
            nowEpochMillis = { NOW_MILLIS },
            nowIsoString = { LATER },
        )

    private fun task() = QueuedCategoryTranslation(
        translation = PendingCategoryTranslation(
            ownerUserId = OWNER,
            categoryId = CATEGORY_ID,
            inputName = "Ăn ngoài",
            sourceLanguage = CategoryNameLanguage.VIETNAMESE,
            savedUpdatedAt = NOW,
            deviceId = DEVICE,
        ),
        attemptCount = 0,
        nextAttemptAtEpochMillis = 0,
        lastError = null,
    )

    private fun categoryRecord(updatedAt: String = NOW) = CloudRecord(
        entity = CloudEntity.TRANSACTION_CATEGORY.table,
        id = CATEGORY_ID,
        ownerUserId = OWNER,
        payload = JsonObject(
            mapOf(
                "user_id" to JsonPrimitive(OWNER),
                "id" to JsonPrimitive(CATEGORY_ID),
                "name" to JsonPrimitive("Ăn ngoài"),
                "name_english" to JsonNull,
                "name_japanese" to JsonNull,
                "kind_raw_value" to JsonPrimitive("expense"),
                "icon_symbol_name" to JsonPrimitive("mistia.flow.expense"),
                "icon_color_hex" to JsonPrimitive("#FF7A59"),
                "is_favorite" to JsonPrimitive(false),
                "family_budget_spending_enabled" to JsonPrimitive(false),
                "parent_category_id" to JsonNull,
                "hierarchy_role_raw_value" to JsonPrimitive("parent"),
                "system_key" to JsonNull,
                "is_system" to JsonPrimitive(false),
                "sort_order" to JsonPrimitive(0),
                "is_archived" to JsonPrimitive(false),
                "archived_at" to JsonNull,
                "created_at" to JsonPrimitive(NOW),
                "updated_at" to JsonPrimitive(updatedAt),
                "deleted_at" to JsonNull,
                "sync_version" to JsonPrimitive(0),
                "last_modified_by_device_id" to JsonPrimitive(DEVICE),
            )
        ),
        updatedAt = updatedAt,
        deletedAt = null,
        syncVersion = 0,
    )

    private class FakeTranslator(
        private val result: CategoryNameTranslations? = null,
        private val failure: Throwable? = null,
        private val delayMillis: Long = 0,
    ) : CategoryNameTranslator {
        var calls = 0
        var inputName: String? = null
        override suspend fun translate(
            inputName: String,
            sourceLanguage: CategoryNameLanguage,
            accessToken: String,
        ): CategoryNameTranslations {
            calls++
            this.inputName = inputName
            if (delayMillis > 0) delay(delayMillis)
            failure?.let { throw it }
            return requireNotNull(result)
        }
    }

    private class FakeLocalStore(
        var record: CloudRecord,
        var task: QueuedCategoryTranslation?,
        private val seedTask: QueuedCategoryTranslation? = null,
    ) : LocalStore {
        var appliedExpectedUpdatedAt: String? = null
        var seededDeviceId: String? = null
        override fun observe(entity: String, ownerUserId: UserId): Flow<List<CloudRecord>> =
            MutableStateFlow(listOf(record))
        override fun observeEntityCounts(ownerUserId: UserId): Flow<List<EntityCount>> =
            MutableStateFlow(emptyList())
        override suspend fun record(ownerUserId: UserId, entity: String, recordId: String) = record
        override suspend fun commitMutation(record: CloudRecord, mutation: PendingMutation) = Unit
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
        override suspend fun pendingCategoryTranslations(
            ownerUserId: UserId,
            dueAtEpochMillis: Long,
            limit: Int,
        ) = listOfNotNull(task).filter {
            it.translation.ownerUserId == ownerUserId.value &&
                it.nextAttemptAtEpochMillis <= dueAtEpochMillis
        }
        override suspend fun enqueueMissingCategoryTranslations(
            ownerUserId: UserId,
            deviceId: String,
            limit: Int,
        ): Int {
            seededDeviceId = deviceId
            if (task != null || seedTask == null || seedTask.translation.ownerUserId != ownerUserId.value) return 0
            task = seedTask
            return 1
        }
        override suspend fun applyCategoryTranslation(
            task: QueuedCategoryTranslation,
            expectedRecord: CloudRecord,
            record: CloudRecord,
            mutation: PendingMutation,
        ): Boolean {
            if (this.task != task || this.record != expectedRecord || this.record.updatedAt != task.translation.savedUpdatedAt) return false
            appliedExpectedUpdatedAt = task.translation.savedUpdatedAt
            this.task = null
            this.record = record
            return true
        }
        override suspend fun discardCategoryTranslation(task: QueuedCategoryTranslation): Boolean {
            if (this.task != task) return false
            this.task = null
            return true
        }
        override suspend fun recordCategoryTranslationFailure(
            task: QueuedCategoryTranslation,
            nextAttemptAtEpochMillis: Long,
            errorCode: String,
        ): Boolean {
            if (this.task != task) return false
            this.task = task.copy(
                attemptCount = task.attemptCount + 1,
                nextAttemptAtEpochMillis = nextAttemptAtEpochMillis,
                lastError = errorCode,
            )
            return true
        }
        override suspend fun replacePullSnapshot(ownerUserId: UserId, entity: String, records: List<CloudRecord>) = Unit
        override suspend fun pendingMutationRecordIds(ownerUserId: UserId, entity: String) = emptySet<String>()
        override suspend fun clearAccount(ownerUserId: UserId) = Unit
    }

    private fun JsonObject.string(key: String) = (get(key) as JsonPrimitive).content

    private companion object {
        const val OWNER = "11111111-1111-1111-1111-111111111111"
        const val CATEGORY_ID = "22222222-2222-2222-2222-222222222222"
        const val DEVICE = "33333333-3333-3333-3333-333333333333"
        const val TOKEN = "access-token"
        const val NOW = "2026-09-23T10:00:00.000Z"
        const val LATER = "2026-09-23T11:00:00.000Z"
        const val NOW_MILLIS = 1_795_000_000_000L
    }
}
