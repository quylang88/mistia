package vn.com.quyln.mistia.core.auth

import android.content.Context
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import java.time.Instant
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.HttpUrl.Companion.toHttpUrl
import vn.com.quyln.mistia.core.model.AuthRepository
import vn.com.quyln.mistia.core.model.AuthSession
import vn.com.quyln.mistia.core.model.AuthState
import vn.com.quyln.mistia.core.model.UserId
import vn.com.quyln.mistia.core.network.SupabaseConfig
import vn.com.quyln.mistia.core.network.SupabaseHttpException

interface SecureSessionStore {
    fun read(): AuthSession?
    fun write(session: AuthSession)
    fun clear()
}

@Suppress("DEPRECATION")
class KeystoreSessionStore(context: Context) : SecureSessionStore {
    private val preferences = EncryptedSharedPreferences.create(
        context,
        "mistia.secure.session",
        MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build(),
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
    )

    override fun read(): AuthSession? {
        val userId = preferences.getString(KEY_USER_ID, null) ?: return null
        val accessToken = preferences.getString(KEY_ACCESS_TOKEN, null) ?: return null
        val refreshToken = preferences.getString(KEY_REFRESH_TOKEN, null) ?: return null
        return AuthSession(
            userId = UserId(userId),
            email = preferences.getString(KEY_EMAIL, null),
            accessToken = accessToken,
            refreshToken = refreshToken,
            expiresAtEpochSeconds = preferences.getLong(KEY_EXPIRES_AT, 0),
        )
    }

    override fun write(session: AuthSession) {
        preferences.edit()
            .putString(KEY_USER_ID, session.userId.value)
            .putString(KEY_EMAIL, session.email)
            .putString(KEY_ACCESS_TOKEN, session.accessToken)
            .putString(KEY_REFRESH_TOKEN, session.refreshToken)
            .putLong(KEY_EXPIRES_AT, session.expiresAtEpochSeconds)
            .apply()
    }

    override fun clear() {
        preferences.edit().clear().apply()
    }

    private companion object {
        const val KEY_USER_ID = "user_id"
        const val KEY_EMAIL = "email"
        const val KEY_ACCESS_TOKEN = "access_token"
        const val KEY_REFRESH_TOKEN = "refresh_token"
        const val KEY_EXPIRES_AT = "expires_at"
    }
}

