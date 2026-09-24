package vn.com.quyln.mistia.feature.transactions

import java.util.concurrent.CancellationException
import vn.com.quyln.mistia.core.model.PreparedReceiptImage
import vn.com.quyln.mistia.core.model.TransactionReceiptImageRecord

internal class TransactionEditorReceiptPreview private constructor(
    private val ownedImageData: ByteArray,
    private val ownedThumbnailData: ByteArray,
    val contentType: String,
    val byteCount: Int,
) {
    val imageData: ByteArray get() = ownedImageData.copyOf()
    val thumbnailData: ByteArray get() = ownedThumbnailData.copyOf()

    override fun equals(other: Any?): Boolean = other is TransactionEditorReceiptPreview &&
        ownedImageData.contentEquals(other.ownedImageData) &&
        ownedThumbnailData.contentEquals(other.ownedThumbnailData) &&
        contentType == other.contentType &&
        byteCount == other.byteCount

    override fun hashCode(): Int {
        var result = ownedImageData.contentHashCode()
        result = 31 * result + ownedThumbnailData.contentHashCode()
        result = 31 * result + contentType.hashCode()
        result = 31 * result + byteCount
        return result
    }

    companion object {
        fun owned(
            imageData: ByteArray,
            thumbnailData: ByteArray,
            contentType: String,
            byteCount: Int,
        ): TransactionEditorReceiptPreview = TransactionEditorReceiptPreview(
            ownedImageData = imageData.copyOf(),
            ownedThumbnailData = thumbnailData.copyOf(),
            contentType = contentType,
            byteCount = byteCount,
        )
    }
}

internal data class TransactionReceiptEditorState(
    val preview: TransactionEditorReceiptPreview?,
    private val newReceiptImage: PreparedReceiptImage?,
    val newReceiptRequired: Boolean,
    val storedReceiptPresent: Boolean,
    val deleteStoredOnSave: Boolean,
) {
    fun loadedStored(
        record: TransactionReceiptImageRecord,
        imageData: ByteArray,
        thumbnailData: ByteArray,
    ): TransactionReceiptEditorState {
        require(imageData.isNotEmpty()) { "Receipt image cannot be empty" }
        require(thumbnailData.isNotEmpty()) { "Receipt thumbnail cannot be empty" }
        return copy(
            preview = TransactionEditorReceiptPreview.owned(
                imageData = imageData,
                thumbnailData = thumbnailData,
                contentType = record.contentType,
                byteCount = record.byteCount,
            ),
            newReceiptImage = null,
            newReceiptRequired = false,
            storedReceiptPresent = true,
            deleteStoredOnSave = false,
        )
    }

    fun remove(): TransactionReceiptEditorState = copy(
        preview = null,
        newReceiptImage = null,
        newReceiptRequired = false,
        storedReceiptPresent = false,
        deleteStoredOnSave = deleteStoredOnSave || storedReceiptPresent,
    )

    fun withoutInMemoryImage(): TransactionReceiptEditorState = copy(
        preview = null,
        newReceiptImage = null,
    )

    fun newReceiptImageForSave(): Result<PreparedReceiptImage?> = resolveReceiptImageForSave(
        receiptRequired = newReceiptRequired,
        receiptImage = newReceiptImage?.ownedCopy(),
    )

    companion object {
        fun none(): TransactionReceiptEditorState = TransactionReceiptEditorState(
            preview = null,
            newReceiptImage = null,
            newReceiptRequired = false,
            storedReceiptPresent = false,
            deleteStoredOnSave = false,
        )

        fun pending(image: PreparedReceiptImage): TransactionReceiptEditorState {
            val ownedImage = image.ownedCopy()
            return TransactionReceiptEditorState(
                preview = TransactionEditorReceiptPreview.owned(
                    imageData = ownedImage.imageData,
                    thumbnailData = ownedImage.thumbnailData,
                    contentType = ownedImage.mimeType,
                    byteCount = ownedImage.imageData.size,
                ),
                newReceiptImage = ownedImage,
                newReceiptRequired = true,
                storedReceiptPresent = false,
                deleteStoredOnSave = false,
            )
        }
    }
}

private fun PreparedReceiptImage.ownedCopy(): PreparedReceiptImage = copy(
    imageData = imageData.copyOf(),
    thumbnailData = thumbnailData.copyOf(),
)

internal suspend fun <Record> saveTransactionThenDeleteReceipt(
    transactionId: String,
    saveTransaction: suspend () -> Result<Record>,
    deleteReceipt: suspend (String) -> Result<Unit>,
): Result<Record> {
    require(transactionId.isNotBlank()) { "Transaction ID cannot be blank" }
    val transactionResult = try {
        saveTransaction()
    } catch (cancellation: CancellationException) {
        throw cancellation
    } catch (error: Throwable) {
        Result.failure(error)
    }
    val transactionFailure = transactionResult.exceptionOrNull()
    if (transactionFailure is CancellationException) throw transactionFailure
    if (transactionFailure != null) return Result.failure(transactionFailure)

    val deletionResult = try {
        deleteReceipt(transactionId)
    } catch (cancellation: CancellationException) {
        throw cancellation
    } catch (error: Throwable) {
        Result.failure(error)
    }
    val deletionFailure = deletionResult.exceptionOrNull()
    if (deletionFailure is CancellationException) throw deletionFailure
    if (deletionFailure != null) return Result.failure(deletionFailure)
    return transactionResult
}
