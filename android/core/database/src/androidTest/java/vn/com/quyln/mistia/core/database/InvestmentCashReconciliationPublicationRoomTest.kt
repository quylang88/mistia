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
class InvestmentCashReconciliationPublicationRoomTest {
    private lateinit var db:MistiaDatabase
    private lateinit var store:RoomLocalStore
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val id="22222222-2222-2222-2222-222222222222"
    private val device="33333333-3333-3333-3333-333333333333"
    private val source="77777777-7777-7777-7777-777777777777"
    private val linked="88888888-8888-8888-8888-888888888888"
    private val ledgerId=investmentLedgerIdentity(id,"cash-reconciliation")
    private val postingId=investmentLedgerIdentity(id,"linked-cash-posting")
    private val holderId=investmentLedgerIdentity(id,"holder-cash-posting")
    private val now="2026-10-27T00:00:00Z"
    private var active=owner
    @Before fun setup() {
        db=Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(),MistiaDatabase::class.java).allowMainThreadQueries().build()
        store=RoomLocalStore(db,currentBillOwner={active})
    }
    @After fun close(){db.close()}
    private fun transaction(v:Long=1,withdraw:Boolean=false)=CloudRecord(CloudEntity.LEDGER_TRANSACTION.table,ledgerId,owner.value,buildJsonObject {
        put("id",ledgerId);put("user_id",owner.value);put("primary_kind_raw_value","transfer");put("transfer_subtype_raw_value","internalTransfer");put("entry_status_raw_value","posted")
        put("settlement_role_raw_value","investmentReconciliation");put("title","Cash event");put("note",JsonNull)
        put("amount_minor",80);put("source_wallet_id",if(withdraw)linked else source);put("destination_wallet_id",if(withdraw)source else linked)
        put("destination_amount_minor",80);put("reporting_amount_minor",80);put("reporting_expense_minor",0);put("reporting_income_minor",0)
        for(key in listOf("source_currency_code","destination_currency_code","reporting_currency_code"))put(key,"VND")
        for(key in listOf("category_id","debt_intent_raw_value","settlement_group_id","settlement_obligation_id","conversion_mode_raw_value","exchange_rate_decimal_string","exchange_rate_provider","exchange_rate_date","counterparty_name","normalized_counterparty_key","archived_at","deleted_at"))put(key,JsonNull)
        put("created_by_user_id",owner.value);put("last_modified_by_user_id",owner.value);put("is_archived",false)
        put("occurred_at",now);put("created_at",now);put("updated_at",now);put("sync_version",v);put("last_modified_by_device_id",device)
        put("future_null",JsonNull);put("future_large",Long.MAX_VALUE)
    },now,null,v)
    private fun posting(v:Long=1,withdraw:Boolean=false)=CloudRecord(CloudEntity.INVESTMENT_POSTING.table,postingId,owner.value,buildJsonObject {
        put("id",postingId);put("user_id",owner.value);put("event_id",id);put("ledger_transaction_id",ledgerId);put("trade_id",JsonNull);put("asset_id",JsonNull);put("wallet_id",linked)
        put("role_raw_value","cashReconciliation");put("cash_bucket_raw_value","booked");put("cash_origin_raw_value","manual")
        put("amount_minor",if(withdraw)-20 else 50);put("accounting_amount_minor",if(withdraw)-20 else 50);put("currency_code","VND");put("accounting_currency_code","VND")
        put("occurred_at",now);put("created_at",now);put("updated_at",now);put("deleted_at",JsonNull);put("sync_version",v);put("last_modified_by_device_id",device)
    },now,null,v)


    private fun holder(v:Long=1)=posting(v).let{it.copy(id=holderId,payload=JsonObject(it.payload+buildJsonObject{put("id",holderId);put("wallet_id",source);put("amount_minor",-50);put("accounting_amount_minor",-50)}))}
    private fun q(row:CloudRecord)=PendingMutation(CloudEntity.fromTable(row.entity)!!,row.id,owner.value,MutationKind.UPSERT,row.payload,row.updatedAt!!,row.syncVersion,device)
    private suspend fun seed():InvestmentCashEventPublicationSnapshot {val rows=listOf(transaction(0),holder(0),posting(0));store.commitMutations(rows.map{it to q(it)});return snapshot()}
    private suspend fun snapshot()=store.investmentCashEventPublicationSnapshot(owner,id)
    private fun candidate()=InvestmentCashReconciliationCloudSnapshot(owner,id,transaction(),listOf(holder(),posting()))
    @Test fun wholeGroupAcknowledgementImportsThreeRowsAndClearsExactlyTheirQueues()=runBlocking {
        val before=seed();assertTrue(store.acknowledgeInvestmentCashReconciliationResult(before,candidate()));val after=snapshot()
        assertTrue(after.pending.isEmpty());assertTrue(after.dirtyKeys.isEmpty());assertEquals(setOf(transaction(),holder(),posting()),after.rows.toSet())
    }
    @Test fun newerLedgerIntentAndQueueSurviveBothLateAckAndFailure()=runBlocking {
        val before=seed();val row=transaction(0).let{it.copy(payload=JsonObject(it.payload+("note" to JsonPrimitive("newer"))))};store.commitMutation(row,q(row));val current=snapshot()
        assertFalse(store.acknowledgeInvestmentCashReconciliationResult(before,candidate()));assertFalse(store.recordInvestmentCashReconciliationFailure(before.pending.first(),30000,"network_io",before));assertEquals(current,snapshot())
    }
    @Test fun unrelatedWalletMutationRevokesTheCapturedGeneration()=runBlocking {
        val before=seed();val w=WalletDraft(id=source,name="newer wallet",kind=WalletKind.CASH,currencyCode="VND").toMutation(owner,null,device,now);store.commitMutation(w.record,w.pending);val current=snapshot()
        assertFalse(store.acknowledgeInvestmentCashReconciliationResult(before,candidate()));assertFalse(store.recordInvestmentCashReconciliationFailure(before.pending.first(),30000,"network_io",before));assertEquals(current,snapshot())
    }
    @Test fun finalSessionRotationRollsBackAllThreeImportsAndQueueDeletions()=runBlocking {
        val before=seed();var checks=0;assertTrue(runCatching{store.acknowledgeInvestmentCashReconciliationResult(before,candidate()){++checks<3}}.exceptionOrNull() is CancellationException)
        assertEquals(3,checks);assertEquals(before,snapshot())
    }
    @Test fun ownerRotationCancelsBeforeTouchingTheOldPartition()=runBlocking {
        val before=seed();active=UserId(device);assertTrue(runCatching{store.acknowledgeInvestmentCashReconciliationResult(before,candidate())}.exceptionOrNull() is CancellationException)
        active=owner;assertEquals(before,snapshot())
    }
    @Test fun invalidSecondPostingNeverPartiallyImportsTheLedgerOrFirstPosting()=runBlocking {
        val before=seed();val c=candidate().copy(postings=listOf(holder()))
        assertTrue(runCatching{store.acknowledgeInvestmentCashReconciliationResult(before,c)}.isFailure);assertEquals(before,snapshot())
    }
    @Test fun retryBookkeepingTouchesOnlyItsExactDriverAndCannotRepeatAnOldGeneration()=runBlocking {
        val before=seed();val driver=before.pending.first();assertTrue(store.recordInvestmentCashReconciliationFailure(driver,30000,"network_io",before));val after=snapshot()
        assertEquals(before.rows,after.rows);assertEquals(before.pending.size,after.pending.size)
        assertEquals(1,after.pending.single{it.mutation==driver.mutation}.attemptCount);assertEquals(30000L,after.pending.single{it.mutation==driver.mutation}.nextAttemptAtEpochMillis)
        assertFalse(store.recordInvestmentCashReconciliationFailure(driver,40000,"network_io",before));assertEquals(after,snapshot())
    }
    @Test fun finalSessionRotationAlsoRollsBackFailureBookkeeping()=runBlocking {
        val before=seed();var checks=0;assertTrue(runCatching{store.recordInvestmentCashReconciliationFailure(before.pending.first(),30000,"network_io",before){++checks<3}}.exceptionOrNull() is CancellationException);assertEquals(before,snapshot())
    }
    @Test fun cleanLedgerAndSingleRemainingPostingRecoverWithoutGenericFinancialAck()=runBlocking {
        seed();for(row in listOf(transaction(),holder())) {val old=snapshot().pending.single{it.mutation.recordId==row.id};assertTrue(store.acknowledgeMutation(old,row))}
        val before=snapshot();assertEquals(1,before.pending.size);assertTrue(store.acknowledgeInvestmentCashReconciliationResult(before,candidate()));assertTrue(snapshot().pending.isEmpty())
    }
}
