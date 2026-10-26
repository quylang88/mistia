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
class InvestmentWalletPublicationRoomTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other=UserId("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
    private val device="33333333-3333-3333-3333-333333333333"
    private val linked="44444444-4444-4444-4444-444444444444"
    private val rootId=investmentSystemWalletId(owner)
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
    private fun wallet(id:String)=WalletDraft(id=id,name="Cash",kind=WalletKind.CASH,currencyCode="VND",openingBalanceMinor=100).toMutation(owner,null,device,now).record
    private fun root()=wallet(rootId).let{it.copy(syncVersion=version,payload=JsonObject(it.payload+buildJsonObject {
        put("kind_raw_value","investment");put("system_purpose_raw_value","investmentProfit");put("opening_balance_minor",0)
        put("investment_linked_wallet_id",linked);put("sync_version",version);put("future_null",JsonNull)
    }))}
    private fun mutation(row:CloudRecord)=PendingMutation(CloudEntity.LEDGER_WALLET,row.id,owner.value,MutationKind.UPSERT,row.payload,requireNotNull(row.updatedAt),row.syncVersion,device)
    private fun result(row:CloudRecord)=row.copy(syncVersion=row.syncVersion+1,payload=JsonObject(row.payload+("sync_version" to JsonPrimitive(row.syncVersion+1))))
    private suspend fun seed(linkedDirty:Boolean=false) {
        val target=wallet(linked);store.commitMutation(target,mutation(target))
        if(!linkedDirty) {
            val q=store.pendingMutations(owner,CloudEntity.LEDGER_WALLET,Long.MAX_VALUE).single()
            assertTrue(store.acknowledgeMutation(q,result(target)))
        }
        val root=root();store.commitMutation(root,mutation(root))
    }
    @Test fun atomicRootAndLinkReadProvesTheExactOwnedQueueWithoutRoundingItsBase()=runBlocking {
        seed();val state=store.investmentWalletPublicationSnapshot(owner)
        assertEquals(root(),state.record);assertEquals(version,state.pending!!.mutation.baseVersion)
        assertTrue(state.matches(state.pending!!));assertTrue(state.hasPendingMutation)
        assertEquals(linked,state.linkedRecord!!.id);assertNull(state.linkedPending);assertFalse(state.linkedHasPendingMutation)
        assertEquals(InvestmentWalletPublicationDependency.READY,state.dependency())
        assertSame(JsonNull,state.record!!.payload["future_null"])
    }
    @Test fun aDirtyLinkedDependencyIsReadInTheSameSnapshotAndDefersPublication()=runBlocking {
        seed(true);val state=store.investmentWalletPublicationSnapshot(owner)
        assertNotNull(state.linkedPending);assertTrue(state.linkedHasPendingMutation)
        assertEquals(InvestmentWalletPublicationDependency.WAITING_FOR_LINKED_WALLET,state.dependency())
    }
    @Test fun exactRootAckImportsOnlyTheRemoteRootAndLeavesTheLinkedWalletIntact()=runBlocking {
        seed();val source=store.investmentWalletPublicationSnapshot(owner);val remote=result(source.record!!)
        assertTrue(store.acknowledgeInvestmentWalletMutation(source.pending!!,remote,source))
        val after=store.investmentWalletPublicationSnapshot(owner)
        assertEquals(remote,after.record);assertNull(after.pending);assertFalse(after.hasPendingMutation)
        assertEquals(source.linkedRecord,after.linkedRecord);assertNull(after.linkedPending)
    }
    @Test fun anOldAckCannotConsumeANewerLinkChoiceOrItsQueue()=runBlocking {
        seed();val old=store.investmentWalletPublicationSnapshot(owner)
        val changed=old.record!!.let{it.copy(updatedAt="2026-10-26T00:15:00Z",payload=JsonObject(it.payload+mapOf("investment_linked_wallet_id" to JsonNull,"updated_at" to JsonPrimitive("2026-10-26T00:15:00Z"))))}
        store.commitMutation(changed,mutation(changed));val current=store.investmentWalletPublicationSnapshot(owner)
        assertFalse(store.acknowledgeInvestmentWalletMutation(old.pending!!,result(old.record!!),old))
        assertEquals(current,store.investmentWalletPublicationSnapshot(owner))
    }
    @Test fun changingTheDependencyDuringHttpCannotConsumeTheUnchangedRootQueue()=runBlocking {
        seed();val source=store.investmentWalletPublicationSnapshot(owner)
        val target=source.linkedRecord!!.let{it.copy(payload=JsonObject(it.payload+("name" to JsonPrimitive("Changed target"))))}
        store.commitMutation(target,mutation(target));val current=store.investmentWalletPublicationSnapshot(owner)
        assertFalse(store.acknowledgeInvestmentWalletMutation(source.pending!!,result(source.record!!),source))
        assertEquals(current,store.investmentWalletPublicationSnapshot(owner))
    }
    @Test fun failureBookkeepingMatchesTheWholeCurrentSourceAndOnlyTheExactQueue()=runBlocking {
        seed();val source=store.investmentWalletPublicationSnapshot(owner);val q=source.pending!!
        assertTrue(store.recordInvestmentWalletMutationFailure(q,34000,"network_io",source))
        val after=store.investmentWalletPublicationSnapshot(owner)
        assertEquals(source.record,after.record);assertEquals(source.linkedRecord,after.linkedRecord)
        assertEquals(q.copy(attemptCount=q.attemptCount+1,nextAttemptAtEpochMillis=34000,lastError="network_io"),after.pending)
        assertFalse(store.recordInvestmentWalletMutationFailure(q,90000,"http_503",source))
        assertEquals(after,store.investmentWalletPublicationSnapshot(owner))
    }
    @Test fun ownerReplacementRevokesTheReadAckAndFailureBeforeAnyOldOwnerWrite()=runBlocking {
        seed();val source=store.investmentWalletPublicationSnapshot(owner);active=other
        assertTrue(runCatching{store.investmentWalletPublicationSnapshot(owner)}.exceptionOrNull() is CancellationException)
        assertTrue(runCatching{store.acknowledgeInvestmentWalletMutation(source.pending!!,result(source.record!!),source)}.exceptionOrNull() is CancellationException)
        assertTrue(runCatching{store.recordInvestmentWalletMutationFailure(source.pending!!,34000,"network_io",source)}.exceptionOrNull() is CancellationException)
        active=owner;assertEquals(source,store.investmentWalletPublicationSnapshot(owner))
    }
    @Test fun aLateRowInsertFailureRollsBackTheAlreadyDeletedRootQueue()=runBlocking {
        seed();val source=store.investmentWalletPublicationSnapshot(owner)
        db.openHelper.writableDatabase.execSQL("CREATE TRIGGER reject_root_ack BEFORE INSERT ON cloud_records WHEN NEW.record_id = '$rootId' BEGIN SELECT RAISE(ABORT, 'root ACK failure'); END")
        val failure=runCatching{store.acknowledgeInvestmentWalletMutation(source.pending!!,result(source.record!!),source)}.exceptionOrNull()
        assertTrue(failure.toString().contains("root ACK failure"))
        assertEquals(source,store.investmentWalletPublicationSnapshot(owner))
    }
    @Test fun finalCallerCancellationRollsBackTheRemoteRootAndQueueDeletion()=runBlocking {
        seed();val source=store.investmentWalletPublicationSnapshot(owner);var task:Deferred<Boolean>?=null
        val guarded=RoomLocalStore(db,currentBillOwner={
            val v=db.openHelper.writableDatabase.query("SELECT sync_version FROM cloud_records WHERE record_id = '$rootId'").use{it.moveToFirst();it.getLong(0)}
            if(v>version)task!!.cancel(CancellationException("Final root ACK fence"))
            active
        })
        task=async(start=CoroutineStart.LAZY){guarded.acknowledgeInvestmentWalletMutation(source.pending!!,result(source.record!!),source)}
        task.start();assertTrue(runCatching{task.await()}.exceptionOrNull() is CancellationException)
        assertEquals(source,store.investmentWalletPublicationSnapshot(owner))
    }
    @Test fun primaryAckCannotImportCloudSuppliedLocalRootEvidence()=runBlocking {
        seed();val source=store.investmentWalletPublicationSnapshot(owner)
        val remote=result(source.record!!).let{it.copy(payload=JsonObject(it.payload+(LOCAL_INVESTMENT_WALLET_PARENTS_KEY to JsonNull)))}
        assertTrue(runCatching{store.acknowledgeInvestmentWalletMutation(source.pending!!,remote,source)}.isFailure)
        assertEquals(source,store.investmentWalletPublicationSnapshot(owner))
    }
    private data class ReceiptCase(val old:InvestmentWalletPublicationSnapshot,val sent:JsonObject,val compared:Long,val remote:CloudRecord)
    private suspend fun receiptCase():ReceiptCase {
        seed();val old=store.investmentWalletPublicationSnapshot(owner);val raw=requireNotNull(old.record)
        val nextId="55555555-5555-5555-5555-555555555555"
        val target=wallet(nextId);store.commitMutation(target,mutation(target))
        val targetQ=store.pendingMutations(owner,CloudEntity.LEDGER_WALLET,Long.MAX_VALUE).single{it.mutation.recordId==nextId}
        assertTrue(store.acknowledgeMutation(targetQ,result(target)))
        OfflineFirstInvestmentRepository(store).changeLinkedWallet(owner,InvestmentWalletLinkRequest(
            LedgerWalletRecord.fromCloudRecord(raw),LedgerWalletRecord.fromCloudRecord(target),"66666666-6666-6666-6666-666666666666",false,0,"Move cash"),device,"2026-10-26T00:15:00Z").getOrThrow()
        val current=store.investmentWalletPublicationSnapshot(owner)
        assertTrue(store.recordInvestmentWalletMutationFailure(current.pending!!,34000,"network_io",current))
        val sent=investmentWalletPayloadForCloud(JsonObject(raw.payload+("sync_version" to JsonPrimitive(version+8))))
        val remote=raw.copy(syncVersion=version+8,updatedAt="2026-10-26T00:30:00Z",payload=JsonObject(sent+("updated_at" to JsonPrimitive("2026-10-26T00:30:00Z"))))
        return ReceiptCase(old,sent,version+7,remote)
    }
    @Test fun definiteReceiptChangesOnlyPrivateEvidenceInTheNewerExactRowAndQueue()=runBlocking {
        val f=receiptCase();val before=store.investmentWalletPublicationSnapshot(owner)
        val oldQueue=requireNotNull(before.pending);val beforeRecord=requireNotNull(before.record)
        val stored=db.cloudRecordDao().record(owner.value,CloudEntity.LEDGER_WALLET.table,rootId)!!
        assertTrue(store.recordInvestmentWalletPublicationReceipt(f.old.pending!!,f.sent,f.compared,f.remote))
        val after=store.investmentWalletPublicationSnapshot(owner);val afterRecord=requireNotNull(after.record)
        assertEquals(investmentWalletPayloadForCloud(beforeRecord.payload),investmentWalletPayloadForCloud(afterRecord.payload))
        assertEquals(oldQueue.copy(mutation=oldQueue.mutation.copy(payload=afterRecord.payload)),after.pending)
        assertEquals(stored.copy(payloadJson=afterRecord.payload.toString()),db.cloudRecordDao().record(owner.value,CloudEntity.LEDGER_WALLET.table,rootId))
        assertTrue(after.matches(after.pending!!));assertTrue(isKnownPriorInvestmentWalletPublication(afterRecord,f.remote,device))
        assertEquals(before.linkedRecord,after.linkedRecord);assertEquals(before.linkedPending,after.linkedPending)
    }
    @Test fun receiptRejectsForgedBusinessPayloadVersionAndPrivateCloudEvidence()=runBlocking {
        val f=receiptCase();val before=store.investmentWalletPublicationSnapshot(owner)
        assertTrue(runCatching{store.recordInvestmentWalletPublicationReceipt(f.old.pending!!,JsonObject(f.sent+("investment_linked_wallet_id" to JsonNull)),f.compared,f.remote)}.isFailure)
        assertTrue(runCatching{store.recordInvestmentWalletPublicationReceipt(f.old.pending!!,f.sent,f.compared-1,f.remote)}.isFailure)
        val forged=f.remote.copy(payload=JsonObject(f.remote.payload+(LOCAL_INVESTMENT_WALLET_PARENTS_KEY to JsonNull)))
        assertTrue(runCatching{store.recordInvestmentWalletPublicationReceipt(f.old.pending!!,f.sent,f.compared,forged)}.isFailure)
        assertEquals(before,store.investmentWalletPublicationSnapshot(owner))
    }
    @Test fun receiptOwnerReplacementCancelsBeforeWritingIntoThePreviousPartition()=runBlocking {
        val f=receiptCase();val before=store.investmentWalletPublicationSnapshot(owner);active=other
        assertTrue(runCatching{store.recordInvestmentWalletPublicationReceipt(f.old.pending!!,f.sent,f.compared,f.remote)}.exceptionOrNull() is CancellationException)
        active=owner;assertEquals(before,store.investmentWalletPublicationSnapshot(owner))
    }
    @Test fun receiptQueueInsertFailureRollsBackTheAlreadyWrittenEvidenceRow()=runBlocking {
        val f=receiptCase();val before=store.investmentWalletPublicationSnapshot(owner)
        db.openHelper.writableDatabase.execSQL("CREATE TRIGGER reject_root_receipt BEFORE INSERT ON sync_outbox WHEN NEW.record_id = '$rootId' BEGIN SELECT RAISE(ABORT, 'root receipt queue failure'); END")
        val error=runCatching{store.recordInvestmentWalletPublicationReceipt(f.old.pending!!,f.sent,f.compared,f.remote)}.exceptionOrNull()
        assertTrue(error.toString().contains("root receipt queue failure"));assertEquals(before,store.investmentWalletPublicationSnapshot(owner))
    }
    @Test fun finalCallerCancellationRollsBackBothPrivateReceiptUpdates()=runBlocking {
        val f=receiptCase();val before=store.investmentWalletPublicationSnapshot(owner);val oldPayload=before.record!!.payload.toString()
        var task:Deferred<Boolean>?=null
        val guarded=RoomLocalStore(db,currentBillOwner={
            val p=db.openHelper.writableDatabase.query("SELECT payload_json FROM cloud_records WHERE record_id = '$rootId'").use{it.moveToFirst();it.getString(0)}
            if(p!=oldPayload)task!!.cancel(CancellationException("Final root receipt fence"))
            active
        })
        task=async(start=CoroutineStart.LAZY){guarded.recordInvestmentWalletPublicationReceipt(f.old.pending!!,f.sent,f.compared,f.remote)}
        task.start();assertTrue(runCatching{task.await()}.exceptionOrNull() is CancellationException)
        assertEquals(before,store.investmentWalletPublicationSnapshot(owner))
    }

    @Test fun sameOwnerSessionReplacementAtFinalAckFenceRollsBackQueueDeletion()=runBlocking {
        seed();val before=store.investmentWalletPublicationSnapshot(owner);var token="original"
        val guarded=RoomLocalStore(db,currentBillOwner={
            val v=db.openHelper.writableDatabase.query("SELECT sync_version FROM cloud_records WHERE record_id = '$rootId'").use{it.moveToFirst();it.getLong(0)}
            if(v>version)token="replacement"
            active
        })
        val failure=runCatching{guarded.acknowledgeInvestmentWalletMutation(before.pending!!,result(before.record!!),before,{token=="original"})}.exceptionOrNull()
        assertTrue(failure.toString(),failure is CancellationException)
        assertEquals(before,store.investmentWalletPublicationSnapshot(owner))
    }
    @Test fun sameOwnerSessionReplacementAtFinalFailureFenceRollsBackRetryMetadata()=runBlocking {
        seed();val before=store.investmentWalletPublicationSnapshot(owner);var token="original"
        val guarded=RoomLocalStore(db,currentBillOwner={
            val attempts=db.openHelper.writableDatabase.query("SELECT attempt_count FROM sync_outbox WHERE record_id = '$rootId'").use{it.moveToFirst();it.getInt(0)}
            if(attempts>0)token="replacement"
            active
        })
        val failure=runCatching{guarded.recordInvestmentWalletMutationFailure(before.pending!!,34000,"http_503",before,{token=="original"})}.exceptionOrNull()
        assertTrue(failure.toString(),failure is CancellationException)
        assertEquals(before,store.investmentWalletPublicationSnapshot(owner))
    }
    @Test fun sameOwnerSessionReplacementAtFinalReceiptFenceRollsBackBothPrivateUpdates()=runBlocking {
        val f=receiptCase();val before=store.investmentWalletPublicationSnapshot(owner);val oldPayload=before.record!!.payload.toString();var token="original"
        val guarded=RoomLocalStore(db,currentBillOwner={
            val p=db.openHelper.writableDatabase.query("SELECT payload_json FROM cloud_records WHERE record_id = '$rootId'").use{it.moveToFirst();it.getString(0)}
            if(p!=oldPayload)token="replacement"
            active
        })
        val failure=runCatching{guarded.recordInvestmentWalletPublicationReceipt(f.old.pending!!,f.sent,f.compared,f.remote,{token=="original"})}.exceptionOrNull()
        assertTrue(failure.toString(),failure is CancellationException)
        assertEquals(before,store.investmentWalletPublicationSnapshot(owner))
    }

}
