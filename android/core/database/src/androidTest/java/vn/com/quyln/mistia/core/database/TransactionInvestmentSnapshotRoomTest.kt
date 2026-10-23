package vn.com.quyln.mistia.core.database

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.*
import org.junit.*
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.model.*

@RunWith(AndroidJUnit4::class)
class TransactionInvestmentSnapshotRoomTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other=UserId("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")
    private val device="44444444-4444-4444-8444-444444444444"
    private val now="2026-10-22T00:00:00Z"
    private lateinit var db:MistiaDatabase
    private lateinit var store:RoomLocalStore
    @Before fun open(){db=Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(),MistiaDatabase::class.java).allowMainThreadQueries().build();store=RoomLocalStore(db,currentBillOwner={owner})}
    @After fun close(){db.close()}
    private fun rows(subject:UserId)=TransactionInvestmentSaveSnapshot.entities.mapIndexed{index,entity->
        val id=java.util.UUID(0,index.toLong()+1).toString()
        CloudRecord(entity.table,id,subject.value,buildJsonObject {
            put("id",id);put("user_id",subject.value);put("created_at",now);put("updated_at",now);put("sync_version",9007199254740993L);put("deleted_at",if(entity==CloudEntity.INVESTMENT_POSTING)JsonPrimitive(now) else JsonNull)
            put("future_field",entity.table+"/"+subject.value)
        },now,if(entity==CloudEntity.INVESTMENT_POSTING)now else null,9007199254740993L)
    }
    private suspend fun seed(){for(subject in listOf(owner,other))store.commitMutations(rows(subject).map{row->row to PendingMutation(CloudEntity.fromTable(row.entity)!!,row.id,row.ownerUserId,if(row.deletedAt==null)MutationKind.UPSERT else MutationKind.DELETE,row.payload,now,row.syncVersion,device)})}
    private suspend fun queues(subject:UserId)=TransactionInvestmentSaveSnapshot.entities.associateWith{store.pendingMutations(subject,it,Long.MAX_VALUE)}
    @Test fun oneOwnerSevenEntityReadRetainsTombstonesVersionsAndUnknownsWithoutChangingAnyQueue()=runBlocking {
        seed();val pending=queues(owner);val foreignPending=queues(other)
        val snapshot=store.transactionInvestmentSaveSnapshot(owner);snapshot.requireValid()
        Assert.assertEquals(7,snapshot.recordsByEntity.size);Assert.assertEquals(rows(owner).toSet(),snapshot.recordsByEntity.values.flatten().toSet())
        Assert.assertEquals(5,snapshot.transactionSnapshot().recordsByEntity.size);Assert.assertEquals(4,snapshot.investmentSnapshot().rows.size)
        Assert.assertNotNull(snapshot.recordsByEntity.getValue(CloudEntity.INVESTMENT_POSTING).single().deletedAt)
        Assert.assertTrue(snapshot.recordsByEntity.values.flatten().all{it.ownerUserId==owner.value && it.syncVersion==9007199254740993L})
        Assert.assertEquals(pending,queues(owner));Assert.assertEquals(foreignPending,queues(other))
        val changed=snapshot.copy(recordsByEntity=snapshot.recordsByEntity+(CloudEntity.INVESTMENT_TRADE to emptyList()))
        Assert.assertTrue(runCatching{snapshot.requireUnchanged(changed)}.isFailure)
    }
    @Test fun ownerReplacementAtTheSecondReadFenceCannotReturnASnapshotFromTheOldPartition()=runBlocking {
        seed();val pending=queues(owner);var checks=0
        val switching=RoomLocalStore(db,currentBillOwner={checks++;if(checks==1)owner else other})
        Assert.assertTrue(runCatching{switching.transactionInvestmentSaveSnapshot(owner)}.exceptionOrNull() is CancellationException)
        Assert.assertEquals(2,checks);Assert.assertEquals(pending,queues(owner))
    }
    @Test fun bodyOwnerContradictionInInvestmentDependenciesCannotBeFilteredOutOfAValidOrdinarySnapshot()=runBlocking {
        seed();val row=rows(owner).single{it.entity==CloudEntity.INVESTMENT_TRADE.table}
        val bad=JsonObject(row.payload+("user_id" to JsonPrimitive(other.value))).toString()
        db.openHelper.writableDatabase.execSQL("UPDATE cloud_records SET payload_json = ? WHERE owner_user_id = ? AND entity = ? AND record_id = ?",arrayOf(bad,owner.value,row.entity,row.id))
        val pending=queues(owner)
        Assert.assertTrue(runCatching{store.transactionInvestmentSaveSnapshot(owner)}.isFailure)
        Assert.assertEquals(pending,queues(owner))
    }
}
