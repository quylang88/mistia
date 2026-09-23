package vn.com.quyln.mistia.feature.transactions

import vn.com.quyln.mistia.core.model.BillItemLineType
import vn.com.quyln.mistia.core.model.TransactionDebtIntent
import vn.com.quyln.mistia.core.model.TransactionPrimaryKind
import vn.com.quyln.mistia.core.model.TransactionTransferSubtype

internal enum class ReceiptTransactionMode {
    EXPENSE,
    LEND,
}

internal data class ReceiptItemSelectionId(
    val billId: String,
    val itemId: String,
)

internal data class ReceiptItemQuantityAllocation(
    val quantity: Int,
    val amountMinor: Long,
)

internal data class ReceiptItemSelectionCandidate(
    val id: ReceiptItemSelectionId,
    val walletId: String?,
    val categoryId: String?,
    val lineType: BillItemLineType,
    val amountMinor: Long,
    val totalQuantity: Int,
    val availableQuantity: Int,
    val selectedQuantity: Int,
    val createdQuantity: Int,
    val lockedQuantity: Int,
    val merchantName: String?,
    val occurredAt: String?,
    val isCreated: Boolean,
    val isLocked: Boolean,
)

internal data class ReceiptItemLockedGroup(
    val id: String,
    val mode: ReceiptTransactionMode,
    val itemAllocations: Map<ReceiptItemSelectionId, ReceiptItemQuantityAllocation>,
    val amountMinor: Long,
) {
    val itemIds: Set<ReceiptItemSelectionId>
        get() = itemAllocations.keys
}

internal data class ReceiptItemTransactionDraft(
    val primaryKind: TransactionPrimaryKind,
    val transferSubtype: TransactionTransferSubtype?,
    val debtIntent: TransactionDebtIntent?,
    val amountMinor: Long,
    val title: String,
    val walletId: String,
    val categoryId: String?,
    val occurredAt: String,
    val receiptAttachmentBillId: String?,
)

internal object ReceiptItemSelectionLogic {
    fun allocationAmount(
        totalAmountMinor: Long,
        totalQuantity: Int,
        allocatedQuantity: Int,
    ): Long {
        val quantity = totalQuantity.coerceAtLeast(0)
        val allocated = allocatedQuantity.coerceIn(0, quantity)
        if (quantity == 0 || allocated == 0) return 0
        val base = totalAmountMinor / quantity.toLong()
        val remainder = totalAmountMinor % quantity.toLong()
        return allocated * base + minOf(allocated.toLong(), remainder.coerceAtLeast(0))
    }

    fun canSelect(
        candidate: ReceiptItemSelectionCandidate,
        selected: List<ReceiptItemSelectionCandidate>,
        mode: ReceiptTransactionMode,
    ): Boolean {
        if (
            candidate.isCreated ||
            candidate.isLocked ||
            candidate.availableQuantity <= 0 ||
            candidate.amountMinor == 0L ||
            candidate.walletId == null
        ) {
            return false
        }
        if (
            mode == ReceiptTransactionMode.EXPENSE &&
            candidate.lineType == BillItemLineType.PURCHASE &&
            candidate.categoryId == null
        ) {
            return false
        }
        val anchor = selected.firstOrNull() ?: return true
        if (candidate.walletId != anchor.walletId) return false
        return when (mode) {
            ReceiptTransactionMode.LEND -> true
            ReceiptTransactionMode.EXPENSE -> {
                if (candidate.lineType == BillItemLineType.DISCOUNT) {
                    true
                } else {
                    val purchaseAnchor = selected.firstOrNull {
                        it.lineType == BillItemLineType.PURCHASE
                    }
                    purchaseAnchor == null || candidate.categoryId == purchaseAnchor.categoryId
                }
            }
        }
    }

    fun normalizedSelection(
        selection: Map<ReceiptItemSelectionId, Int>,
        candidates: List<ReceiptItemSelectionCandidate>,
        mode: ReceiptTransactionMode,
    ): Map<ReceiptItemSelectionId, Int> {
        val normalized = mutableListOf<ReceiptItemSelectionCandidate>()
        candidates.forEach { candidate ->
            if ((selection[candidate.id] ?: 0) > 0 && canSelect(candidate, normalized, mode)) {
                normalized += candidate
            }
        }
        return normalized.associate { candidate ->
            candidate.id to (selection[candidate.id] ?: candidate.selectedQuantity)
                .coerceIn(1, candidate.availableQuantity)
        }
    }

    fun toggleSelection(
        selection: Map<ReceiptItemSelectionId, Int>,
        candidateId: ReceiptItemSelectionId,
        candidates: List<ReceiptItemSelectionCandidate>,
        mode: ReceiptTransactionMode,
    ): Map<ReceiptItemSelectionId, Int> {
        if (candidateId in selection) return selection - candidateId
        val candidate = candidates.firstOrNull { it.id == candidateId } ?: return selection
        val anchorBillId = selection.keys.firstOrNull()?.billId
        if (anchorBillId != null && candidate.id.billId != anchorBillId) return selection
        val selectedCandidates = candidates.filter { it.id in selection }
        if (!canSelect(candidate, selectedCandidates, mode)) return selection
        return normalizedSelection(
            selection = selection + (candidate.id to candidate.availableQuantity),
            candidates = candidates,
            mode = mode,
        )
    }

