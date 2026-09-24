package vn.com.quyln.mistia.feature.transactions

import java.util.concurrent.CancellationException
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import vn.com.quyln.mistia.core.model.PreparedReceiptImage
import vn.com.quyln.mistia.core.model.TransactionReceiptImageRecord

class TransactionReceiptEditorStateTest {
    @Test
    fun `pending receipt owns bytes independently from source preview and save callers`() {
        val sourceImage = image()
        val state = TransactionReceiptEditorState.pending(sourceImage)

        sourceImage.imageData[0] = 99
        sourceImage.thumbnailData[0] = 98
        val exposedPreview = requireNotNull(state.preview)
        val exposedPreviewBytes = exposedPreview.imageData
        val exposedThumbnailBytes = exposedPreview.thumbnailData
        exposedPreviewBytes[0] = 97
        exposedThumbnailBytes[0] = 96
        val firstSaveImage = requireNotNull(state.newReceiptImageForSave().getOrThrow())
        firstSaveImage.imageData[0] = 95
        firstSaveImage.thumbnailData[0] = 94

        val secondSaveImage = requireNotNull(state.newReceiptImageForSave().getOrThrow())
        assertEquals(listOf<Byte>(3, 4), secondSaveImage.imageData.toList())
        assertEquals(listOf<Byte>(5), secondSaveImage.thumbnailData.toList())
        assertEquals(listOf<Byte>(3, 4), state.preview?.imageData?.toList())
        assertEquals(listOf<Byte>(5), state.preview?.thumbnailData?.toList())
    }

    @Test
    fun `stored preview owns bytes and compares them by content`() {
        val imageData = byteArrayOf(3, 4)
        val thumbnailData = byteArrayOf(5)
        val state = TransactionReceiptEditorState.none().loadedStored(
            record = record(),
            imageData = imageData,
            thumbnailData = thumbnailData,
        )
        val expected = TransactionReceiptEditorState.none().loadedStored(
            record = record(),
            imageData = byteArrayOf(3, 4),
            thumbnailData = byteArrayOf(5),
        )

        imageData[0] = 99
        thumbnailData[0] = 98
        requireNotNull(state.preview).imageData[0] = 97
        state.preview.thumbnailData[0] = 96

        assertEquals(expected.preview, state.preview)
        assertEquals(expected.preview.hashCode(), state.preview.hashCode())
        assertEquals(listOf<Byte>(3, 4), state.preview.imageData.toList())
        assertEquals(listOf<Byte>(5), state.preview.thumbnailData.toList())
    }

    @Test
    fun `pending analyzed receipt exposes preview and removal makes plain create valid`() {
        val image = image()
        val pending = TransactionReceiptEditorState.pending(image)

        val saveImage = requireNotNull(pending.newReceiptImageForSave().getOrThrow())
        assertFalse(image === saveImage)
        assertEquals(image.imageData.toList(), saveImage.imageData.toList())
        assertEquals(image.thumbnailData.toList(), saveImage.thumbnailData.toList())
        assertEquals(image.imageData.toList(), pending.preview?.imageData?.toList())
        assertEquals(image.thumbnailData.toList(), pending.preview?.thumbnailData?.toList())
        assertTrue(pending.newReceiptRequired)
        assertFalse(pending.deleteStoredOnSave)

        val removed = pending.remove()

        assertNull(removed.preview)
        assertNull(removed.newReceiptImageForSave().getOrThrow())
        assertFalse(removed.newReceiptRequired)
        assertFalse(removed.deleteStoredOnSave)
    }

    @Test
    fun `stored receipt removal schedules deletion without treating image as new`() {
        val stored = TransactionReceiptEditorState.none().loadedStored(
            record = record(),
            imageData = byteArrayOf(3, 4),
            thumbnailData = byteArrayOf(5),
        )

        assertEquals(2, stored.preview?.byteCount)
        assertNull(stored.newReceiptImageForSave().getOrThrow())
        assertTrue(stored.storedReceiptPresent)

        val removed = stored.remove()

        assertNull(removed.preview)
        assertTrue(removed.deleteStoredOnSave)
        assertFalse(removed.storedReceiptPresent)
        assertTrue(removed.remove().deleteStoredOnSave)
    }

