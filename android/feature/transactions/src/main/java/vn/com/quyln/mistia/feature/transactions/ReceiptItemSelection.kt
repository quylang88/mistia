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
