package vn.com.quyln.mistia.feature.transactions

import java.util.concurrent.CancellationException
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import vn.com.quyln.mistia.core.model.PreparedReceiptImage
import vn.com.quyln.mistia.core.model.ReceiptImagePreparationException
import vn.com.quyln.mistia.core.model.ReceiptImagePreparationFailure

class ReceiptCameraCaptureTest {
    @get:Rule
    val temporaryFolder = TemporaryFolder()

    @Test
    fun `camera entry requests permission before opening available camera`() {
        assertEquals(
            ReceiptCameraEntryAction.RequestPermission,
            receiptCameraEntryAction(hasPermission = false, cameraAvailable = true),
        )
        assertEquals(
            ReceiptCameraEntryAction.OpenCamera,
            receiptCameraEntryAction(hasPermission = true, cameraAvailable = true),
        )
        assertEquals(
            ReceiptCameraEntryAction.Unavailable,
            receiptCameraEntryAction(hasPermission = true, cameraAvailable = false),
        )
        assertEquals(
            ReceiptCameraEntryAction.Unavailable,
            receiptCameraEntryAction(hasPermission = false, cameraAvailable = false),
        )
    }

    @Test
    fun `capture files are unique jpeg files in isolated cache directory`() {
        val cacheDirectory = temporaryFolder.newFolder("cache")

        val first = createReceiptCaptureFile(cacheDirectory)
        val second = createReceiptCaptureFile(cacheDirectory)

        assertEquals("receipt-captures", first.parentFile?.name)
        assertTrue(first.name.startsWith("receipt-"))
        assertTrue(first.name.endsWith(".jpg"))
        assertTrue(first.exists())
        assertTrue(second.exists())
        assertNotEquals(first.absolutePath, second.absolutePath)
    }

    @Test
    fun `successful preparation deletes camera file`() = runBlocking {
        val capture = createReceiptCaptureFile(temporaryFolder.newFolder("success"))
        capture.writeBytes(byteArrayOf(1, 2, 3))

        val result = prepareReceiptCameraCapture(capture) { prepared(7) }

        assertEquals(listOf(7), result.images.map { it.imageData.single().toInt() })
        assertTrue(result.failures.isEmpty())
        assertFalse(capture.exists())
    }

    @Test
    fun `typed preparation failure deletes camera file`() = runBlocking {
        val capture = createReceiptCaptureFile(temporaryFolder.newFolder("failure"))

        val result = prepareReceiptCameraCapture(capture) {
            throw ReceiptImagePreparationException(ReceiptImagePreparationFailure.TOO_LARGE)
        }

        assertTrue(result.images.isEmpty())
        assertEquals(
            listOf(ReceiptPhotoSelectionFailure(0, ReceiptImagePreparationFailure.TOO_LARGE)),
            result.failures,
        )
        assertFalse(capture.exists())
    }

    @Test
    fun `cancellation deletes camera file and propagates`() {
        val capture = createReceiptCaptureFile(temporaryFolder.newFolder("cancelled"))

        val failure = runCatching {
            runBlocking {
                prepareReceiptCameraCapture(capture) {
                    throw CancellationException("cancelled")
                }
            }
        }.exceptionOrNull()

        assertTrue(failure is CancellationException)
        assertFalse(capture.exists())
    }

    private fun prepared(value: Int) = PreparedReceiptImage(
        imageData = byteArrayOf(value.toByte()),
        thumbnailData = byteArrayOf((value + 10).toByte()),
        mimeType = "image/jpeg",
        width = 100,
        height = 200,
    )
}
