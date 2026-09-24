package vn.com.quyln.mistia.feature.transactions

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import vn.com.quyln.mistia.core.model.BillItemAnalysisItem
import vn.com.quyln.mistia.core.model.BillItemAnalysisResult
import vn.com.quyln.mistia.core.model.BillItemLineType
import vn.com.quyln.mistia.core.model.PreparedReceiptImage
import vn.com.quyln.mistia.core.model.ReceiptAnalysisException
import vn.com.quyln.mistia.core.model.ReceiptAnalysisFailure
import vn.com.quyln.mistia.core.model.ReceiptAnalysisQuota

class ReceiptReviewStateTest {
    @Test
    fun `append preserves image order and enforces five bill limit`() {
        var nextId = 0
        val state = ReceiptReviewState()
            .append((1..4).map(::prepared)) { "bill-${++nextId}" }
            .append(listOf(prepared(5), prepared(6))) { "bill-${++nextId}" }

        assertEquals(listOf("bill-1", "bill-2", "bill-3", "bill-4", "bill-5"), state.bills.map { it.id })
        assertEquals(listOf(1, 2, 3, 4, 5), state.bills.map { it.image.imageData.single().toInt() })
        assertEquals(0, state.remainingCapacity)
        assertTrue(state.hasTransientAnalysis)
        assertFalse(ReceiptReviewState().hasTransientAnalysis)
    }

    @Test
    fun `analysis batch contains only pending bills and marks them analyzing`() {
        val analyzed = ReceiptReviewBill(
            id = "ready",
            image = prepared(1),
            result = result(walletId = "wallet"),
            selectedWalletId = "wallet",
        )
        val blocked = ReceiptReviewBill(
            id = "multiple",
            image = prepared(2),
            isMultipleBillImage = true,
        )
        val pending = ReceiptReviewBill(id = "pending", image = prepared(3))

        val batch = ReceiptReviewState(listOf(analyzed, blocked, pending)).beginPendingAnalysis()

        assertEquals(listOf("pending"), batch.billIds)
        assertSame(pending.image, batch.images.single())
        assertFalse(batch.state.bills[0].isAnalyzing)
        assertFalse(batch.state.bills[1].isAnalyzing)
        assertTrue(batch.state.bills[2].isAnalyzing)
        assertTrue(batch.state.beginPendingAnalysis().billIds.isEmpty())
    }

    @Test
    fun `completion validates candidates and preserves literal rows and partial failures`() {
        val rawPurchase = item(
            id = "purchase",
            raw = "3@ まろやかミルク 198",
            name = "まろやかミルク",
            type = BillItemLineType.PURCHASE,
            quantity = 3,
            finalAmount = 594,
            categoryId = "unknown-category",
        )
        val rawDiscount = item(
            id = "discount",
            raw = "クーポン -50",
            name = "クーポン",
            type = BillItemLineType.DISCOUNT,
            quantity = null,
            finalAmount = -50,
            categoryId = null,
        )
        val state = ReceiptReviewState()
            .append(listOf(prepared(1), prepared(2), prepared(3))) { indexId() }
        val batch = state.beginPendingAnalysis()
        val attempts = listOf(
            ReceiptAnalysisAttempt(
                image = batch.images[0],
                result = result(
                    walletId = "unknown-wallet",
                    items = listOf(rawPurchase, rawDiscount),
                    rawText = "3@ まろやかミルク 198\nクーポン -50",
                ),
                failure = null,
            ),
            ReceiptAnalysisAttempt(
                image = batch.images[1],
                result = result(multipleBills = true),
                failure = null,
            ),
            ReceiptAnalysisAttempt(
                image = batch.images[2],
                result = null,
                failure = ReceiptAnalysisException(ReceiptAnalysisFailure.DAILY_LIMIT_REACHED),
            ),
        )

        val completed = batch.complete(
            attempts = attempts,
            categoryIds = setOf("allowed-category"),
            walletIds = setOf("allowed-wallet"),
        )

        val ready = completed.bills[0]
        assertNull(ready.selectedWalletId)
        assertEquals(listOf("purchase", "discount"), ready.result?.items?.map { it.lineId })
        assertEquals("3@ まろやかミルク 198", ready.result?.items?.first()?.rawLineText)
        assertEquals(3, ready.result?.items?.first()?.quantity)
        assertNull(ready.result?.items?.first()?.categoryId)
        assertEquals(BillItemLineType.DISCOUNT, ready.result?.items?.last()?.lineType)
        assertEquals(-50L, ready.result?.items?.last()?.finalAmountMinor)
        assertEquals("3@ まろやかミルク 198\nクーポン -50", ready.result?.rawText)
        assertTrue(ready.result?.missingFields?.containsAll(listOf("categoryID", "walletID")) == true)
        assertFalse(ready.isAnalyzing)

        val multiple = completed.bills[1]
        assertTrue(multiple.isMultipleBillImage)
        assertNull(multiple.result)
        assertFalse(multiple.isAnalyzing)

        val failed = completed.bills[2]
        assertEquals(ReceiptAnalysisFailure.DAILY_LIMIT_REACHED, failed.failure)
        assertNull(failed.result)
        assertFalse(failed.isAnalyzing)
    }

