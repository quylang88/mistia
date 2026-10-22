package vn.com.quyln.mistia.core.database

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.math.BigInteger
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.*
import org.junit.*
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.model.*

@RunWith(AndroidJUnit4::class)
class InvestmentFundTimelineRoomTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other=UserId("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")
    private val device="44444444-4444-4444-8444-444444444444"
    private fun id(n:Int)=java.util.UUID(0,n.toLong()).toString()
    private val now="2026-10-22T00:00:00Z"
    private lateinit var db:MistiaDatabase
    private lateinit var store:RoomLocalStore
    @Before fun open(){db=Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(),MistiaDatabase::class.java).allowMainThreadQueries().build();store=RoomLocalStore(db,currentBillOwner={owner})}
    @After fun close(){db.close()}
    private fun row(entity:CloudEntity,key:Int,fields:JsonObject)=CloudRecord(entity.table,id(key),owner.value,JsonObject(buildJsonObject {
        put("id",id(key));put("user_id",owner.value);put("created_at",now);put("updated_at",now);put("deleted_at",JsonNull);put("sync_version",9007199254740993L);put("future_field","keep")
    }+fields),now,null,9007199254740993L)
    private fun expense(amount:Long=70)=row(CloudEntity.LEDGER_TRANSACTION,20,buildJsonObject {
        put("primary_kind_raw_value","expense");put("entry_status_raw_value","posted");put("amount_minor",amount);put("source_wallet_id",id(1));put("source_currency_code","VND")
        put("occurred_at","2026-10-22T00:00:02Z");put("is_archived",false)
    })
    private fun rows()=listOf(WalletDraft(id=id(1),name="Wallet",kind=WalletKind.CASH,currencyCode="VND",openingBalanceMinor=100).toMutation(owner,null,device,now).record,
        row(CloudEntity.INVESTMENT_POSTING,10,buildJsonObject {
            put("event_id",id(11));put("wallet_id",id(1));put("ledger_transaction_id",id(11));put("role_raw_value","cashAccrual");put("cash_bucket_raw_value","booked");put("cash_origin_raw_value","derived")
            put("amount_minor",60L);put("currency_code","VND");put("accounting_amount_minor",60L);put("accounting_currency_code","VND");put("occurred_at","2026-10-22T00:00:01Z")
        }),expense())
    private suspend fun seed(rows:List<CloudRecord> = rows())=store.commitMutations(rows.map{row->row to PendingMutation(CloudEntity.fromTable(row.entity)!!,row.id,row.ownerUserId,MutationKind.UPSERT,row.payload,now,row.syncVersion,device)})
    private suspend fun queues()=InvestmentCashReadSnapshot.entities.associateWith{store.pendingMutations(owner,it,Long.MAX_VALUE)}
    @Test fun realOwnedSnapshotComparesBothTimelinesWithoutChangingRowsVersionsMetadataOrOutbox()=runBlocking {
        seed();val before=store.investmentCashSnapshot(owner);val pending=queues()
        val result=OfflineFirstInvestmentRepository(store).previewFundUsageTimeline(owner,"VND",id(20),expense(50))
        val change=result.primaryChange!!;Assert.assertEquals(BigInteger.valueOf(30),change.previousMinor);Assert.assertEquals(BigInteger.TEN,change.proposedMinor)
        Assert.assertEquals(BigInteger.valueOf(20),change.restoreMinor);Assert.assertEquals(BigInteger.valueOf(50),change.remainingInvestmentMinor)
        Assert.assertEquals(before,store.investmentCashSnapshot(owner));Assert.assertEquals(pending,queues())
        Assert.assertEquals(9007199254740993L,before.rows.single{it.id==id(20)}.syncVersion)
        Assert.assertEquals(JsonPrimitive("keep"),before.rows.single{it.id==id(20)}.payload["future_field"])
    }
    @Test fun foreignSameIdentityCannotReplaceOwnedProposalAndActiveOwnerIsEnforced()=runBlocking {
        seed();val foreign=expense(999).let{it.copy(ownerUserId=other.value,payload=JsonObject(it.payload+("user_id" to JsonPrimitive(other.value))))};seed(listOf(foreign))
        val before=store.investmentCashSnapshot(owner);val pending=queues();val repo=OfflineFirstInvestmentRepository(store)
        val error=runCatching{repo.previewFundUsageTimeline(owner,"VND",id(20),foreign)}.exceptionOrNull()
        Assert.assertTrue(error is InvestmentFundTimelineException)
        Assert.assertTrue(runCatching{repo.previewFundUsageTimeline(other,"VND",id(20),null)}.isFailure)
        Assert.assertEquals(before,store.investmentCashSnapshot(owner));Assert.assertEquals(pending,queues())
        Assert.assertEquals(foreign,store.record(other,foreign.entity,foreign.id))
    }
    @Test fun ownerChangeAtSecondRoomReadFenceCannotReturnAStaleFinancialPreviewOrWrite()=runBlocking {
        seed();val before=store.investmentCashSnapshot(owner);val pending=queues();var checks=0
        val switching=RoomLocalStore(db,currentBillOwner={checks++;if(checks==1)owner else other})
        Assert.assertTrue(runCatching{OfflineFirstInvestmentRepository(switching).previewFundUsageTimeline(owner,"VND",id(20),expense(50))}.isFailure)
        Assert.assertEquals(2,checks);Assert.assertEquals(before,store.investmentCashSnapshot(owner));Assert.assertEquals(pending,queues())
    }
}
