package vn.com.quyln.mistia.core.network

import java.time.OffsetDateTime
import java.time.ZoneId
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import vn.com.quyln.mistia.core.model.ExchangeRateSnapshot

class FrankfurterExchangeRateRepositoryTest {
    private lateinit var server: MockWebServer
    private lateinit var cache: InMemoryExchangeRateCache
    private lateinit var repository: FrankfurterExchangeRateRepository

    @Before
    fun setUp() {
        server = MockWebServer().apply { start() }
        cache = InMemoryExchangeRateCache()
        repository = FrankfurterExchangeRateRepository(
            client = OkHttpClient(),
            json = Json { ignoreUnknownKeys = true },
            cache = cache,
            endpointBaseUrl = server.url("/").toString().removeSuffix("/"),
            zoneId = ZoneId.of("Asia/Tokyo"),
        )
    }

    @After
    fun tearDown() = server.shutdown()

    @Test
    fun `refresh requests exact pair and atomically replaces validated cache`() = runTest {
        server.enqueue(MockResponse().setBody(
            """{"date":"2026-09-22","base":"JPY","quote":"VND","rate":165.5}"""
        ))

        val result = repository.refreshIfStale(epochMillis("2026-09-23T08:00:00+09:00"))

        assertTrue(result.isSuccess)
        val request = server.takeRequest(1, TimeUnit.SECONDS)
        assertNotNull(request)
        assertEquals("GET", request!!.method)
        assertEquals("/v2/rate/JPY/VND", request.requestUrl?.encodedPath)
        val expected = ExchangeRateSnapshot(
            baseCurrencyCode = "JPY",
            quoteCurrencyCode = "VND",
            rateDecimalString = "165.5",
            provider = "frankfurter",
            fetchedAtEpochMillis = epochMillis("2026-09-23T08:00:00+09:00"),
            rateDate = "2026-09-22",
        )
        assertEquals(listOf(expected), repository.rates.value)
        assertEquals(expected, cache.snapshot)
        assertEquals(1, cache.saveCount)
    }

    @Test
    fun `malformed response fails without erasing last good cache`() = runTest {
        val cached = cachedRate("2026-09-22T08:00:00+09:00")
        cache.snapshot = cached
        repository = newRepository()
        server.enqueue(MockResponse().setBody(
            """{"date":"2026-09-23","base":"JPY","quote":"VND","rate":0}"""
        ))

        val result = repository.refreshIfStale(epochMillis("2026-09-23T08:00:00+09:00"))

        assertTrue(result.isFailure)
        assertEquals(listOf(cached), repository.rates.value)
        assertEquals(cached, cache.snapshot)
        assertEquals(0, cache.saveCount)
    }

    @Test
    fun `refresh is skipped before seven and after success on the same local day`() = runTest {
        val beforeSeven = repository.refreshIfStale(epochMillis("2026-09-23T06:59:59+09:00"))
        assertTrue(beforeSeven.isSuccess)
        assertEquals(0, server.requestCount)

        server.enqueue(MockResponse().setBody(
            """{"date":"2026-09-22","base":"JPY","quote":"VND","rate":165.5}"""
        ))
        assertTrue(repository.refreshIfStale(epochMillis("2026-09-23T07:00:00+09:00")).isSuccess)
        assertTrue(repository.refreshIfStale(epochMillis("2026-09-23T18:00:00+09:00")).isSuccess)
        assertEquals(1, server.requestCount)
    }

    @Test
    fun `cached rate refreshes once on the next local day after seven`() = runTest {
        cache.snapshot = cachedRate("2026-09-22T08:00:00+09:00")
        repository = newRepository()
        server.enqueue(MockResponse().setBody(
            """{"date":"2026-09-22","base":"JPY","quote":"VND","rate":166.25}"""
        ))

        val result = repository.refreshIfStale(epochMillis("2026-09-23T07:00:00+09:00"))

        assertTrue(result.isSuccess)
        assertEquals(1, server.requestCount)
        assertEquals("166.25", repository.rates.value.single().rateDecimalString)
    }

    @Test
    fun `cache write failure keeps prior in-memory snapshot`() = runTest {
        val cached = cachedRate("2026-09-22T08:00:00+09:00")
        cache.snapshot = cached
        cache.saveSucceeds = false
        repository = newRepository()
        server.enqueue(MockResponse().setBody(
            """{"date":"2026-09-23","base":"JPY","quote":"VND","rate":166.25}"""
        ))

        val result = repository.refreshIfStale(epochMillis("2026-09-23T08:00:00+09:00"))

        assertFalse(result.isSuccess)
        assertEquals(listOf(cached), repository.rates.value)
        assertEquals(cached, cache.snapshot)
    }

    @Test
    fun `cache commit runs off the caller thread`() = runTest {
        server.enqueue(MockResponse().setBody(
            """{"date":"2026-09-22","base":"JPY","quote":"VND","rate":165.5}"""
        ))
        val callerThread = Thread.currentThread().name

        assertTrue(repository.refreshIfStale(epochMillis("2026-09-23T08:00:00+09:00")).isSuccess)

        assertNotEquals(callerThread, cache.saveThreadName)
    }

    @Test
    fun `refresh propagates coroutine cancellation`() = runTest {
        val cancellingClient = OkHttpClient.Builder().addInterceptor {
            throw CancellationException("cancelled")
        }.build()
        repository = FrankfurterExchangeRateRepository(
            client = cancellingClient,
            json = Json { ignoreUnknownKeys = true },
            cache = cache,
            endpointBaseUrl = server.url("/").toString().removeSuffix("/"),
            zoneId = ZoneId.of("Asia/Tokyo"),
        )

        var cancellation: CancellationException? = null
        try {
            repository.refreshIfStale(epochMillis("2026-09-23T08:00:00+09:00"))
        } catch (error: CancellationException) {
            cancellation = error
        }

        assertEquals("cancelled", cancellation?.message)
    }

    private fun newRepository() = FrankfurterExchangeRateRepository(
        client = OkHttpClient(),
        json = Json { ignoreUnknownKeys = true },
        cache = cache,
        endpointBaseUrl = server.url("/").toString().removeSuffix("/"),
        zoneId = ZoneId.of("Asia/Tokyo"),
    )

    private fun cachedRate(fetchedAt: String) = ExchangeRateSnapshot(
        baseCurrencyCode = "JPY",
        quoteCurrencyCode = "VND",
        rateDecimalString = "165.5",
        provider = "frankfurter",
        fetchedAtEpochMillis = epochMillis(fetchedAt),
        rateDate = "2026-09-21",
    )

    private fun epochMillis(value: String): Long = OffsetDateTime.parse(value).toInstant().toEpochMilli()

    private class InMemoryExchangeRateCache : ExchangeRateCache {
        var snapshot: ExchangeRateSnapshot? = null
        var saveCount = 0
        var saveSucceeds = true
        var saveThreadName: String? = null

        override fun load(): ExchangeRateSnapshot? = snapshot

        override fun save(snapshot: ExchangeRateSnapshot): Boolean {
            saveCount += 1
            saveThreadName = Thread.currentThread().name
            if (!saveSucceeds) return false
            this.snapshot = snapshot
            return true
        }
    }
}
