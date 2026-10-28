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
class WalletInvestmentPrerequisiteRoomTest {
    private lateinit var db:MistiaDatabase
    private lateinit var store:RoomLocalStore
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val id="22222222-2222-2222-2222-222222222222"
    private val device="33333333-3333-3333-3333-333333333333"
    private val source="77777777-7777-7777-7777-777777777777"
    private val linked="88888888-8888-8888-8888-888888888888"
    private val ledgerId=investmentLedgerIdentity(id,"linked-wallet-move")
    private val postingId=investmentLedgerIdentity(id,"new-linked-cash-posting")
    private val holderId=investmentLedgerIdentity(id,"old-linked-cash-posting")
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
        put("amount_minor",50);put("source_wallet_id",if(withdraw)linked else source);put("destination_wallet_id",if(withdraw)source else linked)
        put("destination_amount_minor",50);put("reporting_amount_minor",50);put("reporting_expense_minor",0);put("reporting_income_minor",0)
        for(key in listOf("source_currency_code","destination_currency_code","reporting_currency_code"))put(key,"VND")
        for(key in listOf("category_id","debt_intent_raw_value","settlement_group_id","settlement_obligation_id","conversion_mode_raw_value","exchange_rate_decimal_string","exchange_rate_provider","exchange_rate_date","counterparty_name","normalized_counterparty_key","archived_at","deleted_at"))put(key,JsonNull)
        put("created_by_user_id",owner.value);put("last_modified_by_user_id",owner.value);put("is_archived",false)
        put("occurred_at",now);put("created_at",now);put("updated_at",now);put("sync_version",v);put("last_modified_by_device_id",device)
        put("future_null",JsonNull);put("future_large",Long.MAX_VALUE)
    },now,null,v)
    private fun posting(v:Long=1,withdraw:Boolean=false)=CloudRecord(CloudEntity.INVESTMENT_POSTING.table,postingId,owner.value,buildJsonObject {
        put("id",postingId);put("user_id",owner.value);put("event_id",id);put("ledger_transaction_id",ledgerId);put("trade_id",JsonNull);put("asset_id",JsonNull);put("wallet_id",linked)
        put("role_raw_value","cashTransfer");put("cash_bucket_raw_value","booked");put("cash_origin_raw_value","manual")
        put("amount_minor",if(withdraw)-20 else 50);put("accounting_amount_minor",if(withdraw)-20 else 50);put("currency_code","VND");put("accounting_currency_code","VND")
        put("occurred_at",now);put("created_at",now);put("updated_at",now);put("deleted_at",JsonNull);put("sync_version",v);put("last_modified_by_device_id",device)
    },now,null,v)


    private fun holder(v:Long=1)=posting(v).let{it.copy(id=holderId,payload=JsonObject(it.payload+buildJsonObject{put("id",holderId);put("wallet_id",source);put("amount_minor",-50);put("accounting_amount_minor",-50)}))}
    private fun q(row:CloudRecord)=PendingMutation(CloudEntity.fromTable(row.entity)!!,row.id,owner.value,MutationKind.UPSERT,row.payload,row.updatedAt!!,row.syncVersion,device)
    private suspend fun seed(base:Long=4):InvestmentTradePublicationSnapshot {
        fun wallet(id:String)=WalletDraft(id=id,name="Cash",kind=WalletKind.CASH,currencyCode="VND").toMutation(owner,null,device,now).record
        val rootId=investmentSystemWalletId(owner)
        val root=wallet(rootId).let{it.copy(payload=JsonObject(it.payload+buildJsonObject{put("kind_raw_value","investment");put("system_purpose_raw_value","investmentProfit");put("investment_linked_wallet_id",linked)}))}
        val wallets=listOf(root,wallet(source),wallet(linked)).map{row->val v=if(row.id==source)base else 1L
            row.copy(syncVersion=v,payload=JsonObject(row.payload+buildJsonObject{put("sync_version",v);if(row.id==source){put("is_archived",true);put("archived_at",now)}}))}

        // A pulled row is an observed remote identity even when a legacy base is0.
        // A genuinely unpublished fixture must originate from a local mutation.
        store.replacePullSnapshot(owner,CloudEntity.LEDGER_WALLET.table,wallets.filter{base>0 || it.id!=source})
        val archived=wallets.single{it.id==source}
        if(base==0L)store.commitMutation(archived,q(archived))
        val rows=listOf(transaction(0),holder(0),posting(0));store.commitMutations(rows.map{it to q(it)})
        if(base>0L)store.commitMutation(archived,q(archived))
        val queue=snapshot().pending.single{it.mutation.entity==CloudEntity.LEDGER_WALLET};assertTrue(store.recordMutationFailure(queue,9000,"network_io"))
        return snapshot()
    }
    private suspend fun snapshot()=store.investmentTradePublicationSnapshot(owner,id)
    private fun candidate()=InvestmentLinkedWalletMoveCloudSnapshot(owner,id,transaction(),listOf(holder(),posting()))
    private fun active(before:InvestmentTradePublicationSnapshot)=before.rows.single{it.id==source}.let{it.copy(payload=JsonObject(it.payload+buildJsonObject{put("is_archived",false);put("archived_at",JsonNull)}))}
    @Test fun observedActiveProofChangesOnlyPrivatePayloadAndRetainsTheEntireFinalQueue()=runBlocking {
        val before=seed();val stored=db.cloudRecordDao().record(owner.value,CloudEntity.LEDGER_WALLET.table,source)!!
        val queue=db.syncOutboxDao().record(owner.value,CloudEntity.LEDGER_WALLET.table,source)!!
        val prepared=store.prepareWalletInvestmentPrerequisite(before,source,active(before))!!
        assertFalse(prepared.needsWrite);assertEquals(prepared.preparedSource,snapshot())
        val after=db.cloudRecordDao().record(owner.value,CloudEntity.LEDGER_WALLET.table,source)!!;val aq=db.syncOutboxDao().record(owner.value,CloudEntity.LEDGER_WALLET.table,source)!!
        assertEquals(stored.copy(payloadJson=after.payloadJson),after);assertEquals(queue.copy(payloadJson=aq.payloadJson),aq)
        assertEquals(4,snapshot().pending.size);assertNotNull(walletInvestmentActivePrerequisite(prepared.preparedRecord))
    }
    @Test fun ownBirthReplyRebasesOnlyWalletBaseAndKeepsArchiveRetryStateAndFinancialQueues()=runBlocking {
        val before=seed(0);val p=store.prepareWalletInvestmentPrerequisite(before,source,null)!!
        assertTrue(store.rebaseWalletInvestmentPrerequisite(p.preparedSource,source,p.proposal))
        val after=snapshot();after.requireCoherent();val old=before.pending.single{it.mutation.entity==CloudEntity.LEDGER_WALLET};val q=after.pending.single{it.mutation.entity==CloudEntity.LEDGER_WALLET}
        assertEquals(1L,q.mutation.baseVersion);assertTrue(q.remoteIdentityObserved);assertEquals(old.attemptCount,q.attemptCount);assertEquals(old.nextAttemptAtEpochMillis,q.nextAttemptAtEpochMillis);assertEquals(old.lastError,q.lastError);assertEquals(old.mutation.modifiedAt,q.mutation.modifiedAt)
        assertEquals(true,after.rows.single{it.id==source}.payload.financeRawArchived());assertEquals(before.pending.filter{it.mutation.entity!=CloudEntity.LEDGER_WALLET},after.pending.filter{it.mutation.entity!=CloudEntity.LEDGER_WALLET})
    }
    @Test fun newerWholeGenerationRejectsAnOlderPreparationWithoutAnyJournalWrite()=runBlocking {
        val before=seed();val changed=transaction(0).let{it.copy(payload=JsonObject(it.payload+("note" to JsonPrimitive("Newer financial intent"))))};store.commitMutation(changed,q(changed));val current=snapshot()
        assertNull(store.prepareWalletInvestmentPrerequisite(before,source,active(before)));assertEquals(current,snapshot())
    }
    @Test fun newerWalletIntentRejectsALateBirthReplyAndPreservesItsExactQueues()=runBlocking {
        val p=store.prepareWalletInvestmentPrerequisite(seed(0),source,null)!!
        val row=p.preparedRecord.copy(payload=JsonObject(p.preparedRecord.payload+("name" to JsonPrimitive("Newer wallet"))));store.commitMutation(row,q(row));val current=snapshot()
        assertFalse(store.rebaseWalletInvestmentPrerequisite(p.preparedSource,source,p.proposal));assertEquals(current,snapshot())
    }
    @Test fun finalSessionRotationRollsBackPreparationPayloadAndOutboxTogether()=runBlocking {
        val before=seed();var checks=0
        assertTrue(runCatching{store.prepareWalletInvestmentPrerequisite(before,source,active(before)){++checks<3}}.exceptionOrNull() is CancellationException)
        assertEquals(3,checks);assertEquals(before,snapshot())
    }
    @Test fun finalSessionRotationRollsBackRebaseAndPreservesThePendingOwnJournal()=runBlocking {
        val p=store.prepareWalletInvestmentPrerequisite(seed(0),source,null)!!;var checks=0
        assertTrue(runCatching{store.rebaseWalletInvestmentPrerequisite(p.preparedSource,source,p.proposal){++checks<3}}.exceptionOrNull() is CancellationException)
        assertEquals(3,checks);assertEquals(p.preparedSource,snapshot())
    }
    @Test fun ownerRotationCancelsBeforeChangingTheOldPartition()=runBlocking {
        val before=seed();val observed=active(before);active=UserId(device)
        assertTrue(runCatching{store.prepareWalletInvestmentPrerequisite(before,source,observed)}.exceptionOrNull() is CancellationException)
        active=owner;assertEquals(before,snapshot())
    }
    @Test fun retryBookkeepingIsExactAndNeverTouchesFinancialRows()=runBlocking {
        val before=seed();val driver=before.pending.single{it.mutation.entity==CloudEntity.LEDGER_WALLET}
        assertTrue(store.recordWalletInvestmentPrerequisiteFailure(driver,30000,"network_io",before));val after=snapshot()
        assertEquals(before.rows,after.rows);assertEquals(2,after.pending.single{it.mutation.entity==CloudEntity.LEDGER_WALLET}.attemptCount)
        assertEquals(30000L,after.pending.single{it.mutation.entity==CloudEntity.LEDGER_WALLET}.nextAttemptAtEpochMillis)
        assertFalse(store.recordWalletInvestmentPrerequisiteFailure(driver,40000,"network_io",before));assertEquals(after,snapshot())
    }
    @Test fun finalFailureSessionRotationRollsBackRetryBookkeeping()=runBlocking {
        val before=seed();val driver=before.pending.single{it.mutation.entity==CloudEntity.LEDGER_WALLET};var checks=0
        assertTrue(runCatching{store.recordWalletInvestmentPrerequisiteFailure(driver,30000,"network_io",before){++checks<3}}.exceptionOrNull() is CancellationException)
        assertEquals(3,checks);assertEquals(before,snapshot())
    }
    @Test fun actualRepositoryRenameRetainsTheOwnJournalAndFreshRebaseKeepsTheNewIntent()=runBlocking {
        val p=store.prepareWalletInvestmentPrerequisite(seed(0),source,null)!!
        val financial=p.preparedSource.pending.filter{it.mutation.entity!=CloudEntity.LEDGER_WALLET}
        OfflineFirstFinanceRepository(store).saveWallet(owner,WalletDraft(id=source,name="Newest wallet name",kind=WalletKind.CASH,currencyCode="VND"),device,"2026-10-27T00:02:00Z").getOrThrow()
        val edited=snapshot();val editedRow=edited.rows.single{it.id==source}
        assertEquals(p.preparedRecord.payload[LOCAL_WALLET_INVESTMENT_PREREQUISITE_KEY],editedRow.payload[LOCAL_WALLET_INVESTMENT_PREREQUISITE_KEY])
        assertFalse(store.rebaseWalletInvestmentPrerequisite(p.preparedSource,source,p.proposal));assertEquals(edited,snapshot())
        assertTrue(store.rebaseWalletInvestmentPrerequisite(edited,source,p.proposal))
        val rebased=snapshot();val row=rebased.rows.single{it.id==source}
        assertEquals("Newest wallet name",row.payload.financeRawString("name"));assertEquals(true,row.payload.financeRawArchived());assertEquals(1L,row.syncVersion)
        assertNull(walletInvestmentActivePrerequisite(row));assertEquals(financial,rebased.pending.filter{it.mutation.entity!=CloudEntity.LEDGER_WALLET})
        val next=store.prepareWalletInvestmentPrerequisite(rebased,source,p.proposal)!!
        assertTrue(next.needsWrite);assertEquals(2L,next.proposal.syncVersion)
        assertTrue(store.rebaseWalletInvestmentPrerequisite(next.preparedSource,source,next.proposal))
        val complete=snapshot();assertEquals("Newest wallet name",walletInvestmentActivePrerequisite(complete.rows.single{it.id==source})!!.payload.financeRawString("name"))
        assertEquals(4,complete.pending.size);assertEquals(financial,complete.pending.filter{it.mutation.entity!=CloudEntity.LEDGER_WALLET})
    }

}
