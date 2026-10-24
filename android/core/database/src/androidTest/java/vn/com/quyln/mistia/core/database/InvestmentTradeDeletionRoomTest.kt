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
class InvestmentTradeDeletionRoomTest {
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

    @Test fun actualDeletionTombstonesTradeLegsAndQueuesThenRetriesTheCompleteResultWithoutWrites()=runBlocking {
        val sale=repo().saveSale(owner,prepare(),device,now).getOrThrow()
        val r=InvestmentTradeDeletionRequest(sale,null,"Reserve")
        val deleted=repo().deleteTrade(owner,r,device,now).getOrThrow();Assert.assertEquals(now,deleted.deletedAt)
        val after=store.investmentPurchaseSnapshot(owner)
        val cash=InvestmentCashReadSnapshot(owner,after.rows.filter{CloudEntity.fromTable(it.entity) in InvestmentCashReadSnapshot.entities})
        Assert.assertEquals(0.toBigInteger(),investmentCashAllocation(cash.walletSnapshot(),"VND").totalMinor)
        Assert.assertEquals(30.toBigInteger(),financeWalletBalancesRaw(owner,after.rows.filter{it.entity==CloudEntity.LEDGER_TRANSACTION.table},after.rows.filter{it.entity==CloudEntity.LEDGER_WALLET.table},setOf(walletId))?.get(walletId))
        Assert.assertEquals(1,after.rows.count{it.entity==CloudEntity.INVESTMENT_TRADE.table && it.financeRawDeleted(true)==false})
        val pending=InvestmentTradeDeletionSnapshot.entities.associateWith{store.pendingMutations(owner,it,Long.MAX_VALUE)}
        Assert.assertEquals(6,pending.values.flatten().count{it.mutation.kind==MutationKind.DELETE})
        repo().deleteTrade(owner,r,device,"2026-10-24T00:00:00Z").getOrThrow()
        Assert.assertEquals(after,store.investmentPurchaseSnapshot(owner));Assert.assertEquals(pending,InvestmentTradeDeletionSnapshot.entities.associateWith{store.pendingMutations(owner,it,Long.MAX_VALUE)})
    }
    private suspend fun deletion():InvestmentTradeDeletionRequest=InvestmentTradeDeletionRequest(repo().saveSale(owner,prepare(),device,now).getOrThrow(),null,"Reserve")
    private suspend fun rows()=store.investmentPurchaseSnapshot(owner)
    private suspend fun queues()=InvestmentTradeDeletionSnapshot.entities.associateWith{store.pendingMutations(owner,it,Long.MAX_VALUE)}
    @Test fun finalDeleteQueueFailureRollsBackPrimaryAndEveryEarlierTombstone()=runBlocking {
        val r=deletion();val before=rows();val pending=queues();val last=planInvestmentTradeDeletion(before,r,device,now).mutations.last().first
        db.openHelper.writableDatabase.execSQL("CREATE TRIGGER reject_last_trade_delete BEFORE INSERT ON sync_outbox WHEN NEW.record_id='"+last.id+"' AND NEW.kind='delete' BEGIN SELECT RAISE(ABORT, 'synthetic final delete queue failure'); END")
        Assert.assertTrue(repo().deleteTrade(owner,r,device,now).isFailure);Assert.assertEquals(before,rows());Assert.assertEquals(pending,queues())
    }
    @Test fun ownerReplacementAtTypedCommitCancelsWithoutAnyDeletedHalfState()=runBlocking {
        val r=deletion();val before=rows();val pending=queues()
        val racing=object:LocalStore by store{override suspend fun commitInvestmentTradeDeletion(expected:InvestmentTradeDeletionSnapshot,request:InvestmentTradeDeletionRequest,deviceId:String,now:String):Boolean{active=other;return store.commitInvestmentTradeDeletion(expected,request,deviceId,now)}}
        Assert.assertTrue(runCatching{repo(racing).deleteTrade(owner,r,device,now)}.exceptionOrNull() is CancellationException)
        active=owner;Assert.assertEquals(before,rows());Assert.assertEquals(pending,queues())
    }
    @Test fun actualCallerCancellationAtTheFinalFenceRollsBackAllDeletedRowsAndQueues()=runBlocking {
        val r=deletion();val before=rows();val pending=queues();var checks=0;var target:Deferred<*>?=null
        val cancelling=RoomLocalStore(db,currentBillOwner={checks++;if(checks==4)target!!.cancel(CancellationException("last trade delete fence"));owner})
        val action=async(start=CoroutineStart.LAZY){cancelling.commitInvestmentTradeDeletion(before,r,device,now)};target=action;action.start()
        Assert.assertTrue(runCatching{action.await()}.exceptionOrNull() is CancellationException)
        Assert.assertEquals(4,checks);Assert.assertEquals(before,rows());Assert.assertEquals(pending,queues())
    }
    @Test fun changedFullSourceCannotCommitAnOlderDeletionSnapshot()=runBlocking {
        val r=deletion();val before=rows();val wallet=before.rows.single{it.entity==CloudEntity.LEDGER_WALLET.table && it.id==walletId}
        val raw=wallet.copy(payload=JsonObject(wallet.payload+("opening_balance_minor" to JsonPrimitive(101L))))
        store.commitMutation(raw,PendingMutation(CloudEntity.LEDGER_WALLET,raw.id,owner.value,MutationKind.UPSERT,raw.payload,now,raw.syncVersion,device))
        val current=rows();val pending=queues();Assert.assertFalse(store.commitInvestmentTradeDeletion(before,r,device,now));Assert.assertEquals(current,rows());Assert.assertEquals(pending,queues())
    }
    @Test fun aCompletedRetryCannotAcceptAnIncoherentDeletedAccrualQueue()=runBlocking {
        val r=deletion();repo().deleteTrade(owner,r,device,now).getOrThrow()
        val posting=investmentLedgerIdentity(r.expectedTrade.id,"cash-accrual-posting")
        db.openHelper.writableDatabase.execSQL("UPDATE sync_outbox SET payload_json='{}' WHERE owner_user_id=? AND entity='investment_wallet_postings' AND record_id=?",arrayOf(owner.value,posting))
        val before=rows();val pending=queues();Assert.assertTrue(repo().deleteTrade(owner,r,device,now).isFailure);Assert.assertEquals(before,rows());Assert.assertEquals(pending,queues())
    }
    @Test fun aRequiredDeletedLegMissingFromStorageCannotBeRepairedByRetry()=runBlocking {
        val r=deletion();repo().deleteTrade(owner,r,device,now).getOrThrow()
        db.openHelper.writableDatabase.execSQL("DELETE FROM cloud_records WHERE owner_user_id=? AND entity='investment_wallet_postings' AND record_id=?",arrayOf(owner.value,investmentLedgerIdentity(r.expectedTrade.id,"cash-accrual-posting")))
        val before=rows();val pending=queues();Assert.assertTrue(repo().deleteTrade(owner,r,device,now).isFailure);Assert.assertEquals(before,rows());Assert.assertEquals(pending,queues())
    }
    @Test fun aNewerPrimaryNoteCannotBeDeletedUsingThePreviouslyConfirmedTrade()=runBlocking {
        val r=deletion();val raw=r.expectedTrade.copy(payload=JsonObject(r.expectedTrade.payload+("note" to JsonPrimitive("Newer note"))))
        store.commitMutation(raw,PendingMutation(CloudEntity.INVESTMENT_TRADE,raw.id,owner.value,MutationKind.UPSERT,raw.payload,now,raw.syncVersion,device))
        val before=rows();val pending=queues();val error=repo().deleteTrade(owner,r,device,now).exceptionOrNull()
        Assert.assertEquals(InvestmentAssetError.STALE_RECORD,(error as? InvestmentAssetException)?.reason);Assert.assertEquals(before,rows());Assert.assertEquals(pending,queues())
    }
    @Test fun historicalFundReviewPrecedesEveryWriteAndConfirmationRetiresAllEffectsTogether()=runBlocking {
        val sale=prepare();val expenseId="aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
        val expense=CloudRecord(CloudEntity.LEDGER_TRANSACTION.table,expenseId,owner.value,buildJsonObject {
            put("id",expenseId);put("user_id",owner.value);put("created_at",now);put("updated_at",now);put("occurred_at","2026-10-24T00:00:00Z");put("deleted_at",JsonNull);put("sync_version",0L)
            put("primary_kind_raw_value","expense");put("entry_status_raw_value","posted");put("settlement_role_raw_value",JsonNull);put("title","Later expense");put("amount_minor",80L);put("source_wallet_id",walletId);put("source_currency_code","VND");put("destination_wallet_id",JsonNull);put("is_archived",false)
        },now,null,0)
        store.commitMutation(expense,PendingMutation(CloudEntity.LEDGER_TRANSACTION,expense.id,owner.value,MutationKind.UPSERT,expense.payload,now,0,device))
        val consent=(repo().saveSale(owner,sale,device,now).exceptionOrNull() as InvestmentSaleConfirmationRequired).review.consent
        val stored=repo().saveSale(owner,sale.copy(consent=consent),device,now).getOrThrow();val r=InvestmentTradeDeletionRequest(stored,null,"Reserve")
        val before=rows();val pending=queues();val error=repo().deleteTrade(owner,r,device,now).exceptionOrNull()
        Assert.assertTrue(error is InvestmentTradeDeletionConfirmationRequired);Assert.assertEquals(before,rows());Assert.assertEquals(pending,queues())
        val review=(error as InvestmentTradeDeletionConfirmationRequired).review;Assert.assertEquals(22.toBigInteger(),review.comparison.changes.single().previousMinor);Assert.assertEquals(0.toBigInteger(),review.comparison.changes.single().proposedMinor)
        val accepted=r.copy(consent=review.consent);repo().deleteTrade(owner,accepted,device,now).getOrThrow()
        val after=rows();Assert.assertNotNull(after.rows.single{it.id==investmentLedgerIdentity(expenseId,"cash-consumption-booked")}.deletedAt)
        val afterQueues=queues();repo().deleteTrade(owner,accepted,device,now).getOrThrow();Assert.assertEquals(after,rows());Assert.assertEquals(afterQueues,queues())
    }

}
