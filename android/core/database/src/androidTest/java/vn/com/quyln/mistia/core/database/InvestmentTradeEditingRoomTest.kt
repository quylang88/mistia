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
class InvestmentTradeEditingRoomTest {
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
    private suspend fun prepare():InvestmentTradeEditRequest {
        repo().saveChannel(owner,InvestmentChannelDraft(channel,"Shop"),"VND",device,now).getOrThrow()
        val asset=repo().saveAsset(owner,InvestmentAssetDraft(assetId,channel,"Cards","VND","box"),device,now).getOrThrow()
        val wallet=WalletDraft(id=walletId,name="Cash",kind=WalletKind.CASH,currencyCode="VND",openingBalanceMinor=100).toMutation(owner,null,device,now)
        store.commitMutation(wallet.record,wallet.pending)
        val buy=repo().savePurchase(owner,InvestmentPurchaseRequest(InvestmentPurchaseDraft(id,assetId,"2.5","box",70,70,"VND",null,null,null,walletId,70,null,null,"2026-10-22T00:00:00Z","2026-10-22T00:00:00Z"),asset,LedgerWalletRecord.fromCloudRecord(wallet.record),null,"Reserve"),device,now).getOrThrow()
        return InvestmentTradeEditRequest(buy,InvestmentTradeEditDraft(id,assetId,InvestmentTradeKind.BUY,"2.5","box",80,80,"VND",null,null,null,walletId,80,null,"Edited", "2026-10-22T00:00:00Z","2026-10-22T00:00:00Z"),asset,LedgerWalletRecord.fromCloudRecord(wallet.record),null,"Reserve")
    }
    private suspend fun rows()=store.investmentPurchaseSnapshot(owner)
    private suspend fun queues()=InvestmentTradeCreationSnapshot.entities.associateWith{store.pendingMutations(owner,it,Long.MAX_VALUE)}
    @Test fun actualEditChangesTheOriginalTradeAndAtomicallyPublishesItsCompleteResult()=runBlocking {
        val r=prepare();val result=repo().editTrade(owner,r,device,now).getOrThrow()
        Assert.assertEquals(id,result.id);Assert.assertEquals(80L,result.payload.financeRawLong("gross_amount_minor"))
        val after=rows();val pending=queues()
        Assert.assertEquals(20.toBigInteger(),financeWalletBalancesRaw(owner,after.rows.filter{it.entity==CloudEntity.LEDGER_TRANSACTION.table},after.rows.filter{it.entity==CloudEntity.LEDGER_WALLET.table},setOf(walletId))?.get(walletId))
        Assert.assertEquals(3,pending.values.flatten().count{it.mutation.entity in setOf(CloudEntity.INVESTMENT_TRADE,CloudEntity.INVESTMENT_POSTING,CloudEntity.LEDGER_TRANSACTION)})
        repo().editTrade(owner,r,device,"2026-10-24T00:00:00Z").getOrThrow();Assert.assertEquals(after,rows());Assert.assertEquals(pending,queues())
    }
    @Test fun finalEditQueueFailureRollsBackEveryRecordAndPendingMutation()=runBlocking {
        val r=prepare();val before=rows();val pending=queues();val last=planInvestmentTradeEdit(before,r,device,now).mutations.last().first
        db.openHelper.writableDatabase.execSQL("CREATE TRIGGER reject_last_trade_edit BEFORE INSERT ON sync_outbox WHEN NEW.record_id='"+last.id+"' BEGIN SELECT RAISE(ABORT, 'synthetic last edit failure'); END")
        Assert.assertTrue(repo().editTrade(owner,r,device,now).isFailure);Assert.assertEquals(before,rows());Assert.assertEquals(pending,queues())
    }
    @Test fun ownerReplacementAtEditCommitCancelsAndPreservesTheOriginal()=runBlocking {
        val r=prepare();val before=rows();val pending=queues()
        val racing=object:LocalStore by store{override suspend fun commitInvestmentTradeEdit(expected:InvestmentTradeCreationSnapshot,request:InvestmentTradeEditRequest,deviceId:String,now:String):Boolean{active=other;return store.commitInvestmentTradeEdit(expected,request,deviceId,now)}}
        Assert.assertTrue(runCatching{repo(racing).editTrade(owner,r,device,now)}.exceptionOrNull() is CancellationException)
        active=owner;Assert.assertEquals(before,rows());Assert.assertEquals(pending,queues())
    }
    @Test fun movedResultRetryStillProtectsTheOriginalHistoryPublication()=runBlocking {
        val r=prepare();val secondId="77777777-7777-7777-7777-777777777777"
        repo().savePurchase(owner,InvestmentPurchaseRequest(InvestmentPurchaseDraft(secondId,assetId,"1","box",10,10,"VND",null,null,null,walletId,10,null,null,now,now),r.expectedAsset,r.expectedWallet,null,"Reserve"),device,now).getOrThrow()
        val target=repo().saveAsset(owner,InvestmentAssetDraft("88888888-8888-8888-8888-888888888888",channel,"Other","VND","box"),device,now).getOrThrow()
        val move=r.copy(expectedAsset=target,draft=r.draft.copy(assetId=target.id));repo().editTrade(owner,move,device,now).getOrThrow()
        db.openHelper.writableDatabase.execSQL("UPDATE sync_outbox SET payload_json='{}' WHERE owner_user_id=? AND entity='ledger_transactions' AND record_id=?",arrayOf(owner.value,investmentLedgerIdentity(secondId,"funding")))
        val before=rows();val pending=queues();Assert.assertTrue(repo().editTrade(owner,move,device,now).isFailure);Assert.assertEquals(before,rows());Assert.assertEquals(pending,queues())
    }
    @Test fun actualCallerCancellationAtTheFinalFenceRollsBackEditedRowsAndQueues()=runBlocking {
        val r=prepare();val before=rows();val pending=queues();var checks=0;var target:Deferred<*>?=null
        val cancelling=RoomLocalStore(db,currentBillOwner={checks++;if(checks==4)target!!.cancel(CancellationException("last trade edit fence"));owner})
        val action=async(start=CoroutineStart.LAZY){cancelling.commitInvestmentTradeEdit(before,r,device,now)};target=action;action.start()
        Assert.assertTrue(runCatching{action.await()}.exceptionOrNull() is CancellationException)
        Assert.assertEquals(4,checks);Assert.assertEquals(before,rows());Assert.assertEquals(pending,queues())
    }
    @Test fun changedFullSourceCannotCommitAnOlderEditSnapshot()=runBlocking {
        val r=prepare();val before=rows();val wallet=before.rows.single{it.entity==CloudEntity.LEDGER_WALLET.table && it.id==walletId}
        val raw=wallet.copy(payload=JsonObject(wallet.payload+("opening_balance_minor" to JsonPrimitive(101L))))
        store.commitMutation(raw,PendingMutation(CloudEntity.LEDGER_WALLET,raw.id,owner.value,MutationKind.UPSERT,raw.payload,now,raw.syncVersion,device))
        val current=rows();val pending=queues();Assert.assertFalse(store.commitInvestmentTradeEdit(before,r,device,now));Assert.assertEquals(current,rows());Assert.assertEquals(pending,queues())
    }

    @Test fun coherentButMalformedRetiredFinancialPublicationCannotPassKnownResultRetry()=runBlocking {
        val r=prepare().let{it.copy(expectedWallet=null,draft=it.draft.copy(grossMinor=0,accountingMinor=0,walletId=null,walletMinor=null))}
        repo().editTrade(owner,r,device,now).getOrThrow()
        val id=investmentLedgerIdentity(r.expectedTrade.id,"funding-posting");val old=store.record(owner,CloudEntity.INVESTMENT_POSTING.table,id)!!
        val raw=old.copy(payload=JsonObject(old.payload+("amount_minor" to JsonPrimitive(-69L))))
        store.commitMutation(raw,PendingMutation(CloudEntity.INVESTMENT_POSTING,id,owner.value,MutationKind.DELETE,raw.payload,requireNotNull(raw.updatedAt),raw.syncVersion,device))
        val before=rows();val pending=queues();val e=repo().editTrade(owner,r,device,now).exceptionOrNull()
        Assert.assertEquals(InvestmentAssetError.INVALID_ACCOUNTING,(e as? InvestmentAssetException)?.reason);Assert.assertEquals(before,rows());Assert.assertEquals(pending,queues())
    }

}
