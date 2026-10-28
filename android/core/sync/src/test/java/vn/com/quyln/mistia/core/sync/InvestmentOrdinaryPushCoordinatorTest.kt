package vn.com.quyln.mistia.core.sync

import java.io.IOException
import java.time.Instant
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import vn.com.quyln.mistia.core.model.*

class InvestmentOrdinaryPushCoordinatorTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val device="44444444-4444-4444-8444-444444444444"
    private val now="2026-10-28T00:00:00Z"
    private var clock=Instant.parse("2026-10-28T00:10:00Z").toEpochMilli()
    private var session:AuthSession?=AuthSession(owner,null,"token","refresh",Long.MAX_VALUE)
    private fun id(n:Int)=java.util.UUID(0,n.toLong()).toString()
    private val event=id(20)
    private fun wallet(n:Int,opening:Long=100)=WalletDraft(id=id(n),name="Wallet$n",kind=WalletKind.CASH,currencyCode="JPY",openingBalanceMinor=opening).toMutation(owner,null,device,now).record
    private fun source(transfer:Boolean=false,card:Boolean=false):InvestmentOrdinaryPublicationSnapshot {
        val parent=CategoryDraft(id=id(30),name="Parent",kind=TransactionCategoryKind.EXPENSE,hierarchyRole=CategoryHierarchyRole.PARENT).toMutation(owner,null,null,device,now).record
        val child=CategoryDraft(id=id(31),name="Child",kind=TransactionCategoryKind.EXPENSE,hierarchyRole=CategoryHierarchyRole.CHILD,parentCategoryId=parent.id).toMutation(owner,null,parent,device,now).record
        val root=wallet(99,0).let{it.copy(id=investmentSystemWalletId(owner),payload=JsonObject(it.payload+buildJsonObject{put("id",investmentSystemWalletId(owner));put("kind_raw_value","investment");put("system_purpose_raw_value","investmentProfit");put("investment_linked_wallet_id",id(1))}))}
        val legacy=CloudRecord(CloudEntity.INVESTMENT_POSTING.table,id(10),owner.value,buildJsonObject {
            put("id",id(10));put("user_id",owner.value);put("sync_version",0);put("deleted_at",JsonNull);put("created_at",now);put("updated_at",now)
            put("event_id",id(11));put("ledger_transaction_id",id(11));put("wallet_id",id(1));put("role_raw_value","cashAccrual");put("cash_bucket_raw_value","booked");put("cash_origin_raw_value","derived")
            put("amount_minor",60);put("accounting_amount_minor",60);put("currency_code","JPY");put("accounting_currency_code","JPY");put("occurred_at","2026-10-28T00:00:01Z")
        },now,null,0)
        val cardMutation=if(card)CreditCardDraft(walletId=id(2),profileId=id(3),name="Card",creditLimitMinor=1000,currencyCode="JPY").toMutation(owner,null,null,null,device,now) else null
        val rows=listOf(root,wallet(1),cardMutation?.wallet?.record?.toCloudRecord() ?: wallet(2,0),parent.toCloudRecord(),child.toCloudRecord(),legacy)+listOfNotNull(cardMutation?.profile?.record?.toCloudRecord())
        val save=TransactionInvestmentSaveSnapshot(owner,TransactionInvestmentSaveSnapshot.entities.associateWith{e->rows.filter{it.entity==e.table}})
        val draft=if(transfer)TransactionDraft(primaryKind=TransactionPrimaryKind.TRANSFER,transferSubtype=TransactionTransferSubtype.INTERNAL_TRANSFER,title="Transfer",amountMinor=70,destinationAmountMinor=70,sourceWalletId=id(1),destinationWalletId=id(2),occurredAt="2026-10-28T00:00:02Z")
            else TransactionDraft(primaryKind=TransactionPrimaryKind.EXPENSE,title="Expense",amountMinor=70,sourceWalletId=id(1),categoryId=id(31),occurredAt="2026-10-28T00:00:02Z")
        val request=TransactionInvestmentSaveRequest(draft,TransactionCreationIdentity(event,now),null,"Adjustment","JPY")
        val error=runCatching{planTransactionInvestmentSave(save,request,device,now)}.exceptionOrNull()
        assertTrue(error is InvestmentFundUsageConfirmationRequired)
        val plan=planTransactionInvestmentSave(save,request.copy(consent=(error as InvestmentFundUsageConfirmationRequired).review.consent),device,now)
        val pending=plan.mutations.map{QueuedMutation(it.second,0,0,null)}
        return InvestmentOrdinaryPublicationSnapshot(owner,event,rows+plan.mutations.map{it.first},pending,pending.map{it.mutation.entity.table to it.mutation.recordId}.toSet())
    }

    private inner class Store(initial:InvestmentOrdinaryPublicationSnapshot):LocalStore {
        private fun unexpected():Nothing=throw AssertionError("Unexpected generic local operation")
        override fun observe(entity:String,ownerUserId:UserId)=unexpected()
        override fun observeEntityCounts(ownerUserId:UserId)=unexpected()
        override suspend fun record(ownerUserId:UserId,entity:String,recordId:String)=unexpected()
        override suspend fun commitMutation(record:CloudRecord,mutation:PendingMutation)=unexpected()
        override suspend fun pendingMutations(ownerUserId:UserId,entity:CloudEntity,dueAtEpochMillis:Long,limit:Int)=unexpected()
        override suspend fun acknowledgeMutation(mutation:QueuedMutation,remoteRecord:CloudRecord)=unexpected()
        override suspend fun recordMutationFailure(mutation:QueuedMutation,nextAttemptAtEpochMillis:Long,errorCode:String)=unexpected()
        override suspend fun replacePullSnapshot(ownerUserId:UserId,entity:String,records:List<CloudRecord>)=unexpected()
        override suspend fun pendingMutationRecordIds(ownerUserId:UserId,entity:String)=unexpected()
        override suspend fun clearAccount(ownerUserId:UserId)=unexpected()
        var state=initial;var reads=0;var prepares=0;var rebases=0;var acks=0;var failures=0
        var failPoint:String?=null
        var afterPrepare:(()->Unit)?=null
        private fun fail(point:String){if(failPoint==point)throw IOException("Local synthetic $point failure")}
        private fun apply(plan:InvestmentOrdinaryLocalPlan) {
            val keys=plan.changes.map{it.first.entity to it.first.id}.toSet()
            val pending=state.pending.filterNot{it.mutation.entity.table to it.mutation.recordId in keys}+plan.changes.map{it.second}
            state=state.copy(rows=state.rows.map{row->plan.changes.singleOrNull{it.first.entity==row.entity && it.first.id==row.id}?.first ?: row},pending=pending,dirtyKeys=pending.map{it.mutation.entity.table to it.mutation.recordId}.toSet())
            state.requireCoherent()
        }
        private fun same(expected:InvestmentOrdinaryPublicationSnapshot)=runCatching{expected.requireUnchanged(state.copy(eventId=expected.eventId))}.isSuccess
        override suspend fun investmentOrdinaryPublicationSnapshot(owner:UserId,eventId:String):InvestmentOrdinaryPublicationSnapshot {reads++;fail("read");return state.copy(eventId=eventId)}
        override suspend fun prepareInvestmentOrdinaryPublication(expected:InvestmentOrdinaryPublicationSnapshot,deviceId:String,now:String,isSessionCurrent:()->Boolean):InvestmentOrdinaryPublicationSnapshot? {
            fail("prepare");check(isSessionCurrent());if(!same(expected))return null
            apply(planInvestmentOrdinaryPreparation(state.copy(eventId=expected.eventId),deviceId,now));prepares++
            val result=state.copy(eventId=expected.eventId);afterPrepare?.invoke();return result
        }
        override suspend fun rebaseInvestmentOrdinaryPublication(expected:InvestmentOrdinaryPublicationSnapshot,observed:InvestmentOrdinaryCloudSnapshot,isSessionCurrent:()->Boolean):InvestmentOrdinaryPublicationSnapshot? {
            fail("rebase");check(isSessionCurrent());if(!same(expected))return null
            apply(planInvestmentOrdinaryRebase(state.copy(eventId=expected.eventId),observed));rebases++;return state.copy(eventId=expected.eventId)
        }
        override suspend fun resolveInvestmentOrdinaryConflict(expected:InvestmentOrdinaryPublicationSnapshot,observed:InvestmentOrdinaryCloudSnapshot,isSessionCurrent:()->Boolean):InvestmentOrdinaryConflictPlan? {
            fail("resolve");check(isSessionCurrent());if(!same(expected))return null
            val plan=planInvestmentOrdinaryConflict(state.copy(eventId=expected.eventId),observed)
            when(plan) {
                is InvestmentOrdinaryConflictPlan.Local->apply(plan.plan)
                is InvestmentOrdinaryConflictPlan.Unresolved->apply(planInvestmentOrdinaryUnresolved(state.copy(eventId=expected.eventId),plan))
                is InvestmentOrdinaryConflictPlan.Remote->{
                    val imported=plan.records.associateBy{it.entity to it.id}
                    val rows=state.rows.filterNot{it.entity to it.id in plan.removals}.map{imported[it.entity to it.id] ?: it}+
                        plan.records.filter{r->state.rows.none{it.entity==r.entity && it.id==r.id}}
                    val pending=state.pending.filterNot{it in plan.queues}
                    state=state.copy(rows=rows,pending=pending,dirtyKeys=pending.map{it.mutation.entity.table to it.mutation.recordId}.toSet())
                }
            }
            return plan
        }
        override suspend fun acknowledgeInvestmentOrdinaryResult(expected:InvestmentOrdinaryPublicationSnapshot,candidate:InvestmentOrdinaryPublicationResult,isSessionCurrent:()->Boolean):Boolean {
            fail("ack");check(isSessionCurrent());if(!same(expected))return false
            val plan=planInvestmentOrdinaryAcknowledgement(state.copy(eventId=expected.eventId),candidate);val remote=plan.records.associateBy{it.entity to it.id}
            val pending=state.pending.filterNot{q->plan.acknowledgements.any{it.first==q}}
            state=state.copy(rows=state.rows.map{remote[it.entity to it.id] ?: it},pending=pending,dirtyKeys=pending.map{it.mutation.entity.table to it.mutation.recordId}.toSet());acks++;return true
        }
        override suspend fun recordInvestmentOrdinaryFailure(mutation:QueuedMutation,nextAttemptAtEpochMillis:Long,errorCode:String,expected:InvestmentOrdinaryPublicationSnapshot,isSessionCurrent:()->Boolean):Boolean {
            check(isSessionCurrent());if(!same(expected))return false
            state=state.copy(pending=state.pending.map{if(it==mutation)it.copy(attemptCount=it.attemptCount+1,nextAttemptAtEpochMillis=nextAttemptAtEpochMillis,lastError=errorCode)else it});failures++;return true
        }
        fun changeNote(value:String) {
            val row=state.rows.single{it.entity==CloudEntity.LEDGER_TRANSACTION.table && it.id==event}
            val p=JsonObject(row.payload+("note" to JsonPrimitive(value)))
            state=state.copy(rows=state.rows.map{if(it==row)it.copy(payload=p)else it},pending=state.pending.map{if(it.mutation.recordId==event)it.copy(mutation=it.mutation.copy(payload=p))else it})
        }
        fun dirty(row:CloudRecord) {
            val q=QueuedMutation(PendingMutation(CloudEntity.fromTable(row.entity)!!,row.id,owner.value,MutationKind.UPSERT,row.payload,row.updatedAt!!,row.syncVersion,device),0,0,null)
            state=state.copy(rows=state.rows.filterNot{it.entity==row.entity && it.id==row.id}+row,pending=state.pending.filterNot{it.mutation.entity.table==row.entity && it.mutation.recordId==row.id}+q,dirtyKeys=state.dirtyKeys+(row.entity to row.id))
        }
    }
    private inner class Remote:InvestmentOrdinaryRemote {
        var reads=0;var sends=0;var lostReply=false;var afterPublish:(()->Unit)?=null
        val observed=mutableMapOf<String,InvestmentOrdinaryCloudSnapshot>()
        override suspend fun fetchEvent(owner:UserId,eventId:String,accessToken:String):InvestmentOrdinaryCloudSnapshot {reads++;assertEquals("token",accessToken);return observed[eventId] ?: InvestmentOrdinaryCloudSnapshot(owner,eventId,null,null,emptyList())}
        override suspend fun publish(source:InvestmentOrdinaryPublicationSnapshot,accessToken:String):InvestmentOrdinaryPublicationResult {
            sends++;val group=investmentOrdinaryPublicationGroup(source)
            fun saved(r:CloudRecord)=r.copy(syncVersion=r.syncVersion+1,payload=JsonObject(r.payload+("sync_version" to JsonPrimitive(r.syncVersion+1))))
            val result=InvestmentOrdinaryPublicationResult(owner,source.eventId,saved(group.primary),group.adjustment?.let(::saved),group.postings.map(::saved))
            observed[source.eventId]=InvestmentOrdinaryCloudSnapshot(owner,source.eventId,result.transaction,result.adjustment,result.postings)
            afterPublish?.invoke();if(lostReply){lostReply=false;throw IOException("Synthetic lost reply")};return result
        }
    }
    private fun coordinator(store:Store,remote:Remote,enabled:Boolean=true)=InvestmentOrdinaryPushCoordinator(store,remote,enabled,{session},{clock})
    @Test fun publishesOneCompleteConfirmedGroupAndClearsItsFinancialQueues()=runTest {
        val store=Store(source());val remote=Remote();val result=coordinator(store,remote).pushPending(owner,"token")
        assertEquals(1,result.pushed);assertEquals(1,remote.sends);assertEquals(1,store.prepares);assertEquals(1,store.acks);assertTrue(store.state.pending.isEmpty())
    }
    @Test fun disabledGateAndFutureRetryNeverReadOrSend()=runTest {
        val store=Store(source());val remote=Remote();assertEquals(DomainPushSummary(),coordinator(store,remote,false).pushPending(owner,"token"));assertEquals(0,store.reads)
        store.state=store.state.copy(pending=store.state.pending.map{it.copy(nextAttemptAtEpochMillis=clock+1)})
        assertEquals(DomainPushSummary(),coordinator(store,remote).pushPending(owner,"token"));assertEquals(0,remote.reads);assertEquals(0,remote.sends)
    }
    @Test fun lostReplyIsRecoveredFromACompleteReadWithoutASecondFinancialWrite()=runTest {
        val store=Store(source());val remote=Remote();remote.lostReply=true
        assertEquals(1,coordinator(store,remote).pushPending(owner,"token").retryableFailures);assertEquals(2,store.state.pending.size)
        clock+=30001
        assertEquals(1,coordinator(store,remote).pushPending(owner,"token").acknowledged);assertEquals(1,remote.sends);assertTrue(store.state.pending.isEmpty())
    }
    @Test fun aNewerIntentDuringPublishSurvivesAndThenUsesTheProvenOldBase()=runTest {
        val store=Store(source());val remote=Remote();remote.afterPublish={store.changeNote("Newer intent");remote.afterPublish=null}
        assertEquals(1,coordinator(store,remote).pushPending(owner,"token").staleResponses);assertEquals(2,store.state.pending.size)
        clock+=30001
        assertEquals(1,coordinator(store,remote).pushPending(owner,"token").pushed)
        assertEquals("Newer intent",store.state.rows.single{it.id==event}.payload.financeRawString("note"));assertTrue(store.state.pending.isEmpty());assertEquals(2,remote.sends)
    }
    @Test fun dirtyReferencedCategoryHoldsTheGroupButUnrelatedQueuesDoNot()=runTest {
        val store=Store(source());val remote=Remote();store.dirty(store.state.rows.single{it.id==id(31)})
        coordinator(store,remote).pushPending(owner,"token");assertEquals(0,remote.reads);assertEquals(0,remote.sends)
        val clean=Store(source());repeat(127){clean.dirty(wallet(1000+it,0))}
        assertEquals(1,coordinator(clean,remote).pushPending(owner,"token").pushed);assertEquals(127,clean.state.pending.size)
    }
    @Test fun localPersistenceFailuresArePropagatedWithoutBeingRecordedAsNetworkRetries()=runTest {
        for(point in listOf("read","prepare","ack")) {
            val store=Store(source());store.failPoint=point;val remote=Remote()
            assertTrue(point,runCatching{coordinator(store,remote).pushPending(owner,"token")}.exceptionOrNull() is IOException)
            assertEquals(0,store.failures)
        }
    }
    @Test fun sessionRotationDuringACommittedWriteCancelsBeforeAnyAcknowledgement()=runTest {
        val store=Store(source());val remote=Remote();remote.afterPublish={session=session!!.copy(accessToken="rotated")}
        assertTrue(runCatching{coordinator(store,remote).pushPending(owner,"token")}.exceptionOrNull() is CancellationException)
        assertEquals(0,store.acks);assertEquals(0,store.failures);assertEquals(2,store.state.pending.size)
    }
    @Test fun twoConfirmedEventsShareTheSourceWithoutBlockingEachOtherForever()=runTest {
        val first=source();val snapshot=TransactionInvestmentSaveSnapshot(owner,TransactionInvestmentSaveSnapshot.entities.associateWith{e->first.rows.filter{it.entity==e.table}})
        val draft=TransactionDraft(primaryKind=TransactionPrimaryKind.EXPENSE,title="Second expense",amountMinor=20,occurredAt="2026-10-28T00:00:03Z",sourceWalletId=id(1),categoryId=id(31))
        val request=TransactionInvestmentSaveRequest(draft,TransactionCreationIdentity(id(21),now),null,"Adjustment","JPY")
        val review=(runCatching{planTransactionInvestmentSave(snapshot,request,device,now)}.exceptionOrNull() as InvestmentFundUsageConfirmationRequired).review
        val plan=planTransactionInvestmentSave(snapshot,request.copy(consent=review.consent),device,now)
        val pending=first.pending+plan.mutations.map{QueuedMutation(it.second,0,0,null)}
        val all=first.copy(rows=first.rows+plan.mutations.map{it.first},pending=pending,dirtyKeys=pending.map{it.mutation.entity.table to it.mutation.recordId}.toSet())
        val store=Store(all);val remote=Remote()
        assertEquals(2,coordinator(store,remote).pushPending(owner,"token").pushed);assertEquals(2,remote.sends);assertTrue(store.state.pending.isEmpty())
    }
    @Test fun structurallyValidButMathematicallyWrongAllocationNeverReachesRemote()=runTest {
        val original=source();val post=investmentOrdinaryPublicationGroup(original).postings.single()
        val payload=JsonObject(post.payload+buildJsonObject{put("amount_minor",-29);put("accounting_amount_minor",-29)})
        val s=original.copy(rows=original.rows.map{if(it==post)it.copy(payload=payload)else it},pending=original.pending.map{if(it.mutation.recordId==post.id)it.copy(mutation=it.mutation.copy(payload=payload))else it})
        investmentOrdinaryPublicationGroup(s)
        val store=Store(s);val remote=Remote();coordinator(store,remote).pushPending(owner,"token")
        assertEquals(0,remote.reads);assertEquals(0,remote.sends);assertEquals(s,store.state)
    }

    @Test fun paymentToCardRequiresAnExistingCleanProfileBeforeFinancialWrite()=runTest {
        val original=source(transfer=true,card=true)
        val profile=original.rows.single{it.entity==CloudEntity.CREDIT_CARD_PROFILE.table}
        val missing=Store(original.copy(rows=original.rows-profile));val remote=Remote()
        coordinator(missing,remote).pushPending(owner,"token");assertEquals(0,remote.reads)
        val dirty=Store(original);dirty.dirty(profile)
        coordinator(dirty,remote).pushPending(owner,"token");assertEquals(0,remote.reads)
        val clean=Store(original)
        assertEquals(1,coordinator(clean,remote).pushPending(owner,"token").pushed)
        assertEquals(1,remote.sends);assertTrue(clean.state.pending.isEmpty())
    }

    private fun differentCloud(s:InvestmentOrdinaryPublicationSnapshot,date:String,version:Long):InvestmentOrdinaryCloudSnapshot {
        val g=investmentOrdinaryPublicationGroup(s)
        fun change(row:CloudRecord,fields:JsonObject)=row.copy(syncVersion=version,updatedAt=date,payload=JsonObject(row.payload+fields+buildJsonObject {
            put("sync_version",version);put("updated_at",date);put("last_modified_by_device_id",id(90))
        }))
        return InvestmentOrdinaryCloudSnapshot(owner,event,change(g.primary,buildJsonObject{put("amount_minor",80);put("reporting_amount_minor",80)}),null,
            g.postings.map{change(it,buildJsonObject{put("amount_minor",-40);put("accounting_amount_minor",-40)})})
    }
    @Test fun completeRemoteWinnerImportsMoneyTogetherWithoutSendingOrGenericAck()=runTest {
        val store=Store(source());val remote=Remote();remote.observed[event]=differentCloud(store.state,"2026-10-28T00:20:00Z",2)
        assertEquals(1,coordinator(store,remote).pushPending(owner,"token").reconciled)
        assertEquals(0,remote.sends);assertTrue(store.state.pending.isEmpty())
        assertEquals(80L,store.state.rows.single{it.id==event}.payload.financeRawLong("amount_minor"))
    }
    @Test fun completeLocalWinnerUsesComparedRemoteBasesBeforePublishingCurrentMoney()=runTest {
        val store=Store(source());val remote=Remote();remote.observed[event]=differentCloud(store.state,"2026-10-27T23:59:59Z",2)
        assertEquals(1,coordinator(store,remote).pushPending(owner,"token").pushed)
        assertTrue(store.state.pending.isEmpty());assertEquals(1,remote.sends)
        val saved=remote.observed.getValue(event)
        assertEquals(3L,saved.transaction!!.syncVersion);assertEquals(70L,saved.transaction!!.payload.financeRawLong("amount_minor"))
        assertEquals(-30L,saved.postings.single().payload.financeRawLong("amount_minor"))
    }
    @Test fun sameClockUnobservedZeroConflictKeepsCompleteEvidenceAndBothQueues()=runTest {
        val store=Store(source());val remote=Remote();remote.observed[event]=differentCloud(store.state,now,0)
        assertEquals(1,coordinator(store,remote).pushPending(owner,"token").conflicts)
        assertEquals(0,remote.sends);assertEquals(2,store.state.pending.size)
        val parent=store.state.rows.single{it.id==event};assertNotNull(localInvestmentOrdinaryConflict(parent))
        assertEquals(70L,parent.payload.financeRawLong("amount_minor"));assertTrue(store.state.pending.all{it.nextAttemptAtEpochMillis==Long.MAX_VALUE})
    }

    @Test fun unresolvedEvidenceIsValidatedAndRemovedByTheGenericWireBoundary() {
        val s=source();val plan=planInvestmentOrdinaryConflict(s,differentCloud(s,now,0)) as InvestmentOrdinaryConflictPlan.Unresolved
        val marked=planInvestmentOrdinaryUnresolved(s,plan).changes.single{it.first.id==event}.first
        val wire=transactionPublicationWire(marked.payload)
        assertTrue(wire.keys.none{it.startsWith("_mistia_android_")});assertEquals(70L,wire.financeRawLong("amount_minor"))
    }

    private fun paidCardOccurrence(linked:String=event)=DueOccurrenceRecord(id(50),owner.value,"creditCard",id(2),"2026-10",now,70,"paid",now,linked,now,now,null,1,device).toCloudRecord()
    private fun editPayment(store:Store,amount:Long) {
        val snapshot=TransactionInvestmentSaveSnapshot(owner,TransactionInvestmentSaveSnapshot.entities.associateWith{e->store.state.rows.filter{it.entity==e.table}})
        var request=TransactionInvestmentSaveRequest(TransactionDraft(id=event,primaryKind=TransactionPrimaryKind.TRANSFER,transferSubtype=TransactionTransferSubtype.INTERNAL_TRANSFER,
            title="Transfer",amountMinor=amount,destinationAmountMinor=amount,sourceWalletId=id(1),destinationWalletId=id(2),occurredAt="2026-10-28T00:00:02Z"),null,null,"Adjustment","JPY")
        val error=runCatching{planTransactionInvestmentSave(snapshot,request,device,now)}.exceptionOrNull()
        if(error is InvestmentFundUsageConfirmationRequired)request=request.copy(consent=error.review.consent) else if(error!=null)throw error
        val plan=planTransactionInvestmentSave(snapshot,request,device,now)
        for((row,_) in plan.mutations)store.dirty(row)
    }
    @Test fun lateCleanPaidOccurrenceHoldsChangedPublishedPaymentWithoutSendingNewMoney()=runTest {
        val store=Store(source(transfer=true,card=true));val remote=Remote()
        assertEquals(1,coordinator(store,remote).pushPending(owner,"token").pushed)
        editPayment(store,80);store.state=store.state.copy(rows=store.state.rows+paidCardOccurrence())
        val before=store.state
        coordinator(store,remote).pushPending(owner,"token")
        assertEquals("A now-paid source cannot publish a different amount",1,remote.sends)
        assertEquals(2,store.state.pending.size);assertEquals(80L,store.state.rows.single{it.id==event}.payload.financeRawLong("amount_minor"))
        assertEquals(70L,remote.observed.getValue(event).transaction!!.payload.financeRawLong("amount_minor"))
        assertEquals(before.dirtyKeys,store.state.dirtyKeys)
    }
    @Test fun ownPendingPaidOccurrenceDoesNotWaitOnItsFinancialParentForever()=runTest {
        val store=Store(source(transfer=true,card=true));val remote=Remote()
        coordinator(store,remote).pushPending(owner,"token");editPayment(store,80);store.dirty(paidCardOccurrence())
        assertEquals(1,coordinator(store,remote).pushPending(owner,"token").pushed)
        assertEquals(2,remote.sends);assertEquals(1,store.state.pending.size)
        assertEquals(CloudEntity.DUE_OCCURRENCE_RECORD,store.state.pending.single().mutation.entity)
        assertEquals(80L,remote.observed.getValue(event).transaction!!.payload.financeRawLong("amount_minor"))
    }
    @Test fun cleanPaidOccurrenceStillAllowsSameFinancialLegacyParentAllocationCompletion()=runTest {
        val original=source(transfer=true,card=true);val g=investmentOrdinaryPublicationGroup(original)
        val parent=g.primary.copy(syncVersion=1,payload=JsonObject(g.primary.payload+("sync_version" to JsonPrimitive(1))))
        val pending=original.pending.filter{it.mutation.entity==CloudEntity.INVESTMENT_POSTING}
        val s=original.copy(rows=original.rows.map{if(it.entity==parent.entity && it.id==event)parent else it}+paidCardOccurrence(),pending=pending,dirtyKeys=pending.map{it.mutation.entity.table to it.mutation.recordId}.toSet())
        val store=Store(s);val remote=Remote();remote.observed[event]=InvestmentOrdinaryCloudSnapshot(owner,event,parent,null,emptyList())
        assertEquals(1,coordinator(store,remote).pushPending(owner,"token").pushed)
        assertEquals(1,remote.sends);assertTrue(store.state.pending.isEmpty())
        assertEquals(-30L,remote.observed.getValue(event).postings.single().payload.financeRawLong("amount_minor"))
    }

    @Test fun unresolvedSourceDoesNotBlockAnIndependentWalletFinancialGroup()=runTest {
        val store=Store(source());val remote=Remote();remote.observed[event]=differentCloud(store.state,now,0)
        assertEquals(1,coordinator(store,remote).pushPending(owner,"token").conflicts)
        val original=source();val g=investmentOrdinaryPublicationGroup(original)
        val wallet2=wallet(2)
        val seed=original.rows.single{it.id==id(10)}.let{it.copy(id=id(12),payload=JsonObject(it.payload+buildJsonObject {
            put("id",id(12));put("event_id",id(13));put("ledger_transaction_id",id(13));put("wallet_id",wallet2.id)
        }))}
        store.state=store.state.copy(rows=store.state.rows.filterNot{it.entity==wallet2.entity && it.id==wallet2.id}+wallet2+seed)
        val parent=g.primary.copy(id=id(21),payload=JsonObject(g.primary.payload+buildJsonObject{put("id",id(21));put("source_wallet_id",wallet2.id)}))
        val postId=investmentLedgerIdentity(id(21),"cash-consumption-booked")
        val post=g.postings.single().let{it.copy(id=postId,payload=JsonObject(it.payload+buildJsonObject {
            put("id",postId);put("event_id",id(21));put("ledger_transaction_id",id(21));put("wallet_id",wallet2.id)
        }))}
        store.dirty(parent);store.dirty(post)
        requireStableInvestmentOrdinaryAllocation(store.state.copy(eventId=id(21)))
        assertEquals(1,coordinator(store,remote).pushPending(owner,"token").pushed)
        assertEquals(1,remote.sends);assertEquals(2,store.state.pending.size)
        assertTrue(store.state.pending.all{it.nextAttemptAtEpochMillis==Long.MAX_VALUE})
    }
    @Test fun resolverPersistenceFailurePropagatesWithoutMutatingFinancialWorkOrRetryBookkeeping()=runTest {
        val store=Store(source());val remote=Remote();remote.observed[event]=differentCloud(store.state,"2026-10-28T00:20:00Z",2)
        store.failPoint="resolve";val before=store.state
        assertTrue(runCatching{coordinator(store,remote).pushPending(owner,"token")}.exceptionOrNull() is IOException)
        assertEquals(before,store.state);assertEquals(0,store.failures);assertEquals(0,remote.sends)
    }

    @Test fun latePaidOriginalCardPaymentCannotEscapeItsLockByBecomingIncome()=runTest {
        val store=Store(source(transfer=true,card=true));val remote=Remote()
        coordinator(store,remote).pushPending(owner,"token")
        val parent=CategoryDraft(id=id(32),name="Income",kind=TransactionCategoryKind.INCOME,hierarchyRole=CategoryHierarchyRole.PARENT).toMutation(owner,null,null,device,now).record
        val child=CategoryDraft(id=id(33),name="Salary",kind=TransactionCategoryKind.INCOME,hierarchyRole=CategoryHierarchyRole.CHILD,parentCategoryId=parent.id).toMutation(owner,null,parent,device,now).record
        store.state=store.state.copy(rows=store.state.rows+parent.toCloudRecord()+child.toCloudRecord())
        val snapshot=TransactionInvestmentSaveSnapshot(owner,TransactionInvestmentSaveSnapshot.entities.associateWith{e->store.state.rows.filter{it.entity==e.table}})
        var request=TransactionInvestmentSaveRequest(TransactionDraft(id=event,primaryKind=TransactionPrimaryKind.INCOME,title="Income",amountMinor=70,
            sourceWalletId=id(1),categoryId=child.id,occurredAt="2026-10-28T00:00:02Z"),null,null,"Adjustment","JPY")
        val error=runCatching{planTransactionInvestmentSave(snapshot,request,device,now)}.exceptionOrNull()
        if(error is InvestmentFundUsageConfirmationRequired)request=request.copy(consent=error.review.consent) else if(error!=null)throw error
        val plan=planTransactionInvestmentSave(snapshot,request,device,now)
        for((row,_) in plan.mutations)store.dirty(row)
        store.state=store.state.copy(pending=store.state.pending.map{q->
            if(q.mutation.payload?.financeRawString("deleted_at")==null)q else q.copy(mutation=q.mutation.copy(kind=MutationKind.DELETE))
        },rows=store.state.rows+paidCardOccurrence())
        coordinator(store,remote).pushPending(owner,"token")
        assertEquals("Original paid source remains locked after changing its proposed kind",1,remote.sends)
        assertEquals("transfer",remote.observed.getValue(event).transaction!!.payload.financeRawString("primary_kind_raw_value"))
        assertEquals(2,store.state.pending.size)
        assertTrue(store.state.pending.any{it.lastError=="ordinary_paid_source_locked"})
    }

    @Test fun confirmedInvestmentAllocationCanPublishWithCleanArchivedCategoryHistory()=runTest {
        for(ids in listOf(setOf(id(31)),setOf(id(30)),setOf(id(30),id(31)))) {
            val original=source()
            val changed=original.copy(rows=original.rows.map{row->
                if(row.entity==CloudEntity.TRANSACTION_CATEGORY.table && row.id in ids)row.copy(payload=JsonObject(row.payload+("is_archived" to JsonPrimitive(true)))) else row
            })
            val store=Store(changed);val remote=Remote()
            assertEquals("Archived category history must not strand a confirmed allocation: $ids",1,coordinator(store,remote).pushPending(owner,"token").pushed)
            assertEquals(1,remote.sends);assertTrue(store.state.pending.isEmpty())
            assertEquals(70L,remote.observed.getValue(event).transaction!!.payload.financeRawLong("amount_minor"))
        }
    }
    @Test fun deletedCategoryOrParentStillHoldsAConfirmedFinancialGroup()=runTest {
        for(target in listOf(id(30),id(31))) {
            val original=source()
            val changed=original.copy(rows=original.rows.map{row->
                if(row.entity==CloudEntity.TRANSACTION_CATEGORY.table && row.id==target)row.copy(deletedAt=now,payload=JsonObject(row.payload+("deleted_at" to JsonPrimitive(now)))) else row
            })
            val store=Store(changed);val remote=Remote();coordinator(store,remote).pushPending(owner,"token")
            assertEquals(0,remote.reads);assertEquals(0,remote.sends);assertEquals(changed,store.state)
        }
    }

}
