package vn.com.quyln.mistia.feature.investment

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.media.ExifInterface
import android.net.Uri
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.model.InvestmentProductImagePreparationException
import vn.com.quyln.mistia.core.model.InvestmentProductImagePreparationFailure
import vn.com.quyln.mistia.core.model.InvestmentProductImagePreparer

@RunWith(AndroidJUnit4::class)
class AndroidInvestmentProductImagePreparationTest {
    @Test fun remoteByteInputProducesA240PixelThumbnailWithoutMutatingTheOriginalObject()=runBlocking {
        val context=ApplicationProvider.getApplicationContext<android.content.Context>()
        val bitmap=Bitmap.createBitmap(480,240,Bitmap.Config.ARGB_8888)
        bitmap.eraseColor(Color.BLUE)
        val original=bitmap.bytes(Bitmap.CompressFormat.JPEG);bitmap.recycle()
        val frozen=original.copyOf()
        val result=AndroidInvestmentProductImagePreparer(context.contentResolver).prepare(original)
        val thumb=BitmapFactory.decodeByteArray(result.thumbnailData,0,result.thumbnailData.size)!!
        try{assertEquals(240,thumb.width);assertEquals(120,thumb.height);assertNearColor(Color.BLUE,thumb.getPixel(100,50))}
        finally{thumb.recycle()}
        assertArrayEquals(frozen,original)
        val error=runCatching{AndroidInvestmentProductImagePreparer(context.contentResolver).prepare(ByteArray(24*1024*1024+1))}.exceptionOrNull()
        assertEquals(InvestmentProductImagePreparationFailure.SOURCE_TOO_LARGE,(error as? InvestmentProductImagePreparationException)?.reason)
    }

    @Test fun darkThemeTransparencyBecomesBlackInBothFullJpegAndThumbnail()=runBlocking {
        val context=ApplicationProvider.getApplicationContext<android.content.Context>()
        val bitmap=Bitmap.createBitmap(480,240,Bitmap.Config.ARGB_8888)
        bitmap.eraseColor(Color.TRANSPARENT)
        Canvas(bitmap).drawRect(240f,0f,480f,240f,Paint().apply{color=Color.RED})
        val bytes=bitmap.bytes(Bitmap.CompressFormat.PNG);bitmap.recycle()
        val result=AndroidInvestmentProductImagePreparer(context.contentResolver,backgroundColor=Color.BLACK).prepare(bytes)
        for(data in listOf(result.imageData,result.thumbnailData)) {
            val decoded=BitmapFactory.decodeByteArray(data,0,data.size)!!
            try{assertNearColor(Color.BLACK,decoded.getPixel(decoded.width/4,decoded.height/2));assertNearColor(Color.RED,decoded.getPixel(decoded.width*3/4,decoded.height/2));assertFalse(decoded.hasAlpha())}
            finally{decoded.recycle()}
        }
    }

    @Test fun transparentPngBecomesOpaqueFullJpegAndThumbnail() = runBlocking {
        val bitmap = Bitmap.createBitmap(2000, 1000, Bitmap.Config.ARGB_8888)
        bitmap.eraseColor(Color.TRANSPARENT)
        Canvas(bitmap).drawRect(1000f, 0f, 2000f, 1000f, Paint().apply { color = Color.RED })
        val source = bitmap.bytes(Bitmap.CompressFormat.PNG)
        bitmap.recycle()
        val result = InvestmentProductImagePreparer(AndroidInvestmentProductImageCodec()).prepare(source)
        assertEquals("image/jpeg", result.mimeType)
        assertEquals(1600, result.width)
        assertEquals(800, result.height)
        assertTrue(result.imageData.size <= 4_000_000)
        assertJpeg(result.imageData)
        assertJpeg(result.thumbnailData)
        val full = BitmapFactory.decodeByteArray(result.imageData, 0, result.imageData.size)!!
        val thumbnail = BitmapFactory.decodeByteArray(result.thumbnailData, 0, result.thumbnailData.size)!!
        try {
            assertEquals(1600, full.width)
            assertEquals(800, full.height)
            assertEquals(240, thumbnail.width)
            assertEquals(120, thumbnail.height)
            assertFalse(full.hasAlpha())
            assertNearColor(Color.WHITE, full.getPixel(200, 200))
            assertNearColor(Color.RED, full.getPixel(1200, 200))
            assertNearColor(Color.WHITE, thumbnail.getPixel(30, 30))
            assertNearColor(Color.RED, thumbnail.getPixel(180, 30))
        } finally {
            full.recycle()
            thumbnail.recycle()
        }
    }