    @Test
    fun `retry clears review outcome without changing image and remove is isolated`() {
        val firstImage = prepared(1)
        val secondImage = prepared(2)
        val state = ReceiptReviewState(
            bills = listOf(
                ReceiptReviewBill(
                    id = "first",
                    image = firstImage,
                    isMultipleBillImage = true,
                    failure = ReceiptAnalysisFailure.INVALID_RESPONSE,
                ),
                ReceiptReviewBill(id = "second", image = secondImage, result = result()),
            ),
        )

        val retry = state.retry("first")
        assertSame(firstImage, retry.bills.first().image)
        assertFalse(retry.bills.first().isMultipleBillImage)
        assertNull(retry.bills.first().failure)
        assertTrue(retry.pendingBills.single().id == "first")

        val removed = retry.remove("first")
        assertEquals(listOf("second"), removed.bills.map { it.id })
        assertSame(secondImage, removed.bills.single().image)
    }

    @Test
    fun `fatal batch failure clears progress for only started bills`() {
        val ready = ReceiptReviewBill(id = "ready", image = prepared(1), result = result())
        val initial = ReceiptReviewState(listOf(ready))
            .append(listOf(prepared(2), prepared(3))) { indexId() }
        val batch = initial.beginPendingAnalysis()
        val quota = ReceiptAnalysisQuota(
            allowed = false,
            usedCount = 5,
            limitCount = 5,
            remainingCount = 0,
            usageDate = "2026-09-24",
            resetTimeZone = "Asia/Tokyo",
            retryAfter = null,
        )

        val failed = batch.fail(
            ReceiptAnalysisException(
                reason = ReceiptAnalysisFailure.DAILY_LIMIT_REACHED,
                quota = quota,
            ),
        )

        assertSame(ready.result, failed.bills[0].result)
        assertNull(failed.bills[0].failure)
        assertEquals(
            listOf(ReceiptAnalysisFailure.DAILY_LIMIT_REACHED, ReceiptAnalysisFailure.DAILY_LIMIT_REACHED),
            failed.bills.drop(1).map { it.failure },
        )
        assertTrue(failed.bills.drop(1).all { !it.isAnalyzing && it.quota == quota })
    }

    @Test
    fun `review edits mutate only targeted bill and preserve literal item evidence`() {
        val purchase = item(
            id = "purchase",
            raw = "3@ ミルク 198",
            name = "ミルク",
            type = BillItemLineType.PURCHASE,
            quantity = 3,
            finalAmount = 594,
            categoryId = null,
        ).copy(
            originalAmountMinor = 594,
            missingFields = listOf("categoryID", "quantity"),
        )
        val discount = item(
            id = "discount",
            raw = "クーポン -41",
            name = "クーポン",
            type = BillItemLineType.DISCOUNT,
            quantity = null,
            finalAmount = -41,
            categoryId = null,
        ).copy(discountAmountMinor = 41)
        val target = ReceiptReviewBill(
            id = "target",
            image = prepared(1),
            result = result(items = listOf(purchase, discount), rawText = "literal"),
        )
        val sibling = ReceiptReviewBill(id = "sibling", image = prepared(2), result = result())

        val editedItem = purchase.reviewed(594, 0, 3)!!
        val edited = ReceiptReviewState(listOf(target, sibling))
            .selectWallet("target", "wallet")
            .updateTotal("target", 553)
            .updateItem("target", editedItem)
            .updateItemCategory("target", "purchase", "food")
            .allocateDiscount("target", "discount")

        val updated = edited.bills.first()
        assertEquals("wallet", updated.selectedWalletId)
        assertEquals(553L, updated.result?.totalMinor)
        assertEquals("3@ ミルク 198", updated.result?.items?.first()?.rawLineText)
        assertEquals("food", updated.result?.items?.first()?.categoryId)
        assertEquals(41L, updated.result?.items?.first()?.discountAmountMinor)
        assertEquals(553L, updated.result?.items?.first()?.finalAmountMinor)
        assertEquals(0L, updated.result?.items?.last()?.finalAmountMinor)
        assertEquals("literal", updated.result?.rawText)
        assertSame(sibling, edited.bills.last())

        val removed = edited.removeItem("target", "discount")
        assertEquals(listOf("purchase"), removed.bills.first().result?.items?.map { it.lineId })
        assertSame(sibling, removed.bills.last())
    }

