package vn.com.quyln.mistia.core.model

import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class TransactionInvestmentLifecyclePlanTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val device="44444444-4444-4444-8444-444444444444"
    private val now="2026-10-23T00:00:00Z"
    private val operation="2026-10-23T00:01:00Z"
    private fun id(n:Int)=java.util.UUID(0,n.toLong()).toString()
    private fun wallet()=WalletDraft(id=id(1),name="Cash",kind=WalletKind.CASH,currencyCode="JPY",openingBalanceMinor=100).toMutation(owner,null,device,now).record
    private fun base():TransactionInvestmentSaveSnapshot {
        val system=wallet().let{it.copy(id=investmentSystemWalletId(owner),payload=JsonObject(it.payload+buildJsonObject{put("id",investmentSystemWalletId(owner));put("kind_raw_value","investment");put("system_purpose_raw_value","investmentProfit")}))}
        val parent=CategoryDraft(id=id(30),name="Expense",kind=TransactionCategoryKind.EXPENSE,hierarchyRole=CategoryHierarchyRole.PARENT).toMutation(owner,null,null,device,now).record
        val child=CategoryDraft(id=id(31),name="Child",kind=TransactionCategoryKind.EXPENSE,hierarchyRole=CategoryHierarchyRole.CHILD,parentCategoryId=parent.id).toMutation(owner,null,parent,device,now).record
        val incomeParent=CategoryDraft(id=id(40),name="Income",kind=TransactionCategoryKind.INCOME,hierarchyRole=CategoryHierarchyRole.PARENT).toMutation(owner,null,null,device,now).record
        val incomeChild=CategoryDraft(id=id(41),name="Income child",kind=TransactionCategoryKind.INCOME,hierarchyRole=CategoryHierarchyRole.CHILD,parentCategoryId=incomeParent.id).toMutation(owner,null,incomeParent,device,now).record
        val posting=CloudRecord(CloudEntity.INVESTMENT_POSTING.table,id(10),owner.value,buildJsonObject {
            put("id",id(10));put("user_id",owner.value);put("created_at",now);put("updated_at",now);put("deleted_at",JsonNull);put("sync_version",0L)
            put("event_id",id(11));put("ledger_transaction_id",id(11));put("wallet_id",id(1));put("role_raw_value","cashAccrual");put("cash_bucket_raw_value","booked");put("cash_origin_raw_value","derived")
            put("amount_minor",60L);put("accounting_amount_minor",60L);put("currency_code","JPY");put("accounting_currency_code","JPY");put("occurred_at","2026-10-23T00:00:01Z")
        },now,null,0)
        val rows=listOf(wallet(),system,parent.toCloudRecord(),child.toCloudRecord(),incomeParent.toCloudRecord(),incomeChild.toCloudRecord(),posting)
        return TransactionInvestmentSaveSnapshot(owner,TransactionInvestmentSaveSnapshot.entities.associateWith{e->rows.filter{it.entity==e.table}})
    }
    private fun draft()=TransactionDraft(primaryKind=TransactionPrimaryKind.EXPENSE,title="Expense",amountMinor=70,occurredAt="2026-10-23T00:00:02Z",sourceWalletId=id(1),categoryId=id(31))
    private fun active():TransactionInvestmentSaveSnapshot {
        val s=base();val r=TransactionInvestmentSaveRequest(draft(),TransactionCreationIdentity(id(20),now),null,"Adjustment","JPY")
        val review=(runCatching{planTransactionInvestmentSave(s,r,device,now)}.exceptionOrNull() as InvestmentFundUsageConfirmationRequired).review
        return apply(s,planTransactionInvestmentSave(s,r.copy(consent=review.consent),device,now))
    }
    private fun apply(s:TransactionInvestmentSaveSnapshot,p:TransactionInvestmentSavePlan):TransactionInvestmentSaveSnapshot {
        val writes=p.mutations.map{it.first}
        return s.copy(recordsByEntity=s.recordsByEntity.mapValues{(e,rows)->rows.filter{r->writes.none{it.entity==e.table && it.id==r.id}}+writes.filter{it.entity==e.table}})
    }
    private fun record(s:TransactionInvestmentSaveSnapshot)=LedgerTransactionRecord.fromCloudRecord(s.recordsByEntity.getValue(CloudEntity.LEDGER_TRANSACTION).single{it.id==id(20)})
    private fun request(s:TransactionInvestmentSaveSnapshot,action:TransactionLifecycleAction)=TransactionInvestmentLifecycleRequest(record(s),action,operation,"JPY","Adjustment",null)
    private fun plan(s:TransactionInvestmentSaveSnapshot,r:TransactionInvestmentLifecycleRequest)=planTransactionInvestmentLifecycle(s,r,device,operation)
    private fun confirmed(s:TransactionInvestmentSaveSnapshot,r:TransactionInvestmentLifecycleRequest):TransactionInvestmentSavePlan {
        val review=(runCatching{plan(s,r)}.exceptionOrNull() as InvestmentFundUsageConfirmationRequired).review
        return plan(s,r.copy(consent=review.consent))
    }
    @Test fun archiveRestoresThirtyReservedMinorAndTombstonesOnlyTheDerivedConsumption() {
        val s=active();val r=request(s,TransactionLifecycleAction.ARCHIVE)
        val review=(runCatching{plan(s,r)}.exceptionOrNull() as InvestmentFundUsageConfirmationRequired).review
        assertEquals(30L,review.comparison.primaryChange!!.restoreMinor.longValueExact())
        val p=plan(s,r.copy(consent=review.consent))
        assertTrue(p.record.isArchived);assertEquals(operation,p.record.archivedAt);assertEquals(2,p.mutations.size)
        val derived=p.mutations.single{it.first.entity==CloudEntity.INVESTMENT_POSTING.table}
        assertEquals(MutationKind.DELETE,derived.second.kind);assertEquals(operation,derived.first.deletedAt)
        assertEquals(setOf(id(20),investmentLedgerIdentity(id(20),"cash-consumption-booked")),p.mutations.map{it.first.id}.toSet())
    }
    @Test fun restoreRequiresFreshThirtyConsentAndCompletedReplayDoesNotRewriteAnything() {
        val s=active();val archived=apply(s,confirmed(s,request(s,TransactionLifecycleAction.ARCHIVE)))
        val r=request(archived,TransactionLifecycleAction.RESTORE)
        val review=(runCatching{plan(archived,r)}.exceptionOrNull() as InvestmentFundUsageConfirmationRequired).review
        assertEquals(30L,review.comparison.proposed.usages.getValue(id(20)).investmentToUseMinor.longValueExact())
        val consent=r.copy(consent=review.consent);val p=plan(archived,consent);assertFalse(p.record.isArchived);assertNull(p.record.archivedAt)
        assertEquals(2,p.mutations.size);assertTrue(plan(apply(archived,p),consent).mutations.isEmpty())
    }
    @Test fun deleteArchivedPrimaryWritesOneDeleteAndNeverPhysicallyRemovesHistory() {
        val s=active();val archived=apply(s,confirmed(s,request(s,TransactionLifecycleAction.ARCHIVE)))
        val r=request(archived,TransactionLifecycleAction.DELETE);val p=plan(archived,r)
        assertEquals(operation,p.record.deletedAt);assertEquals(1,p.mutations.size);assertEquals(MutationKind.DELETE,p.mutations.single().second.kind)
        assertTrue(plan(apply(archived,p),r).mutations.isEmpty())
    }
    @Test fun ackVersionUnknownFieldsAndOriginalCreatorArePreserved() {
        val s=active();val old=record(s).copy(createdByUserId=id(77))
        val original=old.toCloudRecord().let{it.copy(payload=JsonObject(it.payload+("future_field" to JsonPrimitive("keep"))))}
        val initial=s.copy(recordsByEntity=s.recordsByEntity+(CloudEntity.LEDGER_TRANSACTION to listOf(original)))
        val r=request(initial,TransactionLifecycleAction.ARCHIVE)
        val ack=original.copy(syncVersion=9007199254740993L,updatedAt=operation,payload=JsonObject(original.payload+buildJsonObject{put("sync_version",9007199254740993L);put("updated_at",operation);put("last_modified_by_device_id",id(78))}))
        val current=initial.copy(recordsByEntity=initial.recordsByEntity+(CloudEntity.LEDGER_TRANSACTION to listOf(ack)))
        val p=confirmed(current,r);val primary=p.mutations.single{it.first.id==id(20)}
        assertEquals(9007199254740993L,primary.second.baseVersion);assertEquals(JsonPrimitive("keep"),primary.first.payload["future_field"])
        assertEquals(id(77),p.record.createdByUserId);assertEquals(old.createdAt,p.record.createdAt)
    }
    @Test fun changedExpectedForeignAndGeneratedIdentitiesCannotAuthorizeLifecycleWrites() {
        val s=active();val r=request(s,TransactionLifecycleAction.ARCHIVE)
        for(expected in listOf(r.expected.copy(title="Changed"),r.expected.copy(ownerUserId=id(99)),r.expected.copy(settlementRoleWireValue="investmentCapitalReturn"))) {
            val error=runCatching{plan(s,r.copy(expected=expected))}.exceptionOrNull()
            assertTrue(error.toString(),error is IllegalArgumentException)
        }
    }
    @Test fun activeDeleteAndRestoreCannotBypassArchiveAdmission() {
        val s=active()
        for(action in listOf(TransactionLifecycleAction.DELETE,TransactionLifecycleAction.RESTORE))assertTrue(runCatching{plan(s,request(s,action))}.isFailure)
    }
    @Test fun restoringAnExpenseRechecksExactPresentCashBeforeAnyFundWrite() {
        val s=active();val archived=apply(s,confirmed(s,request(s,TransactionLifecycleAction.ARCHIVE)))
        val changed=archived.copy(recordsByEntity=archived.recordsByEntity+(CloudEntity.LEDGER_WALLET to archived.recordsByEntity.getValue(CloudEntity.LEDGER_WALLET).map{if(it.id==id(1))it.copy(payload=JsonObject(it.payload+("opening_balance_minor" to JsonPrimitive(50L))))else it}))
        val error=runCatching{plan(changed,request(archived,TransactionLifecycleAction.RESTORE))}.exceptionOrNull()
        assertEquals(TransactionValidationError.INSUFFICIENT_WALLET_BALANCE,(error as? TransactionValidationException)?.reason)
    }
    @Test fun aPaidOccurrenceStillLocksArchiveAtTheLifecycleBoundary() {
        val s=active();val occurrence=CloudRecord(CloudEntity.DUE_OCCURRENCE_RECORD.table,id(71),owner.value,buildJsonObject{put("id",id(71));put("user_id",owner.value);put("sync_version",0);put("deleted_at",JsonNull);put("source_kind_raw_value","creditCard");put("source_id",id(1));put("status_raw_value","paid");put("linked_transaction_id",id(20))},now,null,0)
        val input=s.copy(recordsByEntity=s.recordsByEntity+(CloudEntity.DUE_OCCURRENCE_RECORD to listOf(occurrence)))
        val error=runCatching{plan(input,request(s,TransactionLifecycleAction.ARCHIVE))}.exceptionOrNull()
        assertEquals(TransactionValidationError.PAID_CREDIT_CARD_STATEMENT,(error as? TransactionValidationException)?.reason)
    }
    @Test fun archivingIncomeShowsTheReservedUseItCreatesInALaterExpense() {
        val original=record(active())
        val income=original.copy(id=id(21),primaryKindWireValue="income",amountMinor=30,categoryId=id(41),title="Income",occurredAt="2026-10-23T00:00:01.500Z")
        val s=base().let{it.copy(recordsByEntity=it.recordsByEntity+(CloudEntity.LEDGER_TRANSACTION to listOf(original.toCloudRecord(),income.toCloudRecord())))}
        val r=TransactionInvestmentLifecycleRequest(income,TransactionLifecycleAction.ARCHIVE,operation,"JPY","Adjustment",null)
        val review=(runCatching{plan(s,r)}.exceptionOrNull() as InvestmentFundUsageConfirmationRequired).review
        assertEquals(30L,review.comparison.proposed.usages.getValue(id(20)).investmentToUseMinor.longValueExact())
        val p=plan(s,r.copy(consent=review.consent))
        assertEquals(setOf(id(21),investmentLedgerIdentity(id(20),"cash-consumption-booked")),p.mutations.map{it.first.id}.toSet())
    }
    @Test fun aPartialRestoreCannotUseKnownResultProofToRepairMissingDerivedRows() {
        val s=active();val archived=apply(s,confirmed(s,request(s,TransactionLifecycleAction.ARCHIVE)))
        val r=request(archived,TransactionLifecycleAction.RESTORE);val p=confirmed(archived,r)
        val partial=apply(archived,p.copy(mutations=p.mutations.filter{it.first.entity==CloudEntity.LEDGER_TRANSACTION.table}))
        val error=runCatching{plan(partial,r)}.exceptionOrNull()
        assertEquals(InvestmentFundUsageError.EVENT_CONFLICT,(error as? InvestmentFundUsageException)?.reason)
    }
    @Test fun sourceChangeRequiresNewConsentRatherThanAnAutomaticArchiveRetry() {
        val s=active();val r=request(s,TransactionLifecycleAction.ARCHIVE)
        val review=(runCatching{plan(s,r)}.exceptionOrNull() as InvestmentFundUsageConfirmationRequired).review
        val current=s.copy(recordsByEntity=s.recordsByEntity+(CloudEntity.LEDGER_WALLET to s.recordsByEntity.getValue(CloudEntity.LEDGER_WALLET).map{
            if(it.id==id(1))it.copy(payload=JsonObject(it.payload+("opening_balance_minor" to JsonPrimitive(101L))))else it}))
        val error=runCatching{plan(current,r.copy(consent=review.consent))}.exceptionOrNull()
        assertEquals(InvestmentFundUsageError.STALE_CONSENT,(error as? InvestmentFundUsageException)?.reason)
    }
    @Test fun archivingKeepsManualConsumptionAndRestoreCannotOverwriteItsCanonicalIdentity() {
        val s=active();val manual=s.copy(recordsByEntity=s.recordsByEntity+(CloudEntity.INVESTMENT_POSTING to s.recordsByEntity.getValue(CloudEntity.INVESTMENT_POSTING).map{
            if(it.id==investmentLedgerIdentity(id(20),"cash-consumption-booked"))it.copy(payload=JsonObject(it.payload+("cash_origin_raw_value" to JsonPrimitive("manual"))))else it}))
        val archive=confirmed(manual,request(manual,TransactionLifecycleAction.ARCHIVE))
        assertTrue(archive.mutations.none{it.first.entity==CloudEntity.INVESTMENT_POSTING.table})
        val archived=apply(manual,archive);val error=runCatching{plan(archived,request(archived,TransactionLifecycleAction.RESTORE))}.exceptionOrNull()
        assertEquals(InvestmentFundUsageError.EVENT_CONFLICT,(error as? InvestmentFundUsageException)?.reason)
    }
    @Test fun aCompletedDeleteWithContradictoryEnvelopeCannotBecomeKnownSuccess() {
        val s=active();val archived=apply(s,confirmed(s,request(s,TransactionLifecycleAction.ARCHIVE)))
        val r=request(archived,TransactionLifecycleAction.DELETE);val deleted=apply(archived,plan(archived,r))
        val broken=deleted.copy(recordsByEntity=deleted.recordsByEntity+(CloudEntity.LEDGER_TRANSACTION to deleted.recordsByEntity.getValue(CloudEntity.LEDGER_TRANSACTION).map{it.copy(deletedAt=null)}))
        assertTrue(runCatching{plan(broken,r)}.isFailure)
    }
    @Test fun absentLegacyOptionalNullsDoNotPreventArchivingOrLoseRawFields() {
        val s=active().let{it.copy(recordsByEntity=it.recordsByEntity+(CloudEntity.LEDGER_TRANSACTION to it.recordsByEntity.getValue(CloudEntity.LEDGER_TRANSACTION).map{r->
            r.copy(payload=JsonObject(r.payload.filterKeys{key->key!="note" && key!="normalized_counterparty_key"}+("future_field" to JsonPrimitive("keep"))))}))}
        val p=confirmed(s,request(s,TransactionLifecycleAction.ARCHIVE));val primary=p.mutations.single{it.first.id==id(20)}.first
        assertEquals(JsonPrimitive("keep"),primary.payload["future_field"]);assertTrue(p.record.isArchived)
    }
    @Test fun restoringCannotReenableAnExpenseWhoseSourceWalletWasDeleted() {
        val s=active();val archived=apply(s,confirmed(s,request(s,TransactionLifecycleAction.ARCHIVE)))
        val changed=archived.copy(recordsByEntity=archived.recordsByEntity+(CloudEntity.LEDGER_WALLET to archived.recordsByEntity.getValue(CloudEntity.LEDGER_WALLET).map{
            if(it.id==id(1))it.copy(deletedAt=operation,payload=JsonObject(it.payload+("deleted_at" to JsonPrimitive(operation))))else it}))
        val error=runCatching{plan(changed,request(archived,TransactionLifecycleAction.RESTORE))}.exceptionOrNull()
        assertEquals(TransactionValidationError.INVALID_SOURCE_WALLET,(error as? TransactionValidationException)?.reason)
    }
    @Test fun restoringCardChargeRechecksCurrentDebtAgainstExactCreditLimit() {
        val existing=record(active()).copy(isArchived=true,archivedAt=operation)
        val other=existing.copy(id=id(22),amountMinor=90,isArchived=false,archivedAt=null)
        val card=wallet().copy(payload=JsonObject(wallet().payload+buildJsonObject{put("kind_raw_value","creditCard");put("opening_balance_minor",0L)}))
        val profile=CreditCardProfileRecord(id(60),owner.value,"Issuer","visa","1234",100,10,26,null,id(1),null,true,now,now,null,0,device).toCloudRecord()
        val s=base().let{it.copy(recordsByEntity=it.recordsByEntity+mapOf(
            CloudEntity.LEDGER_WALLET to (it.recordsByEntity.getValue(CloudEntity.LEDGER_WALLET).filterNot{w->w.id==id(1)}+card),
            CloudEntity.LEDGER_TRANSACTION to listOf(existing.toCloudRecord(),other.toCloudRecord()),CloudEntity.CREDIT_CARD_PROFILE to listOf(profile),CloudEntity.INVESTMENT_POSTING to emptyList()))}
        val error=runCatching{plan(s,request(s,TransactionLifecycleAction.RESTORE))}.exceptionOrNull()
        assertEquals(TransactionValidationError.CREDIT_LIMIT_EXCEEDED,(error as? TransactionValidationException)?.reason)
    }
    @Test fun duplicateCardPaymentRestoreUsesTheSourceMonthRuleWithoutDependingOnItsTitle() {
        val archived=record(active()).copy(primaryKindWireValue="transfer",transferSubtypeWireValue="internalTransfer",categoryId=null,
            title="Transfer",amountMinor=30,destinationWalletId=id(2),destinationCurrencyCode="JPY",destinationAmountMinor=30,
            isArchived=true,archivedAt=operation,reportingCurrencyCode=null,reportingAmountMinor=null)
        val other=archived.copy(id=id(22),isArchived=false,archivedAt=null)
        val card=wallet().copy(id=id(2),payload=JsonObject(wallet().payload+buildJsonObject{put("id",id(2));put("kind_raw_value","creditCard");put("opening_balance_minor",0L)}))
        fun input(payment:LedgerTransactionRecord)=base().let{it.copy(recordsByEntity=it.recordsByEntity+mapOf(
            CloudEntity.LEDGER_WALLET to (it.recordsByEntity.getValue(CloudEntity.LEDGER_WALLET)+card),
            CloudEntity.LEDGER_TRANSACTION to listOf(archived.toCloudRecord(),payment.toCloudRecord())))}
        val sameMonth=input(other);val error=runCatching{plan(sameMonth,request(sameMonth,TransactionLifecycleAction.RESTORE))}.exceptionOrNull()
        assertEquals(TransactionValidationError.PAID_CREDIT_CARD_STATEMENT,(error as? TransactionValidationException)?.reason)
        val anotherMonth=input(other.copy(occurredAt="2026-09-23T00:00:02Z"))
        assertTrue(runCatching{plan(anotherMonth,request(anotherMonth,TransactionLifecycleAction.RESTORE))}.exceptionOrNull() is InvestmentFundUsageConfirmationRequired)
    }
    @Test fun restoringForeignReservedUseCannotBypassTheApprovedAccountingCurrencyRule() {
        val archived=record(active()).copy(amountMinor=70_000,sourceCurrencyCode="VND",reportingCurrencyCode="VND",reportingAmountMinor=70_000,isArchived=true,archivedAt=operation)
        val s=base().let{it.copy(recordsByEntity=it.recordsByEntity+mapOf(
            CloudEntity.LEDGER_TRANSACTION to listOf(archived.toCloudRecord()),
            CloudEntity.LEDGER_WALLET to it.recordsByEntity.getValue(CloudEntity.LEDGER_WALLET).map{w->if(w.id==id(1))w.copy(payload=JsonObject(w.payload+buildJsonObject{put("opening_balance_minor",100_000L);put("currency_code","VND")}))else w},
            CloudEntity.INVESTMENT_POSTING to it.recordsByEntity.getValue(CloudEntity.INVESTMENT_POSTING).map{p->p.copy(payload=JsonObject(p.payload+buildJsonObject{put("currency_code","VND");put("amount_minor",40_000L);put("accounting_amount_minor",2L)}))}))}
        val error=runCatching{plan(s,request(s,TransactionLifecycleAction.RESTORE))}.exceptionOrNull()
        assertEquals(InvestmentFundUsageError.CURRENCY_MISMATCH,(error as? InvestmentFundUsageException)?.reason)
    }
    @Test fun anImportedMissingCurrencyStillUsesItsWalletUnitsAndRestoresWithoutRewritingHistory() {
        val s=active().let{it.copy(recordsByEntity=it.recordsByEntity+(CloudEntity.LEDGER_TRANSACTION to it.recordsByEntity.getValue(CloudEntity.LEDGER_TRANSACTION).map{raw->
            raw.copy(payload=JsonObject(raw.payload+buildJsonObject{put("source_currency_code",JsonNull);put("reporting_currency_code",JsonNull);put("reporting_amount_minor",JsonNull)}))}))}
        val archived=apply(s,confirmed(s,request(s,TransactionLifecycleAction.ARCHIVE)))
        val restored=confirmed(archived,request(archived,TransactionLifecycleAction.RESTORE))
        assertFalse(restored.record.isArchived);assertNull(restored.record.sourceCurrencyCode)
        assertEquals(30L,restored.mutations.single{it.first.entity==CloudEntity.INVESTMENT_POSTING.table}.first.payload.financeRawLong("amount_minor")!!.let{-it})
    }
    @Test fun importingLowercaseCurrencyDoesNotTurnTheSameWalletUnitsIntoAConflict() {
        val s=active().let{it.copy(recordsByEntity=it.recordsByEntity+(CloudEntity.LEDGER_TRANSACTION to it.recordsByEntity.getValue(CloudEntity.LEDGER_TRANSACTION).map{raw->
            raw.copy(payload=JsonObject(raw.payload+("source_currency_code" to JsonPrimitive("jpy"))))}))}
        val archived=apply(s,confirmed(s,request(s,TransactionLifecycleAction.ARCHIVE)))
        val restored=confirmed(archived,request(archived,TransactionLifecycleAction.RESTORE))
        assertFalse(restored.record.isArchived);assertEquals("jpy",restored.record.sourceCurrencyCode)
    }
}
