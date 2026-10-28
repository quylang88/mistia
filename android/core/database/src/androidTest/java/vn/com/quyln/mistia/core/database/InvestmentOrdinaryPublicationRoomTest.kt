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
class InvestmentOrdinaryPublicationRoomTest {
    private lateinit var db:MistiaDatabase
    private lateinit var store:RoomLocalStore
    private lateinit var finance:OfflineFirstFinanceRepository
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val device="44444444-4444-4444-8444-444444444444"
    private val now="2026-10-28T00:00:00Z"
    private var active=owner
    private fun id(n:Int)=java.util.UUID(0,n.toLong()).toString()
    @Before fun setup(){db=Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(),MistiaDatabase::class.java).allowMainThreadQueries().build();store=RoomLocalStore(db,currentBillOwner={active});finance=OfflineFirstFinanceRepository(store)}
    @After fun close(){db.close()}
    private suspend fun snapshot()=store.investmentOrdinaryPublicationSnapshot(owner,id(20))
    private suspend fun seed(unreconciled:Boolean=false,amount:Long?=null):InvestmentOrdinaryPublicationSnapshot {
        finance.saveWallet(owner,WalletDraft(id=id(1),name="Cash",kind=WalletKind.CASH,currencyCode="JPY",openingBalanceMinor=if(unreconciled)0 else 100),device,now).getOrThrow()
        val parent=finance.saveCategory(owner,CategoryDraft(id=id(30),name="Parent",kind=TransactionCategoryKind.EXPENSE,hierarchyRole=CategoryHierarchyRole.PARENT),device,now).getOrThrow()
        finance.saveCategory(owner,CategoryDraft(id=id(31),name="Child",kind=TransactionCategoryKind.EXPENSE,hierarchyRole=CategoryHierarchyRole.CHILD,parentCategoryId=parent.id),device,now).getOrThrow()
        val root=WalletDraft(id=investmentSystemWalletId(owner),name="Investment wallet",kind=WalletKind.CASH,currencyCode="JPY").toMutation(owner,null,device,now).record.let{it.copy(payload=JsonObject(it.payload+buildJsonObject {
            put("kind_raw_value","investment");put("system_purpose_raw_value","investmentProfit");put("investment_linked_wallet_id",id(1));put("opening_balance_minor",0)
            put("icon_symbol_name","chart.line.uptrend.xyaxis");put("icon_color_hex","#9A67FF");put("sort_order",2147483547)
            put("institution_display_name",JsonNull);put("institution_preset_key",JsonNull)
        }))}
        val cash=CloudRecord(CloudEntity.INVESTMENT_POSTING.table,id(10),owner.value,buildJsonObject {
            put("id",id(10));put("user_id",owner.value);put("sync_version",0);put("deleted_at",JsonNull);put("created_at",now);put("updated_at",now);put("last_modified_by_device_id",device)
            put("event_id",id(11));put("ledger_transaction_id",id(11));put("wallet_id",id(1));put("role_raw_value","cashAccrual");put("cash_bucket_raw_value",if(unreconciled)"unreconciled" else "booked");put("cash_origin_raw_value","derived")
            put("amount_minor",60);put("accounting_amount_minor",60);put("currency_code","JPY");put("accounting_currency_code","JPY");put("occurred_at","2026-10-28T00:00:01Z")
        },now,null,0)
        // Imported historical booked cash is explicit; its FIFO origin is outside this lifecycle fixture.
        for(row in listOf(root,cash))store.commitMutation(row,PendingMutation(CloudEntity.fromTable(row.entity)!!,row.id,owner.value,MutationKind.UPSERT,row.payload,now,0,device))
        if(unreconciled) {
            // Swift dates attribute the reserve historically, but saving still
            // requires cash available now. A later real income supplies that cash.
            val incomeParent=finance.saveCategory(owner,CategoryDraft(id=id(40),name="Income",kind=TransactionCategoryKind.INCOME,hierarchyRole=CategoryHierarchyRole.PARENT),device,now).getOrThrow()
            finance.saveCategory(owner,CategoryDraft(id=id(41),name="Income child",kind=TransactionCategoryKind.INCOME,hierarchyRole=CategoryHierarchyRole.CHILD,parentCategoryId=incomeParent.id),device,now).getOrThrow()
            val income=TransactionDraft(primaryKind=TransactionPrimaryKind.INCOME,title="Later actual income",amountMinor=30,occurredAt="2026-10-28T00:00:03Z",sourceWalletId=id(1),categoryId=id(41))
            finance.saveTransactionWithInvestmentFunds(owner,TransactionInvestmentSaveRequest(income,TransactionCreationIdentity(id(12),now),null,"Adjustment","JPY"),device,now).getOrThrow()
        }
        for(entity in listOf(CloudEntity.LEDGER_WALLET,CloudEntity.TRANSACTION_CATEGORY,CloudEntity.INVESTMENT_POSTING,CloudEntity.LEDGER_TRANSACTION)) {
            for(q in store.pendingMutations(owner,entity,Long.MAX_VALUE)) {
                val row=store.record(owner,entity.table,q.mutation.recordId)!!
                val clean=row.copy(syncVersion=1,payload=JsonObject(row.payload+("sync_version" to JsonPrimitive(1))))
                assertTrue(store.acknowledgeMutation(q,clean))
            }
        }

        val draft=TransactionDraft(primaryKind=TransactionPrimaryKind.EXPENSE,title="Expense",amountMinor=amount ?: if(unreconciled)30 else 70,occurredAt="2026-10-28T00:00:02Z",sourceWalletId=id(1),categoryId=id(31))
        val request=TransactionInvestmentSaveRequest(draft,TransactionCreationIdentity(id(20),now),null,"Adjustment","JPY")
        val reviewed=finance.prepareTransactionWithInvestmentFunds(owner,request,device,now).exceptionOrNull()
        if(amount==null)assertTrue("Expected fund consent, got $reviewed",reviewed is InvestmentFundUsageConfirmationRequired)
        if(reviewed!=null && reviewed !is InvestmentFundUsageConfirmationRequired)throw reviewed
        finance.saveTransactionWithInvestmentFunds(owner,request.copy(consent=(reviewed as? InvestmentFundUsageConfirmationRequired)?.review?.consent),device,now).getOrThrow()
        return snapshot().also{it.requireCoherent()}
    }
    private fun q(row:CloudRecord)=PendingMutation(CloudEntity.fromTable(row.entity)!!,row.id,owner.value,if(row.deletedAt==null)MutationKind.UPSERT else MutationKind.DELETE,row.payload,row.updatedAt!!,row.syncVersion,device)
    private fun candidate(s:InvestmentOrdinaryPublicationSnapshot):InvestmentOrdinaryPublicationResult {
        val g=investmentOrdinaryPublicationGroup(s)
        fun saved(r:CloudRecord)=r.copy(syncVersion=r.syncVersion+1,payload=JsonObject(r.payload+("sync_version" to JsonPrimitive(r.syncVersion+1))))
        return InvestmentOrdinaryPublicationResult(s.owner,s.eventId,saved(g.primary),g.adjustment?.let(::saved),g.postings.map(::saved))
    }
    @Test fun fullBookedGroupImportsBothRowsAndPreservesUnrelatedWalletQueue()=runBlocking {
        seed();val w=WalletDraft(id=id(2),name="Unrelated",kind=WalletKind.CASH,currencyCode="JPY").toMutation(owner,null,device,now);store.commitMutation(w.record,w.pending)
        val before=snapshot();val reply=candidate(before);assertTrue(store.acknowledgeInvestmentOrdinaryResult(before,reply));val after=snapshot()
        assertEquals(1,after.pending.size);assertEquals(id(2),after.pending.single().mutation.recordId)
        for(row in reply.rows)assertEquals(row,after.rows.single{it.entity==row.entity && it.id==row.id})
    }
    @Test fun realUnreconciledRepositoryGroupRequiresAndImportsTheActualReserveLedger()=runBlocking {
        val before=seed(true);val group=investmentOrdinaryPublicationGroup(before)
        assertEquals(3,group.rows.size);assertEquals(30L,group.adjustment!!.payload.financeRawLong("amount_minor"))
        assertEquals(-30L,group.postings.single().payload.financeRawLong("amount_minor"))
        assertTrue(store.acknowledgeInvestmentOrdinaryResult(before,candidate(before)));assertTrue(snapshot().pending.isEmpty())
    }
    @Test fun newerParentIntentSurvivesBothLateResultAndFailureBookkeeping()=runBlocking {
        val before=seed();val t=investmentOrdinaryPublicationGroup(before).primary;val next=t.copy(payload=JsonObject(t.payload+("note" to JsonPrimitive("Newer intent"))))
        store.commitMutation(next,q(next));val current=snapshot()
        assertFalse(store.acknowledgeInvestmentOrdinaryResult(before,candidate(before)));assertFalse(store.recordInvestmentOrdinaryFailure(before.pending.first(),30000,"network_io",before));assertEquals(current,snapshot())
    }
    @Test fun newerCategoryRevokesTheCapturedWholeSourceGeneration()=runBlocking {
        val before=seed();val category=before.rows.single{it.entity==CloudEntity.TRANSACTION_CATEGORY.table && it.id==id(31)}
        val changed=category.copy(payload=JsonObject(category.payload+("name" to JsonPrimitive("Changed category"))))
        store.commitMutation(changed,q(changed));val current=snapshot()
        assertFalse(store.acknowledgeInvestmentOrdinaryResult(before,candidate(before)));assertFalse(store.recordInvestmentOrdinaryFailure(before.pending.first(),30000,"network_io",before));assertEquals(current,snapshot())
    }
    @Test fun partialPostingReplyNeverImportsTheParentOrClearsAnyQueue()=runBlocking {
        val before=seed();val partial=candidate(before).copy(postings=emptyList())
        assertTrue(runCatching{store.acknowledgeInvestmentOrdinaryResult(before,partial)}.isFailure);assertEquals(before,snapshot())
    }
    @Test fun finalSessionRotationRollsBackEveryImportAndQueueDeletion()=runBlocking {
        val before=seed();var checks=0
        assertTrue(runCatching{store.acknowledgeInvestmentOrdinaryResult(before,candidate(before)){++checks<3}}.exceptionOrNull() is CancellationException)
        assertEquals(3,checks);assertEquals(before,snapshot())
    }
    @Test fun ownerRotationCancelsBeforeTouchingTheOldPartition()=runBlocking {
        val before=seed();active=UserId(device)
        assertTrue(runCatching{store.acknowledgeInvestmentOrdinaryResult(before,candidate(before))}.exceptionOrNull() is CancellationException)
        active=owner;assertEquals(before,snapshot())
    }
    @Test fun retryTouchesOnlyExactDriverAndCannotRepeatTheOldGeneration()=runBlocking {
        val before=seed();val driver=before.pending.first()
        assertTrue(store.recordInvestmentOrdinaryFailure(driver,30000,"network_io",before));val after=snapshot()
        assertEquals(before.rows,after.rows);assertEquals(before.pending.size,after.pending.size)
        assertEquals(1,after.pending.single{it.mutation==driver.mutation}.attemptCount)
        assertEquals(30000L,after.pending.single{it.mutation==driver.mutation}.nextAttemptAtEpochMillis)
        assertFalse(store.recordInvestmentOrdinaryFailure(driver,40000,"network_io",before));assertEquals(after,snapshot())
    }
    @Test fun finalSessionRotationRollsBackFailureBookkeeping()=runBlocking {
        val before=seed();var checks=0
        assertTrue(runCatching{store.recordInvestmentOrdinaryFailure(before.pending.first(),30000,"network_io",before){++checks<3}}.exceptionOrNull() is CancellationException);assertEquals(before,snapshot())
    }
    private fun observed(r:InvestmentOrdinaryPublicationResult)=InvestmentOrdinaryCloudSnapshot(r.owner,r.eventId,r.transaction,r.adjustment,r.postings)
    private suspend fun staged(s:InvestmentOrdinaryPublicationSnapshot,date:String="2026-10-28T00:03:00Z")=requireNotNull(store.prepareInvestmentOrdinaryPublication(s,device,date))
    private fun primary(s:InvestmentOrdinaryPublicationSnapshot)=s.rows.single{it.entity==CloudEntity.LEDGER_TRANSACTION.table && it.id==id(20)}
    @Test fun beforeWritePreparationJournalsAllComparedRowsAndIsIdempotent()=runBlocking {
        val initial=seed();val before=staged(initial)
        assertEquals(1,localOrdinaryPublicationHistory(primary(before)).size);assertEquals(2,before.pending.size)
        assertEquals(before,staged(before,"2026-10-28T00:04:00Z"))
        assertTrue(primary(before).payload.containsKey(LOCAL_ORDINARY_PUBLICATION_JOURNAL_KEY))
    }
    @Test fun lostReplyRebasesNewerIntentWithoutFinancialAckThenASecondResultClearsTheGroup()=runBlocking {
        val first=staged(seed());val old=observed(candidate(first));val p=primary(first)
        val newer=p.copy(payload=JsonObject(p.payload+("note" to JsonPrimitive("New intent after lost response"))))
        store.commitMutation(newer,q(newer))
        val second=staged(snapshot(),"2026-10-28T00:05:00Z");assertEquals(2,localOrdinaryPublicationHistory(primary(second)).size)
        val rebased=requireNotNull(store.rebaseInvestmentOrdinaryPublication(second,old));assertEquals(2,rebased.pending.size)
        assertEquals("New intent after lost response",primary(rebased).payload.financeRawString("note"))
        assertTrue(rebased.pending.all{it.mutation.baseVersion==1L && it.remoteIdentityObserved})
        val final=staged(rebased,"2026-10-28T00:06:00Z")
        assertTrue(store.acknowledgeInvestmentOrdinaryResult(final,candidate(final)));assertTrue(snapshot().pending.isEmpty())
    }
    @Test fun newerWholeSourceRevokesBothPreparationAndRebase()=runBlocking {
        val before=staged(seed());val wallet=before.rows.single{it.entity==CloudEntity.LEDGER_WALLET.table && it.id==id(1)}
        val renamed=wallet.copy(payload=JsonObject(wallet.payload+("name" to JsonPrimitive("New wallet name"))))
        store.commitMutation(renamed,q(renamed));val current=snapshot()
        assertNull(store.prepareInvestmentOrdinaryPublication(before,device,"2026-10-28T00:05:00Z"))
        assertNull(store.rebaseInvestmentOrdinaryPublication(before,observed(candidate(before))));assertEquals(current,snapshot())
    }
    @Test fun finalSessionRotationRollsBackBeforeWritePreparation()=runBlocking {
        val before=seed();var checks=0
        assertTrue(runCatching{store.prepareInvestmentOrdinaryPublication(before,device,"2026-10-28T00:03:00Z"){++checks<3}}.exceptionOrNull() is CancellationException)
        assertEquals(3,checks);assertEquals(before,snapshot())
    }
    @Test fun finalSessionRotationRollsBackEveryRebasedRowAndQueue()=runBlocking {
        val first=staged(seed());val old=observed(candidate(first));val p=primary(first)
        val newer=p.copy(payload=JsonObject(p.payload+("note" to JsonPrimitive("Newer"))));store.commitMutation(newer,q(newer))
        val before=staged(snapshot(),"2026-10-28T00:05:00Z");var checks=0
        assertTrue(runCatching{store.rebaseInvestmentOrdinaryPublication(before,old){++checks<3}}.exceptionOrNull() is CancellationException)
        assertEquals(3,checks);assertEquals(before,snapshot())
    }
    @Test fun incompleteOldReplyNeverPartiallyAdvancesTheParentBase()=runBlocking {
        val first=staged(seed());val old=observed(candidate(first)).copy(postings=emptyList());val p=primary(first)
        val newer=p.copy(payload=JsonObject(p.payload+("note" to JsonPrimitive("Newer"))));store.commitMutation(newer,q(newer))
        val before=staged(snapshot(),"2026-10-28T00:05:00Z")
        assertTrue(runCatching{store.rebaseInvestmentOrdinaryPublication(before,old)}.isFailure);assertEquals(before,snapshot())
    }
    @Test fun moreThanOneHundredOtherQueuesAreCapturedAndSurviveTheFinancialResult()=runBlocking {
        seed();val writes=(100..226).map{n->WalletDraft(id=id(n),name="Other$n",kind=WalletKind.CASH,currencyCode="JPY").toMutation(owner,null,device,now).let{it.record to it.pending}}
        store.commitMutations(writes);val before=staged(snapshot());assertEquals(129,before.pending.size)
        assertTrue(store.acknowledgeInvestmentOrdinaryResult(before,candidate(before)))
        val after=snapshot();assertEquals(127,after.pending.size);assertEquals(writes.map{it.first.id}.toSet(),after.pending.map{it.mutation.recordId}.toSet())
    }
    @Test fun formerlyCleanParentBecomesQueuedBeforeItsAtomicFinancialWrite()=runBlocking {
        val first=seed();val old=first.pending.single{it.mutation.entity==CloudEntity.LEDGER_TRANSACTION}
        val remote=candidate(first).transaction;assertTrue(store.acknowledgeMutation(old,remote))
        val orphan=snapshot();assertEquals(1,orphan.pending.size)
        val prepared=staged(orphan);assertEquals(2,prepared.pending.size)
        val parent=prepared.pending.single{it.mutation.entity==CloudEntity.LEDGER_TRANSACTION}
        assertEquals(1L,parent.mutation.baseVersion);assertTrue(parent.remoteIdentityObserved)
    }

    @Test fun realObservedZeroRowsKeepExistenceWhenRebasedAndPreparedWithoutAnAck()=runBlocking {
        val before=seed();val g=investmentOrdinaryPublicationGroup(before)
        val cloud=InvestmentOrdinaryCloudSnapshot(owner,id(20),g.primary,null,g.postings)
        val observed=requireNotNull(store.rebaseInvestmentOrdinaryPublication(before,cloud))
        assertEquals(2,observed.pending.size);assertTrue(observed.pending.all{it.remoteIdentityObserved && it.mutation.baseVersion==0L})
        val prepared=staged(observed)
        assertTrue(investmentOrdinaryExpectedPresence(prepared).values.all{it})
        assertTrue(localOrdinaryPublicationHistory(primary(prepared)).single().rows.all{it.expectedPresent})
    }
    @Test fun aCleanObservedZeroParentIsNeverTurnedIntoAnAbsentBirthByPreparation()=runBlocking {
        val before=seed();val old=before.pending.single{it.mutation.entity==CloudEntity.LEDGER_TRANSACTION}
        val parent=primary(before);assertTrue(store.acknowledgeMutation(old,parent))
        val clean=snapshot();assertEquals(1,clean.pending.size);assertEquals(0L,primary(clean).syncVersion)
        val prepared=staged(clean);val flags=investmentOrdinaryExpectedPresence(prepared)
        assertEquals(true,flags[id(20)]);assertEquals(false,flags[investmentLedgerIdentity(id(20),"cash-consumption-booked")])
    }
    @Test fun finalSessionRotationAlsoRollsBackObservedZeroExistenceEvidence()=runBlocking {
        val before=seed();val g=investmentOrdinaryPublicationGroup(before);var checks=0
        val cloud=InvestmentOrdinaryCloudSnapshot(owner,id(20),g.primary,null,g.postings)
        assertTrue(runCatching{store.rebaseInvestmentOrdinaryPublication(before,cloud){++checks<3}}.exceptionOrNull() is CancellationException)
        assertEquals(3,checks);assertEquals(before,snapshot())
    }
    @Test fun ordinaryPullCannotReplaceTheJournalOrNewerFinancialIntentWhileAReplyIsLost()=runBlocking {
        val first=staged(seed());val old=candidate(first);val parent=primary(first)
        val newer=parent.copy(payload=JsonObject(parent.payload+("note" to JsonPrimitive("Latest local intent"))));store.commitMutation(newer,q(newer))
        val before=staged(snapshot(),"2026-10-28T00:05:00Z")
        store.replacePullSnapshot(owner,CloudEntity.LEDGER_TRANSACTION.table,listOf(old.transaction))
        val legacy=before.rows.filter{it.entity==CloudEntity.INVESTMENT_POSTING.table && it.id !in old.postings.map{p->p.id}}
        store.replacePullSnapshot(owner,CloudEntity.INVESTMENT_POSTING.table,legacy+old.postings)
        assertEquals(before,snapshot());assertEquals(2,localOrdinaryPublicationHistory(primary(snapshot())).size)
    }
    @Test fun foreignPostingPayloadCannotEnterTheOwnerPartitionThroughPull()=runBlocking {
        val before=seed();val row=investmentOrdinaryPublicationGroup(before).postings.single()
        val foreign=row.copy(id=id(998),payload=JsonObject(row.payload+buildJsonObject{put("id",id(998));put("user_id",device)}))
        assertTrue(runCatching{store.replacePullSnapshot(owner,CloudEntity.INVESTMENT_POSTING.table,listOf(foreign))}.isFailure)
        assertEquals(before,snapshot())
    }
    @Test fun remotePrivatePostingEvidenceCannotEnterTheOwnerPartitionThroughPull()=runBlocking {
        val before=seed();val row=investmentOrdinaryPublicationGroup(before).postings.single()
        val injected=row.copy(id=id(998),payload=JsonObject(row.payload+buildJsonObject{put("id",id(998));put("_mistia_android_fake",true)}))
        assertTrue(runCatching{store.replacePullSnapshot(owner,CloudEntity.INVESTMENT_POSTING.table,listOf(injected))}.isFailure)
        assertEquals(before,snapshot())
    }

    @Test fun genericPreparationAtomicallyPersistsActualWireTargetAndKeepsEveryFinancialField()=runBlocking {
        val before=seed(amount=20);val row=before.rows.single{it.entity==CloudEntity.LEDGER_TRANSACTION.table && it.id==id(20)};val q=before.pending.single()
        val proposal=JsonObject(row.payload+("sync_version" to JsonPrimitive(9007199254740995L)))
        val staged=store.prepareTransactionPublication(q,row,proposal)!!
        val after=snapshot();val current=after.rows.single{it.id==row.id && it.entity==row.entity}
        assertEquals(q.mutation.baseVersion,current.syncVersion);assertEquals(20L,current.payload.financeRawLong("amount_minor"))
        assertEquals(9007199254740994L,localOrdinaryPublicationHistory(current).single().rows.single().baseVersion)
        assertEquals(staged,after.pending.single());assertEquals(row.payload,ordinaryPublicationPayloadForCloud(current))
        assertTrue(store.acknowledgeMutation(staged,row.copy(payload=proposal,syncVersion=9007199254740995L)))
        assertTrue(snapshot().pending.isEmpty())
    }
    @Test fun genericPreparationRejectsStaleCapturedQueueBeforeRecordingAnyProposal()=runBlocking {
        val before=seed(amount=20);val row=before.rows.single{it.entity==CloudEntity.LEDGER_TRANSACTION.table && it.id==id(20)};val q=before.pending.single()
        val changed=row.copy(payload=JsonObject(row.payload+("note" to JsonPrimitive("Newer"))))
        store.commitMutation(changed,q.mutation.copy(payload=changed.payload));val current=snapshot()
        assertNull(store.prepareTransactionPublication(q,row,JsonObject(row.payload+("sync_version" to JsonPrimitive(1)))))
        assertEquals(current,snapshot())
    }
    @Test fun genericPreparationCannotAuthorizeAParentThatNowHasFinancialAllocation()=runBlocking {
        val before=seed();val row=before.rows.single{it.entity==CloudEntity.LEDGER_TRANSACTION.table && it.id==id(20)}
        val q=before.pending.single{it.mutation.recordId==id(20)}
        assertNull(store.prepareTransactionPublication(q,row,JsonObject(row.payload+("sync_version" to JsonPrimitive(1)))))
        assertEquals(before,snapshot())
    }
    @Test fun genericPreparationOwnerChangeCancelsWithoutJournalOrQueueChange()=runBlocking {
        val before=seed(amount=20);val row=before.rows.single{it.entity==CloudEntity.LEDGER_TRANSACTION.table && it.id==id(20)}
        active=UserId(device)
        assertTrue(runCatching{store.prepareTransactionPublication(before.pending.single(),row,JsonObject(row.payload+("sync_version" to JsonPrimitive(1))))}.exceptionOrNull() is CancellationException)
        active=owner;assertEquals(before,snapshot())
    }

    private fun differentCloud(s:InvestmentOrdinaryPublicationSnapshot,date:String="2026-10-28T00:03:00Z",version:Long=2):InvestmentOrdinaryCloudSnapshot {
        val g=investmentOrdinaryPublicationGroup(s)
        fun change(row:CloudRecord,fields:JsonObject)=row.copy(syncVersion=version,updatedAt=date,payload=JsonObject(row.payload+fields+buildJsonObject {
            put("sync_version",version);put("updated_at",date);put("last_modified_by_device_id",id(90))
        }))
        return InvestmentOrdinaryCloudSnapshot(owner,id(20),change(g.primary,buildJsonObject{put("amount_minor",80);put("reporting_amount_minor",80)}),null,
            g.postings.map{change(it,buildJsonObject{put("amount_minor",-40);put("accounting_amount_minor",-40)})})
    }
    @Test fun wholeRemoteConflictImportsBothMoneyRowsAndConsumesOnlyCapturedEventQueues()=runBlocking {
        val before=seed();val cloud=differentCloud(before)
        val unrelated=WalletDraft(id=id(2),name="Other",kind=WalletKind.CASH,currencyCode="JPY").toMutation(owner,null,device,now);store.commitMutation(unrelated.record,unrelated.pending)
        val current=snapshot();val result=store.resolveInvestmentOrdinaryConflict(current,cloud)
        assertTrue(result is InvestmentOrdinaryConflictPlan.Remote);val after=snapshot()
        assertEquals(1,after.pending.size);assertEquals(id(2),after.pending.single().mutation.recordId)
        assertEquals(80L,after.rows.single{it.entity==CloudEntity.LEDGER_TRANSACTION.table && it.id==id(20)}.payload.financeRawLong("amount_minor"))
        assertEquals(-40L,after.rows.single{it.id==cloud.postings.single().id}.payload.financeRawLong("amount_minor"))
    }
    @Test fun wholeLocalConflictKeepsCurrentMoneyAndAllQueuesAtObservedComparedBases()=runBlocking {
        val before=seed();val result=store.resolveInvestmentOrdinaryConflict(before,differentCloud(before,"2026-10-27T23:59:59Z"))
        assertTrue(result is InvestmentOrdinaryConflictPlan.Local);val after=snapshot();val g=investmentOrdinaryPublicationGroup(after)
        assertEquals(70L,g.primary.payload.financeRawLong("amount_minor"));assertEquals(-30L,g.postings.single().payload.financeRawLong("amount_minor"))
        assertEquals(2,after.pending.size);assertTrue(after.pending.all{it.mutation.baseVersion==2L && it.remoteIdentityObserved})
    }
    @Test fun unresolvedWholeConflictPersistsCompleteEvidenceAndNeverAcknowledgesMoney()=runBlocking {
        val before=seed();val cloud=differentCloud(before,now,0)
        val result=store.resolveInvestmentOrdinaryConflict(before,cloud) as InvestmentOrdinaryConflictPlan.Unresolved
        val after=snapshot();val parent=after.rows.single{it.entity==CloudEntity.LEDGER_TRANSACTION.table && it.id==id(20)}
        assertEquals(result,localInvestmentOrdinaryConflict(parent));assertEquals(70L,parent.payload.financeRawLong("amount_minor"))
        assertEquals(2,after.pending.size);assertTrue(after.pending.all{it.nextAttemptAtEpochMillis==Long.MAX_VALUE})
    }
    @Test fun newerSourceOrFinalSessionChangeCannotPartiallyResolveWholeConflict()=runBlocking {
        val before=seed();val cloud=differentCloud(before)
        for(observed in listOf(cloud,differentCloud(before,"2026-10-27T23:59:59Z"),differentCloud(before,now,0))) {
            var checks=0
            assertTrue(runCatching{store.resolveInvestmentOrdinaryConflict(before,observed){++checks<3}}.exceptionOrNull() is CancellationException)
            assertEquals(before,snapshot())
        }
        val row=before.rows.single{it.entity==CloudEntity.TRANSACTION_CATEGORY.table && it.id==id(31)}
        val next=row.copy(payload=JsonObject(row.payload+("name" to JsonPrimitive("New category"))));store.commitMutation(next,q(next));val current=snapshot()
        assertNull(store.resolveInvestmentOrdinaryConflict(before,cloud));assertEquals(current,snapshot())
    }
    @Test fun remoteNormalConflictRemovesOnlyTheUnpublishedLocalChildAndQueuesAtomically()=runBlocking {
        val before=seed();val g=investmentOrdinaryPublicationGroup(before)
        val p=g.primary.copy(syncVersion=2,updatedAt="2026-10-28T00:03:00Z",payload=JsonObject(g.primary.payload+buildJsonObject {
            put("amount_minor",20);put("reporting_amount_minor",20);put("sync_version",2);put("updated_at","2026-10-28T00:03:00Z");put("last_modified_by_device_id",id(90))
        }))
        assertTrue(store.resolveInvestmentOrdinaryConflict(before,InvestmentOrdinaryCloudSnapshot(owner,id(20),p,null,emptyList())) is InvestmentOrdinaryConflictPlan.Remote)
        assertNull(store.record(owner,CloudEntity.INVESTMENT_POSTING.table,g.postings.single().id));assertTrue(snapshot().pending.isEmpty())
        assertEquals(p,store.record(owner,CloudEntity.LEDGER_TRANSACTION.table,id(20)))
    }

    @Test fun wholeLocalConflictAddsAndComparesCanonicalServerOnlyRetiredHistory()=runBlocking {
        val before=seed();val observed=differentCloud(before,"2026-10-27T23:59:59Z")
        val original=observed.postings.single();val extraId=investmentLedgerIdentity(id(20),"cash-consumption-unreconciled")
        val extra=original.copy(id=extraId,deletedAt=now,updatedAt=now,payload=JsonObject(original.payload+buildJsonObject {
            put("id",extraId);put("cash_bucket_raw_value","unreconciled");put("amount_minor",-10);put("accounting_amount_minor",-10);put("deleted_at",now);put("updated_at",now)
        }))
        assertTrue(store.resolveInvestmentOrdinaryConflict(before,observed.copy(postings=observed.postings+extra)) is InvestmentOrdinaryConflictPlan.Local)
        val after=snapshot();assertEquals(3,after.pending.size);assertEquals(extra,store.record(owner,CloudEntity.INVESTMENT_POSTING.table,extraId))
        assertTrue(after.pending.single{it.mutation.recordId==extraId}.remoteIdentityObserved)
    }

}
