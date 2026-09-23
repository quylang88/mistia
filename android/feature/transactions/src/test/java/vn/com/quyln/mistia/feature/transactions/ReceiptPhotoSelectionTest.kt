package vn.com.quyln.mistia.feature.transactions

import java.util.concurrent.CancellationException
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import vn.com.quyln.mistia.core.model.PreparedReceiptImage
import vn.com.quyln.mistia.core.model.ReceiptImagePreparationException
import vn.com.quyln.mistia.core.model.ReceiptImagePreparationFailure

class ReceiptPhotoSelectionTest {
    @Test
    fun `picker mode follows remaining capacity`() {
        assertEquals(ReceiptPhotoPickerMode.None, receiptPhotoPickerMode(existingImageCount = 5))
        assertEquals(ReceiptPhotoPickerMode.Single, receiptPhotoPickerMode(existingImageCount = 4))
        assertEquals(
            ReceiptPhotoPickerMode.Multiple(maxItems = 3),
            receiptPhotoPickerMode(existingImageCount = 2),
        )
        assertEquals(
            ReceiptPhotoPickerMode.Multiple(maxItems = ReceiptPhotoPickerLimits.MAX_IMAGES),
            receiptPhotoPickerMode(existingImageCount = -2),
        )
    }

    @Test
    fun `prepares only remaining slots in picker order`() = runBlocking {
        val visited = mutableListOf<Int>()

        val result = prepareReceiptPhotoSelections(
            sources = listOf(7, 3, 9, 4),
            availableSlots = 3,
        ) { source ->
            visited += source
            prepared(source)
        }

        assertEquals(listOf(7, 3, 9), visited)
        assertEquals(listOf(7, 3, 9), result.images.map { it.imageData.single().toInt() })
        assertEquals(1, result.rejectedCount)
        assertTrue(result.failures.isEmpty())
    }

    @Test
    fun `continues after typed and provider failures`() = runBlocking {
        val result = prepareReceiptPhotoSelections(
            sources = listOf("bad-size", "good", "provider-failure"),
            availableSlots = ReceiptPhotoPickerLimits.MAX_IMAGES,
        ) { source ->
            when (source) {
                "bad-size" -> throw ReceiptImagePreparationException(
                    ReceiptImagePreparationFailure.TOO_LARGE,
                )
                "provider-failure" -> error("provider disappeared")
                else -> prepared(5)
            }
        }

        assertEquals(listOf(5), result.images.map { it.imageData.single().toInt() })
        assertEquals(
            listOf(
                ReceiptPhotoSelectionFailure(0, ReceiptImagePreparationFailure.TOO_LARGE),
                ReceiptPhotoSelectionFailure(2, ReceiptImagePreparationFailure.DECODE_FAILED),
            ),
            result.failures,
        )
        assertEquals(0, result.rejectedCount)
    }

    @Test
    fun `zero remaining slots rejects all sources without decoding`() = runBlocking {
        var prepareCalls = 0

        val result = prepareReceiptPhotoSelections(
            sources = listOf("first", "second"),
            availableSlots = 0,
        ) {
            prepareCalls += 1
            prepared(1)
        }

        assertEquals(0, prepareCalls)
        assertTrue(result.images.isEmpty())
        assertTrue(result.failures.isEmpty())
        assertEquals(2, result.rejectedCount)
    }

    @Test
    fun `cancellation stops selection processing and propagates`() {
        val visited = mutableListOf<Int>()

        val failure = runCatching {
            runBlocking {
                prepareReceiptPhotoSelections(
                    sources = listOf(1, 2, 3),
                    availableSlots = ReceiptPhotoPickerLimits.MAX_IMAGES,
                ) { source ->
                    visited += source
                    if (source == 2) throw CancellationException("cancelled")
                    prepared(source)
                }
            }
        }.exceptionOrNull()

        assertTrue(failure is CancellationException)
        assertEquals(listOf(1, 2), visited)
    }

    private fun prepared(value: Int) = PreparedReceiptImage(
        imageData = byteArrayOf(value.toByte()),
        thumbnailData = byteArrayOf((value + 10).toByte()),
        mimeType = "image/jpeg",
        width = 100,
        height = 200,
    )
}
