package vn.com.quyln.mistia.feature.transactions

import androidx.compose.runtime.saveable.Saver
import androidx.compose.runtime.saveable.listSaver
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
    fun foundStoredReceipt(): TransactionReceiptEditorState = copy(
        preview = null,
        newReceiptImage = null,
        newReceiptRequired = false,
        storedReceiptPresent = true,
        deleteStoredOnSave = false,
    )

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

    internal fun saveableValues(): List<Boolean> = listOf(
        newReceiptRequired,
        storedReceiptPresent,
        deleteStoredOnSave,
    )

    companion object {
        val Saver: Saver<TransactionReceiptEditorState, Any> =
            listSaver<TransactionReceiptEditorState, Boolean>(
                save = { it.saveableValues() },
                restore = ::restoreSaveableValues,
            )

        internal fun restoreSaveableValues(values: List<Boolean>): TransactionReceiptEditorState {
            require(values.size == 3) { "Receipt editor saved state must contain three flags" }
            return TransactionReceiptEditorState(
                preview = null,
                newReceiptImage = null,
                newReceiptRequired = values[0],
                storedReceiptPresent = values[1],
                deleteStoredOnSave = values[2],
            )
        }

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

internal data class TransactionReceiptEditorLoadResult(
    val state: TransactionReceiptEditorState,
    val error: Throwable? = null,
)

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

internal suspend fun loadStoredReceiptEditorState(
    transactionId: String,
    initialState: TransactionReceiptEditorState,
    loadRecord: suspend (String) -> TransactionReceiptImageRecord?,
    loadImageData: suspend (TransactionReceiptImageRecord) -> Result<ByteArray>,
    loadThumbnailData: suspend (TransactionReceiptImageRecord) -> Result<ByteArray>,
): TransactionReceiptEditorLoadResult {
    require(transactionId.isNotBlank()) { "Transaction ID cannot be blank" }
    val record = try {
        loadRecord(transactionId)
    } catch (cancellation: CancellationException) {
        throw cancellation
    } catch (error: Throwable) {
        return TransactionReceiptEditorLoadResult(initialState, error)
    } ?: return TransactionReceiptEditorLoadResult(TransactionReceiptEditorState.none())

    val storedState = initialState.foundStoredReceipt()

    val imageResult = receiptFileResult { loadImageData(record) }
    val imageFailure = imageResult.exceptionOrNull()
    if (imageFailure is CancellationException) throw imageFailure
    if (imageFailure != null) return TransactionReceiptEditorLoadResult(storedState, imageFailure)

    val thumbnailResult = receiptFileResult { loadThumbnailData(record) }
    val thumbnailFailure = thumbnailResult.exceptionOrNull()
    if (thumbnailFailure is CancellationException) throw thumbnailFailure
    if (thumbnailFailure != null) return TransactionReceiptEditorLoadResult(storedState, thumbnailFailure)

    return try {
        TransactionReceiptEditorLoadResult(
            storedState.loadedStored(
                record = record,
                imageData = imageResult.getOrThrow(),
                thumbnailData = thumbnailResult.getOrThrow(),
            ),
        )
    } catch (cancellation: CancellationException) {
        throw cancellation
    } catch (error: Throwable) {
        TransactionReceiptEditorLoadResult(storedState, error)
    }
}

private suspend fun receiptFileResult(
    load: suspend () -> Result<ByteArray>,
): Result<ByteArray> = try {
    load()
} catch (cancellation: CancellationException) {
    throw cancellation
} catch (error: Throwable) {
    Result.failure(error)
}
