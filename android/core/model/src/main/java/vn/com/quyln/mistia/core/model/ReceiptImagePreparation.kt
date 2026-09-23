package vn.com.quyln.mistia.core.model

import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive

data class ReceiptImageDimensions(
    val width: Int,
    val height: Int,
) {
    val longestSide: Int
        get() = maxOf(width, height)

    val isValid: Boolean
        get() = width > 0 && height > 0
}

data class PreparedReceiptImage(
    val imageData: ByteArray,
    val thumbnailData: ByteArray,
    val mimeType: String,
    val width: Int,
    val height: Int,
) {
    override fun equals(other: Any?): Boolean = other is PreparedReceiptImage &&
        imageData.contentEquals(other.imageData) &&
        thumbnailData.contentEquals(other.thumbnailData) &&
        mimeType == other.mimeType &&
        width == other.width &&
        height == other.height

    override fun hashCode(): Int {
        var result = imageData.contentHashCode()
        result = 31 * result + thumbnailData.contentHashCode()
        result = 31 * result + mimeType.hashCode()
        result = 31 * result + width
        return 31 * result + height
    }
}

interface ReceiptImageCodec<Frame> {
    /** Returns an orientation-normalized frame. */
    fun decode(data: ByteArray): Frame?

    fun dimensions(frame: Frame): ReceiptImageDimensions

    /** Returns an opaque frame whose longest side is no greater than [maxDimension]. */
    fun renderOpaqueScaled(frame: Frame, maxDimension: Int): Frame?

    fun encodeJpeg(frame: Frame, quality: Double): ByteArray?
}

enum class ReceiptImagePreparationFailure {
    DECODE_FAILED,
    INVALID_DIMENSIONS,
    SCALE_FAILED,
    ENCODE_FAILED,
    TOO_LARGE,
}

class ReceiptImagePreparationException(
    val reason: ReceiptImagePreparationFailure,
) : IllegalArgumentException("Receipt image preparation failed (${reason.name})")

class ReceiptImagePreparer<Frame>(
    private val codec: ReceiptImageCodec<Frame>,
) {
    suspend fun prepare(sourceData: ByteArray): PreparedReceiptImage {
        currentCoroutineContext().ensureActive()
        val source = codec.decode(sourceData)
            ?: throw ReceiptImagePreparationException(ReceiptImagePreparationFailure.DECODE_FAILED)
        val sourceDimensions = codec.dimensions(source)
        if (!sourceDimensions.isValid) {
            throw ReceiptImagePreparationException(ReceiptImagePreparationFailure.INVALID_DIMENSIONS)
        }

        val normalized = codec.renderOpaqueScaled(source, MAX_ANALYSIS_DIMENSION)
            ?: throw ReceiptImagePreparationException(ReceiptImagePreparationFailure.SCALE_FAILED)
        val normalizedDimensions = codec.dimensions(normalized)
        if (!normalizedDimensions.isValid || normalizedDimensions.longestSide > MAX_ANALYSIS_DIMENSION) {
            throw ReceiptImagePreparationException(ReceiptImagePreparationFailure.INVALID_DIMENSIONS)
        }

        var candidate = normalized
        var candidateDimensions = normalizedDimensions
        var preparedData: ByteArray? = null

        while (true) {
            currentCoroutineContext().ensureActive()
            preparedData = encodeWithinBudget(candidate)
            if (preparedData.size <= MAX_ANALYSIS_BYTES) break

            if (candidateDimensions.longestSide <= MIN_ANALYSIS_DIMENSION) {
                preparedData = null
                break
            }
            val nextDimension = (candidateDimensions.longestSide * DIMENSION_RETRY_FACTOR).toInt()
            if (nextDimension < MIN_ANALYSIS_DIMENSION) {
                preparedData = null
                break
            }
            candidate = codec.renderOpaqueScaled(normalized, nextDimension)
                ?: throw ReceiptImagePreparationException(ReceiptImagePreparationFailure.SCALE_FAILED)
            candidateDimensions = codec.dimensions(candidate)
            if (!candidateDimensions.isValid || candidateDimensions.longestSide > nextDimension) {
                throw ReceiptImagePreparationException(ReceiptImagePreparationFailure.INVALID_DIMENSIONS)
            }
        }

        val imageData = preparedData?.takeIf { it.size <= MAX_ANALYSIS_BYTES }
            ?: throw ReceiptImagePreparationException(ReceiptImagePreparationFailure.TOO_LARGE)
        currentCoroutineContext().ensureActive()
        val thumbnail = codec.renderOpaqueScaled(normalized, THUMBNAIL_DIMENSION)
            ?: throw ReceiptImagePreparationException(ReceiptImagePreparationFailure.SCALE_FAILED)
        val thumbnailData = codec.encodeJpeg(thumbnail, THUMBNAIL_QUALITY)
            ?: throw ReceiptImagePreparationException(ReceiptImagePreparationFailure.ENCODE_FAILED)

        return PreparedReceiptImage(
            imageData = imageData,
            thumbnailData = thumbnailData,
            mimeType = JPEG_MIME_TYPE,
            width = candidateDimensions.width,
            height = candidateDimensions.height,
        )
    }

    private suspend fun encodeWithinBudget(frame: Frame): ByteArray {
        var qualityPercent = INITIAL_QUALITY_PERCENT
        while (qualityPercent >= MIN_QUALITY_PERCENT) {
            currentCoroutineContext().ensureActive()
            val data = codec.encodeJpeg(frame, qualityPercent / 100.0)
                ?: throw ReceiptImagePreparationException(ReceiptImagePreparationFailure.ENCODE_FAILED)
            if (data.size <= MAX_ANALYSIS_BYTES || qualityPercent == MIN_QUALITY_PERCENT) return data
            qualityPercent -= QUALITY_STEP_PERCENT
        }
        throw ReceiptImagePreparationException(ReceiptImagePreparationFailure.ENCODE_FAILED)
    }

    companion object {
        const val MAX_ANALYSIS_BYTES = 3_800_000
        const val MAX_ANALYSIS_DIMENSION = 3_000
        const val MIN_ANALYSIS_DIMENSION = 900
        const val THUMBNAIL_DIMENSION = 240
        const val INITIAL_QUALITY_PERCENT = 90
        const val MIN_QUALITY_PERCENT = 42
        const val QUALITY_STEP_PERCENT = 8
        const val THUMBNAIL_QUALITY = 0.68
        const val DIMENSION_RETRY_FACTOR = 0.86
        const val JPEG_MIME_TYPE = "image/jpeg"
    }
}
