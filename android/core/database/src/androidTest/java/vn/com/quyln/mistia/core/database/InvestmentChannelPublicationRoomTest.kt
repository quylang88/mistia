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

@RunWith(AndroidJUnit4::class)
class InvestmentChannelPublicationRoomTest {
    private lateinit var db:MistiaDatabase
    private lateinit var store:RoomLocalStore
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other=UserId("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
    private val id="22222222-2222-2222-2222-222222222222"
    private val device="33333333-3333-3333-3333-333333333333"
    private val now="2026-10-24T00:00:00Z"
    private var active=owner
    @Before fun setup() {
        db=Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(),MistiaDatabase::class.java).allowMainThreadQueries().build()
        store=RoomLocalStore(db,currentBillOwner={active})
    }
    @After fun close(){db.close()}
    private suspend fun prepare():QueuedMutation {
        OfflineFirstInvestmentRepository(store).saveChannel(owner,InvestmentChannelDraft(id,"Cards"),"VND",device,now).getOrThrow()
        return store.pendingMutations(owner,CloudEntity.INVESTMENT_CHANNEL,Long.MAX_VALUE).single()
    }
    private suspend fun remote()=store.record(owner,CloudEntity.INVESTMENT_CHANNEL.table,id)!!.let{row->row.copy(syncVersion=9007199254740993L,
        payload=JsonObject(row.payload+("sync_version" to JsonPrimitive(9007199254740993L))))}
    @Test fun actualMetadataAcknowledgementClearsOnlyItsChannelQueueAndKeepsTheReservedWalletPending()=runBlocking {
        val q=prepare();val wallet=store.recordsIncludingDeleted(owner,CloudEntity.LEDGER_WALLET.table)
        val walletQueue=store.pendingMutations(owner,CloudEntity.LEDGER_WALLET,Long.MAX_VALUE)
        val before=store.investmentChannelPublicationSnapshot(owner,id)
        assertTrue(before.matches(q));assertTrue(before.hasPendingMutation)
        val server=remote();assertTrue(store.acknowledgeInvestmentChannelMutation(q,server))
        val after=store.investmentChannelPublicationSnapshot(owner,id)
        assertEquals(server,after.record);assertNull(after.pending);assertFalse(after.hasPendingMutation)
        assertEquals(wallet,store.recordsIncludingDeleted(owner,CloudEntity.LEDGER_WALLET.table))
        assertEquals(walletQueue,store.pendingMutations(owner,CloudEntity.LEDGER_WALLET,Long.MAX_VALUE))
        assertNull(store.record(other,CloudEntity.INVESTMENT_CHANNEL.table,id))
    }
    @Test fun actualFailureBookkeepingIsExactAndCannotChangeChannelMetadata()=runBlocking {
        val q=prepare();val row=store.record(owner,CloudEntity.INVESTMENT_CHANNEL.table,id)
        assertTrue(store.recordInvestmentChannelMutationFailure(q,34000,"network_io"))
        val current=store.pendingMutations(owner,CloudEntity.INVESTMENT_CHANNEL,Long.MAX_VALUE).single()
        assertEquals(1,current.attemptCount);assertEquals(34000L,current.nextAttemptAtEpochMillis);assertEquals("network_io",current.lastError)
        assertEquals(row,store.record(owner,CloudEntity.INVESTMENT_CHANNEL.table,id))
        assertFalse(store.recordInvestmentChannelMutationFailure(q,Long.MAX_VALUE,"old_error"))
        assertEquals(current,store.pendingMutations(owner,CloudEntity.INVESTMENT_CHANNEL,Long.MAX_VALUE).single())
    }
    @Test fun aNewerCurrentNameAndQueueCannotBeReplacedByAnOlderAckOrError()=runBlocking {
        val q=prepare();val server=remote()
        val baseline=InvestmentChannelRecord.fromCloudRecord(store.record(owner,CloudEntity.INVESTMENT_CHANNEL.table,id)!!)
        OfflineFirstInvestmentRepository(store).saveChannel(owner,InvestmentChannelDraft(id,"Newer",baseline),"VND",device,"2026-10-24T01:00:00Z").getOrThrow()
        val current=store.investmentChannelPublicationSnapshot(owner,id)
        assertFalse(store.acknowledgeInvestmentChannelMutation(q,server))
        assertFalse(store.recordInvestmentChannelMutationFailure(q,Long.MAX_VALUE,"old_error"))
        assertEquals(current,store.investmentChannelPublicationSnapshot(owner,id))
    }
    @Test fun ownerReplacementRevokesAckAndFailureBeforeAnyOldOwnerWrite()=runBlocking {
        val q=prepare();val server=remote();val before=store.investmentChannelPublicationSnapshot(owner,id)
        active=other
        assertTrue(runCatching{store.acknowledgeInvestmentChannelMutation(q,server)}.exceptionOrNull() is CancellationException)
        assertTrue(runCatching{store.recordInvestmentChannelMutationFailure(q,34000,"network_io")}.exceptionOrNull() is CancellationException)
        active=owner;assertEquals(before,store.investmentChannelPublicationSnapshot(owner,id))
    }
    @Test fun finalCallerCancellationRollsBackTheAlreadyAppliedAckAndQueueDeletion()=runBlocking {
        val q=prepare();val server=remote();val before=store.investmentChannelPublicationSnapshot(owner,id)
        var task:Deferred<Boolean>?=null
        val guarded=RoomLocalStore(db,currentBillOwner={
            val version=db.openHelper.writableDatabase.query("SELECT sync_version FROM cloud_records WHERE entity = 'investment_channels'").use{it.moveToFirst();it.getLong(0)}
            if(version>0)task!!.cancel(CancellationException("Final channel ACK fence"))
            active
        })
        task=async(start=CoroutineStart.LAZY){guarded.acknowledgeInvestmentChannelMutation(q,server)}
        task.start();assertTrue(runCatching{task.await()}.exceptionOrNull() is CancellationException)
        assertEquals(before,store.investmentChannelPublicationSnapshot(owner,id))
    }
    @Test fun lateRemoteRowFailureRestoresTheDeletedQueueInTheSameTransaction()=runBlocking {
        val q=prepare();val server=remote();val before=store.investmentChannelPublicationSnapshot(owner,id)
        db.openHelper.writableDatabase.execSQL("CREATE TRIGGER reject_channel_ack BEFORE INSERT ON cloud_records WHEN NEW.entity = 'investment_channels' BEGIN SELECT RAISE(ABORT, 'synthetic channel ACK failure'); END")
        assertTrue(runCatching{store.acknowledgeInvestmentChannelMutation(q,server)}.isFailure)
        assertEquals(before,store.investmentChannelPublicationSnapshot(owner,id))
    }
    @Test fun coherentlyQueuedButForeignServerIdentityCannotEnterTheOwnedCache()=runBlocking {
        val q=prepare();val before=store.investmentChannelPublicationSnapshot(owner,id)
        val server=remote().let{it.copy(ownerUserId=other.value,payload=JsonObject(it.payload+("user_id" to JsonPrimitive(other.value))))}
        assertTrue(runCatching{store.acknowledgeInvestmentChannelMutation(q,server)}.isFailure)
        assertEquals(before,store.investmentChannelPublicationSnapshot(owner,id));assertNull(store.record(other,CloudEntity.INVESTMENT_CHANNEL.table,id))
    }
    @Test fun anUnqueuedRowChangeCannotBeOverwrittenEvenWhenTheOldQueueStillExists()=runBlocking {
        val q=prepare();val server=remote()
        db.openHelper.writableDatabase.execSQL("UPDATE cloud_records SET payload_json = json_set(payload_json, '$.name', 'Unqueued newer row') WHERE entity = 'investment_channels'")
        val before=store.investmentChannelPublicationSnapshot(owner,id)
        assertFalse(before.matches(q));assertFalse(store.acknowledgeInvestmentChannelMutation(q,server))
        assertFalse(store.recordInvestmentChannelMutationFailure(q,34000,"network_io"));assertEquals(before,store.investmentChannelPublicationSnapshot(owner,id))
    }
    @Test fun finalCallerCancellationAlsoRollsBackAlreadyWrittenFailureBookkeeping()=runBlocking {
        val q=prepare();val before=store.investmentChannelPublicationSnapshot(owner,id)
        var task:Deferred<Boolean>?=null
        val guarded=RoomLocalStore(db,currentBillOwner={
            val attempt=db.openHelper.writableDatabase.query("SELECT attempt_count FROM sync_outbox WHERE entity = 'investment_channels'").use{it.moveToFirst();it.getInt(0)}
            if(attempt>0)task!!.cancel(CancellationException("Final channel failure fence"))
            active
        })
        task=async(start=CoroutineStart.LAZY){guarded.recordInvestmentChannelMutationFailure(q,34000,"network_io")}
        task.start();assertTrue(runCatching{task.await()}.exceptionOrNull() is CancellationException)
        assertEquals(before,store.investmentChannelPublicationSnapshot(owner,id))
    }

