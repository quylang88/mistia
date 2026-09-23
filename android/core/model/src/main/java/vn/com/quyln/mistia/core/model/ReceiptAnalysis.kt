package vn.com.quyln.mistia.core.model

import java.io.IOException
import java.math.BigInteger
import java.util.Locale
import java.util.UUID
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class ReceiptAnalysisCategoryCandidate(
    val id: String,
    val name: String,
    @SerialName("parent_name") val parentName: String?,
    @SerialName("kind_raw_value") val kindRawValue: String,
)

@Serializable
data class ReceiptAnalysisWalletCandidate(
    val id: String,
    val name: String,
    @SerialName("kind_raw_value") val kindRawValue: String,
    @SerialName("currency_code") val currencyCode: String,
    @SerialName("institution_display_name") val institutionDisplayName: String?,
)

@Serializable
data class BillItemAnalysisRequest(
    @SerialName("image_base64") val imageBase64: String,
    @SerialName("mime_type") val mimeType: String,
    @SerialName("locale_identifier") val localeIdentifier: String,
    @SerialName("time_zone_identifier") val timeZoneIdentifier: String,
    @SerialName("currency_code") val currencyCode: String,
    @SerialName("target_language_code") val targetLanguageCode: String,
    val categories: List<ReceiptAnalysisCategoryCandidate>,
    val wallets: List<ReceiptAnalysisWalletCandidate>,
)

enum class BillItemLineType(val wireValue: String) {
    PURCHASE("purchase"),
    DISCOUNT("discount"),
    ;

    companion object {
        fun fromWireValue(value: String?): BillItemLineType? =
            entries.firstOrNull { it.wireValue == value?.trim()?.lowercase(Locale.ROOT) }
    }
}

data class ReceiptAnalysisQuota(
    val allowed: Boolean,
    val usedCount: Int,
    val limitCount: Int,
    val remainingCount: Int,
    val usageDate: String?,
    val resetTimeZone: String?,
    val retryAfter: String?,
) {
    fun normalized(): ReceiptAnalysisQuota = copy(
        usedCount = usedCount.coerceAtLeast(0),
        limitCount = limitCount.coerceAtLeast(0),
        remainingCount = remainingCount.coerceAtLeast(0),
        usageDate = usageDate.normalizedText(),
        resetTimeZone = resetTimeZone.normalizedText(),
        retryAfter = retryAfter.normalizedText(),
    )
}

