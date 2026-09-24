package vn.com.quyln.mistia.feature.transactions

import vn.com.quyln.mistia.core.model.BillItemAnalysisResult
import vn.com.quyln.mistia.core.model.BillItemAnalysisItem
import vn.com.quyln.mistia.core.model.PreparedReceiptImage
import vn.com.quyln.mistia.core.model.ReceiptAnalysisException
import vn.com.quyln.mistia.core.model.ReceiptAnalysisFailure
import vn.com.quyln.mistia.core.model.ReceiptAnalysisQuota
import vn.com.quyln.mistia.core.model.allocateReceiptDiscount

internal data class ReceiptReviewBill(
    val id: String,
    val image: PreparedReceiptImage,
    val result: BillItemAnalysisResult? = null,
    val selectedWalletId: String? = null,
    val quota: ReceiptAnalysisQuota? = null,
    val isAnalyzing: Boolean = false,
    val isMultipleBillImage: Boolean = false,
    val failure: ReceiptAnalysisFailure? = null,
    val createdAllocations: Map<String, ReceiptItemQuantityAllocation> = emptyMap(),
    val lockedGroups: List<ReceiptItemLockedGroup> = emptyList(),
)

internal data class ReceiptReviewState(
    val bills: List<ReceiptReviewBill> = emptyList(),
) {
    val remainingCapacity: Int
        get() = (ReceiptPhotoPickerLimits.MAX_IMAGES - bills.size).coerceAtLeast(0)

    val pendingBills: List<ReceiptReviewBill>
        get() = bills.filter { bill ->
            bill.result == null && !bill.isMultipleBillImage && !bill.isAnalyzing
        }

    val hasTransientAnalysis: Boolean
        get() = bills.isNotEmpty()

    fun append(
        images: List<PreparedReceiptImage>,
        idProvider: () -> String,
    ): ReceiptReviewState {
        if (images.isEmpty() || remainingCapacity == 0) return this
        val additions = images.take(remainingCapacity).map { image ->
            ReceiptReviewBill(id = idProvider(), image = image)
        }
        return copy(bills = bills + additions)
    }

    fun beginPendingAnalysis(): ReceiptReviewAnalysisBatch {
        val pendingIds = pendingBills.map(ReceiptReviewBill::id)
        val pendingIdSet = pendingIds.toSet()
        return ReceiptReviewAnalysisBatch(
            state = copy(
                bills = bills.map { bill ->
                    if (bill.id in pendingIdSet) {
                        bill.copy(isAnalyzing = true, failure = null)
                    } else {
                        bill
                    }
                },
            ),
            billIds = pendingIds,
            images = pendingBills.map(ReceiptReviewBill::image),
        )
    }

    fun retry(billId: String): ReceiptReviewState = copy(
        bills = bills.map { bill ->
            if (bill.id == billId && bill.canRevise) {
                bill.copy(
                    result = null,
                    selectedWalletId = null,
                    quota = null,
                    isAnalyzing = false,
                    isMultipleBillImage = false,
                    failure = null,
                )
            } else {
                bill
            }
        },
    )

    fun remove(billId: String): ReceiptReviewState = copy(
        bills = bills.filterNot { it.id == billId },
    )

    fun selectWallet(billId: String, walletId: String?): ReceiptReviewState =
        updateBill(billId) { bill -> bill.copy(selectedWalletId = walletId) }

    fun updateTotal(billId: String, totalMinor: Long): ReceiptReviewState =
        updateBill(billId) { bill ->
            if (!bill.canRevise) return@updateBill bill
            val result = bill.result ?: return@updateBill bill
            bill.copy(result = result.copy(totalMinor = totalMinor))
        }

    fun updateItemCategory(
        billId: String,
        itemId: String,
        categoryId: String?,
    ): ReceiptReviewState = updateBillResultIfPresent(billId) { result ->
        result.copy(
            items = result.items.map { item ->
                if (item.lineId == itemId) item.copy(categoryId = categoryId) else item
            },
        )
    }

    fun updateItem(
        billId: String,
        edited: BillItemAnalysisItem,
    ): ReceiptReviewState = updateBill(billId) { bill ->
        val itemId = ReceiptItemSelectionId(billId, edited.lineId)
        if (edited.lineId in bill.createdAllocations ||
            bill.lockedGroups.any { itemId in it.itemAllocations }
        ) {
            return@updateBill bill
        }
        val result = bill.result ?: return@updateBill bill
        bill.copy(result = result.copy(
            items = result.items.map { item ->
                if (item.lineId == edited.lineId) edited else item
            },
        ))
    }

    fun allocateDiscount(
        billId: String,
        itemId: String,
    ): ReceiptReviewState = updateBillResultIfRevisable(billId) transform@{ result ->
        val allocated = allocateReceiptDiscount(itemId, result.items) ?: return@transform result
        result.copy(items = allocated)
    }

    fun removeItem(
        billId: String,
        itemId: String,
    ): ReceiptReviewState = updateBillResultIfRevisable(billId) { result ->
        result.copy(items = result.items.filterNot { it.lineId == itemId })
    }

    private fun updateBill(
        billId: String,
        transform: (ReceiptReviewBill) -> ReceiptReviewBill,
    ): ReceiptReviewState = copy(
        bills = bills.map { bill -> if (bill.id == billId) transform(bill) else bill },
    )

    private fun updateBillResultIfPresent(
        billId: String,
        transform: (BillItemAnalysisResult) -> BillItemAnalysisResult,
    ): ReceiptReviewState = updateBill(billId) { bill ->
        val result = bill.result ?: return@updateBill bill
        bill.copy(result = transform(result))
    }

    private fun updateBillResultIfRevisable(
        billId: String,
        transform: (BillItemAnalysisResult) -> BillItemAnalysisResult,
    ): ReceiptReviewState = updateBill(billId) { bill ->
        if (!bill.canRevise) return@updateBill bill
        val result = bill.result ?: return@updateBill bill
        bill.copy(result = transform(result))
    }
}

