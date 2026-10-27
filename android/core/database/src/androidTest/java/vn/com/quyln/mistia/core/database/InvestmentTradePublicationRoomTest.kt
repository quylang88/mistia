package vn.com.quyln.mistia.core.database

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.*
import kotlinx.serialization.json.*
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.model.*

/** Source-generation and bookkeeping proofs; business/rebuilt-result validation is separate. */
@RunWith(AndroidJUnit4::class)
class InvestmentTradePublicationRoomTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other=UserId("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
    private val id="22222222-2222-2222-2222-222222222222"
    private val device="33333333-3333-3333-3333-333333333333"
    private val now="2026-10-26T00:00:00Z"
    private val version=9007199254740993L
    private var active=owner
    private lateinit var db:MistiaDatabase
    private lateinit var store:RoomLocalStore
    @Before fun setup() {
        db=Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(),MistiaDatabase::class.java).allowMainThreadQueries().build()
        store=RoomLocalStore(db,currentBillOwner={active})
    }
    @After fun close(){db.close()}
    private fun identity(index:Int)="44444444-4444-4444-4444-"+index.toString().padStart(12,'0')
    private fun row(entity:CloudEntity,recordId:String,subject:UserId=owner)=CloudRecord(entity.table,recordId,subject.value,buildJsonObject {
        put("id",recordId);put("user_id",subject.value);put("created_at",now);put("updated_at",now);put("deleted_at",JsonNull)
        put("sync_version",version);put("last_modified_by_device_id",device);put("future_null",JsonNull);put("future_large",Long.MAX_VALUE)
    },now,null,version)
    private fun mutation(raw:CloudRecord)=PendingMutation(CloudEntity.fromTable(raw.entity)!!,raw.id,raw.ownerUserId,MutationKind.UPSERT,raw.payload,requireNotNull(raw.updatedAt),raw.syncVersion,device)
    private suspend fun seed() {
        for((index,entity) in InvestmentTradePublicationSnapshot.entities.withIndex()) {
            val raw=row(entity,if(entity==CloudEntity.INVESTMENT_TRADE)id else identity(index))
            store.commitMutation(raw,mutation(raw))
        }
    }
    private suspend fun source()=store.investmentTradePublicationSnapshot(owner,id)
    @Test fun sourceCapturesAllOwnedFinancialRowsExactQueuesAndDirtyStampsAtomically()=runBlocking {
        seed();val foreign=row(CloudEntity.INVESTMENT_TRADE,identity(99),other);store.commitMutation(foreign,mutation(foreign))
        val source=source();source.requireCoherent();assertTrue(source.matches(source.requestedQueue!!))
        assertEquals(InvestmentTradePublicationSnapshot.entities.map{it.table}.toSet(),source.rows.map{it.entity}.toSet())
        assertEquals(source.rows.map{it.entity to it.id}.toSet(),source.dirtyKeys);assertEquals(source.rows.size,source.pending.size)
        assertEquals(version,source.requestedQueue!!.mutation.baseVersion);assertEquals(JsonPrimitive(Long.MAX_VALUE),source.requestedRecord!!.payload["future_large"])
        assertTrue(source.rows.all{it.ownerUserId==owner.value});assertTrue(source.pending.all{it.mutation.subjectUserId==owner.value})
    }
    @Test fun sourceRetainsCleanDependenciesAndBackoffQueuesBeyondTheOrdinaryDueCap()=runBlocking {
        seed();val initial=source();val wallet=initial.pending.single{it.mutation.entity==CloudEntity.LEDGER_WALLET}
        val raw=initial.rows.single{it.id==wallet.mutation.recordId};assertTrue(store.acknowledgeMutation(wallet,raw))
        for(index in 100..204) {val extra=row(CloudEntity.LEDGER_WALLET,identity(index));store.commitMutation(extra,mutation(extra))}
        val requested=source().requestedQueue!!;assertTrue(store.recordMutationFailure(requested,Long.MAX_VALUE,"held_for_review"))
        val actual=source();actual.requireCoherent();assertEquals(InvestmentTradePublicationSnapshot.entities.size+105,actual.rows.size)
        assertEquals(actual.rows.size-1,actual.pending.size);assertEquals(Long.MAX_VALUE,actual.requestedQueue!!.nextAttemptAtEpochMillis)
        assertFalse(raw.entity to raw.id in actual.dirtyKeys)
    }
    @Test fun exactFailureOnlyUpdatesTheRequestedTradeRetryMetadata()=runBlocking {
        seed();val before=source();val q=before.requestedQueue!!
        assertTrue(store.recordInvestmentTradeMutationFailure(q,34000,"http_503",before))
        val after=source();assertEquals(before.rows,after.rows);assertEquals(before.dirtyKeys,after.dirtyKeys)
        assertEquals(before.pending.filter{it!=q},after.pending.filter{it.mutation.recordId!=id})
        assertEquals(q.copy(attemptCount=1,nextAttemptAtEpochMillis=34000,lastError="http_503"),after.requestedQueue)
        assertFalse(store.recordInvestmentTradeMutationFailure(q,45000,"network_io",before));assertEquals(after,source())
    }
    @Test fun changingAnotherFinancialInputPreventsFailureBookkeepingAgainstTheOldGeneration()=runBlocking {
        seed();val before=source();val q=before.requestedQueue!!
        val changed=before.rows.single{it.entity==CloudEntity.LEDGER_TRANSACTION.table}.let{it.copy(payload=JsonObject(it.payload+("amount_minor" to JsonPrimitive(300))))}
        store.commitMutation(changed,mutation(changed));val current=source()
        assertFalse(store.recordInvestmentTradeMutationFailure(q,34000,"http_503",before));assertEquals(current,source())
    }
    @Test fun ownerReplacementRevokesReadsAndOldTradeFailureBookkeeping()=runBlocking {
        seed();val before=source();active=other
        assertTrue(runCatching{source()}.exceptionOrNull() is CancellationException)
        assertTrue(runCatching{store.recordInvestmentTradeMutationFailure(before.requestedQueue!!,34000,"http_503",before)}.exceptionOrNull() is CancellationException)
        active=owner;assertEquals(before,source())
    }
    @Test fun finalOwnerReplacementRollsBackAnAlreadyUpdatedRetryRow()=runBlocking {
        seed();val before=source()
        val guarded=RoomLocalStore(db,currentBillOwner={
            val attempts=db.openHelper.writableDatabase.query("SELECT attempt_count FROM sync_outbox WHERE record_id = '$id'").use{it.moveToFirst();it.getInt(0)}
            if(attempts>0)other else active
        })
        assertTrue(runCatching{guarded.recordInvestmentTradeMutationFailure(before.requestedQueue!!,34000,"http_503",before)}.exceptionOrNull() is CancellationException)
        assertEquals(before,source())
    }
    @Test fun sameOwnerSessionReplacementAtFinalFenceRollsBackRetryMetadata()=runBlocking {
        seed();val before=source();var sessionCurrent=true
        val guarded=RoomLocalStore(db,currentBillOwner={
            val attempts=db.openHelper.writableDatabase.query("SELECT attempt_count FROM sync_outbox WHERE record_id = '$id'").use{it.moveToFirst();it.getInt(0)}
            if(attempts>0)sessionCurrent=false
            active
        })
        assertTrue(runCatching{guarded.recordInvestmentTradeMutationFailure(before.requestedQueue!!,34000,"http_503",before,{sessionCurrent})}.exceptionOrNull() is CancellationException)
        assertEquals(before,source())
    }
    @Test fun finalCallerCancellationRollsBackTheExactTradeFailureUpdate()=runBlocking {
        seed();val before=source();var task:Deferred<Boolean>?=null
        val guarded=RoomLocalStore(db,currentBillOwner={
            val attempts=db.openHelper.writableDatabase.query("SELECT attempt_count FROM sync_outbox WHERE record_id = '$id'").use{it.moveToFirst();it.getInt(0)}
            if(attempts>0)task!!.cancel(CancellationException("Final trade failure fence"))
            active
        })
        task=async(start=CoroutineStart.LAZY){guarded.recordInvestmentTradeMutationFailure(before.requestedQueue!!,34000,"http_503",before)}
        task.start();assertTrue(runCatching{task.await()}.exceptionOrNull() is CancellationException);assertEquals(before,source())
    }
    @Test fun incoherentDirtyOrOrphanQueuesRemainVisibleWithoutAuthorizingMutation()=runBlocking {
        seed();val before=source();val extra=row(CloudEntity.INVESTMENT_POSTING,identity(900))
        db.cloudRecordDao().upsert(CloudRecordEntity(owner.value,extra.entity,extra.id,extra.payload.toString(),extra.updatedAt,null,extra.syncVersion,true,12))
        val current=source();assertTrue(current.rows.any{it.id==extra.id});assertTrue(runCatching{current.requireCoherent()}.isFailure)
        assertFalse(current.matches(current.requestedQueue!!))
        assertTrue(runCatching{store.recordInvestmentTradeMutationFailure(before.requestedQueue!!,34000,"http_503",current)}.isFailure)
        assertEquals(current,source())
    }
}
