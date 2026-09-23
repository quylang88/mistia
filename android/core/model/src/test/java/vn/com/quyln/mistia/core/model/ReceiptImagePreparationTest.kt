package vn.com.quyln.mistia.core.model

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ReceiptImagePreparationTest {
    @Test
    fun `scales analysis image and creates fixed thumbnail`() = runBlocking {
        val codec = FakeCodec { frame, _ -> if (frame.label == "thumbnail") 240 else 1_000 }
        val result = ReceiptImagePreparer(codec).prepare(byteArrayOf(1, 2, 3))

        assertEquals("image/jpeg", result.mimeType)
        assertArrayEquals(ByteArray(1_000), result.imageData)
        assertArrayEquals(ByteArray(240), result.thumbnailData)
        assertEquals(3_000, result.width)
        assertEquals(1_500, result.height)
        assertEquals(listOf(3_000, 240), codec.scaleRequests)
        assertEquals(listOf(0.90, 0.68), codec.qualities.map(::roundedQuality))
    }

    @Test
    fun `accepts exact byte ceiling without reducing quality`() = runBlocking {
        val codec = FakeCodec { frame, _ ->
            if (frame.label == "thumbnail") 10 else ReceiptImagePreparer.MAX_ANALYSIS_BYTES
        }

        val result = ReceiptImagePreparer(codec).prepare(byteArrayOf(1))

        assertEquals(ReceiptImagePreparer.MAX_ANALYSIS_BYTES, result.imageData.size)
        assertEquals(listOf(0.90, 0.68), codec.qualities.map(::roundedQuality))
    }

    @Test
    fun `accepts readable source smaller than resize floor`() = runBlocking {
        val codec = FakeCodec(sourceWidth = 600, sourceHeight = 800)

        val result = ReceiptImagePreparer(codec).prepare(byteArrayOf(1))

        assertEquals(600, result.width)
        assertEquals(800, result.height)
        assertEquals(listOf(3_000, 240), codec.scaleRequests)
    }

    @Test
    fun `reduces JPEG quality before dimensions`() = runBlocking {
        val codec = FakeCodec { frame, quality ->
            when {
                frame.label == "thumbnail" -> 10
                quality >= 0.82 -> ReceiptImagePreparer.MAX_ANALYSIS_BYTES + 1
                else -> 2_000
            }
        }

        val result = ReceiptImagePreparer(codec).prepare(byteArrayOf(1))

        assertEquals(2_000, result.imageData.size)
        assertEquals(listOf(0.90, 0.82, 0.74, 0.68), codec.qualities.map(::roundedQuality))
        assertEquals(listOf(3_000, 240), codec.scaleRequests)
    }

    @Test
    fun `reduces dimensions after exhausting quality range`() = runBlocking {
        val codec = FakeCodec { frame, _ ->
            when {
                frame.label == "thumbnail" -> 10
                frame.width <= 2_580 -> 2_000
                else -> ReceiptImagePreparer.MAX_ANALYSIS_BYTES + 1
            }
        }

        val result = ReceiptImagePreparer(codec).prepare(byteArrayOf(1))

        assertEquals(2_580, result.width)
        assertEquals(1_290, result.height)
        assertEquals(listOf(3_000, 2_580, 240), codec.scaleRequests)
        assertTrue(codec.qualities.map(::roundedQuality).containsAll(listOf(0.90, 0.42, 0.68)))
    }

    @Test
    fun `rejects image that cannot fit before minimum OCR dimension`() = runBlocking {
        val codec = FakeCodec { frame, _ ->
            if (frame.label == "thumbnail") 10 else ReceiptImagePreparer.MAX_ANALYSIS_BYTES + 1
        }

        val failure = runCatching {
            ReceiptImagePreparer(codec).prepare(byteArrayOf(1))
        }.exceptionOrNull() as ReceiptImagePreparationException

        assertEquals(ReceiptImagePreparationFailure.TOO_LARGE, failure.reason)
        assertTrue(codec.scaleRequests.filter { it != 240 }.all { it >= ReceiptImagePreparer.MIN_ANALYSIS_DIMENSION })
    }

    @Test
    fun `maps decode scale and encode failures`() = runBlocking {
        val decodeFailure = runCatching {
            ReceiptImagePreparer(FakeCodec(decodeSucceeds = false)).prepare(byteArrayOf(1))
        }.exceptionOrNull() as ReceiptImagePreparationException
        assertEquals(ReceiptImagePreparationFailure.DECODE_FAILED, decodeFailure.reason)

        val scaleFailure = runCatching {
            ReceiptImagePreparer(FakeCodec(scaleSucceeds = false)).prepare(byteArrayOf(1))
        }.exceptionOrNull() as ReceiptImagePreparationException
        assertEquals(ReceiptImagePreparationFailure.SCALE_FAILED, scaleFailure.reason)

        val encodeFailure = runCatching {
            ReceiptImagePreparer(FakeCodec { _, _ -> null }).prepare(byteArrayOf(1))
        }.exceptionOrNull() as ReceiptImagePreparationException
        assertEquals(ReceiptImagePreparationFailure.ENCODE_FAILED, encodeFailure.reason)
    }

    @Test
    fun `cancellation propagates before codec work`() = runBlocking {
        val cancelled = Job().apply { cancel() }
        val failure = runCatching {
            withContext(cancelled) {
                ReceiptImagePreparer(FakeCodec()).prepare(byteArrayOf(1))
            }
        }.exceptionOrNull()

        assertTrue(failure is CancellationException)
    }

    @Test
    fun `releases decoded and rendered frames after success`() = runBlocking {
        val codec = FakeCodec()

        ReceiptImagePreparer(codec).prepare(byteArrayOf(1))

        assertEquals(
            setOf("source", "analysis", "thumbnail"),
            codec.releasedFrames.map(FakeFrame::label).toSet(),
        )
    }

    private fun roundedQuality(value: Double): Double = "%.2f".format(java.util.Locale.ROOT, value).toDouble()

    private data class FakeFrame(
        val width: Int,
        val height: Int,
        val label: String,
    )

    private class FakeCodec(
        private val decodeSucceeds: Boolean = true,
        private val scaleSucceeds: Boolean = true,
        private val sourceWidth: Int = 4_000,
        private val sourceHeight: Int = 2_000,
        private val encodedSize: (FakeFrame, Double) -> Int? = { frame, _ ->
            if (frame.label == "thumbnail") 240 else 1_000
        },
    ) : ReceiptImageCodec<FakeFrame> {
        val scaleRequests = mutableListOf<Int>()
        val qualities = mutableListOf<Double>()
        val releasedFrames = mutableListOf<FakeFrame>()

        override fun decode(data: ByteArray): FakeFrame? =
            if (decodeSucceeds) FakeFrame(sourceWidth, sourceHeight, "source") else null

        override fun dimensions(frame: FakeFrame): ReceiptImageDimensions =
            ReceiptImageDimensions(frame.width, frame.height)

        override fun renderOpaqueScaled(frame: FakeFrame, maxDimension: Int): FakeFrame? {
            scaleRequests += maxDimension
            if (!scaleSucceeds) return null
            val largest = maxOf(frame.width, frame.height)
            val scale = minOf(1.0, maxDimension.toDouble() / largest.toDouble())
            return FakeFrame(
                width = (frame.width * scale).toInt(),
                height = (frame.height * scale).toInt(),
                label = if (maxDimension == 240) "thumbnail" else "analysis",
            )
        }

        override fun encodeJpeg(frame: FakeFrame, quality: Double): ByteArray? {
            qualities += quality
            return encodedSize(frame, quality)?.let(::ByteArray)
        }

        override fun release(frame: FakeFrame) {
            releasedFrames += frame
        }
    }
}
