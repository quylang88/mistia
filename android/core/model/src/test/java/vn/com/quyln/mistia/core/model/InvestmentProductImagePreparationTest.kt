package vn.com.quyln.mistia.core.model

import java.nio.ByteBuffer
import kotlin.math.roundToInt
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import org.junit.Assert.*
import org.junit.Test

class InvestmentProductImagePreparationTest {
    @Test fun `normalizes source to opaque 1600 JPEG with source derived 240 thumbnail`() = runBlocking {
        val codec = RasterCodec()
        val result = InvestmentProductImagePreparer(codec).prepare(source(4000, 2000, 0x40224466))
        assertEquals("image/jpeg", result.mimeType)
        assertEquals(1600, result.width)
        assertEquals(800, result.height)
        assertArrayEquals(encodedHeader(1600, 800, 0xffc8d0d9.toInt(), 90), result.imageData.take(16).toByteArray())
        assertArrayEquals(encodedHeader(240, 120, 0xffc8d0d9.toInt(), 78), result.thumbnailData.take(16).toByteArray())
        assertEquals(listOf(1600, 240), codec.scaleLimits)
        assertEquals(listOf("source", "source"), codec.scaleSources)
        assertEquals(listOf("thumbnail", "full", "source"), codec.released.map { it.label })
    }

    @Test fun `small portrait is not enlarged`() = runBlocking {
        val result = InvestmentProductImagePreparer(RasterCodec()).prepare(source(300, 600))
        assertEquals(300, result.width)
        assertEquals(600, result.height)
        assertEquals(120, ByteBuffer.wrap(result.thumbnailData).int)
        assertEquals(240, ByteBuffer.wrap(result.thumbnailData).getInt(4))
    }

    @Test fun `accepts exactly four million bytes at initial quality`() = runBlocking {
        val codec = RasterCodec(fullSize = { 4_000_000 })
        val result = InvestmentProductImagePreparer(codec).prepare(source(2000, 1000))
        assertEquals(4_000_000, result.imageData.size)
        assertEquals(listOf(90, 78), codec.qualities)
    }

    @Test fun `quality retry reaches twenty percent and never shrinks dimensions`() = runBlocking {
        val codec = RasterCodec(fullSize = { if (it > 20) 4_000_001 else 42 })
        val result = InvestmentProductImagePreparer(codec).prepare(source(2000, 1000))
        assertEquals(42, result.imageData.size)
        assertEquals(1600, result.width)
        assertEquals(listOf(90, 80, 70, 60, 50, 40, 30, 20, 78), codec.qualities)
        assertEquals(listOf(1600, 240), codec.scaleLimits)
    }

    @Test fun `oversize at twenty fails without OCR dimension fallback or thumbnail`() = runBlocking {
        val codec = RasterCodec(fullSize = { 4_000_001 })
        assertFailure(InvestmentProductImagePreparationFailure.TOO_LARGE) {
            InvestmentProductImagePreparer(codec).prepare(source(4000, 2000))
        }
        assertEquals(listOf(90, 80, 70, 60, 50, 40, 30, 20), codec.qualities)
        assertEquals(listOf(1600), codec.scaleLimits)
        assertEquals(listOf("full", "source"), codec.released.map { it.label })
    }

    @Test fun `malformed source and invalid source dimensions are rejected`() = runBlocking {
        assertFailure(InvestmentProductImagePreparationFailure.DECODE_FAILED) {
            InvestmentProductImagePreparer(RasterCodec()).prepare(byteArrayOf(1))
        }
        val codec = RasterCodec()
        assertFailure(InvestmentProductImagePreparationFailure.INVALID_DIMENSIONS) {
            InvestmentProductImagePreparer(codec).prepare(source(0, 10))
        }
        assertEquals(listOf("source"), codec.released.map { it.label })
    }

    @Test fun `rejects rendered dimensions beyond requested limit`() = runBlocking {
        val codec = RasterCodec(brokenScale = true)
        assertFailure(InvestmentProductImagePreparationFailure.INVALID_DIMENSIONS) {
            InvestmentProductImagePreparer(codec).prepare(source(4000, 2000))
        }
        assertEquals(2, codec.released.size)
    }

    @Test fun `rejects full render failure while releasing source`() = runBlocking {
        val codec = RasterCodec(failScaleAt = 1600)
        assertFailure(InvestmentProductImagePreparationFailure.SCALE_FAILED) {
            InvestmentProductImagePreparer(codec).prepare(source(2000, 1000))
        }
        assertEquals(listOf("source"), codec.released.map { it.label })
    }

    @Test fun `rejects thumbnail rendering or JPEG failure and releases all acquired frames`() = runBlocking {
        for (failure in listOf("scale", "encode")) {
            val codec = RasterCodec(failScaleAt = if (failure == "scale") 240 else null, failThumbnailEncode = failure == "encode")
            assertFailure(if (failure == "scale") InvestmentProductImagePreparationFailure.SCALE_FAILED else InvestmentProductImagePreparationFailure.ENCODE_FAILED) {
                InvestmentProductImagePreparer(codec).prepare(source(2000, 1000))
            }
            assertEquals(if (failure == "scale") 2 else 3, codec.released.size)
        }
    }

