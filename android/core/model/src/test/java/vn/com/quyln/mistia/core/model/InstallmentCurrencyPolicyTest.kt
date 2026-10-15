package vn.com.quyln.mistia.core.model

import org.junit.Assert.*
import org.junit.Test

class InstallmentCurrencyPolicyTest {
    @Test fun `settlement requires matching valid currency instead of reinterpreting raw minor amounts`() {
        val vectors = listOf(Triple("JPY", "JPY", true), Triple("VND", "VND", true), Triple("USD", "usd", true), Triple(" jpy ", "JPY", true),
            Triple("VND", "JPY", false), Triple("USD", "JPY", false), Triple("JPY", "VND", false), Triple("", "", false),
            Triple(" ", "JPY", false), Triple("JPY", "", false), Triple("US", "US", false), Triple("JP¥", "JP¥", false), Triple("123", "123", false), Triple("JPY1", "JPY1", false))
        for ((plan, wallet, expected) in vectors) assertEquals("$plan/$wallet", expected, installmentPaymentCurrenciesMatch(plan, wallet))
    }
}
