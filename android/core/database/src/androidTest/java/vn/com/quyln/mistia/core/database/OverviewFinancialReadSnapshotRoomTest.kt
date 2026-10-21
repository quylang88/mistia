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
class OverviewFinancialReadSnapshotRoomTest {
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
    private fun source(generation:Int,entity:CloudEntity=CloudEntity.LEDGER_WALLET)=CloudRecord(entity.table,billId,owner.value,buildJsonObject {
        put("id",billId);put("user_id",owner.value);put("amount_minor",generation);put("generation",generation)
        put("is_archived",false);put("created_at",time);put("updated_at",time)
    },time,null,0)
    private fun pending(row:CloudRecord)=PendingMutation(CloudEntity.fromTable(row.entity)!!,row.id,row.ownerUserId,MutationKind.UPSERT,row.payload,time,0,billId)
    private suspend fun batch(generation:Int){store.commitMutations(OverviewFinancialReadSnapshot.entities.map {source(generation,it)}.map {it to pending(it)})}
    @Test fun atomicSixEntityUpdatesNeverEmitMixedReadGenerations()=runBlocking {
        batch(0);val observed=AtomicInteger(-1);val generations=Collections.synchronizedList(mutableListOf<List<Int>>())
        val job=launch(Dispatchers.Unconfined,start=CoroutineStart.UNDISPATCHED) {
            repo.observeOverviewFinancialReadSnapshot(owner).collect {snapshot ->
                val values=OverviewFinancialReadSnapshot.entities.map {entity ->snapshot.records(entity).single().payload.getValue("generation").jsonPrimitive.int}
                generations.add(values)
                if(values.distinct().size==1) observed.set(values.first())
            }
        }
        try {
            withTimeout(5000){while(observed.get()<0) delay(5)}
            for(generation in 1..24){batch(generation);withTimeout(5000){while(observed.get()<generation) delay(5)}}
        } finally {job.cancelAndJoin()}
        Assert.assertTrue(generations.isNotEmpty())
        Assert.assertEquals("Mixed finance generations cannot describe a current Overview",emptyList<List<Int>>(),synchronized(generations){generations.filter {it.distinct().size!=1}})
    }
    @Test fun damagedDeletionAndHistoricalRowsRemainAvailableWithoutReadWritesOrForeignScope()=runBlocking {
        batch(0)
        val damaged=source(0).let {it.copy(payload=JsonObject(it.payload+("deleted_at" to buildJsonObject {put("bad",true)})))}
        store.commitMutation(damaged,pending(damaged))
        val historical=source(0,CloudEntity.TRANSACTION_CATEGORY).copy(entity=CloudEntity.TRANSACTION_CATEGORY.table,deletedAt=time)
        store.commitMutation(historical,pending(historical).copy(kind=MutationKind.DELETE))
        val foreign=source(0).copy(ownerUserId=other.value,payload=JsonObject(source(0).payload+("user_id" to JsonPrimitive(other.value))))
        store.commitMutation(foreign,pending(foreign))
        val before=OverviewFinancialReadSnapshot.entities.associateWith {store.recordsIncludingDeleted(owner,it.table) to store.pendingMutations(owner,it,Long.MAX_VALUE)}
        val snapshot=repo.observeOverviewFinancialReadSnapshot(owner).first()
        Assert.assertEquals(owner,snapshot.owner);Assert.assertEquals(damaged,snapshot.records(CloudEntity.LEDGER_WALLET).singleOrNull())
        Assert.assertTrue(snapshot.records(CloudEntity.TRANSACTION_CATEGORY).any {it.id==billId && it.deletedAt==time})
        Assert.assertTrue(snapshot.rows.all {it.ownerUserId==owner.value})
        Assert.assertEquals(before,OverviewFinancialReadSnapshot.entities.associateWith {store.recordsIncludingDeleted(owner,it.table) to store.pendingMutations(owner,it,Long.MAX_VALUE)})
    }
}
