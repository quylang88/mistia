package vn.com.quyln.mistia.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ReceiptAnalysisTest {
    @Test
    fun `purchase normalization preserves literal OCR and quantity`() {
        val item = BillItemAnalysisItem(
            lineId = " line-1 ",
            rawLineText = " 3@ まろやかミルク 198 ",
            originalName = " まろやかミルク ",
            translatedName = " Mild milk ",
            lineType = BillItemLineType.PURCHASE,
            quantity = 3,
            originalAmountMinor = 594,
            discountAmountMinor = 0,
            finalAmountMinor = 594,
            categoryId = " category-1 ",
            confidence = 1.4,
            missingFields = listOf(" quantity ", "", "quantity"),
        ).normalized()

        assertEquals("line-1", item.lineId)
        assertEquals("3@ まろやかミルク 198", item.rawLineText)
        assertEquals("まろやかミルク", item.originalName)
        assertEquals("Mild milk", item.translatedName)
        assertEquals(3, item.quantity)
        assertEquals(594L, item.originalAmountMinor)
        assertEquals(594L, item.finalAmountMinor)
        assertEquals("category-1", item.categoryId)
        assertEquals(1.0, item.confidence, 0.0)
        assertEquals(listOf("quantity"), item.missingFields)
    }

    @Test
    fun `discount normalization cannot inherit category or purchase fields`() {
        val item = BillItemAnalysisItem(
            lineId = "coupon",
            rawLineText = "クーポン -50",
            originalName = "クーポン",
            translatedName = null,
            lineType = BillItemLineType.DISCOUNT,
            quantity = 10,
            originalAmountMinor = 50,
            discountAmountMinor = -50,
            finalAmountMinor = 50,
            categoryId = "category-1",
            confidence = -0.2,
            missingFields = emptyList(),
        ).normalized()

        assertNull(item.quantity)
        assertNull(item.originalAmountMinor)
        assertEquals(50L, item.discountAmountMinor)
        assertEquals(-50L, item.finalAmountMinor)
        assertNull(item.categoryId)
        assertEquals(0.0, item.confidence, 0.0)
    }

    @Test
    fun `result validation removes unknown selections and audits arithmetic`() {
        val purchase = BillItemAnalysisItem(
            lineId = "purchase",
            rawLineText = "商品 200",
            originalName = "商品",
            translatedName = null,
            lineType = BillItemLineType.PURCHASE,
            quantity = null,
            originalAmountMinor = 200,
            discountAmountMinor = 0,
            finalAmountMinor = 200,
            categoryId = "unknown-category",
            confidence = 0.9,
            missingFields = emptyList(),
        )
        val coupon = BillItemAnalysisItem(
            lineId = "coupon",
            rawLineText = "値引 -20",
            originalName = "値引",
            translatedName = null,
            lineType = BillItemLineType.DISCOUNT,
            quantity = null,
            originalAmountMinor = null,
            discountAmountMinor = 20,
            finalAmountMinor = -20,
            categoryId = null,
            confidence = 0.8,
            missingFields = emptyList(),
        )
        val result = BillItemAnalysisResult(
            merchantName = " Store ",
            totalMinor = 180,
            currencyCode = " jpy ",
            occurredAt = "2026-09-24T10:00:00+09:00",
            walletId = "unknown-wallet",
            multipleBillsDetected = false,
            confidence = 0.95,
            missingFields = emptyList(),
            rawText = " 商品 200\n値引 -20 ",
            items = listOf(purchase, coupon),
            quota = null,
        ).validated(categoryIds = setOf("category-1"), walletIds = setOf("wallet-1"))

        assertEquals("Store", result.merchantName)
        assertEquals("JPY", result.currencyCode)
        assertEquals("商品 200\n値引 -20", result.rawText)
        assertNull(result.walletId)
        assertNull(result.items.first().categoryId)
        assertEquals(listOf("categoryID", "walletID"), result.missingFields)
        assertEquals(180L, result.itemsTotalMinor)
        assertEquals(0L, result.totalDifferenceMinor)
        assertFalse(result.requiresReview)
    }

    @Test
    fun `duplicate item IDs require review`() {
        val item = BillItemAnalysisItem(
            lineId = "duplicate",
            rawLineText = "商品 100",
            originalName = "商品",
            translatedName = null,
            lineType = BillItemLineType.PURCHASE,
            quantity = null,
            originalAmountMinor = 100,
            discountAmountMinor = 0,
            finalAmountMinor = 100,
            categoryId = null,
            confidence = 0.9,
            missingFields = emptyList(),
        )
        val result = BillItemAnalysisResult(
            merchantName = "Store",
            totalMinor = 200,
            currencyCode = "JPY",
            occurredAt = null,
            walletId = null,
            multipleBillsDetected = false,
            confidence = 0.9,
            missingFields = emptyList(),
            rawText = null,
            items = listOf(item, item),
            quota = null,
        )

        assertTrue(result.requiresReview)
    }

    @Test
    fun `purchase with readable final amount does not require original amount`() {
        val item = BillItemAnalysisItem(
            lineId = "line-1",
            rawLineText = "商品 100",
            originalName = "商品",
            translatedName = null,
            lineType = BillItemLineType.PURCHASE,
            quantity = null,
            originalAmountMinor = null,
            discountAmountMinor = 0,
            finalAmountMinor = 100,
            categoryId = null,
            confidence = 0.8,
            missingFields = emptyList(),
        )

        assertFalse(item.requiresReview)
    }

    @Test
    fun `typed exception redacts response details`() {
        val error = ReceiptAnalysisException(
            reason = ReceiptAnalysisFailure.UPSTREAM_UNAVAILABLE,
            statusCode = 502,
            quota = null,
            diagnosticCode = "EDGE_FUNCTION_ERROR",
        )

        assertEquals("Receipt analysis failed (UPSTREAM_UNAVAILABLE, HTTP 502)", error.message)
        assertFalse(error.message.orEmpty().contains("private"))
    }

    @Test
    fun `reviewed purchase recomputes exact total and clears item review fields`() {
        val reviewed = item(
            id = "purchase",
            type = BillItemLineType.PURCHASE,
            original = 0,
            discount = 0,
            final = 0,
            categoryId = "category",
            missing = listOf("sourceText", "quantity", "categoryID"),
        ).reviewed(originalAmountMinor = 594, discountAmountMinor = 30, quantity = 3)!!

        assertEquals(3, reviewed.quantity)
        assertEquals(594L, reviewed.originalAmountMinor)
        assertEquals(30L, reviewed.discountAmountMinor)
        assertEquals(564L, reviewed.finalAmountMinor)
        assertEquals(listOf("categoryID"), reviewed.missingFields)
        assertFalse(reviewed.requiresReview)
    }

    @Test
    fun `reviewed discount stays standalone and rejects invalid purchase arithmetic`() {
        val reviewedDiscount = item(
            id = "discount",
            type = BillItemLineType.DISCOUNT,
            original = null,
            discount = 50,
            final = -50,
            categoryId = "must-clear",
            missing = listOf("discountAmountMinor"),
        ).reviewed(originalAmountMinor = 0, discountAmountMinor = 75, quantity = 9)!!

        assertNull(reviewedDiscount.quantity)
        assertNull(reviewedDiscount.originalAmountMinor)
        assertNull(reviewedDiscount.categoryId)
        assertEquals(75L, reviewedDiscount.discountAmountMinor)
        assertEquals(-75L, reviewedDiscount.finalAmountMinor)
        assertTrue(reviewedDiscount.missingFields.isEmpty())

        assertNull(
            item(
                id = "invalid",
                type = BillItemLineType.PURCHASE,
                original = 100,
                discount = 0,
                final = 100,
                categoryId = "category",
            ).reviewed(originalAmountMinor = 100, discountAmountMinor = 101, quantity = 1),
        )
    }

    @Test
    fun `standalone discount allocation preserves total and deterministic remainder`() {
        val first = item("a", BillItemLineType.PURCHASE, 100, 0, 100, "category")
        val second = item("b", BillItemLineType.PURCHASE, 300, 0, 300, "category")
        val discount = item("discount", BillItemLineType.DISCOUNT, null, 41, -41, null)

        val allocated = allocateReceiptDiscount("discount", listOf(first, second, discount))!!

        assertEquals(listOf(10L, 31L), allocated.take(2).map { it.discountAmountMinor })
        assertEquals(listOf(90L, 269L, 0L), allocated.map { it.finalAmountMinor })
        assertEquals(359L, allocated.sumOf { it.finalAmountMinor })
        assertEquals(BillItemLineType.DISCOUNT, allocated.last().lineType)
        assertEquals(41L, allocated.last().discountAmountMinor)
    }

    private fun item(
        id: String,
        type: BillItemLineType,
        original: Long?,
        discount: Long,
        final: Long,
        categoryId: String?,
        missing: List<String> = emptyList(),
    ) = BillItemAnalysisItem(
        lineId = id,
        rawLineText = id,
        originalName = id,
        translatedName = null,
        lineType = type,
        quantity = null,
        originalAmountMinor = original,
        discountAmountMinor = discount,
        finalAmountMinor = final,
        categoryId = categoryId,
        confidence = 1.0,
        missingFields = missing,
    )
}
