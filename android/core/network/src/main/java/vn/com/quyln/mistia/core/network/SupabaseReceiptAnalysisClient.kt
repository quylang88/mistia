package vn.com.quyln.mistia.core.network

import java.io.IOException
import java.math.RoundingMode
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.longOrNull
import okhttp3.Call
import okhttp3.Callback
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import vn.com.quyln.mistia.core.model.BillItemAnalysisItem
import vn.com.quyln.mistia.core.model.BillItemAnalysisRequest
import vn.com.quyln.mistia.core.model.BillItemAnalysisResult
import vn.com.quyln.mistia.core.model.BillItemLineType
import vn.com.quyln.mistia.core.model.ReceiptAnalysisClient
import vn.com.quyln.mistia.core.model.ReceiptAnalysisException
import vn.com.quyln.mistia.core.model.ReceiptAnalysisFailure
import vn.com.quyln.mistia.core.model.ReceiptAnalysisQuota

class SupabaseReceiptAnalysisClient(
    private val config: SupabaseConfig,
    private val client: OkHttpClient,
    private val json: Json = MistiaWireFormat.json,
) : ReceiptAnalysisClient {
    private val analysisClient = client.newBuilder()
        .readTimeout(READ_TIMEOUT_SECONDS, TimeUnit.SECONDS)
        .callTimeout(CALL_TIMEOUT_SECONDS, TimeUnit.SECONDS)
        .build()

    internal val configuredCallTimeoutMillis: Long
        get() = analysisClient.callTimeoutMillis.toLong()

    internal val configuredReadTimeoutMillis: Long
        get() = analysisClient.readTimeoutMillis.toLong()

    override suspend fun analyzeBillItems(
        request: BillItemAnalysisRequest,
        accessToken: String,
    ): BillItemAnalysisResult {
        validatePreconditions(request, accessToken)
        val url = config.projectUrl.toHttpUrl().newBuilder()
            .addPathSegments("functions/v1")
            .addPathSegment("analyze-bill-items")
            .build()
        val httpRequest = Request.Builder()
            .url(url)
            .header("apikey", config.anonKey)
            .header("Authorization", "Bearer $accessToken")
            .header("Accept", "application/json")
            .header("Content-Type", "application/json")
            .post(json.encodeToString(request).toRequestBody(JSON_MEDIA_TYPE))
            .build()

        val response = try {
            analysisClient.newCall(httpRequest).await()
        } catch (error: CancellationException) {
            throw error
        } catch (error: IOException) {
            throw ReceiptAnalysisException(ReceiptAnalysisFailure.NETWORK, cause = error)
        }

        return response.use { httpResponse ->
            val rawBody = httpResponse.body.string()
            if (!httpResponse.isSuccessful) {
                throw mapHttpFailure(httpResponse, rawBody)
            }
            try {
                parseResult(rawBody).validated(
                    categoryIds = request.categories.map { it.id }.toSet(),
                    walletIds = request.wallets.map { it.id }.toSet(),
                )
            } catch (error: ReceiptAnalysisException) {
                throw error
            } catch (error: Exception) {
                throw ReceiptAnalysisException(
                    reason = ReceiptAnalysisFailure.INVALID_RESPONSE,
                    statusCode = httpResponse.code,
                    diagnosticCode = httpResponse.safeDiagnosticCode(),
                )
            }
        }
    }

    private fun validatePreconditions(request: BillItemAnalysisRequest, accessToken: String) {
        if (!config.isConfigured) {
            throw ReceiptAnalysisException(ReceiptAnalysisFailure.CONFIGURATION)
        }
        if (accessToken.isBlank()) {
            throw ReceiptAnalysisException(ReceiptAnalysisFailure.UNAUTHORIZED)
        }
        if (request.imageBase64.isBlank() || request.categories.isEmpty() || request.wallets.isEmpty()) {
            throw ReceiptAnalysisException(ReceiptAnalysisFailure.INVALID_REQUEST)
        }
        if (request.mimeType !in SUPPORTED_MIME_TYPES) {
            throw ReceiptAnalysisException(ReceiptAnalysisFailure.UNSUPPORTED_MEDIA_TYPE)
        }
    }

    private fun mapHttpFailure(response: Response, rawBody: String): ReceiptAnalysisException {
        val diagnostic = response.safeDiagnosticCode()
        if (response.code == 429) {
            val quota = runCatching { parseQuotaError(rawBody) }.getOrNull()
            return if (quota != null) {
                ReceiptAnalysisException(
                    reason = ReceiptAnalysisFailure.DAILY_LIMIT_REACHED,
                    statusCode = response.code,
                    quota = quota,
                    diagnosticCode = diagnostic,
                )
            } else {
                ReceiptAnalysisException(
                    reason = ReceiptAnalysisFailure.INVALID_RESPONSE,
                    statusCode = response.code,
                    diagnosticCode = diagnostic,
                )
            }
        }
        val reason = when (response.code) {
            401, 403 -> ReceiptAnalysisFailure.UNAUTHORIZED
            400, 405, 422 -> ReceiptAnalysisFailure.INVALID_REQUEST
            413 -> ReceiptAnalysisFailure.IMAGE_TOO_LARGE
            415 -> ReceiptAnalysisFailure.UNSUPPORTED_MEDIA_TYPE
            in 500..599 -> ReceiptAnalysisFailure.UPSTREAM_UNAVAILABLE
            else -> ReceiptAnalysisFailure.INVALID_RESPONSE
        }
        return ReceiptAnalysisException(
            reason = reason,
            statusCode = response.code,
            diagnosticCode = diagnostic,
        )
    }

    private fun parseQuotaError(rawBody: String): ReceiptAnalysisQuota? {
        val root = json.parseToJsonElement(rawBody) as? JsonObject ?: return null
        val quotaObject = root["quota"] as? JsonObject ?: return null
        if (quotaObject.boolean("allowed") != false || quotaObject["limit_count"] == null) return null
        return quotaObject.toQuota()
    }

    private fun parseResult(rawBody: String): BillItemAnalysisResult {
        val root = json.parseToJsonElement(rawBody) as? JsonObject
            ?: throw IllegalArgumentException("Receipt analysis response was not an object")
        val itemsElement = root["items"]
        val items = when (itemsElement) {
            null, JsonNull -> emptyList()
            is JsonArray -> itemsElement.map { element ->
                (element as? JsonObject)?.toItem()
                    ?: throw IllegalArgumentException("Receipt analysis item was not an object")
            }
            else -> throw IllegalArgumentException("Receipt analysis items was not an array")
        }
        return BillItemAnalysisResult(
            merchantName = root.string("merchant_name"),
            totalMinor = root.flexibleLong("total_minor"),
            currencyCode = root.string("currency_code"),
            occurredAt = root.string("occurred_at"),
            walletId = root.string("wallet_id"),
            multipleBillsDetected = root.boolean("multiple_bills_detected") ?: false,
            confidence = root.flexibleDouble("confidence") ?: 0.0,
            missingFields = root.stringList("missing_fields"),
            rawText = root.string("raw_text"),
            items = items,
            quota = (root["quota"] as? JsonObject)?.toQuota(),
        )
    }

    private fun JsonObject.toItem(): BillItemAnalysisItem {
        val decodedFinalAmount = flexibleLong("final_amount_minor") ?: 0L
        val rawLineType = string("line_type")
        val decodedType = if (rawLineType == null) {
            if (decodedFinalAmount < 0) BillItemLineType.DISCOUNT else BillItemLineType.PURCHASE
        } else {
            BillItemLineType.fromWireValue(rawLineType)
                ?: throw IllegalArgumentException("Unknown receipt item line type")
        }
        return BillItemAnalysisItem(
            lineId = string("line_id").orEmpty(),
            rawLineText = string("raw_line_text"),
            originalName = string("original_name").orEmpty(),
            translatedName = string("translated_name"),
            lineType = decodedType,
            quantity = flexibleInt("quantity"),
            originalAmountMinor = flexibleLong("original_amount_minor"),
            discountAmountMinor = flexibleLong("discount_amount_minor")
                ?: if (decodedType == BillItemLineType.DISCOUNT) decodedFinalAmount.safeAbsoluteValue() else 0L,
            finalAmountMinor = decodedFinalAmount,
            categoryId = string("category_id"),
            confidence = flexibleDouble("confidence") ?: 0.0,
            missingFields = stringList("missing_fields"),
        ).normalized()
    }

    private fun JsonObject.toQuota(): ReceiptAnalysisQuota {
        val limit = flexibleInt("limit_count")?.coerceAtLeast(0) ?: 0
        val used = flexibleInt("used_count")?.coerceAtLeast(0) ?: 0
        return ReceiptAnalysisQuota(
            allowed = boolean("allowed") ?: true,
            usedCount = used,
            limitCount = limit,
            remainingCount = flexibleInt("remaining_count") ?: (limit - used).coerceAtLeast(0),
            usageDate = string("usage_date"),
            resetTimeZone = string("reset_time_zone"),
            retryAfter = string("retry_after"),
        ).normalized()
    }

    private fun JsonObject.string(key: String): String? =
        (get(key) as? JsonPrimitive)?.contentOrNull

    private fun JsonObject.boolean(key: String): Boolean? =
        (get(key) as? JsonPrimitive)?.booleanOrNull

    private fun JsonObject.flexibleLong(key: String): Long? {
        val primitive = get(key) as? JsonPrimitive ?: return null
        primitive.longOrNull?.let { return it }
        val decimal = primitive.contentOrNull?.toBigDecimalOrNull() ?: return null
        return runCatching { decimal.setScale(0, RoundingMode.HALF_UP).longValueExact() }.getOrNull()
    }

    private fun JsonObject.flexibleInt(key: String): Int? {
        val primitive = get(key) as? JsonPrimitive ?: return null
        primitive.intOrNull?.let { return it }
        val value = primitive.contentOrNull?.toBigDecimalOrNull() ?: return null
        return runCatching { value.setScale(0, RoundingMode.HALF_UP).intValueExact() }.getOrNull()
    }

    private fun JsonObject.flexibleDouble(key: String): Double? =
        (get(key) as? JsonPrimitive)?.doubleOrNull?.takeIf(Double::isFinite)

    private fun JsonObject.stringList(key: String): List<String> = when (val element = get(key)) {
        null, JsonNull -> emptyList()
        is JsonArray -> element.mapNotNull { (it as? JsonPrimitive)?.contentOrNull }
        else -> throw IllegalArgumentException("Receipt analysis $key was not an array")
    }

    private fun Response.safeDiagnosticCode(): String? = header("sb-error-code")
        ?.trim()
        ?.takeIf { it.matches(DIAGNOSTIC_CODE_PATTERN) }

    private suspend fun Call.await(): Response = suspendCancellableCoroutine { continuation ->
        continuation.invokeOnCancellation { cancel() }
        enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                if (continuation.isCancelled) return
                continuation.resumeWithException(e)
            }

            override fun onResponse(call: Call, response: Response) {
                if (continuation.isCancelled) {
                    response.close()
                } else {
                    continuation.resume(response)
                }
            }
        })
    }

    private fun Long.safeAbsoluteValue(): Long = when {
        this == Long.MIN_VALUE -> Long.MAX_VALUE
        this < 0 -> -this
        else -> this
    }

    private companion object {
        val JSON_MEDIA_TYPE = "application/json; charset=utf-8".toMediaType()
        val SUPPORTED_MIME_TYPES = setOf("image/jpeg", "image/png", "image/heic", "image/heif")
        val DIAGNOSTIC_CODE_PATTERN = Regex("^[A-Z0-9_-]{1,100}$")
        const val READ_TIMEOUT_SECONDS = 170L
        const val CALL_TIMEOUT_SECONDS = 180L
    }
}