    @Test fun aDetachedQueueCannotGrantPublicationAuthorityToACleanRow()=runBlocking {
        val q=prepare();val server=remote()
        db.openHelper.writableDatabase.execSQL("UPDATE cloud_records SET has_pending_mutation = 0 WHERE entity = 'investment_channels'")
        val before=store.investmentChannelPublicationSnapshot(owner,id)
        assertNotNull(before.pending);assertFalse(before.hasPendingMutation);assertFalse(before.matches(q))
        assertFalse(store.acknowledgeInvestmentChannelMutation(q,server));assertFalse(store.recordInvestmentChannelMutationFailure(q,34000,"network_io"))
        assertEquals(before,store.investmentChannelPublicationSnapshot(owner,id))
    }

    @Test fun aQueueDeviceColumnMismatchCannotAuthorizeAckOrFailureBookkeeping()=runBlocking {
        prepare();val server=remote()
        db.openHelper.writableDatabase.execSQL("UPDATE sync_outbox SET device_id = '44444444-4444-4444-4444-444444444444' WHERE entity = 'investment_channels'")
        val q=store.pendingMutations(owner,CloudEntity.INVESTMENT_CHANNEL,Long.MAX_VALUE).single()
        val before=store.investmentChannelPublicationSnapshot(owner,id)
        assertFalse(before.matches(q));assertFalse(store.acknowledgeInvestmentChannelMutation(q,server))
        assertFalse(store.recordInvestmentChannelMutationFailure(q,34000,"network_io"));assertEquals(before,store.investmentChannelPublicationSnapshot(owner,id))
    }

