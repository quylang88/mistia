package vn.com.quyln.mistia.feature.transactions

import vn.com.quyln.mistia.core.model.BillItemAnalysisResult
import vn.com.quyln.mistia.core.model.PreparedReceiptImage
import vn.com.quyln.mistia.core.model.ReceiptAnalysisException
import vn.com.quyln.mistia.core.model.ReceiptAnalysisFailure
import vn.com.quyln.mistia.core.model.ReceiptAnalysisQuota

internal data class ReceiptReviewBill(
    val id: String,
    val image: PreparedReceiptImage,
    val result: BillItemAnalysisResult? = null,
    val selectedWalletId: String? = null,
    val quota: ReceiptAnalysisQuota? = null,
    val isAnalyzing: Boolean = false,
    val isMultipleBillImage: Boolean = false,
    val failure: ReceiptAnalysisFailure? = null,
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
            if (bill.id == billId) {
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
