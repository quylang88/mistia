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
class InvestmentChannelRoomTest {
    private lateinit var db:MistiaDatabase
    private lateinit var store:RoomLocalStore
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other=UserId("99999999-9999-9999-9999-999999999999")
    private val id="22222222-2222-2222-2222-222222222222"
    private val device="44444444-4444-4444-4444-444444444444"
    private val now="2026-10-21T00:00:00Z"
    private var active=owner
    @Before fun setup(){db=Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(),MistiaDatabase::class.java).allowMainThreadQueries().build();store=RoomLocalStore(db,currentBillOwner={active})}
    @After fun close(){db.close()}
    private fun mutation(raw:CloudRecord)=raw to PendingMutation(CloudEntity.fromTable(raw.entity)!!,raw.id,raw.ownerUserId,MutationKind.UPSERT,raw.payload,raw.updatedAt!!,raw.syncVersion,device)
    private fun wallet()=WalletDraft(id=investmentSystemWalletId(owner),name="USD accounting",kind=WalletKind.CASH,currencyCode="USD").toMutation(owner,null,device,now).record
    @Test fun actualRoomCreateWritesBothOwnedRowsAndQueuesAsOneVisibleSnapshot()=runBlocking {
        val repo=OfflineFirstInvestmentRepository(store)
        val result=repo.saveChannel(owner,InvestmentChannelDraft(id,"Cards"),"VND",device,now).getOrThrow()
        val snapshot=store.investmentChannelSnapshot(owner)
        Assert.assertEquals(setOf(CloudEntity.INVESTMENT_CHANNEL.table,CloudEntity.LEDGER_WALLET.table),snapshot.rows.map{it.entity}.toSet())
        Assert.assertEquals(result.toCloudRecord(),store.record(owner,CloudEntity.INVESTMENT_CHANNEL.table,id))
        val wallet=snapshot.records(CloudEntity.LEDGER_WALLET).single();Assert.assertEquals(investmentSystemWalletId(owner),wallet.id);Assert.assertEquals(JsonPrimitive("VND"),wallet.payload["currency_code"])
        for(entity in listOf(CloudEntity.INVESTMENT_CHANNEL,CloudEntity.LEDGER_WALLET)) Assert.assertEquals(1,store.pendingMutations(owner,entity,Long.MAX_VALUE).size)
        Assert.assertTrue(InvestmentChannelSnapshot.entities.all{store.recordsIncludingDeleted(other,it.table).isEmpty()})
    }
    @Test fun triggerFailureOnChannelRollsBackPreviouslyWrittenWalletAndBothQueues()=runBlocking {
        db.openHelper.writableDatabase.execSQL("CREATE TRIGGER reject_channel BEFORE INSERT ON cloud_records WHEN NEW.entity = 'investment_channels' BEGIN SELECT RAISE(ABORT, 'channel failed'); END")
        val result=OfflineFirstInvestmentRepository(store).saveChannel(owner,InvestmentChannelDraft(id,"Cards"),"JPY",device,now)
        Assert.assertTrue(result.isFailure);Assert.assertTrue(store.investmentChannelSnapshot(owner).rows.isEmpty())
        Assert.assertTrue(InvestmentChannelSnapshot.entities.all{store.pendingMutations(owner,it,Long.MAX_VALUE).isEmpty()})
    }
    @Test fun walletCreatedAtCompareAndSwapIsReloadedAndItsAccountingCurrencyIsPreserved()=runBlocking {
        var attempts=0
        val racing=object:LocalStore by store {override suspend fun commitInvestmentChannels(expected:InvestmentChannelSnapshot,mutations:List<Pair<CloudRecord,PendingMutation>>):Boolean {
            attempts++;if(attempts==1) store.commitMutations(listOf(mutation(wallet())))
            return store.commitInvestmentChannels(expected,mutations)
        }}
        OfflineFirstInvestmentRepository(racing).saveChannel(owner,InvestmentChannelDraft(id,"Cards"),"VND",device,now).getOrThrow()
        Assert.assertEquals(2,attempts);Assert.assertEquals(JsonPrimitive("USD"),store.record(owner,CloudEntity.LEDGER_WALLET.table,investmentSystemWalletId(owner))!!.payload["currency_code"])
        Assert.assertEquals(2,store.investmentChannelSnapshot(owner).rows.size)
    }
    @Test fun accountReplacementBeforeTransactionRejectsEveryWrite()=runBlocking {
        val racing=object:LocalStore by store {override suspend fun commitInvestmentChannels(expected:InvestmentChannelSnapshot,mutations:List<Pair<CloudRecord,PendingMutation>>):Boolean {
            active=other;return store.commitInvestmentChannels(expected,mutations)
        }}
        val result=runCatching{OfflineFirstInvestmentRepository(racing).saveChannel(owner,InvestmentChannelDraft(id,"Cards"),"JPY",device,now)}
        Assert.assertTrue(result.exceptionOrNull() is CancellationException)
        active=owner;Assert.assertTrue(store.investmentChannelSnapshot(owner).rows.isEmpty());Assert.assertTrue(InvestmentChannelSnapshot.entities.all{store.recordsIncludingDeleted(other,it.table).isEmpty()})
    }
    private fun raw(entity:CloudEntity,generation:Int)=CloudRecord(entity.table,id,owner.value,buildJsonObject {
        put("id",id);put("user_id",owner.value);put("created_at",now);put("updated_at",now);put("generation",generation)
    },now,null,0)
    @Test fun fourEntityAtomicReadNeverMixesWalletChannelAssetOrTradeGenerations()=runBlocking {
        suspend fun batch(generation:Int){store.commitMutations(InvestmentChannelSnapshot.entities.map{mutation(raw(it,generation))})}
        batch(0);val observed=AtomicInteger(-1);val reads=Collections.synchronizedList(mutableListOf<List<Int>>())
        val job=launch(Dispatchers.Unconfined,start=CoroutineStart.UNDISPATCHED){store.observeInvestmentChannelSnapshot(owner).collect{snapshot ->
            val values=InvestmentChannelSnapshot.entities.map{snapshot.records(it).single().payload.getValue("generation").jsonPrimitive.int}
            reads.add(values);if(values.distinct().size==1) observed.set(values.first())
        }}
        try{withTimeout(5000){while(observed.get()<0)delay(5)};for(generation in 1..16){batch(generation);withTimeout(5000){while(observed.get()<generation)delay(5)}}}finally{job.cancelAndJoin()}
        Assert.assertTrue(reads.isNotEmpty());Assert.assertEquals(emptyList<List<Int>>(),synchronized(reads){reads.filter{it.distinct().size!=1}})
    }
    @Test fun stockBecomingPositiveAtAtomicCommitStopsArchiveWithoutReplacingChannelQueue()=runBlocking {
        val repo=OfflineFirstInvestmentRepository(store);val channel=repo.saveChannel(owner,InvestmentChannelDraft(id,"Cards"),"JPY",device,now).getOrThrow()
        val assetId="33333333-3333-3333-3333-333333333333";val tradeId="55555555-5555-5555-5555-555555555555"
        fun record(entity:CloudEntity,key:String,fields:JsonObject)=CloudRecord(entity.table,key,owner.value,JsonObject(buildJsonObject{put("id",key);put("user_id",owner.value);put("is_archived",false);put("created_at",now);put("updated_at",now);put("occurred_at",now)}+fields),now,null,0)
        val asset=record(CloudEntity.INVESTMENT_ASSET,assetId,buildJsonObject{put("channel_id",id)})
        val trade=record(CloudEntity.INVESTMENT_TRADE,tradeId,buildJsonObject{put("asset_id",assetId);put("position_quantity_after_decimal_string","0")})
        store.commitMutations(listOf(mutation(asset),mutation(trade)));val beforeQueue=store.pendingMutations(owner,CloudEntity.INVESTMENT_CHANNEL,Long.MAX_VALUE)
        var attempts=0
        val racing=object:LocalStore by store {override suspend fun commitInvestmentChannels(expected:InvestmentChannelSnapshot,mutations:List<Pair<CloudRecord,PendingMutation>>):Boolean {
            attempts++;if(attempts==1)store.commitMutations(listOf(mutation(trade.copy(payload=JsonObject(trade.payload+("position_quantity_after_decimal_string" to JsonPrimitive("1")))))))
            return store.commitInvestmentChannels(expected,mutations)
        }}
        val result=OfflineFirstInvestmentRepository(racing).archiveChannel(owner,channel,device,now)
        Assert.assertEquals(InvestmentChannelError.OPEN_POSITION,(result.exceptionOrNull() as? InvestmentChannelException)?.reason)
        Assert.assertEquals(channel.toCloudRecord(),store.record(owner,CloudEntity.INVESTMENT_CHANNEL.table,id));Assert.assertEquals(beforeQueue,store.pendingMutations(owner,CloudEntity.INVESTMENT_CHANNEL,Long.MAX_VALUE));Assert.assertEquals(1,attempts)
    }

}
