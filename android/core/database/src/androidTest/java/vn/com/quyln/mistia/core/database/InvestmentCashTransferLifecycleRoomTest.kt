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
class InvestmentCashTransferLifecycleRoomTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other=UserId("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")
    private val linked="22222222-2222-4222-8222-222222222222"
    private val selected="33333333-3333-4333-8333-333333333333"
    private val device="44444444-4444-4444-8444-444444444444"
    private val event="55555555-5555-4555-8555-555555555555"
    private val profitId="66666666-6666-4666-8666-666666666666"
    private val cashId="77777777-7777-4777-8777-777777777777"
    private val now="2026-10-22T00:00:00Z"
    private fun wallet(id:String)=WalletDraft(id=id,name="Wallet",kind=WalletKind.CASH,currencyCode="VND",openingBalanceMinor=10000).toMutation(owner,null,device,now).record
    private fun rows():List<CloudRecord> {
        val system=wallet(investmentSystemWalletId(owner)).let{it.copy(syncVersion=9007199254740993L,payload=JsonObject(it.payload+buildJsonObject {
            put("kind_raw_value","investment");put("system_purpose_raw_value","investmentProfit");put("investment_linked_wallet_id",linked);put("opening_balance_minor",0L);put("sync_version",9007199254740993L);put("future_field","preserve")
        }))}
        fun row(entity:CloudEntity,id:String,fields:JsonObject)=CloudRecord(entity.table,id,owner.value,JsonObject(fields+buildJsonObject {
            put("id",id);put("user_id",owner.value);put("created_at",now);put("updated_at",now);put("sync_version",0L);put("deleted_at",JsonNull)
        }),now,null,0)
        return listOf(system,wallet(linked),wallet(selected),row(CloudEntity.INVESTMENT_TRADE,profitId,buildJsonObject{put("realized_profit_loss_minor",800L);put("accounting_currency_code","VND")}),
            row(CloudEntity.INVESTMENT_POSTING,cashId,buildJsonObject {
                put("wallet_id",linked);put("role_raw_value","cashAccrual");put("cash_bucket_raw_value","booked");put("cash_origin_raw_value","derived")
                put("amount_minor",300L);put("currency_code","VND");put("accounting_amount_minor",300L);put("accounting_currency_code","VND")
            }))
    }
    private fun mutation(raw:CloudRecord)=raw to PendingMutation(CloudEntity.fromTable(raw.entity)!!,raw.id,raw.ownerUserId,MutationKind.UPSERT,raw.payload,now,raw.syncVersion,device)
    private fun request(withdraw:Boolean=false,otherWallet:Boolean=false):InvestmentCashTransferRequest {
        val records=rows();fun wallet(id:String)=investmentLinkedWalletRecord(records.single{it.id==id})
        val direction=if(withdraw)InvestmentCashTransferDirection.WITHDRAWAL else InvestmentCashTransferDirection.DEPOSIT
        val amount=if(withdraw)300L else 500L
        val target=if(otherWallet)selected else linked
        return InvestmentCashTransferRequest(wallet(investmentSystemWalletId(owner)),wallet(linked),wallet(target),
            InvestmentCashTransferDraft(event,direction,target,amount," Test note ","2026-10-20T12:34:00Z",now),
            InvestmentCashTransferPreview(direction,amount,amount,java.math.BigInteger.valueOf(800),java.math.BigInteger.valueOf(300),java.math.BigInteger.valueOf(300),java.math.BigInteger.valueOf(if(withdraw || !otherWallet)9700 else 10000)),"Transfer")
    }

    private lateinit var db:MistiaDatabase
    private lateinit var store:RoomLocalStore
    private var active=owner
    @Before fun setup(){
        db=Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(),MistiaDatabase::class.java).allowMainThreadQueries().build()
        store=RoomLocalStore(db,currentBillOwner={active})
    }
    @After fun close(){db.close()}
    private suspend fun prepare(){store.commitMutations(rows().map(::mutation))}
    private suspend fun snapshot()=store.investmentCashSnapshot(owner)
    private suspend fun queues()=InvestmentCashReadSnapshot.entities.associateWith{store.pendingMutations(owner,it,Long.MAX_VALUE)}
    private fun repo(source:LocalStore=store)=OfflineFirstInvestmentRepository(source)

    private val later="2026-10-22T01:00:00Z"
    private suspend fun deposited(){prepare();repo().saveCashTransfer(owner,request(),device,now).getOrThrow()}
    private suspend fun change(delete:Boolean=false):InvestmentCashTransferLifecycleRequest {
        val read=readInvestmentCashTransferLifecycle(snapshot(),event);val view=read.baseline
        val draft=if(delete)read.event.draft else read.event.draft.copy(amountMinor=400,note="Edited")
        val review=InvestmentCashTransferRequest(view.system,view.linked,view.selected,draft,view.preview.copy(requestedMinor=draft.amountMinor),"Edited transfer")
        return if(delete)InvestmentCashTransferLifecycleRequest.Delete(read.event,review) else InvestmentCashTransferLifecycleRequest.Save(read.event,review)
    }
    @Test fun editingThePairIsAtomicKeepsOriginalIdentitiesAndReplaysWithoutCompactingQueuesAgain()=runBlocking {
        deposited();val before=snapshot();val request=change();repo().changeCashTransfer(owner,request,device,later).getOrThrow()
        val current=snapshot();val pending=queues();Assert.assertEquals(7,current.rows.size);Assert.assertEquals(7,pending.values.sumOf{it.size})
        Assert.assertEquals(400L,current.rows.single{it.id==event}.payload.financeRawLong("amount_minor"));Assert.assertEquals(BigInteger.valueOf(700),investmentCashFinancialView(current,"VND").availableMinor)
        Assert.assertEquals(before.rows.filter{it.id!=event && it.id!=investmentLedgerIdentity(event,"cash-transfer-posting")},current.rows.filter{it.id!=event && it.id!=investmentLedgerIdentity(event,"cash-transfer-posting")})
        Assert.assertEquals(9007199254740993L,current.rows.single{it.id==investmentSystemWalletId(owner)}.syncVersion)
        repo().changeCashTransfer(owner,request,device,later).getOrThrow();Assert.assertEquals(current,snapshot());Assert.assertEquals(pending,queues())
        Assert.assertTrue(InvestmentCashReadSnapshot.entities.all{store.recordsIncludingDeleted(other,it.table).isEmpty()})
    }
    @Test fun deletingThePairAtomicallyTombstonesOwnedRowsAndQueuesDeleteWithoutChangingWalletOpenings()=runBlocking {
        deposited();val before=snapshot();val request=change(delete=true);repo().changeCashTransfer(owner,request,device,later).getOrThrow()
        val current=snapshot();val pending=queues();val ids=setOf(event,investmentLedgerIdentity(event,"cash-transfer-posting"))
        Assert.assertTrue(current.rows.filter{it.id in ids}.all{it.deletedAt==later});Assert.assertEquals(2,current.rows.count{it.id in ids})
        val eventQueues=pending.values.flatten().map{it.mutation}.filter{it.recordId in ids}
        Assert.assertEquals(2,eventQueues.size);Assert.assertTrue(eventQueues.all{it.kind==MutationKind.DELETE})
        Assert.assertEquals(BigInteger.valueOf(300),investmentCashFinancialView(current,"VND").availableMinor)
        Assert.assertEquals(before.rows.filter{it.entity==CloudEntity.LEDGER_WALLET.table},current.rows.filter{it.entity==CloudEntity.LEDGER_WALLET.table})
        repo().changeCashTransfer(owner,request,device,later).getOrThrow();Assert.assertEquals(current,snapshot());Assert.assertEquals(pending,queues())
    }
    @Test fun lastPostingFailureRollsBackBothEditAndDeletionWithEveryOriginalOutboxRow()=runBlocking {
        deposited();val before=snapshot();val pending=queues()
        db.openHelper.writableDatabase.execSQL("CREATE TRIGGER reject_lifecycle BEFORE INSERT ON cloud_records WHEN NEW.entity = 'investment_wallet_postings' AND NEW.record_id = '"+investmentLedgerIdentity(event,"cash-transfer-posting")+"' BEGIN SELECT RAISE(ABORT, 'synthetic lifecycle failure'); END")
        for(delete in listOf(false,true)) {
            val result=repo().changeCashTransfer(owner,change(delete),device,later)
            Assert.assertTrue(result.exceptionOrNull().toString().contains("synthetic lifecycle failure"));Assert.assertEquals(before,snapshot());Assert.assertEquals(pending,queues())
        }
    }
    @Test fun currentOwnerReplacementBeforeCommitCancelsWithoutChangingAnyPartition()=runBlocking {
        deposited();val before=snapshot();val pending=queues();val request=change();active=other
        val result=runCatching{store.commitInvestmentCashTransferLifecycle(before,request,device,later)}
        Assert.assertTrue(result.exceptionOrNull() is CancellationException);active=owner;Assert.assertEquals(before,snapshot());Assert.assertEquals(pending,queues())
    }
    @Test fun ownerReplacementAfterBothFinancialWritesRollsBackBeforeReturningSuccess()=runBlocking {
        deposited();val before=snapshot();val pending=queues();val request=change();var checks=0
        val fenced=RoomLocalStore(db,currentBillOwner={checks++;if(checks>=4)other else owner})
        val result=runCatching{fenced.commitInvestmentCashTransferLifecycle(before,request,device,later)}
        Assert.assertTrue(result.exceptionOrNull() is CancellationException);Assert.assertEquals(4,checks);Assert.assertEquals(before,snapshot());Assert.assertEquals(pending,queues())
    }
    @Test fun changedTradeAtTheFourEntityCasCannotApplyAnUnreviewedLifecyclePlan()=runBlocking {
        deposited();val before=snapshot();val request=change()
        val profit=before.rows.single{it.id==profitId}.let{it.copy(payload=JsonObject(it.payload+("realized_profit_loss_minor" to JsonPrimitive(900L))))}
        store.commitMutations(listOf(mutation(profit)));val current=snapshot();val pending=queues()
        Assert.assertFalse(store.commitInvestmentCashTransferLifecycle(before,request,device,later));Assert.assertEquals(current,snapshot());Assert.assertEquals(pending,queues())
    }
    @Test fun observedUpdatesAndTombstonesNeverExposeOneModifiedHalfOfThePair()=runBlocking {
        deposited();val observed=Collections.synchronizedList(mutableListOf<Pair<Long?,Long?>>());val postingId=investmentLedgerIdentity(event,"cash-transfer-posting")
        val job=launch(Dispatchers.Unconfined,start=CoroutineStart.UNDISPATCHED){store.observeInvestmentCashSnapshot(owner).collect{read ->
            fun amount(id:String)=read.rows.single{it.id==id}.takeIf{it.deletedAt==null}?.payload?.financeRawLong("amount_minor")
            observed.add(amount(event) to amount(postingId))
        }}
        try {
            withTimeout(5000){while(observed.isEmpty())delay(5)}
            repo().changeCashTransfer(owner,change(),device,later).getOrThrow()
            withTimeout(5000){while(synchronized(observed){observed.none{it.first==400L}})delay(5)}
            repo().changeCashTransfer(owner,change(delete=true),device,later).getOrThrow()
            withTimeout(5000){while(synchronized(observed){observed.none{it.first==null && it.second==null}})delay(5)}
        }finally{job.cancelAndJoin()}
        Assert.assertTrue(synchronized(observed){observed.all{it.first==it.second}})
    }
}
