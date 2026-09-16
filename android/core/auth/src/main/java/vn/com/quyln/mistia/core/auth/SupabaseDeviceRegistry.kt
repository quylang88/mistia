package vn.com.quyln.mistia.core.auth

import android.content.Context
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.HttpUrl.Companion.toHttpUrl
import vn.com.quyln.mistia.core.model.AuthSession
import vn.com.quyln.mistia.core.model.DeviceRegistration
import vn.com.quyln.mistia.core.model.DeviceRegistry
import vn.com.quyln.mistia.core.network.SupabaseConfig
import vn.com.quyln.mistia.core.network.SupabaseHttpException

interface SecureDeviceIdStore {
    fun getOrCreate(): String
}

@Suppress("DEPRECATION")
class KeystoreDeviceIdStore(context: Context) : SecureDeviceIdStore {
    private val preferences = EncryptedSharedPreferences.create(
        context,
        "mistia.secure.device",
        MasterKey.Builder(context).setKeyScheme(MasterKey.KeyScheme.AES256_GCM).build(),
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
    )

    override fun getOrCreate(): String {
        preferences.getString(KEY, null)?.let { return it }
        return UUID.randomUUID().toString().also { preferences.edit().putString(KEY, it).commit() }
    }

    private companion object { const val KEY = "device_id" }
}

class SupabaseDeviceRegistry(
    private val config: SupabaseConfig,
    private val client: OkHttpClient,
) : DeviceRegistry {
    override suspend fun register(
        session: AuthSession,
        registration: DeviceRegistration,
    ): Result<Unit> = runCatching {
        withContext(Dispatchers.IO) {
            val timestamp = Instant.now().toString()
            val payload = buildJsonArray {
                add(buildJsonObject {
                    put("user_id", registration.userId.value)
                    put("device_id", registration.deviceId)
                    put("device_name", registration.deviceName)
                    put("model_identifier", registration.modelIdentifier)
                    put("model_display_name", registration.modelDisplayName)
                    put("system_name", registration.systemName)
                    put("system_version", registration.systemVersion)
                    put("app_version", registration.appVersion)
                    put("app_build", registration.appBuild)
                    put("last_seen_at", timestamp)
                    put("signed_out_at", null)
                })
            }
            val url = config.projectUrl.toHttpUrl().newBuilder()
                .addPathSegments("rest/v1/account_devices")
                .addQueryParameter("on_conflict", "user_id,device_id")
                .build()
            val request = Request.Builder()
                .url(url)
                .header("apikey", config.anonKey)
                .header("Authorization", "Bearer ${session.accessToken}")
                .header("Content-Type", "application/json")
                .header("Prefer", "resolution=merge-duplicates,return=minimal")
                .post(payload.toString().toRequestBody(JSON_MEDIA_TYPE))
                .build()
            client.newCall(request).execute().use { response ->
                val body = response.body.string()
                if (!response.isSuccessful) throw SupabaseHttpException(response.code, body)
            }
        }
    }

    private companion object {
        val JSON_MEDIA_TYPE = "application/json; charset=utf-8".toMediaType()
    }
}
