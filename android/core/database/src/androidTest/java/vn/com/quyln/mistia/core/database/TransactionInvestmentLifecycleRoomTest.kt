package vn.com.quyln.mistia.core.database

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import kotlinx.serialization.json.*
import org.junit.*
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.model.*

@RunWith(AndroidJUnit4::class)
class TransactionInvestmentLifecycleRoomTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val device="44444444-4444-4444-8444-444444444444"
    private val now="2026-10-23T00:00:00Z"
    private val at="2026-10-23T00:01:00Z"
    private fun id(n:Int)=java.util.UUID(0,n.toLong()).toString()
    private lateinit var db:MistiaDatabase
    private lateinit var store:RoomLocalStore
    @Before fun open(){db=Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(),MistiaDatabase::class.java).allowMainThreadQueries().build();store=RoomLocalStore(db,currentBillOwner={owner})}
    @After fun close(){db.close()}
    private suspend fun seed() {
        val wallet=WalletDraft(id=id(1),name="Cash",kind=WalletKind.CASH,currencyCode="JPY",openingBalanceMinor=100).toMutation(owner,null,device,now).record
        val parent=CategoryDraft(id=id(30),name="Parent",kind=TransactionCategoryKind.EXPENSE,hierarchyRole=CategoryHierarchyRole.PARENT).toMutation(owner,null,null,device,now).record
        val child=CategoryDraft(id=id(31),name="Child",kind=TransactionCategoryKind.EXPENSE,hierarchyRole=CategoryHierarchyRole.CHILD,parentCategoryId=parent.id).toMutation(owner,null,parent,device,now).record
        val posting=CloudRecord(CloudEntity.INVESTMENT_POSTING.table,id(10),owner.value,buildJsonObject {
            put("id",id(10));put("user_id",owner.value);put("sync_version",0L);put("deleted_at",JsonNull);put("created_at",now);put("updated_at",now)
            put("event_id",id(11));put("ledger_transaction_id",id(11));put("wallet_id",id(1));put("role_raw_value","cashAccrual");put("cash_bucket_raw_value","booked");put("cash_origin_raw_value","derived")
            put("amount_minor",60L);put("accounting_amount_minor",60L);put("currency_code","JPY");put("accounting_currency_code","JPY");put("occurred_at","2026-10-23T00:00:01Z")
        },now,null,0)
        for(row in listOf(wallet,parent.toCloudRecord(),child.toCloudRecord(),posting))store.commitMutation(row,PendingMutation(CloudEntity.fromTable(row.entity)!!,row.id,owner.value,MutationKind.UPSERT,row.payload,now,row.syncVersion,device))
        val draft=TransactionDraft(primaryKind=TransactionPrimaryKind.EXPENSE,title="Expense",amountMinor=70,occurredAt="2026-10-23T00:00:02Z",sourceWalletId=id(1),categoryId=id(31))
        val request=TransactionInvestmentSaveRequest(draft,TransactionCreationIdentity(id(20),now),null,"Adjustment","JPY")
        val snapshot=store.transactionInvestmentSaveSnapshot(owner)
        val review=(runCatching{planTransactionInvestmentSave(snapshot,request,device,now)}.exceptionOrNull() as InvestmentFundUsageConfirmationRequired).review
        store.commitTransactionInvestmentSave(snapshot,request.copy(consent=review.consent),device,now)
    }
    private suspend fun snapshot()=store.transactionInvestmentSaveSnapshot(owner)
    private suspend fun queues()=TransactionInvestmentSaveSnapshot.entities.associateWith{store.pendingMutations(owner,it,Long.MAX_VALUE)}
    private fun request(s:TransactionInvestmentSaveSnapshot,action:TransactionLifecycleAction=TransactionLifecycleAction.ARCHIVE)=TransactionInvestmentLifecycleRequest(
        LedgerTransactionRecord.fromCloudRecord(s.recordsByEntity.getValue(CloudEntity.LEDGER_TRANSACTION).single{it.id==id(20)}),action,at,"JPY","Adjustment",null)
    private fun confirmed(s:TransactionInvestmentSaveSnapshot,r:TransactionInvestmentLifecycleRequest=request(s))=r.copy(consent=
        (runCatching{planTransactionInvestmentLifecycle(s,r,device,at)}.exceptionOrNull() as InvestmentFundUsageConfirmationRequired).review.consent)
    @Test fun archiveRestoreDeleteAndKnownReplaysCommitTheirPrimaryDerivedAndQueuesTogether()=runBlocking {
        seed();var before=snapshot();var r=confirmed(before)
        Assert.assertTrue(store.commitTransactionInvestmentLifecycle(before,r,device,at).isArchived)
        var current=snapshot();var pending=queues();Assert.assertEquals(2,pending.values.flatten().count{it.mutation.modifiedAt==at})
        Assert.assertEquals(at,current.recordsByEntity.getValue(CloudEntity.INVESTMENT_POSTING).single{it.id==investmentLedgerIdentity(id(20),"cash-consumption-booked")}.deletedAt)
        Assert.assertTrue(store.commitTransactionInvestmentLifecycle(current,r,device,at).isArchived);Assert.assertEquals(current,snapshot());Assert.assertEquals(pending,queues())
        before=current;r=confirmed(before,request(before,TransactionLifecycleAction.RESTORE))
        Assert.assertFalse(store.commitTransactionInvestmentLifecycle(before,r,device,at).isArchived)
        before=snapshot();store.commitTransactionInvestmentLifecycle(before,confirmed(before),device,at)
        before=snapshot();val deletion=request(before,TransactionLifecycleAction.DELETE)
        Assert.assertEquals(at,store.commitTransactionInvestmentLifecycle(before,deletion,device,at).deletedAt)
        current=snapshot();pending=queues();Assert.assertEquals(at,store.commitTransactionInvestmentLifecycle(current,deletion,device,at).deletedAt)
        Assert.assertEquals(current,snapshot());Assert.assertEquals(pending,queues())
    }
    @Test fun unconfirmedArchiveCannotWriteEvenItsPrimaryOrQueue()=runBlocking {
        seed();val before=snapshot();val pending=queues()
        val error=runCatching{store.commitTransactionInvestmentLifecycle(before,request(before),device,at)}.exceptionOrNull()
        Assert.assertTrue(error.toString(),error is InvestmentFundUsageConfirmationRequired)
        Assert.assertEquals(before,snapshot());Assert.assertEquals(pending,queues())
    }
    @Test fun aFailureAtTheLastDerivedOutboxRollsBackPrimaryAndBothQueues()=runBlocking {
        seed();val before=snapshot();val pending=queues();val key=investmentLedgerIdentity(id(20),"cash-consumption-booked")
        db.openHelper.writableDatabase.execSQL("CREATE TRIGGER lifecycle_queue_abort BEFORE INSERT ON sync_outbox WHEN NEW.record_id = '$key' BEGIN SELECT RAISE(ABORT, 'reject derived queue'); END")
        Assert.assertTrue(runCatching{store.commitTransactionInvestmentLifecycle(before,confirmed(before),device,at)}.isFailure)
        Assert.assertEquals(before,snapshot());Assert.assertEquals(pending,queues())
    }
    @Test fun financialSourceRaceCannotUseThePreviousSevenEntityRead()=runBlocking {
        seed();val before=snapshot();val accepted=confirmed(before)
        val wallet=before.recordsByEntity.getValue(CloudEntity.LEDGER_WALLET).single().let{it.copy(payload=JsonObject(it.payload+("opening_balance_minor" to JsonPrimitive(101L))))}
        store.commitMutation(wallet,PendingMutation(CloudEntity.LEDGER_WALLET,wallet.id,owner.value,MutationKind.UPSERT,wallet.payload,now,wallet.syncVersion,device))
        val current=snapshot();val pending=queues()
        Assert.assertTrue(runCatching{store.commitTransactionInvestmentLifecycle(before,accepted,device,at)}.exceptionOrNull() is IllegalArgumentException)
        Assert.assertEquals(current,snapshot());Assert.assertEquals(pending,queues())
    }
    @Test fun actualCallerCancellationAtLastFenceRollsBackEveryLifecycleEffect()=runBlocking {
        seed();val before=snapshot();val pending=queues();var checks=0;var target:Job?=null
        val cancelling=RoomLocalStore(db,currentBillOwner={checks++;if(checks==4)target!!.cancel(CancellationException("last lifecycle fence"));owner})
        val save=async(start=CoroutineStart.LAZY){cancelling.commitTransactionInvestmentLifecycle(before,confirmed(before),device,at)}
        target=save;save.start();Assert.assertTrue(runCatching{save.await()}.exceptionOrNull() is CancellationException)
        Assert.assertEquals(4,checks);Assert.assertEquals(before,snapshot());Assert.assertEquals(pending,queues())
    }
    @Test fun actualRepositoryPreparationIsReadOnlyAndUnsupportedStoreCannotFallBackToGenericWrites()=runBlocking {
        seed();val before=snapshot();val pending=queues();val repo=OfflineFirstFinanceRepository(store)
        val error=repo.prepareTransactionLifecycle(owner,request(before),device,at).exceptionOrNull()
        Assert.assertTrue(error.toString(),error is InvestmentFundUsageConfirmationRequired);Assert.assertEquals(before,snapshot());Assert.assertEquals(pending,queues())
        val unsupported=object:LocalStore by store {
            override suspend fun commitTransactionInvestmentLifecycle(expected:TransactionInvestmentSaveSnapshot,request:TransactionInvestmentLifecycleRequest,deviceId:String,now:String,statementZone:java.time.ZoneId):LedgerTransactionRecord =
                super<LocalStore>.commitTransactionInvestmentLifecycle(expected,request,deviceId,now,statementZone)
        }
        val accepted=confirmed(before)
        Assert.assertTrue(OfflineFirstFinanceRepository(unsupported).saveTransactionLifecycle(owner,accepted,device,at).exceptionOrNull() is UnsupportedOperationException)
        Assert.assertEquals(before,snapshot());Assert.assertEquals(pending,queues())
        Assert.assertTrue(repo.saveTransactionLifecycle(owner,accepted,device,at).getOrThrow().isArchived)
    }
    @Test fun aRealRoomObserverNeverSeesArchiveWithoutItsDerivedRestoration()=runBlocking {
        seed();val before=snapshot();val started=CompletableDeferred<Unit>()
        val collected=async(start=CoroutineStart.UNDISPATCHED) {
            store.observeInvestmentCashSnapshot(owner).distinctUntilChanged().onEach{started.complete(Unit)}.take(2).toList()
        }
        withTimeout(5000){started.await()}
        store.commitTransactionInvestmentLifecycle(before,confirmed(before),device,at)
        val values=withTimeout(5000){collected.await()};Assert.assertEquals(2,values.size)
        for(value in values) {
            val primary=value.rows.single{it.entity==CloudEntity.LEDGER_TRANSACTION.table && it.id==id(20)}
            val usage=value.rows.single{it.entity==CloudEntity.INVESTMENT_POSTING.table && it.id==investmentLedgerIdentity(id(20),"cash-consumption-booked")}
            Assert.assertEquals(primary.payload.financeRawArchived(),usage.deletedAt!=null)
        }
        Assert.assertEquals(true,values.last().rows.single{it.entity==CloudEntity.LEDGER_TRANSACTION.table && it.id==id(20)}.payload.financeRawArchived())
    }
    @Test fun ownerReplacementAtTheLastFenceRollsBackArchiveAndDerivedQueues()=runBlocking {
        seed();val before=snapshot();val pending=queues();var checks=0
        val changing=RoomLocalStore(db,currentBillOwner={checks++;if(checks>=4)UserId(id(99))else owner})
        val error=runCatching{changing.commitTransactionInvestmentLifecycle(before,confirmed(before),device,at)}.exceptionOrNull()
        Assert.assertTrue(error.toString(),error is CancellationException);Assert.assertEquals(4,checks)
        Assert.assertEquals(before,snapshot());Assert.assertEquals(pending,queues())
    }
    @Test fun restoringCannotRecreateAConsumptionIdentityWhoseQueueOutlivedItsMissingRow()=runBlocking {
        seed();var before=snapshot();store.commitTransactionInvestmentLifecycle(before,confirmed(before),device,at)
        db.openHelper.writableDatabase.execSQL("DELETE FROM cloud_records WHERE owner_user_id = ? AND entity = ? AND record_id = ?",arrayOf(owner.value,CloudEntity.INVESTMENT_POSTING.table,investmentLedgerIdentity(id(20),"cash-consumption-booked")))
        before=snapshot();val pending=queues();val restore=confirmed(before,request(before,TransactionLifecycleAction.RESTORE))
        val error=runCatching{store.commitTransactionInvestmentLifecycle(before,restore,device,at)}.exceptionOrNull()
        Assert.assertTrue(error.toString(),error is IllegalArgumentException)
        Assert.assertEquals(before,snapshot());Assert.assertEquals(pending,queues())
    }
}