    @Test
    fun `restored pending receipt without memory image refuses silent receiptless save`() {
        val restored = TransactionReceiptEditorState.pending(image()).withoutInMemoryImage()

        assertTrue(restored.newReceiptRequired)
        assertTrue(restored.newReceiptImageForSave().isFailure)
    }

    @Test
    fun `transaction saves before stored receipt deletion`() = runBlocking {
        val events = mutableListOf<String>()

        val result = saveTransactionThenDeleteReceipt(
            transactionId = TRANSACTION_ID,
            saveTransaction = {
                events += "transaction"
                Result.success("saved")
            },
            deleteReceipt = { transactionId ->
                events += "delete:$transactionId"
                Result.success(Unit)
            },
        )

        assertEquals("saved", result.getOrThrow())
        assertEquals(listOf("transaction", "delete:$TRANSACTION_ID"), events)
    }

    @Test
    fun `transaction failure leaves stored receipt untouched`() = runBlocking {
        val failure = IllegalStateException("save failed")
        var didDelete = false

        val result: Result<String> = saveTransactionThenDeleteReceipt(
            transactionId = TRANSACTION_ID,
            saveTransaction = { Result.failure(failure) },
            deleteReceipt = {
                didDelete = true
                Result.success(Unit)
            },
        )

        assertSame(failure, result.exceptionOrNull())
        assertFalse(didDelete)
    }

    @Test
    fun `stored receipt deletion failure is returned after transaction save`() = runBlocking {
        val failure = IllegalArgumentException("delete failed")

        val result = saveTransactionThenDeleteReceipt(
            transactionId = TRANSACTION_ID,
            saveTransaction = { Result.success("saved") },
            deleteReceipt = { Result.failure(failure) },
        )

        assertSame(failure, result.exceptionOrNull())
    }

    @Test
    fun `transaction cancellation propagates without deleting stored receipt`() = runBlocking {
        val cancellation = CancellationException("save cancelled")
        var didDelete = false

        val thrown = runCatching {
            saveTransactionThenDeleteReceipt<String>(
                transactionId = TRANSACTION_ID,
                saveTransaction = { Result.failure(cancellation) },
                deleteReceipt = {
                    didDelete = true
                    Result.success(Unit)
                },
            )
        }.exceptionOrNull()

        assertSame(cancellation, thrown)
        assertFalse(didDelete)
    }

    @Test
    fun `stored receipt deletion cancellation propagates after transaction save`() = runBlocking {
        val cancellation = CancellationException("delete cancelled")

        val thrown = runCatching {
            saveTransactionThenDeleteReceipt(
                transactionId = TRANSACTION_ID,
                saveTransaction = { Result.success("saved") },
                deleteReceipt = { Result.failure(cancellation) },
            )
        }.exceptionOrNull()

        assertSame(cancellation, thrown)
    }

    @Test
    fun `stored receipt loader returns empty editor state when metadata is absent`() = runBlocking {
        var didReadFile = false

        val result = loadStoredReceiptEditorState(
            transactionId = TRANSACTION_ID,
            initialState = TransactionReceiptEditorState.none(),
            loadRecord = { null },
            loadImageData = {
                didReadFile = true
                Result.success(byteArrayOf(1))
            },
            loadThumbnailData = {
                didReadFile = true
                Result.success(byteArrayOf(2))
            },
        )

        assertNull(result.state.preview)
        assertNull(result.error)
        assertFalse(didReadFile)
    }

