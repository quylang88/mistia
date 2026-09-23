package vn.com.quyln.mistia.feature.transactions

import java.util.concurrent.CancellationException
import vn.com.quyln.mistia.core.model.PreparedReceiptImage
import vn.com.quyln.mistia.core.model.ReceiptImagePreparationException
import vn.com.quyln.mistia.core.model.ReceiptImagePreparationFailure

internal object ReceiptPhotoPickerLimits {
    const val MAX_IMAGES = 5
}

internal sealed interface ReceiptPhotoPickerMode {
    data object None : ReceiptPhotoPickerMode

    data object Single : ReceiptPhotoPickerMode

    data class Multiple(val maxItems: Int) : ReceiptPhotoPickerMode
}

internal data class ReceiptPhotoSelectionFailure(
    val selectionIndex: Int,
    val reason: ReceiptImagePreparationFailure,
)

internal data class ReceiptPhotoSelectionResult(
    val images: List<PreparedReceiptImage>,
    val failures: List<ReceiptPhotoSelectionFailure>,
    val rejectedCount: Int,
)

internal fun receiptPhotoPickerMode(existingImageCount: Int): ReceiptPhotoPickerMode {
    val remaining = (ReceiptPhotoPickerLimits.MAX_IMAGES - existingImageCount.coerceAtLeast(0))
        .coerceAtLeast(0)
    return when (remaining) {
        0 -> ReceiptPhotoPickerMode.None
        1 -> ReceiptPhotoPickerMode.Single
        else -> ReceiptPhotoPickerMode.Multiple(maxItems = remaining)
    }
}

internal suspend fun <Source> prepareReceiptPhotoSelections(
    sources: List<Source>,
    availableSlots: Int,
    prepare: suspend (Source) -> PreparedReceiptImage,
): ReceiptPhotoSelectionResult {
    val acceptedSources = sources.take(
        availableSlots.coerceIn(0, ReceiptPhotoPickerLimits.MAX_IMAGES),
    )
    val images = mutableListOf<PreparedReceiptImage>()
    val failures = mutableListOf<ReceiptPhotoSelectionFailure>()

    acceptedSources.forEachIndexed { index, source ->
        try {
            images += prepare(source)
        } catch (error: CancellationException) {
            throw error
        } catch (error: ReceiptImagePreparationException) {
            failures += ReceiptPhotoSelectionFailure(index, error.reason)
        } catch (_: Exception) {
            failures += ReceiptPhotoSelectionFailure(
                selectionIndex = index,
                reason = ReceiptImagePreparationFailure.DECODE_FAILED,
            )
        }
    }

    return ReceiptPhotoSelectionResult(
        images = images,
        failures = failures,
        rejectedCount = sources.size - acceptedSources.size,
    )
}
