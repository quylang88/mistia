package vn.com.quyln.mistia.core.database

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.util.Collections
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.first
import kotlinx.serialization.json.*
import org.junit.*
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.model.*

@RunWith(AndroidJUnit4::class)
class UpcomingDueReadSnapshotRoomTest {
    private lateinit var db:MistiaDatabase
    private lateinit var store:RoomLocalStore
    private lateinit var repo:OfflineFirstFinanceRepository
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other=UserId("99999999-9999-9999-9999-999999999999")
    private val billId="22222222-2222-2222-2222-222222222222"
    private val cycleId="33333333-3333-3333-3333-333333333333"
    private val time="2026-10-21T00:00:00Z"
    @Before fun setup() {
        db=Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(),MistiaDatabase::class.java).allowMainThreadQueries().build()
        store=RoomLocalStore(db);repo=OfflineFirstFinanceRepository(store)
    }
    @After fun close(){db.close()}
    private fun source(generation:Int)=CloudRecord(CloudEntity.RECURRING_BILL_PLAN.table,billId,owner.value,buildJsonObject {
        put("id",billId);put("user_id",owner.value);put("name","Internet");put("amount_minor",if(generation%2==0) 5000 else 6000)
        put("is_archived",false);put("created_at",time);put("updated_at",time);put("generation",generation)
    },time,null,0)
    private fun cycle(generation:Int)=CloudRecord(CloudEntity.DUE_OCCURRENCE_RECORD.table,cycleId,owner.value,buildJsonObject {
        put("id",cycleId);put("user_id",owner.value);put("source_kind_raw_value","recurringBill");put("source_id",billId)
        put("selected_month_key","2026-10");put("amount_minor_snapshot",if(generation%2==0) 5000 else 6000);put("status_raw_value","pending")
        put("created_at",time);put("updated_at",time);put("generation",generation)
    },time,null,0)
    private fun pending(row:CloudRecord)=PendingMutation(CloudEntity.fromTable(row.entity)!!,row.id,row.ownerUserId,MutationKind.UPSERT,row.payload,time,0,billId)
    private suspend fun pair(generation:Int){store.commitMutations(listOf(source(generation),cycle(generation)).map {it to pending(it)})}
    @Test fun atomicSourceAndCycleAmountChangesNeverEmitMixedReadGenerations()=runBlocking {
        pair(0);val observed=AtomicInteger(-1);val pairs=Collections.synchronizedList(mutableListOf<Pair<Long,Long>>())
        val job=launch(Dispatchers.Unconfined,start=CoroutineStart.UNDISPATCHED) {
            repo.observeUpcomingDueReadSnapshot(owner).collect {snapshot ->
                val left=snapshot.records(CloudEntity.RECURRING_BILL_PLAN).single().payload
                val right=snapshot.records(CloudEntity.DUE_OCCURRENCE_RECORD).single().payload
                pairs.add(left.getValue("amount_minor").jsonPrimitive.long to right.getValue("amount_minor_snapshot").jsonPrimitive.long)
                val a=left.getValue("generation").jsonPrimitive.int;val b=right.getValue("generation").jsonPrimitive.int
                if(a==b) observed.set(a)
            }
        }
        try {
            withTimeout(5000){while(observed.get()<0) delay(5)}
            for(generation in 1..16){pair(generation);withTimeout(5000){while(observed.get()<generation) delay(5)}}
        } finally {job.cancelAndJoin()}
        Assert.assertTrue(pairs.isNotEmpty())
        Assert.assertEquals("Mixed bill/cycle amounts cannot describe a current due snapshot",emptyList<Pair<Long,Long>>(),synchronized(pairs){pairs.filter {it.first!=it.second}})
    }
    @Test fun damagedDeletionAndHistoricalRowsRemainAvailableWithoutReadWritesOrForeignScope()=runBlocking {
        pair(0)
        val damaged=source(0).let {it.copy(payload=JsonObject(it.payload+("deleted_at" to buildJsonObject {put("bad",true)})))}
        store.commitMutation(damaged,pending(damaged))
        val historical=cycle(0).copy(entity=CloudEntity.TRANSACTION_CATEGORY.table,deletedAt=time)
        store.commitMutation(historical,pending(historical).copy(kind=MutationKind.DELETE))
        val foreign=source(0).copy(ownerUserId=other.value,payload=JsonObject(source(0).payload+("user_id" to JsonPrimitive(other.value))))
        store.commitMutation(foreign,pending(foreign))
        val before=UpcomingDueReadSnapshot.entities.associateWith {store.recordsIncludingDeleted(owner,it.table) to store.pendingMutations(owner,it,Long.MAX_VALUE)}
        val snapshot=repo.observeUpcomingDueReadSnapshot(owner).first()
        Assert.assertEquals(owner,snapshot.owner);Assert.assertEquals(damaged,snapshot.records(CloudEntity.RECURRING_BILL_PLAN).singleOrNull())
        Assert.assertTrue(snapshot.records(CloudEntity.TRANSACTION_CATEGORY).any {it.id==cycleId && it.deletedAt==time})
        Assert.assertTrue(snapshot.rows.all {it.ownerUserId==owner.value})
        Assert.assertEquals(before,UpcomingDueReadSnapshot.entities.associateWith {store.recordsIncludingDeleted(owner,it.table) to store.pendingMutations(owner,it,Long.MAX_VALUE)})
    }
}
