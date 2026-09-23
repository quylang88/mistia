package vn.com.quyln.mistia.core.network

import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.yield
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.SocketPolicy
import okhttp3.tls.HandshakeCertificates
import okhttp3.tls.HeldCertificate
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import vn.com.quyln.mistia.core.model.BillItemAnalysisRequest
import vn.com.quyln.mistia.core.model.BillItemLineType
import vn.com.quyln.mistia.core.model.ReceiptAnalysisCategoryCandidate
import vn.com.quyln.mistia.core.model.ReceiptAnalysisException
import vn.com.quyln.mistia.core.model.ReceiptAnalysisFailure
import vn.com.quyln.mistia.core.model.ReceiptAnalysisWalletCandidate

class SupabaseReceiptAnalysisClientTest {
    private lateinit var server: MockWebServer
    private lateinit var client: SupabaseReceiptAnalysisClient

    @Before
    fun setUp() {
        val certificate = HeldCertificate.Builder().addSubjectAlternativeName("localhost").build()
        val serverCertificates = HandshakeCertificates.Builder().heldCertificate(certificate).build()
        val clientCertificates = HandshakeCertificates.Builder()
            .addTrustedCertificate(certificate.certificate)
            .build()
        server = MockWebServer().apply {
            useHttps(serverCertificates.sslSocketFactory(), false)
            start()
        }
        client = SupabaseReceiptAnalysisClient(
            config = SupabaseConfig(server.url("/").toString().removeSuffix("/"), "publishable-key"),
            client = OkHttpClient.Builder().sslSocketFactory(
                clientCertificates.sslSocketFactory(),
                clientCertificates.trustManager,
            ).build(),
            json = MistiaWireFormat.json,
        )
    }

    @After
    fun tearDown() = server.shutdown()

    @Test
    fun `request matches authenticated edge function contract and decodes tolerant response`() = runTest {
        server.enqueue(MockResponse().setBody(SUCCESS_BODY))

        val result = client.analyzeBillItems(sampleRequest(), "user-access-token")

        val recorded = server.takeRequest(1, TimeUnit.SECONDS)
        assertNotNull(recorded)
        assertEquals("POST", recorded!!.method)
        assertEquals("/functions/v1/analyze-bill-items", recorded.requestUrl?.encodedPath)
        assertEquals("publishable-key", recorded.headers["apikey"])
        assertEquals("Bearer user-access-token", recorded.headers["Authorization"])
        assertEquals("application/json", recorded.headers["Accept"])
        assertTrue(recorded.headers["Content-Type"].orEmpty().startsWith("application/json"))

        val body = Json.parseToJsonElement(recorded.body.readUtf8()).jsonObject
        assertEquals("AQID", body["image_base64"]?.jsonPrimitive?.content)
        assertEquals("image/jpeg", body["mime_type"]?.jsonPrimitive?.content)
        assertEquals("ja_JP", body["locale_identifier"]?.jsonPrimitive?.content)
        assertEquals("Asia/Tokyo", body["time_zone_identifier"]?.jsonPrimitive?.content)
        assertEquals("JPY", body["currency_code"]?.jsonPrimitive?.content)
        assertEquals("vi", body["target_language_code"]?.jsonPrimitive?.content)
        assertEquals("Ăn uống", body["categories"]?.jsonArray?.single()?.jsonObject?.get("name")?.jsonPrimitive?.content)
        assertEquals(JsonNull, body["categories"]?.jsonArray?.single()?.jsonObject?.get("parent_name"))
        assertEquals("cash", body["wallets"]?.jsonArray?.single()?.jsonObject?.get("kind_raw_value")?.jsonPrimitive?.content)

        assertEquals("Cửa hàng", result.merchantName)
        assertEquals(544L, result.totalMinor)
        assertEquals("JPY", result.currencyCode)
        assertEquals("wallet-1", result.walletId)
        assertEquals(0.87, result.confidence, 0.0)
        assertEquals(2, result.items.size)
        assertEquals(BillItemLineType.PURCHASE, result.items[0].lineType)
        assertEquals("3@ まろやかミルク 198", result.items[0].rawLineText)
        assertEquals(3, result.items[0].quantity)
        assertEquals(594L, result.items[0].finalAmountMinor)
        assertEquals(BillItemLineType.DISCOUNT, result.items[1].lineType)
        assertEquals(-50L, result.items[1].finalAmountMinor)
        assertEquals(2, result.quota?.usedCount)
        assertEquals(8, result.quota?.remainingCount)
    }