    @Test fun finalSessionRotationRollsBackChannelAcknowledgement()=runBlocking {
        val q=prepare();val before=store.investmentChannelPublicationSnapshot(owner,id);val server=remote()
        var sawApplied=false
        val error=runCatching{store.acknowledgeInvestmentChannelMutation(q,server,isSessionCurrent={
            val value=db.openHelper.writableDatabase.query("SELECT sync_version FROM cloud_records WHERE entity = 'investment_channels'").use{it.moveToFirst();it.getLong(0)}
            if(!(value==0L))sawApplied=true
            value==0L
        })}.exceptionOrNull()
        assertTrue("Session fence must observe the applied write before rollback",sawApplied)
        assertTrue(error is CancellationException)
        assertEquals(before,store.investmentChannelPublicationSnapshot(owner,id))
    }

    @Test fun finalSessionRotationRollsBackChannelFailureBookkeeping()=runBlocking {
        val q=prepare();val before=store.investmentChannelPublicationSnapshot(owner,id);val server=remote()
        var sawApplied=false
        val error=runCatching{store.recordInvestmentChannelMutationFailure(q,34000,"network_io",isSessionCurrent={
            val value=db.openHelper.writableDatabase.query("SELECT attempt_count FROM sync_outbox WHERE entity = 'investment_channels'").use{it.moveToFirst();it.getLong(0)}
            if(!(value==0L))sawApplied=true
            value==0L
        })}.exceptionOrNull()
        assertTrue("Session fence must observe the applied write before rollback",sawApplied)
        assertTrue(error is CancellationException)
        assertEquals(before,store.investmentChannelPublicationSnapshot(owner,id))
    }

}
