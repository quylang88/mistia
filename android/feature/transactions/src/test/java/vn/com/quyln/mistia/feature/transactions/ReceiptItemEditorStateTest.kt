package vn.com.quyln.mistia.feature.transactions

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Test
import vn.com.quyln.mistia.core.model.BillItemAnalysisItem
import vn.com.quyln.mistia.core.model.BillItemAnalysisResult
import vn.com.quyln.mistia.core.model.BillItemLineType
import vn.com.quyln.mistia.core.model.PreparedReceiptImage

class ReceiptItemEditorStateTest {
    @Test
    fun `purchase edit parses currency precision and preserves literal OCR evidence`() {
        val source = item(
            raw = "3@ ミルク 198",
            name = "ミルク",
            originalAmountMinor = 594,
            missingFields = listOf("quantity", "originalAmountMinor"),
        )
        val state = ReceiptItemEditorState.from(source, "JPY").copy(
            originalName = "牛乳",
            translatedName = "Milk",
            quantityText = "3",
            originalAmountText = "594",
            discountAmountText = "41",
        )

        val edited = state.reviewedItem()

        requireNotNull(edited)
        assertEquals("3@ ミルク 198", edited.rawLineText)
        assertEquals("牛乳", edited.originalName)
        assertEquals("Milk", edited.translatedName)
        assertEquals(3, edited.quantity)
        assertEquals(594L, edited.originalAmountMinor)
        assertEquals(41L, edited.discountAmountMinor)
        assertEquals(553L, edited.finalAmountMinor)
        assertFalse(edited.requiresReview)
    }

    @Test
    fun `purchase edit accepts exact decimal currency values`() {
        val edited = ReceiptItemEditorState.from(item(), "USD").copy(
            originalAmountText = "12.34",
            discountAmountText = "0.35",
        ).reviewedItem()

        requireNotNull(edited)
        assertEquals(1_234L, edited.originalAmountMinor)
        assertEquals(35L, edited.discountAmountMinor)
        assertEquals(1_199L, edited.finalAmountMinor)
    }

    @Test
    fun `discount edit normalizes hidden purchase fields`() {
        val edited = ReceiptItemEditorState.from(item(), "JPY").copy(
            lineType = BillItemLineType.DISCOUNT,
            discountAmountText = "41",
            quantityText = "not visible",
            originalAmountText = "not visible",
        ).reviewedItem()

        requireNotNull(edited)
        assertEquals(BillItemLineType.DISCOUNT, edited.lineType)
        assertNull(edited.quantity)
        assertNull(edited.originalAmountMinor)
        assertNull(edited.categoryId)
        assertEquals(41L, edited.discountAmountMinor)
        assertEquals(-41L, edited.finalAmountMinor)
        assertFalse(edited.requiresReview)
    }

    @Test
    fun `item edit rejects invalid names amounts quantities and precision`() {
        val valid = ReceiptItemEditorState.from(item(), "USD")

        assertNull(valid.copy(originalName = "  ").reviewedItem())
        assertNull(valid.copy(quantityText = "0").reviewedItem())
        assertNull(valid.copy(originalAmountText = "12.345").reviewedItem())
        assertNull(valid.copy(originalAmountText = "1", discountAmountText = "2").reviewedItem())
        assertNull(
            valid.copy(
                lineType = BillItemLineType.DISCOUNT,
                discountAmountText = "0",
            ).reviewedItem(),
        )
    }

    @Test
    fun `review item update replaces target and clears only its selection`() {
        val source = item()
        val edited = ReceiptItemEditorState.from(source, "JPY").copy(
            originalName = "Edited",
            originalAmountText = "120",
            discountAmountText = "20",
        ).reviewedItem()!!
        val target = bill("target", source, 1)
        val sibling = bill("sibling", source.copy(lineId = "sibling-item"), 2)
        val targetSelection = ReceiptItemSelectionId("target", "item")
        val siblingSelection = ReceiptItemSelectionId("sibling", "sibling-item")

        val update = ReceiptReviewState(listOf(target, sibling)).updateItemForReview(
            billId = "target",
            edited = edited,
            selection = mapOf(targetSelection to 1, siblingSelection to 1),
        )

        assertEquals("Edited", update.state.bills.first().result?.items?.single()?.originalName)
        assertEquals(100L, update.state.bills.first().result?.items?.single()?.finalAmountMinor)
        assertSame(sibling, update.state.bills.last())
        assertEquals(mapOf(siblingSelection to 1), update.selection)
    }

    @Test
    fun `review item removal deletes target and clears only its bill selection`() {
        val source = item()
        val target = bill("target", source, 1)
        val sibling = bill("sibling", source.copy(lineId = "sibling-item"), 2)
        val targetSelection = ReceiptItemSelectionId("target", "item")
        val siblingSelection = ReceiptItemSelectionId("sibling", "sibling-item")

        val update = ReceiptReviewState(listOf(target, sibling)).removeItemForReview(
            billId = "target",
            itemId = "item",
            selection = mapOf(targetSelection to 1, siblingSelection to 1),
        )

        assertEquals(emptyList<BillItemAnalysisItem>(), update.state.bills.first().result?.items)
        assertSame(sibling, update.state.bills.last())
        assertEquals(mapOf(siblingSelection to 1), update.selection)
    }

    private fun item(
        raw: String = "Item 100",
        name: String = "Item",
        originalAmountMinor: Long = 100,
        missingFields: List<String> = emptyList(),
    ) = BillItemAnalysisItem(
        lineId = "item",
        rawLineText = raw,
        originalName = name,
        translatedName = null,
        lineType = BillItemLineType.PURCHASE,
        quantity = null,
        originalAmountMinor = originalAmountMinor,
        discountAmountMinor = 0,
        finalAmountMinor = originalAmountMinor,
        categoryId = "food",
        confidence = 0.9,
        missingFields = missingFields,
    )

    private fun bill(
        id: String,
        item: BillItemAnalysisItem,
        imageByte: Int,
    ) = ReceiptReviewBill(
        id = id,
        image = PreparedReceiptImage(
            imageData = byteArrayOf(imageByte.toByte()),
            thumbnailData = byteArrayOf((imageByte + 10).toByte()),
            mimeType = "image/jpeg",
            width = 100,
            height = 200,
        ),
        result = BillItemAnalysisResult(
            merchantName = "Store",
            totalMinor = item.finalAmountMinor,
            currencyCode = "JPY",
            occurredAt = null,
            walletId = "wallet",
            multipleBillsDetected = false,
            confidence = 0.9,
            missingFields = emptyList(),
            rawText = "literal receipt",
            items = listOf(item),
            quota = null,
        ),
    )
}