    @Test fun uriInputAppliesExifRotationAndMirroringBeforeEncoding() = runBlocking {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val bitmap = Bitmap.createBitmap(400, 200, Bitmap.Config.ARGB_8888)
        bitmap.eraseColor(Color.RED)
        Canvas(bitmap).drawRect(200f, 0f, 400f, 200f, Paint().apply { color = Color.BLUE })
        val bytes = bitmap.bytes(Bitmap.CompressFormat.JPEG)
        bitmap.recycle()
        // Top-left color after each EXIF transform, independently derived from the source halves.
        val cases = listOf(
            Triple(ExifInterface.ORIENTATION_NORMAL, 400, Color.RED),
            Triple(ExifInterface.ORIENTATION_FLIP_HORIZONTAL, 400, Color.BLUE),
            Triple(ExifInterface.ORIENTATION_ROTATE_180, 400, Color.BLUE),
            Triple(ExifInterface.ORIENTATION_FLIP_VERTICAL, 400, Color.RED),
            Triple(ExifInterface.ORIENTATION_TRANSPOSE, 200, Color.RED),
            Triple(ExifInterface.ORIENTATION_ROTATE_90, 200, Color.RED),
            Triple(ExifInterface.ORIENTATION_TRANSVERSE, 200, Color.BLUE),
            Triple(ExifInterface.ORIENTATION_ROTATE_270, 200, Color.BLUE),
        )
        for ((orientation, expectedWidth, topLeftColor) in cases) {
            val file = File.createTempFile("investment-orientation-", ".jpg", context.cacheDir)
            try {
                file.writeBytes(bytes)
                ExifInterface(file.absolutePath).apply {
                    setAttribute(ExifInterface.TAG_ORIENTATION, orientation.toString())
                    saveAttributes()
                }
                val result = AndroidInvestmentProductImagePreparer(context.contentResolver).prepare(Uri.fromFile(file))
                assertEquals("orientation $orientation", expectedWidth, result.width)
                assertEquals(if (expectedWidth == 400) 200 else 400, result.height)
                val image = BitmapFactory.decodeByteArray(result.imageData, 0, result.imageData.size)!!
                try { assertNearColor(topLeftColor, image.getPixel(25, 25)) } finally { image.recycle() }
            } finally { file.delete() }
        }
    }

    @Test fun largeSourceDecodeIsBoundedButPreservesEnoughPixelsForFull1600Output() = runBlocking {
        val bitmap = Bitmap.createBitmap(6400, 100, Bitmap.Config.ARGB_8888)
        bitmap.eraseColor(Color.GREEN)
        val bytes = bitmap.bytes(Bitmap.CompressFormat.PNG)
        bitmap.recycle()
        val codec = AndroidInvestmentProductImageCodec()
        val decoded = codec.decode(bytes)!!
        assertTrue(decoded.width in 1600..3200)
        codec.release(decoded)
        assertTrue(decoded.isRecycled)
        val result = InvestmentProductImagePreparer(codec).prepare(bytes)
        assertEquals(1600, result.width)
        assertEquals(25, result.height)
    }

    @Test fun malformedSourceIsAClassifiedFailure() = runBlocking {
        val failure = runCatching {
            InvestmentProductImagePreparer(AndroidInvestmentProductImageCodec()).prepare(byteArrayOf(1, 2, 3))
        }.exceptionOrNull()
        assertTrue(failure is InvestmentProductImagePreparationException)
        assertEquals(InvestmentProductImagePreparationFailure.DECODE_FAILED, (failure as InvestmentProductImagePreparationException).reason)
    }

    @Test fun sourceReaderAcceptsBoundaryRejectsOversizeAndRejectsEmpty() = runBlocking {
        assertArrayEquals(ByteArray(16) { it.toByte() }, readBoundedInvestmentProductBytes(ByteArrayInputStream(ByteArray(16) { it.toByte() }), 16))
        val oversized = runCatching { readBoundedInvestmentProductBytes(ByteArrayInputStream(ByteArray(17)), 16) }.exceptionOrNull()
        assertTrue(oversized is InvestmentProductImagePreparationException)
        assertEquals(InvestmentProductImagePreparationFailure.SOURCE_TOO_LARGE, (oversized as InvestmentProductImagePreparationException).reason)
        val empty = runCatching { readBoundedInvestmentProductBytes(ByteArrayInputStream(byteArrayOf()), 16) }.exceptionOrNull()
        assertEquals(InvestmentProductImagePreparationFailure.DECODE_FAILED, (empty as InvestmentProductImagePreparationException).reason)
    }

    @Test fun sourceReaderChecksCancellationBetweenReads() = runBlocking {
        val job = Job()
        var reads = 0
        val input = object : ByteArrayInputStream(ByteArray(20_000)) {
            override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
                reads++
                return super.read(buffer, offset, length).also { job.cancel() }
            }
        }
        val failure = runCatching { withContext(job) { readBoundedInvestmentProductBytes(input) } }.exceptionOrNull()
        assertTrue(failure is CancellationException)
        assertEquals(1, reads)
    }

    private fun Bitmap.bytes(format: Bitmap.CompressFormat): ByteArray = ByteArrayOutputStream().use {
        check(compress(format, 100, it))
        it.toByteArray()
    }
    private fun assertJpeg(data: ByteArray) {
        assertEquals(0xff, data[0].toInt() and 255)
        assertEquals(0xd8, data[1].toInt() and 255)
    }
    private fun assertNearColor(expected: Int, actual: Int) {
        assertTrue("Expected $expected, actual $actual", kotlin.math.abs(Color.red(expected) - Color.red(actual)) < 15 &&
            kotlin.math.abs(Color.green(expected) - Color.green(actual)) < 15 &&
            kotlin.math.abs(Color.blue(expected) - Color.blue(actual)) < 15)
    }
}
