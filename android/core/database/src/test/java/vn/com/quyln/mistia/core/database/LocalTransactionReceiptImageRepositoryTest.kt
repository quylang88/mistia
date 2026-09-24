package vn.com.quyln.mistia.core.database

import java.io.File
import java.util.ArrayDeque
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import vn.com.quyln.mistia.core.model.TransactionReceiptImageRecord
import vn.com.quyln.mistia.core.model.UserId

class LocalTransactionReceiptImageRepositoryTest {
    @get:Rule
    val temporaryFolder = TemporaryFolder()

    @Test
    fun `replace persists image metadata and removes superseded files`() = runTest {
        val metadata = ReceiptMetadataMemoryStore()
        val ids = ArrayDeque(listOf("receipt-id-1", "file-id-1", "receipt-id-2", "file-id-2"))
        val repository = LocalTransactionReceiptImageRepository(
            metadataStore = metadata,
            baseDirectory = temporaryFolder.newFolder("receipts"),
            idProvider = ids::removeFirst,
        )

        val first = repository.replaceReceipt(
            ownerUserId = UserId("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"),
            transactionId = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
            imageData = byteArrayOf(1, 2, 3),
            thumbnailData = byteArrayOf(4, 5),
            contentType = "image/jpeg",
            now = "2026-09-24T10:00:00Z",
        ).getOrThrow()
        val second = repository.replaceReceipt(
            ownerUserId = UserId("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"),
            transactionId = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
            imageData = byteArrayOf(9, 8),
            thumbnailData = byteArrayOf(7),
            contentType = "image/jpeg",
            now = "2026-09-24T10:01:00Z",
        ).getOrThrow()

        assertNotEquals(first.id, second.id)
        assertEquals(2, second.byteCount)
        assertEquals("2026-09-24T10:01:00Z", second.updatedAt)
        assertEquals(second, repository.receipt(second.transactionId))
        assertArrayEquals(byteArrayOf(9, 8), repository.imageData(second).getOrThrow())
        assertArrayEquals(byteArrayOf(7), repository.thumbnailData(second).getOrThrow())
        assertFalse(File(temporaryFolder.root, "receipts/${first.imageFileName}").exists())
        assertFalse(File(temporaryFolder.root, "receipts/${first.thumbnailFileName}").exists())
        assertEquals(2, File(temporaryFolder.root, "receipts").listFiles()?.size)
    }

    @Test
    fun `metadata failure cleans new files and preserves previous receipt`() = runTest {
        val metadata = ReceiptMetadataMemoryStore()
        val ids = ArrayDeque(listOf("receipt-id-1", "file-id-1", "receipt-id-2", "file-id-2"))
        val repository = LocalTransactionReceiptImageRepository(
            metadataStore = metadata,
            baseDirectory = temporaryFolder.newFolder("failure"),
            idProvider = ids::removeFirst,
        )
        val first = repository.replaceReceipt(
            ownerUserId = UserId("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"),
            transactionId = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
            imageData = byteArrayOf(1),
            thumbnailData = byteArrayOf(2),
            contentType = "image/jpeg",
            now = "2026-09-24T10:00:00Z",
        ).getOrThrow()
        metadata.failNextReplace = true

        val failure = repository.replaceReceipt(
            ownerUserId = UserId("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"),
            transactionId = first.transactionId,
            imageData = byteArrayOf(9),
            thumbnailData = byteArrayOf(8),
            contentType = "image/jpeg",
            now = "2026-09-24T10:01:00Z",
        )

        assertTrue(failure.isFailure)
        assertEquals(first, repository.receipt(first.transactionId))
        assertArrayEquals(byteArrayOf(1), repository.imageData(first).getOrThrow())
        assertEquals(2, File(temporaryFolder.root, "failure").listFiles()?.size)
    }

    @Test
    fun `delete removes metadata and both local files`() = runTest {
        val metadata = ReceiptMetadataMemoryStore()
        val repository = LocalTransactionReceiptImageRepository(
            metadataStore = metadata,
            baseDirectory = temporaryFolder.newFolder("delete"),
            idProvider = ArrayDeque(listOf("receipt-id", "file-id"))::removeFirst,
        )
        val receipt = repository.replaceReceipt(
            ownerUserId = UserId("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"),
            transactionId = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
            imageData = byteArrayOf(1),
            thumbnailData = byteArrayOf(2),
            contentType = "image/jpeg",
            now = "2026-09-24T10:00:00Z",
        ).getOrThrow()

        repository.deleteReceipt(receipt.transactionId).getOrThrow()

        assertNull(repository.receipt(receipt.transactionId))
        assertEquals(0, File(temporaryFolder.root, "delete").listFiles()?.size)
    }

    @Test
    fun `delete account removes only that owners receipt files and metadata`() = runTest {
        val metadata = ReceiptMetadataMemoryStore()
        val repository = LocalTransactionReceiptImageRepository(
            metadataStore = metadata,
            baseDirectory = temporaryFolder.newFolder("accounts"),
            idProvider = ArrayDeque(
                listOf("file-a", "receipt-a", "file-b", "receipt-b"),
            )::removeFirst,
        )
        val ownerA = UserId("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
        val ownerB = UserId("cccccccc-cccc-cccc-cccc-cccccccccccc")
        val first = repository.replaceReceipt(
            ownerUserId = ownerA,
            transactionId = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
            imageData = byteArrayOf(1),
            thumbnailData = byteArrayOf(2),
            contentType = "image/jpeg",
            now = "2026-09-24T10:00:00Z",
        ).getOrThrow()
        val second = repository.replaceReceipt(
            ownerUserId = ownerB,
            transactionId = "dddddddd-dddd-dddd-dddd-dddddddddddd",
            imageData = byteArrayOf(3),
            thumbnailData = byteArrayOf(4),
            contentType = "image/jpeg",
            now = "2026-09-24T10:00:00Z",
        ).getOrThrow()

        repository.deleteAccount(ownerA).getOrThrow()

        assertNull(repository.receipt(first.transactionId))
        assertEquals(second, repository.receipt(second.transactionId))
        assertArrayEquals(byteArrayOf(3), repository.imageData(second).getOrThrow())
        assertEquals(2, File(temporaryFolder.root, "accounts").listFiles()?.size)
    }

    private class ReceiptMetadataMemoryStore : TransactionReceiptMetadataStore {
        private val records = mutableMapOf<String, TransactionReceiptImageRecord>()
        var failNextReplace = false

        override suspend fun receipt(transactionId: String): TransactionReceiptImageRecord? = records[transactionId]

        override suspend fun replace(record: TransactionReceiptImageRecord) {
            if (failNextReplace) {
                failNextReplace = false
                error("metadata write failed")
            }
            records[record.transactionId] = record
        }

        override suspend fun delete(transactionId: String) {
            records.remove(transactionId)
        }

        override suspend fun receipts(ownerUserId: String): List<TransactionReceiptImageRecord> =
            records.values.filter { it.ownerUserId == ownerUserId }

        override suspend fun deleteAccount(ownerUserId: String) {
            records.entries.removeAll { it.value.ownerUserId == ownerUserId }
        }
    }
}