    @Test
    fun `wallet review change clears only the edited bill selection`() {
        val target = ReceiptReviewBill(id = "target", image = prepared(1), result = result())
        val sibling = ReceiptReviewBill(id = "sibling", image = prepared(2), result = result())
        val targetItem = ReceiptItemSelectionId("target", "item")
        val siblingItem = ReceiptItemSelectionId("sibling", "item")

        val update = ReceiptReviewState(listOf(target, sibling)).selectWalletForReview(
            billId = "target",
            walletId = "wallet",
            selection = mapOf(targetItem to 1, siblingItem to 1),
        )

        assertEquals("wallet", update.state.bills.first().selectedWalletId)
        assertEquals(mapOf(siblingItem to 1), update.selection)
    }

    @Test
    fun `category review change clears only the edited bill selection`() {
        val target = ReceiptReviewBill(id = "target", image = prepared(1), result = result())
        val sibling = ReceiptReviewBill(id = "sibling", image = prepared(2), result = result())
        val targetItem = ReceiptItemSelectionId("target", "item")
        val siblingItem = ReceiptItemSelectionId("sibling", "item")

        val update = ReceiptReviewState(listOf(target, sibling)).updateItemCategoryForReview(
            billId = "target",
            itemId = "item",
            categoryId = "food",
            selection = mapOf(targetItem to 1, siblingItem to 1),
        )

        assertEquals("food", update.state.bills.first().result?.items?.first()?.categoryId)
        assertEquals(mapOf(siblingItem to 1), update.selection)
    }

    private var generatedId = 0

    private fun indexId(): String = "bill-${++generatedId}"

    private fun prepared(value: Int) = PreparedReceiptImage(
        imageData = byteArrayOf(value.toByte()),
        thumbnailData = byteArrayOf((value + 10).toByte()),
        mimeType = "image/jpeg",
        width = 100,
        height = 200,
    )

    private fun result(
        walletId: String? = null,
        items: List<BillItemAnalysisItem> = listOf(
            item(
                id = "item",
                raw = "商品 100",
                name = "商品",
                type = BillItemLineType.PURCHASE,
                quantity = null,
                finalAmount = 100,
                categoryId = "allowed-category",
            ),
        ),
        rawText: String? = null,
        multipleBills: Boolean = false,
    ) = BillItemAnalysisResult(
        merchantName = "店",
        totalMinor = 100,
        currencyCode = "JPY",
        occurredAt = null,
        walletId = walletId,
        multipleBillsDetected = multipleBills,
        confidence = 0.9,
        missingFields = emptyList(),
        rawText = rawText,
        items = items,
        quota = null,
    )

    private fun item(
        id: String,
        raw: String,
        name: String,
        type: BillItemLineType,
        quantity: Int?,
        finalAmount: Long,
        categoryId: String?,
    ) = BillItemAnalysisItem(
        lineId = id,
        rawLineText = raw,
        originalName = name,
        translatedName = null,
        lineType = type,
        quantity = quantity,
        originalAmountMinor = finalAmount.takeIf { type == BillItemLineType.PURCHASE },
        discountAmountMinor = 0,
        finalAmountMinor = finalAmount,
        categoryId = categoryId,
        confidence = 0.9,
        missingFields = emptyList(),
    )
}
