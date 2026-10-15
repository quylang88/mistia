package vn.com.quyln.mistia.core.designsystem

import java.util.Locale
import org.junit.Assert.*
import org.junit.Test

class CurrencyFormattingTest {
    private fun <T> locale(value: Locale, block: () -> T): T {
        val before = Locale.getDefault()
        return try { Locale.setDefault(value); block() } finally { Locale.setDefault(before) }
    }
    @Test fun `JPY and VND presentation use no fractional digits under English locale`() = locale(Locale.US) {
        assertEquals("￥600", formatMinorUnits(600, "JPY"))
        assertEquals("600 ₫", formatMinorUnits(600, "VND"))
    }
    @Test fun `currency locale and grouping are stable across app language changes like Swift`() {
        val expected = locale(Locale.US) { listOf(formatMinorUnits(123456, "JPY"), formatMinorUnits(123456789, "VND"), formatMinorUnits(1375, "USD")) }
        for (language in listOf(Locale.JAPAN, Locale.forLanguageTag("vi-VN"), Locale.GERMANY))
            assertEquals(expected, locale(language) { listOf(formatMinorUnits(123456, "JPY"), formatMinorUnits(123456789, "VND"), formatMinorUnits(1375, "USD")) })
    }
    @Test fun `ISO decimal precision is retained for existing imported USD and three digit currencies`() = locale(Locale.US) {
        assertEquals("$13.75", formatMinorUnits(1375, "USD"))
        assertTrue(formatMinorUnits(1234, "KWD").contains("1.234"))
    }
    @Test fun `zero negative and Long boundary values never round through Double`() = locale(Locale.US) {
        assertEquals("￥0", formatMinorUnits(0, "JPY")); assertEquals("-￥1,375", formatMinorUnits(-1375, "JPY"))
        assertEquals("￥9,007,199,254,740,993", formatMinorUnits(9007199254740993, "JPY"))
        assertEquals("$90,071,992,547,409.93", formatMinorUnits(9007199254740993, "USD"))
        assertEquals("-￥9,223,372,036,854,775,808", formatMinorUnits(Long.MIN_VALUE, "JPY"))
    }
    @Test fun `unsupported code keeps exact raw integer and code instead of claiming a conversion`() {
        assertEquals("9007199254740993 INVALID", formatMinorUnits(9007199254740993, "INVALID"))
    }
}
