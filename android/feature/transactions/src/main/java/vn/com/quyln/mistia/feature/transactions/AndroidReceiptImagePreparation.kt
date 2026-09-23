package vn.com.quyln.mistia.feature.transactions

import android.content.ContentResolver
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.media.ExifInterface
import android.net.Uri
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.InputStream
import kotlin.math.max
import kotlin.math.roundToInt
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import vn.com.quyln.mistia.core.model.PreparedReceiptImage
import vn.com.quyln.mistia.core.model.ReceiptImageCodec
import vn.com.quyln.mistia.core.model.ReceiptImageDimensions
import vn.com.quyln.mistia.core.model.ReceiptImagePreparationException
import vn.com.quyln.mistia.core.model.ReceiptImagePreparationFailure
import vn.com.quyln.mistia.core.model.ReceiptImagePreparer

class AndroidReceiptImagePreparer(
    private val contentResolver: ContentResolver,
    private val dispatcher: CoroutineDispatcher = Dispatchers.IO,
) {
    suspend fun prepare(uri: Uri): PreparedReceiptImage = withContext(dispatcher) {
        val source = contentResolver.openInputStream(uri)?.use(::readBoundedReceiptBytes)
            ?: throw ReceiptImagePreparationException(ReceiptImagePreparationFailure.DECODE_FAILED)
        ReceiptImagePreparer(AndroidReceiptImageCodec()).prepare(source)
    }

    companion object {
        const val MAX_SOURCE_BYTES = 24 * 1024 * 1024
    }
}

internal fun readBoundedReceiptBytes(
    input: InputStream,
    maxBytes: Int = AndroidReceiptImagePreparer.MAX_SOURCE_BYTES,
): ByteArray {
    require(maxBytes > 0) { "Receipt source byte limit must be positive" }
    val output = ByteArrayOutputStream(minOf(maxBytes, DEFAULT_BUFFER_SIZE))
    val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
    var total = 0
    while (true) {
        val count = input.read(buffer)
        if (count < 0) break
        if (count == 0) continue
        total += count
        if (total > maxBytes) {
            throw ReceiptImagePreparationException(ReceiptImagePreparationFailure.SOURCE_TOO_LARGE)
        }
        output.write(buffer, 0, count)
    }
    if (total == 0) {
        throw ReceiptImagePreparationException(ReceiptImagePreparationFailure.DECODE_FAILED)
    }
    return output.toByteArray()
}

internal class AndroidReceiptImageCodec : ReceiptImageCodec<Bitmap> {
    override fun decode(data: ByteArray): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(data, 0, data.size, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        val options = BitmapFactory.Options().apply {
            inSampleSize = calculateBitmapSampleSize(
                bounds.outWidth,
                bounds.outHeight,
                MAX_DECODE_DIMENSION,
            )
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
            Bitmap.createBitmap(decoded, 0, 0, decoded.width, decoded.height, matrix, true)
                .also { oriented -> if (oriented !== decoded) decoded.recycle() }
        } catch (_: RuntimeException) {
            decoded.recycle()
            null
        }
    }

    override fun dimensions(frame: Bitmap): ReceiptImageDimensions =
        ReceiptImageDimensions(frame.width, frame.height)

    override fun renderOpaqueScaled(frame: Bitmap, maxDimension: Int): Bitmap? {
        if (frame.width <= 0 || frame.height <= 0 || maxDimension <= 0) return null
        val scale = minOf(1.0, maxDimension.toDouble() / max(frame.width, frame.height).toDouble())
        val targetWidth = max(1, (frame.width * scale).roundToInt())
        val targetHeight = max(1, (frame.height * scale).roundToInt())
        return runCatching {
            Bitmap.createBitmap(targetWidth, targetHeight, Bitmap.Config.ARGB_8888).also { output ->
                val canvas = Canvas(output)
                canvas.drawColor(Color.WHITE)
                canvas.drawBitmap(
                    frame,
                    null,
                    android.graphics.Rect(0, 0, targetWidth, targetHeight),
                    Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG),
                )
            }
        }.getOrNull()
    }

    override fun encodeJpeg(frame: Bitmap, quality: Double): ByteArray? = runCatching {
        ByteArrayOutputStream().use { output ->
            val encoded = frame.compress(
                Bitmap.CompressFormat.JPEG,
                (quality * 100).roundToInt().coerceIn(0, 100),
                output,
            )
            if (encoded) output.toByteArray() else null
        }
    }.getOrNull()

    override fun release(frame: Bitmap) {
        if (!frame.isRecycled) frame.recycle()
    }

    private fun orientationMatrix(orientation: Int): Matrix? = when (orientation) {
        ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> Matrix().apply { setScale(-1f, 1f) }
        ExifInterface.ORIENTATION_ROTATE_180 -> Matrix().apply { setRotate(180f) }
        ExifInterface.ORIENTATION_FLIP_VERTICAL -> Matrix().apply { setScale(1f, -1f) }
        ExifInterface.ORIENTATION_TRANSPOSE -> Matrix().apply {
            setRotate(90f)
            postScale(-1f, 1f)
        }
        ExifInterface.ORIENTATION_ROTATE_90 -> Matrix().apply { setRotate(90f) }
        ExifInterface.ORIENTATION_TRANSVERSE -> Matrix().apply {
            setRotate(270f)
            postScale(-1f, 1f)
        }
        ExifInterface.ORIENTATION_ROTATE_270 -> Matrix().apply { setRotate(270f) }
        else -> null
    }

    private companion object {
        const val MAX_DECODE_DIMENSION = 3_000
    }
}

internal fun calculateBitmapSampleSize(
    width: Int,
    height: Int,
    maxDimension: Int,
): Int {
    require(width > 0 && height > 0) { "Bitmap dimensions must be positive" }
    require(maxDimension > 0) { "Bitmap decode dimension must be positive" }
    val longestSide = maxOf(width, height).toLong()
    var sampleSize = 1
    while (longestSide > maxDimension.toLong() * sampleSize && sampleSize <= Int.MAX_VALUE / 2) {
        sampleSize *= 2
    }
    return sampleSize
}
