package vn.com.quyln.mistia.feature.transactions

import vn.com.quyln.mistia.core.model.BillItemAnalysisItem
import vn.com.quyln.mistia.core.model.BillItemLineType

internal data class ReceiptItemEditorState(
    private val source: BillItemAnalysisItem,
    val currencyCode: String,
    val originalName: String,
    val translatedName: String,
    val lineType: BillItemLineType,
    val quantityText: String,
    val originalAmountText: String,
    val discountAmountText: String,
) {
    fun reviewedItem(): BillItemAnalysisItem? {
        val normalizedName = originalName.trim()
        val quantity: Int
        val originalAmountMinor: Long
        when (lineType) {
            BillItemLineType.PURCHASE -> {
                quantity = quantityText.trim().toIntOrNull()?.takeIf { it > 0 } ?: return null
                originalAmountMinor = parseMinorInput(originalAmountText, currencyCode) ?: return null
            }

            BillItemLineType.DISCOUNT -> {
                quantity = 1
                originalAmountMinor = 0
            }
        }
        val discountAmountMinor = parseMinorInput(discountAmountText, currencyCode) ?: return null
        return source.copy(
            originalName = normalizedName,
            translatedName = translatedName.trim().takeIf(String::isNotEmpty),
            lineType = lineType,
        ).reviewed(
            originalAmountMinor = originalAmountMinor,
            discountAmountMinor = discountAmountMinor,
            quantity = quantity,
        )?.takeUnless(BillItemAnalysisItem::requiresReview)
    }

    companion object {
        fun from(
            item: BillItemAnalysisItem,
            currencyCode: String,
        ): ReceiptItemEditorState = ReceiptItemEditorState(
            source = item,
            currencyCode = currencyCode,
            originalName = item.originalName,
            translatedName = item.translatedName.orEmpty(),
            lineType = item.lineType,
            quantityText = (item.quantity ?: 1).toString(),
            originalAmountText = formatMinorInput(
                minor = item.originalAmountMinor ?: maxOf(0, item.finalAmountMinor),
                currencyCode = currencyCode,
            ),
            discountAmountText = formatMinorInput(
                minor = item.discountAmountMinor,
                currencyCode = currencyCode,
            ),
        )
    }
}
