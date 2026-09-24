package vn.com.quyln.mistia.feature.transactions

import java.util.concurrent.CancellationException
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import vn.com.quyln.mistia.core.model.PreparedReceiptImage
import vn.com.quyln.mistia.core.model.TransactionDraft
import vn.com.quyln.mistia.core.model.TransactionPrimaryKind

class ReceiptTransactionSaveCoordinatorTest {
    @Test
    fun `recreated receipt editor refuses save when required image was not retained`() {
        val result = resolveReceiptImageForSave(
            receiptRequired = true,
            receiptImage = null,
        )

        assertTrue(result.isFailure)
    }

    @Test
    fun `receipt persists before transaction with one preassigned transaction id`() = runBlocking {
        val events = mutableListOf<String>()
        var savedDraft: TransactionDraft? = null

        val result: Result<String> = saveReceiptBackedTransaction(
            draft = draft(),
            receiptImage = image(),
            transactionIdProvider = { TRANSACTION_ID },
            persistReceipt = { transactionId, receipt ->
                events += "receipt:$transactionId:${receipt.imageData.single()}"
                Result.success(Unit)
            },
            saveTransaction = { transactionDraft ->
                savedDraft = transactionDraft
                events += "transaction:${transactionDraft.id}"
                Result.success("saved")
            },
            deleteReceipt = { error("cleanup must not run") },
        )

        assertEquals("saved", result.getOrThrow())
        assertEquals(TRANSACTION_ID, savedDraft?.id)
        assertEquals(
            listOf("receipt:$TRANSACTION_ID:1", "transaction:$TRANSACTION_ID"),
            events,
        )
    }

    @Test
    fun `receipt failure prevents transaction save`() = runBlocking {
        val receiptFailure = IllegalStateException("receipt failed")
        var didSave = false

        val result: Result<String> = saveReceiptBackedTransaction(
            draft = draft(),
            receiptImage = image(),
            transactionIdProvider = { TRANSACTION_ID },
            persistReceipt = { _, _ -> Result.failure(receiptFailure) },
            saveTransaction = {
                didSave = true
                Result.success("unexpected")
            },
            deleteReceipt = { error("cleanup must not run") },
        )

        assertSame(receiptFailure, result.exceptionOrNull())
        assertFalse(didSave)
    }

    @Test
    fun `transaction failure deletes newly persisted receipt and keeps original error`() = runBlocking {
        val transactionFailure = IllegalArgumentException("transaction failed")
        var deletedId: String? = null

        val result: Result<String> = saveReceiptBackedTransaction(
            draft = draft(),
            receiptImage = image(),
            transactionIdProvider = { TRANSACTION_ID },
            persistReceipt = { _, _ -> Result.success(Unit) },
            saveTransaction = { Result.failure(transactionFailure) },
            deleteReceipt = { transactionId ->
                deletedId = transactionId
                Result.success(Unit)
            },
        )

        assertSame(transactionFailure, result.exceptionOrNull())
        assertEquals(TRANSACTION_ID, deletedId)
    }

    @Test
    fun `cleanup failure is attached to transaction failure`() = runBlocking {
        val transactionFailure = IllegalArgumentException("transaction failed")
        val cleanupFailure = IllegalStateException("cleanup failed")

        val result: Result<String> = saveReceiptBackedTransaction(
            draft = draft(),
            receiptImage = image(),
            transactionIdProvider = { TRANSACTION_ID },
            persistReceipt = { _, _ -> Result.success(Unit) },
            saveTransaction = { Result.failure(transactionFailure) },
            deleteReceipt = { Result.failure(cleanupFailure) },
        )

        assertSame(transactionFailure, result.exceptionOrNull())
        assertTrue(transactionFailure.suppressed.contains(cleanupFailure))
    }

    @Test
    fun `receipt cancellation cleans ambiguous receipt and propagates cancellation`() = runBlocking {
        val cancellation = CancellationException("receipt cancelled")
        var deletedId: String? = null
        var didSave = false

        val thrown = runCatching {
            saveReceiptBackedTransaction<String>(
                draft = draft(),
                receiptImage = image(),
                transactionIdProvider = { TRANSACTION_ID },
                persistReceipt = { _, _ -> throw cancellation },
                saveTransaction = {
                    didSave = true
                    Result.success("unexpected")
                },
                deleteReceipt = { transactionId ->
                    deletedId = transactionId
                    Result.success(Unit)
                },
            )
        }.exceptionOrNull()

        assertSame(cancellation, thrown)
        assertEquals(TRANSACTION_ID, deletedId)
        assertFalse(didSave)
    }

    @Test
    fun `transaction cancellation cleans persisted receipt and propagates cancellation`() = runBlocking {
        val cancellation = CancellationException("transaction cancelled")
        var deletedId: String? = null

        val thrown = runCatching {
            saveReceiptBackedTransaction<String>(
                draft = draft(),
                receiptImage = image(),
                transactionIdProvider = { TRANSACTION_ID },
                persistReceipt = { _, _ -> Result.success(Unit) },
                saveTransaction = { throw cancellation },
                deleteReceipt = { transactionId ->
                    deletedId = transactionId
                    Result.success(Unit)
                },
            )
        }.exceptionOrNull()

        assertSame(cancellation, thrown)
        assertEquals(TRANSACTION_ID, deletedId)
    }

    private fun draft() = TransactionDraft(
        primaryKind = TransactionPrimaryKind.EXPENSE,
        title = "Store",
        amountMinor = 100,
        occurredAt = "2026-09-24T10:00:00Z",
        sourceWalletId = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
        categoryId = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
    )

    private fun image() = PreparedReceiptImage(
        imageData = byteArrayOf(1),
        thumbnailData = byteArrayOf(2),
        mimeType = "image/jpeg",
        width = 100,
        height = 200,
    )

    private companion object {
        const val TRANSACTION_ID = "cccccccc-cccc-cccc-cccc-cccccccccccc"
    }
}
