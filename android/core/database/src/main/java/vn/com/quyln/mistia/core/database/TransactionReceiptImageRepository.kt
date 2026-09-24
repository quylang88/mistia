package vn.com.quyln.mistia.core.database

import java.io.File
import java.util.UUID
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import vn.com.quyln.mistia.core.model.TransactionReceiptImageRecord
import vn.com.quyln.mistia.core.model.TransactionReceiptImageRepository
import vn.com.quyln.mistia.core.model.UserId

internal interface TransactionReceiptMetadataStore {
    suspend fun receipt(transactionId: String): TransactionReceiptImageRecord?
    suspend fun replace(record: TransactionReceiptImageRecord)
    suspend fun delete(transactionId: String)
    suspend fun receipts(ownerUserId: String): List<TransactionReceiptImageRecord>
    suspend fun deleteAccount(ownerUserId: String)
}

class LocalTransactionReceiptImageRepository internal constructor(
    private val metadataStore: TransactionReceiptMetadataStore,
    private val baseDirectory: File,
    private val idProvider: () -> String = { UUID.randomUUID().toString().lowercase() },
    private val dispatcher: CoroutineDispatcher = Dispatchers.IO,
) : TransactionReceiptImageRepository {
    constructor(
        database: MistiaDatabase,
        baseDirectory: File,
    ) : this(
        metadataStore = RoomTransactionReceiptMetadataStore(database.transactionReceiptImageDao()),
        baseDirectory = baseDirectory,
    )

    override suspend fun receipt(transactionId: String): TransactionReceiptImageRecord? =
        metadataStore.receipt(transactionId.normalizedTransactionId())

    override suspend fun replaceReceipt(
        ownerUserId: UserId,
        transactionId: String,
        imageData: ByteArray,
        thumbnailData: ByteArray,
        contentType: String,
        now: String,
    ): Result<TransactionReceiptImageRecord> = runCatching {
        require(imageData.isNotEmpty()) { "Receipt image cannot be empty" }
        require(thumbnailData.isNotEmpty()) { "Receipt thumbnail cannot be empty" }
        val normalizedTransactionId = transactionId.normalizedTransactionId()
        val normalizedOwner = ownerUserId.value.normalizedUuid("owner user ID")
        val normalizedContentType = contentType.trim().lowercase()
        require(normalizedContentType == "image/jpeg") { "Only JPEG receipt images are supported" }
        require(now.isNotBlank()) { "Receipt timestamp cannot be blank" }

        withContext(dispatcher) {
            ensureDirectory()
            val previous = metadataStore.receipt(normalizedTransactionId)
            val fileToken = idProvider().safeFileToken()
            val imageFileName = "receipt-$normalizedTransactionId-$fileToken.jpg"
            val thumbnailFileName = "thumb-$normalizedTransactionId-$fileToken.jpg"
            val imageFile = file(imageFileName)
            val thumbnailFile = file(thumbnailFileName)
            try {
                writeAtomically(imageFile, imageData)
                writeAtomically(thumbnailFile, thumbnailData)
                val record = TransactionReceiptImageRecord(
                    id = idProvider().trim().also { require(it.isNotEmpty()) },
                    ownerUserId = normalizedOwner,
                    transactionId = normalizedTransactionId,
                    imageFileName = imageFileName,
                    thumbnailFileName = thumbnailFileName,
                    contentType = normalizedContentType,
                    byteCount = imageData.size,
                    createdAt = previous?.createdAt ?: now,
                    updatedAt = now,
                )
                metadataStore.replace(record)
                previous?.let(::deleteFiles)
                record
            } catch (error: Throwable) {
                imageFile.delete()
                thumbnailFile.delete()
                throw error
            }
        }
    }

    override suspend fun imageData(receipt: TransactionReceiptImageRecord): Result<ByteArray> =
        read(receipt.imageFileName)

    override suspend fun thumbnailData(receipt: TransactionReceiptImageRecord): Result<ByteArray> =
        read(receipt.thumbnailFileName)

    override suspend fun deleteReceipt(transactionId: String): Result<Unit> = runCatching {
        val normalizedTransactionId = transactionId.normalizedTransactionId()
        withContext(dispatcher) {
            val receipt = metadataStore.receipt(normalizedTransactionId) ?: return@withContext
            deleteFiles(receipt)
            metadataStore.delete(normalizedTransactionId)
        }
    }

    override suspend fun deleteAccount(ownerUserId: UserId): Result<Unit> = runCatching {
        val normalizedOwner = ownerUserId.value.normalizedUuid("owner user ID")
        withContext(dispatcher) {
            metadataStore.receipts(normalizedOwner).forEach(::deleteFiles)
            metadataStore.deleteAccount(normalizedOwner)
        }
    }

    private suspend fun read(fileName: String): Result<ByteArray> = runCatching {
        withContext(dispatcher) { file(fileName).readBytes() }
    }

    private fun ensureDirectory() {
        if (!baseDirectory.exists()) {
            check(baseDirectory.mkdirs()) { "Could not create receipt image directory" }
        }
        check(baseDirectory.isDirectory) { "Receipt image path is not a directory" }
    }

    private fun file(fileName: String): File {
        require(fileName == File(fileName).name && fileName.isNotBlank()) { "Invalid receipt file name" }
        return File(baseDirectory, fileName)
    }

    private fun deleteFiles(receipt: TransactionReceiptImageRecord) {
        file(receipt.imageFileName).delete()
        file(receipt.thumbnailFileName).delete()
    }

    private fun writeAtomically(destination: File, bytes: ByteArray) {
        val temporary = File(destination.parentFile, ".${destination.name}.${UUID.randomUUID()}.tmp")
        try {
            temporary.writeBytes(bytes)
            check(temporary.renameTo(destination)) { "Could not commit receipt image" }
        } finally {
            temporary.delete()
        }
    }
}

private fun String.normalizedTransactionId(): String = normalizedUuid("transaction ID")

private fun String.normalizedUuid(label: String): String =
    UUID.fromString(trim()).toString().lowercase().also { require(it.isNotEmpty()) { "Invalid $label" } }

private fun String.safeFileToken(): String = trim().also { token ->
    require(token.isNotEmpty() && token.all { it.isLetterOrDigit() || it == '-' }) {
        "Invalid receipt file token"
    }
}
