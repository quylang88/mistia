package vn.com.quyln.mistia.feature.transactions

import java.io.File
import java.io.IOException
import vn.com.quyln.mistia.core.model.PreparedReceiptImage

internal enum class ReceiptCameraEntryAction {
    Unavailable,
    RequestPermission,
    OpenCamera,
}

internal enum class ReceiptCameraFailure {
    PermissionDenied,
    Unavailable,
    BindFailed,
    CaptureFailed,
}

internal fun receiptCameraEntryAction(
    hasPermission: Boolean,
    cameraAvailable: Boolean,
): ReceiptCameraEntryAction = when {
    !cameraAvailable -> ReceiptCameraEntryAction.Unavailable
    !hasPermission -> ReceiptCameraEntryAction.RequestPermission
    else -> ReceiptCameraEntryAction.OpenCamera
}

internal fun createReceiptCaptureFile(cacheDirectory: File): File {
    val captureDirectory = File(cacheDirectory, "receipt-captures")
    if (!captureDirectory.isDirectory && !captureDirectory.mkdirs()) {
        throw IOException("Could not create receipt capture directory")
    }
    return File.createTempFile("receipt-", ".jpg", captureDirectory)
}

internal suspend fun prepareReceiptCameraCapture(
    captureFile: File,
    prepare: suspend (File) -> PreparedReceiptImage,
): ReceiptPhotoSelectionResult = try {
    prepareReceiptPhotoSelections(
        sources = listOf(captureFile),
        availableSlots = 1,
        prepare = prepare,
    )
} finally {
    captureFile.delete()
}
