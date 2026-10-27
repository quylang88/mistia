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
class InvestmentCashEventPublicationRoomTest {
    private lateinit var db:MistiaDatabase
    private lateinit var store:RoomLocalStore
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val id="22222222-2222-2222-2222-222222222222"
    private val device="33333333-3333-3333-3333-333333333333"
    private val source="77777777-7777-7777-7777-777777777777"
    private val linked="88888888-8888-8888-8888-888888888888"
    private val postingId="625e1715-81fd-57c6-91e1-596e53e42db5"
    private val now="2026-10-27T00:00:00Z"
    private var active=owner
    @Before fun setup() {
        db=Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(),MistiaDatabase::class.java).allowMainThreadQueries().build()
        store=RoomLocalStore(db,currentBillOwner={active})
    }
    @After fun close(){db.close()}
    private fun transaction(v:Long=1,withdraw:Boolean=false)=CloudRecord(CloudEntity.LEDGER_TRANSACTION.table,id,owner.value,buildJsonObject {
        put("id",id);put("user_id",owner.value);put("primary_kind_raw_value","transfer");put("transfer_subtype_raw_value","internalTransfer");put("entry_status_raw_value","posted")
        put("settlement_role_raw_value",if(withdraw)"investmentCashWithdrawal" else "investmentCashDeposit");put("title","Cash event");put("note",JsonNull)
        put("amount_minor",if(withdraw)20 else 50);put("source_wallet_id",if(withdraw)linked else source);put("destination_wallet_id",if(withdraw)source else linked)
        put("destination_amount_minor",if(withdraw)20 else 50);put("reporting_amount_minor",if(withdraw)20 else 50);put("reporting_expense_minor",0);put("reporting_income_minor",0)
        for(key in listOf("source_currency_code","destination_currency_code","reporting_currency_code"))put(key,"VND")
        for(key in listOf("category_id","debt_intent_raw_value","settlement_group_id","settlement_obligation_id","conversion_mode_raw_value","exchange_rate_decimal_string","exchange_rate_provider","exchange_rate_date","counterparty_name","normalized_counterparty_key","archived_at","deleted_at"))put(key,JsonNull)
        put("created_by_user_id",owner.value);put("last_modified_by_user_id",owner.value);put("is_archived",false)
        put("occurred_at",now);put("created_at",now);put("updated_at",now);put("sync_version",v);put("last_modified_by_device_id",device)
        put("future_null",JsonNull);put("future_large",Long.MAX_VALUE)
    },now,null,v)
    private fun posting(v:Long=1,withdraw:Boolean=false)=CloudRecord(CloudEntity.INVESTMENT_POSTING.table,postingId,owner.value,buildJsonObject {
        put("id",postingId);put("user_id",owner.value);put("event_id",id);put("ledger_transaction_id",id);put("trade_id",JsonNull);put("asset_id",JsonNull);put("wallet_id",linked)
        put("role_raw_value","cashTransfer");put("cash_bucket_raw_value","booked");put("cash_origin_raw_value","manual")
        put("amount_minor",if(withdraw)-20 else 50);put("accounting_amount_minor",if(withdraw)-20 else 50);put("currency_code","VND");put("accounting_currency_code","VND")
        put("occurred_at",now);put("created_at",now);put("updated_at",now);put("deleted_at",JsonNull);put("sync_version",v);put("last_modified_by_device_id",device)
    },now,null,v)


    private fun q(row:CloudRecord)=PendingMutation(CloudEntity.fromTable(row.entity)!!,row.id,owner.value,if(row.deletedAt==null)MutationKind.UPSERT else MutationKind.DELETE,row.payload,row.updatedAt!!,row.syncVersion,device)
    private suspend fun seed(deleted:Boolean=false):InvestmentCashEventPublicationSnapshot {
        val rows=listOf(transaction(0),posting(0)).map{if(deleted)it.copy(deletedAt=now,payload=JsonObject(it.payload+("deleted_at" to JsonPrimitive(now)))) else it}
        store.commitMutations(rows.map{it to q(it)})
        return snapshot()
    }
    private suspend fun snapshot()=store.investmentCashEventPublicationSnapshot(owner,id)
    private fun candidate()=InvestmentCashEventCloudSnapshot(owner,id,transaction(),listOf(posting()))
    @Test fun oneTransactionImportsTheCanonicalPairAndClearsExactlyItsQueues()=runBlocking {
        val before=seed();assertEquals(2,before.pending.size);before.requireCoherent()
        assertTrue(store.acknowledgeInvestmentCashEventResult(before,candidate(),device,now))
        val after=snapshot();assertTrue(after.pending.isEmpty());assertTrue(after.dirtyKeys.isEmpty());assertEquals(setOf(transaction(),posting()),after.rows.toSet())
    }
    @Test fun completeAbsenceAcknowledgesOnlyTheUnobservedNeverPublishedTombstones()=runBlocking {
        val before=seed(true)
        assertTrue(store.acknowledgeInvestmentCashEventResult(before,InvestmentCashEventCloudSnapshot(owner,id,null,emptyList()),device,now))
        val after=snapshot();assertEquals(before.rows,after.rows);assertTrue(after.pending.isEmpty());assertTrue(after.dirtyKeys.isEmpty())
    }
    @Test fun anUnrelatedWalletChangeRevokesTheCapturedFinancialDecision()=runBlocking {
        val before=seed()
        val row=WalletDraft(id=source,name="Changed",kind=WalletKind.CASH,currencyCode="VND").toMutation(owner,null,device,now)
        store.commitMutation(row.record,row.pending);val current=snapshot()
        assertFalse(store.acknowledgeInvestmentCashEventResult(before,candidate(),device,now));assertEquals(current,snapshot())
        assertFalse(store.recordInvestmentCashEventMutationFailure(before.requestedQueue!!,30000,"network_io",before));assertEquals(current,snapshot())
    }
    @Test fun newerNoteAndItsQueueCannotBeOverwrittenByAnOldAckOrFailure()=runBlocking {
        val before=seed();val row=transaction(0).let{it.copy(payload=JsonObject(it.payload+("note" to JsonPrimitive("Newer"))))};store.commitMutation(row,q(row))
        val current=snapshot();assertFalse(store.acknowledgeInvestmentCashEventResult(before,candidate(),device,now))
        assertFalse(store.recordInvestmentCashEventMutationFailure(before.requestedQueue!!,30000,"network_io",before));assertEquals(current,snapshot())
    }
    @Test fun failureUpdatesOnlyTheCapturedLedgerRetryWithoutChangingFinancialRows()=runBlocking {
        val before=seed();val posting=before.pending.single{it.mutation.entity==CloudEntity.INVESTMENT_POSTING}
        assertTrue(store.recordInvestmentCashEventMutationFailure(before.requestedQueue!!,30000,"network_io",before))
        val after=snapshot();assertEquals(before.rows,after.rows);assertEquals(posting,after.pending.single{it.mutation.entity==CloudEntity.INVESTMENT_POSTING})
        assertEquals(1,after.requestedQueue!!.attemptCount);assertEquals(30000L,after.requestedQueue!!.nextAttemptAtEpochMillis);assertEquals("network_io",after.requestedQueue!!.lastError)
        assertFalse(store.recordInvestmentCashEventMutationFailure(before.requestedQueue!!,Long.MAX_VALUE,"old_error",before));assertEquals(after,snapshot())
    }
    @Test fun ownerReplacementRevokesBothWritesBeforeTouchingTheOldPartition()=runBlocking {
        val before=seed();active=UserId(device)
        assertTrue(runCatching{store.acknowledgeInvestmentCashEventResult(before,candidate(),device,now)}.exceptionOrNull() is CancellationException)
        assertTrue(runCatching{store.recordInvestmentCashEventMutationFailure(before.requestedQueue!!,30000,"network_io",before)}.exceptionOrNull() is CancellationException)
        active=owner;assertEquals(before,snapshot())
    }
    @Test fun finalSessionRotationRollsBackTheImportedPairAndBothQueueDeletions()=runBlocking {
        val before=seed();var checks=0
        assertTrue(runCatching{store.acknowledgeInvestmentCashEventResult(before,candidate(),device,now){++checks<3}}.exceptionOrNull() is CancellationException)
        assertEquals(3,checks);assertEquals(before,snapshot())
    }
    @Test fun finalSessionRotationRollsBackFailureBookkeeping()=runBlocking {
        val before=seed();var checks=0
        assertTrue(runCatching{store.recordInvestmentCashEventMutationFailure(before.requestedQueue!!,30000,"network_io",before){++checks<3}}.exceptionOrNull() is CancellationException)
        assertEquals(3,checks);assertEquals(before,snapshot())
    }
    @Test fun aLatePostingInsertFailureRestoresTheLedgerAndBothQueues()=runBlocking {
        val before=seed()
        db.openHelper.writableDatabase.execSQL("CREATE TRIGGER reject_cash_ack BEFORE INSERT ON cloud_records WHEN NEW.entity = 'investment_wallet_postings' BEGIN SELECT RAISE(ABORT, 'cash ACK insert failure'); END")
        assertTrue(runCatching{store.acknowledgeInvestmentCashEventResult(before,candidate(),device,now)}.exceptionOrNull().toString().contains("cash ACK insert failure"));assertEquals(before,snapshot())
    }
    @Test fun forgedMoneyCannotEnterTheCacheOrConsumeEitherQueue()=runBlocking {
        val before=seed();val bad=posting().let{it.copy(payload=JsonObject(it.payload+("accounting_amount_minor" to JsonPrimitive(49))))}
        assertTrue(runCatching{store.acknowledgeInvestmentCashEventResult(before,candidate().copy(postings=listOf(bad)),device,now)}.exceptionOrNull() is IllegalArgumentException)
        assertEquals(before,snapshot())
    }
    @Test fun ledgerPullRejectsPrivateCashAuthorityBeforeDeletingTheCleanOwnedSnapshot()=runBlocking {
        val dirty=seed();assertTrue(store.acknowledgeInvestmentCashEventResult(dirty,candidate(),device,now));val before=snapshot()
        val injected=transaction().let{it.copy(payload=JsonObject(it.payload+(LOCAL_CASH_EVENT_PUBLICATION_PARENTS_KEY to JsonNull)))}
        assertTrue(runCatching{store.replacePullSnapshot(owner,CloudEntity.LEDGER_TRANSACTION.table,listOf(injected))}.exceptionOrNull() is IllegalArgumentException)
        assertEquals(before,snapshot())
    }
    @Test fun ledgerPullHonorsCurrentOwnerBeforeReplacingCleanCashEventRows()=runBlocking {
        val dirty=seed();assertTrue(store.acknowledgeInvestmentCashEventResult(dirty,candidate(),device,now));val before=snapshot();active=UserId(device)
        assertTrue(runCatching{store.replacePullSnapshot(owner,CloudEntity.LEDGER_TRANSACTION.table,listOf(transaction()))}.exceptionOrNull() is CancellationException)
        active=owner;assertEquals(before,snapshot())
    }

    private suspend fun supersededReceipt():InvestmentCashEventPublicationReceipt {
        val before=seed();val old=before.requestedRecord!!
        val marker=buildJsonObject {
            put("version",1);put("owner_user_id",owner.value);put("event_id",id)
            put("parents",JsonArray(listOf(buildJsonObject{
                put("base_version",0);put("confirmed_version",JsonNull);put("device_id",device);put("deleted",false);put("fingerprint",cashEventIntentFingerprint(old))
            })))
        }
        val row=old.copy(payload=JsonObject(old.payload+buildJsonObject{put("note","Newer user note");put(LOCAL_CASH_EVENT_PUBLICATION_PARENTS_KEY,marker)}))
        store.commitMutation(row,q(row));val current=snapshot()
        assertTrue(store.recordInvestmentCashEventMutationFailure(current.requestedQueue!!,60000,"network_io",current))
        val sent=transaction(901)
        return InvestmentCashEventPublicationReceipt(before,sent,900,42,sent)
    }
    @Test fun definiteReceiptAddsOnlyCausalEvidenceAndPreservesTheNewUserQueueAndRows()=runBlocking {
        val receipt=supersededReceipt();val before=snapshot()
        assertEquals(1,store.recordInvestmentCashEventPublicationReceipt(receipt))
        val after=snapshot();val row=after.requestedRecord!!;val queue=before.requestedQueue!!
        assertEquals(cashEventPayloadForCloud(before.requestedRecord!!),cashEventPayloadForCloud(row));assertEquals(before.requestedRecord!!.syncVersion,row.syncVersion)
        assertEquals(queue.copy(mutation=queue.mutation.copy(payload=row.payload)),after.requestedQueue)
        assertEquals(before.rows.filter{it.id!=id},after.rows.filter{it.id!=id});assertEquals(before.pending.filter{it.mutation.recordId!=id},after.pending.filter{it.mutation.recordId!=id})
        assertTrue(isKnownPriorCashEventPublication(row,receipt.returned,device))
        assertEquals(0,store.recordInvestmentCashEventPublicationReceipt(receipt))
    }
    @Test fun finalReceiptSessionReplacementRollsBackBothPrivatePayloadWrites()=runBlocking {
        val receipt=supersededReceipt();val before=snapshot();var checks=0
        assertTrue(runCatching{store.recordInvestmentCashEventPublicationReceipt(receipt){++checks<3}}.exceptionOrNull() is CancellationException)
        assertEquals(3,checks);assertEquals(before,snapshot())
    }
    @Test fun receiptQueueInsertFailureRollsBackTheAlreadyWrittenRowEvidence()=runBlocking {
        val receipt=supersededReceipt();val before=snapshot()
        db.openHelper.writableDatabase.execSQL("CREATE TRIGGER reject_cash_receipt BEFORE INSERT ON sync_outbox WHEN NEW.entity = 'ledger_transactions' BEGIN SELECT RAISE(ABORT, 'cash receipt queue failure'); END")
        assertTrue(runCatching{store.recordInvestmentCashEventPublicationReceipt(receipt)}.exceptionOrNull().toString().contains("cash receipt queue failure"))
        assertEquals(before,snapshot())
    }
    @Test fun receiptFromAnOldOwnerCannotWriteAnyPrivateAncestry()=runBlocking {
        val receipt=supersededReceipt();val before=snapshot();active=UserId(device)
        assertTrue(runCatching{store.recordInvestmentCashEventPublicationReceipt(receipt)}.exceptionOrNull() is CancellationException)
        active=owner;assertEquals(before,snapshot())
    }

}
