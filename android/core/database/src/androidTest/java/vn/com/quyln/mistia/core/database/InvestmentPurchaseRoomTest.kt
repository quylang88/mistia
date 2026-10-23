package vn.com.quyln.mistia.core.database

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.*
import kotlinx.serialization.json.*
import org.junit.*
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.model.*

@RunWith(AndroidJUnit4::class)
class InvestmentPurchaseRoomTest {
    private lateinit var db:MistiaDatabase
    private lateinit var store:RoomLocalStore
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other=UserId("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
    private val channel="22222222-2222-2222-2222-222222222222"
    private val assetId="33333333-3333-3333-3333-333333333333"
    private val walletId="44444444-4444-4444-4444-444444444444"
    private val id="55555555-5555-5555-5555-555555555555"
    private val device="66666666-6666-6666-6666-666666666666"
    private val now="2026-10-23T00:00:00Z"
    private var active=owner
    @Before fun setup(){db=Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(),MistiaDatabase::class.java).allowMainThreadQueries().build();store=RoomLocalStore(db,currentBillOwner={active})}
    @After fun close(){db.close()}
    private fun repo(source:LocalStore=store)=OfflineFirstInvestmentRepository(source)
    private suspend fun prepare():InvestmentPurchaseRequest {
        repo().saveChannel(owner,InvestmentChannelDraft(channel,"Shop"),"VND",device,now).getOrThrow()
        val asset=repo().saveAsset(owner,InvestmentAssetDraft(assetId,channel,"Cards","VND","box"),device,now).getOrThrow()
        val wallet=WalletDraft(id=walletId,name="Cash",kind=WalletKind.CASH,currencyCode="VND",openingBalanceMinor=100).toMutation(owner,null,device,now)
        store.commitMutation(wallet.record,wallet.pending)
        return InvestmentPurchaseRequest(InvestmentPurchaseDraft(id,assetId,"2.5","box",70,70,"VND",null,null,null,walletId,70,null,null,now,now),asset,LedgerWalletRecord.fromCloudRecord(wallet.record),null,"Reserve")
    }
    @Test fun actualPurchaseWritesExactStockFundingPostingAndOutboxAndRetryWritesNothing()=runBlocking {
        val r=prepare();val result=repo().savePurchase(owner,r,device,now).getOrThrow()
        Assert.assertEquals("2.5",result.payload.financeRawString("position_quantity_after_decimal_string"))
        Assert.assertEquals(70L,result.payload.financeRawLong("position_cost_basis_after_minor"))
        val before=InvestmentPurchaseSnapshot.entities.associateWith{store.recordsIncludingDeleted(owner,it.table)}
        val queue=InvestmentPurchaseSnapshot.entities.associateWith{store.pendingMutations(owner,it,Long.MAX_VALUE)}
        Assert.assertEquals(1,before.getValue(CloudEntity.INVESTMENT_TRADE).size)
        Assert.assertEquals(1,before.getValue(CloudEntity.LEDGER_TRANSACTION).size)
        Assert.assertEquals(1,before.getValue(CloudEntity.INVESTMENT_POSTING).size)
        repo().savePurchase(owner,r,device,"2026-10-24T00:00:00Z").getOrThrow()
        Assert.assertEquals(before,InvestmentPurchaseSnapshot.entities.associateWith{store.recordsIncludingDeleted(owner,it.table)})
        Assert.assertEquals(queue,InvestmentPurchaseSnapshot.entities.associateWith{store.pendingMutations(owner,it,Long.MAX_VALUE)})
        Assert.assertTrue(InvestmentPurchaseSnapshot.entities.all{store.recordsIncludingDeleted(other,it.table).isEmpty()})
    }
    private suspend fun rows()=store.investmentPurchaseSnapshot(owner)
    private suspend fun queues()=InvestmentPurchaseSnapshot.entities.associateWith{store.pendingMutations(owner,it,Long.MAX_VALUE)}
    @Test fun lateFundingPostingQueueFailureRollsBackStockLedgerAndAllQueues()=runBlocking {
        val r=prepare();val before=rows();val queue=queues()
        db.openHelper.writableDatabase.execSQL("CREATE TRIGGER reject_purchase_posting BEFORE INSERT ON sync_outbox WHEN NEW.entity = 'investment_wallet_postings' BEGIN SELECT RAISE(ABORT, 'synthetic purchase queue failure'); END")
        Assert.assertTrue(repo().savePurchase(owner,r,device,now).isFailure)
        Assert.assertEquals(before,rows());Assert.assertEquals(queue,queues())
    }
    @Test fun accountChangedAtCommitCancelsWithoutForeignOrOldOwnerWrites()=runBlocking {
        val r=prepare();val before=rows();val queue=queues()
        val racing=object:LocalStore by store {
            override suspend fun commitInvestmentPurchase(expected:InvestmentPurchaseSnapshot,request:InvestmentPurchaseRequest,deviceId:String,now:String):Boolean {
                active=other;return store.commitInvestmentPurchase(expected,request,deviceId,now)
            }
        }
        Assert.assertTrue(runCatching{repo(racing).savePurchase(owner,r,device,now)}.exceptionOrNull() is CancellationException)
        active=owner;Assert.assertEquals(before,rows());Assert.assertEquals(queue,queues())
    }
    @Test fun callerCancelledAtLastOwnerFenceRollsBackAlreadyInsertedRows()=runBlocking {
        val r=prepare();val before=rows();val queue=queues();var checks=0;var target:Deferred<*>?=null
        val cancelling=RoomLocalStore(db,currentBillOwner={checks++;if(checks==4)target!!.cancel(CancellationException("last purchase fence"));owner})
        val action=async(start=CoroutineStart.LAZY){cancelling.commitInvestmentPurchase(before,r,device,now)};target=action;action.start()
        Assert.assertTrue(runCatching{action.await()}.exceptionOrNull() is CancellationException)
        Assert.assertEquals(4,checks);Assert.assertEquals(before,rows());Assert.assertEquals(queue,queues())
    }
    @Test fun staleSnapshotCannotCommitAfterSourceChanges()=runBlocking {
        val r=prepare();val before=rows();val old=before.rows.single{it.entity==CloudEntity.INVESTMENT_ASSET.table}
        val changed=old.copy(payload=JsonObject(old.payload+("name" to JsonPrimitive("Changed"))))
        store.commitMutation(changed,PendingMutation(CloudEntity.INVESTMENT_ASSET,old.id,owner.value,MutationKind.UPSERT,changed.payload,now,0,device))
        val current=rows();val queue=queues()
        Assert.assertFalse(store.commitInvestmentPurchase(before,r,device,now));Assert.assertEquals(current,rows());Assert.assertEquals(queue,queues())
    }
    @Test fun orphanFundingQueueCannotBeClaimedAsANewCanonicalIdentity()=runBlocking {
        val r=prepare();val canonical=investmentLedgerIdentity(id,"funding")
        val orphan=CloudRecord(CloudEntity.LEDGER_TRANSACTION.table,canonical,owner.value,buildJsonObject{put("id",canonical);put("user_id",owner.value);put("old","pending")},now,null,0)
        store.commitMutation(orphan,PendingMutation(CloudEntity.LEDGER_TRANSACTION,canonical,owner.value,MutationKind.UPSERT,orphan.payload,now,0,device))
        db.openHelper.writableDatabase.execSQL("DELETE FROM cloud_records WHERE owner_user_id=? AND entity=? AND record_id=?",arrayOf(owner.value,orphan.entity,canonical))
        val before=rows();val queue=queues();Assert.assertTrue(repo().savePurchase(owner,r,device,now).isFailure)
        Assert.assertEquals(before,rows());Assert.assertEquals(queue,queues())
    }
    @Test fun noObserverSeesAPurchaseWithoutItsFundingAndPosting()=runBlocking {
        val r=prepare();val values=java.util.Collections.synchronizedList(mutableListOf<InvestmentPurchaseSnapshot>())
        val job=launch(Dispatchers.Unconfined,start=CoroutineStart.UNDISPATCHED){store.observeInvestmentPurchaseSnapshot(owner).collect{values.add(it)}}
        try {
            withTimeout(5000){while(values.isEmpty())delay(5)};repo().savePurchase(owner,r,device,now).getOrThrow()
            withTimeout(5000){while(values.none{it.rows.any{row->row.entity==CloudEntity.INVESTMENT_TRADE.table}})delay(5)}
        }finally{job.cancelAndJoin()}
        Assert.assertTrue(values.all{s->val present=s.rows.any{it.entity==CloudEntity.INVESTMENT_TRADE.table};
            s.rows.count{it.entity==CloudEntity.LEDGER_TRANSACTION.table}==(if(present)1 else 0) && s.rows.count{it.entity==CloudEntity.INVESTMENT_POSTING.table}==(if(present)1 else 0)})
    }
    @Test fun corruptedPendingKnownResultIsHeldWithoutOverwritingTheQueue()=runBlocking {
        val r=prepare();repo().savePurchase(owner,r,device,now).getOrThrow()
        db.openHelper.writableDatabase.execSQL("UPDATE sync_outbox SET payload_json='{}' WHERE owner_user_id=? AND entity='investment_trades' AND record_id=?",arrayOf(owner.value,id))
        val before=rows();val queue=queues()
        Assert.assertTrue("known result must prove pending payload coherence",repo().savePurchase(owner,r,device,now).isFailure)
        Assert.assertEquals(before,rows());Assert.assertEquals(queue,queues())
    }

