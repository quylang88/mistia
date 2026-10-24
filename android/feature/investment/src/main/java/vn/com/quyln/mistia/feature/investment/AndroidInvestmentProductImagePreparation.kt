package vn.com.quyln.mistia.feature.investment

import android.content.ContentResolver
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Rect
import android.media.ExifInterface
import android.net.Uri
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.InputStream
import kotlin.math.roundToInt
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import vn.com.quyln.mistia.core.model.InvestmentProductImagePreparationException
import vn.com.quyln.mistia.core.model.InvestmentProductImagePreparationFailure
import vn.com.quyln.mistia.core.model.InvestmentProductImagePreparer
import vn.com.quyln.mistia.core.model.PreparedInvestmentProductImage
import vn.com.quyln.mistia.core.model.ReceiptImageCodec
import vn.com.quyln.mistia.core.model.ReceiptImageDimensions

class AndroidInvestmentProductImagePreparer(
    private val contentResolver: ContentResolver,
    private val dispatcher: CoroutineDispatcher = Dispatchers.IO,
    private val backgroundColor:Int=Color.WHITE,
) {
    suspend fun prepare(data:ByteArray):PreparedInvestmentProductImage = withContext(dispatcher) {
        currentCoroutineContext().ensureActive()
        if(data.size>MAX_SOURCE_BYTES)throw InvestmentProductImagePreparationException(InvestmentProductImagePreparationFailure.SOURCE_TOO_LARGE)
        InvestmentProductImagePreparer(AndroidInvestmentProductImageCodec(backgroundColor)).prepare(data.copyOf())
    }

    suspend fun prepare(uri: Uri): PreparedInvestmentProductImage = withContext(dispatcher) {
        currentCoroutineContext().ensureActive()
        val input = contentResolver.openInputStream(uri)
            ?: throw InvestmentProductImagePreparationException(InvestmentProductImagePreparationFailure.DECODE_FAILED)
        val source = input.use { readBoundedInvestmentProductBytes(it) }
        InvestmentProductImagePreparer(AndroidInvestmentProductImageCodec(backgroundColor)).prepare(source)
    }

    companion object {
        const val MAX_SOURCE_BYTES = 24 * 1024 * 1024
    }
}

internal suspend fun readBoundedInvestmentProductBytes(
    input: InputStream,
    maxBytes: Int = AndroidInvestmentProductImagePreparer.MAX_SOURCE_BYTES,
): ByteArray {
    require(maxBytes > 0) { "Investment image source byte limit must be positive" }
    val output = ByteArrayOutputStream(minOf(maxBytes, DEFAULT_BUFFER_SIZE))
    val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
    var total = 0
    while (true) {
        currentCoroutineContext().ensureActive()
        // Read at most one byte past the ceiling, so an oversized source cannot force a large read.
        val count = input.read(buffer, 0, minOf(buffer.size.toLong(), maxBytes.toLong() - total + 1).toInt())
        currentCoroutineContext().ensureActive()
        if (count < 0) break
        if (count == 0) continue
        if (count > maxBytes - total) {
            throw InvestmentProductImagePreparationException(InvestmentProductImagePreparationFailure.SOURCE_TOO_LARGE)
        }
        output.write(buffer, 0, count)
        total += count
    }
    if (total == 0) {
        throw InvestmentProductImagePreparationException(InvestmentProductImagePreparationFailure.DECODE_FAILED)
    }
    return output.toByteArray()
}

internal class AndroidInvestmentProductImageCodec(private val backgroundColor:Int=Color.WHITE) : ReceiptImageCodec<Bitmap> {
    override fun decode(data: ByteArray): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(data, 0, data.size, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        // A power-of-two decode stays <= 3200, while retaining >= 1600 pixels when the source has them.
        var sampleSize = 1
        val longEdge = maxOf(bounds.outWidth, bounds.outHeight).toLong()
        while (longEdge > MAX_DECODE_DIMENSION.toLong() * sampleSize && sampleSize <= Int.MAX_VALUE / 2) {
            sampleSize *= 2
        }
        val options = BitmapFactory.Options().apply {
            inSampleSize = sampleSize
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
        val decoded = BitmapFactory.decodeByteArray(data, 0, data.size, options) ?: return null
        val orientation = runCatching {
            ExifInterface(ByteArrayInputStream(data)).getAttributeInt(
                ExifInterface.TAG_ORIENTATION,
                ExifInterface.ORIENTATION_NORMAL,
            )
        }.getOrDefault(ExifInterface.ORIENTATION_NORMAL)
        val matrix = orientationMatrix(orientation) ?: return decoded
        return try {
            Bitmap.createBitmap(decoded, 0, 0, decoded.width, decoded.height, matrix, true).also {
                if (it !== decoded) decoded.recycle()
            }
        } catch (_: RuntimeException) {
            decoded.recycle()
            null
        }
    }

    override fun dimensions(frame: Bitmap) = ReceiptImageDimensions(frame.width, frame.height)

    override fun renderOpaqueScaled(frame: Bitmap, maxDimension: Int): Bitmap? {
        if (frame.width <= 0 || frame.height <= 0 || maxDimension <= 0) return null
        val scale = minOf(1.0, maxDimension.toDouble() / maxOf(frame.width, frame.height))
        val width = maxOf(1, (frame.width * scale).roundToInt())
        val height = maxOf(1, (frame.height * scale).roundToInt())
        var output: Bitmap? = null
        return try {
            val rendered = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            output = rendered
            Canvas(rendered).apply {
                drawColor(backgroundColor)
                drawBitmap(frame, null, Rect(0, 0, width, height), Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG))
            }
            rendered.setHasAlpha(false)
            rendered
        } catch (_: RuntimeException) {
            output?.recycle()
            null
        }
    }

    override fun encodeJpeg(frame: Bitmap, quality: Double): ByteArray? = runCatching {
        ByteArrayOutputStream().use { output ->
            if (frame.compress(Bitmap.CompressFormat.JPEG, (quality * 100).roundToInt().coerceIn(0, 100), output)) {
                output.toByteArray()
            } else null
        }
    }.getOrNull()

    override fun release(frame: Bitmap) {
        if (!frame.isRecycled) frame.recycle()
    }

    private fun orientationMatrix(orientation: Int): Matrix? = when (orientation) {
        ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> Matrix().apply { setScale(-1f, 1f) }
        ExifInterface.ORIENTATION_ROTATE_180 -> Matrix().apply { setRotate(180f) }
        ExifInterface.ORIENTATION_FLIP_VERTICAL -> Matrix().apply { setScale(1f, -1f) }
        ExifInterface.ORIENTATION_TRANSPOSE -> Matrix().apply { setRotate(90f); postScale(-1f, 1f) }
        ExifInterface.ORIENTATION_ROTATE_90 -> Matrix().apply { setRotate(90f) }
        ExifInterface.ORIENTATION_TRANSVERSE -> Matrix().apply { setRotate(270f); postScale(-1f, 1f) }
        ExifInterface.ORIENTATION_ROTATE_270 -> Matrix().apply { setRotate(270f) }
        else -> null
    }

    private companion object {
        const val MAX_DECODE_DIMENSION = 3_200
    }
}
