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
class InvestmentTradeResultAcknowledgementRoomTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other=UserId("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
    private val channel="22222222-2222-2222-2222-222222222222"
    private val assetId="33333333-3333-3333-3333-333333333333"
    private val walletId="44444444-4444-4444-4444-444444444444"
    private val id="55555555-5555-5555-5555-555555555555"
    private val device="66666666-6666-6666-6666-666666666666"
    private val now="2026-10-26T00:00:00Z"
    private val serverTime="2026-10-26T00:30:00Z"
    private var active=owner
    private lateinit var db:MistiaDatabase
    private lateinit var store:RoomLocalStore
    private lateinit var repo:OfflineFirstInvestmentRepository
    @Before fun setup(){db=Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(),MistiaDatabase::class.java).allowMainThreadQueries().build();store=RoomLocalStore(db,currentBillOwner={active});repo=OfflineFirstInvestmentRepository(store)}
    @After fun close(){db.close()}
    private suspend fun seed() {
        val asset=InvestmentAssetRecord(assetId,owner.value,channel,"Cards","VND",null,"box",0,false,null,now,now,null,0,device)
        val channelRow=InvestmentChannelRecord(channel,owner.value,"Shop","shippingbox.fill","#9A67FF",0,false,null,now,now,null,0,device).toCloudRecord()
        val wallet=WalletDraft(id=walletId,name="Cash",kind=WalletKind.CASH,currencyCode="VND",openingBalanceMinor=1000).toMutation(owner,null,device,now).record
        val root=WalletDraft(id=investmentSystemWalletId(owner),name="Investment",kind=WalletKind.CASH,currencyCode="VND").toMutation(owner,null,device,now).record.let{
            it.copy(payload=JsonObject(it.payload+buildJsonObject{put("kind_raw_value","investment");put("system_purpose_raw_value","investmentProfit")}))
        }
        for(raw in listOf(asset.toCloudRecord(),channelRow,wallet,root)) {
            val entity=CloudEntity.fromTable(raw.entity)!!
            store.commitMutation(raw,PendingMutation(entity,raw.id,owner.value,MutationKind.UPSERT,raw.payload,now,0,device))
            val q=store.pendingMutations(owner,entity,Long.MAX_VALUE).single{it.mutation.recordId==raw.id}
            assertTrue(store.acknowledgeMutation(q,raw.copy(syncVersion=1,payload=JsonObject(raw.payload+("sync_version" to JsonPrimitive(1))))))
        }
        val context=store.investmentPurchaseSnapshot(owner)
        repo.savePurchase(owner,InvestmentPurchaseRequest(InvestmentPurchaseDraft(id,assetId,"2.5","box",70,70,"VND",null,null,null,walletId,70,null,null,now,now),
            InvestmentAssetRecord.fromCloudRecord(context.rows.single{it.id==assetId}),LedgerWalletRecord.fromCloudRecord(context.rows.single{it.id==walletId}),null,"Reserve"),device,now).getOrThrow()
    }
    private suspend fun source()=store.investmentTradePublicationSnapshot(owner,id)
    private fun candidate(source:InvestmentTradePublicationSnapshot):InvestmentTradeCloudSnapshot {
        val rows=source.rows.filter{it.entity in setOf(CloudEntity.INVESTMENT_TRADE.table,CloudEntity.LEDGER_TRANSACTION.table,CloudEntity.INVESTMENT_POSTING.table)}.map{raw->
            val version=if(raw.entity==CloudEntity.INVESTMENT_TRADE.table)2L else 1L
            raw.copy(syncVersion=version,updatedAt=serverTime,payload=JsonObject(raw.payload+buildJsonObject{put("sync_version",version);put("updated_at",serverTime)}))
        }
        return InvestmentTradeCloudSnapshot(owner,setOf(assetId),rows)
    }
    @Test fun completeResultAtomicallyConsumesTradeAndChildrenAndImportsActualServerVersions()=runBlocking {
        seed();val before=source();val remote=candidate(before)
        assertEquals(3,before.pending.size);assertTrue(store.acknowledgeInvestmentTradeResult(before,remote,device,serverTime))
        val after=source();after.requireCoherent();assertTrue(after.pending.isEmpty());assertTrue(after.dirtyKeys.isEmpty())
        remote.rows.forEach{raw->assertEquals(raw,after.rows.single{it.entity==raw.entity && it.id==raw.id})}
        assertFalse(store.acknowledgeInvestmentTradeResult(before,remote,device,serverTime));assertEquals(after,source())
    }
    @Test fun aNewerTradeNoteAndItsQueueSurviveTheOlderResult()=runBlocking {
        seed();val before=source();val remote=candidate(before);val old=before.requestedRecord!!
        val newer=old.copy(updatedAt="2026-10-26T00:15:00Z",payload=JsonObject(old.payload+buildJsonObject{put("note","New user note");put("updated_at","2026-10-26T00:15:00Z")}))
        store.commitMutation(newer,PendingMutation(CloudEntity.INVESTMENT_TRADE,id,owner.value,MutationKind.UPSERT,newer.payload,newer.updatedAt!!,newer.syncVersion,device))
        val current=source();assertFalse(store.acknowledgeInvestmentTradeResult(before,remote,device,serverTime));assertEquals(current,source())
        assertTrue(runCatching{store.acknowledgeInvestmentTradeResult(current,remote,device,serverTime)}.isFailure);assertEquals(current,source())
    }
    @Test fun anInvalidFinancialAmountCannotPartiallyConsumeTheParentOrSiblingQueues()=runBlocking {
        seed();val before=source();val remote=candidate(before).let{it.copy(rows=it.rows.map{raw->if(raw.entity==CloudEntity.LEDGER_TRANSACTION.table)raw.copy(payload=JsonObject(raw.payload+("amount_minor" to JsonPrimitive(71)))) else raw})}
        val error=runCatching{store.acknowledgeInvestmentTradeResult(before,remote,device,serverTime)}.exceptionOrNull()
        assertEquals(InvestmentTradeResultError.INVALID_RESULT,(error as? InvestmentTradeResultException)?.reason);assertEquals(before,source())
    }
    @Test fun aLateInsertFailureRollsBackAllEarlierQueueRemovalsAndImports()=runBlocking {
        seed();val before=source();val remote=candidate(before);val ledger=investmentLedgerIdentity(id,"funding")
        db.openHelper.writableDatabase.execSQL("CREATE TRIGGER reject_trade_result BEFORE INSERT ON cloud_records WHEN NEW.record_id = '$ledger' BEGIN SELECT RAISE(ABORT, 'trade result insert failure'); END")
        val error=runCatching{store.acknowledgeInvestmentTradeResult(before,remote,device,serverTime)}.exceptionOrNull()
        assertTrue(error.toString().contains("trade result insert failure"));assertEquals(before,source())
    }
    @Test fun aChangedChildQueueAfterParentRemovalRollsBackTheEntireResult()=runBlocking {
        seed();val before=source();val remote=candidate(before);val ledger=investmentLedgerIdentity(id,"funding")
        db.openHelper.writableDatabase.execSQL("CREATE TRIGGER change_trade_child AFTER DELETE ON sync_outbox WHEN OLD.record_id = '$id' BEGIN UPDATE sync_outbox SET attempt_count = attempt_count + 1 WHERE record_id = '$ledger'; END")
        val error=runCatching{store.acknowledgeInvestmentTradeResult(before,remote,device,serverTime)}.exceptionOrNull()
        assertTrue(error.toString().contains("Trade result queue changed"));assertEquals(before,source())
    }
    @Test fun finalOwnerReplacementRollsBackAlreadyImportedRowsAndDeletedQueues()=runBlocking {
        seed();val before=source();val remote=candidate(before)
        val guarded=RoomLocalStore(db,currentBillOwner={if(currentVersion()>0)other else active})
        assertTrue(runCatching{guarded.acknowledgeInvestmentTradeResult(before,remote,device,serverTime)}.exceptionOrNull() is CancellationException);assertEquals(before,source())
    }
    @Test fun sameOwnerSessionReplacementAtCommitRollsBackTheWholeFinancialResult()=runBlocking {
        seed();val before=source();val remote=candidate(before);var sessionCurrent=true
        val guarded=RoomLocalStore(db,currentBillOwner={if(currentVersion()>0)sessionCurrent=false;active})
        assertTrue(runCatching{guarded.acknowledgeInvestmentTradeResult(before,remote,device,serverTime,{sessionCurrent})}.exceptionOrNull() is CancellationException);assertEquals(before,source())
    }
    @Test fun finalCallerCancellationRollsBackEveryImportAndAcknowledgement()=runBlocking {
        seed();val before=source();val remote=candidate(before);var task:Deferred<Boolean>?=null
        val guarded=RoomLocalStore(db,currentBillOwner={if(currentVersion()>0)task!!.cancel(CancellationException("Final trade result fence"));active})
        task=async(start=CoroutineStart.LAZY){guarded.acknowledgeInvestmentTradeResult(before,remote,device,serverTime)}
        task.start();assertTrue(runCatching{task.await()}.exceptionOrNull() is CancellationException);assertEquals(before,source())
    }
    @Test fun neverPublishedLocalDeletionClearsOnlyAbsentQueuesWithoutInventingRemoteVersions()=runBlocking {
        seed();repo.deleteTrade(owner,InvestmentTradeDeletionRequest(source().requestedRecord!!,null,"Reserve"),device,now).getOrThrow()
        val before=source();assertTrue(before.pending.all{it.mutation.kind==MutationKind.DELETE && it.mutation.baseVersion==0L && !it.remoteIdentityObserved})
        assertTrue(store.acknowledgeInvestmentTradeResult(before,InvestmentTradeCloudSnapshot(owner,setOf(assetId),emptyList()),device,serverTime))
        val after=source();assertEquals(before.rows,after.rows);assertTrue(after.pending.isEmpty());assertTrue(after.dirtyKeys.isEmpty())
    }

    private fun otherDeviceWinner(before:InvestmentTradePublicationSnapshot):InvestmentTradeCloudSnapshot {
        val cloud=candidate(before)
        val rows=cloud.rows.map{raw->
            val fields=buildJsonObject {
                put("last_modified_by_device_id",walletId)
                when(raw.entity) {
                    CloudEntity.INVESTMENT_TRADE.table->{put("gross_amount_minor",90);put("accounting_gross_amount_minor",90);put("funding_wallet_amount_minor",90);put("position_cost_basis_after_minor",90)}
                    CloudEntity.LEDGER_TRANSACTION.table->{put("amount_minor",90);put("reporting_amount_minor",90)}
                    CloudEntity.INVESTMENT_POSTING.table->{put("amount_minor",-90);put("accounting_amount_minor",-90)}
                }
            }
            raw.copy(payload=JsonObject(raw.payload+fields))
        }
        return cloud.copy(rows=rows,remoteIntentWinners=setOf(id))
    }
    @Test fun provenOtherDeviceWinnerReplacesTradeAndBothFinancialChildrenAtomically()=runBlocking {
        seed();val before=source();val remote=otherDeviceWinner(before)
        assertTrue(store.acknowledgeInvestmentTradeResult(before,remote,device,serverTime))
        val after=source();assertTrue(after.pending.isEmpty());assertTrue(after.dirtyKeys.isEmpty());after.requireCoherent()
        assertEquals(90L,after.requestedRecord!!.payload.financeRawLong("gross_amount_minor"))
        assertEquals(-90L,after.rows.single{it.entity==CloudEntity.INVESTMENT_POSTING.table}.payload.financeRawLong("amount_minor"))
    }
    @Test fun aClaimedRemoteWinnerCannotConsumeAnUnprovenOwnOlderBusinessProposal()=runBlocking {
        seed();val before=source();val remote=otherDeviceWinner(before).let{it.copy(rows=it.rows.map{raw->raw.copy(payload=JsonObject(raw.payload+("last_modified_by_device_id" to JsonPrimitive(device))))})}
        assertTrue(runCatching{store.acknowledgeInvestmentTradeResult(before,remote,device,serverTime)}.isFailure);assertEquals(before,source())
    }
    @Test fun aWinnerWithMalformedMoneyLeavesEveryOriginalQueueAndRowIntact()=runBlocking {
        seed();val before=source();val remote=otherDeviceWinner(before).let{it.copy(rows=it.rows.map{raw->if(raw.entity==CloudEntity.LEDGER_TRANSACTION.table)raw.copy(payload=JsonObject(raw.payload+("amount_minor" to JsonPrimitive(91)))) else raw})}
        assertTrue(runCatching{store.acknowledgeInvestmentTradeResult(before,remote,device,serverTime)}.isFailure);assertEquals(before,source())
    }
    @Test fun completeOtherDeviceTombstonesReconcileTheLosingLiveIntentAndItsChildren()=runBlocking {
        seed();val before=source();val remote=candidate(before).let{it.copy(remoteIntentWinners=setOf(id),rows=it.rows.map{raw->
            raw.copy(deletedAt=serverTime,payload=JsonObject(raw.payload+buildJsonObject{put("deleted_at",serverTime);put("last_modified_by_device_id",walletId)}))
        })}
        assertTrue(store.acknowledgeInvestmentTradeResult(before,remote,device,serverTime));val after=source()
        assertTrue(after.pending.isEmpty());assertTrue(after.rows.filter{it.entity in setOf(CloudEntity.INVESTMENT_TRADE.table,CloudEntity.LEDGER_TRANSACTION.table,CloudEntity.INVESTMENT_POSTING.table)}.all{it.deletedAt==serverTime})
    }

    @Test fun genericPullCannotReplaceACleanTradeWithForgedRemoteCausalEvidence()=runBlocking {
        seed();val initial=source();store.acknowledgeInvestmentTradeResult(initial,candidate(initial),device,serverTime)
        val before=source();val forged=before.requestedRecord!!.let{it.copy(payload=JsonObject(it.payload+(LOCAL_TRADE_PUBLICATION_PARENTS_KEY to JsonNull)))}
        val error=runCatching{store.replacePullSnapshot(owner,CloudEntity.INVESTMENT_TRADE.table,listOf(forged))}.exceptionOrNull()
        assertTrue(error is IllegalArgumentException);assertEquals(before,source())
    }
    @Test fun genericTradePullRefusesForeignOwnerRowsBeforeDeletingTheCleanSnapshot()=runBlocking {
        seed();val initial=source();store.acknowledgeInvestmentTradeResult(initial,candidate(initial),device,serverTime)
        val before=source();val foreign=before.requestedRecord!!.let{it.copy(ownerUserId=other.value,payload=JsonObject(it.payload+("user_id" to JsonPrimitive(other.value))))}
        val error=runCatching{store.replacePullSnapshot(owner,CloudEntity.INVESTMENT_TRADE.table,listOf(foreign))}.exceptionOrNull()
        assertTrue(error is IllegalArgumentException);assertEquals(before,source())
    }

    private fun nextTrade(raw:CloudRecord)=raw.copy(syncVersion=3,payload=JsonObject(raw.payload+("sync_version" to JsonPrimitive(3))))
    @Test fun genericTradePullRejectsAReplacedOwnerBeforeAnySnapshotMutation()=runBlocking {
        seed();val initial=source();store.acknowledgeInvestmentTradeResult(initial,candidate(initial),device,serverTime)
        val before=source();val guarded=RoomLocalStore(db,currentBillOwner={other})
        val error=runCatching{guarded.replacePullSnapshot(owner,CloudEntity.INVESTMENT_TRADE.table,listOf(nextTrade(before.requestedRecord!!)))}.exceptionOrNull()
        assertTrue(error is CancellationException);assertEquals(before,source())
    }
    @Test fun genericTradePullRollsBackACleanReplacementWhenTheOwnerChangesAtCommit()=runBlocking {
        seed();val initial=source();store.acknowledgeInvestmentTradeResult(initial,candidate(initial),device,serverTime)
        val before=source();val guarded=RoomLocalStore(db,currentBillOwner={if(currentVersion()==3L)other else owner})
        val error=runCatching{guarded.replacePullSnapshot(owner,CloudEntity.INVESTMENT_TRADE.table,listOf(nextTrade(before.requestedRecord!!)))}.exceptionOrNull()
        assertTrue(error is CancellationException);assertEquals(before,source())
    }
    @Test fun genericTradePullRollsBackACleanReplacementWhenTheCallerCancelsAtCommit()=runBlocking {
        seed();val initial=source();store.acknowledgeInvestmentTradeResult(initial,candidate(initial),device,serverTime)
        val before=source();var task:Deferred<Unit>?=null
        val guarded=RoomLocalStore(db,currentBillOwner={if(currentVersion()==3L)task!!.cancel(CancellationException("Final trade pull fence"));owner})
        task=async(start=CoroutineStart.LAZY){guarded.replacePullSnapshot(owner,CloudEntity.INVESTMENT_TRADE.table,listOf(nextTrade(before.requestedRecord!!)))};task.start()
        assertTrue(runCatching{task.await()}.exceptionOrNull() is CancellationException);assertEquals(before,source())
    }
    private fun currentVersion()=db.openHelper.writableDatabase.query("SELECT sync_version FROM cloud_records WHERE record_id = '$id'").use{it.moveToFirst();it.getLong(0)}
}
