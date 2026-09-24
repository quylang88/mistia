package vn.com.quyln.mistia.feature.transactions

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import vn.com.quyln.mistia.core.model.BillItemAnalysisItem
import vn.com.quyln.mistia.core.model.BillItemAnalysisResult
import vn.com.quyln.mistia.core.model.BillItemLineType
import vn.com.quyln.mistia.core.model.PreparedReceiptImage
import vn.com.quyln.mistia.core.model.TransactionDebtIntent
import vn.com.quyln.mistia.core.model.TransactionPrimaryKind
import vn.com.quyln.mistia.core.model.TransactionTransferSubtype

class ReceiptItemSelectionTest {
    @Test
    fun `expense selection requires same wallet and purchase category but accepts discount`() {
        val purchase = candidate("a", walletId = "wallet", categoryId = "food")
        val sameGroup = candidate("b", walletId = "wallet", categoryId = "food")
        val otherCategory = candidate("c", walletId = "wallet", categoryId = "travel")
        val otherWallet = candidate("d", walletId = "other", categoryId = "food")
        val discount = candidate(
            "discount",
            walletId = "wallet",
            categoryId = null,
            lineType = BillItemLineType.DISCOUNT,
            amountMinor = -100,
        )

        assertTrue(ReceiptItemSelectionLogic.canSelect(purchase, emptyList(), ReceiptTransactionMode.EXPENSE))
        assertTrue(ReceiptItemSelectionLogic.canSelect(sameGroup, listOf(purchase), ReceiptTransactionMode.EXPENSE))
        assertTrue(ReceiptItemSelectionLogic.canSelect(discount, listOf(purchase), ReceiptTransactionMode.EXPENSE))
        assertFalse(ReceiptItemSelectionLogic.canSelect(otherCategory, listOf(purchase), ReceiptTransactionMode.EXPENSE))
        assertFalse(ReceiptItemSelectionLogic.canSelect(otherWallet, listOf(purchase), ReceiptTransactionMode.EXPENSE))
    }

    @Test
    fun `lend selection permits mixed categories only within one wallet`() {
        val first = candidate("a", walletId = "wallet", categoryId = "food")
        val differentCategory = candidate("b", walletId = "wallet", categoryId = "travel")
        val otherWallet = candidate("c", walletId = "other", categoryId = "food")

        assertTrue(ReceiptItemSelectionLogic.canSelect(differentCategory, listOf(first), ReceiptTransactionMode.LEND))
        assertFalse(ReceiptItemSelectionLogic.canSelect(otherWallet, listOf(first), ReceiptTransactionMode.LEND))
    }

    @Test
    fun `normalizing after mode change drops incompatible selection`() {
        val first = candidate("a", walletId = "wallet", categoryId = "food")
        val second = candidate("b", walletId = "wallet", categoryId = "travel")

        val normalized = ReceiptItemSelectionLogic.normalizedSelection(
            selection = mapOf(first.id to 1, second.id to 1),
            candidates = listOf(first, second),
            mode = ReceiptTransactionMode.EXPENSE,
        )

        assertEquals(mapOf(first.id to 1), normalized)
    }

    @Test
    fun `expense draft applies standalone discount and carries single bill attachment`() {
        val purchase = candidate(
            itemId = "purchase",
            walletId = "wallet",
            categoryId = "food",
            amountMinor = 1_000,
            merchantName = "FamilyMart",
            occurredAt = "2026-05-19T21:34:00Z",
        )
        val discount = candidate(
            itemId = "discount",
            walletId = "wallet",
            categoryId = null,
            lineType = BillItemLineType.DISCOUNT,
            amountMinor = -150,
            merchantName = "FamilyMart",
            occurredAt = "2026-05-19T21:34:00Z",
        )

        val draft = ReceiptItemSelectionLogic.transactionDraft(
            selected = listOf(purchase, discount),
            mode = ReceiptTransactionMode.EXPENSE,
            fallbackOccurredAt = "1970-01-01T00:00:00Z",
        )!!

        assertEquals(TransactionPrimaryKind.EXPENSE, draft.primaryKind)
        assertNull(draft.transferSubtype)
        assertEquals(850L, draft.amountMinor)
        assertEquals("FamilyMart", draft.title)
        assertEquals("wallet", draft.walletId)
        assertEquals("food", draft.categoryId)
        assertEquals("2026-05-19T21:34:00Z", draft.occurredAt)
        assertEquals("bill", draft.receiptAttachmentBillId)
    }

