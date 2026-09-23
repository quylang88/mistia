package vn.com.quyln.mistia.feature.transactions

import java.io.ByteArrayInputStream
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test
import vn.com.quyln.mistia.core.model.ReceiptImagePreparationException
import vn.com.quyln.mistia.core.model.ReceiptImagePreparationFailure

class BoundedReceiptInputTest {
    @Test
    fun `accepts source at exact byte limit`() {
        val source = ByteArray(8) { it.toByte() }

        val result = readBoundedReceiptBytes(ByteArrayInputStream(source), maxBytes = 8)

        assertArrayEquals(source, result)
    }

    @Test
    fun `rejects source above byte limit`() {
        val failure = runCatching {
            readBoundedReceiptBytes(ByteArrayInputStream(ByteArray(9)), maxBytes = 8)
        }.exceptionOrNull() as ReceiptImagePreparationException

        assertEquals(ReceiptImagePreparationFailure.SOURCE_TOO_LARGE, failure.reason)
    }

    @Test
    fun `rejects empty source`() {
        val failure = runCatching {
            readBoundedReceiptBytes(ByteArrayInputStream(byteArrayOf()), maxBytes = 8)
        }.exceptionOrNull() as ReceiptImagePreparationException

        assertEquals(ReceiptImagePreparationFailure.DECODE_FAILED, failure.reason)
    }

    @Test
    fun `bitmap sampling bounds decoded longest side`() {
        assertEquals(1, calculateBitmapSampleSize(4_000, 2_000, maxDimension = 6_000))
        assertEquals(2, calculateBitmapSampleSize(12_000, 8_000, maxDimension = 6_000))
        assertEquals(8, calculateBitmapSampleSize(24_001, 12_000, maxDimension = 6_000))
    }
}