internal val ReceiptReviewBill.canRevise: Boolean
    get() = createdAllocations.isEmpty() && lockedGroups.isEmpty()

internal data class ReceiptReviewEditUpdate(
    val state: ReceiptReviewState,
    val selection: Map<ReceiptItemSelectionId, Int>,
)

internal fun ReceiptReviewState.selectWalletForReview(
    billId: String,
    walletId: String?,
    selection: Map<ReceiptItemSelectionId, Int>,
): ReceiptReviewEditUpdate = ReceiptReviewEditUpdate(
    state = selectWallet(billId, walletId),
    selection = selection.filterKeys { it.billId != billId },
)

internal fun ReceiptReviewState.updateItemCategoryForReview(
    billId: String,
    itemId: String,
    categoryId: String?,
    selection: Map<ReceiptItemSelectionId, Int>,
): ReceiptReviewEditUpdate = ReceiptReviewEditUpdate(
    state = updateItemCategory(billId, itemId, categoryId),
    selection = selection.filterKeys { it.billId != billId },
)

internal fun ReceiptReviewState.updateItemForReview(
    billId: String,
    edited: BillItemAnalysisItem,
    selection: Map<ReceiptItemSelectionId, Int>,
): ReceiptReviewEditUpdate = ReceiptReviewEditUpdate(
    state = updateItem(billId, edited),
    selection = selection.filterKeys { it.billId != billId },
)

internal fun ReceiptReviewState.removeItemForReview(
    billId: String,
    itemId: String,
    selection: Map<ReceiptItemSelectionId, Int>,
): ReceiptReviewEditUpdate = ReceiptReviewEditUpdate(
    state = removeItem(billId, itemId),
    selection = selection.filterKeys { it.billId != billId },
)

internal fun ReceiptReviewState.allocateDiscountForReview(
    billId: String,
    itemId: String,
    selection: Map<ReceiptItemSelectionId, Int>,
): ReceiptReviewEditUpdate? {
    val items = bills.firstOrNull { it.id == billId }?.result?.items ?: return null
    if (allocateReceiptDiscount(itemId, items) == null) return null
    return ReceiptReviewEditUpdate(
        state = allocateDiscount(billId, itemId),
        selection = selection.filterKeys { it.billId != billId },
    )
}

internal fun ReceiptReviewState.updateTotalForReview(
    billId: String,
    amountText: String,
    currencyCode: String,
    selection: Map<ReceiptItemSelectionId, Int>,
): ReceiptReviewEditUpdate? {
    val totalMinor = parseMinorInput(amountText, currencyCode)?.takeIf { it > 0 } ?: return null
    return ReceiptReviewEditUpdate(
        state = updateTotal(billId, totalMinor),
        selection = selection.filterKeys { it.billId != billId },
    )
}

internal data class ReceiptReviewAnalysisBatch(
    val state: ReceiptReviewState,
    val billIds: List<String>,
    val images: List<PreparedReceiptImage>,
) {
    fun fail(error: ReceiptAnalysisException): ReceiptReviewState {
        val startedIds = billIds.toSet()
        return state.copy(
            bills = state.bills.map { bill ->
                if (bill.id in startedIds) {
                    bill.copy(
                        result = null,
                        selectedWalletId = null,
                        quota = error.quota,
                        isAnalyzing = false,
                        isMultipleBillImage = false,
                        failure = error.reason,
                    )
                } else {
                    bill
                }
            },
        )
    }

    fun complete(
        attempts: List<ReceiptAnalysisAttempt>,
        categoryIds: Set<String>,
        walletIds: Set<String>,
    ): ReceiptReviewState {
        require(attempts.size == billIds.size) {
            "Receipt analysis attempts must match the started batch"
        }
        val attemptsByBillId = billIds.zip(attempts).toMap()
        return state.copy(
            bills = state.bills.map { bill ->
                val attempt = attemptsByBillId[bill.id] ?: return@map bill
                val result = attempt.result?.validated(
                    categoryIds = categoryIds,
                    walletIds = walletIds,
                )
                when {
                    attempt.failure != null -> bill.copy(
                        result = null,
                        selectedWalletId = null,
                        quota = attempt.failure.quota,
                        isAnalyzing = false,
                        isMultipleBillImage = false,
                        failure = attempt.failure.reason,
                    )
                    result?.multipleBillsDetected == true -> bill.copy(
                        result = null,
                        selectedWalletId = null,
                        quota = result.quota,
                        isAnalyzing = false,
                        isMultipleBillImage = true,
                        failure = null,
                    )
                    result != null -> bill.copy(
                        result = result,
                        selectedWalletId = result.walletId,
                        quota = result.quota,
                        isAnalyzing = false,
                        isMultipleBillImage = false,
                        failure = null,
                    )
                    else -> bill.copy(
                        result = null,
                        selectedWalletId = null,
                        isAnalyzing = false,
                        isMultipleBillImage = false,
                        failure = ReceiptAnalysisFailure.INVALID_RESPONSE,
                    )
                }
            },
        )
    }
}
