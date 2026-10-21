package vn.com.quyln.mistia.core.database

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.time.*
import java.util.Collections
import java.util.UUID
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import kotlinx.serialization.json.*
import org.junit.*
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.model.*

@RunWith(AndroidJUnit4::class)
class BudgetReadSnapshotRoomTest {
    private lateinit var db:MistiaDatabase
    private lateinit var store:RoomLocalStore
    private lateinit var repo:OfflineFirstFinanceRepository
    private lateinit var parent:TransactionCategoryRecord
    private lateinit var child:TransactionCategoryRecord
    private lateinit var plan:BudgetPlanRecord
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other=UserId("99999999-9999-9999-9999-999999999999")
    private val device="22222222-2222-2222-2222-222222222222"
    private val walletId="33333333-3333-3333-3333-333333333333"
    private val transactionId="44444444-4444-4444-4444-444444444444"
    private val time="2026-10-21T00:00:00Z"
    @Before fun setup()=runBlocking {
        db=Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(),MistiaDatabase::class.java).allowMainThreadQueries().build()
        store=RoomLocalStore(db);repo=OfflineFirstFinanceRepository(store)
        parent=repo.saveCategory(owner,CategoryDraft(name="Living",kind=TransactionCategoryKind.EXPENSE,hierarchyRole=CategoryHierarchyRole.PARENT),device,time).getOrThrow()
        child=repo.saveCategory(owner,CategoryDraft(name="Food",kind=TransactionCategoryKind.EXPENSE,hierarchyRole=CategoryHierarchyRole.CHILD,parentCategoryId=parent.id),device,time).getOrThrow()
        val zone=ZoneId.systemDefault();plan=repo.saveBudget(owner,BudgetDraft(child.id,YearMonth.from(Instant.parse(time).atZone(zone)).atDay(1).atStartOfDay(zone).toInstant().toString(),1000,"JPY",zoneId=zone),device,time).getOrThrow()
    }
    @After fun close(){db.close()}
    private fun wallet(generation:Int)=CloudRecord(CloudEntity.LEDGER_WALLET.table,walletId,owner.value,buildJsonObject {
        put("id",walletId);put("user_id",owner.value);put("name","Generation $generation");put("note",generation)
        put("kind_raw_value","cash");put("currency_code",if(generation%2==0) "JPY" else "VND");put("opening_balance_minor",0)
        put("is_archived",false);put("created_at",time);put("updated_at",time)
    },time,null,0)
    private fun transaction(generation:Int)=CloudRecord(CloudEntity.LEDGER_TRANSACTION.table,transactionId,owner.value,buildJsonObject {
        put("id",transactionId);put("user_id",owner.value);put("title","Atomic budget input");put("primary_kind_raw_value","expense");put("entry_status_raw_value","posted")
        put("amount_minor",if(generation%2==0) 100 else 16500);put("source_wallet_id",walletId);put("source_currency_code",JsonNull);put("category_id",child.id);put("note",generation)
        put("is_archived",false);put("occurred_at",time);put("created_at",time);put("updated_at",time)
    },time,null,0)
    private fun pending(row:CloudRecord)=PendingMutation(CloudEntity.fromTable(row.entity)!!,row.id,row.ownerUserId,MutationKind.UPSERT,row.payload,time,0,device)
    private suspend fun pair(generation:Int){val rows=listOf(wallet(generation),transaction(generation));store.commitMutations(rows.map {it to pending(it)})}
    @Test fun atomicWalletAndLedgerChangesNeverEmitAFalseConvertedSpendingPair()=runBlocking {
        pair(0);val observations=Collections.synchronizedList(mutableListOf<Pair<String,Long>>());val observed=AtomicInteger(-1)
        val job=launch(Dispatchers.Unconfined,start=CoroutineStart.UNDISPATCHED) {
            repo.observeBudgetReadSnapshot(owner).collect {snapshot ->
                val wallet=snapshot.records(CloudEntity.LEDGER_WALLET).single {it.id==walletId}
                val transaction=snapshot.records(CloudEntity.LEDGER_TRANSACTION).single {it.id==transactionId}
                val code=wallet.payload.getValue("currency_code").jsonPrimitive.content
                val amount=transaction.payload.getValue("amount_minor").jsonPrimitive.long
                observations.add(code to amount)
                val left=wallet.payload.getValue("note").jsonPrimitive.int;val right=transaction.payload.getValue("note").jsonPrimitive.int
                if(left==right) observed.set(right)
            }
        }
        try {
            withTimeout(5000){while(observed.get()<0) delay(5)}
            for(generation in 1..16){pair(generation);withTimeout(5000){while(observed.get()<generation) delay(5)}}
        } finally {job.cancelAndJoin()}
        Assert.assertTrue(observations.isNotEmpty())
        val bad=synchronized(observations){observations.filterNot {it==("JPY" to 100L) || it==("VND" to 16500L)}}
        Assert.assertEquals("Mixed source currency/amount would report other than100JPY at165",emptyList<Pair<String,Long>>(),bad)
    }
    @Test fun completeHistoricalAndDamagedRowsReachTheReaderWithoutForeignDataOrReadWrites()=runBlocking {
        pair(0)
        val deleted=child.copy(deletedAt=time).toCloudRecord();store.commitMutation(deleted,pending(deleted).copy(kind=MutationKind.DELETE))
        val original=transaction(0);val damaged=original.copy(payload=JsonObject(original.payload+("deleted_at" to buildJsonObject {put("bad",true)})))
        store.commitMutation(damaged,pending(damaged))
        repo.saveWallet(other,WalletDraft(name="Other private",kind=WalletKind.CASH,currencyCode="VND"),device,time).getOrThrow()
        val before=BudgetReadSnapshot.entities.associateWith {store.recordsIncludingDeleted(owner,it.table) to store.pendingMutations(owner,it,Long.MAX_VALUE)}
        val snapshot=repo.observeBudgetReadSnapshot(owner).first()
        Assert.assertEquals(owner,snapshot.owner);Assert.assertEquals(BudgetReadSnapshot.entities,snapshot.rows.map {CloudEntity.fromTable(it.entity)!!}.toSet())
        Assert.assertTrue(snapshot.records(CloudEntity.TRANSACTION_CATEGORY).any {it.id==child.id && it.deletedAt==time})
        Assert.assertEquals(damaged,snapshot.records(CloudEntity.LEDGER_TRANSACTION).single())
        Assert.assertTrue(snapshot.rows.all {it.ownerUserId==owner.value})
        Assert.assertEquals(before,BudgetReadSnapshot.entities.associateWith {store.recordsIncludingDeleted(owner,it.table) to store.pendingMutations(owner,it,Long.MAX_VALUE)})
    }
}