    @Test
    fun `429 with valid quota maps daily limit and keeps quota`() = runTest {
        server.enqueue(MockResponse().setResponseCode(429).setBody(
            """{"message":"private quota detail","quota":{"allowed":false,"used_count":"10","limit_count":10,"remaining_count":"0","usage_date":"2026-09-24","reset_time_zone":"Asia/Tokyo","retry_after":"2026-09-25T00:00:00+09:00"}}"""
        ))

        val failure = runCatching {
            client.analyzeBillItems(sampleRequest(), "user-access-token")
        }.exceptionOrNull() as ReceiptAnalysisException

        assertEquals(ReceiptAnalysisFailure.DAILY_LIMIT_REACHED, failure.reason)
        assertEquals(429, failure.statusCode)
        assertEquals(10, failure.quota?.usedCount)
        assertEquals("2026-09-25T00:00:00+09:00", failure.quota?.retryAfter)
        assertFalse(failure.message.orEmpty().contains("private quota detail"))
    }

    @Test
    fun `429 without valid quota is an invalid response`() = runTest {
        server.enqueue(MockResponse().setResponseCode(429).setBody("""{"message":"limit"}"""))

        val failure = runCatching {
            client.analyzeBillItems(sampleRequest(), "user-access-token")
        }.exceptionOrNull() as ReceiptAnalysisException

        assertEquals(ReceiptAnalysisFailure.INVALID_RESPONSE, failure.reason)
        assertEquals(429, failure.statusCode)
        assertEquals(null, failure.quota)
    }

    @Test
    fun `HTTP statuses map to stable typed failures without body leakage`() = runTest {
        val cases = listOf(
            401 to ReceiptAnalysisFailure.UNAUTHORIZED,
            403 to ReceiptAnalysisFailure.UNAUTHORIZED,
            400 to ReceiptAnalysisFailure.INVALID_REQUEST,
            405 to ReceiptAnalysisFailure.INVALID_REQUEST,
            413 to ReceiptAnalysisFailure.IMAGE_TOO_LARGE,
            415 to ReceiptAnalysisFailure.UNSUPPORTED_MEDIA_TYPE,
            500 to ReceiptAnalysisFailure.UPSTREAM_UNAVAILABLE,
            502 to ReceiptAnalysisFailure.UPSTREAM_UNAVAILABLE,
            504 to ReceiptAnalysisFailure.UPSTREAM_UNAVAILABLE,
            546 to ReceiptAnalysisFailure.UPSTREAM_UNAVAILABLE,
        )

        cases.forEach { (status, expected) ->
            server.enqueue(
                MockResponse().setResponseCode(status)
                    .addHeader("sb-error-code", "EDGE_FUNCTION_ERROR")
                    .setBody("secret-$status"),
            )
            val failure = runCatching {
                client.analyzeBillItems(sampleRequest(), "user-access-token")
            }.exceptionOrNull() as ReceiptAnalysisException
            assertEquals("status $status", expected, failure.reason)
            assertEquals(status, failure.statusCode)
            assertEquals("EDGE_FUNCTION_ERROR", failure.diagnosticCode)
            assertFalse(failure.message.orEmpty().contains("secret-$status"))
        }
    }

    @Test
    fun `malformed success maps invalid response`() = runTest {
        server.enqueue(MockResponse().setBody("""{"merchant_name":"private-response-detail","items":"not-an-array"}"""))

        val failure = runCatching {
            client.analyzeBillItems(sampleRequest(), "user-access-token")
        }.exceptionOrNull() as ReceiptAnalysisException

        assertEquals(ReceiptAnalysisFailure.INVALID_RESPONSE, failure.reason)
        assertEquals(200, failure.statusCode)
        assertEquals(null, failure.cause)
        assertFalse(failure.toString().contains("private-response-detail"))
    }

