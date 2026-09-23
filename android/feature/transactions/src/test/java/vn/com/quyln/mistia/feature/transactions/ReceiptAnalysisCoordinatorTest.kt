package vn.com.quyln.mistia.feature.transactions

import java.util.Locale
import java.util.concurrent.CancellationException
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import vn.com.quyln.mistia.core.model.BillItemAnalysisRequest
import vn.com.quyln.mistia.core.model.BillItemAnalysisResult
import vn.com.quyln.mistia.core.model.CategoryHierarchyRole
import vn.com.quyln.mistia.core.model.LedgerWalletRecord
import vn.com.quyln.mistia.core.model.PreparedReceiptImage
import vn.com.quyln.mistia.core.model.ReceiptAnalysisClient
import vn.com.quyln.mistia.core.model.ReceiptAnalysisException
import vn.com.quyln.mistia.core.model.ReceiptAnalysisFailure
import vn.com.quyln.mistia.core.model.TransactionCategoryKind
import vn.com.quyln.mistia.core.model.TransactionCategoryRecord
import vn.com.quyln.mistia.core.model.WalletKind

class ReceiptAnalysisCoordinatorTest {
    @Test
    fun `request uses localized owner scoped candidates in iOS order`() {
        val parent = category(
            id = "parent",
            name = "Ăn uống",
            nameEnglish = "Food",
            nameJapanese = "食費",
            role = CategoryHierarchyRole.PARENT,
            sortOrder = 1,
        )
        val eligible = category(
            id = "eligible",
            name = "Đi chợ",
            nameEnglish = "Groceries",
            nameJapanese = "食料品",
            parentId = parent.id,
            sortOrder = 2,
        )
        val otherOwner = category(id = "other", owner = "other-owner", sortOrder = 0)
        val income = category(id = "income", kind = TransactionCategoryKind.INCOME, sortOrder = 0)
        val balanceAdjustment = category(
            id = TransactionCategoryRecord.BALANCE_ADJUSTMENT_EXPENSE_ID,
            sortOrder = 0,
        )
        val archivedCategory = category(id = "archived-category", sortOrder = 0).copy(isArchived = true)
        val wallet = wallet(id = "wallet", name = "PayPay", sortOrder = 2, currency = "JPY")
        val earlierWallet = wallet(id = "cash", name = "Cash", sortOrder = 1, currency = "VND")
        val archivedWallet = wallet(id = "archived", archived = true, sortOrder = 0)
        val deletedWallet = wallet(id = "deleted", sortOrder = 0).copy(deletedAt = "2026-01-02T00:00:00Z")
        val otherOwnerWallet = wallet(id = "other-wallet", owner = "other-owner", sortOrder = 0)
        val investmentSystemWallet = wallet(
            id = "investment",
            kind = WalletKind.INVESTMENT,
            systemPurpose = "investmentProfit",
            sortOrder = 0,
        )

        val request = buildReceiptAnalysisRequest(
            image = prepared(0xFF, 0xEE),
            ownerUserId = "owner",
            categories = listOf(
                eligible,
                parent,
                income,
                otherOwner,
                balanceAdjustment,
                archivedCategory,
            ),
            wallets = listOf(
                wallet,
                archivedWallet,
                earlierWallet,
                investmentSystemWallet,
                deletedWallet,
                otherOwnerWallet,
            ),
            locale = Locale.JAPAN,
            timeZoneIdentifier = "Asia/Tokyo",
        )

        assertEquals("/+4=", request.imageBase64)
        assertEquals("image/jpeg", request.mimeType)
        assertEquals("ja-JP", request.localeIdentifier)
        assertEquals("ja", request.targetLanguageCode)
        assertEquals("Asia/Tokyo", request.timeZoneIdentifier)
        assertEquals("VND", request.currencyCode)
        assertEquals(listOf("eligible"), request.categories.map { it.id })
        assertEquals("食料品", request.categories.single().name)
        assertEquals("食費", request.categories.single().parentName)
        assertEquals(listOf("cash", "wallet"), request.wallets.map { it.id })
    }

    @Test
    fun `batch refreshes one token and keeps ordered partial results`() = runBlocking {
        var tokenCalls = 0
        val client = RecordingAnalysisClient { request, _ ->
            if (request.imageBase64 == "Ag==") {
                throw ReceiptAnalysisException(ReceiptAnalysisFailure.UPSTREAM_UNAVAILABLE)
            }
            result(request.imageBase64)
        }
        val context = ReceiptAnalysisRequestContext(
            ownerUserId = "owner",
            categories = listOf(category(id = "category")),
            wallets = listOf(wallet(id = "wallet")),
            locale = Locale.ENGLISH,
            timeZoneIdentifier = "UTC",
        )

        val attempts = analyzePreparedReceipts(
            images = listOf(prepared(1), prepared(2), prepared(3)),
            context = context,
            client = client,
            accessTokenProvider = {
                tokenCalls += 1
                "fresh-jwt"
            },
        )

        assertEquals(1, tokenCalls)
        assertEquals(listOf("AQ==", "Ag==", "Aw=="), client.requestImages)
        assertEquals(listOf("fresh-jwt", "fresh-jwt", "fresh-jwt"), client.tokens)
        assertEquals("AQ==", attempts[0].result?.merchantName)
        assertNull(attempts[0].failure)
        assertNull(attempts[1].result)
        assertEquals(ReceiptAnalysisFailure.UPSTREAM_UNAVAILABLE, attempts[1].failure?.reason)
        assertEquals("Aw==", attempts[2].result?.merchantName)
    }