    @Test fun pendingDeleteCannotMasqueradeAsACompleteActivePurchase()=runBlocking {
        val r=prepare();repo().savePurchase(owner,r,device,now).getOrThrow()
        db.openHelper.writableDatabase.execSQL("UPDATE sync_outbox SET kind='delete' WHERE owner_user_id=? AND entity='investment_trades' AND record_id=?",arrayOf(owner.value,id))
        val before=rows();val queue=queues();Assert.assertTrue(repo().savePurchase(owner,r,device,now).isFailure)
        Assert.assertEquals(before,rows());Assert.assertEquals(queue,queues())
    }

    @Test fun knownPurchaseProvesPendingCoherenceAcrossTheSameAssetFifoHistory()=runBlocking {
        val first=prepare();repo().savePurchase(owner,first,device,now).getOrThrow()
        val secondId="77777777-7777-7777-7777-777777777777"
        val second=first.copy(draft=first.draft.copy(id=secondId,quantity="1",grossMinor=1,accountingMinor=1,fundingMinor=1))
        repo().savePurchase(owner,second,device,now).getOrThrow()
        db.openHelper.writableDatabase.execSQL("UPDATE sync_outbox SET payload_json='{}' WHERE owner_user_id=? AND entity='investment_trades' AND record_id=?",arrayOf(owner.value,secondId))
        val before=rows();val queue=queues()
        Assert.assertTrue("a complete FIFO history includes its pending publication",repo().savePurchase(owner,first,device,now).isFailure)
        Assert.assertEquals(before,rows());Assert.assertEquals(queue,queues())
    }

}
