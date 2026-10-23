package vn.com.quyln.mistia.core.database

import java.io.File
import java.util.UUID
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import vn.com.quyln.mistia.core.model.TransactionReceiptImageRecord
import vn.com.quyln.mistia.core.model.TransactionReceiptImageRepository
import vn.com.quyln.mistia.core.model.UserId

internal interface TransactionReceiptMetadataStore {
    suspend fun receipt(transactionId: String): TransactionReceiptImageRecord?
    suspend fun replace(record: TransactionReceiptImageRecord)
    suspend fun replaceIfCurrent(expected:TransactionReceiptImageRecord?,record:TransactionReceiptImageRecord):Boolean = throw UnsupportedOperationException("Atomic receipt metadata replacement unavailable")
    suspend fun deleteIfCurrent(expected:TransactionReceiptImageRecord):Boolean = throw UnsupportedOperationException("Atomic receipt metadata deletion unavailable")
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
        metadataStore = RoomTransactionReceiptMetadataStore(database),
        baseDirectory = baseDirectory,
    )

    override suspend fun receipt(transactionId: String): TransactionReceiptImageRecord? =
        metadataStore.receipt(transactionId.normalizedTransactionId())

    override suspend fun replaceReceipt(ownerUserId:UserId,transactionId:String,imageData:ByteArray,thumbnailData:ByteArray,contentType:String,now:String):Result<TransactionReceiptImageRecord> =
        writeReceipt(ownerUserId,transactionId,imageData,thumbnailData,contentType,now,requireAbsent=false)

    override suspend fun createReceiptIfAbsent(ownerUserId:UserId,transactionId:String,imageData:ByteArray,thumbnailData:ByteArray,contentType:String,now:String):Result<TransactionReceiptImageRecord> =
        writeReceipt(ownerUserId,transactionId,imageData,thumbnailData,contentType,now,requireAbsent=true)

    private suspend fun writeReceipt(ownerUserId:UserId,transactionId:String,imageData:ByteArray,thumbnailData:ByteArray,contentType:String,now:String,
        requireAbsent:Boolean):Result<TransactionReceiptImageRecord> {
        var attempted:TransactionReceiptImageRecord?=null
        var candidates:List<File> = emptyList()
        val result=runCatching {
            currentCoroutineContext().ensureActive()
            require(imageData.isNotEmpty()) {"Receipt image cannot be empty"}
            require(thumbnailData.isNotEmpty()) {"Receipt thumbnail cannot be empty"}
            val key=transactionId.normalizedTransactionId()
            val subject=ownerUserId.value.normalizedUuid("owner user ID")
            val mime=contentType.trim().lowercase()
            require(mime=="image/jpeg") {"Only JPEG receipt images are supported"}
            require(now.isNotBlank()) {"Receipt timestamp cannot be blank"}
            withContext(dispatcher) {
                val previous=metadataStore.receipt(key)
                require(previous==null || previous.ownerUserId==subject) {"Receipt belongs to another owner"}
                require(!requireAbsent || previous==null) {"Receipt creation identity is occupied"}
                ensureDirectory()
                val token=idProvider().safeFileToken()
                val image=file("receipt-$key-$token.jpg");val thumbnail=file("thumb-$key-$token.jpg")
                check(!image.exists() && !thumbnail.exists()) {"Receipt file identity is occupied"}
                val record=TransactionReceiptImageRecord(idProvider().trim().also{require(it.isNotEmpty())},subject,key,image.name,thumbnail.name,mime,imageData.size,previous?.createdAt ?: now,now)
                attempted=record;candidates=listOf(image,thumbnail)
                writeAtomically(image,imageData);writeAtomically(thumbnail,thumbnailData)
                check(metadataStore.replaceIfCurrent(previous,record)) {"Receipt changed during image persistence"}
                previous?.let(::deleteFiles)
                record
            }
        }
        if(result.isSuccess || candidates.isEmpty())return result
        val error=requireNotNull(result.exceptionOrNull())
        // The metadata transaction may have committed before its response was lost/cancelled.
        // Probe durably before removing any files; a known committed result keeps both files.
        return withContext(NonCancellable) {withContext(dispatcher) {
            val attempt=requireNotNull(attempted)
            val current=try{metadataStore.receipt(attempt.transactionId)}catch(probe:Throwable) {
                if(probe!==error)error.addSuppressed(probe)
                return@withContext Result.failure<TransactionReceiptImageRecord>(error)
            }
            if(current==attempt && file(attempt.imageFileName).length()==attempt.byteCount.toLong() && file(attempt.thumbnailFileName).length()>0)
                Result.success(attempt)
            else {
                val referenced=current?.let{setOf(it.imageFileName,it.thumbnailFileName)}.orEmpty()
                candidates.filterNot{it.name in referenced}.forEach{it.delete()}
                Result.failure(error)
            }
        }}
    }

    override suspend fun imageData(receipt: TransactionReceiptImageRecord): Result<ByteArray> =
        read(receipt.imageFileName)

    override suspend fun thumbnailData(receipt: TransactionReceiptImageRecord): Result<ByteArray> =
        read(receipt.thumbnailFileName)

    override suspend fun deleteReceipt(transactionId:String):Result<Unit> = runCatching {
        val stored=withContext(dispatcher){metadataStore.receipt(transactionId.normalizedTransactionId())}
        if(stored!=null)deleteReceiptIfUnchanged(UserId(stored.ownerUserId),stored).getOrThrow()
    }

    override suspend fun deleteReceiptIfUnchanged(ownerUserId:UserId,expected:TransactionReceiptImageRecord):Result<Unit> = runCatching {
        currentCoroutineContext().ensureActive()
        require(expected.ownerUserId==ownerUserId.value.normalizedUuid("owner user ID") && expected.transactionId==expected.transactionId.normalizedTransactionId()) {"Receipt deletion owner/identity mismatch"}
        file(expected.imageFileName);file(expected.thumbnailFileName)
        // Once metadata is conditionally unlinked, finish deleting exactly its files even if the caller leaves.
        withContext(NonCancellable) {withContext(dispatcher) {
            check(metadataStore.deleteIfCurrent(expected)) {"Receipt changed before deletion"}
            deleteFiles(expected)
        }}
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