data class BillItemAnalysisItem(
    val lineId: String,
    val rawLineText: String?,
    val originalName: String,
    val translatedName: String?,
    val lineType: BillItemLineType,
    val quantity: Int?,
    val originalAmountMinor: Long?,
    val discountAmountMinor: Long,
    val finalAmountMinor: Long,
    val categoryId: String?,
    val confidence: Double,
    val missingFields: List<String>,
) {
    fun normalized(): BillItemAnalysisItem {
        val normalizedType = if (lineType == BillItemLineType.DISCOUNT || finalAmountMinor < 0) {
            BillItemLineType.DISCOUNT
        } else {
            BillItemLineType.PURCHASE
        }
        val normalizedDiscount = discountAmountMinor.safeAbsoluteValue()
        return copy(
            lineId = lineId.normalizedText() ?: UUID.randomUUID().toString(),
            rawLineText = rawLineText.normalizedText(),
            originalName = originalName.normalizedText().orEmpty(),
            translatedName = translatedName.normalizedText(),
            lineType = normalizedType,
            quantity = quantity?.takeIf { normalizedType == BillItemLineType.PURCHASE && it > 1 },
            originalAmountMinor = originalAmountMinor
                ?.coerceAtLeast(0)
                ?.takeIf { normalizedType == BillItemLineType.PURCHASE },
            discountAmountMinor = normalizedDiscount,
            finalAmountMinor = when (normalizedType) {
                BillItemLineType.PURCHASE -> finalAmountMinor.coerceAtLeast(0)
                BillItemLineType.DISCOUNT -> -finalAmountMinor.safeAbsoluteValue()
            },
            categoryId = categoryId.normalizedText()
                ?.takeIf { normalizedType == BillItemLineType.PURCHASE },
            confidence = confidence.takeIf(Double::isFinite)?.coerceIn(0.0, 1.0) ?: 0.0,
            missingFields = missingFields.normalizedFieldNames(),
        )
    }

    val requiresReview: Boolean
        get() {
            val normalized = normalized()
            if (normalized.originalName.isEmpty()) return true
            if (normalized.missingFields.any { it in ITEM_REVIEW_FIELDS }) return true
            return when (normalized.lineType) {
                BillItemLineType.DISCOUNT -> normalized.finalAmountMinor >= 0
                BillItemLineType.PURCHASE -> {
                    val original = normalized.originalAmountMinor
                    if (original != null) {
                        original - normalized.discountAmountMinor != normalized.finalAmountMinor
                    } else {
                        normalized.finalAmountMinor == 0L
                    }
                }
            }
        }

    fun reviewed(
        originalAmountMinor: Long,
        discountAmountMinor: Long,
        quantity: Int,
    ): BillItemAnalysisItem? {
        if (
            originalAmountMinor < 0 ||
            discountAmountMinor < 0 ||
            quantity <= 0 ||
            originalName.isBlank() ||
            (
                lineType != BillItemLineType.DISCOUNT &&
                    (originalAmountMinor <= 0 || discountAmountMinor > originalAmountMinor)
                )
        ) {
            return null
        }
        return copy(
            quantity = quantity.takeIf { lineType == BillItemLineType.PURCHASE && it > 1 },
            originalAmountMinor = originalAmountMinor.takeIf { lineType == BillItemLineType.PURCHASE },
            discountAmountMinor = discountAmountMinor,
            finalAmountMinor = if (lineType == BillItemLineType.PURCHASE) {
                originalAmountMinor - discountAmountMinor
            } else {
                -discountAmountMinor
            },
            categoryId = categoryId.takeIf { lineType == BillItemLineType.PURCHASE },
            missingFields = missingFields.filterNot { it in ITEM_REVIEW_FIELDS },
        )
    }
}

fun allocateReceiptDiscount(
    itemId: String,
    items: List<BillItemAnalysisItem>,
): List<BillItemAnalysisItem>? {
    val discountIndex = items.indexOfFirst {
        it.lineId == itemId && it.lineType == BillItemLineType.DISCOUNT
    }
    if (discountIndex < 0) return null
    val discountItem = items[discountIndex]
    val discountAmount = maxOf(
        discountItem.discountAmountMinor.safeAbsoluteValue(),
        discountItem.finalAmountMinor.safeAbsoluteValue(),
    )
    if (discountItem.finalAmountMinor >= 0 || discountAmount <= 0) return null
    val eligibleIndexes = items.indices.filter { index ->
        items[index].lineType == BillItemLineType.PURCHASE && items[index].finalAmountMinor > 0
    }
    val baseTotal = eligibleIndexes.sumOf { items[it].finalAmountMinor }
    if (baseTotal <= 0 || discountAmount > baseTotal) return null

    data class Allocation(
        val index: Int,
        var floor: Long,
        val remainder: BigInteger,
    )

    val divisor = BigInteger.valueOf(baseTotal)
    val discount = BigInteger.valueOf(discountAmount)
    val allocations = eligibleIndexes.map { index ->
        val division = BigInteger.valueOf(items[index].finalAmountMinor)
            .multiply(discount)
            .divideAndRemainder(divisor)
        Allocation(index = index, floor = division[0].longValueExact(), remainder = division[1])
    }
    var remaining = discountAmount - allocations.sumOf(Allocation::floor)
    allocations
        .sortedWith(compareByDescending<Allocation> { it.remainder }.thenBy { it.index })
        .forEach { allocation ->
            if (remaining > 0) {
                allocation.floor += 1
                remaining -= 1
            }
        }

    val updated = items.toMutableList()
    allocations.forEach { allocation ->
        val item = updated[allocation.index]
        updated[allocation.index] = item.copy(
            originalAmountMinor = item.originalAmountMinor
                ?: item.finalAmountMinor + item.discountAmountMinor,
            discountAmountMinor = item.discountAmountMinor + allocation.floor,
            finalAmountMinor = (item.finalAmountMinor - allocation.floor).coerceAtLeast(0),
        )
    }
    updated[discountIndex] = updated[discountIndex].copy(
        discountAmountMinor = discountAmount,
        finalAmountMinor = 0,
    )
    return updated
}