    @Test
    fun `stored receipt loader resolves full image and thumbnail into editor preview`() = runBlocking {
        val events = mutableListOf<String>()

        val result = loadStoredReceiptEditorState(
            transactionId = TRANSACTION_ID,
            initialState = TransactionReceiptEditorState.none(),
            loadRecord = {
                events += "record:$it"
                record()
            },
            loadImageData = {
                events += "image:${it.id}"
                Result.success(byteArrayOf(3, 4))
            },
            loadThumbnailData = {
                events += "thumbnail:${it.id}"
                Result.success(byteArrayOf(5))
            },
        )

        val state = result.state
        assertNull(result.error)
        assertEquals(listOf<Byte>(3, 4), state.preview?.imageData?.toList())
        assertEquals(listOf<Byte>(5), state.preview?.thumbnailData?.toList())
        assertTrue(state.storedReceiptPresent)
        assertEquals(
            listOf("record:$TRANSACTION_ID", "image:receipt-id", "thumbnail:receipt-id"),
            events,
        )
    }

    @Test
    fun `stored receipt loader returns file failure without partial preview`() = runBlocking {
        val failure = IllegalStateException("missing image")
        var didReadThumbnail = false

        val result = loadStoredReceiptEditorState(
            transactionId = TRANSACTION_ID,
            initialState = TransactionReceiptEditorState.none(),
            loadRecord = { record() },
            loadImageData = { Result.failure(failure) },
            loadThumbnailData = {
                didReadThumbnail = true
                Result.success(byteArrayOf(5))
            },
        )

        assertSame(failure, result.error)
        assertTrue(result.state.storedReceiptPresent)
        assertTrue(result.state.remove().deleteStoredOnSave)
        assertFalse(didReadThumbnail)
    }

    @Test
    fun `receipt editor saveable flags restore pending stored and deletion states without bytes`() {
        val pending = TransactionReceiptEditorState.pending(image())
        val restoredPending = TransactionReceiptEditorState.restoreSaveableValues(
            pending.saveableValues(),
        )
        assertTrue(restoredPending.newReceiptRequired)
        assertNull(restoredPending.preview)
        assertTrue(restoredPending.newReceiptImageForSave().isFailure)

        val stored = TransactionReceiptEditorState.none().loadedStored(
            record = record(),
            imageData = byteArrayOf(3, 4),
            thumbnailData = byteArrayOf(5),
        )
        val restoredStored = TransactionReceiptEditorState.restoreSaveableValues(
            stored.saveableValues(),
        )
        assertTrue(restoredStored.storedReceiptPresent)
        assertFalse(restoredStored.deleteStoredOnSave)
        assertNull(restoredStored.preview)

        val restoredRemoval = TransactionReceiptEditorState.restoreSaveableValues(
            stored.remove().saveableValues(),
        )
        assertFalse(restoredRemoval.storedReceiptPresent)
        assertTrue(restoredRemoval.deleteStoredOnSave)
        assertNull(restoredRemoval.preview)
    }

    @Test
    fun `stored receipt load cancellation propagates and skips thumbnail`() = runBlocking {
        val cancellation = CancellationException("image load cancelled")
        var didReadThumbnail = false

        val thrown = runCatching {
            loadStoredReceiptEditorState(
                transactionId = TRANSACTION_ID,
                initialState = TransactionReceiptEditorState.none(),
                loadRecord = { record() },
                loadImageData = { Result.failure(cancellation) },
                loadThumbnailData = {
                    didReadThumbnail = true
                    Result.success(byteArrayOf(5))
                },
            )
        }.exceptionOrNull()

        assertSame(cancellation, thrown)
        assertFalse(didReadThumbnail)
    }

    private fun image() = PreparedReceiptImage(
        imageData = byteArrayOf(3, 4),
        thumbnailData = byteArrayOf(5),
        mimeType = "image/jpeg",
        width = 100,
        height = 200,
    )

    private fun record() = TransactionReceiptImageRecord(
        id = "receipt-id",
        ownerUserId = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
        transactionId = TRANSACTION_ID,
        imageFileName = "receipt.jpg",
        thumbnailFileName = "thumb.jpg",
        contentType = "image/jpeg",
        byteCount = 2,
        createdAt = "2026-09-24T00:00:00Z",
        updatedAt = "2026-09-24T00:00:00Z",
    )

    private companion object {
        const val TRANSACTION_ID = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
    }
}
