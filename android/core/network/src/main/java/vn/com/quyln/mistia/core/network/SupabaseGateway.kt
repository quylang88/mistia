package vn.com.quyln.mistia.core.network

import java.io.IOException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.longOrNull
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import okhttp3.HttpUrl.Companion.toHttpUrl
import vn.com.quyln.mistia.core.model.RemotePage
import vn.com.quyln.mistia.core.model.RemoteStore
import vn.com.quyln.mistia.core.model.UserId

data class SupabaseConfig(
    val projectUrl: String,
    val anonKey: String,
) {
    val isConfigured: Boolean
        get() = projectUrl.startsWith("https://") && anonKey.isNotBlank()
}

class SupabaseHttpException(
    val statusCode: Int,
    val responseBody: String,
) : IOException("Supabase request failed ($statusCode)")

class SupabasePostgrestRemoteStore(
    private val config: SupabaseConfig,
    private val client: OkHttpClient,
    private val json: Json = Json { ignoreUnknownKeys = true },
) : RemoteStore {
    override suspend fun pullPage(
        table: String,
        accessToken: String,
        ownerUserId: UserId,
        offset: Int,
        limit: Int,
    ): RemotePage = withContext(Dispatchers.IO) {
        check(config.isConfigured) { "Supabase is not configured for this build" }
        require(table.matches(Regex("^[a-z][a-z0-9_]+$"))) { "Unsafe PostgREST table name" }
        require(limit in 1..1_000)

        val orderColumn = when (table) {
            "user_profiles" -> "user_id"
            "account_devices" -> "device_id"
            else -> "id"
        }
        val url = config.projectUrl.toHttpUrl().newBuilder()
            .addPathSegments("rest/v1")
            .addPathSegment(table)
            .addQueryParameter("select", "*")
            .addQueryParameter("order", "$orderColumn.asc")
            .build()
        val request = Request.Builder()
            .url(url)
            .header("apikey", config.anonKey)
            .header("Authorization", "Bearer $accessToken")
            .header("Accept", "application/json")
            .header("Range-Unit", "items")
            .header("Range", "$offset-${offset + limit - 1}")
            .get()
            .build()

        client.newCall(request).execute().use { response ->
            val body = response.body.string()
            if (!response.isSuccessful) throw SupabaseHttpException(response.code, body)
            val records = (json.parseToJsonElement(body) as? JsonArray)
                ?.mapNotNull { it as? JsonObject }
                .orEmpty()
            RemotePage(records = records, nextOffset = if (records.size == limit) offset + limit else null)
        }
    }
}

/**
 * All non-trivial writes go through this gateway so feature gates, explicit nulls, RLS errors,
 * and atomic RPC behavior stay testable outside a ViewModel or UI.
 */
class SupabaseMutationGateway(
    private val config: SupabaseConfig,
    private val client: OkHttpClient,
    private val writesEnabled: Boolean,
    private val json: Json = Json { explicitNulls = true; encodeDefaults = true },
) {
    suspend fun rpc(function: String, accessToken: String, payload: JsonObject): JsonElement =
        withContext(Dispatchers.IO) {
            check(writesEnabled) { "Cloud writes are disabled in this APK feature gate" }
            require(function.matches(Regex("^[a-z][a-z0-9_]+$"))) { "Unsafe RPC name" }
            val request = Request.Builder()
                .url(
                    config.projectUrl.toHttpUrl().newBuilder()
                        .addPathSegments("rest/v1/rpc")
                        .addPathSegment(function)
                        .build()
                )
                .header("apikey", config.anonKey)
                .header("Authorization", "Bearer $accessToken")
                .header("Content-Type", "application/json")
                .post(json.encodeToString(payload).toRequestBody(JSON_MEDIA_TYPE))
                .build()
            client.newCall(request).execute().use { response -> response.requireJson(json) }
        }

    suspend fun patch(
        table: String,
        recordId: String,
        accessToken: String,
        payload: JsonObject,
    ): JsonElement = withContext(Dispatchers.IO) {
        check(writesEnabled) { "Cloud writes are disabled in this APK feature gate" }
        require(table.matches(Regex("^[a-z][a-z0-9_]+$")))
        val url = config.projectUrl.toHttpUrl().newBuilder()
            .addPathSegments("rest/v1")
            .addPathSegment(table)
            .addQueryParameter("id", "eq.$recordId")
            .build()
        val request = Request.Builder()
            .url(url)
            .header("apikey", config.anonKey)
            .header("Authorization", "Bearer $accessToken")
            .header("Content-Type", "application/json")
            .header("Prefer", "return=representation")
            .patch(json.encodeToString(payload).toRequestBody(JSON_MEDIA_TYPE))
            .build()
        client.newCall(request).execute().use { response -> response.requireJson(json) }
    }

    private fun Response.requireJson(json: Json): JsonElement {
        val raw = body.string()
        if (!isSuccessful) throw SupabaseHttpException(code, raw)
        return if (raw.isBlank()) JsonArray(emptyList()) else json.parseToJsonElement(raw)
    }

    private companion object {
        val JSON_MEDIA_TYPE = "application/json; charset=utf-8".toMediaType()
    }
}

internal fun JsonObject.string(key: String): String? =
    (get(key) as? JsonPrimitive)?.contentOrNull

internal fun JsonObject.long(key: String): Long =
    (get(key) as? JsonPrimitive)?.longOrNull ?: 0L