    fun lockedGroup(
        selected: List<ReceiptItemSelectionCandidate>,
        mode: ReceiptTransactionMode,
        id: String,
    ): ReceiptItemLockedGroup? {
        val candidates = selected.filter { candidate ->
            !candidate.isCreated &&
                !candidate.isLocked &&
                candidate.availableQuantity > 0 &&
                candidate.selectedQuantity > 0 &&
                candidate.amountMinor != 0L
        }
        val amount = candidates.sumOf(ReceiptItemSelectionCandidate::amountMinor)
        if (amount <= 0 || candidates.isEmpty()) return null
        val selectedIds = candidates.associate { it.id to it.selectedQuantity }
        if (normalizedSelection(selectedIds, candidates, mode).keys != selectedIds.keys) return null
        return ReceiptItemLockedGroup(
            id = id,
            mode = mode,
            itemAllocations = candidates.associate { candidate ->
                candidate.id to ReceiptItemQuantityAllocation(
                    quantity = candidate.selectedQuantity,
                    amountMinor = candidate.amountMinor,
                )
            },
            amountMinor = amount,
        )
    }

    fun lockedItemIds(groups: List<ReceiptItemLockedGroup>): Set<ReceiptItemSelectionId> =
        groups.flatMapTo(mutableSetOf()) { it.itemIds }

    fun transactionDraft(
        selected: List<ReceiptItemSelectionCandidate>,
        mode: ReceiptTransactionMode,
        fallbackOccurredAt: String,
    ): ReceiptItemTransactionDraft? {
        val candidates = selected.filter { !it.isCreated && it.amountMinor != 0L }
        if (candidates.isEmpty()) return null
        val walletId = candidates.first().walletId ?: return null
        if (candidates.any { it.walletId != walletId }) return null
        val categoryId = when (mode) {
            ReceiptTransactionMode.LEND -> null
            ReceiptTransactionMode.EXPENSE -> {
                val purchases = candidates.filter { it.lineType == BillItemLineType.PURCHASE }
                val firstCategory = purchases.firstOrNull()?.categoryId ?: return null
                if (purchases.any { it.categoryId != firstCategory }) return null
                firstCategory
            }
        }
        val amount = candidates.sumOf(ReceiptItemSelectionCandidate::amountMinor)
        if (amount <= 0) return null
        val merchantNames = candidates.mapNotNull { candidate ->
            candidate.merchantName?.trim()?.takeIf(String::isNotEmpty)
        }.toSet()
        val occurredDates = candidates.mapNotNull(ReceiptItemSelectionCandidate::occurredAt)
        val occurredAt = occurredDates
            .takeIf { it.size == candidates.size && it.toSet().size == 1 }
            ?.first()
            ?: fallbackOccurredAt
        val billIds = candidates.map { it.id.billId }.toSet()

        return ReceiptItemTransactionDraft(
            primaryKind = if (mode == ReceiptTransactionMode.EXPENSE) {
                TransactionPrimaryKind.EXPENSE
            } else {
                TransactionPrimaryKind.TRANSFER
            },
            transferSubtype = if (mode == ReceiptTransactionMode.LEND) {
                TransactionTransferSubtype.DEBT
            } else {
                null
            },
            debtIntent = if (mode == ReceiptTransactionMode.LEND) TransactionDebtIntent.LEND else null,
            amountMinor = amount,
            title = merchantNames.singleOrNull().orEmpty(),
            walletId = walletId,
            categoryId = categoryId,
            occurredAt = occurredAt,
            receiptAttachmentBillId = billIds.singleOrNull(),
        )
    }
}

internal fun ReceiptReviewState.selectionCandidates(
    selection: Map<ReceiptItemSelectionId, Int>,
): List<ReceiptItemSelectionCandidate> = bills.flatMap { bill ->
    val result = bill.result ?: return@flatMap emptyList()
    result.items.map { item ->
        val id = ReceiptItemSelectionId(bill.id, item.lineId)
        val totalQuantity = if (item.lineType == BillItemLineType.PURCHASE) {
            maxOf(1, item.quantity ?: 1)
        } else {
            1
        }
        val selectedQuantity = (selection[id] ?: 0).coerceIn(0, totalQuantity)
        val representedQuantity = selectedQuantity.takeIf { it > 0 } ?: totalQuantity
        ReceiptItemSelectionCandidate(
            id = id,
            walletId = bill.selectedWalletId,
            categoryId = item.categoryId.takeIf { item.lineType == BillItemLineType.PURCHASE },
            lineType = item.lineType,
            amountMinor = if (item.lineType == BillItemLineType.DISCOUNT) {
                item.finalAmountMinor
            } else {
                ReceiptItemSelectionLogic.allocationAmount(
                    totalAmountMinor = item.finalAmountMinor,
                    totalQuantity = totalQuantity,
                    allocatedQuantity = representedQuantity,
                )
            },
            totalQuantity = totalQuantity,
            availableQuantity = totalQuantity,
            selectedQuantity = selectedQuantity,
            createdQuantity = 0,
            lockedQuantity = 0,
            merchantName = result.merchantName,
            occurredAt = result.occurredAt,
            isCreated = false,
            isLocked = false,
        )
    }
}