class SupabaseAuthRepository(
    private val config: SupabaseConfig,
    private val client: OkHttpClient,
    private val secureStore: SecureSessionStore,
    private val json: Json = Json { ignoreUnknownKeys = true; explicitNulls = true },
    private val nowEpochSeconds: () -> Long = { Instant.now().epochSecond },
    private val clearCredentialState: suspend () -> Unit = {},
) : AuthRepository {
    private val mutableState = MutableStateFlow<AuthState>(AuthState.Restoring)
    override val state: StateFlow<AuthState> = mutableState.asStateFlow()

    override suspend fun restore() {
        val saved = secureStore.read()
        if (saved == null) {
            mutableState.value = AuthState.SignedOut
            return
        }
        mutableState.value = AuthState.SignedIn(saved)
        if (saved.shouldRefresh(nowEpochSeconds())) {
            refreshIfNeeded().onFailure { error ->
                if (error is SupabaseHttpException && error.statusCode in 400..499) {
                    secureStore.clear()
                    mutableState.value = AuthState.SignedOut
                }
            }
        }
    }

    override suspend fun signIn(email: String, password: String): Result<AuthSession> = runCatching {
        val response = post(
            path = "auth/v1/token",
            query = "grant_type" to "password",
            payload = buildJsonObject {
                put("email", email.trim())
                put("password", password)
            },
        )
        response.toSession().also(::persist)
    }

    override suspend fun signUp(email: String, password: String, displayName: String): Result<AuthSession?> = runCatching {
        val response = post(
            path = "auth/v1/signup",
            payload = buildJsonObject {
                put("email", email.trim())
                put("password", password)
                put("data", buildJsonObject { put("display_name", displayName.trim()) })
            },
        )
        val token = response["access_token"]?.jsonPrimitive?.contentOrNull
        if (token == null) null else response.toSession().also(::persist)
    }

    override suspend fun resendConfirmation(email: String): Result<Unit> = runCatching {
        post(path = "auth/v1/resend", payload = buildJsonObject {
            put("type", "signup")
            put("email", email.trim())
        })
        Unit
    }

    override suspend fun sendPasswordReset(email: String): Result<Unit> = runCatching {
        post(
            path = "auth/v1/recover",
            payload = buildJsonObject { put("email", email.trim()) },
        )
        Unit
    }

    override suspend fun exchangeGoogleIdToken(idToken: String, nonce: String?): Result<AuthSession> = runCatching {
        val response = post(
            path = "auth/v1/token",
            query = "grant_type" to "id_token",
            payload = buildJsonObject {
                put("provider", "google")
                put("id_token", idToken)
                put("nonce", nonce?.let(::JsonPrimitive) ?: JsonNull)
            },
        )
        response.toSession().also(::persist)
    }

    override suspend fun refreshIfNeeded(): Result<AuthSession?> = runCatching {
        val current = (mutableState.value as? AuthState.SignedIn)?.session ?: secureStore.read()
            ?: return@runCatching null
        if (!current.shouldRefresh(nowEpochSeconds())) return@runCatching current
        val response = post(
            path = "auth/v1/token",
            query = "grant_type" to "refresh_token",
            payload = buildJsonObject { put("refresh_token", current.refreshToken) },
        )
        response.toSession().also(::persist)
    }

    override suspend fun signOut(clearLocalSession: Boolean) {
        val current = (mutableState.value as? AuthState.SignedIn)?.session
        if (current != null) {
            runCatching { post(path = "auth/v1/logout", accessToken = current.accessToken) }
        }
        if (clearLocalSession) secureStore.clear()
        mutableState.value = AuthState.SignedOut
        runCatching { clearCredentialState() }
    }

    private fun persist(session: AuthSession) {
        secureStore.write(session)
        mutableState.value = AuthState.SignedIn(session)
    }

    private fun JsonObject.toSession(): AuthSession {
        val user = getValue("user").jsonObject
        val expiresIn = get("expires_in")?.jsonPrimitive?.intOrNull ?: 3_600
        return AuthSession(
            userId = UserId(user.getValue("id").jsonPrimitive.content),
            email = user["email"]?.jsonPrimitive?.contentOrNull,
            accessToken = getValue("access_token").jsonPrimitive.content,
            refreshToken = getValue("refresh_token").jsonPrimitive.content,
            expiresAtEpochSeconds = nowEpochSeconds() + expiresIn,
        )
    }

    private suspend fun post(
        path: String,
        payload: JsonObject = JsonObject(emptyMap()),
        query: Pair<String, String>? = null,
        accessToken: String? = null,
    ): JsonObject = withContext(Dispatchers.IO) {
        check(config.isConfigured) { "Supabase is not configured for this build" }
        val urlBuilder = config.projectUrl.toHttpUrl().newBuilder().addPathSegments(path)
        query?.let { urlBuilder.addQueryParameter(it.first, it.second) }
        val request = Request.Builder()
            .url(urlBuilder.build())
            .header("apikey", config.anonKey)
            .header("Content-Type", "application/json")
            .apply { accessToken?.let { header("Authorization", "Bearer $it") } }
            .post(payload.toString().toRequestBody(JSON_MEDIA_TYPE))
            .build()
        client.newCall(request).execute().use { response ->
            val body = response.body.string()
            if (!response.isSuccessful) throw SupabaseHttpException(response.code, body)
            if (body.isBlank()) JsonObject(emptyMap()) else json.parseToJsonElement(body).jsonObject
        }
    }

    private companion object {
        val JSON_MEDIA_TYPE = "application/json; charset=utf-8".toMediaType()
    }
}
