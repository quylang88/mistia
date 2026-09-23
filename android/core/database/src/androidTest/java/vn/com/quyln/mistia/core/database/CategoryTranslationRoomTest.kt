package vn.com.quyln.mistia.core.database

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.model.CategoryDraft
import vn.com.quyln.mistia.core.model.CategoryHierarchyRole
import vn.com.quyln.mistia.core.model.CategoryNameLanguage
import vn.com.quyln.mistia.core.model.CloudEntity
import vn.com.quyln.mistia.core.model.LocalStore
import vn.com.quyln.mistia.core.model.MutationKind
import vn.com.quyln.mistia.core.model.PendingMutation
import vn.com.quyln.mistia.core.model.TransactionCategoryKind
import vn.com.quyln.mistia.core.model.TransactionCategoryRecord
import vn.com.quyln.mistia.core.model.UserId

@RunWith(AndroidJUnit4::class)
class CategoryTranslationRoomTest {
    private lateinit var database: MistiaDatabase
    private lateinit var localStore: LocalStore
    private lateinit var repository: OfflineFirstFinanceRepository

    @Before
    fun createDatabase() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        database = Room.inMemoryDatabaseBuilder(context, MistiaDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        localStore = RoomLocalStore(database)
        repository = OfflineFirstFinanceRepository(localStore)
    }

    @After
    fun closeDatabase() = database.close()

    @Test
    fun categoryAndTranslationRequestCommitAtomicallyForOneOwner() = runTest {
        repository.saveCategory(UserId(OWNER_A), draft("Ăn ngoài"), DEVICE, NOW).getOrThrow()

        assertEquals(1, localStore.pendingCategoryTranslations(UserId(OWNER_A), 0).size)
        assertTrue(localStore.pendingCategoryTranslations(UserId(OWNER_B), 0).isEmpty())
        assertEquals("Ăn ngoài", repository.observeCategories(UserId(OWNER_A)).first().single().name)
    }

    @Test
    fun staleTranslationCannotOverwriteAConcurrentCategoryEditOrItsNewTask() = runTest {
        repository.saveCategory(UserId(OWNER_A), draft("Ăn ngoài"), DEVICE, NOW).getOrThrow()
        val staleTask = localStore.pendingCategoryTranslations(UserId(OWNER_A), 0).single()
        repository.saveCategory(UserId(OWNER_A), draft("Nhà hàng"), DEVICE, LATER).getOrThrow()

        val current = repository.observeCategories(UserId(OWNER_A)).first().single()
        val translated = current.copy(
            nameEnglish = "Dining",
            nameJapanese = "外食",
            updatedAt = LAST,
        ).toCloudRecord()
        val mutation = PendingMutation(
            CloudEntity.TRANSACTION_CATEGORY,
            translated.id,
            OWNER_A,
            MutationKind.UPSERT,
            translated.payload,
            LAST,
            translated.syncVersion,
            DEVICE,
        )

        assertFalse(localStore.applyCategoryTranslation(staleTask, translated, mutation))
        assertEquals("Nhà hàng", repository.observeCategories(UserId(OWNER_A)).first().single().name)
        assertEquals("Nhà hàng", localStore.pendingCategoryTranslations(UserId(OWNER_A), 0).single().translation.inputName)
    }

    @Test
    fun maintenanceSeedsMissingPulledTranslationWithoutReplacingANewerLocalRequest() = runTest {
        val pulled = draft("外食").copy(nameLanguage = CategoryNameLanguage.JAPANESE)
            .toMutation(UserId(OWNER_A), null, null, DEVICE, NOW)
            .record
            .toCloudRecord()
        localStore.replacePullSnapshot(UserId(OWNER_A), CloudEntity.TRANSACTION_CATEGORY.table, listOf(pulled))

        assertEquals(1, localStore.enqueueMissingCategoryTranslations(UserId(OWNER_A), DEVICE))
        val seeded = localStore.pendingCategoryTranslations(UserId(OWNER_A), 0).single().translation
        assertEquals(CategoryNameLanguage.JAPANESE, seeded.sourceLanguage)
        assertEquals("外食", seeded.inputName)
        assertTrue(localStore.pendingCategoryTranslations(UserId(OWNER_B), 0).isEmpty())

        repository.saveCategory(UserId(OWNER_A), draft("Ăn ngoài"), DEVICE, LATER).getOrThrow()
        assertEquals(0, localStore.enqueueMissingCategoryTranslations(UserId(OWNER_A), DEVICE))
        assertEquals(
            "Ăn ngoài",
            localStore.pendingCategoryTranslations(UserId(OWNER_A), 0).single().translation.inputName,
        )
    }

    private fun draft(name: String) = CategoryDraft(
        id = CATEGORY_ID,
        name = name,
        kind = TransactionCategoryKind.EXPENSE,
        hierarchyRole = CategoryHierarchyRole.PARENT,
    )

    private companion object {
        const val OWNER_A = "11111111-1111-1111-1111-111111111111"
        const val OWNER_B = "22222222-2222-2222-2222-222222222222"
        const val DEVICE = "33333333-3333-3333-3333-333333333333"
        const val CATEGORY_ID = "44444444-4444-4444-4444-444444444444"
        const val NOW = "2026-09-23T10:00:00.000Z"
        const val LATER = "2026-09-23T11:00:00.000Z"
        const val LAST = "2026-09-23T12:00:00.000Z"
    }
}