data class BillItemAnalysisResult(
    val merchantName: String?,
    val totalMinor: Long?,
    val currencyCode: String?,
    val occurredAt: String?,
    val walletId: String?,
    val multipleBillsDetected: Boolean,
    val confidence: Double,
    val missingFields: List<String>,
    val rawText: String?,
    val items: List<BillItemAnalysisItem>,
    val quota: ReceiptAnalysisQuota?,
) {
    fun validated(
        categoryIds: Set<String>,
        walletIds: Set<String>,
    ): BillItemAnalysisResult {
        val allowedCategories = categoryIds.mapNotNull(String::normalizedText).toSet()
        val allowedWallets = walletIds.mapNotNull(String::normalizedText).toSet()
        val missing = missingFields.normalizedFieldNames().toMutableSet()
        val normalizedItems = items.map { item ->
            val normalized = item.normalized()
            if (normalized.categoryId != null && normalized.categoryId !in allowedCategories) {
                missing += "categoryID"
                normalized.copy(categoryId = null)
            } else {
                normalized
            }
        }
        val normalizedWallet = walletId.normalizedText()?.takeIf { wallet ->
            if (wallet in allowedWallets) {
                true
            } else {
                missing += "walletID"
                false
            }
        }
        return copy(
            merchantName = merchantName.normalizedText(),
            currencyCode = currencyCode.normalizedText()?.uppercase(Locale.ROOT),
            occurredAt = occurredAt.normalizedText(),
            walletId = normalizedWallet,
            confidence = confidence.takeIf(Double::isFinite)?.coerceIn(0.0, 1.0) ?: 0.0,
            missingFields = missing.sorted(),
            rawText = rawText.normalizedText(),
            items = normalizedItems,
            quota = quota?.normalized(),
        )
    }

    val itemsTotalMinor: Long?
        get() = items.fold(0L) { total, item ->
            try {
                Math.addExact(total, item.finalAmountMinor)
            } catch (_: ArithmeticException) {
                return null
            }
        }

    val totalDifferenceMinor: Long?
        get() {
            val billTotal = totalMinor ?: return null
            val itemTotal = itemsTotalMinor ?: return null
            return try {
                Math.subtractExact(itemTotal, billTotal)
            } catch (_: ArithmeticException) {
                null
            }
        }

    val requiresReview: Boolean
        get() = multipleBillsDetected || items.isEmpty() || totalMinor == null ||
            totalDifferenceMinor != 0L || items.any(BillItemAnalysisItem::requiresReview) ||
            items.map(BillItemAnalysisItem::lineId).toSet().size != items.size
}

interface ReceiptAnalysisClient {
    suspend fun analyzeBillItems(
        request: BillItemAnalysisRequest,
        accessToken: String,
    ): BillItemAnalysisResult
}

enum class ReceiptAnalysisFailure {
    CONFIGURATION,
    UNAUTHORIZED,
    INVALID_REQUEST,
    IMAGE_TOO_LARGE,
    UNSUPPORTED_MEDIA_TYPE,
    DAILY_LIMIT_REACHED,
    UPSTREAM_UNAVAILABLE,
    INVALID_RESPONSE,
    NETWORK,
}

class ReceiptAnalysisException(
    val reason: ReceiptAnalysisFailure,
    val statusCode: Int? = null,
    val quota: ReceiptAnalysisQuota? = null,
    val diagnosticCode: String? = null,
    cause: Throwable? = null,
) : IOException(
    buildString {
        append("Receipt analysis failed (")
        append(reason.name)
        statusCode?.let { append(", HTTP ").append(it) }
        append(')')
    },
    cause,
)

private fun String?.normalizedText(): String? = this?.trim()?.takeIf(String::isNotEmpty)

private fun List<String>.normalizedFieldNames(): List<String> =
    mapNotNull(String::normalizedText).distinct()

private fun Long.safeAbsoluteValue(): Long = when {
    this == Long.MIN_VALUE -> Long.MAX_VALUE
    this < 0 -> -this
    else -> this
}

private val ITEM_REVIEW_FIELDS = setOf(
    "sourceText",
    "originalName",
    "quantity",
    "finalAmountMinor",
    "originalAmountMinor",
    "discountAmountMinor",
)