    @Test fun `null full encoding fails and releases resources`() = runBlocking {
        val codec = RasterCodec(fullSize = { null })
        assertFailure(InvestmentProductImagePreparationFailure.ENCODE_FAILED) {
            InvestmentProductImagePreparer(codec).prepare(source(2000, 1000))
        }
        assertEquals(listOf("full", "source"), codec.released.map { it.label })
    }

    @Test fun `aliased frames are released once by identity`() = runBlocking {
        val codec = RasterCodec(aliasFrames = true)
        val result = InvestmentProductImagePreparer(codec).prepare(source(120, 60))
        assertEquals(120, result.width)
        assertEquals(1, codec.released.size)
    }

    @Test fun `cancellation during encoding stops thumbnail and releases owned frames`() = runBlocking {
        val job = Job()
        val codec = RasterCodec(afterEncode = { job.cancel() })
        val failure = runCatching {
            withContext(job) { InvestmentProductImagePreparer(codec).prepare(source(2000, 1000)) }
        }.exceptionOrNull()
        assertTrue(failure is CancellationException)
        assertEquals(listOf(1600), codec.scaleLimits)
        assertEquals(listOf("full", "source"), codec.released.map { it.label })
    }

    @Test fun `cancellation before preparation performs no decode`() = runBlocking {
        val codec = RasterCodec()
        val failure = runCatching {
            withContext(Job().apply { cancel() }) { InvestmentProductImagePreparer(codec).prepare(source(100, 100)) }
        }.exceptionOrNull()
        assertTrue(failure is CancellationException)
        assertEquals(0, codec.decodes)
    }

    @Test fun `codec exception propagates and cleanup continues if one release throws`() = runBlocking {
        val marker = IllegalStateException("encoder failed")
        val codec = RasterCodec(encodeException = marker, releaseThrows = true)
        val failure = runCatching { InvestmentProductImagePreparer(codec).prepare(source(2000, 1000)) }.exceptionOrNull()
        assertSame(marker, failure)
        assertEquals(listOf("full", "source"), codec.released.map { it.label })
    }

    private suspend fun assertFailure(reason: InvestmentProductImagePreparationFailure, operation: suspend () -> Unit) {
        val failure = runCatching { operation() }.exceptionOrNull()
        assertTrue("Expected $reason but was $failure", failure is InvestmentProductImagePreparationException)
        assertEquals(reason, (failure as InvestmentProductImagePreparationException).reason)
    }

    // This codec models raster dimensions, alpha compositing, and JPEG budget at the platform port.
    // Output headers let assertions inspect the preparer's actual selected frame/quality.
    private data class Raster(val width: Int, val height: Int, val argb: Int, val label: String)
    private class RasterCodec(
        val fullSize: (Int) -> Int? = { 32 },
        val failScaleAt: Int? = null,
        val brokenScale: Boolean = false,
        val failThumbnailEncode: Boolean = false,
        val aliasFrames: Boolean = false,
        val afterEncode: () -> Unit = {},
        val encodeException: Throwable? = null,
        val releaseThrows: Boolean = false,
    ) : ReceiptImageCodec<Raster> {
        val scaleLimits = mutableListOf<Int>()
        val scaleSources = mutableListOf<String>()
        val qualities = mutableListOf<Int>()
        val released = mutableListOf<Raster>()
        var decodes = 0
        override fun decode(data: ByteArray): Raster? {
            decodes++
            if (data.size != 12) return null
            val input = ByteBuffer.wrap(data)
            return Raster(input.int, input.int, input.int, "source")
        }
        override fun dimensions(frame: Raster) = ReceiptImageDimensions(frame.width, frame.height)
        override fun renderOpaqueScaled(frame: Raster, maxDimension: Int): Raster? {
            scaleLimits += maxDimension
            scaleSources += frame.label
            if (failScaleAt == maxDimension) return null
            if (aliasFrames) return frame
            val scale = if (brokenScale) 1.0 else minOf(1.0, maxDimension.toDouble() / maxOf(frame.width, frame.height))
            val alpha = (frame.argb ushr 24) / 255.0
            fun channel(shift: Int) = (((frame.argb ushr shift and 255) * alpha) + 255 * (1 - alpha)).roundToInt()
            val opaque = (255 shl 24) or (channel(16) shl 16) or (channel(8) shl 8) or channel(0)
            return Raster((frame.width * scale).roundToInt(), (frame.height * scale).roundToInt(), opaque, if (maxDimension == 240) "thumbnail" else "full")
        }
        override fun encodeJpeg(frame: Raster, quality: Double): ByteArray? {
            encodeException?.let { throw it }
            val percent = (quality * 100).roundToInt()
            qualities += percent
            val size = if (frame.label == "thumbnail") { if (failThumbnailEncode) null else 24 } else fullSize(percent)
            val output = size?.let { encodedHeader(frame.width, frame.height, frame.argb, percent).copyOf(it) }
            afterEncode()
            return output
        }
        override fun release(frame: Raster) {
            check(released.none { it === frame }) { "Frame released twice" }
            released += frame
            if (releaseThrows) error("Release failed")
        }
    }

    companion object {
        private fun source(width: Int, height: Int, argb: Int = 0xff224466.toInt()) =
            ByteBuffer.allocate(12).putInt(width).putInt(height).putInt(argb).array()
        private fun encodedHeader(width: Int, height: Int, argb: Int, quality: Int) =
            ByteBuffer.allocate(16).putInt(width).putInt(height).putInt(argb).putInt(quality).array()
    }
}
