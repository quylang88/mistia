package vn.com.quyln.mistia.core.model

data class TransactionReceiptImageRecord(
    val id: String,
    val ownerUserId: String,
    val transactionId: String,
    val imageFileName: String,
    val thumbnailFileName: String,
    val contentType: String,
    val byteCount: Int,
    val createdAt: String,
    val updatedAt: String,
)

interface TransactionReceiptImageRepository {
    suspend fun receipt(transactionId: String): TransactionReceiptImageRecord?

    suspend fun replaceReceipt(
        ownerUserId: UserId,
        transactionId: String,
        imageData: ByteArray,
        thumbnailData: ByteArray,
        contentType: String,
        now: String,
    ): Result<TransactionReceiptImageRecord>

    suspend fun imageData(receipt: TransactionReceiptImageRecord): Result<ByteArray>

    suspend fun thumbnailData(receipt: TransactionReceiptImageRecord): Result<ByteArray>

    suspend fun deleteReceipt(transactionId: String): Result<Unit>

    suspend fun deleteAccount(ownerUserId: UserId): Result<Unit>
}