    @Test
    fun `unknown line type maps invalid response`() = runTest {
        server.enqueue(MockResponse().setBody(
            SUCCESS_BODY.replace("\"line_type\":\"purchase\"", "\"line_type\":\"refund\""),
        ))

        val failure = runCatching {
            client.analyzeBillItems(sampleRequest(), "user-access-token")
        }.exceptionOrNull() as ReceiptAnalysisException

        assertEquals(ReceiptAnalysisFailure.INVALID_RESPONSE, failure.reason)
        assertEquals(200, failure.statusCode)
    }

    @Test
    fun `blank token fails before network without leaking it`() = runTest {
        val failure = runCatching {
            client.analyzeBillItems(sampleRequest(), "  ")
        }.exceptionOrNull() as ReceiptAnalysisException

        assertEquals(ReceiptAnalysisFailure.UNAUTHORIZED, failure.reason)
        assertEquals(0, server.requestCount)
    }

    @Test
    fun `client configures timeout for long AI invocation`() {
        assertEquals(180_000L, client.configuredCallTimeoutMillis)
        assertEquals(170_000L, client.configuredReadTimeoutMillis)
    }

    @Test
    fun `cancellation propagates and cancels in flight call`() = runBlocking {
        server.enqueue(MockResponse().setSocketPolicy(SocketPolicy.NO_RESPONSE))
        val operation = async {
            client.analyzeBillItems(sampleRequest(), "user-access-token")
        }
        yield()
        assertNotNull(server.takeRequest(1, TimeUnit.SECONDS))

        operation.cancel()

        val failure = runCatching { operation.await() }.exceptionOrNull()
        assertTrue(failure is CancellationException)
    }

    private fun sampleRequest() = BillItemAnalysisRequest(
        imageBase64 = "AQID",
        mimeType = "image/jpeg",
        localeIdentifier = "ja_JP",
        timeZoneIdentifier = "Asia/Tokyo",
        currencyCode = "JPY",
        targetLanguageCode = "vi",
        categories = listOf(
            ReceiptAnalysisCategoryCandidate(
                id = "category-1",
                name = "Ăn uống",
                parentName = null,
                kindRawValue = "expense",
            ),
        ),
        wallets = listOf(
            ReceiptAnalysisWalletCandidate(
                id = "wallet-1",
                name = "Tiền mặt",
                kindRawValue = "cash",
                currencyCode = "JPY",
                institutionDisplayName = null,
            ),
        ),
    )

    private companion object {
        const val SUCCESS_BODY = """
            {
              "merchant_name":" Cửa hàng ",
              "total_minor":"544",
              "currency_code":"jpy",
              "occurred_at":"2026-09-24T10:30:00+09:00",
              "wallet_id":"wallet-1",
              "multiple_bills_detected":false,
              "confidence":"0.87",
              "missing_fields":[],
              "raw_text":"3@ まろやかミルク 198\nクーポン -50",
              "items":[
                {
                  "line_id":"line-1",
                  "source_line_indexes":[1],
                  "raw_line_text":"3@ まろやかミルク 198",
                  "original_name":"まろやかミルク",
                  "translated_name":"Sữa dịu",
                  "line_type":"purchase",
                  "quantity":"3",
                  "original_amount_minor":594.0,
                  "discount_amount_minor":"0",
                  "final_amount_minor":"594",
                  "category_id":"category-1",
                  "confidence":0.9,
                  "missing_fields":[]
                },
                {
                  "line_id":"line-2",
                  "raw_line_text":"クーポン -50",
                  "original_name":"クーポン",
                  "translated_name":"Phiếu giảm giá",
                  "line_type":"discount",
                  "quantity":null,
                  "original_amount_minor":null,
                  "discount_amount_minor":50,
                  "final_amount_minor":-50,
                  "category_id":null,
                  "confidence":0.8,
                  "missing_fields":[]
                }
              ],
              "quota":{"allowed":true,"used_count":"2","limit_count":10,"remaining_count":"8"}
            }
        """
    }
}
