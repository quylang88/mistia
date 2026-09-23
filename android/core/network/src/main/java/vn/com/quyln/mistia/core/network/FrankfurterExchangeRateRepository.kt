package vn.com.quyln.mistia.core.network

import android.content.Context
import java.io.IOException
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import vn.com.quyln.mistia.core.model.ExchangeRateRepository
import vn.com.quyln.mistia.core.model.ExchangeRateSnapshot

class FrankfurterExchangeRateRepository internal constructor(
    private val client: OkHttpClient,
    private val json: Json,
    private val cache: ExchangeRateCache,
    endpointBaseUrl: String,
    private val zoneId: ZoneId,
) : ExchangeRateRepository {
    constructor(
        context: Context,
        client: OkHttpClient,
        json: Json,
        endpointBaseUrl: String = DEFAULT_ENDPOINT_BASE_URL,
        zoneId: ZoneId = ZoneId.systemDefault(),
    ) : this(
        client = client,
        json = json,
        cache = SharedPreferencesExchangeRateCache(context, json),
        endpointBaseUrl = endpointBaseUrl,
        zoneId = zoneId,
    )

    private val endpointBaseUrl = endpointBaseUrl.removeSuffix("/")
    private val refreshMutex = Mutex()
    private val mutableRates = MutableStateFlow(cache.load()?.let(::listOf).orEmpty())

    override val rates: StateFlow<List<ExchangeRateSnapshot>> = mutableRates.asStateFlow()

    override suspend fun refreshIfStale(nowEpochMillis: Long): Result<Unit> = refreshMutex.withLock {
        val now = Instant.ofEpochMilli(nowEpochMillis).atZone(zoneId)
        if (now.toLocalTime().isBefore(REFRESH_TIME)) return@withLock Result.success(Unit)
        val current = mutableRates.value.singleOrNull()
        if (current != null && fetchedLocalDate(current) == now.toLocalDate()) {
            return@withLock Result.success(Unit)
        }

        try {
            val snapshot = withContext(Dispatchers.IO) {
                fetch(nowEpochMillis).also { fetched ->
                    check(cache.save(fetched)) { "Could not persist exchange-rate cache" }
                }
            }
            mutableRates.value = listOf(snapshot)
            Result.success(Unit)
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            Result.failure(error)
        }
    }

    private fun fetchedLocalDate(snapshot: ExchangeRateSnapshot): LocalDate? = runCatching {
        Instant.ofEpochMilli(snapshot.fetchedAtEpochMillis).atZone(zoneId).toLocalDate()
    }.getOrNull()

    private fun fetch(nowEpochMillis: Long): ExchangeRateSnapshot {
        val request = Request.Builder()
            .url("$endpointBaseUrl/v2/rate/JPY/VND")
            .get()
            .build()
        return client.newCall(request).execute().use { response ->
            if (!response.isSuccessful) throw IOException("Exchange-rate request failed (${response.code})")
            val body = response.body.string()
            val payload = json.parseToJsonElement(body) as? JsonObject
                ?: throw IOException("Exchange-rate response was not an object")
            val base = payload.string("base")
            val quote = payload.string("quote")
            val rate = payload.string("rate")
            val rateDate = payload.string("date")
            if (base != "JPY" || quote != "VND") {
                throw IOException("Exchange-rate response used an unsupported pair")
            }
            val decimal = rate.toBigDecimalOrNull()?.takeIf { it.signum() > 0 }
                ?: throw IOException("Exchange-rate response contained an invalid rate")
            runCatching { LocalDate.parse(rateDate) }.getOrElse {
                throw IOException("Exchange-rate response contained an invalid date", it)
            }
            ExchangeRateSnapshot(
                baseCurrencyCode = base,
                quoteCurrencyCode = quote,
                rateDecimalString = decimal.toPlainString(),
                provider = PROVIDER,
                fetchedAtEpochMillis = nowEpochMillis,
                rateDate = rateDate,
            )
        }
    }

    private fun JsonObject.string(key: String): String =
        (get(key) as? JsonPrimitive)?.contentOrNull?.trim().orEmpty()

    private companion object {
        const val DEFAULT_ENDPOINT_BASE_URL = "https://api.frankfurter.dev"
        const val PROVIDER = "frankfurter"
        val REFRESH_TIME: LocalTime = LocalTime.of(7, 0)
    }
}

internal interface ExchangeRateCache {
    fun load(): ExchangeRateSnapshot?
    fun save(snapshot: ExchangeRateSnapshot): Boolean
}

private class SharedPreferencesExchangeRateCache(
    context: Context,
    private val json: Json,
) : ExchangeRateCache {
    private val preferences = context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)

    override fun load(): ExchangeRateSnapshot? = preferences.getString(SNAPSHOT_KEY, null)
        ?.let { encoded -> runCatching { json.decodeFromString<ExchangeRateSnapshot>(encoded) }.getOrNull() }

    override fun save(snapshot: ExchangeRateSnapshot): Boolean = preferences.edit()
        .putString(SNAPSHOT_KEY, json.encodeToString(snapshot))
        .commit()

    private companion object {
        const val PREFERENCES_NAME = "mistia.exchange-rates"
        const val SNAPSHOT_KEY = "latest-jpy-vnd"
    }
}