    @Test
    fun `lend draft uses debt intent and mixed receipt metadata falls back`() {
        val first = candidate(
            itemId = "a",
            billId = "bill-a",
            walletId = "wallet",
            categoryId = null,
            amountMinor = 700,
            merchantName = "FamilyMart",
            occurredAt = "2026-05-19T21:34:00Z",
        )
        val second = candidate(
            itemId = "b",
            billId = "bill-b",
            walletId = "wallet",
            categoryId = "travel",
            amountMinor = 800,
            merchantName = "Lawson",
            occurredAt = "2026-05-20T08:00:00Z",
        )

        val draft = ReceiptItemSelectionLogic.transactionDraft(
            selected = listOf(first, second),
            mode = ReceiptTransactionMode.LEND,
            fallbackOccurredAt = "1970-01-01T00:00:42Z",
        )!!

        assertEquals(TransactionPrimaryKind.TRANSFER, draft.primaryKind)
        assertEquals(TransactionTransferSubtype.DEBT, draft.transferSubtype)
        assertEquals(TransactionDebtIntent.LEND, draft.debtIntent)
        assertEquals(1_500L, draft.amountMinor)
        assertEquals("", draft.title)
        assertEquals("1970-01-01T00:00:42Z", draft.occurredAt)
        assertNull(draft.categoryId)
        assertNull(draft.receiptAttachmentBillId)
    }

    @Test
    fun `quantity allocation preserves exact minor total and group rejects nonpositive sum`() {
        assertEquals(34L, ReceiptItemSelectionLogic.allocationAmount(101, 3, 1))
        assertEquals(68L, ReceiptItemSelectionLogic.allocationAmount(101, 3, 2))
        assertEquals(101L, ReceiptItemSelectionLogic.allocationAmount(101, 3, 3))

        val discountOnly = candidate(
            itemId = "discount",
            walletId = "wallet",
            categoryId = null,
            lineType = BillItemLineType.DISCOUNT,
            amountMinor = -150,
        )
        assertNull(
            ReceiptItemSelectionLogic.lockedGroup(
                selected = listOf(discountOnly),
                mode = ReceiptTransactionMode.EXPENSE,
                id = "group",
            ),
        )

        val purchase = candidate("purchase", walletId = "wallet", categoryId = "food", amountMinor = 1_000)
        val group = ReceiptItemSelectionLogic.lockedGroup(
            selected = listOf(purchase, discountOnly),
            mode = ReceiptTransactionMode.EXPENSE,
            id = "group",
        )!!
        assertEquals(850L, group.amountMinor)
        assertEquals(setOf(purchase.id, discountOnly.id), ReceiptItemSelectionLogic.lockedItemIds(listOf(group)))
    }

    @Test
    fun `review projection preserves bill order and selected quantity amount`() {
        val first = reviewBill(
            id = "bill-a",
            walletId = "wallet",
            items = listOf(reviewItem("milk", quantity = 3, amountMinor = 101)),
        )
        val second = reviewBill(
            id = "bill-b",
            walletId = "wallet",
            items = listOf(reviewItem("bread", quantity = null, amountMinor = 200)),
        )
        val selection = mapOf(ReceiptItemSelectionId("bill-a", "milk") to 2)

        val candidates = ReceiptReviewState(listOf(first, second)).selectionCandidates(selection)

        assertEquals(listOf("bill-a", "bill-b"), candidates.map { it.id.billId })
        assertEquals(3, candidates[0].totalQuantity)
        assertEquals(2, candidates[0].selectedQuantity)
        assertEquals(68L, candidates[0].amountMinor)
        assertEquals(1, candidates[1].availableQuantity)
        assertEquals(200L, candidates[1].amountMinor)
    }

