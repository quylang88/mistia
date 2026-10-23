package vn.com.quyln.mistia.core.model

import java.time.*
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class BillInvestmentMoneyPlanTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val device="44444444-4444-4444-8444-444444444444"
    private val now="2026-10-23T00:00:00Z"
    private val at="2026-10-23T00:01:00Z"
    private val later="2026-10-23T00:02:00Z"
    private val month=YearMonth.of(2026,10)
    private val zone=ZoneId.of("Asia/Tokyo")
    private fun id(n:Int)=java.util.UUID(0,n.toLong()).toString()
    private val catalog=SystemCategoryCatalog.parse("""[{"id":"home","kind":"expense","active":true,"icon":"mistia.category.parent.expense.home_bills","fallbackIcon":"house.fill","color":"#FF8A4C","translations":{"vi":"Nhà","en":"Home","ja":"住まい"},"aliases":[],"children":[{"id":"internet","active":true,"icon":"mistia.category.expense.home_bills.internet","fallbackIcon":"wifi","color":"#5B7BFF","translations":{"vi":"Mạng","en":"Internet","ja":"インターネット"},"aliases":[]}]}]""")
    private fun source(amount:Long=70,opening:Long=100,reserve:Long=60):BillMoneySnapshot {
        val parent=catalog.definitions.single{it.parentKey==null}.seedRecord(owner,null,device,now)
        val child=catalog.definitions.single{it.parentKey!=null}.seedRecord(owner,parent.id,device,now)
        val wallet=WalletDraft(id=id(1),name="Cash",kind=WalletKind.CASH,currencyCode="JPY",openingBalanceMinor=opening).toMutation(owner,null,device,now).record
        val bill=RecurringBillDraft("Internet",child.id,amount,wallet.id,"JPY",id=id(50),paymentStartDay=1,zoneId=zone).toBillRecord(owner,child,null,device,now).toCloudRecord()
        val posting=CloudRecord(CloudEntity.INVESTMENT_POSTING.table,id(10),owner.value,buildJsonObject {
            put("id",id(10));put("user_id",owner.value);put("sync_version",0L);put("deleted_at",JsonNull);put("created_at",now);put("updated_at",now)
            put("event_id",id(11));put("ledger_transaction_id",id(11));put("wallet_id",id(1));put("role_raw_value","cashAccrual");put("cash_bucket_raw_value","booked");put("cash_origin_raw_value","derived")
            put("amount_minor",reserve);put("accounting_amount_minor",reserve);put("currency_code","JPY");put("accounting_currency_code","JPY");put("occurred_at","2026-10-23T00:00:01Z")
        },now,null,0)
        val rows=listOf(wallet,parent.toCloudRecord(),child.toCloudRecord(),bill,posting)
        return BillMoneySnapshot(owner,bill,month,CloudEntity.entries.associateWith{e->rows.filter{it.entity==e.table}})
    }
    private fun request(s:BillMoneySnapshot)=BillPaymentRequest(RecordId(s.bill.id),month,RecordId(id(1)),RecurringBillPlanRecord.fromCloudRecord(s.bill).amountMinor,
        expectedBill=RecurringBillPlanRecord.fromCloudRecord(s.bill),investment=BillInvestmentOperationContext(TransactionCreationIdentity(id(20),at),"JPY","Adjustment"))
    private fun plan(s:BillMoneySnapshot,r:BillPaymentRequest,clock:String=at)=planBillInvestmentMoney(s,BillInvestmentMoneyOperation.Pay(r),catalog,device,clock,zone)
    private fun confirmed(s:BillMoneySnapshot,r:BillPaymentRequest):BillInvestmentMoneyPlan {
        val review=(runCatching{plan(s,r)}.exceptionOrNull() as InvestmentFundUsageConfirmationRequired).review
        return plan(s,r.copy(investment=r.investment!!.copy(consent=review.consent)))
    }
    private fun apply(s:BillMoneySnapshot,p:BillInvestmentMoneyPlan):BillMoneySnapshot {
        val writes=p.mutations.map{it.first}
        return s.copy(recordsByEntity=s.recordsByEntity.mapValues{(e,rows)->rows.filter{old->writes.none{it.entity==e.table && it.id==old.id}}+writes.filter{it.entity==e.table}})
    }
    @Test fun seventyBillRequiresThirtyReservedConsentThenPlansOneExpenseCycleAndConsumption() {
        val s=source();val r=request(s)
        val review=(runCatching{plan(s,r)}.exceptionOrNull() as InvestmentFundUsageConfirmationRequired).review
        assertEquals(30L,review.comparison.proposed.usages.getValue(id(20)).investmentToUseMinor.longValueExact())
        val p=plan(s,r.copy(investment=r.investment!!.copy(consent=review.consent)));val paid=p.payment!!
        assertEquals(id(20),paid.transaction.id);assertEquals(at,paid.transaction.createdAt);assertEquals(70L,paid.transaction.amountMinor)
        assertEquals(id(20),paid.occurrences.single().linkedTransactionId);assertEquals(70L,paid.occurrences.single().amountMinorSnapshot)
        assertEquals(3,p.mutations.size);assertEquals(-30L,p.mutations.single{it.first.entity==CloudEntity.INVESTMENT_POSTING.table}.first.payload.financeRawLong("amount_minor"))
    }
    @Test fun completedPaymentAfterAckProvesEverythingWithoutSpendingAgainOrRefreshingConsent() {
        val s=source();val r=request(s);val p=confirmed(s,r);val saved=apply(s,p)
        val acknowledged=saved.copy(recordsByEntity=saved.recordsByEntity.mapValues{(_,rows)->rows.map{row->row.copy(updatedAt=later,syncVersion=9007199254740993L,
            payload=JsonObject(row.payload+buildJsonObject{put("updated_at",later);put("sync_version",9007199254740993L);put("last_modified_by_device_id",id(77))}))}})
        val coherent=acknowledged.copy(bill=acknowledged.recordsByEntity.getValue(CloudEntity.RECURRING_BILL_PLAN).single())
        val retry=plan(coherent,r,later)
        assertTrue(retry.mutations.isEmpty());assertEquals(id(20),retry.payment!!.transaction.id);assertEquals(9007199254740993L,retry.payment.transaction.syncVersion)
    }
    @Test fun completePrimaryAndCycleWithMissingDerivedResultCannotBeRepairedAsACompletedRetry() {
        val s=source();val r=request(s);val paid=apply(s,confirmed(s,r))
        val partial=paid.copy(recordsByEntity=paid.recordsByEntity+(CloudEntity.INVESTMENT_POSTING to paid.recordsByEntity.getValue(CloudEntity.INVESTMENT_POSTING).filterNot{it.id==investmentLedgerIdentity(id(20),"cash-consumption-booked")}))
        val error=runCatching{plan(partial,r,later)}.exceptionOrNull()
        assertEquals(InvestmentFundUsageError.EVENT_CONFLICT,(error as? InvestmentFundUsageException)?.reason)
    }
    @Test fun ordinaryMoneyInAReservedWalletDoesNotNeedFundConsentOrCreateConsumption() {
        val s=source(amount=30);val p=plan(s,request(s))
        assertEquals(30L,p.payment!!.transaction.amountMinor);assertEquals(2,p.mutations.size);assertTrue(p.mutations.none{it.first.entity==CloudEntity.INVESTMENT_POSTING.table})
    }
    @Test fun exactPresentAffordabilityRejectsPaymentBeforeAnyDerivedAdjustment() {
        val s=source(opening=50);val error=runCatching{plan(s,request(s))}.exceptionOrNull()
        assertEquals(TransactionValidationError.INSUFFICIENT_WALLET_BALANCE,(error as? TransactionValidationException)?.reason)
    }
    @Test fun unknownCycleStatusReturnsExplicitUnsupportedStateBeforePlanning() {
        val s=source(amount=30)
        val marker=DueOccurrenceRecord(id(70),owner.value,"recurringBill",s.bill.id,month.toString(),at,30,"futureStatus",null,null,now,now,null,0,device).toCloudRecord()
        val bad=s.copy(recordsByEntity=s.recordsByEntity+(CloudEntity.DUE_OCCURRENCE_RECORD to listOf(marker)))
        val error=runCatching{plan(bad,request(s))}.exceptionOrNull()
        assertEquals(BillPaymentError.UNSUPPORTED_LINKED_STATE,(error as? BillPaymentException)?.reason)
    }
    private fun foreign(amount:Long):BillMoneySnapshot {
        val s=source(amount=amount,opening=100_000,reserve=2)
        val records=s.recordsByEntity.mapValues{(e,rows)->rows.map{row->when(e) {
            CloudEntity.LEDGER_WALLET->row.copy(payload=JsonObject(row.payload+("currency_code" to JsonPrimitive("VND"))))
            CloudEntity.RECURRING_BILL_PLAN->row.copy(payload=JsonObject(row.payload+("currency_code" to JsonPrimitive("VND"))))
            CloudEntity.INVESTMENT_POSTING->row.copy(payload=JsonObject(row.payload+buildJsonObject{put("currency_code","VND");put("amount_minor",40_000L)}))
            else->row
        }}}
        return s.copy(recordsByEntity=records,bill=records.getValue(CloudEntity.RECURRING_BILL_PLAN).single())
    }
    @Test fun foreignOrdinaryMoneyStillPaysWithoutConvertingAccountingMinor() {
        val s=foreign(50_000);val p=plan(s,request(s))
        assertEquals("VND",p.payment!!.transaction.sourceCurrencyCode);assertEquals(50_000L,p.payment.transaction.amountMinor);assertEquals(2,p.mutations.size)
    }
    @Test fun foreignReservedMoneyReturnsTheApprovedCurrencyError() {
        val s=foreign(70_000);val error=runCatching{plan(s,request(s))}.exceptionOrNull()
        assertEquals(InvestmentFundUsageError.CURRENCY_MISMATCH,(error as? InvestmentFundUsageException)?.reason)
    }
    @Test fun categoryBootstrapUsesFrozenOperationTimeAcrossFundConsentAndLaterSave() {
        val s=source().let{it.copy(recordsByEntity=it.recordsByEntity+(CloudEntity.TRANSACTION_CATEGORY to emptyList()))};val r=request(s)
        val review=(runCatching{plan(s,r)}.exceptionOrNull() as InvestmentFundUsageConfirmationRequired).review
        val p=plan(s,r.copy(investment=r.investment!!.copy(consent=review.consent)),later)
        assertEquals(5,p.mutations.size);assertTrue(p.mutations.filter{it.first.entity==CloudEntity.TRANSACTION_CATEGORY.table}.all{it.first.payload.financeRawString("created_at")==at})
    }
    @Test fun aChangedVisibleBillCannotUseTheSameFundOperation() {
        val s=source();val r=request(s);val b=RecurringBillPlanRecord.fromCloudRecord(s.bill).copy(amountMinor=80).toCloudRecord()
        val changed=s.copy(bill=b,recordsByEntity=s.recordsByEntity+(CloudEntity.RECURRING_BILL_PLAN to listOf(b)))
        val error=runCatching{plan(changed,r)}.exceptionOrNull();assertEquals(BillPaymentError.SOURCE_CHANGED,(error as? BillPaymentException)?.reason)
    }
    @Test fun changingAHiddenWalletBalanceInvalidatesTheFrozenFundConsent() {
        val s=source();val r=request(s);val review=(runCatching{plan(s,r)}.exceptionOrNull() as InvestmentFundUsageConfirmationRequired).review
        val changed=s.copy(recordsByEntity=s.recordsByEntity+(CloudEntity.LEDGER_WALLET to s.recordsByEntity.getValue(CloudEntity.LEDGER_WALLET).map{it.copy(payload=JsonObject(it.payload+("opening_balance_minor" to JsonPrimitive(101L))))}))
        val error=runCatching{plan(changed,r.copy(investment=r.investment!!.copy(consent=review.consent)))}.exceptionOrNull()
        assertEquals(InvestmentFundUsageError.STALE_CONSENT,(error as? InvestmentFundUsageException)?.reason)
    }
    private fun undoRequest(s:BillMoneySnapshot)=BillInvestmentUndoRequest(RecurringBillPlanRecord.fromCloudRecord(s.bill),month,70,id(20),BillInvestmentOperationContext(TransactionCreationIdentity(id(60),later),"JPY","Adjustment"))
    private fun undo(s:BillMoneySnapshot,r:BillInvestmentUndoRequest):BillInvestmentMoneyPlan=planBillInvestmentMoney(s,BillInvestmentMoneyOperation.Undo(r),catalog,device,later,zone)
    private fun confirmedUndo(s:BillMoneySnapshot):BillInvestmentMoneyPlan {
        val r=undoRequest(s);val review=(runCatching{undo(s,r)}.exceptionOrNull() as InvestmentFundUsageConfirmationRequired).review
        return undo(s,r.copy(investment=r.investment.copy(consent=review.consent)))
    }
    @Test fun aCompleteUndoIsNoWriteOnRetryAndMissingDerivedDeletionIsHeld() {
        val s=source();val paid=apply(s,confirmed(s,request(s)));val undone=apply(paid,confirmedUndo(paid))
        assertTrue(undo(undone,undoRequest(s)).mutations.isEmpty())
        val partial=undone.copy(recordsByEntity=undone.recordsByEntity+(CloudEntity.INVESTMENT_POSTING to paid.recordsByEntity.getValue(CloudEntity.INVESTMENT_POSTING)))
        assertEquals(InvestmentFundUsageError.EVENT_CONFLICT,(runCatching{undo(partial,undoRequest(s))}.exceptionOrNull() as? InvestmentFundUsageException)?.reason)
    }
    @Test fun aContradictoryTombstoneBodyCannotBeAcceptedAsCompletedUndo() {
        val s=source();val paid=apply(s,confirmed(s,request(s)));val undone=apply(paid,confirmedUndo(paid))
        val bad=undone.copy(recordsByEntity=undone.recordsByEntity+(CloudEntity.LEDGER_TRANSACTION to undone.recordsByEntity.getValue(CloudEntity.LEDGER_TRANSACTION).map{it.copy(payload=JsonObject(it.payload+("deleted_at" to JsonNull)))}))
        assertTrue(runCatching{undo(bad,undoRequest(s))}.isFailure)
    }
    @Test fun repaymentReusesTheOriginalExpenseAndCycleWithoutLosingUnknownFields() {
        val s=source();val paid=apply(s,confirmed(s,request(s))).let{it.copy(recordsByEntity=it.recordsByEntity.mapValues{(e,rows)->if(e==CloudEntity.LEDGER_TRANSACTION)rows.map{row->row.copy(payload=JsonObject(row.payload+("future_field" to JsonPrimitive("preserve"))))}else rows})}
        val undone=apply(paid,confirmedUndo(paid));val retry=request(s).copy(investment=BillInvestmentOperationContext(TransactionCreationIdentity(id(21),"2026-10-23T00:03:00Z"),"JPY","Adjustment"))
        val review=(runCatching{plan(undone,retry,"2026-10-23T00:03:00Z")}.exceptionOrNull() as InvestmentFundUsageConfirmationRequired).review
        val p=plan(undone,retry.copy(investment=retry.investment!!.copy(consent=review.consent)),"2026-10-23T00:03:00Z")
        assertEquals(id(20),p.payment!!.transaction.id);assertEquals(at,p.payment.transaction.createdAt)
        assertEquals(paid.recordsByEntity.getValue(CloudEntity.DUE_OCCURRENCE_RECORD).map{it.id},p.payment.occurrences.map{it.id})
        assertEquals(JsonPrimitive("preserve"),p.mutations.single{it.first.entity==CloudEntity.LEDGER_TRANSACTION.table}.first.payload["future_field"])
    }
    @Test fun undoRecalculatesTheDownstreamExpenseRatherThanOnlyTheSelectedConsumption() {
        val s=source();val paid=apply(s,confirmed(s,request(s)))
        val ordinary=TransactionInvestmentSaveSnapshot(owner,paid.recordsByEntity.filterKeys{it in TransactionInvestmentSaveSnapshot.entities})
        val draft=TransactionDraft(primaryKind=TransactionPrimaryKind.EXPENSE,title="Later expense",amountMinor=20,occurredAt="2026-10-23T00:01:30Z",sourceWalletId=id(1),categoryId=RecurringBillPlanRecord.fromCloudRecord(s.bill).categoryId)
        val request=TransactionInvestmentSaveRequest(draft,TransactionCreationIdentity(id(22),"2026-10-23T00:01:30Z"),null,"Adjustment","JPY")
        val review=(runCatching{planTransactionInvestmentSave(ordinary,request,device,later)}.exceptionOrNull() as InvestmentFundUsageConfirmationRequired).review
        val laterExpense=planTransactionInvestmentSave(ordinary,request.copy(consent=review.consent),device,later)
        val withLater=apply(paid,BillInvestmentMoneyPlan(null,laterExpense.mutations));val undo=undoRequest(s)
        val restore=(runCatching{undo(withLater,undo)}.exceptionOrNull() as InvestmentFundUsageConfirmationRequired).review
        assertEquals(50L,restore.comparison.primaryChange!!.restoreMinor.longValueExact())
        val p=undo(withLater,undo.copy(investment=undo.investment.copy(consent=restore.consent)))
        assertEquals(4,p.mutations.size);assertEquals(2,p.mutations.count{it.first.entity==CloudEntity.INVESTMENT_POSTING.table && it.second.kind==MutationKind.DELETE})
    }
    @Test fun aNewOrdinaryBillCannotSilentlyRepairPreExistingDerivedMoneyRows() {
        val original=source();val paid=apply(original,confirmed(original,request(original)))
        val other=RecurringBillPlanRecord.fromCloudRecord(original.bill).copy(id=id(51),name="Other bill",amountMinor=30).toCloudRecord()
        val records=paid.recordsByEntity+(CloudEntity.RECURRING_BILL_PLAN to (paid.recordsByEntity.getValue(CloudEntity.RECURRING_BILL_PLAN)+other))+
            (CloudEntity.LEDGER_WALLET to paid.recordsByEntity.getValue(CloudEntity.LEDGER_WALLET).map{it.copy(payload=JsonObject(it.payload+("opening_balance_minor" to JsonPrimitive(200L))))})
        val current=paid.copy(bill=other,recordsByEntity=records)
        val r=request(current).copy(investment=BillInvestmentOperationContext(TransactionCreationIdentity(id(21),"2026-10-23T00:03:00Z"),"JPY","Adjustment"))
        val error=runCatching{plan(current,r,"2026-10-23T00:03:00Z")}.exceptionOrNull()
        assertEquals(InvestmentFundUsageError.EVENT_CONFLICT,(error as? InvestmentFundUsageException)?.reason)
    }
    @Test fun anOldPaymentIntentCannotReviveTheExpenseAfterASeparateExplicitUndo() {
        val s=source();val r=request(s);val paid=apply(s,confirmed(s,r));val undone=apply(paid,confirmedUndo(paid))
        val error=runCatching{plan(undone,r,"2026-10-23T00:03:00Z")}.exceptionOrNull()
        assertEquals(BillPaymentError.SOURCE_CHANGED,(error as? BillPaymentException)?.reason)
    }
    @Test fun repaymentMetadataAcknowledgementDoesNotChangeTheApprovedFundAuthorization() {
        val s=source();val paid=apply(s,confirmed(s,request(s)));val undone=apply(paid,confirmedUndo(paid))
        val r=request(s).copy(investment=BillInvestmentOperationContext(TransactionCreationIdentity(id(21),"2026-10-23T00:03:00Z"),"JPY","Adjustment"))
        val review=(runCatching{plan(undone,r,"2026-10-23T00:03:00Z")}.exceptionOrNull() as InvestmentFundUsageConfirmationRequired).review
        val records=undone.recordsByEntity.mapValues{(_,rows)->rows.map{row->row.copy(updatedAt="2026-10-23T00:05:00Z",syncVersion=9007199254740993L,
            payload=JsonObject(row.payload+buildJsonObject{put("updated_at","2026-10-23T00:05:00Z");put("sync_version",9007199254740993L);put("last_modified_by_device_id",id(77))}))}}
        val acknowledged=undone.copy(recordsByEntity=records,bill=records.getValue(CloudEntity.RECURRING_BILL_PLAN).single())
        val p=plan(acknowledged,r.copy(investment=r.investment!!.copy(consent=review.consent)),"2026-10-23T00:06:00Z")
        assertEquals(id(20),p.payment!!.transaction.id);assertEquals(9007199254740993L,p.payment.transaction.syncVersion)
        assertEquals("2026-10-23T00:03:00Z",p.payment.transaction.occurredAt);assertEquals(3,p.mutations.size)
    }
    private fun automaticSource(amount:Long):BillMoneySnapshot {
        val s=source(amount=amount);val bill=RecurringBillPlanRecord.fromCloudRecord(s.bill).copy(autoPayEnabled=true,autoPayDay=23,paymentStartDay=23,dueDay=23).toCloudRecord()
        return s.copy(bill=bill,recordsByEntity=s.recordsByEntity+(CloudEntity.RECURRING_BILL_PLAN to listOf(bill)))
    }
    private fun automaticRequest(s:BillMoneySnapshot)=request(s).copy(walletId=null,amountMinorOverride=null,automatic=true)
    @Test fun automaticOrdinaryMoneyWithInvestmentPostingsKeepsItsLocalizedPaymentTitle() {
        val s=automaticSource(30);val text=BillAutomaticPaymentText("Auto paid Internet","Done","Paid",emitNotification=false)
        val p=planBillInvestmentMoney(s,BillInvestmentMoneyOperation.Pay(automaticRequest(s),text),catalog,device,at,zone)
        assertEquals("Auto paid Internet",p.payment!!.transaction.title);assertEquals(2,p.mutations.size)
        assertTrue(p.mutations.none{it.first.entity==CloudEntity.INVESTMENT_POSTING.table})
    }
    @Test fun automaticPaymentNeedingReservedMoneyStaysPaused() {
        val s=automaticSource(70)
        val error=runCatching{planBillInvestmentMoney(s,BillInvestmentMoneyOperation.Pay(automaticRequest(s)),catalog,device,at,zone)}.exceptionOrNull()
        assertEquals(BillPaymentError.INVESTMENT_USAGE_UNAVAILABLE,(error as? BillPaymentException)?.reason)
    }
    @Test fun aManualRequestCannotInjectAnAutomaticPaymentPresentation() {
        val s=automaticSource(30)
        val error=runCatching{planBillInvestmentMoney(s,BillInvestmentMoneyOperation.Pay(request(s),BillAutomaticPaymentText("Injected automatic title","Done","Paid")),catalog,device,at,zone)}.exceptionOrNull()
        assertEquals(BillPaymentError.INVALID_AUTO_PAY_OVERRIDE,(error as? BillPaymentException)?.reason)
    }
    @Test fun completedUndoRejectsChangedMarkerAmountInsteadOfClaimingSuccess() {
        val s=source();val paid=apply(s,confirmed(s,request(s)));val undone=apply(paid,confirmedUndo(paid))
        val bad=undone.copy(recordsByEntity=undone.recordsByEntity+(CloudEntity.DUE_OCCURRENCE_RECORD to undone.recordsByEntity.getValue(CloudEntity.DUE_OCCURRENCE_RECORD).map{
            it.copy(payload=JsonObject(it.payload+("amount_minor_snapshot" to JsonPrimitive(99L))))}))
        assertTrue(runCatching{undo(bad,undoRequest(s))}.isFailure)
    }
    @Test fun completedUndoCannotIgnoreARemainingPendingDuplicateForTheSameCycle() {
        val s=source();val paid=apply(s,confirmed(s,request(s)));val undone=apply(paid,confirmedUndo(paid))
        val marker=DueOccurrenceRecord(id(73),owner.value,"recurringBill",s.bill.id,month.toString(),at,70,"pending",null,null,now,now,null,0,device).toCloudRecord()
        val bad=undone.copy(recordsByEntity=undone.recordsByEntity+(CloudEntity.DUE_OCCURRENCE_RECORD to (undone.recordsByEntity.getValue(CloudEntity.DUE_OCCURRENCE_RECORD)+marker)))
        assertTrue(runCatching{undo(bad,undoRequest(s))}.isFailure)
    }
    @Test fun legacyPaidMarkerWithoutALinkRemainsUndoableAndRetryable() {
        val s=source(amount=30)
        val marker=DueOccurrenceRecord(id(72),owner.value,"recurringBill",s.bill.id,month.toString(),at,null,"paid",null,null,now,now,null,0,device).toCloudRecord()
        val input=s.copy(recordsByEntity=s.recordsByEntity+(CloudEntity.DUE_OCCURRENCE_RECORD to listOf(marker)))
        val due=recurringBillDueRows(owner,listOf(RecurringBillPlanRecord.fromCloudRecord(s.bill)),listOf(DueOccurrenceRecord.fromCloudRecord(marker)),month,zone).single()
        val r=undoRequest(s).copy(expectedAmountMinor=due.amountMinor,expectedLinkedTransactionId=null)
        val p=undo(input,r);assertEquals(1,p.mutations.size);assertEquals(id(72),p.mutations.single().first.id)
        assertTrue(undo(apply(input,p),r).mutations.isEmpty())
    }
    @Test fun exactMinorAboveDoubleRangeIsPreservedInExpenseAndPaidMarker() {
        val s=source(amount=9007199254740993L,opening=Long.MAX_VALUE,reserve=0);val p=plan(s,request(s))
        assertEquals(9007199254740993L,p.payment!!.transaction.amountMinor);assertEquals(9007199254740993L,p.payment.occurrences.single().amountMinorSnapshot)
    }
    @Test fun manualConsumptionAtACanonicalIdentityCannotBeDeletedByBillUndo() {
        val s=source();val paid=apply(s,confirmed(s,request(s)))
        val altered=paid.copy(recordsByEntity=paid.recordsByEntity+(CloudEntity.INVESTMENT_POSTING to paid.recordsByEntity.getValue(CloudEntity.INVESTMENT_POSTING).map{
            if(it.id==investmentLedgerIdentity(id(20),"cash-consumption-booked"))it.copy(payload=JsonObject(it.payload+("cash_origin_raw_value" to JsonPrimitive("manual"))))else it}))
        assertEquals(BillPaymentError.UNSUPPORTED_LINKED_STATE,(runCatching{undo(altered,undoRequest(s))}.exceptionOrNull() as? BillPaymentException)?.reason)
    }
    @Test fun undoReviewsRestoringThirtyAndTombstonesTheCompleteOwnedCycleAndDerivedPosting() {
        val s=source();val paid=apply(s,confirmed(s,request(s)))
        val r=BillInvestmentUndoRequest(RecurringBillPlanRecord.fromCloudRecord(s.bill),month,70,id(20),BillInvestmentOperationContext(TransactionCreationIdentity(id(60),later),"JPY","Adjustment"))
        fun undo(request:BillInvestmentUndoRequest)=planBillInvestmentMoney(paid,BillInvestmentMoneyOperation.Undo(request),catalog,device,later,zone)
        val review=(runCatching{undo(r)}.exceptionOrNull() as InvestmentFundUsageConfirmationRequired).review
        assertEquals(30L,review.comparison.primaryChange!!.restoreMinor.longValueExact())
        val p=undo(r.copy(investment=r.investment.copy(consent=review.consent)))
        assertNull(p.payment);assertEquals(3,p.mutations.size);assertTrue(p.mutations.all{it.second.kind==MutationKind.DELETE && it.first.deletedAt==later})
    }
    private fun legacyCompoundPaid():BillMoneySnapshot {
        val s=source(amount=30,reserve=0);val paid=apply(s,plan(s,request(s)))
        val extra=LedgerTransactionRecord.fromCloudRecord(paid.recordsByEntity.getValue(CloudEntity.LEDGER_TRANSACTION).single()).copy(id=id(23),amountMinor=20).toCloudRecord()
        val marker=DueOccurrenceRecord.fromCloudRecord(paid.recordsByEntity.getValue(CloudEntity.DUE_OCCURRENCE_RECORD).single()).copy(id=id(74),amountMinorSnapshot=20,linkedTransactionId=id(23),paidAt=now).toCloudRecord()
        return paid.copy(recordsByEntity=paid.recordsByEntity+(CloudEntity.LEDGER_TRANSACTION to (paid.recordsByEntity.getValue(CloudEntity.LEDGER_TRANSACTION)+extra))+
            (CloudEntity.DUE_OCCURRENCE_RECORD to (paid.recordsByEntity.getValue(CloudEntity.DUE_OCCURRENCE_RECORD)+marker)))
    }
    @Test fun compoundUndoWithDistinctAmountsIsACompleteNoWriteRetry() {
        val s=legacyCompoundPaid();val r=undoRequest(s).copy(expectedAmountMinor=30)
        val p=undo(s,r);assertEquals(4,p.mutations.size)
        assertTrue(undo(apply(s,p),r).mutations.isEmpty())
    }
    @Test fun undoKeepsAnAlreadyDeletedLinkedExpenseAndProvesTheSameCompletedResult() {
        val original=legacyCompoundPaid()
        val s=original.copy(recordsByEntity=original.recordsByEntity+(CloudEntity.LEDGER_TRANSACTION to original.recordsByEntity.getValue(CloudEntity.LEDGER_TRANSACTION).map{row->
            if(row.id==id(23))row.copy(deletedAt=at,payload=JsonObject(row.payload+("deleted_at" to JsonPrimitive(at))))else row}))
        val r=undoRequest(s).copy(expectedAmountMinor=30);val p=undo(s,r)
        assertEquals(3,p.mutations.size);assertTrue(p.mutations.none{it.first.id==id(23)})
        assertTrue(undo(apply(s,p),r).mutations.isEmpty())
    }
    @Test fun undoRejectsAnExistingPendingDuplicateBeforeAnySuccessfulMutation() {
        val paid=legacyCompoundPaid()
        val pending=DueOccurrenceRecord(id(75),owner.value,"recurringBill",paid.bill.id,month.toString(),at,30,"pending",null,null,now,now,null,0,device).toCloudRecord()
        val s=paid.copy(recordsByEntity=paid.recordsByEntity+(CloudEntity.DUE_OCCURRENCE_RECORD to (paid.recordsByEntity.getValue(CloudEntity.DUE_OCCURRENCE_RECORD)+pending)))
        val error=runCatching{undo(s,undoRequest(s).copy(expectedAmountMinor=30))}.exceptionOrNull()
        assertEquals(BillPaymentError.UNSUPPORTED_LINKED_STATE,(error as? BillPaymentException)?.reason)
    }

}
