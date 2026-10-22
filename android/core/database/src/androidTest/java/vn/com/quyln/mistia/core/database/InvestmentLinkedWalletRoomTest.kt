package vn.com.quyln.mistia.core.database

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.util.Collections
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.*
import kotlinx.serialization.json.*
import org.junit.*
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.model.*

@RunWith(AndroidJUnit4::class)
class InvestmentLinkedWalletRoomTest {
    private lateinit var db:MistiaDatabase
    private lateinit var store:RoomLocalStore
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other=UserId("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
    private val device="44444444-4444-4444-4444-444444444444"
    private val previous="55555555-5555-5555-5555-555555555555"
    private val target="66666666-6666-6666-6666-666666666666"
    private val event="77777777-7777-7777-7777-777777777777"
    private val cashId="88888888-8888-8888-8888-888888888888"
    private val now="2026-10-22T00:00:00Z"
    private var active=owner
    @Before fun setup() {
        db=Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(),MistiaDatabase::class.java).allowMainThreadQueries().build()
        store=RoomLocalStore(db,currentBillOwner={active})
    }
    @After fun close(){db.close()}
    private fun repo(source:LocalStore=store)=OfflineFirstInvestmentRepository(source)
    private fun wallet(id:String)=WalletDraft(id=id,name="Wallet",kind=WalletKind.CASH,currencyCode="VND",openingBalanceMinor=10000).toMutation(owner,null,device,now).record
    private fun system(first:Boolean=false)=wallet(investmentSystemWalletId(owner)).let{it.copy(syncVersion=9007199254740993L,payload=JsonObject(it.payload+buildJsonObject {
        put("kind_raw_value","investment");put("system_purpose_raw_value","investmentProfit");put("investment_linked_wallet_id",if(first)JsonNull else JsonPrimitive(previous))
        put("opening_balance_minor",0L);put("sync_version",9007199254740993L);put("future_field","preserve")
    }))}
    private fun cash(amount:Long)=CloudRecord(CloudEntity.INVESTMENT_POSTING.table,cashId,owner.value,buildJsonObject {
        put("id",cashId);put("user_id",owner.value);put("wallet_id",previous);put("role_raw_value","cashAccrual")
        put("cash_bucket_raw_value","booked");put("cash_origin_raw_value","derived");put("amount_minor",amount);put("currency_code","VND")
        put("accounting_amount_minor",amount);put("accounting_currency_code","VND");put("created_at",now);put("updated_at",now);put("deleted_at",JsonNull)
    },now,null,0)
    private fun request(first:Boolean=false,move:Boolean=true)=InvestmentWalletLinkRequest(LedgerWalletRecord.fromCloudRecord(system(first)),LedgerWalletRecord.fromCloudRecord(wallet(target)),event,move,if(first)0 else 300,"Move investment cash")
    private fun mutation(row:CloudRecord)=row to PendingMutation(CloudEntity.fromTable(row.entity)!!,row.id,owner.value,MutationKind.UPSERT,row.payload,now,row.syncVersion,device)
    private suspend fun prepare(first:Boolean=false){store.commitMutations(listOf(system(first),wallet(previous),wallet(target),cash(300)).map(::mutation))}
    private suspend fun queues()=InvestmentWalletSnapshot.entities.associateWith{store.pendingMutations(owner,it,Long.MAX_VALUE)}
    @Test fun choosingFirstLinkUpdatesOnlyTheCanonicalWalletWithExactVersionAndOwnedOutbox()=runBlocking {
        prepare(true);val before=store.recordsIncludingDeleted(owner,CloudEntity.LEDGER_WALLET.table).filter{it.id!=investmentSystemWalletId(owner)}
        repo().changeLinkedWallet(owner,request(first=true,move=false),device,now).getOrThrow()
        val system=store.record(owner,CloudEntity.LEDGER_WALLET.table,investmentSystemWalletId(owner))!!
        Assert.assertEquals(target,system.payload.financeRawString("investment_linked_wallet_id"));Assert.assertEquals(9007199254740993L,system.syncVersion)
        Assert.assertEquals("preserve",system.payload.financeRawString("future_field"));Assert.assertEquals(4,queues().values.sumOf{it.size})
        Assert.assertEquals(before,store.recordsIncludingDeleted(owner,CloudEntity.LEDGER_WALLET.table).filter{it.id!=investmentSystemWalletId(owner)})
        Assert.assertTrue(InvestmentWalletSnapshot.entities.all{store.recordsIncludingDeleted(other,it.table).isEmpty()})
    }
    @Test fun actualMoveWritesOneLedgerAndTwoSignedCashPostingsWithoutRewritingOpeningBalances()=runBlocking {
        prepare();val before=store.recordsIncludingDeleted(owner,CloudEntity.LEDGER_WALLET.table).associate{it.id to it.payload.financeRawLong("opening_balance_minor")}
        repo().changeLinkedWallet(owner,request(),device,now).getOrThrow()
        val snapshot=store.investmentWalletSnapshot(owner)
        Assert.assertEquals(7,queues().values.sumOf{it.size})
        Assert.assertEquals(before,snapshot.rows.filter{it.entity==CloudEntity.LEDGER_WALLET.table}.associate{it.id to it.payload.financeRawLong("opening_balance_minor")})
        val ledger=snapshot.rows.single{it.entity==CloudEntity.LEDGER_TRANSACTION.table}
        Assert.assertEquals(300L,ledger.payload.financeRawLong("amount_minor"));Assert.assertEquals("investmentReconciliation",ledger.payload.financeRawString("settlement_role_raw_value"))
        val postings=snapshot.rows.filter{it.entity==CloudEntity.INVESTMENT_POSTING.table}
        Assert.assertEquals(3,postings.size)
        Assert.assertEquals(0L,postings.filter{it.payload.financeRawString("wallet_id")==previous}.sumOf{it.payload.financeRawLong("amount_minor")!!})
        Assert.assertEquals(300L,postings.single{it.payload.financeRawString("wallet_id")==target}.payload.financeRawLong("amount_minor"))
        Assert.assertEquals(9007199254740993L,store.pendingMutations(owner,CloudEntity.LEDGER_WALLET,Long.MAX_VALUE).single{it.mutation.recordId==investmentSystemWalletId(owner)}.mutation.baseVersion)
    }
    @Test fun failureInTheLastDestinationPostingRollsBackWalletLedgerSourcePostingAndAllQueues()=runBlocking {
        prepare();val before=store.investmentWalletSnapshot(owner);val pending=queues()
        db.openHelper.writableDatabase.execSQL("CREATE TRIGGER reject_new_cash BEFORE INSERT ON cloud_records WHEN NEW.entity = 'investment_wallet_postings' AND json_extract(NEW.payload_json, '$.wallet_id') = '66666666-6666-6666-6666-666666666666' BEGIN SELECT RAISE(ABORT, 'synthetic destination cash failure'); END")
        Assert.assertTrue(repo().changeLinkedWallet(owner,request(),device,now).isFailure)
        Assert.assertEquals(before,store.investmentWalletSnapshot(owner));Assert.assertEquals(pending,queues())
    }
    @Test fun ownerReplacementAtCommitCancelsWithoutAnyOldOrForeignOwnerWrites()=runBlocking {
        prepare();val before=store.investmentWalletSnapshot(owner);val pending=queues()
        val racing=object:LocalStore by store {
            override suspend fun commitInvestmentWalletLink(expected:InvestmentWalletSnapshot,request:InvestmentWalletLinkRequest,deviceId:String,now:String):Boolean {
                active=other;return store.commitInvestmentWalletLink(expected,request,deviceId,now)
            }
        }
        val result=runCatching{repo(racing).changeLinkedWallet(owner,request(),device,now)}
        Assert.assertTrue(result.exceptionOrNull() is CancellationException)
        active=owner;Assert.assertEquals(before,store.investmentWalletSnapshot(owner));Assert.assertEquals(pending,queues())
        Assert.assertTrue(InvestmentWalletSnapshot.entities.all{store.recordsIncludingDeleted(other,it.table).isEmpty()})
    }
    @Test fun newerCashAtCasCannotBeMovedUsingTheOldConfirmedAmount()=runBlocking {
        prepare();var commits=0
        val racing=object:LocalStore by store {
            override suspend fun commitInvestmentWalletLink(expected:InvestmentWalletSnapshot,request:InvestmentWalletLinkRequest,deviceId:String,now:String):Boolean {
                if(commits++==0)store.commitMutations(listOf(mutation(cash(301))))
                return store.commitInvestmentWalletLink(expected,request,deviceId,now)
            }
        }
        val result=repo(racing).changeLinkedWallet(owner,request(),device,now)
        Assert.assertEquals(InvestmentWalletLinkError.STALE_RECORD,(result.exceptionOrNull() as? InvestmentWalletLinkException)?.reason)
        Assert.assertEquals(previous,store.record(owner,CloudEntity.LEDGER_WALLET.table,investmentSystemWalletId(owner))!!.payload.financeRawString("investment_linked_wallet_id"))
        Assert.assertTrue(store.recordsIncludingDeleted(owner,CloudEntity.LEDGER_TRANSACTION.table).isEmpty());Assert.assertEquals(4,queues().values.sumOf{it.size})
    }
    @Test fun threeEntityReadDoesNotMixWalletLedgerAndPostingGenerations()=runBlocking {
        suspend fun batch(generation:Int){store.commitMutations(InvestmentWalletSnapshot.entities.map{entity ->mutation(CloudRecord(entity.table,event,owner.value,
            buildJsonObject{put("id",event);put("user_id",owner.value);put("updated_at",now);put("generation",generation)},now,null,0))})}
        batch(0);val observed=AtomicInteger(-1);val values=Collections.synchronizedList(mutableListOf<List<Int>>())
        val job=launch(Dispatchers.Unconfined,start=CoroutineStart.UNDISPATCHED) {
            store.observeInvestmentWalletSnapshot(owner).collect{snapshot ->
                val generations=InvestmentWalletSnapshot.entities.map{entity ->snapshot.rows.single{it.entity==entity.table}.payload.getValue("generation").jsonPrimitive.int}
                values.add(generations);if(generations.distinct().size==1)observed.set(generations.first())
            }
        }
        try {
            withTimeout(5000){while(observed.get()<0)delay(5)}
            for(generation in 1..16){batch(generation);withTimeout(5000){while(observed.get()<generation)delay(5)}}
        }finally{job.cancelAndJoin()}
        Assert.assertTrue(values.isNotEmpty());Assert.assertEquals(emptyList<List<Int>>(),synchronized(values){values.filter{it.distinct().size!=1}})
    }
}