    @Test
    fun `selection toggle keeps one bill and normalizes category compatibility`() {
        val first = candidate("a", billId = "bill-a", walletId = "wallet", categoryId = "food")
        val discount = candidate(
            "discount",
            billId = "bill-a",
            walletId = "wallet",
            categoryId = null,
            lineType = BillItemLineType.DISCOUNT,
            amountMinor = -50,
        )
        val otherBill = candidate("b", billId = "bill-b", walletId = "wallet", categoryId = "food")
        val otherCategory = candidate("c", billId = "bill-a", walletId = "wallet", categoryId = "travel")
        val candidates = listOf(first, discount, otherBill, otherCategory)

        val withFirst = ReceiptItemSelectionLogic.toggleSelection(
            selection = emptyMap(),
            candidateId = first.id,
            candidates = candidates,
            mode = ReceiptTransactionMode.EXPENSE,
        )
        val withDiscount = ReceiptItemSelectionLogic.toggleSelection(
            selection = withFirst,
            candidateId = discount.id,
            candidates = candidates,
            mode = ReceiptTransactionMode.EXPENSE,
        )

        assertEquals(mapOf(first.id to 1, discount.id to 1), withDiscount)
        assertEquals(
            withDiscount,
            ReceiptItemSelectionLogic.toggleSelection(
                withDiscount,
                otherBill.id,
                candidates,
                ReceiptTransactionMode.EXPENSE,
            ),
        )
        assertEquals(
            withDiscount,
            ReceiptItemSelectionLogic.toggleSelection(
                withDiscount,
                otherCategory.id,
                candidates,
                ReceiptTransactionMode.EXPENSE,
            ),
        )
        assertEquals(
            mapOf(first.id to 1),
            ReceiptItemSelectionLogic.toggleSelection(
                withDiscount,
                discount.id,
                candidates,
                ReceiptTransactionMode.EXPENSE,
            ),
        )
    }

    @Test
    fun `review state creates expense draft only from one valid selected bill`() {
        val bill = reviewBill(
            id = "bill-a",
            walletId = "wallet",
            items = listOf(
                reviewItem("milk", quantity = 3, amountMinor = 300),
                reviewItem("bread", quantity = null, amountMinor = 200),
            ),
        )
        val selection = mapOf(ReceiptItemSelectionId("bill-a", "milk") to 2)

        val draft = ReceiptReviewState(listOf(bill)).expenseTransactionDraft(
            selection = selection,
            fallbackOccurredAt = "1970-01-01T00:00:00Z",
        )

        requireNotNull(draft)
        assertEquals(200L, draft.amountMinor)
        assertEquals("wallet", draft.walletId)
        assertEquals("food", draft.categoryId)
        assertEquals("bill-a", draft.receiptAttachmentBillId)
    }

    @Test
    fun `review state launches expense editor with the exact selected bill image`() {
        val bill = reviewBill(
            id = "bill-a",
            walletId = "wallet",
            items = listOf(reviewItem("milk", quantity = null, amountMinor = 300)),
        )

        val launch = ReceiptReviewState(listOf(bill)).transactionLaunch(
            selection = mapOf(ReceiptItemSelectionId("bill-a", "milk") to 1),
            mode = ReceiptTransactionMode.EXPENSE,
            fallbackOccurredAt = NOW_FALLBACK,
        )

        requireNotNull(launch)
        assertEquals("bill-a", launch.draft.receiptAttachmentBillId)
        assertEquals(bill.image, launch.receiptImage)
    }

