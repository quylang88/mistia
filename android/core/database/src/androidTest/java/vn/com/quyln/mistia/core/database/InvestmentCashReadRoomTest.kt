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
class InvestmentCashReadRoomTest {
    private lateinit var db:MistiaDatabase
    private lateinit var store:RoomLocalStore
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other=UserId("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
    private val id="22222222-2222-2222-2222-222222222222"
    private val device="44444444-4444-4444-4444-444444444444"
    private val now="2026-10-22T00:00:00Z"
    @Before fun setup() {
        db=Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(),MistiaDatabase::class.java).allowMainThreadQueries().build()
        store=RoomLocalStore(db,currentBillOwner={owner})
    }
    @After fun close(){db.close()}
    private suspend fun batch(generation:Int,subject:UserId=owner,deleted:Boolean=false) {
        store.commitMutations(InvestmentCashReadSnapshot.entities.map{entity ->
            val row=CloudRecord(entity.table,id,subject.value,buildJsonObject {
                put("id",id);put("user_id",subject.value);put("updated_at",now);put("generation",generation)
                put("deleted_at",if(deleted)JsonPrimitive(now) else JsonNull)
            },now,if(deleted)now else null,9007199254740993L)
            row to PendingMutation(entity,id,subject.value,MutationKind.UPSERT,row.payload,now,row.syncVersion,device)
        })
    }
    private suspend fun queues()=InvestmentCashReadSnapshot.entities.associateWith{store.pendingMutations(owner,it,Long.MAX_VALUE)}
    @Test fun rawReadIncludesAllOwnedEntitiesAndTombstonesWithoutChangingQueuesOrForeignScope()=runBlocking {
        batch(1,deleted=true);batch(2,other);val before=queues()
        val read=store.investmentCashSnapshot(owner)
        Assert.assertEquals(owner,read.owner);Assert.assertEquals(4,read.rows.size)
        Assert.assertTrue(read.rows.all{it.ownerUserId==owner.value && it.deletedAt==now && it.syncVersion==9007199254740993L})
        Assert.assertEquals(setOf(1),read.rows.map{it.payload.getValue("generation").jsonPrimitive.int}.toSet())
        Assert.assertEquals(before,queues())
    }
    @Test fun ownerReplacementAfterTheQueryCancelsBeforeDeliveringPrivateFinancialRows()=runBlocking {
        batch(0);val before=queues();var checks=0
        val fenced=RoomLocalStore(db,currentBillOwner={if(++checks==1)owner else other})
        val result=runCatching{fenced.investmentCashSnapshot(owner)}
        Assert.assertTrue(result.exceptionOrNull() is CancellationException);Assert.assertEquals(2,checks)
        Assert.assertEquals(before,queues())
    }
    @Test fun oneFourEntityQueryNeverCombinesDifferentWalletTradeLedgerOrPostingGenerations()=runBlocking {
        batch(0);val observed=AtomicInteger(-1);val reads=Collections.synchronizedList(mutableListOf<List<Int>>())
        val job=launch(Dispatchers.Unconfined,start=CoroutineStart.UNDISPATCHED) {
            store.observeInvestmentCashSnapshot(owner).collect{snapshot ->
                val values=InvestmentCashReadSnapshot.entities.map{entity ->snapshot.rows.single{it.entity==entity.table}.payload.getValue("generation").jsonPrimitive.int}
                reads.add(values);if(values.distinct().size==1)observed.set(values.first())
            }
        }
        try {
            withTimeout(5000){while(observed.get()<0)delay(5)}
            for(generation in 1..16){batch(generation);withTimeout(5000){while(observed.get()<generation)delay(5)}}
        }finally{job.cancelAndJoin()}
        Assert.assertTrue(reads.isNotEmpty());Assert.assertEquals(emptyList<List<Int>>(),synchronized(reads){reads.filter{it.distinct().size!=1}})
    }
}
