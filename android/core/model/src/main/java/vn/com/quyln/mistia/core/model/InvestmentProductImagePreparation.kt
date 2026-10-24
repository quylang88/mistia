package vn.com.quyln.mistia.core.model

import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive

data class PreparedInvestmentProductImage(
    val imageData: ByteArray,
    val thumbnailData: ByteArray,
    val mimeType: String,
    val width: Int,
    val height: Int,
) {
    override fun equals(other: Any?): Boolean = other is PreparedInvestmentProductImage &&
        imageData.contentEquals(other.imageData) && thumbnailData.contentEquals(other.thumbnailData) &&
        mimeType == other.mimeType && width == other.width && height == other.height

    override fun hashCode(): Int {
        var result = imageData.contentHashCode()
        result = 31 * result + thumbnailData.contentHashCode()
        result = 31 * result + mimeType.hashCode()
        result = 31 * result + width
        return 31 * result + height
    }
}

enum class InvestmentProductImagePreparationFailure {
    DECODE_FAILED, INVALID_DIMENSIONS, SCALE_FAILED, ENCODE_FAILED, SOURCE_TOO_LARGE, TOO_LARGE,
}

class InvestmentProductImagePreparationException(
    val reason: InvestmentProductImagePreparationFailure,
) : IllegalArgumentException("Investment product image preparation failed (${reason.name})")

/** Investment image normalization follows InvestmentProductImageProcessing.normalizedJPEG on iOS. */
class InvestmentProductImagePreparer<Frame>(
    private val codec: ReceiptImageCodec<Frame>,
) {
    suspend fun prepare(sourceData: ByteArray): PreparedInvestmentProductImage {
        val owned = mutableListOf<Frame>()
        fun Frame.takeOwnership(): Frame {
            if (owned.none { it === this }) owned += this
            return this
        }
        fun fail(reason: InvestmentProductImagePreparationFailure): Nothing =
            throw InvestmentProductImagePreparationException(reason)
        try {
            currentCoroutineContext().ensureActive()
            val source = codec.decode(sourceData)?.takeOwnership()
                ?: fail(InvestmentProductImagePreparationFailure.DECODE_FAILED)
            currentCoroutineContext().ensureActive()
            if (!codec.dimensions(source).isValid) fail(InvestmentProductImagePreparationFailure.INVALID_DIMENSIONS)
            val full = codec.renderOpaqueScaled(source, MAX_FULL_DIMENSION)?.takeOwnership()
                ?: fail(InvestmentProductImagePreparationFailure.SCALE_FAILED)
            currentCoroutineContext().ensureActive()
            val dimensions = codec.dimensions(full)
            if (!dimensions.isValid || dimensions.longestSide > MAX_FULL_DIMENSION) {
                fail(InvestmentProductImagePreparationFailure.INVALID_DIMENSIONS)
            }

            var imageData: ByteArray? = null
            // Swift subtracts 0.1 while quality > 0.25, so its last attempt is 0.2.
            // Integer percentages preserve the same 90, 80, …, 20 sequence without drift.
            for (quality in INITIAL_QUALITY_PERCENT downTo MIN_QUALITY_PERCENT step QUALITY_STEP_PERCENT) {
                currentCoroutineContext().ensureActive()
                val candidate = codec.encodeJpeg(full, quality / 100.0)
                    ?: fail(InvestmentProductImagePreparationFailure.ENCODE_FAILED)
                currentCoroutineContext().ensureActive()
                if (candidate.size <= MAX_FULL_BYTES) {
                    imageData = candidate
                    break
                }
            }
            val fullData = imageData ?: fail(InvestmentProductImagePreparationFailure.TOO_LARGE)

            currentCoroutineContext().ensureActive()
            // Both Swift derivatives render from the source, avoiding a second resize of the full image.
            val thumbnail = codec.renderOpaqueScaled(source, THUMBNAIL_DIMENSION)?.takeOwnership()
                ?: fail(InvestmentProductImagePreparationFailure.SCALE_FAILED)
            currentCoroutineContext().ensureActive()
            val thumbnailDimensions = codec.dimensions(thumbnail)
            if (!thumbnailDimensions.isValid || thumbnailDimensions.longestSide > THUMBNAIL_DIMENSION) {
                fail(InvestmentProductImagePreparationFailure.INVALID_DIMENSIONS)
            }
            val thumbnailData = codec.encodeJpeg(thumbnail, THUMBNAIL_QUALITY)
                ?: fail(InvestmentProductImagePreparationFailure.ENCODE_FAILED)
            currentCoroutineContext().ensureActive()
            return PreparedInvestmentProductImage(fullData, thumbnailData, JPEG_MIME_TYPE, dimensions.width, dimensions.height)
        } finally {
            owned.asReversed().forEach { frame -> runCatching { codec.release(frame) } }
        }
    }

    companion object {
        const val MAX_FULL_DIMENSION = 1_600
        const val MAX_FULL_BYTES = 4_000_000
        const val THUMBNAIL_DIMENSION = 240
        const val THUMBNAIL_QUALITY = 0.78
        const val INITIAL_QUALITY_PERCENT = 90
        const val MIN_QUALITY_PERCENT = 20
        const val QUALITY_STEP_PERCENT = 10
        const val JPEG_MIME_TYPE = "image/jpeg"
    }
}
