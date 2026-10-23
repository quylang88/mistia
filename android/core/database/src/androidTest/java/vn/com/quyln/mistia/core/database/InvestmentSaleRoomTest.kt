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
class InvestmentSaleRoomTest {
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
    private suspend fun prepare():InvestmentSaleRequest {
        repo().saveChannel(owner,InvestmentChannelDraft(channel,"Shop"),"VND",device,now).getOrThrow()
        val asset=repo().saveAsset(owner,InvestmentAssetDraft(assetId,channel,"Cards","VND","box"),device,now).getOrThrow()
        val wallet=WalletDraft(id=walletId,name="Cash",kind=WalletKind.CASH,currencyCode="VND",openingBalanceMinor=100).toMutation(owner,null,device,now)
        store.commitMutation(wallet.record,wallet.pending)
        repo().savePurchase(owner,InvestmentPurchaseRequest(InvestmentPurchaseDraft(id,assetId,"2.5","box",70,70,"VND",null,null,null,walletId,70,null,null,"2026-10-22T00:00:00Z","2026-10-22T00:00:00Z"),asset,LedgerWalletRecord.fromCloudRecord(wallet.record),null,"Reserve"),device,now).getOrThrow()
        return InvestmentSaleRequest(InvestmentSaleDraft("77777777-7777-7777-7777-777777777777",assetId,"1","box",50,50,"VND",null,null,null,walletId,null,null,now,now),asset,LedgerWalletRecord.fromCloudRecord(wallet.record),null,"Reserve")
    }
    @Test fun actualSaleCommitsStockCapitalProfitAndCashOnceThenRetriesWithoutWrites()=runBlocking {
        val r=prepare();val saved=repo().saveSale(owner,r,device,now).getOrThrow()
        Assert.assertEquals("sell",saved.payload.financeRawString("kind_raw_value"))
        Assert.assertEquals(28L,saved.payload.financeRawLong("released_cost_basis_minor"));Assert.assertEquals(22L,saved.payload.financeRawLong("realized_profit_loss_minor"))
        val before=store.investmentPurchaseSnapshot(owner)
        val queues=InvestmentSaleSnapshot.entities.associateWith{store.pendingMutations(owner,it,Long.MAX_VALUE)}
        val cash=InvestmentCashReadSnapshot(owner,before.rows.filter{CloudEntity.fromTable(it.entity) in InvestmentCashReadSnapshot.entities})
        Assert.assertEquals(22.toBigInteger(),investmentCashAllocation(cash.walletSnapshot(),"VND").locations.single{it.walletId==walletId}.originalBookedMinor)
        repo().saveSale(owner,r,device,"2026-10-24T00:00:00Z").getOrThrow()
        Assert.assertEquals(before,store.investmentPurchaseSnapshot(owner))
        Assert.assertEquals(queues,InvestmentSaleSnapshot.entities.associateWith{store.pendingMutations(owner,it,Long.MAX_VALUE)})
        Assert.assertTrue(InvestmentSaleSnapshot.entities.all{store.recordsIncludingDeleted(other,it.table).isEmpty()})
    }
    private suspend fun rows()=store.investmentPurchaseSnapshot(owner)
    private suspend fun queues()=InvestmentSaleSnapshot.entities.associateWith{store.pendingMutations(owner,it,Long.MAX_VALUE)}
    @Test fun finalCashAccrualQueueFailureRollsBackSaleCapitalProfitAndAllPendingRows()=runBlocking {
        val r=prepare();val before=rows();val pending=queues()
        db.openHelper.writableDatabase.execSQL("CREATE TRIGGER reject_sale_cash BEFORE INSERT ON sync_outbox WHEN NEW.entity='investment_wallet_postings' AND json_extract(NEW.payload_json, '$.role_raw_value')='cashAccrual' BEGIN SELECT RAISE(ABORT, 'synthetic final sale queue failure'); END")
        Assert.assertTrue(repo().saveSale(owner,r,device,now).isFailure)
        Assert.assertEquals(before,rows());Assert.assertEquals(pending,queues())
    }
    @Test fun replacedAccountAtTypedSaleCommitCancelsWithoutAnyHalfSale()=runBlocking {
        val r=prepare();val before=rows();val pending=queues()
        val racing=object:LocalStore by store {
            override suspend fun commitInvestmentSale(expected:InvestmentSaleSnapshot,request:InvestmentSaleRequest,deviceId:String,now:String):Boolean {
                active=other;return store.commitInvestmentSale(expected,request,deviceId,now)
            }
        }
        Assert.assertTrue(runCatching{repo(racing).saveSale(owner,r,device,now)}.exceptionOrNull() is CancellationException)
        active=owner;Assert.assertEquals(before,rows());Assert.assertEquals(pending,queues())
    }
    @Test fun cancellationAtTheLastFenceRollsBackTheAlreadyCalculatedProfit()=runBlocking {
        val r=prepare();val before=rows();val pending=queues();var checks=0;var target:Deferred<*>?=null
        val cancelling=RoomLocalStore(db,currentBillOwner={checks++;if(checks==4)target!!.cancel(CancellationException("last sale fence"));owner})
        val action=async(start=CoroutineStart.LAZY){cancelling.commitInvestmentSale(before,r,device,now)};target=action;action.start()
        Assert.assertTrue(runCatching{action.await()}.exceptionOrNull() is CancellationException)
        Assert.assertEquals(4,checks);Assert.assertEquals(before,rows());Assert.assertEquals(pending,queues())
    }
    @Test fun concurrentSourceChangeCannotCommitAnOldSaleSnapshot()=runBlocking {
        val r=prepare();val before=rows();val old=before.rows.single{it.id==assetId}
        val raw=old.copy(payload=JsonObject(old.payload+("name" to JsonPrimitive("Newer asset"))))
        store.commitMutation(raw,PendingMutation(CloudEntity.INVESTMENT_ASSET,raw.id,owner.value,MutationKind.UPSERT,raw.payload,now,0,device))
        val current=rows();val pending=queues();Assert.assertFalse(store.commitInvestmentSale(before,r,device,now))
        Assert.assertEquals(current,rows());Assert.assertEquals(pending,queues())
    }
    @Test fun orphanCapitalReturnOutboxCannotBeOverwritten()=runBlocking {
        val r=prepare();val canonical=investmentLedgerIdentity(r.draft.id,"capital-return")
        val raw=CloudRecord(CloudEntity.LEDGER_TRANSACTION.table,canonical,owner.value,buildJsonObject{put("id",canonical);put("user_id",owner.value);put("old","pending")},now,null,0)
        store.commitMutation(raw,PendingMutation(CloudEntity.LEDGER_TRANSACTION,raw.id,owner.value,MutationKind.UPSERT,raw.payload,now,0,device))
        db.openHelper.writableDatabase.execSQL("DELETE FROM cloud_records WHERE owner_user_id=? AND entity=? AND record_id=?",arrayOf(owner.value,raw.entity,raw.id))
        val before=rows();val pending=queues();Assert.assertTrue(repo().saveSale(owner,r,device,now).isFailure)
        Assert.assertEquals(before,rows());Assert.assertEquals(pending,queues())
    }
    @Test fun completeSaleRetryHoldsAnIncoherentProfitPostingQueue()=runBlocking {
        val r=prepare();repo().saveSale(owner,r,device,now).getOrThrow()
        val posting=investmentLedgerIdentity(r.draft.id,"cash-accrual-posting")
        db.openHelper.writableDatabase.execSQL("UPDATE sync_outbox SET payload_json='{}' WHERE owner_user_id=? AND entity='investment_wallet_postings' AND record_id=?",arrayOf(owner.value,posting))
        val before=rows();val pending=queues();Assert.assertTrue(repo().saveSale(owner,r,device,now).isFailure)
        Assert.assertEquals(before,rows());Assert.assertEquals(pending,queues())
    }

}
