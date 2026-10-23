package vn.com.quyln.mistia.core.database

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.*
import org.junit.*
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.model.*

@RunWith(AndroidJUnit4::class)
class ReceiptImageAtomicRoomTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other=UserId("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")
    private val key="bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
    private val secondKey="cccccccc-cccc-cccc-cccc-cccccccccccc"
    private val now="2026-10-22T00:00:00Z"
    private lateinit var db:MistiaDatabase
    private lateinit var metadata:RoomTransactionReceiptMetadataStore
    private lateinit var folder:java.io.File
    private lateinit var repository:LocalTransactionReceiptImageRepository
    @Before fun open() {
        val context=ApplicationProvider.getApplicationContext<Context>()
        db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).allowMainThreadQueries().build()
        metadata=RoomTransactionReceiptMetadataStore(db)
        folder=java.io.File(context.cacheDir,"atomic-receipt-"+java.util.UUID.randomUUID())
        repository=LocalTransactionReceiptImageRepository(metadata,folder)
    }
    @After fun close(){db.close();folder.deleteRecursively()}
    private suspend fun seed()=repository.replaceReceipt(owner,key,byteArrayOf(1),byteArrayOf(2),"image/jpeg",now).getOrThrow()
    @Test fun realRoomForeignOwnerCannotReplaceAnExistingReceiptOrItsFiles()=runBlocking {
        val saved=seed();val files=folder.listFiles()!!.map{it.name}.toSet()
        Assert.assertTrue(repository.replaceReceipt(other,key,byteArrayOf(3),byteArrayOf(4),"image/jpeg",now).isFailure)
        Assert.assertEquals(saved,metadata.receipt(key));Assert.assertEquals(files,folder.listFiles()!!.map{it.name}.toSet())
        Assert.assertArrayEquals(byteArrayOf(1),repository.imageData(saved).getOrThrow())
    }
    @Test fun realRoomRejectsAReceiptInsertedBetweenTheInitialLookupAndTheWrite()=runBlocking {
        val saved=seed();metadata.delete(key);val files=folder.listFiles()!!.map{it.name}.toSet();var first=true
        val raced=object:TransactionReceiptMetadataStore by metadata {
            override suspend fun receipt(transactionId:String):TransactionReceiptImageRecord? {
                val observed=metadata.receipt(transactionId)
                if(first){first=false;metadata.replace(saved)}
                return observed
            }
        }
        val candidate=LocalTransactionReceiptImageRepository(raced,folder)
        Assert.assertTrue(candidate.replaceReceipt(other,key,byteArrayOf(3),byteArrayOf(4),"image/jpeg",now).isFailure)
        Assert.assertEquals(saved,metadata.receipt(key));Assert.assertEquals(files,folder.listFiles()!!.map{it.name}.toSet())
        Assert.assertArrayEquals(byteArrayOf(1),repository.imageData(saved).getOrThrow())
    }
    @Test fun receiptPrimaryKeyCollisionCannotDeleteAnotherOwnersDifferentTransactionMetadata()=runBlocking {
        val ids=java.util.ArrayDeque(listOf("file-a","shared-record","file-b","shared-record"))
        val candidate=LocalTransactionReceiptImageRepository(metadata,folder,idProvider={ids.removeFirst()})
        val saved=candidate.replaceReceipt(owner,key,byteArrayOf(1),byteArrayOf(2),"image/jpeg",now).getOrThrow()
        val files=folder.listFiles()!!.map{it.name}.toSet()
        Assert.assertTrue(candidate.replaceReceipt(other,secondKey,byteArrayOf(3),byteArrayOf(4),"image/jpeg",now).isFailure)
        Assert.assertEquals(saved,metadata.receipt(key));Assert.assertNull(metadata.receipt(secondKey));Assert.assertEquals(files,folder.listFiles()!!.map{it.name}.toSet())
    }
    @Test fun acknowledgementLossAfterRealRoomCommitKeepsDurableFilesAndReturnsKnownSuccess()=runBlocking {
        val lost=object:TransactionReceiptMetadataStore by metadata {
            override suspend fun replace(record:TransactionReceiptImageRecord){metadata.replace(record);throw java.io.IOException("lost metadata ACK")}
            override suspend fun replaceIfCurrent(expected:TransactionReceiptImageRecord?,record:TransactionReceiptImageRecord):Boolean {
                val result=metadata.replaceIfCurrent(expected,record)
                if(result)throw java.io.IOException("lost metadata ACK")
                return result
            }
        }
        val candidate=LocalTransactionReceiptImageRepository(lost,folder)
        val saved=candidate.replaceReceipt(owner,key,byteArrayOf(1),byteArrayOf(2),"image/jpeg",now).getOrThrow()
        Assert.assertEquals(saved,metadata.receipt(key));Assert.assertArrayEquals(byteArrayOf(1),candidate.imageData(saved).getOrThrow());Assert.assertEquals(2,folder.listFiles()!!.size)
    }
    @Test fun conditionalCreateAndDeleteUseActualRoomIdentityAndOwnerChecks()=runBlocking {
        val saved=repository.createReceiptIfAbsent(owner,key,byteArrayOf(1),byteArrayOf(2),"image/jpeg",now).getOrThrow()
        Assert.assertTrue(repository.createReceiptIfAbsent(owner,key,byteArrayOf(3),byteArrayOf(4),"image/jpeg",now).isFailure)
        Assert.assertTrue(repository.deleteReceiptIfUnchanged(other,saved).isFailure)
        val changed=repository.replaceReceipt(owner,key,byteArrayOf(5),byteArrayOf(6),"image/jpeg",now).getOrThrow()
        Assert.assertTrue(repository.deleteReceiptIfUnchanged(owner,saved).isFailure)
        Assert.assertEquals(changed,metadata.receipt(key));Assert.assertArrayEquals(byteArrayOf(5),repository.imageData(changed).getOrThrow())
        repository.deleteReceiptIfUnchanged(owner,changed).getOrThrow();Assert.assertNull(metadata.receipt(key));Assert.assertTrue(folder.listFiles().orEmpty().isEmpty())
    }
    @Test fun realCallerCancellationAfterMetadataCommitDoesNotDestroyItsDurableFiles()=runBlocking {
        var target:Job?=null;var response:Result<TransactionReceiptImageRecord>?=null
        val cancelled=object:TransactionReceiptMetadataStore by metadata {
            override suspend fun replaceIfCurrent(expected:TransactionReceiptImageRecord?,record:TransactionReceiptImageRecord):Boolean {
                val saved=metadata.replaceIfCurrent(expected,record)
                if(saved)target!!.cancel(CancellationException("cancelled after actual metadata commit"))
                return saved
            }
        }
        val candidate=LocalTransactionReceiptImageRepository(cancelled,folder)
        val task=async(start=CoroutineStart.LAZY){response=candidate.createReceiptIfAbsent(owner,key,byteArrayOf(1),byteArrayOf(2),"image/jpeg",now)}
        target=task;task.start();Assert.assertTrue(runCatching{task.await()}.exceptionOrNull() is CancellationException)
        val saved=requireNotNull(response).getOrThrow();Assert.assertEquals(saved,metadata.receipt(key))
        Assert.assertArrayEquals(byteArrayOf(1),candidate.imageData(saved).getOrThrow());Assert.assertArrayEquals(byteArrayOf(2),candidate.thumbnailData(saved).getOrThrow())
        Assert.assertEquals(2,folder.listFiles()!!.size)
    }
}