    @Test
    fun `review state launches lend editor with exact selected bill image`() {
        val bill = reviewBill(
            id = "bill-a",
            walletId = "wallet",
            items = listOf(
                reviewItem("milk", quantity = null, amountMinor = 300),
                reviewItem("train", quantity = null, amountMinor = 500).copy(categoryId = "travel"),
            ),
        )

        val launch = ReceiptReviewState(listOf(bill)).transactionLaunch(
            selection = mapOf(
                ReceiptItemSelectionId("bill-a", "milk") to 1,
                ReceiptItemSelectionId("bill-a", "train") to 1,
            ),
            mode = ReceiptTransactionMode.LEND,
            fallbackOccurredAt = NOW_FALLBACK,
        )

        requireNotNull(launch)
        assertEquals(TransactionPrimaryKind.TRANSFER, launch.draft.primaryKind)
        assertEquals(TransactionTransferSubtype.DEBT, launch.draft.transferSubtype)
        assertEquals(TransactionDebtIntent.LEND, launch.draft.debtIntent)
        assertNull(launch.draft.categoryId)
        assertEquals("bill-a", launch.draft.receiptAttachmentBillId)
        assertEquals(bill.image, launch.receiptImage)
    }

    @Test
    fun `review state rejects flagged incompatible and cross bill selections`() {
        val valid = reviewBill(
            id = "bill-a",
            walletId = "wallet",
            items = listOf(reviewItem("milk", quantity = null, amountMinor = 300)),
        )
        val flagged = reviewBill(
            id = "bill-flagged",
            walletId = "wallet",
            items = listOf(
                reviewItem("unknown", quantity = null, amountMinor = 100).copy(originalName = ""),
            ),
        )
        val state = ReceiptReviewState(listOf(valid, flagged))

        assertNull(
            state.expenseTransactionDraft(
                selection = mapOf(ReceiptItemSelectionId("bill-flagged", "unknown") to 1),
                fallbackOccurredAt = NOW_FALLBACK,
            ),
        )
        assertNull(
            state.expenseTransactionDraft(
                selection = mapOf(
                    ReceiptItemSelectionId("bill-a", "milk") to 1,
                    ReceiptItemSelectionId("bill-flagged", "unknown") to 1,
                ),
                fallbackOccurredAt = NOW_FALLBACK,
            ),
        )
    }

    private fun candidate(
        itemId: String,
        billId: String = "bill",
        walletId: String?,
        categoryId: String?,
        lineType: BillItemLineType = BillItemLineType.PURCHASE,
        amountMinor: Long = 500,
        merchantName: String? = "Store",
        occurredAt: String? = "2026-05-19T21:34:00Z",
    ) = ReceiptItemSelectionCandidate(
        id = ReceiptItemSelectionId(billId, itemId),
        walletId = walletId,
        categoryId = categoryId,
        lineType = lineType,
        amountMinor = amountMinor,
        totalQuantity = 1,
        availableQuantity = 1,
        selectedQuantity = 1,
        createdQuantity = 0,
        lockedQuantity = 0,
        merchantName = merchantName,
        occurredAt = occurredAt,
        isCreated = false,
        isLocked = false,
    )

    private fun reviewBill(
        id: String,
        walletId: String,
        items: List<BillItemAnalysisItem>,
    ) = ReceiptReviewBill(
        id = id,
        image = PreparedReceiptImage(
            imageData = byteArrayOf(1),
            thumbnailData = byteArrayOf(2),
            mimeType = "image/jpeg",
            width = 10,
            height = 20,
        ),
        result = BillItemAnalysisResult(
            merchantName = "Store",
            totalMinor = items.sumOf { it.finalAmountMinor },
            currencyCode = "JPY",
            occurredAt = "2026-05-19T21:34:00Z",
            walletId = walletId,
            multipleBillsDetected = false,
            confidence = 1.0,
            missingFields = emptyList(),
            rawText = null,
            items = items,
            quota = null,
        ),
        selectedWalletId = walletId,
    )

    private fun reviewItem(
        id: String,
        quantity: Int?,
        amountMinor: Long,
    ) = BillItemAnalysisItem(
        lineId = id,
        rawLineText = id,
        originalName = id,
        translatedName = null,
        lineType = BillItemLineType.PURCHASE,
        quantity = quantity,
        originalAmountMinor = amountMinor,
        discountAmountMinor = 0,
        finalAmountMinor = amountMinor,
        categoryId = "food",
        confidence = 1.0,
        missingFields = emptyList(),
    )

    private companion object {
        const val NOW_FALLBACK = "1970-01-01T00:00:00Z"
    }
}
