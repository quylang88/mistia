package vn.com.quyln.mistia.core.database

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.util.Collections
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.*
import kotlinx.serialization.json.*
import org.junit.*
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.model.*

@RunWith(AndroidJUnit4::class)
class InvestmentAssetRoomTest {
    private lateinit var db:MistiaDatabase
    private lateinit var store:RoomLocalStore
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other=UserId("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
    private val id="22222222-2222-2222-2222-222222222222"
    private val channelId="33333333-3333-3333-3333-333333333333"
    private val device="44444444-4444-4444-4444-444444444444"
    private val now="2026-10-21T00:00:00Z"
    private var active=owner
    @Before fun setup() {
        db=Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(),MistiaDatabase::class.java).allowMainThreadQueries().build()
        store=RoomLocalStore(db,currentBillOwner={active})
    }
    @After fun close(){db.close()}
    private fun repo(source:LocalStore=store)=OfflineFirstInvestmentRepository(source)
    private fun draft()=InvestmentAssetDraft(id,channelId,"Product","VND","box")
    private suspend fun prepare(){repo().saveChannel(owner,InvestmentChannelDraft(channelId,"Cards"),"VND",device,now).getOrThrow()}
    private suspend fun queues()=InvestmentAssetSnapshot.entities.associateWith{store.pendingMutations(owner,it,Long.MAX_VALUE)}
    private fun mutation(row:CloudRecord)=row to PendingMutation(CloudEntity.fromTable(row.entity)!!,row.id,row.ownerUserId,MutationKind.UPSERT,row.payload,now,row.syncVersion,device)

