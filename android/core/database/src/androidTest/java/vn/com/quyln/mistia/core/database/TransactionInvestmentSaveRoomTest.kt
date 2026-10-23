package vn.com.quyln.mistia.core.database

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.async
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Job
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.flow.*
import kotlinx.serialization.json.*
import org.junit.*
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.model.*

@RunWith(AndroidJUnit4::class)
class TransactionInvestmentSaveRoomTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val device="44444444-4444-4444-8444-444444444444"
    private val now="2026-10-22T00:00:00Z"
    private fun id(n:Int)=java.util.UUID(0,n.toLong()).toString()
    private lateinit var db:MistiaDatabase
    private lateinit var store:RoomLocalStore
    @Before fun open(){db=Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(),MistiaDatabase::class.java).allowMainThreadQueries().build();store=RoomLocalStore(db,currentBillOwner={owner})}
    @After fun close(){db.close()}
    private suspend fun seed() {
        val wallet=WalletDraft(id=id(1),name="Cash",kind=WalletKind.CASH,currencyCode="JPY",openingBalanceMinor=100).toMutation(owner,null,device,now).record
        val parent=CategoryDraft(id=id(30),name="Parent",kind=TransactionCategoryKind.EXPENSE,hierarchyRole=CategoryHierarchyRole.PARENT).toMutation(owner,null,null,device,now).record
        val child=CategoryDraft(id=id(31),name="Child",kind=TransactionCategoryKind.EXPENSE,hierarchyRole=CategoryHierarchyRole.CHILD,parentCategoryId=id(30)).toMutation(owner,null,parent,device,now).record
        val posting=CloudRecord(CloudEntity.INVESTMENT_POSTING.table,id(10),owner.value,buildJsonObject {
            put("id",id(10));put("user_id",owner.value);put("sync_version",0L);put("deleted_at",JsonNull);put("created_at",now);put("updated_at",now)
            put("event_id",id(11));put("ledger_transaction_id",id(11));put("wallet_id",id(1));put("role_raw_value","cashAccrual");put("cash_bucket_raw_value","booked");put("cash_origin_raw_value","derived")
            put("amount_minor",60L);put("accounting_amount_minor",60L);put("currency_code","JPY");put("accounting_currency_code","JPY");put("occurred_at","2026-10-22T00:00:01Z")
        },now,null,0)
        for(row in listOf(wallet,parent.toCloudRecord(),child.toCloudRecord(),posting))store.commitMutation(row,PendingMutation(CloudEntity.fromTable(row.entity)!!,row.id,owner.value,MutationKind.UPSERT,row.payload,now,row.syncVersion,device))
    }
    private fun request()=TransactionInvestmentSaveRequest(TransactionDraft(primaryKind=TransactionPrimaryKind.EXPENSE,title="Expense",amountMinor=70,occurredAt="2026-10-22T00:00:02Z",sourceWalletId=id(1),categoryId=id(31)),TransactionCreationIdentity(id(20),now),null,"Automatic adjustment","JPY")
    private fun consent(snapshot:TransactionInvestmentSaveSnapshot,request:TransactionInvestmentSaveRequest=request())=request.copy(consent=(runCatching{planTransactionInvestmentSave(snapshot,request,device,now)}.exceptionOrNull() as InvestmentFundUsageConfirmationRequired).review.consent)
    private suspend fun queues()=TransactionInvestmentSaveSnapshot.entities.associateWith{store.pendingMutations(owner,it,Long.MAX_VALUE)}
    @Test fun confirmationPrecedesEveryWriteAndOneCommitPersistsPrimaryDerivedAndBothQueues()=runBlocking {
        seed();val snapshot=store.transactionInvestmentSaveSnapshot(owner);val before=queues()
        Assert.assertTrue(runCatching{store.commitTransactionInvestmentSave(snapshot,request(),device,now)}.exceptionOrNull() is InvestmentFundUsageConfirmationRequired)
        Assert.assertEquals(snapshot,store.transactionInvestmentSaveSnapshot(owner));Assert.assertEquals(before,queues())
        val saved=store.commitTransactionInvestmentSave(snapshot,consent(snapshot),device,now)
        Assert.assertEquals(id(20),saved.id)
        val after=store.transactionInvestmentSaveSnapshot(owner)
        Assert.assertEquals(1,after.recordsByEntity.getValue(CloudEntity.LEDGER_TRANSACTION).size)
        Assert.assertEquals(2,after.recordsByEntity.getValue(CloudEntity.INVESTMENT_POSTING).size)
        Assert.assertEquals(1,queues().getValue(CloudEntity.LEDGER_TRANSACTION).size);Assert.assertEquals(2,queues().getValue(CloudEntity.INVESTMENT_POSTING).size)
    }
    @Test fun changedInvestmentSourceCannotPassAnOtherwiseUnchangedOrdinarySnapshot()=runBlocking {
        seed();val before=store.transactionInvestmentSaveSnapshot(owner);val accepted=consent(before)
        val old=before.recordsByEntity.getValue(CloudEntity.INVESTMENT_POSTING).single();val changed=old.copy(payload=JsonObject(old.payload+("amount_minor" to JsonPrimitive(59L))))
        store.commitMutation(changed,PendingMutation(CloudEntity.INVESTMENT_POSTING,old.id,owner.value,MutationKind.UPSERT,changed.payload,now,0,device))
        val current=store.transactionInvestmentSaveSnapshot(owner);val pending=queues()
        Assert.assertTrue(runCatching{store.commitTransactionInvestmentSave(before,accepted,device,now)}.isFailure)
        Assert.assertEquals(current,store.transactionInvestmentSaveSnapshot(owner));Assert.assertEquals(pending,queues())
    }
    @Test fun lastDerivedQueueFailureRollsBackPrimaryAndAllEarlierOutboxWrites()=runBlocking {
        seed();val before=store.transactionInvestmentSaveSnapshot(owner);val pending=queues()
        db.openHelper.writableDatabase.execSQL("CREATE TRIGGER reject_fund_queue BEFORE INSERT ON sync_outbox WHEN NEW.entity = 'investment_wallet_postings' AND NEW.record_id = '"+investmentLedgerIdentity(id(20),"cash-consumption-booked")+"' BEGIN SELECT RAISE(ABORT, 'synthetic fund queue failure'); END")
        val error=runCatching{store.commitTransactionInvestmentSave(before,consent(before),device,now)}.exceptionOrNull()
        Assert.assertNotNull(error);Assert.assertFalse(error is UnsupportedOperationException)
        Assert.assertEquals(before,store.transactionInvestmentSaveSnapshot(owner));Assert.assertEquals(pending,queues())
    }
    @Test fun ownerReplacementAtFinalFenceRollsBackTheWholeBatch()=runBlocking {
        seed();val before=store.transactionInvestmentSaveSnapshot(owner);val pending=queues();var checks=0
        val switching=RoomLocalStore(db,currentBillOwner={checks++;if(checks<4)owner else UserId("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")})
        val error=runCatching{switching.commitTransactionInvestmentSave(before,consent(before),device,now)}.exceptionOrNull()
        Assert.assertTrue(error.toString(),error is CancellationException);Assert.assertEquals(4,checks)
        Assert.assertEquals(before,store.transactionInvestmentSaveSnapshot(owner));Assert.assertEquals(pending,queues())
    }
    @Test fun orphanDerivedQueueCannotBeOverwrittenByANewPrimaryTransaction()=runBlocking {
        seed();val before=store.transactionInvestmentSaveSnapshot(owner);val accepted=consent(before)
        val posting=planTransactionInvestmentSave(before,accepted,device,now).mutations.single{it.first.entity==CloudEntity.INVESTMENT_POSTING.table}
        store.commitMutation(posting.first,posting.second)
        db.openHelper.writableDatabase.execSQL("DELETE FROM cloud_records WHERE owner_user_id = ? AND entity = ? AND record_id = ?",arrayOf(owner.value,posting.first.entity,posting.first.id))
        val current=store.transactionInvestmentSaveSnapshot(owner);val pending=queues()
        val error=runCatching{store.commitTransactionInvestmentSave(current,accepted,device,now)}.exceptionOrNull()
        Assert.assertTrue(error.toString(),error is IllegalArgumentException);Assert.assertEquals(current,store.transactionInvestmentSaveSnapshot(owner));Assert.assertEquals(pending,queues())
    }
    @Test fun completedCreationReturnsStoredRecordWithoutRewritingEitherQueue()=runBlocking {
        seed();val before=store.transactionInvestmentSaveSnapshot(owner);val accepted=consent(before)
        val saved=store.commitTransactionInvestmentSave(before,accepted,device,now);val current=store.transactionInvestmentSaveSnapshot(owner);val pending=queues()
        Assert.assertEquals(saved,store.commitTransactionInvestmentSave(current,accepted,device,"2026-10-22T00:01:00Z"))
        Assert.assertEquals(current,store.transactionInvestmentSaveSnapshot(owner));Assert.assertEquals(pending,queues())
    }
    @Test fun actualFinanceRepositoryPreflightIsReadOnlyAndConfirmedSaveUsesTheAtomicBoundary()=runBlocking {
        seed();val repository=OfflineFirstFinanceRepository(store);val before=store.transactionInvestmentSaveSnapshot(owner);val pending=queues()
        val error=repository.prepareTransactionWithInvestmentFunds(owner,request(),device,now).exceptionOrNull()
        Assert.assertTrue(error.toString(),error is InvestmentFundUsageConfirmationRequired)
        Assert.assertEquals(before,store.transactionInvestmentSaveSnapshot(owner));Assert.assertEquals(pending,queues())
        val accepted=request().copy(consent=(error as InvestmentFundUsageConfirmationRequired).review.consent)
        val preview=repository.prepareTransactionWithInvestmentFunds(owner,accepted,device,now).getOrThrow();Assert.assertEquals(2,preview.mutations.size)
        Assert.assertEquals(before,store.transactionInvestmentSaveSnapshot(owner))
        Assert.assertEquals(preview.record,repository.saveTransactionWithInvestmentFunds(owner,accepted,device,now).getOrThrow())
        Assert.assertTrue(repository.prepareTransactionWithInvestmentFunds(owner,accepted,device,now).getOrThrow().mutations.isEmpty())
    }
    @Test fun actualFinanceRepositoryCannotUseGenericWritesWhenAtomicStoreIsUnavailable()=runBlocking {
        seed();val before=store.transactionInvestmentSaveSnapshot(owner);val pending=queues()
        val unsupported=object:LocalStore by store {
            override suspend fun commitTransactionInvestmentSave(expected:TransactionInvestmentSaveSnapshot,request:TransactionInvestmentSaveRequest,deviceId:String,now:String,statementZone:java.time.ZoneId):LedgerTransactionRecord =
                super<LocalStore>.commitTransactionInvestmentSave(expected,request,deviceId,now,statementZone)
        }
        val result=OfflineFirstFinanceRepository(unsupported).saveTransactionWithInvestmentFunds(owner,consent(before),device,now)
        Assert.assertTrue(result.exceptionOrNull() is UnsupportedOperationException)
        Assert.assertEquals(before,store.transactionInvestmentSaveSnapshot(owner));Assert.assertEquals(pending,queues())
    }
    @Test fun oneRoomObserverNeverSeesThePrimaryWithoutItsDerivedUsage()=runBlocking {
        seed();val before=store.transactionInvestmentSaveSnapshot(owner);val started=CompletableDeferred<Unit>()
        val collected=async(start=CoroutineStart.UNDISPATCHED) {
            store.observeInvestmentCashSnapshot(owner).distinctUntilChanged().onEach{started.complete(Unit)}.take(2).toList()
        }
        withTimeout(5000){started.await()}
        store.commitTransactionInvestmentSave(before,consent(before),device,now)
        val snapshots=withTimeout(5000){collected.await()}
        Assert.assertEquals(2,snapshots.size)
        Assert.assertTrue(snapshots.first().rows.none{it.entity==CloudEntity.LEDGER_TRANSACTION.table && it.id==id(20)})
        snapshots.forEach{snapshot->
            val hasPrimary=snapshot.rows.any{it.entity==CloudEntity.LEDGER_TRANSACTION.table && it.id==id(20)}
            val hasUsage=snapshot.rows.any{it.entity==CloudEntity.INVESTMENT_POSTING.table && it.id==investmentLedgerIdentity(id(20),"cash-consumption-booked")}
            Assert.assertEquals(hasPrimary,hasUsage)
        }
        Assert.assertTrue(snapshots.last().rows.any{it.entity==CloudEntity.LEDGER_TRANSACTION.table && it.id==id(20)})
    }
    @Test fun actualJobCancellationAtTheLastFenceRollsBackEveryRowAndQueue()=runBlocking {
        seed();val before=store.transactionInvestmentSaveSnapshot(owner);val pending=queues();var checks=0;var target:Job?=null
        val cancelling=RoomLocalStore(db,currentBillOwner={checks++;if(checks==4)target!!.cancel(CancellationException("cancel at last owner fence"));owner})
        val save=async(start=CoroutineStart.LAZY){cancelling.commitTransactionInvestmentSave(before,consent(before),device,now)}
        target=save;save.start()
        Assert.assertTrue(runCatching{save.await()}.exceptionOrNull() is CancellationException)
        Assert.assertEquals(4,checks);Assert.assertEquals(before,store.transactionInvestmentSaveSnapshot(owner));Assert.assertEquals(pending,queues())
    }
    @Test fun orphanPrimaryQueueCannotBeReusedAsAStableCreationIdentity()=runBlocking {
        seed();val before=store.transactionInvestmentSaveSnapshot(owner);val accepted=consent(before)
        val primary=planTransactionInvestmentSave(before,accepted,device,now).mutations.single{it.first.entity==CloudEntity.LEDGER_TRANSACTION.table}
        store.commitMutation(primary.first,primary.second)
        db.openHelper.writableDatabase.execSQL("DELETE FROM cloud_records WHERE owner_user_id = ? AND entity = ? AND record_id = ?",arrayOf(owner.value,primary.first.entity,primary.first.id))
        val current=store.transactionInvestmentSaveSnapshot(owner);val pending=queues()
        val error=runCatching{store.commitTransactionInvestmentSave(current,accepted,device,now)}.exceptionOrNull()
        Assert.assertTrue(error.toString(),error is IllegalArgumentException)
        Assert.assertEquals(current,store.transactionInvestmentSaveSnapshot(owner));Assert.assertEquals(pending,queues())
    }
}
