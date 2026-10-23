package vn.com.quyln.mistia.core.model

import java.time.*
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class InstallmentInvestmentMoneyPlanTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val device="44444444-4444-4444-8444-444444444444"
    private val now="2026-10-23T00:00:00Z"
    private val at="2026-10-23T00:01:00Z"
    private val later="2026-10-23T00:02:00Z"
    private val month=YearMonth.of(2026,10)
    private val zone=ZoneId.of("Asia/Tokyo")
    private fun id(n:Int)=java.util.UUID(0,n.toLong()).toString()
    private val catalog=SystemCategoryCatalog.parse("""[{"id":"debt","kind":"expense","active":true,"icon":"house.fill","fallbackIcon":"house.fill","color":"#123456","translations":{"vi":"Nợ","en":"Debt","ja":"債務"},"aliases":[],"children":[{"id":"loan_repayment","active":true,"icon":"mistia.category.expense.financial_obligations.loan_repayment","fallbackIcon":"house.fill","color":"#123456","translations":{"vi":"Trả nợ","en":"Loan repayment","ja":"返済"},"aliases":[]}]}]""")
    private fun source(amount:Long=70,opening:Long=100,reserve:Long=60):BillMoneySnapshot {
        val parent=catalog.definitions.single{it.parentKey==null}.seedRecord(owner,null,device,now)
        val child=catalog.definitions.single{it.parentKey!=null}.seedRecord(owner,parent.id,device,now)
        val wallet=WalletDraft(id=id(1),name="Cash",kind=WalletKind.CASH,currencyCode="JPY",openingBalanceMinor=opening).toMutation(owner,null,device,now).record
        val plan=InstallmentPlanRecord(id(50),owner.value,"Loan","mistia.plan.loan",amount,23,12,1,wallet.id,"JPY",false,now,now,null,0,device).toCloudRecord()
        val posting=CloudRecord(CloudEntity.INVESTMENT_POSTING.table,id(10),owner.value,buildJsonObject {
            put("id",id(10));put("user_id",owner.value);put("sync_version",0L);put("deleted_at",JsonNull);put("created_at",now);put("updated_at",now)
            put("event_id",id(11));put("ledger_transaction_id",id(11));put("wallet_id",id(1));put("role_raw_value","cashAccrual");put("cash_bucket_raw_value","booked");put("cash_origin_raw_value","derived")
            put("amount_minor",reserve);put("accounting_amount_minor",reserve);put("currency_code","JPY");put("accounting_currency_code","JPY");put("occurred_at","2026-10-23T00:00:01Z")
        },now,null,0)
        val rows=listOf(wallet,parent.toCloudRecord(),child.toCloudRecord(),plan,posting)
        return BillMoneySnapshot(owner,plan,month,CloudEntity.entries.associateWith{e->rows.filter{it.entity==e.table}},sourceKind=DueSourceKind.INSTALLMENT)
    }
    private fun request(s:BillMoneySnapshot)=InstallmentPaymentRequest(InstallmentPlanRecord.fromCloudRecord(s.bill),month,RecordId(id(1)),investment=
        BillInvestmentOperationContext(TransactionCreationIdentity(id(20),at),"JPY","Adjustment"))
    private fun plan(s:BillMoneySnapshot,r:InstallmentPaymentRequest,clock:String=at)=planInstallmentInvestmentMoney(s,InstallmentInvestmentMoneyOperation.Pay(r),catalog,device,clock,zone)
    private fun confirmed(s:BillMoneySnapshot,r:InstallmentPaymentRequest):InstallmentInvestmentMoneyPlan {
        val review=(runCatching{plan(s,r)}.exceptionOrNull() as InvestmentFundUsageConfirmationRequired).review
        return plan(s,r.copy(investment=r.investment!!.copy(consent=review.consent)))
    }
    private fun apply(s:BillMoneySnapshot,p:InstallmentInvestmentMoneyPlan):BillMoneySnapshot {
        val writes=p.mutations.map{it.first}
        return s.copy(recordsByEntity=s.recordsByEntity.mapValues{(e,rows)->rows.filter{old->writes.none{it.entity==e.table && it.id==old.id}}+writes.filter{it.entity==e.table}})
    }
    @Test fun seventyInstallmentNeedsThirtyConsentAndRealInstallmentCycleAndLoanCategory() {
        val s=source();val r=request(s);val review=(runCatching{plan(s,r)}.exceptionOrNull() as InvestmentFundUsageConfirmationRequired).review
        assertEquals(30L,review.comparison.proposed.usages.getValue(id(20)).investmentToUseMinor.longValueExact())
        val p=plan(s,r.copy(investment=r.investment!!.copy(consent=review.consent)))
        assertEquals(id(20),p.payment!!.transaction.id);assertEquals(70L,p.payment.transaction.amountMinor)
        assertEquals("installment",p.payment.occurrences.single().sourceKindWireValue);assertEquals(id(50),p.payment.occurrences.single().sourceId)
        assertEquals(SystemCategoryIdentity.cloudId("loan_repayment",owner),p.payment.transaction.categoryId)
        assertEquals(-30L,p.mutations.single{it.first.entity==CloudEntity.INVESTMENT_POSTING.table}.first.payload.financeRawLong("amount_minor"))
    }
    @Test fun ordinaryPartOfWalletWithReservedCashPaysWithoutConsent() {
        val s=source(amount=30);val p=plan(s,request(s))
        assertEquals(30L,p.payment!!.transaction.amountMinor);assertEquals(2,p.mutations.size)
    }
    @Test fun aKnownCompletePaymentAfterAckDoesNotSpendOrQueueAgain() {
        val s=source();val r=request(s);val paid=apply(s,confirmed(s,r))
        val rows=paid.recordsByEntity.mapValues{(_,list)->list.map{it.copy(syncVersion=9007199254740993L,updatedAt=later,
            payload=JsonObject(it.payload+buildJsonObject{put("sync_version",9007199254740993L);put("updated_at",later)}))}}
        val ack=paid.copy(recordsByEntity=rows,bill=rows.getValue(CloudEntity.INSTALLMENT_PLAN).single())
        val retry=plan(ack,r,later);assertTrue(retry.mutations.isEmpty());assertEquals(id(20),retry.payment!!.transaction.id)
    }
    @Test fun partialDerivedKnownResultIsHeldInsteadOfSilentlyRepaired() {
        val s=source();val r=request(s);val paid=apply(s,confirmed(s,r))
        val partial=paid.copy(recordsByEntity=paid.recordsByEntity+(CloudEntity.INVESTMENT_POSTING to paid.recordsByEntity.getValue(CloudEntity.INVESTMENT_POSTING).filterNot{it.id==investmentLedgerIdentity(id(20),"cash-consumption-booked")}))
        assertEquals(InvestmentFundUsageError.EVENT_CONFLICT,(runCatching{plan(partial,r,later)}.exceptionOrNull() as? InvestmentFundUsageException)?.reason)
    }
    @Test fun insufficientCurrentCashIsRejectedBeforeDerivedMoneyCanHideIt() {
        val s=source(opening=50)
        assertEquals(TransactionValidationError.INSUFFICIENT_WALLET_BALANCE,(runCatching{plan(s,request(s))}.exceptionOrNull() as? TransactionValidationException)?.reason)
    }
    @Test fun undoRequiresRestoreReviewThenProvesCompleteNoWriteRetry() {
        val s=source();val paid=apply(s,confirmed(s,request(s)))
        val r=InstallmentInvestmentUndoRequest(InstallmentPlanRecord.fromCloudRecord(s.bill),month,70,id(20),BillInvestmentOperationContext(TransactionCreationIdentity(id(60),later),"JPY","Adjustment"))
        fun undo(s:BillMoneySnapshot,r:InstallmentInvestmentUndoRequest)=planInstallmentInvestmentMoney(s,InstallmentInvestmentMoneyOperation.Undo(r),catalog,device,later,zone)
        val review=(runCatching{undo(paid,r)}.exceptionOrNull() as InvestmentFundUsageConfirmationRequired).review
        assertEquals(30L,review.comparison.primaryChange!!.restoreMinor.longValueExact())
        val p=undo(paid,r.copy(investment=r.investment.copy(consent=review.consent)))
        assertEquals(3,p.mutations.size);assertTrue(p.mutations.all{it.second.kind==MutationKind.DELETE})
        assertTrue(undo(apply(paid,p),r).mutations.isEmpty())
    }
    private fun replace(s:BillMoneySnapshot,row:CloudRecord):BillMoneySnapshot {
        val entity=CloudEntity.fromTable(row.entity)!!
        return s.copy(bill=if(row.entity==s.bill.entity && row.id==s.bill.id)row else s.bill,
            recordsByEntity=s.recordsByEntity+(entity to (s.recordsByEntity.getValue(entity).filterNot{it.id==row.id}+row)))
    }
    private fun foreign(amount:Long):BillMoneySnapshot {
        var s=source(amount,100_000,2)
        val wallet=s.recordsByEntity.getValue(CloudEntity.LEDGER_WALLET).single()
        s=replace(s,wallet.copy(payload=JsonObject(wallet.payload+("currency_code" to JsonPrimitive("VND")))))
        s=replace(s,InstallmentPlanRecord.fromCloudRecord(s.bill).copy(currencyCode="VND").toCloudRecord())
        val posting=s.recordsByEntity.getValue(CloudEntity.INVESTMENT_POSTING).single()
        return replace(s,posting.copy(payload=JsonObject(posting.payload+buildJsonObject{put("currency_code","VND");put("amount_minor",40_000L)})))
    }
    @Test fun foreignOrdinaryCashStillPaysButForeignReservedCashCannotBeComparedToAccountingMinor() {
        val ordinary=foreign(50_000);assertEquals(50_000L,plan(ordinary,request(ordinary)).payment!!.transaction.amountMinor)
        val fund=foreign(70_000)
        assertEquals(InvestmentFundUsageError.CURRENCY_MISMATCH,(runCatching{plan(fund,request(fund))}.exceptionOrNull() as? InvestmentFundUsageException)?.reason)
    }
    @Test fun installmentRejectsCardsInvestmentWalletsAndDifferentCurrencyBeforeAnyPayment() {
        for(kind in listOf(WalletKind.CREDIT_CARD,WalletKind.INVESTMENT)) {
            val s=source();val wallet=s.recordsByEntity.getValue(CloudEntity.LEDGER_WALLET).single()
            val changed=replace(s,wallet.copy(payload=JsonObject(wallet.payload+("kind_raw_value" to JsonPrimitive(kind.wireValue)))))
            assertEquals(kind.toString(),BillPaymentError.INVALID_WALLET,(runCatching{plan(changed,request(s))}.exceptionOrNull() as? BillPaymentException)?.reason)
        }
        val s=source();val wallet=s.recordsByEntity.getValue(CloudEntity.LEDGER_WALLET).single()
        val changed=replace(s,wallet.copy(payload=JsonObject(wallet.payload+("currency_code" to JsonPrimitive("VND")))))
        assertEquals(BillPaymentError.WALLET_CURRENCY_MISMATCH,(runCatching{plan(changed,request(s))}.exceptionOrNull() as? BillPaymentException)?.reason)
    }
    @Test fun realInstallmentAnchorFrequencyAndTotalCyclesDetermineEligibility() {
        val s=source(amount=30);val expired=s.copy(month=month.plusMonths(12))
        assertEquals(BillPaymentError.NOT_SCHEDULED,(runCatching{plan(expired,request(expired).copy(month=expired.month))}.exceptionOrNull() as? BillPaymentException)?.reason)
        val alternate=replace(s,InstallmentPlanRecord.fromCloudRecord(s.bill).copy(frequencyMonths=2).toCloudRecord()).copy(month=month.plusMonths(1))
        assertEquals(BillPaymentError.NOT_SCHEDULED,(runCatching{plan(alternate,request(alternate).copy(month=alternate.month))}.exceptionOrNull() as? BillPaymentException)?.reason)
        assertTrue(plan(s,request(s)).payment!!.occurrences.single().scheduledDate.startsWith("2026-10-22T15:00:00"))
    }
    @Test fun skippedUnknownAndChangedEffectiveCycleCannotAcceptOldPaymentConfirmation() {
        val s=source(amount=30)
        for((status,amount,want)in listOf(Triple("skipped",30L,BillPaymentError.CYCLE_NOT_PENDING),Triple("future",30L,BillPaymentError.UNSUPPORTED_LINKED_STATE),Triple("pending",40L,BillPaymentError.SOURCE_CHANGED))) {
            val marker=DueOccurrenceRecord(id(70),owner.value,"installment",s.bill.id,month.toString(),at,amount,status,null,null,now,now,null,0,device).toCloudRecord()
            assertEquals(status,want,(runCatching{plan(replace(s,marker),request(s))}.exceptionOrNull() as? BillPaymentException)?.reason)
        }
    }
    @Test fun exactLongBootstrapAndRawExtensionSurviveUndoAndRepaymentWithOneOriginalIdentity() {
        val exact=source(9007199254740993L,Long.MAX_VALUE,0);val p=plan(exact,request(exact))
        assertEquals(9007199254740993L,p.payment!!.transaction.amountMinor);assertEquals(9007199254740993L,p.payment.occurrences.single().amountMinorSnapshot)
        val missing=source().let{it.copy(recordsByEntity=it.recordsByEntity+(CloudEntity.TRANSACTION_CATEGORY to emptyList()))}
        val request=request(missing);val review=(runCatching{plan(missing,request)}.exceptionOrNull() as InvestmentFundUsageConfirmationRequired).review
        val bootstrap=plan(missing,request.copy(investment=request.investment!!.copy(consent=review.consent)),later)
        assertEquals(2,bootstrap.mutations.count{it.first.entity==CloudEntity.TRANSACTION_CATEGORY.table})
        assertTrue(bootstrap.mutations.filter{it.first.entity==CloudEntity.TRANSACTION_CATEGORY.table}.all{it.first.payload.financeRawString("created_at")==at})
        var paid=apply(missing,bootstrap);val tx=paid.recordsByEntity.getValue(CloudEntity.LEDGER_TRANSACTION).single()
        paid=replace(paid,tx.copy(payload=JsonObject(tx.payload+("future_field" to JsonPrimitive("keep")))))
        val undo=InstallmentInvestmentUndoRequest(InstallmentPlanRecord.fromCloudRecord(paid.bill),month,70,id(20),BillInvestmentOperationContext(TransactionCreationIdentity(id(60),later),"JPY","Adjustment"))
        val undoReview=(runCatching{planInstallmentInvestmentMoney(paid,InstallmentInvestmentMoneyOperation.Undo(undo),catalog,device,later,zone)}.exceptionOrNull() as InvestmentFundUsageConfirmationRequired).review
        val undone=apply(paid,planInstallmentInvestmentMoney(paid,InstallmentInvestmentMoneyOperation.Undo(undo.copy(investment=undo.investment.copy(consent=undoReview.consent))),catalog,device,later,zone))
        assertEquals(BillPaymentError.SOURCE_CHANGED,(runCatching{plan(undone,request,"2026-10-23T00:03:00Z")}.exceptionOrNull() as? BillPaymentException)?.reason)
        val again=request.copy(investment=BillInvestmentOperationContext(TransactionCreationIdentity(id(21),"2026-10-23T00:03:00Z"),"JPY","Adjustment"))
        val againReview=(runCatching{plan(undone,again,"2026-10-23T00:03:00Z")}.exceptionOrNull() as InvestmentFundUsageConfirmationRequired).review
        val saved=plan(undone,again.copy(investment=again.investment!!.copy(consent=againReview.consent)),"2026-10-23T00:03:00Z")
        assertEquals(id(20),saved.payment!!.transaction.id)
        assertEquals(JsonPrimitive("keep"),saved.mutations.single{it.first.entity==CloudEntity.LEDGER_TRANSACTION.table}.first.payload["future_field"])
    }

    private fun undoRequest(s:BillMoneySnapshot)=InstallmentInvestmentUndoRequest(InstallmentPlanRecord.fromCloudRecord(s.bill),month,30,id(20),
        BillInvestmentOperationContext(TransactionCreationIdentity(id(60),later),"JPY","Adjustment"))
    private fun undo(s:BillMoneySnapshot,r:InstallmentInvestmentUndoRequest)=planInstallmentInvestmentMoney(s,InstallmentInvestmentMoneyOperation.Undo(r),catalog,device,later,zone)
    private fun compoundPaid():BillMoneySnapshot {
        val s=source(amount=30,reserve=0);var paid=apply(s,plan(s,request(s)))
        val extra=LedgerTransactionRecord.fromCloudRecord(paid.recordsByEntity.getValue(CloudEntity.LEDGER_TRANSACTION).single()).copy(id=id(23),amountMinor=20).toCloudRecord()
        val marker=DueOccurrenceRecord.fromCloudRecord(paid.recordsByEntity.getValue(CloudEntity.DUE_OCCURRENCE_RECORD).single()).copy(id=id(74),amountMinorSnapshot=20,linkedTransactionId=id(23),paidAt=now).toCloudRecord()
        paid=replace(paid,extra);return replace(paid,marker)
    }
    @Test fun compoundInstallmentUndoWithDifferentAmountsAndPriorExpenseTombstoneHasSameCompletedProof() {
        for(priorDeleted in listOf(false,true)) {
            var s=compoundPaid()
            if(priorDeleted) {
                val row=s.recordsByEntity.getValue(CloudEntity.LEDGER_TRANSACTION).single{it.id==id(23)}
                s=replace(s,row.copy(deletedAt=at,payload=JsonObject(row.payload+("deleted_at" to JsonPrimitive(at)))))
            }
            val r=undoRequest(s);val p=undo(s,r);assertEquals(if(priorDeleted)3 else 4,p.mutations.size)
            assertTrue(undo(apply(s,p),r).mutations.isEmpty())
        }
    }
    @Test fun pendingDuplicateIsHeldBeforeUndoAndTamperedCompletedMarkerCannotBeClaimedAsSuccess() {
        val s=compoundPaid();val r=undoRequest(s);val done=apply(s,undo(s,r))
        val marker=done.recordsByEntity.getValue(CloudEntity.DUE_OCCURRENCE_RECORD).first()
        val changed=replace(done,marker.copy(payload=JsonObject(marker.payload+("amount_minor_snapshot" to JsonPrimitive(99L)))))
        assertTrue(runCatching{undo(changed,r)}.isFailure)
        val pending=DueOccurrenceRecord(id(75),owner.value,"installment",s.bill.id,month.toString(),at,30,"pending",null,null,now,now,null,0,device).toCloudRecord()
        assertEquals(BillPaymentError.UNSUPPORTED_LINKED_STATE,(runCatching{undo(replace(s,pending),r)}.exceptionOrNull() as? BillPaymentException)?.reason)
    }
    @Test fun receiptLinkAndPreexistingCanonicalDriftCannotBeHiddenByAReservedPayment() {
        val original=source();val paid=apply(original,confirmed(original,request(original)))
        val receipt=paid.copy(receiptTransactionIds=setOf(id(20)))
        assertEquals(BillPaymentError.UNSUPPORTED_LINKED_STATE,(runCatching{plan(receipt,request(original),later)}.exceptionOrNull() as? BillPaymentException)?.reason)
        val other=InstallmentPlanRecord.fromCloudRecord(original.bill).copy(id=id(51),name="Other loan",amountPerCycleMinor=30).toCloudRecord()
        var current=replace(paid,other).copy(bill=other)
        val wallet=current.recordsByEntity.getValue(CloudEntity.LEDGER_WALLET).single()
        current=replace(current,wallet.copy(payload=JsonObject(wallet.payload+("opening_balance_minor" to JsonPrimitive(200L)))))
        val r=request(current).copy(investment=BillInvestmentOperationContext(TransactionCreationIdentity(id(21),later),"JPY","Adjustment"))
        assertEquals(InvestmentFundUsageError.EVENT_CONFLICT,(runCatching{plan(current,r,later)}.exceptionOrNull() as? InvestmentFundUsageException)?.reason)
    }

    @Test fun olderDeletedDuplicateMarkerDoesNotMakeASuccessfulUndoUnretryable() {
        val s=compoundPaid()
        val live=DueOccurrenceRecord.fromCloudRecord(s.recordsByEntity.getValue(CloudEntity.DUE_OCCURRENCE_RECORD).first())
        val old=live.copy(id=id(76),createdAt=now,updatedAt=now,paidAt=now,deletedAt=now).toCloudRecord()
        val withOld=replace(s,old);val r=undoRequest(withOld)
        val result=undo(withOld,r)
        assertTrue(result.mutations.none{it.first.id==id(76)})
        assertTrue(undo(apply(withOld,result),r).mutations.isEmpty())
    }

}