    @Test fun actualCreateKeepsAssetAndOutboxOwnedAndDoesNotRewriteTheCanonicalWallet()=runBlocking {
        prepare();val before=store.recordsIncludingDeleted(owner,CloudEntity.LEDGER_WALLET.table)
        val saved=repo().saveAsset(owner,draft(),device,now).getOrThrow()
        val snapshot=store.investmentAssetSnapshot(owner)
        Assert.assertEquals(saved.toCloudRecord(),snapshot.records(CloudEntity.INVESTMENT_ASSET).single())
        Assert.assertEquals(1,store.pendingMutations(owner,CloudEntity.INVESTMENT_ASSET,Long.MAX_VALUE).size)
        Assert.assertEquals(3,queues().values.sumOf{it.size});Assert.assertEquals(before,snapshot.records(CloudEntity.LEDGER_WALLET))
        Assert.assertTrue(InvestmentAssetSnapshot.entities.all{store.recordsIncludingDeleted(other,it.table).isEmpty()})
    }
    @Test fun failedQueueInsertRollsBackAnAlreadyInsertedAsset()=runBlocking {
        prepare();val before=store.investmentAssetSnapshot(owner);val pending=queues()
        db.openHelper.writableDatabase.execSQL("CREATE TRIGGER reject_asset_queue BEFORE INSERT ON sync_outbox WHEN NEW.entity = 'investment_assets' BEGIN SELECT RAISE(ABORT, 'synthetic asset queue failure'); END")
        Assert.assertTrue(repo().saveAsset(owner,draft(),device,now).isFailure)
        Assert.assertEquals(before,store.investmentAssetSnapshot(owner));Assert.assertEquals(pending,queues())
    }
    @Test fun accountReplacementBeforeAtomicCommitCancelsWithoutCreatingForeignOrOldOwnerAsset()=runBlocking {
        prepare();val before=store.investmentAssetSnapshot(owner);val pending=queues()
        val racing=object:LocalStore by store {
            override suspend fun commitInvestmentAssetMutation(expected:InvestmentAssetSnapshot,request:InvestmentAssetRequest,deviceId:String,now:String):Boolean {
                active=other;return store.commitInvestmentAssetMutation(expected,request,deviceId,now)
            }
        }
        val result=runCatching{repo(racing).saveAsset(owner,draft(),device,now)}
        Assert.assertTrue(result.exceptionOrNull() is CancellationException)
        active=owner;Assert.assertEquals(before,store.investmentAssetSnapshot(owner));Assert.assertEquals(pending,queues())
        Assert.assertTrue(InvestmentAssetSnapshot.entities.all{store.recordsIncludingDeleted(other,it.table).isEmpty()})
    }
    @Test fun sixEntityReadNeverMixesAssetTradeWalletChannelLedgerOrPostingGenerations()=runBlocking {
        suspend fun batch(generation:Int) {
            store.commitMutations(InvestmentAssetSnapshot.entities.map{entity ->
                mutation(CloudRecord(entity.table,id,owner.value,buildJsonObject {
                    put("id",id);put("user_id",owner.value);put("updated_at",now);put("generation",generation)
                },now,null,0))
            })
        }
        batch(0);val observed=AtomicInteger(-1);val reads=Collections.synchronizedList(mutableListOf<List<Int>>())
        val job=launch(Dispatchers.Unconfined,start=CoroutineStart.UNDISPATCHED) {
            store.observeInvestmentAssetSnapshot(owner).collect{snapshot ->
                val values=InvestmentAssetSnapshot.entities.map{snapshot.records(it).single().payload.getValue("generation").jsonPrimitive.int}
                reads.add(values);if(values.distinct().size==1)observed.set(values.first())
            }
        }
        try {
            withTimeout(5000){while(observed.get()<0)delay(5)}
            for(generation in 1..16){batch(generation);withTimeout(5000){while(observed.get()<generation)delay(5)}}
        }finally{job.cancelAndJoin()}
        Assert.assertTrue(reads.isNotEmpty())
        Assert.assertEquals(emptyList<List<Int>>(),synchronized(reads){reads.filter{it.distinct().size!=1}})
    }
    private suspend fun legacyAssetWithHistory():InvestmentAssetRecord {
        prepare()
        val asset=InvestmentAssetRecord(id,owner.value,channelId,"Legacy product","VND",null,null,0,false,null,now,now,null,9007199254740993L,device)
        val funding="88888888-8888-8888-8888-888888888888"
        val capital="99999999-9999-9999-9999-999999999999"
        val wallets=listOf(funding,capital).map {walletId ->
            WalletDraft(id=walletId,name="VND",kind=WalletKind.CASH,currencyCode="VND").toMutation(owner,null,device,now).record
        }
        fun trade(tradeId:String,kind:String,gross:Long)=CloudRecord(CloudEntity.INVESTMENT_TRADE.table,tradeId,owner.value,buildJsonObject {
            put("id",tradeId);put("user_id",owner.value);put("channel_id",channelId);put("asset_id",id)
            put("kind_raw_value",kind);put("quantity_decimal_string","1");put("unit_label",JsonNull)
            put("gross_amount_minor",gross);put("currency_code","VND");put("accounting_gross_amount_minor",gross);put("accounting_currency_code","VND")
            put("funding_wallet_id",if(kind=="buy")JsonPrimitive(funding) else JsonNull)
            put("capital_return_wallet_id",if(kind=="sell")JsonPrimitive(capital) else JsonNull)
            put("funding_to_accounting_rate_decimal_string",JsonNull);put("accounting_to_capital_return_rate_decimal_string",JsonNull)
            put("funding_wallet_amount_minor",if(kind=="buy")JsonPrimitive(gross) else JsonNull)
            for(key in listOf("funding_ledger_transaction_id","capital_return_ledger_transaction_id","profit_loss_ledger_transaction_id"))put(key,JsonNull)
            put("occurred_at",if(kind=="buy")"2026-10-20T00:00:00Z" else now);put("created_at",now);put("updated_at",now);put("deleted_at",JsonNull)
            put("released_cost_basis_minor",0L);put("realized_profit_loss_minor",0L);put("position_quantity_after_decimal_string","0");put("position_cost_basis_after_minor",0L)
            put("sync_version",9007199254740995L);put("last_modified_by_device_id",device);put("future_flag","preserve")
        },now,null,9007199254740995L)
        store.commitMutations((listOf(asset.toCloudRecord())+wallets+listOf(trade("66666666-6666-6666-6666-666666666666","buy",100),
            trade("77777777-7777-7777-7777-777777777777","sell",150))).map(::mutation))
        return asset
    }
    @Test fun actualLegacyResolutionWritesCompleteFinancialBatchWithoutTouchingWalletOpeningBalances()=runBlocking {
        val asset=legacyAssetWithHistory();val wallets=store.recordsIncludingDeleted(owner,CloudEntity.LEDGER_WALLET.table)
        val saved=repo().saveAsset(owner,draft().copy(expected=asset),device,now).getOrThrow()
        val snapshot=store.investmentAssetSnapshot(owner)
        Assert.assertEquals("box",saved.defaultUnitLabel);Assert.assertEquals(9007199254740993L,saved.syncVersion)
        Assert.assertEquals(wallets,snapshot.records(CloudEntity.LEDGER_WALLET))
        val trades=snapshot.records(CloudEntity.INVESTMENT_TRADE)
        Assert.assertTrue(trades.all{it.payload.financeRawString("unit_label")=="box" && it.syncVersion==9007199254740995L && it.payload.financeRawString("future_flag")=="preserve"})
        val sale=trades.single{it.payload.financeRawString("kind_raw_value")=="sell"}
        Assert.assertEquals(100L,sale.payload.financeRawLong("released_cost_basis_minor"));Assert.assertEquals(50L,sale.payload.financeRawLong("realized_profit_loss_minor"))
        Assert.assertEquals(3,snapshot.records(CloudEntity.LEDGER_TRANSACTION).size)
        val postings=snapshot.records(CloudEntity.INVESTMENT_POSTING);Assert.assertEquals(4,postings.size)
        Assert.assertEquals(50L,postings.single{it.payload.financeRawString("role_raw_value")=="cashAccrual"}.payload.financeRawLong("amount_minor"))
        Assert.assertEquals(14,queues().values.sumOf{it.size})
        Assert.assertEquals(9007199254740993L,store.pendingMutations(owner,CloudEntity.INVESTMENT_ASSET,Long.MAX_VALUE).single().mutation.baseVersion)
        Assert.assertTrue(store.pendingMutations(owner,CloudEntity.INVESTMENT_TRADE,Long.MAX_VALUE).all{it.mutation.baseVersion==9007199254740995L})
    }
    @Test fun lateCashPostingFailureRollsBackAssetTradesLedgerPostingsAndEveryOutboxMutation()=runBlocking {
        val asset=legacyAssetWithHistory();val before=store.investmentAssetSnapshot(owner);val pending=queues()
        db.openHelper.writableDatabase.execSQL("CREATE TRIGGER reject_cash_posting BEFORE INSERT ON cloud_records WHEN NEW.entity = 'investment_wallet_postings' AND json_extract(NEW.payload_json, '$.role_raw_value') = 'cashAccrual' BEGIN SELECT RAISE(ABORT, 'synthetic last cash posting failure'); END")
        Assert.assertTrue(repo().saveAsset(owner,draft().copy(expected=asset),device,now).isFailure)
        Assert.assertEquals(before,store.investmentAssetSnapshot(owner));Assert.assertEquals(pending,queues())
    }
    @Test fun historyAppearingAtCasLocksCurrencyBeforeAnOlderFormCanRewriteIt()=runBlocking {
        prepare();val asset=repo().saveAsset(owner,draft(),device,now).getOrThrow()
        var commits=0
        val racing=object:LocalStore by store {
            override suspend fun commitInvestmentAssetMutation(expected:InvestmentAssetSnapshot,request:InvestmentAssetRequest,deviceId:String,now:String):Boolean {
                commits++
                if(commits==1) {
                    val trade=CloudRecord(CloudEntity.INVESTMENT_TRADE.table,"66666666-6666-6666-6666-666666666666",owner.value,buildJsonObject {
                        put("id","66666666-6666-6666-6666-666666666666");put("user_id",owner.value);put("asset_id",id);put("updated_at",now);put("deleted_at",JsonNull)
                    },now,null,0)
                    store.commitMutations(listOf(mutation(trade)))
                }
                return store.commitInvestmentAssetMutation(expected,request,deviceId,now)
            }
        }
        val result=repo(racing).saveAsset(owner,draft().copy(currencyCode="JPY",expected=asset),device,now)
        Assert.assertEquals(InvestmentAssetError.HISTORY_LOCKS_ACCOUNTING,(result.exceptionOrNull() as? InvestmentAssetException)?.reason)
        Assert.assertEquals(asset.toCloudRecord(),store.record(owner,CloudEntity.INVESTMENT_ASSET.table,id));Assert.assertEquals(1,commits)
    }

    @Test fun archiveRejectsComputedOpenInventoryEvenWhenTheStoredSnapshotSaysZero()=runBlocking {
        val asset=legacyAssetWithHistory()
        val sale=store.recordsIncludingDeleted(owner,CloudEntity.INVESTMENT_TRADE.table).single{it.payload.financeRawString("kind_raw_value")=="sell"}
        store.commitMutations(listOf(mutation(sale.copy(deletedAt=now,payload=JsonObject(sale.payload+("deleted_at" to JsonPrimitive(now)))))))
        val before=store.investmentAssetSnapshot(owner);val pending=queues()
        val result=repo().archiveAsset(owner,asset,device,now)
        Assert.assertEquals(InvestmentAssetError.OPEN_POSITION,(result.exceptionOrNull() as? InvestmentAssetException)?.reason)
        Assert.assertEquals(before,store.investmentAssetSnapshot(owner));Assert.assertEquals(pending,queues())
    }

}
