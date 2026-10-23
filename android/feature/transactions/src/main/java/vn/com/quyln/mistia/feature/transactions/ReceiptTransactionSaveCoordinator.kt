package vn.com.quyln.mistia.feature.transactions

import java.util.concurrent.CancellationException
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import vn.com.quyln.mistia.core.model.PreparedReceiptImage
import vn.com.quyln.mistia.core.model.TransactionDraft

internal fun resolveReceiptImageForSave(
    receiptRequired: Boolean,
    receiptImage: PreparedReceiptImage?,
): Result<PreparedReceiptImage?> = when {
    receiptRequired && receiptImage == null -> Result.failure(
        IllegalStateException("Required receipt image is no longer available"),
    )
    else -> Result.success(receiptImage)
}

internal suspend fun <Record> saveReceiptBackedTransaction(
    draft: TransactionDraft,
    receiptImage: PreparedReceiptImage,
    transactionIdProvider: () -> String,
    persistReceipt: suspend (String, PreparedReceiptImage) -> Result<Unit>,
    saveTransaction: suspend (TransactionDraft) -> Result<Record>,
    deleteReceipt: suspend (String) -> Result<Unit>,
    preflight:suspend (TransactionDraft)->Result<Record?> = {Result.success(null)},
    recoverCommitted:(suspend (TransactionDraft)->Result<Record?>)? = null,
): Result<Record> {
    val prepared=try{preflight(draft)}catch(error:Throwable){if(error is CancellationException)throw error;Result.failure(error)}
    prepared.exceptionOrNull()?.let{if(it is CancellationException)throw it;return Result.failure(it)}
    prepared.getOrNull()?.let{return Result.success(it)}
    val transactionId = runCatching {
        require(draft.id == null) { "Receipt-backed coordinator only creates new transactions" }
        draft.creationIdentity?.let { identity ->
            require(java.util.UUID.fromString(identity.id).toString()==identity.id)
            java.time.Instant.parse(identity.createdAt)
            identity.id
        } ?: transactionIdProvider().trim().also { require(it.isNotEmpty()) }
    }.getOrElse { return Result.failure(it) }
    val receiptFailure = try {
        persistReceipt(transactionId, receiptImage).exceptionOrNull()
    } catch (error: Throwable) {
        error
    }
    if (receiptFailure != null) {
        if (receiptFailure is CancellationException) {
            cleanupReceiptAfterCancellation(transactionId, receiptFailure, deleteReceipt)
            throw receiptFailure
        }
        return Result.failure(receiptFailure)
    }
    try {
        currentCoroutineContext().ensureActive()
    } catch (cancellation: CancellationException) {
        cleanupReceiptAfterCancellation(transactionId, cancellation, deleteReceipt)
        throw cancellation
    }

    val transactionResult = try {
        saveTransaction(if(draft.creationIdentity==null)draft.copy(id=transactionId) else draft)
    } catch (error: Throwable) {
        Result.failure(error)
    }
    val transactionFailure = transactionResult.exceptionOrNull() ?: return transactionResult
    if(recoverCommitted!=null) {
        val recovered=withContext(NonCancellable) {
            try{recoverCommitted(draft)}catch(error:Throwable){Result.failure(error)}
        }
        recovered.getOrNull()?.let {
            if(transactionFailure is CancellationException)throw transactionFailure
            return Result.success(it)
        }
        recovered.exceptionOrNull()?.takeUnless{it===transactionFailure}?.let(transactionFailure::addSuppressed)
    }
    val cleanupFailure = if (transactionFailure is CancellationException) {
        withContext(NonCancellable) { receiptCleanupFailure(transactionId, deleteReceipt) }
    } else {
        receiptCleanupFailure(transactionId, deleteReceipt)
    }
    if (cleanupFailure != null && cleanupFailure !== transactionFailure) {
        transactionFailure.addSuppressed(cleanupFailure)
    }
    if (transactionFailure is CancellationException) throw transactionFailure
    return Result.failure(transactionFailure)
}

private suspend fun cleanupReceiptAfterCancellation(
    transactionId: String,
    cancellation: CancellationException,
    deleteReceipt: suspend (String) -> Result<Unit>,
) {
    val cleanupFailure = withContext(NonCancellable) {
        receiptCleanupFailure(transactionId, deleteReceipt)
    }
    if (cleanupFailure != null && cleanupFailure !== cancellation) {
        cancellation.addSuppressed(cleanupFailure)
    }
}

private suspend fun receiptCleanupFailure(
    transactionId: String,
    deleteReceipt: suspend (String) -> Result<Unit>,
): Throwable? = try {
    deleteReceipt(transactionId).exceptionOrNull()
} catch (error: Throwable) {
    error
}