    @Test
    fun `missing refreshed token fails before any request`() {
        val client = RecordingAnalysisClient { _, _ -> result("unexpected") }

        val failure = runCatching {
            runBlocking {
                analyzePreparedReceipts(
                    images = listOf(prepared(1)),
                    context = ReceiptAnalysisRequestContext(
                        ownerUserId = "owner",
                        categories = listOf(category(id = "category")),
                        wallets = listOf(wallet(id = "wallet")),
                        locale = Locale.ENGLISH,
                        timeZoneIdentifier = "UTC",
                    ),
                    client = client,
                    accessTokenProvider = { null },
                )
            }
        }.exceptionOrNull() as ReceiptAnalysisException

        assertEquals(ReceiptAnalysisFailure.UNAUTHORIZED, failure.reason)
        assertTrue(client.requestImages.isEmpty())
    }

    @Test
    fun `cancellation stops batch and propagates`() {
        val client = RecordingAnalysisClient { request, _ ->
            if (request.imageBase64 == "Ag==") throw CancellationException("cancelled")
            result(request.imageBase64)
        }

        val failure = runCatching {
            runBlocking {
                analyzePreparedReceipts(
                    images = listOf(prepared(1), prepared(2), prepared(3)),
                    context = ReceiptAnalysisRequestContext(
                        ownerUserId = "owner",
                        categories = listOf(category(id = "category")),
                        wallets = listOf(wallet(id = "wallet")),
                        locale = Locale.ENGLISH,
                        timeZoneIdentifier = "UTC",
                    ),
                    client = client,
                    accessTokenProvider = { "jwt" },
                )
            }
        }.exceptionOrNull()

        assertTrue(failure is CancellationException)
        assertEquals(listOf("AQ==", "Ag=="), client.requestImages)
    }

    private class RecordingAnalysisClient(
        private val response: suspend (BillItemAnalysisRequest, String) -> BillItemAnalysisResult,
    ) : ReceiptAnalysisClient {
        val requestImages = mutableListOf<String>()
        val tokens = mutableListOf<String>()

        override suspend fun analyzeBillItems(
            request: BillItemAnalysisRequest,
            accessToken: String,
        ): BillItemAnalysisResult {
            requestImages += request.imageBase64
            tokens += accessToken
            return response(request, accessToken)
        }
    }

    private fun result(name: String) = BillItemAnalysisResult(
        merchantName = name,
        totalMinor = 100,
        currencyCode = "JPY",
        occurredAt = null,
        walletId = null,
        multipleBillsDetected = false,
        confidence = 1.0,
        missingFields = emptyList(),
        rawText = null,
        items = emptyList(),
        quota = null,
    )

    private fun prepared(vararg values: Int) = PreparedReceiptImage(
        imageData = ByteArray(values.size) { index -> values[index].toByte() },
        thumbnailData = byteArrayOf(9),
        mimeType = "image/jpeg",
        width = 100,
        height = 200,
    )

    private fun category(
        id: String,
        owner: String = "owner",
        name: String = "Ăn uống",
        nameEnglish: String? = "Food",
        nameJapanese: String? = "食費",
        kind: TransactionCategoryKind = TransactionCategoryKind.EXPENSE,
        role: CategoryHierarchyRole = CategoryHierarchyRole.CHILD,
        parentId: String? = null,
        sortOrder: Int = 1,
    ) = TransactionCategoryRecord(
        id = id,
        ownerUserId = owner,
        name = name,
        nameEnglish = nameEnglish,
        nameJapanese = nameJapanese,
        kindWireValue = kind.wireValue,
        iconSymbolName = "mistia.category.food",
        iconColorHex = "#112233",
        isFavorite = false,
        familyBudgetSpendingEnabled = false,
        parentCategoryId = parentId,
        hierarchyRoleWireValue = role.wireValue,
        systemKey = null,
        isSystem = false,
        sortOrder = sortOrder,
        isArchived = false,
        archivedAt = null,
        createdAt = "2026-01-0${sortOrder.coerceIn(1, 9)}T00:00:00Z",
        updatedAt = "2026-01-01T00:00:00Z",
        deletedAt = null,
        syncVersion = 0,
        lastModifiedByDeviceId = null,
    )

    private fun wallet(
        id: String,
        name: String = "Cash",
        owner: String = "owner",
        kind: WalletKind = WalletKind.CASH,
        currency: String = "JPY",
        sortOrder: Int = 1,
        archived: Boolean = false,
        systemPurpose: String? = null,
    ) = LedgerWalletRecord(
        id = id,
        ownerUserId = owner,
        name = name,
        kindWireValue = kind.wireValue,
        iconSymbolName = kind.defaultIcon,
        iconColorHex = kind.defaultColorHex,
        currencyCode = currency,
        openingBalanceMinor = 0,
        institutionDisplayName = null,
        institutionPresetKey = null,
        sortOrder = sortOrder,
        isArchived = archived,
        archivedAt = null,
        createdAt = "2026-01-0${sortOrder.coerceIn(1, 9)}T00:00:00Z",
        updatedAt = "2026-01-01T00:00:00Z",
        deletedAt = null,
        syncVersion = 0,
        lastModifiedByDeviceId = null,
        systemPurposeRawValue = systemPurpose,
        investmentLinkedWalletId = null,
    )
}
