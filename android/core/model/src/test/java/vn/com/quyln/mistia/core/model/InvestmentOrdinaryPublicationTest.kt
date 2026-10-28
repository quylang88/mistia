package vn.com.quyln.mistia.core.model

import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class InvestmentOrdinaryPublicationTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val device="44444444-4444-4444-8444-444444444444"
    private val now="2026-10-28T00:00:00Z"
    private val later="2026-10-28T00:03:00Z"
    private fun id(n:Int)=java.util.UUID(0,n.toLong()).toString()
    private val event=id(20)
    private fun wallet(n:Int,opening:Long=100)=WalletDraft(id=id(n),name="Wallet$n",kind=WalletKind.CASH,currencyCode="JPY",openingBalanceMinor=opening).toMutation(owner,null,device,now).record
    private fun source(transfer:Boolean=false):InvestmentOrdinaryPublicationSnapshot {
        val parent=CategoryDraft(id=id(30),name="Parent",kind=TransactionCategoryKind.EXPENSE,hierarchyRole=CategoryHierarchyRole.PARENT).toMutation(owner,null,null,device,now).record
        val child=CategoryDraft(id=id(31),name="Child",kind=TransactionCategoryKind.EXPENSE,hierarchyRole=CategoryHierarchyRole.CHILD,parentCategoryId=parent.id).toMutation(owner,null,parent,device,now).record
        val root=wallet(99,0).let{it.copy(id=investmentSystemWalletId(owner),payload=JsonObject(it.payload+buildJsonObject{put("id",investmentSystemWalletId(owner));put("kind_raw_value","investment");put("system_purpose_raw_value","investmentProfit");put("investment_linked_wallet_id",id(1))}))}
        val legacy=CloudRecord(CloudEntity.INVESTMENT_POSTING.table,id(10),owner.value,buildJsonObject {
            put("id",id(10));put("user_id",owner.value);put("sync_version",0);put("deleted_at",JsonNull);put("created_at",now);put("updated_at",now)
            put("event_id",id(11));put("ledger_transaction_id",id(11));put("wallet_id",id(1));put("role_raw_value","cashAccrual");put("cash_bucket_raw_value","booked");put("cash_origin_raw_value","derived")
            put("amount_minor",60);put("accounting_amount_minor",60);put("currency_code","JPY");put("accounting_currency_code","JPY");put("occurred_at","2026-10-28T00:00:01Z")
        },now,null,0)
        val rows=listOf(root,wallet(1),wallet(2,0),parent.toCloudRecord(),child.toCloudRecord(),legacy)
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
    private fun changed(s:InvestmentOrdinaryPublicationSnapshot,row:CloudRecord):InvestmentOrdinaryPublicationSnapshot =s.copy(
        rows=s.rows.map{if(it.entity==row.entity && it.id==row.id)row else it},
        pending=s.pending.map{q->if(q.mutation.entity.table==row.entity && q.mutation.recordId==row.id)q.copy(mutation=q.mutation.copy(payload=row.payload,baseVersion=row.syncVersion,modifiedAt=row.updatedAt!!,kind=if(row.deletedAt==null)MutationKind.UPSERT else MutationKind.DELETE))else q})
    private fun canonical(s:InvestmentOrdinaryPublicationSnapshot)=s.rows.single{it.entity==CloudEntity.INVESTMENT_POSTING.table && it.payload.financeRawString("event_id")==event && it.payload.financeRawLong("amount_minor")!!<0}
    private fun bad(action:()->Unit){assertTrue(runCatching{action()}.exceptionOrNull() is IllegalArgumentException)}
    @Test fun aRealConsentedExpenseHasOneExactFinancialGroupWithoutAcknowledgingAnyQueue() {
        val s=source();val g=investmentOrdinaryPublicationGroup(s)
        assertEquals(event,g.primary.id);assertNull(g.adjustment);assertEquals(1,g.postings.size);assertEquals(-30L,g.postings.single().payload.financeRawLong("accounting_amount_minor"))
        assertEquals(s.pending,g.queues);assertEquals(setOf(event,investmentLedgerIdentity(event,"cash-consumption-booked")),g.rows.map{it.id}.toSet())
        assertEquals(listOf(event),investmentOrdinaryPublicationCandidates(s));assertEquals(2,s.pending.size)
    }
    @Test fun realInternalTransferRequiresItsCompleteBalancedSourceAndDestinationPair() {
        val s=source(true);val g=investmentOrdinaryPublicationGroup(s)
        assertEquals(setOf(-30L,30L),g.postings.map{it.payload.financeRawLong("accounting_amount_minor")}.toSet());assertEquals(3,g.queues.size)
        val missing=s.copy(rows=s.rows.filterNot{it.id==investmentLedgerIdentity(event,"cash-destination-booked")},pending=s.pending.filterNot{it.mutation.recordId==investmentLedgerIdentity(event,"cash-destination-booked")},dirtyKeys=s.dirtyKeys-filterSet())
        bad{investmentOrdinaryPublicationGroup(missing)}
    }
    private fun filterSet()=setOf(CloudEntity.INVESTMENT_POSTING.table to investmentLedgerIdentity(event,"cash-destination-booked"))
    @Test fun wrongRoleSignCurrencyEventOrAmountCannotAuthorizeOrdinaryCash() {
        val s=source();val p=canonical(s)
        val variants=listOf(buildJsonObject{put("role_raw_value","cashTransfer")},buildJsonObject{put("amount_minor",30);put("accounting_amount_minor",30)},
            buildJsonObject{put("currency_code","VND")},buildJsonObject{put("event_id",id(99))},buildJsonObject{put("amount_minor",-71);put("accounting_amount_minor",-71)})
        for(fields in variants)bad{investmentOrdinaryPublicationGroup(changed(s,p.copy(payload=JsonObject(p.payload+fields))))}
    }
    @Test fun anUnknownSameEventSiblingHoldsTheCompleteGroup() {
        val s=source();val p=canonical(s).let{it.copy(id=id(999),payload=JsonObject(it.payload+buildJsonObject{put("id",id(999));put("role_raw_value","cashCorrection")}))}
        bad{investmentOrdinaryPublicationGroup(s.copy(rows=s.rows+p))}
    }
    @Test fun archiveKeepsPrimaryHistoryAndRetiresTheExistingCanonicalAllocation() {
        val s=source();val primary=s.rows.single{it.id==event};val post=canonical(s)
        val archived=primary.copy(updatedAt=later,payload=JsonObject(primary.payload+buildJsonObject{put("is_archived",true);put("archived_at",later);put("updated_at",later)}))
        val deleted=post.copy(deletedAt=later,updatedAt=later,payload=JsonObject(post.payload+buildJsonObject{put("deleted_at",later);put("updated_at",later)}))
        val g=investmentOrdinaryPublicationGroup(changed(changed(s,archived),deleted))
        assertEquals(true,g.primary.payload.financeRawArchived());assertEquals(later,g.postings.single().deletedAt);assertEquals(2,g.queues.size)
        bad{investmentOrdinaryPublicationGroup(changed(s,archived))}
    }
    @Test fun aCleanParentWithOnlyThePostingQueuedStillDiscoversTheOrdinaryGroup() {
        val s=source();val pending=s.pending.filter{it.mutation.entity==CloudEntity.INVESTMENT_POSTING}
        val orphan=s.copy(pending=pending,dirtyKeys=pending.map{it.mutation.entity.table to it.mutation.recordId}.toSet())
        assertEquals(listOf(event),investmentOrdinaryPublicationCandidates(orphan));assertEquals(1,investmentOrdinaryPublicationGroup(orphan).queues.size)
    }
    @Test fun cleanPostingHistoryStillReservesAnEditedParentWithoutCreatingDuplicateCandidates() {
        val s=source();val pending=s.pending.filter{it.mutation.entity==CloudEntity.LEDGER_TRANSACTION}
        val onlyParent=s.copy(pending=pending,dirtyKeys=pending.map{it.mutation.entity.table to it.mutation.recordId}.toSet())
        assertEquals(listOf(event),investmentOrdinaryPublicationCandidates(onlyParent));assertEquals(1,investmentOrdinaryPublicationGroup(onlyParent).queues.size)
    }
    @Test fun foreignRowsOrPayloadEnvelopeMismatchNeverProduceAPublicationProof() {
        val s=source();val p=canonical(s)
        bad{changed(s,p.copy(ownerUserId=device,payload=JsonObject(p.payload+("user_id" to JsonPrimitive(device))))).requireCoherent()}
        bad{s.copy(pending=s.pending.map{q->if(q.mutation.entity==CloudEntity.INVESTMENT_POSTING)q.copy(mutation=q.mutation.copy(baseVersion=1))else q}).requireCoherent()}
    }
    @Test fun aNewerWholeGenerationCannotBeConsumedByTheCapturedPublication() {
        val s=source();s.requireCoherent();s.requireUnchanged(s)
        val primary=s.rows.single{it.id==event};val newer=changed(s,primary.copy(payload=JsonObject(primary.payload+("note" to JsonPrimitive("New intent")))))
        bad{s.requireUnchanged(newer)}
    }

    @Test fun aCanonicalPostingWithASpoofedEventStillRoutesToItsParentForClosedValidation() {
        val original=source();val p=canonical(original)
        val corrupted=changed(original,p.copy(payload=JsonObject(p.payload+("event_id" to JsonPrimitive(id(99))))))
        val pending=corrupted.pending.filter{it.mutation.entity==CloudEntity.INVESTMENT_POSTING}
        val s=corrupted.copy(pending=pending,dirtyKeys=pending.map{it.mutation.entity.table to it.mutation.recordId}.toSet())
        assertEquals(listOf(event),investmentOrdinaryPublicationCandidates(s))
        bad{investmentOrdinaryPublicationGroup(s)}
    }
    @Test fun nonFundCashHistoryDoesNotReserveAnUnrelatedOrdinaryIncomeMetadataEdit() {
        val original=source();val primary=original.rows.single{it.id==event};val old=canonical(original)
        val income=primary.copy(payload=JsonObject(primary.payload+buildJsonObject{put("primary_kind_raw_value","income");put("category_id",JsonNull)}))
        val cash=old.copy(id=id(888),payload=JsonObject(old.payload+buildJsonObject{put("id",id(888));put("role_raw_value","cashAccrual");put("amount_minor",30);put("accounting_amount_minor",30)}))
        val next=changed(original,income)
        val pending=next.pending.filter{it.mutation.entity==CloudEntity.LEDGER_TRANSACTION}
        val s=next.copy(rows=next.rows.filterNot{it==old}+cash,pending=pending,dirtyKeys=pending.map{it.mutation.entity.table to it.mutation.recordId}.toSet())
        assertTrue(investmentOrdinaryPublicationCandidates(s).isEmpty())
    }
    @Test fun discoveryUsesActualInstantsForOrderingHistoricalRowsWithDifferentOffsets() {
        val original=source();val p=canonical(original);val primary=original.rows.single{it.id==event}
        val earlier=id(21);val date="2026-10-28T07:00:01+07:00"
        val historical=primary.copy(id=earlier,updatedAt=later,payload=JsonObject(primary.payload+buildJsonObject{put("id",earlier);put("occurred_at",date);put("is_archived",true);put("archived_at",later);put("updated_at",later)}))
        val postId=investmentLedgerIdentity(earlier,"cash-consumption-booked")
        val historicalPost=p.copy(id=postId,deletedAt=later,updatedAt=later,payload=JsonObject(p.payload+buildJsonObject{put("id",postId);put("event_id",earlier);put("ledger_transaction_id",earlier);put("occurred_at",date);put("deleted_at",later);put("updated_at",later)}))
        fun queue(row:CloudRecord)=QueuedMutation(PendingMutation(CloudEntity.fromTable(row.entity)!!,row.id,owner.value,if(row.deletedAt==null)MutationKind.UPSERT else MutationKind.DELETE,row.payload,row.updatedAt!!,row.syncVersion,device),0,0,null)
        val pending=original.pending+listOf(queue(historical),queue(historicalPost))
        val s=original.copy(rows=original.rows+listOf(historical,historicalPost),pending=pending,dirtyKeys=pending.map{it.mutation.entity.table to it.mutation.recordId}.toSet())
        assertEquals(listOf(earlier,event),investmentOrdinaryPublicationCandidates(s))
    }
    private fun unreconciled():InvestmentOrdinaryPublicationSnapshot {
        val original=source();val old=canonical(original);val primary=original.rows.single{it.id==event}
        val postId=investmentLedgerIdentity(event,"cash-consumption-unreconciled")
        val post=old.copy(id=postId,payload=JsonObject(old.payload+buildJsonObject{put("id",postId);put("cash_bucket_raw_value","unreconciled")}))
        val adjustmentId=investmentLedgerIdentity(event,"cash-unreconciled-adjustment")
        val adjustment=primary.copy(id=adjustmentId,payload=JsonObject(primary.payload+buildJsonObject {
            put("id",adjustmentId);put("primary_kind_raw_value","transfer");put("transfer_subtype_raw_value","internalTransfer");put("settlement_role_raw_value","investmentReserveUse")
            put("title","Adjustment");put("source_wallet_id",investmentSystemWalletId(owner));put("destination_wallet_id",id(1));put("category_id",JsonNull)
            put("amount_minor",30);put("destination_amount_minor",30);put("reporting_amount_minor",30);put("reporting_expense_minor",0);put("reporting_income_minor",0)
            put("source_currency_code","JPY");put("destination_currency_code","JPY");put("reporting_currency_code","JPY")
        }))
        val pending=original.pending.map{q->if(q.mutation.recordId==old.id)q.copy(mutation=q.mutation.copy(recordId=post.id,payload=post.payload))else q}+QueuedMutation(PendingMutation(CloudEntity.LEDGER_TRANSACTION,adjustment.id,owner.value,MutationKind.UPSERT,adjustment.payload,now,0,device),0,0,null)
        return original.copy(rows=original.rows.map{if(it==old)post else it}+adjustment,pending=pending,dirtyKeys=pending.map{it.mutation.entity.table to it.mutation.recordId}.toSet())
    }
    @Test fun structuralUnreconciledGroupIncludesTheExactRequiredReserveLedger() {
        val s=unreconciled();val group=investmentOrdinaryPublicationGroup(s)
        assertEquals(3,group.rows.size);assertEquals(30L,group.adjustment!!.payload.financeRawLong("amount_minor"));assertEquals(-30L,group.postings.single().payload.financeRawLong("amount_minor"))
        val pending=s.pending.filter{it.mutation.recordId==group.adjustment!!.id}
        assertEquals(listOf(event),investmentOrdinaryPublicationCandidates(s.copy(pending=pending,dirtyKeys=pending.map{it.mutation.entity.table to it.mutation.recordId}.toSet())))
    }
    @Test fun missingOrMismatchedReserveLedgerNeverGrantsUnreconciledFinancialAuthority() {
        val s=unreconciled();val adjustment=s.rows.single{it.id==investmentLedgerIdentity(event,"cash-unreconciled-adjustment")}
        val pending=s.pending.filterNot{it.mutation.recordId==adjustment.id}
        bad{investmentOrdinaryPublicationGroup(s.copy(rows=s.rows-adjustment,pending=pending,dirtyKeys=pending.map{it.mutation.entity.table to it.mutation.recordId}.toSet()))}
        bad{investmentOrdinaryPublicationGroup(changed(s,adjustment.copy(payload=JsonObject(adjustment.payload+("amount_minor" to JsonPrimitive(29))))))}
    }

    private fun result(s:InvestmentOrdinaryPublicationSnapshot):InvestmentOrdinaryPublicationResult {
        val g=investmentOrdinaryPublicationGroup(s)
        fun saved(r:CloudRecord)=r.copy(syncVersion=r.syncVersion+1,payload=JsonObject(r.payload+("sync_version" to JsonPrimitive(r.syncVersion+1))))
        return InvestmentOrdinaryPublicationResult(s.owner,s.eventId,saved(g.primary),g.adjustment?.let(::saved),g.postings.map(::saved))
    }
    @Test fun completeOrdinaryResultProvesAllRowsAndOnlyCapturedGroupQueues() {
        for(s in listOf(source(),source(true),unreconciled())) {
            val reply=result(s);val plan=planInvestmentOrdinaryAcknowledgement(s,reply)
            assertEquals(reply.rows,plan.records)
            assertEquals(investmentOrdinaryPublicationGroup(s).queues.toSet(),plan.acknowledgements.map{it.first}.toSet())
            assertEquals(reply.rows.map{it.entity to it.id}.toSet(),plan.acknowledgements.map{it.second.entity to it.second.id}.toSet())
        }
    }
    @Test fun partialDuplicateForeignOrUnexpectedResultNeverAcknowledgesFinancialQueues() {
        val s=source(true);val r=result(s)
        fun foreign(row:CloudRecord)=row.copy(ownerUserId=device,payload=JsonObject(row.payload+("user_id" to JsonPrimitive(device))))
        for(broken in listOf(r.copy(owner=UserId(device)),r.copy(eventId=id(97)),r.copy(postings=r.postings.dropLast(1)),r.copy(postings=r.postings+ r.postings.first()),r.copy(transaction=foreign(r.transaction)),r.copy(postings=r.postings.map(::foreign)),r.copy(adjustment=r.transaction)))
            assertTrue(runCatching{planInvestmentOrdinaryAcknowledgement(s,broken)}.isFailure)
    }
    @Test fun resultRequiresExactlyOneComparedAdvanceForEveryFinancialRow() {
        val s=source();val r=result(s)
        for(version in listOf(0L,2L,Long.MAX_VALUE)) {
            val row=r.transaction.copy(syncVersion=version,payload=JsonObject(r.transaction.payload+("sync_version" to JsonPrimitive(version))))
            assertTrue(runCatching{planInvestmentOrdinaryAcknowledgement(s,r.copy(transaction=row))}.isFailure)
        }
        val p=r.postings.single();val mismatched=p.copy(payload=JsonObject(p.payload+("sync_version" to JsonPrimitive(2))))
        assertTrue(runCatching{planInvestmentOrdinaryAcknowledgement(s,r.copy(postings=listOf(mismatched)))}.isFailure)
    }
    @Test fun staleOrDifferentFinancialReplyCannotAcknowledgeNewerIntent() {
        val s=source();val r=result(s);val t=s.rows.single{it.id==event}
        val newer=changed(s,t.copy(payload=JsonObject(t.payload+("note" to JsonPrimitive("Newer note")))))
        assertTrue(runCatching{planInvestmentOrdinaryAcknowledgement(newer,r)}.isFailure)
        val p=r.postings.single();val altered=p.copy(payload=JsonObject(p.payload+buildJsonObject{put("amount_minor",-29);put("accounting_amount_minor",-29)}))
        assertTrue(runCatching{planInvestmentOrdinaryAcknowledgement(s,r.copy(postings=listOf(altered)))}.isFailure)
    }
    @Test fun PostgreSQLTimestampFormattingAndNullableColumnsPreserveExactBusinessMeaning() {
        val s=source();val r=result(s)
        fun postgres(row:CloudRecord):CloudRecord {
            val payload=JsonObject(row.payload.mapValues{(key,value)->if(key in setOf("created_at","updated_at","occurred_at") && value is JsonPrimitive && value.isString)JsonPrimitive(java.time.Instant.parse(value.content).toString().replace("Z","+00:00"))else value}+("future_nullable" to JsonNull))
            return row.copy(payload=payload,updatedAt=payload.financeRawString("updated_at"))
        }
        val reformatted=r.copy(transaction=postgres(r.transaction),postings=r.postings.map(::postgres))
        assertEquals(reformatted.rows,planInvestmentOrdinaryAcknowledgement(s,reformatted).records)
    }
    @Test fun orphanAllocationProofKeepsCleanParentAndEveryUnrelatedQueue() {
        val original=source();val parent=original.rows.single{it.id==event}
        val withCleanParent=changed(original,parent.copy(syncVersion=7,payload=JsonObject(parent.payload+("sync_version" to JsonPrimitive(7)))))
        val unrelated=withCleanParent.rows.single{it.entity==CloudEntity.LEDGER_WALLET.table && it.id==id(2)}
        val unrelatedQueue=QueuedMutation(PendingMutation(CloudEntity.LEDGER_WALLET,unrelated.id,owner.value,MutationKind.UPSERT,unrelated.payload,now,unrelated.syncVersion,device),0,0,null)
        val pending=withCleanParent.pending.filter{it.mutation.entity==CloudEntity.INVESTMENT_POSTING}+unrelatedQueue
        val s=withCleanParent.copy(pending=pending,dirtyKeys=pending.map{it.mutation.entity.table to it.mutation.recordId}.toSet())
        val r=result(s);val plan=planInvestmentOrdinaryAcknowledgement(s,r)
        assertEquals(2,plan.records.size);assertEquals(1,plan.acknowledgements.size)
        assertEquals(8L,plan.records.single{it.id==event}.syncVersion)
        assertFalse(plan.acknowledgements.any{it.first==unrelatedQueue})
        val empty=s.copy(pending=emptyList(),dirtyKeys=emptySet())
        assertTrue(runCatching{planInvestmentOrdinaryAcknowledgement(empty,result(empty))}.isFailure)
    }

    @Test fun financialAcknowledgementRetainsLongVersionsAboveJavascriptPrecisionAndAllTombstones() {
        val base=9007199254740993L
        var s=source()
        for(row in investmentOrdinaryPublicationGroup(s).rows) {
            val p=JsonObject(row.payload+("sync_version" to JsonPrimitive(base)))
            s=changed(s,row.copy(syncVersion=base,payload=p))
        }
        val t=s.rows.single{it.id==event}
        s=changed(s,t.copy(deletedAt=later,payload=JsonObject(t.payload+("deleted_at" to JsonPrimitive(later)))))
        val posting=canonical(s)
        s=changed(s,posting.copy(deletedAt=later,payload=JsonObject(posting.payload+("deleted_at" to JsonPrimitive(later)))))
        val plan=planInvestmentOrdinaryAcknowledgement(s,result(s))
        assertTrue(plan.records.all{it.syncVersion==base+1 && it.deletedAt==later})
        assertEquals(2,plan.acknowledgements.size)
    }
    @Test fun privateUnknownBusinessOrActorChangesInRepliesCannotBecomeAcknowledgements() {
        val s=source();val r=result(s)
        for(pair in listOf("_mistia_android_forged" to JsonPrimitive(true),"future_financial_field" to JsonPrimitive(1),"last_modified_by_device_id" to JsonPrimitive(id(999)),"amount_minor" to JsonPrimitive(69))) {
            val changed=r.transaction.copy(payload=JsonObject(r.transaction.payload+pair))
            assertTrue(runCatching{planInvestmentOrdinaryAcknowledgement(s,r.copy(transaction=changed))}.isFailure)
        }
    }

    private fun applyLocal(s:InvestmentOrdinaryPublicationSnapshot,p:InvestmentOrdinaryLocalPlan):InvestmentOrdinaryPublicationSnapshot {
        val keys=p.changes.map{it.first.entity to it.first.id}.toSet()
        val pending=s.pending.filterNot{it.mutation.entity.table to it.mutation.recordId in keys}+p.changes.map{it.second}
        return s.copy(rows=s.rows.filterNot{it.entity to it.id in keys}+p.changes.map{it.first},pending=pending,dirtyKeys=pending.map{it.mutation.entity.table to it.mutation.recordId}.toSet()).also{it.requireCoherent()}
    }
    private fun prepared(s:InvestmentOrdinaryPublicationSnapshot=source(),date:String=later)=applyLocal(s,planInvestmentOrdinaryPreparation(s,device,date))
    private fun rawParent(s:InvestmentOrdinaryPublicationSnapshot)=s.rows.single{it.entity==CloudEntity.LEDGER_TRANSACTION.table && it.id==event}
    private fun observed(r:InvestmentOrdinaryPublicationResult)=InvestmentOrdinaryCloudSnapshot(r.owner,r.eventId,r.transaction,r.adjustment,r.postings)
    @Test fun preparationJournalsACompleteOwnedProposalAndIsIdempotentBeforeRetry() {
        val s=prepared();val parent=rawParent(s)
        assertTrue(parent.payload.containsKey(LOCAL_ORDINARY_PUBLICATION_JOURNAL_KEY));assertFalse(requiresInvestmentLedgerDomain(parent.payload))
        val history=localOrdinaryPublicationHistory(parent);assertEquals(1,history.size);assertEquals(2,history.single().rows.size)
        assertEquals(investmentOrdinaryPublicationGroup(s).rows.map{it.entity to it.id}.toSet(),s.pending.map{it.mutation.entity.table to it.mutation.recordId}.toSet())
        assertFalse(ordinaryPublicationPayloadForCloud(parent).containsKey(LOCAL_ORDINARY_PUBLICATION_JOURNAL_KEY))
        assertTrue(planInvestmentOrdinaryPreparation(s,device,"2026-10-28T00:04:00Z").changes.isEmpty())
        assertEquals(2,planInvestmentOrdinaryAcknowledgement(s,result(s)).acknowledgements.size)
    }
    @Test fun olderOwnCompleteReplyRebasesEveryComparedRowAndPreservesTheNewerIntent() {
        val a=prepared();val oldReply=observed(result(a));val parent=rawParent(a)
        val newer=changed(a,parent.copy(payload=JsonObject(parent.payload+("note" to JsonPrimitive("New intent")))))
        val b=prepared(newer,"2026-10-28T00:05:00Z")
        assertEquals(2,localOrdinaryPublicationHistory(rawParent(b)).size)
        val rebased=applyLocal(b,planInvestmentOrdinaryRebase(b,oldReply))
        assertEquals("New intent",rawParent(rebased).payload.financeRawString("note"))
        assertTrue(investmentOrdinaryPublicationGroup(rebased).rows.all{it.syncVersion==1L})
        assertEquals(2,rebased.pending.size);assertTrue(localOrdinaryPublicationHistory(rawParent(rebased)).isEmpty())
        assertTrue(rebased.pending.all{it.remoteIdentityObserved})
        val next=prepared(rebased,"2026-10-28T00:06:00Z")
        assertTrue(localOrdinaryPublicationHistory(rawParent(next)).single().rows.all{it.baseVersion==1L})
    }
    @Test fun everyUnresolvedSameBaseProposalCanBeRecoveredWhicheverRequestWins() {
        val a=prepared();val parent=rawParent(a)
        val b=prepared(changed(a,parent.copy(payload=JsonObject(parent.payload+("note" to JsonPrimitive("B"))))),"2026-10-28T00:05:00Z")
        val c=prepared(changed(b,rawParent(b).copy(payload=JsonObject(rawParent(b).payload+("note" to JsonPrimitive("C"))))),"2026-10-28T00:06:00Z")
        assertEquals(3,localOrdinaryPublicationHistory(rawParent(c)).size)
        for(winner in listOf(a,b)) {
            val next=applyLocal(c,planInvestmentOrdinaryRebase(c,observed(result(winner))))
            assertEquals("C",rawParent(next).payload.financeRawString("note"));assertEquals(1L,rawParent(next).syncVersion)
        }
    }
    @Test fun anUnjournaledOrPartialDifferentReplyCannotRebaseANewerLocalIntent() {
        val s=source();val r=observed(result(s));val parent=rawParent(s)
        val newer=changed(s,parent.copy(payload=JsonObject(parent.payload+("note" to JsonPrimitive("New intent")))))
        assertTrue(runCatching{planInvestmentOrdinaryRebase(newer,r)}.isFailure)
        val staged=prepared(newer)
        assertTrue(runCatching{planInvestmentOrdinaryRebase(staged,r.copy(postings=emptyList()))}.isFailure)
        assertTrue(runCatching{planInvestmentOrdinaryRebase(staged,r.copy(owner=UserId(device)))}.isFailure)
    }
    @Test fun historyMustMatchOwnerEventBirthAndOnlyKnownCanonicalComponents() {
        val s=prepared();val parent=rawParent(s);val marker=parent.payload.getValue(LOCAL_ORDINARY_PUBLICATION_JOURNAL_KEY).jsonObject
        for(pair in listOf("owner_user_id" to JsonPrimitive(device),"event_id" to JsonPrimitive(id(99)),"created_at" to JsonPrimitive("2026-10-27T00:00:00Z"),"unknown" to JsonPrimitive(true))) {
            val corrupt=parent.copy(payload=JsonObject(parent.payload+(LOCAL_ORDINARY_PUBLICATION_JOURNAL_KEY to JsonObject(marker+pair))))
            assertTrue(runCatching{ordinaryPublicationPayloadForCloud(corrupt)}.isFailure)
        }
    }
    @Test fun aFullUnresolvedHistoryNeverEvictsAnOlderRequest() {
        var s=source()
        repeat(64){n->
            val p=rawParent(s);s=changed(s,p.copy(payload=JsonObject(p.payload+("note" to JsonPrimitive("Intent$n")))))
            s=prepared(s,java.time.Instant.parse(later).plusSeconds(n.toLong()).toString())
        }
        assertEquals(64,localOrdinaryPublicationHistory(rawParent(s)).size)
        val p=rawParent(s);val newer=changed(s,p.copy(payload=JsonObject(p.payload+("note" to JsonPrimitive("Intent65")))))
        assertTrue(runCatching{planInvestmentOrdinaryPreparation(newer,device,"2026-10-28T00:10:00Z")}.isFailure)
        assertEquals(64,localOrdinaryPublicationHistory(rawParent(s)).size)
    }
    @Test fun validatedSyncOnlyJournalDoesNotRevokeFinancialConsentOrChangeTheTimeline() {
        val before=source();val after=prepared(before)
        fun review(s:InvestmentOrdinaryPublicationSnapshot)=reviewInvestmentFundUsage(InvestmentCashReadSnapshot(s.owner,s.rows.filter{CloudEntity.fromTable(it.entity) in InvestmentCashReadSnapshot.entities}),"JPY",rawParent(s))
        assertEquals(review(before).consent,review(after).consent)
        assertEquals(review(before).comparison,review(after).comparison)
    }
    @Test fun preparationQueuesAFormerlyCleanParentSoPullCannotDiscardItsIntentJournal() {
        val original=source();val parent=rawParent(original)
        val next=changed(original,parent.copy(syncVersion=7,payload=JsonObject(parent.payload+("sync_version" to JsonPrimitive(7)))))
        val pending=next.pending.filter{it.mutation.entity==CloudEntity.INVESTMENT_POSTING}
        val s=next.copy(pending=pending,dirtyKeys=pending.map{it.mutation.entity.table to it.mutation.recordId}.toSet())
        val staged=prepared(s)
        assertEquals(2,staged.pending.size);assertTrue(CloudEntity.LEDGER_TRANSACTION.table to event in staged.dirtyKeys)
        assertEquals(7L,staged.pending.single{it.mutation.recordId==event}.mutation.baseVersion)
        assertTrue(staged.pending.single{it.mutation.recordId==event}.remoteIdentityObserved)
    }

    @Test fun observedZeroVersionsAreAdoptedAsExistingWithoutAdvancingOrClearingFinancialIntent() {
        val s=source();val group=investmentOrdinaryPublicationGroup(s)
        val cloud=InvestmentOrdinaryCloudSnapshot(owner,event,group.primary,null,group.postings)
        val next=applyLocal(s,planInvestmentOrdinaryRebase(s,cloud))
        assertTrue(next.pending.all{it.remoteIdentityObserved && it.mutation.baseVersion==0L})
        val staged=prepared(next)
        assertTrue(localOrdinaryPublicationHistory(rawParent(staged)).single().rows.all{it.expectedPresent})
        assertTrue(investmentOrdinaryExpectedPresence(staged).values.all{it})
    }
    @Test fun cleanObservedZeroParentCannotLoseItsExistenceEvidenceWhenPreparationQueuesIt() {
        val initial=source();val pending=initial.pending.filter{it.mutation.entity==CloudEntity.INVESTMENT_POSTING}
        val clean=initial.copy(pending=pending,dirtyKeys=pending.map{it.mutation.entity.table to it.mutation.recordId}.toSet())
        val staged=prepared(clean)
        assertTrue(staged.pending.single{it.mutation.recordId==event}.remoteIdentityObserved)
        val flags=investmentOrdinaryExpectedPresence(staged)
        assertEquals(true,flags[event]);assertEquals(false,flags[canonical(staged).id])
        assertTrue(localOrdinaryPublicationHistory(rawParent(staged)).single().rows.single{it.id==event}.expectedPresent)
    }
    @Test fun freshZeroBirthsKeepCompleteExplicitAbsenceComparisonsInTheirIntent() {
        val s=prepared();val flags=investmentOrdinaryExpectedPresence(s)
        assertEquals(investmentOrdinaryPublicationGroup(s).rows.map{it.id}.toSet(),flags.keys)
        assertTrue(flags.values.none{it});assertTrue(localOrdinaryPublicationHistory(rawParent(s)).single().rows.none{it.expectedPresent})
    }

    @Test fun sameFinancialOrphanAdoptsComparedBasesWithoutAcknowledgingAnyAllocation() {
        val s=source();val parent=investmentOrdinaryPublicationGroup(s).primary
        val remote=parent.copy(syncVersion=7,updatedAt=later,payload=JsonObject(parent.payload+buildJsonObject {
            put("sync_version",7);put("updated_at",later);put("last_modified_by_device_id",id(90));put("last_modified_by_user_id",owner.value)
        }))
        val observed=InvestmentOrdinaryCloudSnapshot(owner,event,remote,null,emptyList())
        val plan=planInvestmentOrdinaryRebase(s,observed)
        val after=applyLocal(s,plan);val group=investmentOrdinaryPublicationGroup(after)
        assertEquals(7L,group.primary.syncVersion);assertEquals(0L,group.postings.single().syncVersion)
        assertEquals(70L,group.primary.payload.financeRawLong("amount_minor"));assertEquals(s.pending.size,after.pending.size)
        assertTrue(after.pending.single{it.mutation.recordId==event}.remoteIdentityObserved)
        assertFalse(after.pending.single{it.mutation.entity==CloudEntity.INVESTMENT_POSTING}.remoteIdentityObserved)
        assertTrue(runCatching{planInvestmentOrdinaryAcknowledgement(s,result(s).copy(transaction=remote))}.isFailure)
    }
    @Test fun sameFinancialOrphanCannotAdoptDifferentBirthBusinessOrRegressedIdentity() {
        val s=source();val parent=investmentOrdinaryPublicationGroup(s).primary
        val v=parent.copy(syncVersion=7,payload=JsonObject(parent.payload+("sync_version" to JsonPrimitive(7))))
        for(fields in listOf(buildJsonObject{put("amount_minor",71)},buildJsonObject{put("created_at",later)},buildJsonObject{put("note","Other intent")})) {
            val remote=v.copy(payload=JsonObject(v.payload+fields))
            assertTrue(runCatching{planInvestmentOrdinaryRebase(s,InvestmentOrdinaryCloudSnapshot(owner,event,remote,null,emptyList()))}.isFailure)
        }
    }

    @Test fun ordinaryConsumptionCanStageTheActiveWalletWithoutConsumingItsFinalArchive() {
        val original=source();val active=original.rows.single{it.entity==CloudEntity.LEDGER_WALLET.table && it.id==id(1)}.let {
            it.copy(syncVersion=1,payload=JsonObject(it.payload+("sync_version" to JsonPrimitive(1))))
        }
        val archived=LedgerWalletRecord.fromCloudRecord(active).toArchiveMutation(device,later)
        val rows=original.rows.filter{CloudEntity.fromTable(it.entity) in InvestmentTradePublicationSnapshot.entities}.map{if(it.entity==active.entity && it.id==active.id)archived.record else it}
        val pending=original.pending+QueuedMutation(archived.pending,0,0,null)
        val s=InvestmentTradePublicationSnapshot(owner,event,rows,pending,pending.map{it.mutation.entity.table to it.mutation.recordId}.toSet())
        val proposal=prepareWalletInvestmentPrerequisite(s,id(1),active)
        assertFalse(proposal.needsWrite);assertTrue(proposal.preparedRecord.payload.financeRawArchived()==true)
        assertEquals(active,walletInvestmentActivePrerequisite(proposal.preparedRecord))
        val ledgerOnly=s.copy(pending=s.pending.filter{it.mutation.entity!=CloudEntity.INVESTMENT_POSTING},dirtyKeys=s.dirtyKeys-filterSet()-setOf(CloudEntity.INVESTMENT_POSTING.table to canonical(original).id))
        assertTrue(walletHasPendingInvestmentFinancialDependency(ledgerOnly,id(1)))
        assertNotNull(prepareWalletInvestmentPrerequisite(ledgerOnly,id(1),active))
    }

    private fun genericBeforeFund(target:Long=1L):Pair<InvestmentOrdinaryPublicationSnapshot,CloudRecord> {
        val s=source();val parent=investmentOrdinaryPublicationGroup(s).primary
        val normal=parent.copy(payload=JsonObject(parent.payload+("amount_minor" to JsonPrimitive(20))))
        val q=s.pending.single{it.mutation.recordId==event}.let{it.copy(mutation=it.mutation.copy(payload=normal.payload))}
        val wire=JsonObject(normal.payload+("sync_version" to JsonPrimitive(target)))
        val staged=planTransactionPublicationPreparation(q,normal,wire)
        val current=parent.copy(payload=JsonObject(parent.payload+(LOCAL_ORDINARY_PUBLICATION_JOURNAL_KEY to staged.first.payload.getValue(LOCAL_ORDINARY_PUBLICATION_JOURNAL_KEY))))
        val funded=changed(s,current)
        val reply=normal.copy(syncVersion=target,payload=wire)
        return funded to reply
    }
    @Test fun exactGenericCreateAncestryPreservesNewFundIntentEvenWithEqualOrBackwardClock() {
        val (s,reply)=genericBeforeFund()
        for(date in listOf(now,"2026-10-27T23:00:00Z")) {
            val p=rawParent(s);val current=changed(s,p.copy(updatedAt=date,payload=JsonObject(p.payload+("updated_at" to JsonPrimitive(date)))))
            val next=applyLocal(current,planInvestmentOrdinaryRebase(current,InvestmentOrdinaryCloudSnapshot(owner,event,reply,null,emptyList())))
            assertEquals(70L,rawParent(next).payload.financeRawLong("amount_minor"));assertEquals(1L,rawParent(next).syncVersion)
            assertEquals(0L,canonical(next).syncVersion);assertEquals(2,next.pending.size)
        }
    }
    @Test fun genericLocalWinnerCapturesActualTargetInsteadOfGuessingLocalBasePlusOne() {
        val (s,reply)=genericBeforeFund(9007199254740995L)
        val next=applyLocal(s,planInvestmentOrdinaryRebase(s,InvestmentOrdinaryCloudSnapshot(owner,event,reply,null,emptyList())))
        assertEquals(9007199254740995L,rawParent(next).syncVersion);assertEquals(0L,canonical(next).syncVersion)
        val wrong=reply.copy(syncVersion=9007199254740996L,payload=JsonObject(reply.payload+("sync_version" to JsonPrimitive(9007199254740996L))))
        assertTrue(runCatching{planInvestmentOrdinaryRebase(s,InvestmentOrdinaryCloudSnapshot(owner,event,wrong,null,emptyList()))}.isFailure)
    }
    @Test fun genericHistoryCannotBeInventedFromDifferentBusinessOrActorReply() {
        val (s,reply)=genericBeforeFund()
        for(fields in listOf(buildJsonObject{put("amount_minor",21)},buildJsonObject{put("last_modified_by_device_id",id(90))},buildJsonObject{put("created_at",later)})) {
            val altered=reply.copy(payload=JsonObject(reply.payload+fields))
            assertTrue(runCatching{planInvestmentOrdinaryRebase(s,InvestmentOrdinaryCloudSnapshot(owner,event,altered,null,emptyList()))}.isFailure)
        }
    }

    @Test fun aGenericPrimaryOnlyJournalNeverInventsAnInvestmentWalletReservation() {
        val s=source();val g=investmentOrdinaryPublicationGroup(s)
        val normal=g.primary.copy(payload=JsonObject(g.primary.payload+("amount_minor" to JsonPrimitive(20))))
        val q=s.pending.single{it.mutation.recordId==event}.let{it.copy(mutation=it.mutation.copy(payload=normal.payload))}
        val prepared=planTransactionPublicationPreparation(q,normal,JsonObject(normal.payload+("sync_version" to JsonPrimitive(1))))
        val rows=s.rows.filter{it.id !in g.rows.map{r->r.id} && CloudEntity.fromTable(it.entity) in InvestmentTradePublicationSnapshot.entities}+prepared.first
        val trade=InvestmentTradePublicationSnapshot(owner,event,rows,listOf(prepared.second),setOf(normal.entity to normal.id))
        assertFalse(walletHasPendingInvestmentFinancialDependency(trade,id(1)))
    }

    private fun remoteDifferent(s:InvestmentOrdinaryPublicationSnapshot=source(),date:String=later,version:Long=2):InvestmentOrdinaryCloudSnapshot {
        val group=investmentOrdinaryPublicationGroup(s)
        fun remote(row:CloudRecord,fields:JsonObject)=row.copy(syncVersion=version,updatedAt=date,payload=JsonObject(row.payload+fields+buildJsonObject {
            put("sync_version",version);put("updated_at",date);put("last_modified_by_device_id",id(90))
        }))
        return InvestmentOrdinaryCloudSnapshot(owner,event,remote(group.primary,buildJsonObject{put("amount_minor",80);put("reporting_amount_minor",80)}),null,
            group.postings.map{remote(it,buildJsonObject{put("amount_minor",-40);put("accounting_amount_minor",-40)})})
    }
    @Test fun wholeRemoteWinnerImportsEightyAndFortyTogetherAndOnlyCapturedQueues() {
        val s=source();val remote=remoteDifferent(s)
        val plan=planInvestmentOrdinaryConflict(s,remote) as InvestmentOrdinaryConflictPlan.Remote
        assertEquals(2,plan.records.size);assertEquals(80L,plan.records.single{it.id==event}.payload.financeRawLong("amount_minor"))
        assertEquals(-40L,plan.records.single{it.entity==CloudEntity.INVESTMENT_POSTING.table}.payload.financeRawLong("amount_minor"))
        assertEquals(s.pending,plan.queues);assertTrue(plan.removals.isEmpty())
    }
    @Test fun wholeLocalWinnerRebasesBothRowsButKeepsSeventyAndThirtyPending() {
        val s=source();val remote=remoteDifferent(s,date="2026-10-27T23:59:59Z")
        val plan=planInvestmentOrdinaryConflict(s,remote) as InvestmentOrdinaryConflictPlan.Local
        val next=applyLocal(s,plan.plan)
        assertEquals(70L,rawParent(next).payload.financeRawLong("amount_minor"));assertEquals(-30L,canonical(next).payload.financeRawLong("amount_minor"))
        assertEquals(2,next.pending.size);assertTrue(next.pending.all{it.mutation.baseVersion==2L && it.remoteIdentityObserved})
    }
    @Test fun sameClockVersionDifferentWholeEventRetainsRawEvidenceWithoutAcknowledgement() {
        val s=source();val remote=remoteDifferent(s,date=now,version=0)
        val plan=planInvestmentOrdinaryConflict(s,remote) as InvestmentOrdinaryConflictPlan.Unresolved
        assertEquals("same_clock_version_different_payload",plan.reason)
        assertEquals(remote,plan.observed);assertEquals(investmentOrdinaryPublicationGroup(s).rows,plan.localRows)
        assertEquals(2,s.pending.size)
    }
    @Test fun foreignOrDifferentBirthOrMathematicallyIncompleteRemoteNeverWins() {
        val s=source();val remote=remoteDifferent(s)
        val p=remote.transaction!!
        val foreign=p.copy(ownerUserId=device,payload=JsonObject(p.payload+("user_id" to JsonPrimitive(device))))
        val otherBirth=p.copy(payload=JsonObject(p.payload+("created_at" to JsonPrimitive(later))))
        val wrong=remote.postings.single().let{it.copy(payload=JsonObject(it.payload+buildJsonObject{put("amount_minor",-39);put("accounting_amount_minor",-39)}))}
        for(broken in listOf(remote.copy(owner=UserId(device)),remote.copy(transaction=foreign),remote.copy(transaction=otherBirth),remote.copy(postings=listOf(wrong))))
            assertTrue(runCatching{planInvestmentOrdinaryConflict(s,broken)}.isFailure)
    }
    @Test fun remoteNormalWinnerDiscardsOnlyGenuineUnobservedLocalPostingBirths() {
        val s=source();val parent=investmentOrdinaryPublicationGroup(s).primary
        val remoteParent=parent.copy(syncVersion=2,updatedAt=later,payload=JsonObject(parent.payload+buildJsonObject{put("amount_minor",20);put("reporting_amount_minor",20);put("sync_version",2);put("updated_at",later);put("last_modified_by_device_id",id(90))}))
        val remote=InvestmentOrdinaryCloudSnapshot(owner,event,remoteParent,null,emptyList())
        val plan=planInvestmentOrdinaryConflict(s,remote) as InvestmentOrdinaryConflictPlan.Remote
        assertEquals(listOf(remoteParent),plan.records);assertEquals(setOf(CloudEntity.INVESTMENT_POSTING.table to canonical(s).id),plan.removals)
        val observed=s.copy(pending=s.pending.map{if(it.mutation.entity==CloudEntity.INVESTMENT_POSTING)it.copy(remoteIdentityObserved=true)else it})
        assertTrue(runCatching{planInvestmentOrdinaryConflict(observed,remote)}.isFailure)
        val post=canonical(s);val positive=changed(s,post.copy(syncVersion=1,payload=JsonObject(post.payload+("sync_version" to JsonPrimitive(1)))))
        assertTrue(runCatching{planInvestmentOrdinaryConflict(positive,remote)}.isFailure)
    }

    @Test fun localPolicyKeepsAnUnresolvedGenericRequestThatCanStillCommitAtObservedBase() {
        val (s,_)=genericBeforeFund(3)
        val plan=planInvestmentOrdinaryConflict(s,remoteDifferent(s,date="2026-10-27T23:59:59Z",version=2)) as InvestmentOrdinaryConflictPlan.Local
        val next=applyLocal(s,plan.plan)
        val history=localOrdinaryPublicationHistory(rawParent(next))
        assertEquals(1,history.size);assertEquals(2L,history.single().rows.single().baseVersion)
        assertEquals(70L,rawParent(next).payload.financeRawLong("amount_minor"));assertEquals(2,next.pending.size)
    }
    @Test fun localPolicyIncludesRemoteOnlyCanonicalTombstoneInNextComparedGroup() {
        val s=source();val remote=remoteDifferent(s,date="2026-10-27T23:59:59Z")
        val original=remote.postings.single();val extraId=investmentLedgerIdentity(event,"cash-consumption-unreconciled")
        val extra=original.copy(id=extraId,deletedAt=now,updatedAt=now,payload=JsonObject(original.payload+buildJsonObject {
            put("id",extraId);put("cash_bucket_raw_value","unreconciled");put("amount_minor",-10);put("accounting_amount_minor",-10);put("deleted_at",now);put("updated_at",now)
        }))
        val plan=planInvestmentOrdinaryConflict(s,remote.copy(postings=remote.postings+extra)) as InvestmentOrdinaryConflictPlan.Local
        val next=applyLocal(s,plan.plan);val group=investmentOrdinaryPublicationGroup(next)
        assertEquals(2,group.postings.size);assertEquals(3,next.pending.size)
        assertEquals(extra,group.postings.single{it.id==extraId});assertTrue(next.pending.single{it.mutation.recordId==extraId}.remoteIdentityObserved)
        assertTrue(investmentOrdinaryExpectedPresence(next).values.all{it})
    }
    @Test fun missingPositivePrimaryRegressedRowsDuplicateRowsAndPrivateRemoteCannotResolve() {
        val s=source();val original=remoteDifferent(s)
        val parent=rawParent(s);val post=canonical(s)
        val positive=changed(changed(s,parent.copy(syncVersion=3,payload=JsonObject(parent.payload+("sync_version" to JsonPrimitive(3))))),post.copy(syncVersion=3,payload=JsonObject(post.payload+("sync_version" to JsonPrimitive(3)))))
        assertTrue(runCatching{planInvestmentOrdinaryConflict(positive,original)}.isFailure)
        val private=original.transaction!!.let{it.copy(payload=JsonObject(it.payload+("_mistia_android_fake" to JsonPrimitive(true))))}
        for(remote in listOf(original.copy(transaction=null),original.copy(postings=original.postings+original.postings),original.copy(transaction=private)))
            assertTrue(runCatching{planInvestmentOrdinaryConflict(s,remote)}.isFailure)
    }

    @Test fun unresolvedEvidenceRetainsCompleteEventAndQueuesWhileWireStripsOnlyValidatedState() {
        val source=source();val remote=remoteDifferent(source,date=now,version=0)
        val unresolved=planInvestmentOrdinaryConflict(source,remote) as InvestmentOrdinaryConflictPlan.Unresolved
        val next=applyLocal(source,planInvestmentOrdinaryUnresolved(source,unresolved))
        assertEquals(unresolved,localInvestmentOrdinaryConflict(rawParent(next)))
        assertEquals(70L,rawParent(next).payload.financeRawLong("amount_minor"));assertEquals(-30L,canonical(next).payload.financeRawLong("amount_minor"))
        assertEquals(2,next.pending.size);assertTrue(next.pending.all{it.nextAttemptAtEpochMillis==Long.MAX_VALUE})
        assertFalse(ordinaryPublicationPayloadForCloud(rawParent(next)).containsKey(LOCAL_ORDINARY_CONFLICT_KEY))
    }
    @Test fun malformedOrForeignConflictEvidenceCannotBeStrippedOrSentAsAnOrdinaryPayload() {
        val s=source();val unresolved=planInvestmentOrdinaryConflict(s,remoteDifferent(s,date=now,version=0)) as InvestmentOrdinaryConflictPlan.Unresolved
        val current=applyLocal(s,planInvestmentOrdinaryUnresolved(s,unresolved));val row=rawParent(current)
        val marker=row.payload.getValue(LOCAL_ORDINARY_CONFLICT_KEY).jsonObject
        for(fields in listOf(buildJsonObject{put("owner_user_id",device)},buildJsonObject{put("event_id",id(99))},buildJsonObject{put("version",2)})) {
            val corrupt=row.copy(payload=JsonObject(row.payload+(LOCAL_ORDINARY_CONFLICT_KEY to JsonObject(marker+fields))))
            assertTrue(runCatching{ordinaryPublicationPayloadForCloud(corrupt)}.isFailure)
        }
        val newer=row.copy(payload=JsonObject(row.payload+("note" to JsonPrimitive("A later local choice"))))
        assertEquals(unresolved,localInvestmentOrdinaryConflict(newer))
    }

    @Test fun malformedHistoricalPostingCurrencyCannotHideInsideConflictEvidence() {
        val s=source();val unresolved=planInvestmentOrdinaryConflict(s,remoteDifferent(s,date=now,version=0)) as InvestmentOrdinaryConflictPlan.Unresolved
        val current=applyLocal(s,planInvestmentOrdinaryUnresolved(s,unresolved));val row=rawParent(current)
        val marker=row.payload.getValue(LOCAL_ORDINARY_CONFLICT_KEY).jsonObject
        val badRows=marker.getValue("remote").jsonArray.map{element->
            val item=element.jsonObject
            if(item.financeRawString("entity")!=CloudEntity.INVESTMENT_POSTING.table)item else JsonObject(item+("payload" to JsonObject(item.getValue("payload").jsonObject+("currency_code" to JsonPrimitive("INVALID")))))
        }
        val badMarker=JsonObject(marker+("remote" to JsonArray(badRows)))
        val corrupt=row.copy(payload=JsonObject(row.payload+(LOCAL_ORDINARY_CONFLICT_KEY to badMarker)))
        assertTrue(runCatching{ordinaryPublicationPayloadForCloud(corrupt)}.isFailure)
    }

    @Test fun aKnownGenericPrimaryReplyCanRebaseAlongsideUnchangedComparedAllocationHistory() {
        val (original,reply)=genericBeforeFund(3)
        val remote=remoteDifferent(original,date="2026-10-27T23:59:59Z",version=2)
        val local=planInvestmentOrdinaryConflict(original,remote) as InvestmentOrdinaryConflictPlan.Local
        val current=applyLocal(original,local.plan)
        val observed=remote.copy(transaction=reply)
        val next=applyLocal(current,planInvestmentOrdinaryRebase(current,observed))
        assertEquals(3L,rawParent(next).syncVersion);assertEquals(2L,canonical(next).syncVersion)
        assertEquals(70L,rawParent(next).payload.financeRawLong("amount_minor"));assertEquals(-30L,canonical(next).payload.financeRawLong("amount_minor"))
        assertEquals(2,next.pending.size)
        val changed=remote.postings.single().let{it.copy(syncVersion=3,payload=JsonObject(it.payload+("sync_version" to JsonPrimitive(3))))}
        assertTrue(runCatching{planInvestmentOrdinaryRebase(current,observed.copy(postings=listOf(changed)))}.isFailure)
    }
    @Test fun remotePolicyCannotDiscardAnOwnRequestThatCanStillCommitAtObservedBase() {
        val (s,_)=genericBeforeFund(3)
        val observed=remoteDifferent(s,version=2)
        val planned=planInvestmentOrdinaryConflict(s,observed)
        assertTrue("An in-flight own proposal must preserve conflict evidence",planned is InvestmentOrdinaryConflictPlan.Unresolved)
        val plan=planned as InvestmentOrdinaryConflictPlan.Unresolved
        assertEquals("pending_own_proposal",plan.reason)
        val current=applyLocal(s,planInvestmentOrdinaryUnresolved(s,plan))
        assertEquals(1,localOrdinaryPublicationHistory(rawParent(current)).size)
        assertEquals(observed,localInvestmentOrdinaryConflict(rawParent(current))!!.observed)
        assertEquals(2,current.pending.size)
    }

    @Test fun knownGenericReplyCanObserveAnIdenticalZeroSiblingWithDifferentAuditStamps() {
        val (s,reply)=genericBeforeFund(3)
        val post=canonical(s).let{it.copy(updatedAt=later,payload=JsonObject(it.payload+buildJsonObject{put("updated_at",later);put("last_modified_by_device_id",id(90))}))}
        val next=applyLocal(s,planInvestmentOrdinaryRebase(s,InvestmentOrdinaryCloudSnapshot(owner,event,reply,null,listOf(post))))
        assertEquals(3L,rawParent(next).syncVersion);assertEquals(0L,canonical(next).syncVersion)
        assertEquals(70L,rawParent(next).payload.financeRawLong("amount_minor"));assertEquals(-30L,canonical(next).payload.financeRawLong("amount_minor"))
        assertEquals(2,next.pending.size);assertTrue(next.pending.all{it.remoteIdentityObserved})
    }

    @Test fun financialComparisonIgnoresOnlySyncEvidenceAuditAndTimestampRepresentation() {
        val s=prepared();val parent=rawParent(s)
        val same=investmentOrdinaryPublicationGroup(s).primary.copy(syncVersion=9,updatedAt=later,payload=JsonObject(investmentOrdinaryPublicationGroup(s).primary.payload+buildJsonObject {
            put("sync_version",9);put("updated_at",later);put("last_modified_by_device_id",id(90));put("last_modified_by_user_id",id(91));put("created_at","2026-10-28T00:00:00.000000Z");put("optional_future_field",JsonNull)
        }))
        assertFalse(ordinaryPublicationHasFinancialDifferences(parent,same))
        for(fields in listOf(buildJsonObject{put("amount_minor",71)},buildJsonObject{put("note","Changed")},buildJsonObject{put("deleted_at",later)},buildJsonObject{put("source_wallet_id",id(2))}))
            assertTrue(ordinaryPublicationHasFinancialDifferences(parent,same.copy(payload=JsonObject(same.payload+fields),deletedAt=fields.financeRawString("deleted_at"))))
    }

    @Test fun remoteWinnerThatWouldReattributeAnotherConfirmedEventRetainsTypedConflictEvidence() {
        val original=source()
        val save=TransactionInvestmentSaveSnapshot(owner,TransactionInvestmentSaveSnapshot.entities.associateWith{e->original.rows.filter{it.entity==e.table}})
        var request=TransactionInvestmentSaveRequest(TransactionDraft(primaryKind=TransactionPrimaryKind.EXPENSE,title="Second expense",amountMinor=20,
            sourceWalletId=id(1),categoryId=id(31),occurredAt="2026-10-28T00:00:03Z"),TransactionCreationIdentity(id(21),now),null,"Adjustment","JPY")
        val error=runCatching{planTransactionInvestmentSave(save,request,device,now)}.exceptionOrNull() as InvestmentFundUsageConfirmationRequired
        request=request.copy(consent=error.review.consent)
        val created=planTransactionInvestmentSave(save,request,device,now)
        val s=applyLocal(original,InvestmentOrdinaryLocalPlan(created.mutations.map{it.first to QueuedMutation(it.second,0,0,null)}))
        requireStableInvestmentOrdinaryAllocation(s)
        val parent=rawParent(s)
        val remote=InvestmentOrdinaryCloudSnapshot(owner,event,parent.copy(syncVersion=2,updatedAt=later,payload=JsonObject(parent.payload+buildJsonObject {
            put("amount_minor",30);put("reporting_amount_minor",30);put("sync_version",2);put("updated_at",later);put("last_modified_by_device_id",id(90))
        })),null,emptyList())
        val planned=planInvestmentOrdinaryConflict(s,remote)
        assertTrue("Related allocation changes need a recoverable conflict",planned is InvestmentOrdinaryConflictPlan.Unresolved)
        val conflict=planned as InvestmentOrdinaryConflictPlan.Unresolved
        assertEquals("other_event_allocation_changed",conflict.reason)
        val retained=applyLocal(s,planInvestmentOrdinaryUnresolved(s,conflict))
        assertEquals(conflict,localInvestmentOrdinaryConflict(rawParent(retained)))
        assertEquals(s.pending.size,retained.pending.size)
        assertEquals(70L,rawParent(retained).payload.financeRawLong("amount_minor"))
        assertEquals(-20L,retained.rows.single{it.id==investmentLedgerIdentity(id(21),"cash-consumption-booked")}.payload.financeRawLong("amount_minor"))
    }

}
