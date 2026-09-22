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
import vn.com.quyln.mistia.core.model.CloudEntity
import vn.com.quyln.mistia.core.model.CloudRecord
import vn.com.quyln.mistia.core.model.RemotePage
import vn.com.quyln.mistia.core.model.RemoteMutationStore
import vn.com.quyln.mistia.core.model.RemoteStore
import vn.com.quyln.mistia.core.model.UserId

private val POSTGREST_JSON_MEDIA_TYPE = "application/json; charset=utf-8".toMediaType()

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
    private val writableEntities: Set<CloudEntity> = emptySet(),
) : RemoteStore, RemoteMutationStore {
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

    override suspend fun fetchRecord(
        entity: CloudEntity,
        recordId: String,
        accessToken: String,
        ownerUserId: UserId,
    ): CloudRecord? = withContext(Dispatchers.IO) {
        requireRecordIdentity(recordId, ownerUserId)
        val url = tableUrl(entity)
            .addQueryParameter("select", "*")
            .addQueryParameter("id", "eq.$recordId")
            .addQueryParameter("user_id", "eq.${ownerUserId.value}")
            .addQueryParameter("limit", "1")
            .build()
        val request = authorizedRequest(url.toString(), accessToken).get().build()
        client.newCall(request).execute().use { response ->
            response.requireObjectRows().firstOrNull()?.toCloudRecord(entity, ownerUserId)
        }
    }

    override suspend fun createRecord(
        entity: CloudEntity,
        accessToken: String,
        ownerUserId: UserId,
        payload: JsonObject,
    ): CloudRecord = withContext(Dispatchers.IO) {
        requireWriteEnabled(entity)
        val recordId = payload.string("id") ?: error("Mutation payload is missing id")
        requirePayloadIdentity(payload, recordId, ownerUserId)
        val url = tableUrl(entity)
            .addQueryParameter("user_id", "eq.${ownerUserId.value}")
            .build()
        val request = authorizedRequest(url.toString(), accessToken)
            .header("Content-Type", "application/json")
            .header("Prefer", "return=representation")
            .post(json.encodeToString(JsonArray(listOf(payload))).toRequestBody(POSTGREST_JSON_MEDIA_TYPE))
            .build()
        client.newCall(request).execute().use { response ->
            response.requireObjectRows().firstOrNull()?.toCloudRecord(entity, ownerUserId)
                ?: error("Supabase create returned no ${entity.table} row")
        }
    }

    override suspend fun conditionalUpdate(
        entity: CloudEntity,
        recordId: String,
        accessToken: String,
        ownerUserId: UserId,
        expectedVersion: Long,
        payload: JsonObject,
    ): CloudRecord? = withContext(Dispatchers.IO) {
        requireWriteEnabled(entity)
        require(expectedVersion >= 0) { "Expected version cannot be negative" }
        requirePayloadIdentity(payload, recordId, ownerUserId)
        val url = tableUrl(entity)
            .addQueryParameter("id", "eq.$recordId")
            .addQueryParameter("user_id", "eq.${ownerUserId.value}")
            .addQueryParameter("sync_version", "eq.$expectedVersion")
            .build()
        val request = authorizedRequest(url.toString(), accessToken)
            .header("Content-Type", "application/json")
            .header("Prefer", "return=representation")
            .patch(json.encodeToString(payload).toRequestBody(POSTGREST_JSON_MEDIA_TYPE))
            .build()
        client.newCall(request).execute().use { response ->
            response.requireObjectRows().firstOrNull()?.toCloudRecord(entity, ownerUserId)
        }
    }

    private fun tableUrl(entity: CloudEntity) = config.projectUrl.toHttpUrl().newBuilder()
        .addPathSegments("rest/v1")
        .addPathSegment(entity.table)

    private fun authorizedRequest(url: String, accessToken: String): Request.Builder {
        check(config.isConfigured) { "Supabase is not configured for this build" }
        return Request.Builder()
            .url(url)
            .header("apikey", config.anonKey)
            .header("Authorization", "Bearer $accessToken")
            .header("Accept", "application/json")
    }

    private fun requireWriteEnabled(entity: CloudEntity) {
        check(entity in writableEntities) { "Cloud writes are disabled for ${entity.table}" }
    }

    private fun requireRecordIdentity(recordId: String, ownerUserId: UserId) {
        require(recordId.isNotBlank()) { "Record ID cannot be blank" }
        require(ownerUserId.value.isNotBlank()) { "Owner user ID cannot be blank" }
    }

    private fun requirePayloadIdentity(payload: JsonObject, recordId: String, ownerUserId: UserId) {
        requireRecordIdentity(recordId, ownerUserId)
        require(payload.string("id") == recordId) { "Mutation payload ID does not match request" }
        require(payload.string("user_id") == ownerUserId.value) { "Mutation payload owner does not match request" }
    }

    private fun Response.requireObjectRows(): List<JsonObject> {
        val raw = body.string()
        if (!isSuccessful) throw SupabaseHttpException(code, raw)
        if (raw.isBlank()) return emptyList()
        return (json.parseToJsonElement(raw) as? JsonArray)
            ?.mapNotNull { it as? JsonObject }
            ?: error("Supabase response was not a JSON array")
    }

    private fun JsonObject.toCloudRecord(entity: CloudEntity, ownerUserId: UserId): CloudRecord {
        val recordId = string("id") ?: error("Supabase ${entity.table} row is missing id")
        require(string("user_id") == ownerUserId.value) { "Supabase row owner does not match request" }
        return CloudRecord(
            entity = entity.table,
            id = recordId,
            ownerUserId = ownerUserId.value,
            payload = this,
            updatedAt = string("updated_at"),
            deletedAt = string("deleted_at"),
            syncVersion = long("sync_version"),
        )
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
