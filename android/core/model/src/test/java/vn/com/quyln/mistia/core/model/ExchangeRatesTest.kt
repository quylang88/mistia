package vn.com.quyln.mistia.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ExchangeRatesTest {
    @Test
    fun `direct rate multiplies minor units and preserves snapshot metadata`() {
        val result = resolveExchangeRate(100, "jpy", "vnd", listOf(rate("165.5")))

        assertEquals(16_550L, result?.destinationAmountMinor)
        assertEquals("165.5", result?.rateDecimalString)
        assertEquals("frankfurter", result?.provider)
        assertEquals("2026-09-23", result?.rateDate)
    }

    @Test
    fun `inverse rate divides minor units`() {
        val result = resolveExchangeRate(16_550, "VND", "JPY", listOf(rate("165.5")))

        assertEquals(100L, result?.destinationAmountMinor)
    }

    @Test
    fun `conversion rounds half up to an integer minor unit`() {
        val result = resolveExchangeRate(1, "JPY", "VND", listOf(rate("165.5")))

        assertEquals(166L, result?.destinationAmountMinor)
    }

    @Test
    fun `zero malformed and unsupported rates do not resolve`() {
        assertNull(resolveExchangeRate(100, "JPY", "VND", listOf(rate("0"))))
        assertNull(resolveExchangeRate(100, "JPY", "VND", listOf(rate("not-a-rate"))))
        assertNull(resolveExchangeRate(100, "USD", "JPY", listOf(rate("165"))))
        assertNull(resolveExchangeRate(100, "JPY", "JPY", listOf(rate("165"))))
    }

    @Test
    fun `overflow does not clamp or create a result`() {
        assertNull(resolveExchangeRate(Long.MAX_VALUE, "JPY", "VND", listOf(rate("2"))))
    }

    private fun rate(value: String) = ExchangeRateSnapshot(
        baseCurrencyCode = "JPY",
        quoteCurrencyCode = "VND",
        rateDecimalString = value,
        provider = "frankfurter",
        fetchedAtEpochMillis = 1_795_000_000_000,
        rateDate = "2026-09-23",
    )
}
