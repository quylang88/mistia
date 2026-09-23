package vn.com.quyln.mistia.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class CategoryTranslationModelsTest {
    @Test
    fun `vietnamese fallback preserves existing translated names`() {
        val fallback = CategoryNameTranslations.fallback(
            inputName = "  Ăn ngoài  ",
            sourceLanguage = CategoryNameLanguage.VIETNAMESE,
            existing = CategoryNameTranslations("Cũ", "Dining", "外食"),
        )

        assertEquals(CategoryNameTranslations("Ăn ngoài", "Dining", "外食"), fallback)
    }

    @Test
    fun `english fallback keeps input in source slot and supplies required base name`() {
        val fallback = CategoryNameTranslations.fallback(
            inputName = " Groceries ",
            sourceLanguage = CategoryNameLanguage.ENGLISH,
            existing = null,
        )

        assertEquals("Groceries", fallback.name)
        assertEquals("Groceries", fallback.nameEnglish)
        assertNull(fallback.nameJapanese)
    }

    @Test
    fun `remote blanks fall back without erasing existing values`() {
        val merged = CategoryNameTranslations("", "Dining", null).mergedWithFallback(
            CategoryNameTranslations("Ăn ngoài", "Old English", "外食")
        )

        assertEquals(CategoryNameTranslations("Ăn ngoài", "Dining", "外食"), merged)
    }

    @Test
    fun `legacy category with missing names infers the same retry source as iOS maintenance`() {
        val japanese = category(name = "外食", nameEnglish = null, nameJapanese = "外食")
        val english = category(name = "Dining", nameEnglish = "Dining", nameJapanese = null)
        val complete = category(name = "Ăn ngoài", nameEnglish = "Dining", nameJapanese = "外食")

        assertEquals(
            CategoryNameTranslationSource("外食", CategoryNameLanguage.JAPANESE),
            japanese.translationRetrySource(),
        )
        assertEquals(
            CategoryNameTranslationSource("Dining", CategoryNameLanguage.ENGLISH),
            english.translationRetrySource(),
        )
        assertNull(complete.translationRetrySource())
    }

    private fun category(
        name: String,
        nameEnglish: String?,
        nameJapanese: String?,
    ) = TransactionCategoryRecord(
        id = "22222222-2222-2222-2222-222222222222",
        ownerUserId = "11111111-1111-1111-1111-111111111111",
        name = name,
        nameEnglish = nameEnglish,
        nameJapanese = nameJapanese,
        kindWireValue = "expense",
        iconSymbolName = "mistia.flow.expense",
        iconColorHex = "#FF7A59",
        isFavorite = false,
        familyBudgetSpendingEnabled = false,
        parentCategoryId = null,
        hierarchyRoleWireValue = "parent",
        systemKey = null,
        isSystem = false,
        sortOrder = 0,
        isArchived = false,
        archivedAt = null,
        createdAt = "2026-09-23T10:00:00.000Z",
        updatedAt = "2026-09-23T10:00:00.000Z",
        deletedAt = null,
        syncVersion = 0,
        lastModifiedByDeviceId = null,
    )
}
