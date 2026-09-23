package vn.com.quyln.mistia.feature.transactions

import java.util.Base64
import java.util.Locale
import java.util.concurrent.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import vn.com.quyln.mistia.core.model.BillItemAnalysisRequest
import vn.com.quyln.mistia.core.model.BillItemAnalysisResult
import vn.com.quyln.mistia.core.model.CategoryHierarchyRole
import vn.com.quyln.mistia.core.model.LedgerWalletRecord
import vn.com.quyln.mistia.core.model.PreparedReceiptImage
import vn.com.quyln.mistia.core.model.ReceiptAnalysisCategoryCandidate
import vn.com.quyln.mistia.core.model.ReceiptAnalysisClient
import vn.com.quyln.mistia.core.model.ReceiptAnalysisException
import vn.com.quyln.mistia.core.model.ReceiptAnalysisFailure
import vn.com.quyln.mistia.core.model.ReceiptAnalysisWalletCandidate
import vn.com.quyln.mistia.core.model.TransactionCategoryKind
import vn.com.quyln.mistia.core.model.TransactionCategoryRecord

internal data class ReceiptAnalysisRequestContext(
    val ownerUserId: String,
    val categories: List<TransactionCategoryRecord>,
    val wallets: List<LedgerWalletRecord>,
    val locale: Locale,
    val timeZoneIdentifier: String,
)

internal data class ReceiptAnalysisAttempt(
    val image: PreparedReceiptImage,
    val result: BillItemAnalysisResult?,
    val failure: ReceiptAnalysisException?,
)

internal fun buildReceiptAnalysisRequest(
    image: PreparedReceiptImage,
    ownerUserId: String,
    categories: List<TransactionCategoryRecord>,
    wallets: List<LedgerWalletRecord>,
    locale: Locale,
    timeZoneIdentifier: String,
): BillItemAnalysisRequest {
    val parentCategories = categories
        .filter { it.ownerUserId == ownerUserId }
        .associateBy(TransactionCategoryRecord::id)
    val categoryCandidates = categories
        .asSequence()
        .filter { category ->
            category.ownerUserId == ownerUserId &&
                category.deletedAt == null &&
                !category.isArchived &&
                category.kind == TransactionCategoryKind.EXPENSE &&
                category.hierarchyRole == CategoryHierarchyRole.CHILD &&
                !category.isBalanceAdjustmentSystemCategory
        }
        .sortedWith(compareBy(TransactionCategoryRecord::sortOrder, TransactionCategoryRecord::createdAt))
        .map { category ->
            ReceiptAnalysisCategoryCandidate(
                id = category.id,
                name = category.localizedName(locale),
                parentName = category.parentCategoryId
                    ?.let(parentCategories::get)
                    ?.localizedName(locale),
                kindRawValue = category.kindWireValue,
            )
        }
        .toList()
    val walletCandidates = wallets
        .asSequence()
        .filter { wallet ->
            wallet.ownerUserId == ownerUserId &&
                wallet.deletedAt == null &&
                !wallet.isArchived &&
                wallet.systemPurposeRawValue != INVESTMENT_PROFIT_SYSTEM_PURPOSE
        }
        .sortedWith(compareBy(LedgerWalletRecord::sortOrder, LedgerWalletRecord::createdAt))
        .map { wallet ->
            ReceiptAnalysisWalletCandidate(
                id = wallet.id,
                name = wallet.name,
                kindRawValue = wallet.kindWireValue,
                currencyCode = wallet.currencyCode,
                institutionDisplayName = wallet.institutionDisplayName,
            )
        }
        .toList()

    return BillItemAnalysisRequest(
        imageBase64 = Base64.getEncoder().encodeToString(image.imageData),
        mimeType = image.mimeType,
        localeIdentifier = locale.toLanguageTag(),
        timeZoneIdentifier = timeZoneIdentifier,
        currencyCode = walletCandidates.firstOrNull()?.currencyCode ?: DEFAULT_CURRENCY_CODE,
        targetLanguageCode = locale.receiptLanguageCode(),
        categories = categoryCandidates,
        wallets = walletCandidates,
    )
}

internal suspend fun analyzePreparedReceipts(
    images: List<PreparedReceiptImage>,
    context: ReceiptAnalysisRequestContext,
    client: ReceiptAnalysisClient,
    accessTokenProvider: suspend () -> String?,
): List<ReceiptAnalysisAttempt> {
    if (images.isEmpty()) return emptyList()
    val accessToken = accessTokenProvider()?.trim().orEmpty()
    if (accessToken.isEmpty()) {
        throw ReceiptAnalysisException(ReceiptAnalysisFailure.UNAUTHORIZED)
    }

    return images.map { image ->
        try {
            val request = withContext(Dispatchers.Default) {
                buildReceiptAnalysisRequest(
                    image = image,
                    ownerUserId = context.ownerUserId,
                    categories = context.categories,
                    wallets = context.wallets,
                    locale = context.locale,
                    timeZoneIdentifier = context.timeZoneIdentifier,
                )
            }
            ReceiptAnalysisAttempt(
                image = image,
                result = client.analyzeBillItems(request, accessToken),
                failure = null,
            )
        } catch (error: CancellationException) {
            throw error
        } catch (error: ReceiptAnalysisException) {
            ReceiptAnalysisAttempt(image = image, result = null, failure = error)
        } catch (error: Exception) {
            ReceiptAnalysisAttempt(
                image = image,
                result = null,
                failure = ReceiptAnalysisException(
                    reason = ReceiptAnalysisFailure.INVALID_RESPONSE,
                    cause = error,
                ),
            )
        }
    }
}

private fun TransactionCategoryRecord.localizedName(locale: Locale): String = when (
    locale.receiptLanguageCode()
) {
    "vi" -> name
    "ja" -> nameJapanese?.trim()?.takeIf(String::isNotEmpty) ?: name
    else -> nameEnglish?.trim()?.takeIf(String::isNotEmpty) ?: name
}

private fun Locale.receiptLanguageCode(): String = when (language.lowercase(Locale.ROOT)) {
    "vi" -> "vi"
    "ja" -> "ja"
    else -> "en"
}

private const val DEFAULT_CURRENCY_CODE = "JPY"
private const val INVESTMENT_PROFIT_SYSTEM_PURPOSE = "investmentProfit"
