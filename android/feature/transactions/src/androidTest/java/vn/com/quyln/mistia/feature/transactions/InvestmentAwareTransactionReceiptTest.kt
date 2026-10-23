package vn.com.quyln.mistia.feature.transactions

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.async
import kotlinx.serialization.json.*
import org.junit.*
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.database.*
import vn.com.quyln.mistia.core.model.*

@RunWith(AndroidJUnit4::class)
class InvestmentAwareTransactionReceiptTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other=UserId("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")
    private val device="44444444-4444-4444-8444-444444444444"
    private val now="2026-10-22T00:00:00Z"
    private fun id(n:Int)=java.util.UUID(0,n.toLong()).toString()
    private lateinit var db:MistiaDatabase
    private lateinit var store:RoomLocalStore
    private lateinit var repository:OfflineFirstFinanceRepository
    private lateinit var receipts:LocalTransactionReceiptImageRepository
    private lateinit var folder:java.io.File
    private fun image()=PreparedReceiptImage(byteArrayOf(1,2,3),byteArrayOf(4,5),"image/jpeg",1,1)
    private fun draft()=TransactionDraft(primaryKind=TransactionPrimaryKind.EXPENSE,title="Expense",amountMinor=70,occurredAt="2026-10-22T00:00:02Z",sourceWalletId=id(1),categoryId=id(31),creationIdentity=TransactionCreationIdentity(id(20),now))
    @Before fun open()=runBlocking {
        val context=ApplicationProvider.getApplicationContext<Context>()
        db=Room.inMemoryDatabaseBuilder(context,MistiaDatabase::class.java).allowMainThreadQueries().build();store=RoomLocalStore(db,currentBillOwner={owner});repository=OfflineFirstFinanceRepository(store)
        folder=java.io.File(context.cacheDir,"fund-receipt-"+java.util.UUID.randomUUID());receipts=LocalTransactionReceiptImageRepository(db,folder)
        repository.saveWallet(owner,WalletDraft(id=id(1),name="Cash",kind=WalletKind.CASH,currencyCode="JPY",openingBalanceMinor=100),device,now).getOrThrow()
        val parent=repository.saveCategory(owner,CategoryDraft(id=id(30),name="Parent",kind=TransactionCategoryKind.EXPENSE,hierarchyRole=CategoryHierarchyRole.PARENT),device,now).getOrThrow()
        repository.saveCategory(owner,CategoryDraft(id=id(31),name="Child",kind=TransactionCategoryKind.EXPENSE,hierarchyRole=CategoryHierarchyRole.CHILD,parentCategoryId=parent.id),device,now).getOrThrow()
        val posting=CloudRecord(CloudEntity.INVESTMENT_POSTING.table,id(10),owner.value,buildJsonObject {
            put("id",id(10));put("user_id",owner.value);put("sync_version",0L);put("deleted_at",JsonNull);put("created_at",now);put("updated_at",now)
            put("event_id",id(11));put("ledger_transaction_id",id(11));put("wallet_id",id(1));put("role_raw_value","cashAccrual");put("cash_bucket_raw_value","booked");put("cash_origin_raw_value","derived")
            put("amount_minor",60L);put("accounting_amount_minor",60L);put("currency_code","JPY");put("accounting_currency_code","JPY");put("occurred_at","2026-10-22T00:00:01Z")
        },now,null,0)
        store.commitMutation(posting,PendingMutation(CloudEntity.INVESTMENT_POSTING,posting.id,owner.value,MutationKind.UPSERT,posting.payload,now,0,device))
    }
    @After fun close(){db.close();folder.deleteRecursively()}
    private suspend fun confirmed():TransactionDraft {
        val request=TransactionInvestmentSaveRequest(draft(),draft().creationIdentity,null,"Automatic adjustment","JPY")
        val error=repository.prepareTransactionWithInvestmentFunds(owner,request,device,now).exceptionOrNull() as InvestmentFundUsageConfirmationRequired
        return draft().copy(investmentConsent=error.review.consent)
    }
    private suspend fun save(d:TransactionDraft,repo:FinanceRepository=repository)=saveInvestmentAwareEditorTransaction(owner,d,"JPY","Automatic adjustment",device,now,repo,receipts,image())
    private suspend fun assertNoTransaction(){Assert.assertNull(store.record(owner,CloudEntity.LEDGER_TRANSACTION.table,id(20)))}
    @Test fun unconfirmedFundUseCreatesNoReceiptMetadataOrFiles()=runBlocking {
        Assert.assertTrue(save(draft()).exceptionOrNull() is InvestmentFundUsageConfirmationRequired)
        Assert.assertNull(receipts.receipt(id(20)));Assert.assertTrue(folder.listFiles().orEmpty().isEmpty());assertNoTransaction()
    }
    @Test fun confirmedReceiptCreationAndReplayKeepTheOriginalImageAndOneTransaction()=runBlocking {
        val d=confirmed();Assert.assertEquals(id(20),save(d).getOrThrow().id)
        val stored=requireNotNull(receipts.receipt(id(20)));val before=store.transactionInvestmentSaveSnapshot(owner)
        Assert.assertEquals(id(20),save(d).getOrThrow().id);Assert.assertEquals(stored,receipts.receipt(id(20)))
        Assert.assertEquals(before,store.transactionInvestmentSaveSnapshot(owner));Assert.assertEquals(2,folder.listFiles()!!.size)
        Assert.assertArrayEquals(image().imageData,receipts.imageData(stored).getOrThrow())
    }
    @Test fun lostResponseAfterRealRoomCommitKeepsReceiptAndReturnsTheStoredResult()=runBlocking {
        val d=confirmed()
        val lost=object:FinanceRepository by repository {
            override suspend fun saveTransactionWithInvestmentFunds(owner:UserId,request:TransactionInvestmentSaveRequest,deviceId:String,now:String):Result<LedgerTransactionRecord> {
                repository.saveTransactionWithInvestmentFunds(owner,request,deviceId,now).getOrThrow()
                return Result.failure(IllegalStateException("lost response after commit"))
            }
        }
        Assert.assertEquals(id(20),save(d,lost).getOrThrow().id);val stored=requireNotNull(receipts.receipt(id(20)))
        Assert.assertArrayEquals(image().imageData,receipts.imageData(stored).getOrThrow());Assert.assertEquals(2,folder.listFiles()!!.size)
    }
    @Test fun saveFailureBeforeAnyFinancialWriteCleansOnlyItsOwnStagedImage()=runBlocking {
        val expected=IllegalStateException("failed before commit")
        val failed=object:FinanceRepository by repository {
            override suspend fun saveTransactionWithInvestmentFunds(owner:UserId,request:TransactionInvestmentSaveRequest,deviceId:String,now:String)=Result.failure<LedgerTransactionRecord>(expected)
        }
        Assert.assertSame(expected,save(confirmed(),failed).exceptionOrNull());Assert.assertNull(receipts.receipt(id(20)))
        Assert.assertTrue(folder.listFiles().orEmpty().isEmpty());assertNoTransaction()
    }
    @Test fun foreignReceiptAtStableIdentityCannotBeReplacedOrDeleted()=runBlocking {
        val old=receipts.replaceReceipt(other,id(20),byteArrayOf(9),byteArrayOf(8),"image/jpeg",now).getOrThrow()
        Assert.assertTrue(save(confirmed()).isFailure);Assert.assertEquals(old,receipts.receipt(id(20)));Assert.assertArrayEquals(byteArrayOf(9),receipts.imageData(old).getOrThrow());assertNoTransaction()
    }
    @Test fun sameOwnedStagedReceiptIsReusedWhileDifferentContentIsPreservedAndRejected()=runBlocking {
        val d=confirmed();val old=receipts.replaceReceipt(owner,id(20),image().imageData,image().thumbnailData,"image/jpeg",now).getOrThrow()
        Assert.assertEquals(id(20),save(d).getOrThrow().id);Assert.assertEquals(old,receipts.receipt(id(20)))
        val different=image().copy(imageData=byteArrayOf(9))
        Assert.assertTrue(saveInvestmentAwareEditorTransaction(owner,d,"JPY","Automatic adjustment",device,now,repository,receipts,different).isFailure)
        Assert.assertEquals(old,receipts.receipt(id(20)));Assert.assertArrayEquals(image().imageData,receipts.imageData(old).getOrThrow())
    }
    @Test fun cancellationAfterRealCommitKeepsTheImageAndTheNextAttemptProvesCompletion()=runBlocking {
        val d=confirmed()
        val cancelled=object:FinanceRepository by repository {
            override suspend fun saveTransactionWithInvestmentFunds(owner:UserId,request:TransactionInvestmentSaveRequest,deviceId:String,now:String):Result<LedgerTransactionRecord> {
                repository.saveTransactionWithInvestmentFunds(owner,request,deviceId,now).getOrThrow()
                throw kotlinx.coroutines.CancellationException("cancelled after commit")
            }
        }
        Assert.assertTrue(runCatching{save(d,cancelled)}.exceptionOrNull() is kotlinx.coroutines.CancellationException)
        val stored=requireNotNull(receipts.receipt(id(20)));Assert.assertArrayEquals(image().imageData,receipts.imageData(stored).getOrThrow())
        Assert.assertEquals(id(20),save(d).getOrThrow().id);Assert.assertEquals(stored,receipts.receipt(id(20)))
    }
    @Test fun ownerReplacementAfterCommitCannotDeleteTheImageWhenActiveOwnerProofIsUnavailable()=runBlocking {
        var active=owner
        val owned=OfflineFirstFinanceRepository(RoomLocalStore(db,currentBillOwner={active}))
        val switched=object:FinanceRepository by owned {
            override suspend fun saveTransactionWithInvestmentFunds(owner:UserId,request:TransactionInvestmentSaveRequest,deviceId:String,now:String):Result<LedgerTransactionRecord> {
                owned.saveTransactionWithInvestmentFunds(owner,request,deviceId,now).getOrThrow();active=other
                return Result.failure(IllegalStateException("owner replaced after commit"))
            }
        }
        val d=confirmed();Assert.assertTrue(save(d,switched).isFailure)
        val stored=requireNotNull(receipts.receipt(id(20)));Assert.assertNotNull(store.record(owner,CloudEntity.LEDGER_TRANSACTION.table,id(20)))
        Assert.assertArrayEquals(image().imageData,receipts.imageData(stored).getOrThrow())
        active=owner;Assert.assertEquals(id(20),save(d,owned).getOrThrow().id);Assert.assertEquals(stored,receipts.receipt(id(20)))
    }
    @Test fun restoredRequiredReceiptWithoutMemoryCanProveBothFinancialAndStoredImageCompletion()=runBlocking {
        val d=confirmed();val saved=save(d).getOrThrow();val stored=requireNotNull(receipts.receipt(id(20)))
        val before=store.transactionInvestmentSaveSnapshot(owner)
        val restored=TransactionReceiptEditorState.pending(image()).withoutInMemoryImage()
        Assert.assertTrue(restored.newReceiptImageForSave().isFailure)
        val result=saveInvestmentAwareEditorReceiptState(owner,d.copy(investmentConsent=null),"JPY","Automatic adjustment",device,now,repository,receipts,restored)
        Assert.assertEquals(saved,result.getOrThrow());Assert.assertEquals(stored,receipts.receipt(id(20)))
        Assert.assertEquals(before,store.transactionInvestmentSaveSnapshot(owner));Assert.assertEquals(2,folder.listFiles()!!.size)
    }
    @Test fun requiredReceiptWithoutMemoryCannotRecoverAnUncommittedOrChangedCreation()=runBlocking {
        val d=confirmed();val restored=TransactionReceiptEditorState.pending(image()).withoutInMemoryImage()
        Assert.assertTrue(saveInvestmentAwareEditorReceiptState(owner,d,"JPY","Automatic adjustment",device,now,repository,receipts,restored).isFailure)
        assertNoTransaction();Assert.assertNull(receipts.receipt(id(20)));Assert.assertTrue(folder.listFiles().orEmpty().isEmpty())
        save(d).getOrThrow();val before=store.transactionInvestmentSaveSnapshot(owner);val stored=receipts.receipt(id(20))
        Assert.assertTrue(saveInvestmentAwareEditorReceiptState(owner,d.copy(amountMinor=69),"JPY","Automatic adjustment",device,now,repository,receipts,restored).isFailure)
        Assert.assertEquals(before,store.transactionInvestmentSaveSnapshot(owner));Assert.assertEquals(stored,receipts.receipt(id(20)))
    }
    @Test fun requiredReceiptWithoutMemoryCannotProveMissingOrForeignStoredImageFiles()=runBlocking {
        val d=confirmed();save(d).getOrThrow();val restored=TransactionReceiptEditorState.pending(image()).withoutInMemoryImage();val before=store.transactionInvestmentSaveSnapshot(owner)
        val stored=requireNotNull(receipts.receipt(id(20)));java.io.File(folder,stored.imageFileName).delete()
        Assert.assertTrue(saveInvestmentAwareEditorReceiptState(owner,d,"JPY","Automatic adjustment",device,now,repository,receipts,restored).isFailure)
        Assert.assertEquals(before,store.transactionInvestmentSaveSnapshot(owner));Assert.assertEquals(stored,receipts.receipt(id(20)))
        receipts.replaceReceipt(owner,id(20),image().imageData,image().thumbnailData,"image/jpeg",now).getOrThrow()
        db.openHelper.writableDatabase.execSQL("UPDATE transaction_receipt_images SET owner_user_id = ? WHERE transaction_id = ?",arrayOf(other.value,id(20)))
        val foreign=requireNotNull(receipts.receipt(id(20)))
        Assert.assertTrue(saveInvestmentAwareEditorReceiptState(owner,d,"JPY","Automatic adjustment",device,now,repository,receipts,restored).isFailure)
        Assert.assertEquals(foreign,receipts.receipt(id(20)));Assert.assertEquals(before,store.transactionInvestmentSaveSnapshot(owner))
    }
    @Test fun cancellationAfterConditionalReceiptCreationCleansItsOwnStagingBeforeAnyFinancialWrite()=runBlocking {
        val d=confirmed();val before=store.transactionInvestmentSaveSnapshot(owner);var target:kotlinx.coroutines.Job?=null
        val cancelled=object:TransactionReceiptImageRepository by receipts {
            override suspend fun createReceiptIfAbsent(ownerUserId:UserId,transactionId:String,imageData:ByteArray,thumbnailData:ByteArray,contentType:String,now:String):Result<TransactionReceiptImageRecord> {
                val saved=receipts.createReceiptIfAbsent(ownerUserId,transactionId,imageData,thumbnailData,contentType,now)
                if(saved.isSuccess)target!!.cancel(kotlinx.coroutines.CancellationException("cancel after conditional receipt commit"))
                return saved
            }
        }
        val task=async(start=kotlinx.coroutines.CoroutineStart.LAZY) {
            saveInvestmentAwareEditorTransaction(owner,d,"JPY","Automatic adjustment",device,now,repository,cancelled,image())
        }
        target=task;task.start()
        Assert.assertTrue(runCatching{task.await()}.exceptionOrNull() is kotlinx.coroutines.CancellationException)
        Assert.assertNull(receipts.receipt(id(20)));Assert.assertTrue(folder.listFiles().orEmpty().isEmpty())
        Assert.assertEquals(before,store.transactionInvestmentSaveSnapshot(owner))
    }
    @Test fun newerReceiptInsertedAtDeletionCannotBeRemovedByTheOldStoredEditorAttempt()=runBlocking {
        val created=confirmed();save(created).getOrThrow()
        val draft=created.copy(id=id(20),creationIdentity=null,amountMinor=50,investmentConsent=null)
        val request=TransactionInvestmentSaveRequest(draft,null,null,"Automatic adjustment","JPY")
        val review=(repository.prepareTransactionWithInvestmentFunds(owner,request,device,now).exceptionOrNull() as InvestmentFundUsageConfirmationRequired).review
        var newer:TransactionReceiptImageRecord?=null
        suspend fun replace(){newer=receipts.replaceReceipt(owner,id(20),byteArrayOf(9),byteArrayOf(8),"image/jpeg",now).getOrThrow()}
        val raced=object:TransactionReceiptImageRepository by receipts {
            override suspend fun deleteReceipt(transactionId:String):Result<Unit>{replace();return receipts.deleteReceipt(transactionId)}
            override suspend fun deleteReceiptIfUnchanged(ownerUserId:UserId,expected:TransactionReceiptImageRecord):Result<Unit>{replace();return receipts.deleteReceiptIfUnchanged(ownerUserId,expected)}
        }
        val result=saveInvestmentAwareEditorTransaction(owner,draft.copy(investmentConsent=review.consent),"JPY","Automatic adjustment",device,now,repository,raced,deleteStoredReceipt=true)
        Assert.assertTrue(result.isFailure);Assert.assertEquals(newer,receipts.receipt(id(20)));Assert.assertNotNull(newer)
        Assert.assertArrayEquals(byteArrayOf(9),receipts.imageData(requireNotNull(newer)).getOrThrow())
        Assert.assertEquals(50L,store.record(owner,CloudEntity.LEDGER_TRANSACTION.table,id(20))!!.payload.financeRawLong("amount_minor"))
    }
}
