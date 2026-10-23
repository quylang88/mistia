package vn.com.quyln.mistia.feature.transactions

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.async
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Job
import kotlinx.serialization.json.*
import org.junit.*
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.database.*
import vn.com.quyln.mistia.core.model.*

@RunWith(AndroidJUnit4::class)
class TransactionLifecycleReceiptTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val device="44444444-4444-4444-8444-444444444444"
    private val now="2026-10-23T00:00:00Z"
    private val at="2026-10-23T00:01:00Z"
    private fun id(n:Int)=java.util.UUID(0,n.toLong()).toString()
    private var activeOwner=owner
    private lateinit var db:MistiaDatabase
    private lateinit var store:RoomLocalStore
    private lateinit var repo:OfflineFirstFinanceRepository
    private lateinit var receipts:LocalTransactionReceiptImageRepository
    private lateinit var folder:java.io.File
    private var deletionSnapshot:TransactionLifecycleReceiptSnapshot?=null
    @Before fun open()=runBlocking {
        val context=ApplicationProvider.getApplicationContext<Context>()
        db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).allowMainThreadQueries().build()
        store=RoomLocalStore(db,currentBillOwner={activeOwner});repo=OfflineFirstFinanceRepository(store)
        folder=java.io.File(context.cacheDir,"lifecycle-receipt-"+java.util.UUID.randomUUID());receipts=LocalTransactionReceiptImageRepository(db,folder)
        repo.saveWallet(owner,WalletDraft(id=id(1),name="Cash",kind=WalletKind.CASH,currencyCode="JPY",openingBalanceMinor=100),device,now).getOrThrow()
        val parent=repo.saveCategory(owner,CategoryDraft(id=id(30),name="Parent",kind=TransactionCategoryKind.EXPENSE,hierarchyRole=CategoryHierarchyRole.PARENT),device,now).getOrThrow()
        repo.saveCategory(owner,CategoryDraft(id=id(31),name="Child",kind=TransactionCategoryKind.EXPENSE,hierarchyRole=CategoryHierarchyRole.CHILD,parentCategoryId=parent.id),device,now).getOrThrow()
        val posting=CloudRecord(CloudEntity.INVESTMENT_POSTING.table,id(10),owner.value,buildJsonObject {
            put("id",id(10));put("user_id",owner.value);put("sync_version",0L);put("deleted_at",JsonNull);put("created_at",now);put("updated_at",now)
            put("event_id",id(11));put("ledger_transaction_id",id(11));put("wallet_id",id(1));put("role_raw_value","cashAccrual");put("cash_bucket_raw_value","booked");put("cash_origin_raw_value","derived")
            put("amount_minor",60L);put("accounting_amount_minor",60L);put("currency_code","JPY");put("accounting_currency_code","JPY");put("occurred_at","2026-10-23T00:00:01Z")
        },now,null,0)
        store.commitMutation(posting,PendingMutation(CloudEntity.INVESTMENT_POSTING,posting.id,owner.value,MutationKind.UPSERT,posting.payload,now,0,device))
        val draft=TransactionDraft(primaryKind=TransactionPrimaryKind.EXPENSE,title="Expense",amountMinor=70,occurredAt="2026-10-23T00:00:02Z",sourceWalletId=id(1),categoryId=id(31))
        val request=TransactionInvestmentSaveRequest(draft,TransactionCreationIdentity(id(20),now),null,"Adjustment","JPY")
        val review=(repo.prepareTransactionWithInvestmentFunds(owner,request,device,now).exceptionOrNull() as InvestmentFundUsageConfirmationRequired).review
        repo.saveTransactionWithInvestmentFunds(owner,request.copy(consent=review.consent),device,now).getOrThrow()
        receipts.createReceiptIfAbsent(owner,id(20),byteArrayOf(1,2,3),byteArrayOf(4,5),"image/jpeg",now).getOrThrow()
        Unit
    }
    @After fun close(){db.close();folder.deleteRecursively()}
    private suspend fun request(action:TransactionLifecycleAction)=TransactionInvestmentLifecycleRequest(
        LedgerTransactionRecord.fromCloudRecord(requireNotNull(store.record(owner,CloudEntity.LEDGER_TRANSACTION.table,id(20)))),action,at,"JPY","Adjustment",null)
    private suspend fun confirmed(action:TransactionLifecycleAction):TransactionInvestmentLifecycleRequest {
        val r=request(action);val error=repo.prepareTransactionLifecycle(owner,r,device,at).exceptionOrNull()
        return if(error is InvestmentFundUsageConfirmationRequired)r.copy(consent=error.review.consent)else r.also{if(error!=null)throw error}
    }
    private suspend fun archivedDelete():TransactionInvestmentLifecycleRequest {
        repo.saveTransactionLifecycle(owner,confirmed(TransactionLifecycleAction.ARCHIVE),device,at).getOrThrow()
        return request(TransactionLifecycleAction.DELETE)
    }
    private suspend fun save(request:TransactionInvestmentLifecycleRequest,repository:FinanceRepository=repo,images:TransactionReceiptImageRepository=receipts):Result<LedgerTransactionRecord> {
        if(request.action==TransactionLifecycleAction.DELETE && deletionSnapshot==null)
            deletionSnapshot=captureTransactionLifecycleReceiptSnapshot(owner,request,device,at,repository,images)
        return saveTransactionLifecycleWithReceipt(owner,request,device,at,repository,images,deletionSnapshot)
    }
    @Test fun archiveAndRestoreKeepTheSameReceiptMetadataAndFiles()=runBlocking {
        val image=receipts.receipt(id(20));Assert.assertTrue(save(confirmed(TransactionLifecycleAction.ARCHIVE)).getOrThrow().isArchived)
        Assert.assertFalse(save(confirmed(TransactionLifecycleAction.RESTORE)).getOrThrow().isArchived)
        Assert.assertEquals(image,receipts.receipt(id(20)));Assert.assertEquals(2,folder.listFiles()!!.size)
    }
    @Test fun deletionUnlinksOnlyItsOwnedImageAfterTheFinancialTombstone()=runBlocking {
        val r=archivedDelete();Assert.assertEquals(at,save(r).getOrThrow().deletedAt)
        Assert.assertNull(receipts.receipt(id(20)));Assert.assertTrue(folder.listFiles().orEmpty().isEmpty())
        val before=store.transactionInvestmentSaveSnapshot(owner);Assert.assertEquals(at,save(r).getOrThrow().deletedAt);Assert.assertEquals(before,store.transactionInvestmentSaveSnapshot(owner))
    }
    @Test fun unconfirmedArchiveDoesNotEvenReadTheReceiptOrChangeFinancialRows()=runBlocking {
        val before=store.transactionInvestmentSaveSnapshot(owner);var reads=0
        val images=object:TransactionReceiptImageRepository by receipts {override suspend fun receipt(transactionId:String):TransactionReceiptImageRecord?{reads++;return receipts.receipt(transactionId)}}
        Assert.assertTrue(save(request(TransactionLifecycleAction.ARCHIVE),images=images).exceptionOrNull() is InvestmentFundUsageConfirmationRequired)
        Assert.assertEquals(0,reads);Assert.assertEquals(before,store.transactionInvestmentSaveSnapshot(owner));Assert.assertEquals(2,folder.listFiles()!!.size)
    }
    @Test fun failedFinancialDeleteRetainsTheOriginalImage()=runBlocking {
        val r=archivedDelete();val original=receipts.receipt(id(20));val before=store.transactionInvestmentSaveSnapshot(owner)
        val failing=object:FinanceRepository by repo {override suspend fun saveTransactionLifecycle(owner:UserId,request:TransactionInvestmentLifecycleRequest,deviceId:String,now:String)=Result.failure<LedgerTransactionRecord>(java.io.IOException("save failed"))}
        Assert.assertTrue(save(r,failing).isFailure);Assert.assertEquals(before,store.transactionInvestmentSaveSnapshot(owner));Assert.assertEquals(original,receipts.receipt(id(20)));Assert.assertEquals(2,folder.listFiles()!!.size)
    }
    @Test fun lostResponseAfterRealFinancialCommitProvesCompletionBeforeRemovingTheImage()=runBlocking {
        val r=archivedDelete()
        val lost=object:FinanceRepository by repo {override suspend fun saveTransactionLifecycle(owner:UserId,request:TransactionInvestmentLifecycleRequest,deviceId:String,now:String):Result<LedgerTransactionRecord>{repo.saveTransactionLifecycle(owner,request,deviceId,now).getOrThrow();return Result.failure(java.io.IOException("response lost"))}}
        Assert.assertEquals(at,save(r,lost).getOrThrow().deletedAt);Assert.assertNull(receipts.receipt(id(20)));Assert.assertTrue(folder.listFiles().orEmpty().isEmpty())
    }
    @Test fun cancellationAfterCommitKeepsTheImageUntilTheNextExplicitKnownResultRetry()=runBlocking {
        val r=archivedDelete();val original=receipts.receipt(id(20))
        val cancelled=object:FinanceRepository by repo {override suspend fun saveTransactionLifecycle(owner:UserId,request:TransactionInvestmentLifecycleRequest,deviceId:String,now:String):Result<LedgerTransactionRecord>{repo.saveTransactionLifecycle(owner,request,deviceId,now).getOrThrow();throw CancellationException("left after delete")}}
        Assert.assertTrue(runCatching{save(r,cancelled).getOrThrow()}.exceptionOrNull() is CancellationException)
        Assert.assertEquals(original,receipts.receipt(id(20)));Assert.assertEquals(at,save(r).getOrThrow().deletedAt);Assert.assertNull(receipts.receipt(id(20)))
    }
    @Test fun ownerReplacementAfterCommitCannotAuthorizeReceiptDeletion()=runBlocking {
        val r=archivedDelete();val original=receipts.receipt(id(20))
        val changed=object:FinanceRepository by repo {override suspend fun saveTransactionLifecycle(owner:UserId,request:TransactionInvestmentLifecycleRequest,deviceId:String,now:String):Result<LedgerTransactionRecord>{val saved=repo.saveTransactionLifecycle(owner,request,deviceId,now);activeOwner=UserId(id(99));return saved}}
        Assert.assertTrue(runCatching{save(r,changed).getOrThrow()}.exceptionOrNull() is CancellationException)
        Assert.assertEquals(original,receipts.receipt(id(20)));Assert.assertEquals(2,folder.listFiles()!!.size)
    }
    @Test fun anImageReplacedAtConditionalDeletionIsPreservedAndReported()=runBlocking {
        val r=archivedDelete();var newer:TransactionReceiptImageRecord?=null
        val replacing=object:TransactionReceiptImageRepository by receipts {override suspend fun deleteReceiptIfUnchanged(ownerUserId:UserId,expected:TransactionReceiptImageRecord):Result<Unit>{
            newer=receipts.replaceReceipt(owner,id(20),byteArrayOf(9),byteArrayOf(8),"image/jpeg",at).getOrThrow()
            return receipts.deleteReceiptIfUnchanged(ownerUserId,expected)
        }}
        Assert.assertTrue(save(r,images=replacing).isFailure);Assert.assertNotNull(newer);Assert.assertEquals(newer,receipts.receipt(id(20)))
        Assert.assertArrayEquals(byteArrayOf(9),receipts.imageData(requireNotNull(newer)).getOrThrow())
        Assert.assertEquals(at,store.record(owner,CloudEntity.LEDGER_TRANSACTION.table,id(20))!!.deletedAt)
        // Retrying this same old delete must not turn the concurrent replacement into its own image.
        Assert.assertTrue(save(r).isFailure)
        Assert.assertEquals(newer,receipts.receipt(id(20)))
    }
    @Test fun receiptCleanupFailureReportsCommittedDeletionAndRetryOnlyCleansTheOriginalImage()=runBlocking {
        val r=archivedDelete();var attempts=0
        val failing=object:TransactionReceiptImageRepository by receipts {override suspend fun deleteReceiptIfUnchanged(ownerUserId:UserId,expected:TransactionReceiptImageRecord):Result<Unit>{
            attempts++;return if(attempts==1)Result.failure(java.io.IOException("disk unavailable"))else receipts.deleteReceiptIfUnchanged(ownerUserId,expected)
        }}
        val failure=save(r,images=failing).exceptionOrNull()
        Assert.assertEquals("TransactionReceiptCleanupRequired",failure?.javaClass?.simpleName)
        Assert.assertEquals(at,store.record(owner,CloudEntity.LEDGER_TRANSACTION.table,id(20))!!.deletedAt);Assert.assertNotNull(receipts.receipt(id(20)))
        val committed=store.transactionInvestmentSaveSnapshot(owner)
        Assert.assertEquals(at,save(r,images=failing).getOrThrow().deletedAt)
        Assert.assertEquals(committed,store.transactionInvestmentSaveSnapshot(owner));Assert.assertNull(receipts.receipt(id(20)));Assert.assertEquals(2,attempts)
    }
    @Test fun actualCallerJobCancellationAfterFinancialCommitKeepsTheImageForExplicitRetry()=runBlocking {
        val r=archivedDelete();val original=receipts.receipt(id(20));var target:Job?=null
        val cancelling=object:FinanceRepository by repo {override suspend fun saveTransactionLifecycle(owner:UserId,request:TransactionInvestmentLifecycleRequest,deviceId:String,now:String):Result<LedgerTransactionRecord>{
            val saved=repo.saveTransactionLifecycle(owner,request,deviceId,now);target!!.cancel(CancellationException("actual caller left"));return saved
        }}
        val action=async(start=CoroutineStart.LAZY){save(r,cancelling).getOrThrow()};target=action;action.start()
        Assert.assertTrue(runCatching{action.await()}.exceptionOrNull() is CancellationException)
        Assert.assertEquals(original,receipts.receipt(id(20)));Assert.assertEquals(at,save(r).getOrThrow().deletedAt);Assert.assertNull(receipts.receipt(id(20)))
    }
    @Test fun actualForeignReceiptMetadataCannotBeDeletedOrAuthorizeAFinancialDelete()=runBlocking {
        val r=archivedDelete();val before=store.transactionInvestmentSaveSnapshot(owner)
        db.openHelper.writableDatabase.execSQL("UPDATE transaction_receipt_images SET owner_user_id = ? WHERE transaction_id = ?",arrayOf(id(99),id(20)))
        Assert.assertTrue(runCatching{save(r).getOrThrow()}.exceptionOrNull() is IllegalArgumentException)
        Assert.assertEquals(before,store.transactionInvestmentSaveSnapshot(owner));Assert.assertEquals(id(99),receipts.receipt(id(20))!!.ownerUserId);Assert.assertEquals(2,folder.listFiles()!!.size)
    }
}
