package vn.com.quyln.mistia.feature.management

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import vn.com.quyln.mistia.core.model.TransactionCategoryKind

class CategoryIconCatalogTest {
    @Test
    fun `packaged shared catalog matches the complete active iOS picker set`() {
        val source = checkNotNull(javaClass.classLoader?.getResourceAsStream("MistiaSystemCategories.json"))
            .bufferedReader()
            .use { it.readText() }

        val catalog = CategoryIconCatalog.parse(source)
        val options = TransactionCategoryKind.entries.flatMap(catalog::options)

        assertEquals(147, options.size)
        assertTrue(options.any { it.token == "mistia.category.expense.food.grocery" })
        assertTrue(options.any { it.token == "mistia.category.income.salary_work.salary" })
        assertFalse(options.any { it.token == "mistia.category.expense.other.expense" })
    }

    @Test
    fun `catalog includes every active parent then active child for its kind`() {
        val catalog = CategoryIconCatalog.parse(
            """
            [
              {
                "active": true,
                "kind": "expense",
                "icon": "mistia.category.parent.expense.food",
                "fallbackIcon": "cart.fill",
                "color": "#FF8A4C",
                "children": [
                  {"active": true, "icon": "mistia.category.expense.food.grocery", "fallbackIcon": "basket.fill", "color": "#FF8A4C"},
                  {"active": false, "icon": "mistia.category.expense.food.legacy", "fallbackIcon": "tray.fill", "color": "#000000"}
                ]
              },
              {
                "active": true,
                "kind": "income",
                "icon": "mistia.category.parent.income.salary_work",
                "fallbackIcon": "briefcase.fill",
                "color": "#2DAA9E",
                "children": [
                  {"active": true, "icon": "mistia.category.income.salary_work.salary", "fallbackIcon": "banknote.fill", "color": "#2DAA9E"}
                ]
              }
            ]
            """.trimIndent()
        )

        val expense = catalog.options(TransactionCategoryKind.EXPENSE)
        assertEquals(
            listOf("mistia.category.parent.expense.food", "mistia.category.expense.food.grocery"),
            expense.map(CategoryIconOption::token),
        )
        assertEquals("basket.fill", catalog.option("mistia.category.expense.food.grocery")?.fallbackIcon)
        assertFalse(expense.any { it.token.endsWith("legacy") })
        assertTrue(catalog.options(TransactionCategoryKind.INCOME).all { it.token.contains("salary_work") })
    }

    @Test
    fun `parent and child fallbacks map to stable Android icon families`() {
        assertEquals(
            CategoryIconFamily.FOOD,
            categoryIconFamily("cart.fill", TransactionCategoryKind.EXPENSE),
        )
        assertEquals(
            CategoryIconFamily.WORK,
            categoryIconFamily("graduationcap.fill", TransactionCategoryKind.EXPENSE),
        )
        assertEquals(
            CategoryIconFamily.INCOME,
            categoryIconFamily("chart.line.uptrend.xyaxis", TransactionCategoryKind.INCOME),
        )
    }
}
