package vn.com.quyln.mistia.feature.transactions

import vn.com.quyln.mistia.core.model.BillItemLineType
import vn.com.quyln.mistia.core.model.PreparedReceiptImage
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

internal data class ReceiptTransactionEditorLaunch(
    val draft: ReceiptItemTransactionDraft,
    val receiptImage: PreparedReceiptImage,
    val lockedGroupId: String? = null,
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

    fun selectQuantity(
        selection: Map<ReceiptItemSelectionId, Int>,
        candidateId: ReceiptItemSelectionId,
        quantity: Int,
        candidates: List<ReceiptItemSelectionCandidate>,
        mode: ReceiptTransactionMode,
    ): Map<ReceiptItemSelectionId, Int> {
        val candidate = candidates.firstOrNull { it.id == candidateId } ?: return selection
        val anchorBillId = selection.keys.firstOrNull()?.billId
        if (anchorBillId != null && candidate.id.billId != anchorBillId) return selection
        val otherSelected = candidates.filter { it.id != candidateId && it.id in selection }
        if (!canSelect(candidate, otherSelected, mode)) return selection
        return normalizedSelection(
            selection = selection + (
                candidate.id to quantity.coerceIn(1, candidate.availableQuantity)
            ),
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

    fun lockedAllocations(
        groups: List<ReceiptItemLockedGroup>,
    ): Map<ReceiptItemSelectionId, ReceiptItemQuantityAllocation> = buildMap {
        groups.forEach { group ->
            group.itemAllocations.forEach { (id, allocation) ->
                val existing = get(id) ?: ReceiptItemQuantityAllocation(0, 0)
                put(
                    id,
                    ReceiptItemQuantityAllocation(
                        quantity = existing.quantity + allocation.quantity,
                        amountMinor = existing.amountMinor + allocation.amountMinor,
                    ),
                )
            }
        }
    }

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
    val lockedItemIds = ReceiptItemSelectionLogic.lockedItemIds(bill.lockedGroups)
    val lockedAllocations = ReceiptItemSelectionLogic.lockedAllocations(bill.lockedGroups)
    result.items.map { item ->
        val id = ReceiptItemSelectionId(bill.id, item.lineId)
        val totalQuantity = if (item.lineType == BillItemLineType.PURCHASE) {
            maxOf(1, item.quantity ?: 1)
        } else {
            1
        }
        val createdAllocation = bill.createdAllocations[item.lineId]
            ?: ReceiptItemQuantityAllocation(0, 0)
        val lockedAllocation = lockedAllocations[id] ?: ReceiptItemQuantityAllocation(0, 0)
        val usedQuantity = minOf(
            totalQuantity,
            createdAllocation.quantity + lockedAllocation.quantity,
        )
        val availableQuantity = (totalQuantity - usedQuantity).coerceAtLeast(0)
        val remainingAmount = (
            item.finalAmountMinor - createdAllocation.amountMinor - lockedAllocation.amountMinor
        ).coerceAtLeast(0)
        val selectedQuantity = (selection[id] ?: 0).coerceIn(0, availableQuantity)
        val representedQuantity = selectedQuantity.takeIf { it > 0 } ?: availableQuantity
        ReceiptItemSelectionCandidate(
            id = id,
            walletId = bill.selectedWalletId,
            categoryId = item.categoryId.takeIf { item.lineType == BillItemLineType.PURCHASE },
            lineType = item.lineType,
            amountMinor = if (item.lineType == BillItemLineType.DISCOUNT) {
                item.finalAmountMinor
            } else {
                ReceiptItemSelectionLogic.allocationAmount(
                    totalAmountMinor = remainingAmount,
                    totalQuantity = availableQuantity,
                    allocatedQuantity = representedQuantity,
                )
            },
            totalQuantity = totalQuantity,
            availableQuantity = availableQuantity,
            selectedQuantity = if (item.lineType == BillItemLineType.DISCOUNT) {
                minOf(selectedQuantity, 1)
            } else {
                selectedQuantity
            },
            createdQuantity = minOf(createdAllocation.quantity, totalQuantity),
            lockedQuantity = minOf(lockedAllocation.quantity, totalQuantity),
            merchantName = result.merchantName,
            occurredAt = result.occurredAt,
            isCreated = availableQuantity == 0 && createdAllocation.quantity > 0,
            isLocked = availableQuantity == 0 && id in lockedItemIds,
        )
    }
}

internal fun ReceiptReviewState.lockSelection(
    selection: Map<ReceiptItemSelectionId, Int>,
    mode: ReceiptTransactionMode,
    groupId: String,
): ReceiptReviewEditUpdate? {
    if (bills.any { bill -> bill.lockedGroups.any { it.id == groupId } }) return null
    val requested = selection.filterValues { it > 0 }
    val billId = requested.keys.map(ReceiptItemSelectionId::billId).toSet().singleOrNull()
        ?: return null
    val bill = bills.firstOrNull { it.id == billId } ?: return null
    if (bill.result?.requiresReview != false) return null
    val candidates = selectionCandidates(requested)
    val normalized = ReceiptItemSelectionLogic.normalizedSelection(requested, candidates, mode)
    if (normalized != requested) return null
    val selected = selectionCandidates(normalized).filter { it.id in normalized }
    val group = ReceiptItemSelectionLogic.lockedGroup(selected, mode, groupId) ?: return null
    return ReceiptReviewEditUpdate(
        state = copy(
            bills = bills.map { candidateBill ->
                if (candidateBill.id == billId) {
                    candidateBill.copy(lockedGroups = candidateBill.lockedGroups + group)
                } else {
                    candidateBill
                }
            },
        ),
        selection = selection - group.itemIds,
    )
}

internal fun ReceiptReviewState.cancelLockedGroup(
    billId: String,
    groupId: String,
): ReceiptReviewState = copy(
    bills = bills.map { bill ->
        if (bill.id == billId) {
            bill.copy(lockedGroups = bill.lockedGroups.filterNot { it.id == groupId })
        } else {
            bill
        }
    },
)

internal fun ReceiptReviewState.markLockedGroupCreated(groupId: String): ReceiptReviewState = copy(
    bills = bills.map { bill ->
        val group = bill.lockedGroups.firstOrNull { it.id == groupId } ?: return@map bill
        val created = bill.createdAllocations.toMutableMap()
        group.itemAllocations.forEach { (id, allocation) ->
            val existing = created[id.itemId] ?: ReceiptItemQuantityAllocation(0, 0)
            created[id.itemId] = ReceiptItemQuantityAllocation(
                quantity = existing.quantity + allocation.quantity,
                amountMinor = existing.amountMinor + allocation.amountMinor,
            )
        }
        bill.copy(
            createdAllocations = created,
            lockedGroups = bill.lockedGroups.filterNot { it.id == groupId },
        )
    },
)

internal fun ReceiptReviewState.transactionLaunch(
    groupId: String,
    fallbackOccurredAt: String,
): ReceiptTransactionEditorLaunch? {
    val bill = bills.singleOrNull { candidate -> candidate.lockedGroups.any { it.id == groupId } }
        ?: return null
    val group = bill.lockedGroups.singleOrNull { it.id == groupId } ?: return null
    if (bill.result?.requiresReview != false) return null
    val candidates = selectionCandidates(emptyMap()).mapNotNull { candidate ->
        val allocation = group.itemAllocations[candidate.id] ?: return@mapNotNull null
        candidate.copy(
            amountMinor = allocation.amountMinor,
            availableQuantity = allocation.quantity,
            selectedQuantity = allocation.quantity,
            isCreated = false,
            isLocked = false,
        )
    }
    val draft = ReceiptItemSelectionLogic.transactionDraft(
        selected = candidates,
        mode = group.mode,
        fallbackOccurredAt = fallbackOccurredAt,
    ) ?: return null
    return ReceiptTransactionEditorLaunch(
        draft = draft,
        receiptImage = bill.image,
        lockedGroupId = group.id,
    )
}

internal fun ReceiptReviewState.expenseTransactionDraft(
    selection: Map<ReceiptItemSelectionId, Int>,
    fallbackOccurredAt: String,
): ReceiptItemTransactionDraft? = transactionDraft(
    selection = selection,
    mode = ReceiptTransactionMode.EXPENSE,
    fallbackOccurredAt = fallbackOccurredAt,
)

internal fun ReceiptReviewState.transactionDraft(
    selection: Map<ReceiptItemSelectionId, Int>,
    mode: ReceiptTransactionMode,
    fallbackOccurredAt: String,
): ReceiptItemTransactionDraft? {
    val requested = selection.filterValues { it > 0 }
    val billId = requested.keys.map(ReceiptItemSelectionId::billId).toSet().singleOrNull()
        ?: return null
    val bill = bills.firstOrNull { it.id == billId } ?: return null
    val result = bill.result ?: return null
    if (bill.isMultipleBillImage || result.requiresReview) return null

    val candidates = selectionCandidates(requested)
    val normalized = ReceiptItemSelectionLogic.normalizedSelection(
        selection = requested,
        candidates = candidates,
        mode = mode,
    )
    if (normalized.keys != requested.keys) return null
    val selected = selectionCandidates(normalized).filter { it.id in normalized }
    return ReceiptItemSelectionLogic.transactionDraft(
        selected = selected,
        mode = mode,
        fallbackOccurredAt = fallbackOccurredAt,
    )
}

internal fun ReceiptReviewState.expenseTransactionLaunch(
    selection: Map<ReceiptItemSelectionId, Int>,
    fallbackOccurredAt: String,
): ReceiptTransactionEditorLaunch? = transactionLaunch(
    selection = selection,
    mode = ReceiptTransactionMode.EXPENSE,
    fallbackOccurredAt = fallbackOccurredAt,
)

internal fun ReceiptReviewState.transactionLaunch(
    selection: Map<ReceiptItemSelectionId, Int>,
    mode: ReceiptTransactionMode,
    fallbackOccurredAt: String,
): ReceiptTransactionEditorLaunch? {
    val draft = transactionDraft(selection, mode, fallbackOccurredAt) ?: return null
    val billId = draft.receiptAttachmentBillId ?: return null
    val image = bills.firstOrNull { it.id == billId }?.image ?: return null
    return ReceiptTransactionEditorLaunch(draft = draft, receiptImage = image)
}
