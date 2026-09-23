package vn.com.quyln.mistia.core.network

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import vn.com.quyln.mistia.core.model.CategoryNameLanguage
import vn.com.quyln.mistia.core.model.CategoryNameTranslations
import vn.com.quyln.mistia.core.model.CategoryNameTranslator

class SupabaseCategoryNameTranslator(
    private val config: SupabaseConfig,
    private val client: OkHttpClient,
    private val json: Json = MistiaWireFormat.json,
) : CategoryNameTranslator {
    override suspend fun translate(
        inputName: String,
        sourceLanguage: CategoryNameLanguage,
        accessToken: String,
    ): CategoryNameTranslations = withContext(Dispatchers.IO) {
        check(config.isConfigured) { "Supabase is not configured for this build" }
        val name = inputName.trim()
        require(name.isNotEmpty()) { "Category name cannot be blank" }
        require(accessToken.isNotBlank()) { "Access token cannot be blank" }
        val payload = buildJsonObject {
            put("name", JsonPrimitive(name))
            put("source_language", JsonPrimitive(sourceLanguage.wireValue))
        }
        val url = config.projectUrl.toHttpUrl().newBuilder()
            .addPathSegments("functions/v1")
            .addPathSegment("translate-category-name")
            .build()
        val request = Request.Builder()
            .url(url)
            .header("apikey", config.anonKey)
            .header("Authorization", "Bearer $accessToken")
            .header("Accept", "application/json")
            .header("Content-Type", "application/json")
            .post(payload.toString().toRequestBody(JSON_MEDIA_TYPE))
            .build()

        client.newCall(request).execute().use { response ->
            val raw = response.body.string()
            if (!response.isSuccessful) throw SupabaseHttpException(response.code, raw)
            val body = json.parseToJsonElement(raw) as? JsonObject
                ?: error("Category translation response was not an object")
            CategoryNameTranslations(
                name = body.string("name_vietnamese").orEmpty().trim(),
                nameEnglish = body.string("name_english")?.trim()?.takeIf(String::isNotEmpty),
                nameJapanese = body.string("name_japanese")?.trim()?.takeIf(String::isNotEmpty),
            )
        }
    }

    private fun JsonObject.string(key: String): String? =
        (get(key) as? JsonPrimitive)?.contentOrNull

    private companion object {
        val JSON_MEDIA_TYPE = "application/json; charset=utf-8".toMediaType()
    }
}
