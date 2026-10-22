package vn.com.quyln.mistia.core.database

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.math.BigInteger
import java.util.Collections
import kotlinx.coroutines.*
import kotlinx.serialization.json.*
import org.junit.*
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.model.*

@RunWith(AndroidJUnit4::class)
class InvestmentCashReconciliationRoomTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other=UserId("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")
    private val device="44444444-4444-4444-8444-444444444444"
    private fun id(n:Int)=java.util.UUID(0,n.toLong()).toString()
    private val now="2026-10-22T00:00:00Z"
    private lateinit var db:MistiaDatabase
    private lateinit var store:RoomLocalStore
    private var active=owner
    @Before fun open(){db=Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(),MistiaDatabase::class.java).allowMainThreadQueries().build();store=RoomLocalStore(db,currentBillOwner={active})}
    @After fun close(){db.close()}
    private fun row(entity:CloudEntity,key:Int,fields:JsonObject)=CloudRecord(entity.table,id(key),owner.value,JsonObject(buildJsonObject {
        put("id",id(key));put("user_id",owner.value);put("created_at",now);put("updated_at",now);put("deleted_at",JsonNull);put("sync_version",9007199254740993L);put("future_field","keep")
    }+fields),now,null,9007199254740993L)
    private fun rows():List<CloudRecord> {
        fun wallet(key:Int,opening:Long)=WalletDraft(id=id(key),name="Wallet$key",kind=WalletKind.CASH,currencyCode="JPY",openingBalanceMinor=opening).toMutation(owner,null,device,now).record
        val system=wallet(99,0).let{it.copy(id=investmentSystemWalletId(owner),payload=JsonObject(it.payload+buildJsonObject{put("id",investmentSystemWalletId(owner));put("kind_raw_value","investment");put("system_purpose_raw_value","investmentProfit");put("investment_linked_wallet_id",id(2))}))}
        fun cash(key:Int,wallet:Int,amount:Long)=row(CloudEntity.INVESTMENT_POSTING,key,buildJsonObject {
            put("event_id",id(key+100));put("wallet_id",id(wallet));put("ledger_transaction_id",id(key+100));put("role_raw_value","cashAccrual");put("cash_bucket_raw_value","booked");put("cash_origin_raw_value","derived")
            put("amount_minor",amount);put("currency_code","JPY");put("accounting_amount_minor",amount);put("accounting_currency_code","JPY");put("occurred_at",now)
        })
        return listOf(system,wallet(1,150),wallet(2,0),wallet(3,200),cash(10,1,50),cash(11,3,60),row(CloudEntity.INVESTMENT_TRADE,30,buildJsonObject{put("realized_profit_loss_minor",110L);put("accounting_currency_code","JPY")}))
    }
    private fun mutation(row:CloudRecord)=row to PendingMutation(CloudEntity.fromTable(row.entity)!!,row.id,row.ownerUserId,MutationKind.UPSERT,row.payload,now,row.syncVersion,device)
    private suspend fun seed()=store.commitMutations(rows().map(::mutation))
    private suspend fun snapshot()=store.investmentCashSnapshot(owner)
    private suspend fun queues()=InvestmentCashReadSnapshot.entities.associateWith{store.pendingMutations(owner,it,Long.MAX_VALUE)}
    private suspend fun request()=InvestmentCashReconciliationRequest(readInvestmentCashReconciliation(snapshot()),listOf(InvestmentCashReconciliationTransfer(id(20),id(1),80),InvestmentCashReconciliationTransfer(id(21),id(3),100)),now,now,"Reconciliation",true)
    @Test fun completeSixRowBatchAndQueuesMoveActualCashOnceAndReplayWithoutWriting()=runBlocking {
        seed();val before=snapshot();val r=request();val repo=OfflineFirstInvestmentRepository(store)
        repo.reconcileCash(owner,r,device,now).getOrThrow();val after=snapshot();val pending=queues()
        Assert.assertEquals(before.rows.size+6,after.rows.size);Assert.assertEquals(before.rows.size+6,pending.values.sumOf{it.size})
        val balances=financeWalletBalancesRaw(owner,after.rows.filter{it.entity==CloudEntity.LEDGER_TRANSACTION.table},after.rows.filter{it.entity==CloudEntity.LEDGER_WALLET.table})!!
        Assert.assertEquals(BigInteger.valueOf(70),balances[id(1)]);Assert.assertEquals(BigInteger.valueOf(180),balances[id(2)]);Assert.assertEquals(BigInteger.valueOf(100),balances[id(3)])
        Assert.assertEquals(BigInteger.valueOf(110),investmentCashFinancialView(after,"JPY").availableMinor)
        Assert.assertEquals(before.rows,after.rows.filter{row->before.rows.any{it.entity==row.entity && it.id==row.id}})
        repo.reconcileCash(owner,r,device,now).getOrThrow();Assert.assertEquals(after,snapshot());Assert.assertEquals(pending,queues())
    }
    @Test fun lastPostingFailureRollsBackBothTransfersAndEveryQueuedMutation()=runBlocking {
        seed();val before=snapshot();val pending=queues();val r=request()
        db.openHelper.writableDatabase.execSQL("CREATE TRIGGER reject_reconciliation BEFORE INSERT ON cloud_records WHEN NEW.entity = 'investment_wallet_postings' AND NEW.record_id = '"+investmentLedgerIdentity(id(21),"linked-cash-posting")+"' BEGIN SELECT RAISE(ABORT, 'synthetic reconciliation failure'); END")
        val result=OfflineFirstInvestmentRepository(store).reconcileCash(owner,r,device,now)
        Assert.assertTrue(result.exceptionOrNull().toString().contains("synthetic reconciliation failure"));Assert.assertEquals(before,snapshot());Assert.assertEquals(pending,queues())
    }
    @Test fun wholeFourEntityCasRejectsChangedTradeWithoutApplyingAnUnreviewedBatch()=runBlocking {
        seed();val before=snapshot();val r=request();val trade=before.rows.single{it.entity==CloudEntity.INVESTMENT_TRADE.table}.let{it.copy(payload=JsonObject(it.payload+("realized_profit_loss_minor" to JsonPrimitive(111L))))}
        store.commitMutations(listOf(mutation(trade)));val current=snapshot();val pending=queues()
        Assert.assertFalse(store.commitInvestmentCashReconciliation(before,r,device,now));Assert.assertEquals(current,snapshot());Assert.assertEquals(pending,queues())
    }
    @Test fun currentOwnerChangeBeforeOrAfterAllWritesLeavesBothPartitionsUntouched()=runBlocking {
        seed();val before=snapshot();val pending=queues();val r=request();active=other
        Assert.assertTrue(runCatching{store.commitInvestmentCashReconciliation(before,r,device,now)}.exceptionOrNull() is CancellationException)
        active=owner;var checks=0;val switching=RoomLocalStore(db,currentBillOwner={checks++;if(checks>=4)other else owner})
        Assert.assertTrue(runCatching{switching.commitInvestmentCashReconciliation(before,r,device,now)}.exceptionOrNull() is CancellationException)
        Assert.assertEquals(4,checks);Assert.assertEquals(before,snapshot());Assert.assertEquals(pending,queues())
        Assert.assertTrue(InvestmentCashReadSnapshot.entities.all{store.recordsIncludingDeleted(other,it.table).isEmpty()})
    }
    @Test fun sameIdentityForeignRowsAndQueuesNeverCountAsOwnedReplayOrChangeOnCommit()=runBlocking {
        seed();val r=request();val foreign=planInvestmentCashReconciliation(snapshot(),r,device,now).mutations.map{it.first}.map{it.copy(ownerUserId=other.value,payload=JsonObject(it.payload+("user_id" to JsonPrimitive(other.value))))}
        store.commitMutations(foreign.map(::mutation));val foreignPending=InvestmentCashReadSnapshot.entities.associateWith{store.pendingMutations(other,it,Long.MAX_VALUE)}
        OfflineFirstInvestmentRepository(store).reconcileCash(owner,r,device,now).getOrThrow()
        Assert.assertEquals(foreign.toSet(),InvestmentCashReadSnapshot.entities.flatMap{store.recordsIncludingDeleted(other,it.table)}.toSet())
        Assert.assertEquals(foreignPending,InvestmentCashReadSnapshot.entities.associateWith{store.pendingMutations(other,it,Long.MAX_VALUE)})
    }
    @Test fun observersNeverSeeOneTransferOrOneFinancialHalfOfTheBatch()=runBlocking {
        seed();val r=request();val observed=Collections.synchronizedList(mutableListOf<Int>())
        val job=launch(Dispatchers.Unconfined,start=CoroutineStart.UNDISPATCHED){store.observeInvestmentCashSnapshot(owner).collect{read->observed.add(read.rows.count{row->row.entity==CloudEntity.LEDGER_TRANSACTION.table || row.payload.financeRawString("role_raw_value")=="cashReconciliation"})}}
        try {
            withTimeout(5000){while(observed.isEmpty())delay(5)}
            OfflineFirstInvestmentRepository(store).reconcileCash(owner,r,device,now).getOrThrow()
            withTimeout(5000){while(synchronized(observed){6 !in observed})delay(5)}
        }finally{job.cancelAndJoin()}
        Assert.assertTrue(synchronized(observed){observed.all{it==0 || it==6}})
    }
    @Test fun orphanQueuedIdentityCannotBeOverwrittenByAReconciliationWithNoMatchingLocalRow()=runBlocking {
        seed();val r=request();val planned=planInvestmentCashReconciliation(snapshot(),r,device,now).mutations.first()
        store.commitMutations(listOf(planned))
        db.openHelper.writableDatabase.execSQL("DELETE FROM cloud_records WHERE owner_user_id = ? AND entity = ? AND record_id = ?",arrayOf(owner.value,planned.first.entity,planned.first.id))
        val before=snapshot();val pending=queues()
        val result=OfflineFirstInvestmentRepository(store).reconcileCash(owner,r,device,now)
        Assert.assertEquals(InvestmentCashReconciliationError.STALE_RECORD,(result.exceptionOrNull() as? InvestmentCashReconciliationException)?.reason)
        Assert.assertEquals(before,snapshot());Assert.assertEquals(pending,queues())
    }
}
