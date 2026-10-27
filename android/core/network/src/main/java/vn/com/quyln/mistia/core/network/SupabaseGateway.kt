package vn.com.quyln.mistia.core.network

import java.io.IOException
import java.util.UUID
import java.time.Instant
import java.time.YearMonth
import vn.com.quyln.mistia.core.model.DueOccurrenceRecord
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.longOrNull
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import okhttp3.HttpUrl.Companion.toHttpUrl
import vn.com.quyln.mistia.core.model.DueSourceKind
import vn.com.quyln.mistia.core.model.CloudEntity
import vn.com.quyln.mistia.core.model.CloudRecord
import vn.com.quyln.mistia.core.model.RemotePage
import vn.com.quyln.mistia.core.model.RemoteMutationStore
import vn.com.quyln.mistia.core.model.RemoteStore
import vn.com.quyln.mistia.core.model.UserId
import vn.com.quyln.mistia.core.model.TransactionCategoryRecord
import vn.com.quyln.mistia.core.model.SystemCategoryPage

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
    val serviceCode: String? = null,
) : IOException("Supabase request failed ($statusCode)")

class SupabasePostgrestRemoteStore(
    private val config: SupabaseConfig,
    private val client: OkHttpClient,
    private val json: Json = Json { ignoreUnknownKeys = true },
    private val writableEntities: Set<CloudEntity> = emptySet(),
    private val writableDueSources: Set<DueSourceKind> = setOf(DueSourceKind.RECURRING_BILL),
    private val allowInstallmentOccurrenceDeletes: Boolean = false,
    private val allowInstallmentOccurrenceSkips: Boolean = false,
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
            require(table!=CloudEntity.LEDGER_WALLET.table || records.none{vn.com.quyln.mistia.core.model.LOCAL_INVESTMENT_WALLET_PARENTS_KEY in it}) {"Remote wallet cannot supply local publication evidence"}
            require(table!=CloudEntity.INVESTMENT_ASSET.table || records.none{record->vn.com.quyln.mistia.core.model.LOCAL_ASSET_PUBLICATION_KEYS.any{it in record}}) {"Remote asset cannot supply local image provenance"}
            require(table!=CloudEntity.INVESTMENT_TRADE.table || records.none{vn.com.quyln.mistia.core.model.LOCAL_TRADE_PUBLICATION_PARENTS_KEY in it}) {"Remote trade cannot supply local publication evidence"}
            require(table!=CloudEntity.LEDGER_TRANSACTION.table || records.none{row->row.keys.any{it.startsWith("_mistia_android_")}}) {"Remote ledger cannot supply local publication evidence"}
            require(table!=CloudEntity.INVESTMENT_CHANNEL.table || records.none{vn.com.quyln.mistia.core.model.LOCAL_INVESTMENT_METADATA_STAGES_KEY in it}) {"Remote channel cannot supply local publication evidence"}
            RemotePage(records = records, nextOffset = if (records.size == limit) offset + limit else null)
        }
    }

    override suspend fun fetchInstallmentCyclePage(planId: String, month: String, accessToken: String, ownerUserId: UserId,
        offset: Int, limit: Int): vn.com.quyln.mistia.core.model.DueOccurrencePage = withContext(Dispatchers.IO) {
        for (id in listOf(planId, ownerUserId.value)) require(id.length == 36 && UUID.fromString(id).toString() == id)
        require(YearMonth.parse(month).toString() == month && accessToken.isNotBlank())
        require(offset >= 0 && limit in 1..1000 && offset <= Int.MAX_VALUE - limit)
        val url = tableUrl(CloudEntity.DUE_OCCURRENCE_RECORD).addQueryParameter("select", "*")
            .addQueryParameter("user_id", "eq.${ownerUserId.value}").addQueryParameter("source_kind_raw_value", "eq.installment")
            .addQueryParameter("source_id", "eq.$planId").addQueryParameter("selected_month_key", "eq.$month")
            .addQueryParameter("order", "id.asc").build()
        val request = authorizedRequest(url.toString(), accessToken).header("Prefer", "count=exact").header("Range-Unit", "items")
            .header("Range", "$offset-${offset + limit - 1}").get().build()
        client.newCall(request).execute().use { response ->
            val rows = response.requireObjectRows(strict = true)
            require(rows.size <= limit)
            val records = rows.map { payload -> payload.toCloudRecord(CloudEntity.DUE_OCCURRENCE_RECORD, ownerUserId).also { record ->
                val cycle = DueOccurrenceRecord.fromCloudRecord(record)
                val version = requireNotNull(payload["sync_version"] as? JsonPrimitive)
                require(!version.isString && version.longOrNull == record.syncVersion && record.syncVersion >= 0)
                require(cycle.id == record.id && cycle.ownerUserId == ownerUserId.value && cycle.sourceKindWireValue == "installment" && cycle.sourceId == planId && cycle.selectedMonthKey == month)
            } }
            require(records.map { it.id }.distinct().size == records.size)
            val parts = requireNotNull(response.header("Content-Range")).split('/')
            require(parts.size == 2)
            val total = requireNotNull(parts[1].toIntOrNull()); require(total >= 0)
            val consumed = offset + records.size
            if (records.isEmpty()) require(parts[0] == "*" && offset >= total)
            else require(parts[0] == "$offset-${consumed - 1}" && consumed <= total)
            vn.com.quyln.mistia.core.model.DueOccurrencePage(records, if (consumed < total) consumed else null)
        }
    }

    override suspend fun fetchSystemCategoryPage(
        systemKey: String,
        accessToken: String,
        ownerUserId: UserId,
        offset: Int,
        limit: Int,
    ): SystemCategoryPage = withContext(Dispatchers.IO) {
        require(systemKey.matches(Regex("[a-z][a-z0-9_]{0,127}"))) { "Invalid system category key" }
        require(accessToken.isNotBlank()) { "Access token cannot be blank" }
        require(ownerUserId.value.matches(Regex("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")))
        val owner = UserId(UUID.fromString(ownerUserId.value).toString())
        require(offset >= 0 && limit in 1..1_000 && offset <= Int.MAX_VALUE - limit) { "Invalid system category page range" }
        val url = tableUrl(CloudEntity.TRANSACTION_CATEGORY)
            .addQueryParameter("select", "*")
            .addQueryParameter("user_id", "eq.${owner.value}")
            .addQueryParameter("system_key", "eq.$systemKey")
            .addQueryParameter("is_system", "eq.true")
            .addQueryParameter("order", "id.asc")
            .build()
        val request = authorizedRequest(url.toString(), accessToken)
            .header("Prefer", "count=exact")
            .header("Range-Unit", "items")
            .header("Range", "$offset-${offset + limit - 1}")
            .get().build()
        client.newCall(request).execute().use { response ->
            val rows = response.requireObjectRows(strict = true)
            require(rows.size <= limit) { "System category response exceeded requested page" }
            val records = rows.map { payload ->
                val version = (payload["sync_version"] as? JsonPrimitive)?.takeUnless { it.isString }?.longOrNull
                require(version != null && version >= 0) { "Invalid system category version" }
                val system = (payload["is_system"] as? JsonPrimitive)?.takeUnless { it.isString }?.booleanOrNull
                require(system == true && payload.string("system_key") == systemKey) { "System category key does not match request" }
                payload.toCloudRecord(CloudEntity.TRANSACTION_CATEGORY, owner).also { record ->
                    val decoded = TransactionCategoryRecord.fromCloudRecord(record)
                    require(decoded.id == record.id && decoded.ownerUserId == owner.value && decoded.isSystem && decoded.systemKey == systemKey)
                }
            }
            // Exact range metadata detects a server page cap below our requested limit.
            val range = requireNotNull(response.header("Content-Range")) { "Missing system category range" }
            val parts = range.split('/')
            require(parts.size == 2)
            val total = requireNotNull(parts[1].toIntOrNull()) { "Missing exact system category count" }
            require(total >= 0)
            val consumed = offset + records.size
            if (records.isEmpty()) {
                require(parts[0] == "*" && offset >= total) { "Empty system category page before end" }
            } else {
                require(parts[0] == "$offset-${consumed - 1}" && consumed <= total) { "Inconsistent system category range" }
            }
            SystemCategoryPage(records, if (consumed < total) consumed else null)
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
        requireWriteEnabled(entity, payload, creating = true)
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
            val record = response.requireObjectRows().firstOrNull()?.toCloudRecord(entity, ownerUserId)
                ?: error("Supabase create returned no ${entity.table} row")
            if (entity == CloudEntity.DUE_OCCURRENCE_RECORD && payload.string("source_kind_raw_value") == "installment")
                require(record.id == recordId) { "Supabase occurrence response identity does not match request" }
            record
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
        requireWriteEnabled(entity, payload)
        require(expectedVersion >= 0) { "Expected version cannot be negative" }
        if (entity == CloudEntity.DUE_OCCURRENCE_RECORD && payload.string("source_kind_raw_value") == "installment")
            require(requireNotNull((payload["sync_version"] as? JsonPrimitive)?.longOrNull) > expectedVersion)
        requirePayloadIdentity(payload, recordId, ownerUserId)
        val url = tableUrl(entity)
            .addQueryParameter("id", "eq.$recordId")
            .addQueryParameter("user_id", "eq.${ownerUserId.value}")
            .addQueryParameter("sync_version", "eq.$expectedVersion")
            .apply {
                if (entity == CloudEntity.DUE_OCCURRENCE_RECORD) {
                    addQueryParameter("source_kind_raw_value", "eq.${payload.string("source_kind_raw_value")}")
                    if (payload.string("source_kind_raw_value") == "installment" && payload.string("status_raw_value") == "skipped") {
                        val undo = payload.string("deleted_at") != null
                        addQueryParameter("status_raw_value", if (undo) "eq.skipped" else "in.(pending,skipped)")
                        addQueryParameter("paid_at", "is.null"); addQueryParameter("linked_transaction_id", "is.null")
                        if (undo) addQueryParameter("amount_minor_snapshot", "is.null")
                    }
                }
            }
            .build()
        val request = authorizedRequest(url.toString(), accessToken)
            .header("Content-Type", "application/json")
            .header("Prefer", "return=representation")
            .patch(json.encodeToString(payload).toRequestBody(POSTGREST_JSON_MEDIA_TYPE))
            .build()
        client.newCall(request).execute().use { response ->
            response.requireObjectRows().firstOrNull()?.toCloudRecord(entity, ownerUserId)?.also { record ->
                if (entity == CloudEntity.DUE_OCCURRENCE_RECORD && payload.string("source_kind_raw_value") == "installment")
                    require(record.id == recordId) { "Supabase occurrence response identity does not match request" }
            }
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

    private fun requireWriteEnabled(entity: CloudEntity, payload: JsonObject, creating: Boolean = false) {
        require(entity!=CloudEntity.LEDGER_WALLET || vn.com.quyln.mistia.core.model.LOCAL_INVESTMENT_WALLET_PARENTS_KEY !in payload) {"Local investment wallet evidence cannot enter a generic writer"}

        check(entity in writableEntities) { "Cloud writes are disabled for ${entity.table}" }
        check(!entity.table.startsWith("investment_")) {"Investment entities require their dedicated write pipeline"}
        if(entity==CloudEntity.LEDGER_WALLET) check(!vn.com.quyln.mistia.core.model.requiresInvestmentWalletDomain(
            UserId(payload.string("user_id").orEmpty()),payload.string("id").orEmpty(),payload)) {"Investment wallets require their dedicated write pipeline"}
        if(entity==CloudEntity.LEDGER_TRANSACTION)check(!vn.com.quyln.mistia.core.model.requiresInvestmentLedgerDomain(payload)) {
            "Investment ledger writes require their dedicated atomic pipeline"
        }
        if (entity == CloudEntity.DUE_OCCURRENCE_RECORD) {
            if (payload.string("source_kind_raw_value") == "installment") {
                val skip = payload.string("status_raw_value") == "skipped"
                if (skip) {
                    check(allowInstallmentOccurrenceSkips) { "Installment skip writes are disabled" }
                    val financial = setOf("paid_at", "linked_transaction_id", "amount_minor_snapshot")
                    require(financial.all { payload[it] == kotlinx.serialization.json.JsonNull })
                    val undoFields = setOf("id", "user_id", "source_kind_raw_value", "status_raw_value", "amount_minor_snapshot", "paid_at", "linked_transaction_id", "updated_at", "deleted_at", "sync_version", "last_modified_by_device_id")
                    if (payload.string("deleted_at") != null) {
                        require(!creating && payload.keys == undoFields)
                        Instant.parse(requireNotNull(payload.string("deleted_at")))
                    } else {
                        require(payload["deleted_at"] == kotlinx.serialization.json.JsonNull)
                        val typed = DueOccurrenceRecord.fromCloudRecord(CloudRecord(entity.table, requireNotNull(payload.string("id")), requireNotNull(payload.string("user_id")), payload,
                            payload.string("updated_at"), null, requireNotNull((payload["sync_version"] as? JsonPrimitive)?.longOrNull)))
                        require(payload.keys == typed.toPayload().keys)
                        require(YearMonth.parse(typed.selectedMonthKey).toString() == typed.selectedMonthKey)
                        val source = requireNotNull(payload.string("source_id")); require(source.length == 36 && UUID.fromString(source).toString() == source)
                    }
                } else {
                    check(allowInstallmentOccurrenceDeletes && !creating) { "Installment occurrence creation/edits are disabled" }
                    require(payload.keys == setOf("id", "user_id", "source_kind_raw_value", "updated_at", "deleted_at", "sync_version", "last_modified_by_device_id"))
                    Instant.parse(requireNotNull(payload.string("deleted_at")))
                }
                for (key in listOf("id", "user_id", "last_modified_by_device_id")) {
                    val value = requireNotNull(payload.string(key))
                    require(value.length == 36 && UUID.fromString(value).toString() == value)
                }
                Instant.parse(requireNotNull(payload.string("updated_at")))
                val version = requireNotNull(payload["sync_version"] as? JsonPrimitive)
                require(!version.isString && version.longOrNull != null && requireNotNull(version.longOrNull) >= 0)
            } else check(payload.string("source_kind_raw_value") in writableDueSources.map { it.wireValue }) { "Cloud due source writes are disabled" }
        }
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

    private fun Response.requireObjectRows(strict: Boolean = false): List<JsonObject> {
        val raw = body.string()
        if (!isSuccessful) throw SupabaseHttpException(code, raw)
        if (raw.isBlank()) {
            check(!strict) { "Supabase response was empty" }
            return emptyList()
        }
        val rows = json.parseToJsonElement(raw) as? JsonArray ?: error("Supabase response was not a JSON array")
        return if (strict) rows.map { it as? JsonObject ?: error("Supabase response contained a non-object row") }
            else rows.mapNotNull { it as? JsonObject }
    }

    private fun JsonObject.toCloudRecord(entity: CloudEntity, ownerUserId: UserId): CloudRecord {
        require(entity!=CloudEntity.LEDGER_TRANSACTION || keys.none{it.startsWith("_mistia_android_")}) {"Remote ledger cannot supply local publication evidence"}
        require(entity!=CloudEntity.INVESTMENT_CHANNEL || vn.com.quyln.mistia.core.model.LOCAL_INVESTMENT_METADATA_STAGES_KEY !in this) {"Remote channel cannot supply local publication evidence"}
        require(entity!=CloudEntity.LEDGER_WALLET || vn.com.quyln.mistia.core.model.LOCAL_INVESTMENT_WALLET_PARENTS_KEY !in this) {"Remote wallet cannot supply local publication evidence"}
        require(entity!=CloudEntity.INVESTMENT_ASSET || vn.com.quyln.mistia.core.model.LOCAL_ASSET_PUBLICATION_KEYS.none{it in this}) {"Remote asset cannot supply local image provenance"}
        require(entity!=CloudEntity.INVESTMENT_TRADE || vn.com.quyln.mistia.core.model.LOCAL_TRADE_PUBLICATION_PARENTS_KEY !in this) {"Remote trade cannot supply local publication evidence"}
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
