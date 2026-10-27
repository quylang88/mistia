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
class InvestmentTradePublicationReceiptRoomTest {
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
    private fun version(raw:CloudRecord,v:Long)=raw.copy(syncVersion=v,updatedAt=serverTime,payload=JsonObject(investmentTradePayloadForCloud(raw.payload)+buildJsonObject{put("sync_version",v);put("updated_at",serverTime)}))
    private fun receipt(s:InvestmentTradePublicationSnapshot,base:Long=0):InvestmentTradePublicationReceipt {
        val requested=s.requestedRecord!!
        val proposal=version(requested,maxOf(base,requested.syncVersion)+1)
        val rows=s.rows.filter{it.entity==CloudEntity.INVESTMENT_TRADE.table}.map{version(it,if(it.id==id && base>0)proposal.syncVersion+1 else 2)}
        return InvestmentTradePublicationReceipt(s,proposal,base,rows)
    }
    private suspend fun editNote(tradeId:String=id,note:String="New user note") {
        val context=store.investmentPurchaseSnapshot(owner);val old=context.rows.single{it.entity==CloudEntity.INVESTMENT_TRADE.table && it.id==tradeId}
        val p=old.payload
        repo.editTrade(owner,InvestmentTradeEditRequest(old,InvestmentTradeEditDraft(old.id,assetId,InvestmentTradeKind.BUY,
            p.financeRawString("quantity_decimal_string")!!,"box",70,70,"VND",null,null,null,walletId,70,null,note,now,now),
            InvestmentAssetRecord.fromCloudRecord(context.rows.single{it.id==assetId}),LedgerWalletRecord.fromCloudRecord(context.rows.single{it.id==walletId}),null,"Reserve"),device,"2026-10-26T00:15:00Z").getOrThrow()
    }
    private fun withoutJournal(s:InvestmentTradePublicationSnapshot)=s.copy(rows=s.rows.map{it.copy(payload=JsonObject(it.payload-LOCAL_TRADE_PUBLICATION_PARENTS_KEY))},pending=s.pending.map{it.copy(mutation=it.mutation.copy(payload=it.mutation.payload?.let{p->JsonObject(p-LOCAL_TRADE_PUBLICATION_PARENTS_KEY)}))})
    @Test fun definiteHigherBaseReceiptPreservesNewerActualRepositoryEditAndEveryQueueStamp()=runBlocking {
        seed();val old=source();val r=receipt(old,11);editNote();val before=source()
        assertEquals(1,store.recordInvestmentTradePublicationReceipt(r));val after=source();after.requireCoherent()
        assertEquals(withoutJournal(before),withoutJournal(after));assertTrue(isKnownPriorInvestmentTradePublication(after.requestedRecord!!,r.returned.single(),device))
        assertEquals(0,store.recordInvestmentTradePublicationReceipt(r));assertEquals(after,source())
    }
    @Test fun unchangedPendingTradeGetsAReceiptBeforeItsNextActualEdit()=runBlocking {
        seed();val before=source();val r=receipt(before,11)
        assertEquals(1,store.recordInvestmentTradePublicationReceipt(r));editNote()
        assertTrue(isKnownPriorInvestmentTradePublication(source().requestedRecord!!,r.returned.single(),device))
        assertEquals(before.pending.map{it.mutation.baseVersion},source().pending.map{it.mutation.baseVersion})
    }
    @Test fun allOtherPendingTradesRebuiltByTheSameRpcKeepTheirDefiniteReceipts()=runBlocking {
        seed();val second="77777777-7777-7777-7777-777777777777";val context=store.investmentPurchaseSnapshot(owner)
        repo.savePurchase(owner,InvestmentPurchaseRequest(InvestmentPurchaseDraft(second,assetId,"2.5","box",70,70,"VND",null,null,null,walletId,70,null,null,now,now),
            InvestmentAssetRecord.fromCloudRecord(context.rows.single{it.id==assetId}),LedgerWalletRecord.fromCloudRecord(context.rows.single{it.id==walletId}),null,"Reserve"),device,now).getOrThrow()
        val old=source();val r=receipt(old);editNote(second);val before=source()
        assertEquals(2,store.recordInvestmentTradePublicationReceipt(r));val after=source();assertEquals(withoutJournal(before),withoutJournal(after))
        for(remote in r.returned)assertTrue(isKnownPriorInvestmentTradePublication(after.rows.single{it.id==remote.id},remote,device))
    }
    @Test fun anUnrelatedCurrentProposalWithoutCausalEvidenceGetsNoReceipt()=runBlocking {
        seed();val old=source();val r=receipt(old,11);val raw=old.requestedRecord!!
        val changed=raw.copy(payload=JsonObject(raw.payload+("note" to JsonPrimitive("unrelated imported intent"))))
        store.commitMutation(changed,PendingMutation(CloudEntity.INVESTMENT_TRADE,id,owner.value,MutationKind.UPSERT,changed.payload,now,changed.syncVersion,device))
        val before=source();assertEquals(0,store.recordInvestmentTradePublicationReceipt(r));assertEquals(before,source())
    }
    @Test fun aLateOutboxInsertFailureRollsBackTheEarlierRowReceipt()=runBlocking {
        seed();val r=receipt(source(),11);editNote();val before=source()
        db.openHelper.writableDatabase.execSQL("CREATE TRIGGER reject_trade_receipt BEFORE INSERT ON sync_outbox WHEN NEW.record_id = '$id' BEGIN SELECT RAISE(ABORT, 'trade receipt outbox failure'); END")
        val error=runCatching{store.recordInvestmentTradePublicationReceipt(r)}.exceptionOrNull()
        assertTrue(error.toString().contains("trade receipt outbox failure"));assertEquals(before,source())
    }
    @Test fun finalSessionReplacementRollsBackBothReceiptPayloads()=runBlocking {
        seed();val r=receipt(source(),11);editNote();val before=source()
        val guarded=RoomLocalStore(db,currentBillOwner={active})
        val error=runCatching{guarded.recordInvestmentTradePublicationReceipt(r,{!hasConfirmedReceipt()})}.exceptionOrNull()
        assertTrue(error is CancellationException);assertEquals(before,source())
    }
    @Test fun finalOwnerReplacementRollsBackBothReceiptPayloads()=runBlocking {
        seed();val r=receipt(source(),11);editNote();val before=source()
        val guarded=RoomLocalStore(db,currentBillOwner={if(hasConfirmedReceipt())other else active})
        assertTrue(runCatching{guarded.recordInvestmentTradePublicationReceipt(r)}.exceptionOrNull() is CancellationException);assertEquals(before,source())
    }
    @Test fun finalCallerCancellationRollsBackBothReceiptPayloads()=runBlocking {
        seed();val r=receipt(source(),11);editNote();val before=source();var task:Deferred<Int>?=null
        val guarded=RoomLocalStore(db,currentBillOwner={if(hasConfirmedReceipt())task!!.cancel(CancellationException("Trade receipt final fence"));active})
        task=async(start=CoroutineStart.LAZY){guarded.recordInvestmentTradePublicationReceipt(r)};task.start()
        assertTrue(runCatching{task.await()}.exceptionOrNull() is CancellationException);assertEquals(before,source())
    }
    @Test fun invalidDefiniteReplyCannotAddAnyCausalAuthority()=runBlocking {
        seed();val r=receipt(source());editNote();val before=source()
        val error=runCatching{store.recordInvestmentTradePublicationReceipt(r.copy(returned=r.returned.map{version(it,3)}))}.exceptionOrNull()
        assertTrue(error is IllegalArgumentException);assertEquals(before,source())
    }
    private fun hasConfirmedReceipt():Boolean= db.openHelper.writableDatabase.query("SELECT payload_json FROM cloud_records WHERE record_id = '$id'").use{cursor->
        cursor.moveToFirst();val row=Json.parseToJsonElement(cursor.getString(0)).jsonObject
        (row[LOCAL_TRADE_PUBLICATION_PARENTS_KEY] as? JsonObject)?.get("parents")?.jsonArray?.any{it.jsonObject["confirmed_version"]!=JsonNull}==true
    }
}
