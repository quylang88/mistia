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
class InvestmentCashTransferRoomTest {
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
    @Test fun sameWalletDepositAtomicallyAddsTwoFinancialQueuesAndReplayPreservesExactSourceMetadata()=runBlocking {
        prepare();val original=snapshot();val request=request()
        repo().saveCashTransfer(owner,request,device,now).getOrThrow()
        val current=snapshot();val pending=queues()
        Assert.assertEquals(7,pending.values.sumOf{it.size});Assert.assertEquals(BigInteger.valueOf(800),investmentCashFinancialView(current,"VND").availableMinor)
        Assert.assertEquals(BigInteger.valueOf(10000),investmentCashFinancialView(current,"VND").linkedActualMinor)
        Assert.assertEquals(original.rows,current.rows.filter{row ->original.rows.any{it.entity==row.entity && it.id==row.id}})
        Assert.assertEquals(9007199254740993L,current.rows.single{it.id==investmentSystemWalletId(owner)}.syncVersion)
        repo().saveCashTransfer(owner,request,device,now).getOrThrow()
        Assert.assertEquals(current,snapshot());Assert.assertEquals(pending,queues())
        Assert.assertTrue(InvestmentCashReadSnapshot.entities.all{store.recordsIncludingDeleted(other,it.table).isEmpty()})
    }
    @Test fun otherWalletWithdrawalMovesActualCashAndReducesOnlyTheLinkedBookedAllocation()=runBlocking {
        prepare();repo().saveCashTransfer(owner,request(withdraw=true,otherWallet=true),device,now).getOrThrow()
        val read=snapshot();val financial=investmentCashFinancialView(read,"VND")
        Assert.assertEquals(BigInteger.ZERO,financial.availableMinor);Assert.assertEquals(BigInteger.valueOf(9700),financial.linkedActualMinor)
        val balances=financeWalletBalancesRaw(owner,read.rows.filter{it.entity==CloudEntity.LEDGER_TRANSACTION.table},read.rows.filter{it.entity==CloudEntity.LEDGER_WALLET.table})!!
        Assert.assertEquals(BigInteger.valueOf(10300),balances[selected]);Assert.assertEquals(7,queues().values.sumOf{it.size})
    }
    @Test fun lastPostingFailureRollsBackTheLedgerAndBothNewOutboxRows()=runBlocking {
        prepare();val before=snapshot();val pending=queues()
        val postingId=investmentLedgerIdentity(event,"cash-transfer-posting")
        db.openHelper.writableDatabase.execSQL("CREATE TRIGGER reject_cash_transfer BEFORE INSERT ON cloud_records WHEN NEW.entity = 'investment_wallet_postings' AND NEW.record_id = '"+postingId+"' BEGIN SELECT RAISE(ABORT, 'synthetic cash posting failure'); END")
        val result=repo().saveCashTransfer(owner,request(),device,now)
        Assert.assertTrue(result.exceptionOrNull().toString().contains("synthetic cash posting failure"))
        Assert.assertEquals(before,snapshot());Assert.assertEquals(pending,queues())
    }
    @Test fun ownerReplacementBeforeCommitCancelsWithoutOldOrForeignWrites()=runBlocking {
        prepare();val before=snapshot();val pending=queues()
        val racing=object:LocalStore by store {
            override suspend fun commitInvestmentCashTransfer(expected:InvestmentCashReadSnapshot,request:InvestmentCashTransferRequest,deviceId:String,now:String):Boolean {
                active=other;return store.commitInvestmentCashTransfer(expected,request,deviceId,now)
            }
        }
        val result=runCatching{repo(racing).saveCashTransfer(owner,request(),device,now)}
        Assert.assertTrue(result.exceptionOrNull() is CancellationException)
        active=owner;Assert.assertEquals(before,snapshot());Assert.assertEquals(pending,queues())
    }
    @Test fun ownerReplacementAfterWritesRollsBackBeforeTheTransactionCanReturnSuccess()=runBlocking {
        prepare();val before=snapshot();val pending=queues();var checks=0
        val fenced=RoomLocalStore(db,currentBillOwner={if(++checks<=3)owner else other})
        val result=runCatching{fenced.commitInvestmentCashTransfer(before,request(),device,now)}
        Assert.assertTrue(result.exceptionOrNull() is CancellationException);Assert.assertEquals(4,checks)
        Assert.assertEquals(before,snapshot());Assert.assertEquals(pending,queues())
    }
    @Test fun changedTradeProfitMakesTheWholeFourEntityCasFailWithoutAStaleTransfer()=runBlocking {
        prepare();val before=snapshot()
        val changed=rows().single{it.id==profitId}.let{it.copy(payload=JsonObject(it.payload+("realized_profit_loss_minor" to JsonPrimitive(900L))))}
        store.commitMutations(listOf(mutation(changed)));val current=snapshot();val pending=queues()
        Assert.assertFalse(store.commitInvestmentCashTransfer(before,request(),device,now))
        Assert.assertEquals(current,snapshot());Assert.assertEquals(pending,queues())
    }
    @Test fun anExistingUnmatchedOutboxCannotBeOverwrittenByACreateWithTheSamePostingId()=runBlocking {
        prepare();val postingId=investmentLedgerIdentity(event,"cash-transfer-posting")
        val orphan=CloudRecord(CloudEntity.INVESTMENT_POSTING.table,postingId,owner.value,buildJsonObject{put("id",postingId);put("user_id",owner.value);put("older","pending")},now,null,0)
        store.commitMutations(listOf(mutation(orphan)))
        db.openHelper.writableDatabase.execSQL("DELETE FROM cloud_records WHERE owner_user_id=? AND entity=? AND record_id=?",arrayOf(owner.value,orphan.entity,postingId))
        val before=snapshot();val pending=queues();val result=repo().saveCashTransfer(owner,request(),device,now)
        Assert.assertEquals(InvestmentCashTransferError.STALE_RECORD,(result.exceptionOrNull() as? InvestmentCashTransferException)?.reason)
        Assert.assertEquals(before,snapshot());Assert.assertEquals(pending,queues())
    }
    @Test fun observedFinancialSnapshotsNeverExposeOnlyOneHalfOfTheNewLedgerPostingPair()=runBlocking {
        prepare();val observed=Collections.synchronizedList(mutableListOf<Pair<Boolean,Boolean>>())
        val postingId=investmentLedgerIdentity(event,"cash-transfer-posting")
        val job=launch(Dispatchers.Unconfined,start=CoroutineStart.UNDISPATCHED){store.observeInvestmentCashSnapshot(owner).collect{snapshot ->
            observed.add((snapshot.rows.any{it.entity==CloudEntity.LEDGER_TRANSACTION.table && it.id==event}) to (snapshot.rows.any{it.entity==CloudEntity.INVESTMENT_POSTING.table && it.id==postingId}))
        }}
        try {
            withTimeout(5000){while(observed.isEmpty())delay(5)}
            repo().saveCashTransfer(owner,request(),device,now).getOrThrow()
            withTimeout(5000){while(synchronized(observed){observed.none{it.first && it.second}})delay(5)}
        }finally{job.cancelAndJoin()}
        Assert.assertTrue(observed.isNotEmpty());Assert.assertTrue(synchronized(observed){observed.all{it.first==it.second}})
    }
}
