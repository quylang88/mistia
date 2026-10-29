package vn.com.quyln.mistia.core.model

import java.time.*
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class CreditCardStatementPaymentTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val device="44444444-4444-4444-8444-444444444444"
    private val birth="2026-08-01T00:00:00Z"
    private val now="2026-10-22T00:00:02Z"
    private val month=YearMonth.of(2026,9)
    private val zone=ZoneId.of("Asia/Tokyo")
    private fun id(n:Int)=java.util.UUID(0,n.toLong()).toString()
    private fun cash(opening:Long=100)=LedgerWalletRecord.fromCloudRecord(WalletDraft(id=id(1),name="Cash",kind=WalletKind.CASH,currencyCode="JPY",openingBalanceMinor=opening).toMutation(owner,null,device,birth).record)
    private val card=LedgerWalletRecord.fromCloudRecord(WalletDraft(id=id(2),name="Card",kind=WalletKind.CASH,currencyCode="JPY").toMutation(owner,null,device,birth).record).copy(kindWireValue="creditCard")
    private val profile=CreditCardProfileRecord(id(3),owner.value,"Issuer","visa","1234",Long.MAX_VALUE,10,26,null,card.id,id(1),true,birth,birth,null,0,device)
    private val parent=CategoryDraft(id=id(30),name="Parent",kind=TransactionCategoryKind.EXPENSE,hierarchyRole=CategoryHierarchyRole.PARENT).toMutation(owner,null,null,device,birth).record
    private val child=CategoryDraft(id=id(31),name="Child",kind=TransactionCategoryKind.EXPENSE,hierarchyRole=CategoryHierarchyRole.CHILD,parentCategoryId=parent.id).toMutation(owner,null,parent,device,birth).record
    private fun charge(amount:Long=70,n:Int=5,at:String="2026-09-12T00:00:00Z")=TransactionDraft(id=id(n),primaryKind=TransactionPrimaryKind.EXPENSE,title="Charge",amountMinor=amount,occurredAt=at,sourceWalletId=card.id,categoryId=child.id).toMutation(owner,null,card,null,child,device,birth).record.toCloudRecord()
    private fun source(reserve:Long=0,amount:Long=70,opening:Long=100,additional:List<CloudRecord> = emptyList()):CreditCardStatementPaymentSnapshot {
        val root=cash(0).copy(id=investmentSystemWalletId(owner),kindWireValue="investment",systemPurposeRawValue="investmentProfit",investmentLinkedWalletId=id(1)).toCloudRecord()
        val posting=CloudRecord(CloudEntity.INVESTMENT_POSTING.table,id(10),owner.value,buildJsonObject{
            put("id",id(10));put("user_id",owner.value);put("sync_version",0);put("created_at",birth);put("updated_at",birth);put("deleted_at",JsonNull);put("last_modified_by_device_id",device)
            put("event_id",id(11));put("ledger_transaction_id",id(11));put("wallet_id",id(1));put("role_raw_value","cashAccrual");put("cash_bucket_raw_value","booked");put("cash_origin_raw_value","derived")
            put("amount_minor",reserve);put("accounting_amount_minor",reserve);put("currency_code","JPY");put("accounting_currency_code","JPY");put("occurred_at",birth)
        },birth,null,0)
        val rows=listOf(cash(opening).toCloudRecord(),card.toCloudRecord(),profile.toCloudRecord(),parent.toCloudRecord(),child.toCloudRecord(),charge(amount),root)+
            (if(reserve>0)listOf(posting)else emptyList())+additional
        return CreditCardStatementPaymentSnapshot(TransactionInvestmentSaveSnapshot(owner,TransactionInvestmentSaveSnapshot.entities.associateWith{entity->rows.filter{it.entity==entity.table}}))
    }
    private fun statement(s:CreditCardStatementPaymentSnapshot,selected:YearMonth=month,at:String=now):CreditCardStatement {
        val rows=s.money.recordsByEntity
        val c=rows.getValue(CloudEntity.LEDGER_WALLET).single{it.id==card.id}.let(LedgerWalletRecord::fromCloudRecord)
        val p=rows.getValue(CloudEntity.CREDIT_CARD_PROFILE).single().let(CreditCardProfileRecord::fromCloudRecord)
        return creditCardStatementItems(owner,listOf(CreditCardAccount(c,p)),rows.getValue(CloudEntity.LEDGER_TRANSACTION).map(LedgerTransactionRecord::fromCloudRecord),
            rows.getValue(CloudEntity.DUE_OCCURRENCE_RECORD).map(DueOccurrenceRecord::fromCloudRecord),listOf(selected),Instant.parse(at),zone,rows.getValue(CloudEntity.TRANSACTION_CATEGORY).map(TransactionCategoryRecord::fromCloudRecord)).single()
    }
    private fun request(s:CreditCardStatementPaymentSnapshot,consent:InvestmentFundUsageConsent?=null,selected:YearMonth=month)=
        CreditCardStatementPaymentRequest(statement(s,selected),BillInvestmentOperationContext(TransactionCreationIdentity(id(20),now),"JPY","Adjustment",consent),"Pay Card")
    private fun plan(s:CreditCardStatementPaymentSnapshot,r:CreditCardStatementPaymentRequest=request(s))=planCreditCardStatementPayment(s,r,device,now,zone)
    private fun change(s:CreditCardStatementPaymentSnapshot,entity:CloudEntity,transform:(CloudRecord)->CloudRecord)=s.copy(money=s.money.copy(recordsByEntity=s.money.recordsByEntity+(entity to s.money.recordsByEntity.getValue(entity).map(transform))))
    private fun patch(r:CloudRecord,key:String,v:JsonElement)=r.copy(payload=JsonObject(r.payload+(key to v)))
    private fun apply(s:CreditCardStatementPaymentSnapshot,p:CreditCardStatementPaymentPlan)=s.copy(money=s.money.copy(recordsByEntity=s.money.recordsByEntity.mapValues{(entity,rows)->rows.filter{old->p.mutations.none{it.first.entity==entity.table && it.first.id==old.id}}+p.mutations.map{it.first}.filter{it.entity==entity.table}}))
    private fun reason(s:CreditCardStatementPaymentSnapshot,r:CreditCardStatementPaymentRequest)= (runCatching{plan(s,r)}.exceptionOrNull() as? CreditCardStatementPaymentException)?.reason
    @Test fun ordinaryPaymentCreatesOneExactTransferAndOneOwnedPaidMarker() {
        val s=source();val p=plan(s)
        assertEquals(2,p.mutations.size);assertEquals(70L,p.payment.transaction.amountMinor);assertEquals(70L,p.payment.transaction.destinationAmountMinor ?: p.payment.transaction.amountMinor)
        assertEquals(id(1),p.payment.transaction.sourceWalletId);assertEquals(card.id,p.payment.transaction.destinationWalletId)
        val c=p.payment.occurrence;assertEquals("creditCard",c.sourceKindWireValue);assertEquals(month.toString(),c.selectedMonthKey)
        assertEquals(statement(s).dueDate,Instant.parse(c.scheduledDate));assertEquals(now,c.paidAt);assertEquals(id(20),c.linkedTransactionId)
        assertTrue(p.mutations.all{it.first.ownerUserId==owner.value && it.second.payload==it.first.payload && it.first.entity in setOf(CloudEntity.LEDGER_TRANSACTION.table,CloudEntity.DUE_OCCURRENCE_RECORD.table)})
    }
    @Test fun confirmedFundedPaymentConsumesOnlyTheThirtyReservedMinor() {
        val s=source(60);val review=(runCatching{plan(s)}.exceptionOrNull() as InvestmentFundUsageConfirmationRequired).review
        val p=plan(s,request(s,review.consent));assertEquals(3,p.mutations.size)
        val posting=p.mutations.single{it.first.entity==CloudEntity.INVESTMENT_POSTING.table}.first
        assertEquals(-30L,posting.payload.financeRawLong("amount_minor"));assertEquals("cashConsumption",posting.payload.financeRawString("role_raw_value"))
        assertEquals(70L,p.payment.occurrence.amountMinorSnapshot)
    }
    @Test fun completedPaymentReplayAfterAckNeverCreatesOrRepairsMoneyAgain() {
        val s=source(60);val r=request(s,(runCatching{plan(s)}.exceptionOrNull() as InvestmentFundUsageConfirmationRequired).review.consent)
        val p=plan(s,r);var saved=apply(s,p)
        saved=saved.copy(money=saved.money.copy(recordsByEntity=saved.money.recordsByEntity.mapValues{(_,rows)->rows.map{row->patch(row,"sync_version",JsonPrimitive(9007199254740993L)).copy(syncVersion=9007199254740993L)}}))
        val replay=plan(saved,r);assertTrue(replay.mutations.isEmpty());assertEquals(9007199254740993L,replay.payment.transaction.syncVersion)
    }
    @Test fun changedChargeOrProfileCannotPayTheOldVisibleStatement() {
        val s=source();val r=request(s)
        assertEquals(CreditCardStatementPaymentError.SOURCE_CHANGED,reason(change(s,CloudEntity.LEDGER_TRANSACTION){patch(it,"amount_minor",JsonPrimitive(80L))},r))
        assertEquals(CreditCardStatementPaymentError.SOURCE_CHANGED,reason(change(s,CloudEntity.CREDIT_CARD_PROFILE){patch(it,"payment_due_day",JsonPrimitive(27))},r))
    }
    @Test fun deletedArchivedOrForeignCardCannotProduceAnyPayment() {
        val s=source();val r=request(s)
        for(value in listOf(true,false)) {
            val c=change(s,CloudEntity.LEDGER_WALLET){if(it.id!=card.id)it else if(value)patch(it,"is_archived",JsonPrimitive(true)) else patch(it,"deleted_at",JsonPrimitive(now)).copy(deletedAt=now)}
            assertEquals(CreditCardStatementPaymentError.NOT_FOUND,reason(c,r))
        }
        val foreign=change(s,CloudEntity.LEDGER_WALLET){if(it.id==card.id)it.copy(ownerUserId=id(99))else it}
        assertTrue(runCatching{plan(foreign,r)}.isFailure)
    }
    @Test fun linkedWalletMustBeLiveOwnedNormalAndSameCurrency() {
        val s=source();val r=request(s)
        assertEquals(CreditCardStatementPaymentError.CURRENCY_MISMATCH,reason(change(s,CloudEntity.LEDGER_WALLET){if(it.id==id(1))patch(it,"currency_code",JsonPrimitive("VND"))else it},r))
        for(kind in listOf("creditCard","investment","unknown"))assertEquals(CreditCardStatementPaymentError.INVALID_WALLET,reason(change(s,CloudEntity.LEDGER_WALLET){if(it.id==id(1))patch(it,"kind_raw_value",JsonPrimitive(kind))else it},r))
        val missing=change(s,CloudEntity.CREDIT_CARD_PROFILE){patch(it,"payment_source_wallet_id",JsonNull)}
        assertEquals(CreditCardStatementPaymentError.MISSING_LINKED_WALLET,reason(missing,request(missing)))
    }
    @Test fun currencyEligibilityRejectsUnmatchedAndMalformedCodes() {
        for((a,b,expected) in listOf(Triple("JPY","JPY",true),Triple(" jpy ","JPY",true),Triple("VND","JPY",false),Triple("","",false),Triple("US","US",false),Triple("123","123",false)))
            assertEquals(expected,creditCardPaymentCurrenciesMatch(a,b))
    }
    @Test fun zeroUnclosedOrAlreadyPaidStatementsCannotCreateAnotherTransfer() {
        val base=source();val s=base.copy(money=base.money.copy(recordsByEntity=base.money.recordsByEntity+(CloudEntity.LEDGER_TRANSACTION to emptyList())));assertEquals(CreditCardStatementPaymentError.NOT_PAYABLE,reason(s,request(s)))
        val before=source();val early="2026-10-09T00:00:00Z"
        val req=request(before).copy(expected=statement(before,at=early),context=request(before).context.copy(creation=TransactionCreationIdentity(id(20),early)))
        assertEquals(CreditCardStatementPaymentError.NOT_PAYABLE,(runCatching{planCreditCardStatementPayment(before,req,device,early,zone)}.exceptionOrNull() as? CreditCardStatementPaymentException)?.reason)
        val p=plan(before);val saved=apply(before,p);assertEquals(CreditCardStatementPaymentError.NOT_PAYABLE,reason(saved,request(saved).copy(context=request(saved).context.copy(creation=TransactionCreationIdentity(id(21),now)))))
    }
    @Test fun changedFundSourceRevokesTheConfirmedReview() {
        val s=source(60);val consent=(runCatching{plan(s)}.exceptionOrNull() as InvestmentFundUsageConfirmationRequired).review.consent
        val changed=change(s,CloudEntity.LEDGER_WALLET){if(it.id==id(1))patch(it,"opening_balance_minor",JsonPrimitive(90L))else it}
        val error=runCatching{plan(changed,request(s,consent))}.exceptionOrNull()
        assertEquals(InvestmentFundUsageError.STALE_CONSENT,(error as? InvestmentFundUsageException)?.reason)
    }
    @Test fun consentForAnotherStatementMonthCannotBeReusedForAnIdenticalTransfer() {
        val s=source(60,additional=listOf(charge(n=6,at="2026-08-12T00:00:00Z")))
        val consent=(runCatching{plan(s)}.exceptionOrNull() as InvestmentFundUsageConfirmationRequired).review.consent
        val other=request(s,consent,YearMonth.of(2026,8))
        assertEquals(InvestmentFundUsageError.STALE_CONSENT,(runCatching{plan(s,other)}.exceptionOrNull() as? InvestmentFundUsageException)?.reason)
    }
    @Test fun conflictingFinancialSiblingOrDuplicateMetadataNeedsExplicitReconciliation() {
        val s=source();val due=statement(s).dueDate.toString()
        val pending=DueOccurrenceRecord(id(40),owner.value,"creditCard",card.id,month.toString(),due,70,"pending",null,null,birth,birth,null,0,device)
        val duplicate=source(additional=listOf(pending.toCloudRecord(),pending.copy(id=id(41)).toCloudRecord()))
        assertEquals(CreditCardStatementPaymentError.CYCLE_CONFLICT,reason(duplicate,request(duplicate)))
        val unknown=source(additional=listOf(pending.copy(statusWireValue="paid",paidAt=now,linkedTransactionId=id(99)).toCloudRecord()))
        assertEquals(CreditCardStatementPaymentError.CYCLE_CONFLICT,reason(unknown,request(unknown)))
    }
    @Test fun existingPendingMarkerKeepsItsImmutableBirthAndExactLongVersion() {
        val s=source();val pending=DueOccurrenceRecord(id(40),owner.value,"creditCard",card.id,month.toString(),statement(s).dueDate.toString(),70,"pending",null,null,birth,birth,null,9007199254740993L,device)
        val input=source(additional=listOf(pending.toCloudRecord()));val p=plan(input)
        assertEquals(pending.id,p.payment.occurrence.id);assertEquals(birth,p.payment.occurrence.createdAt);assertEquals(pending.syncVersion,p.payment.occurrence.syncVersion)
    }
    @Test fun exactMoneyAboveDoubleRangeAndInsufficientSourceUseIntegerUnits() {
        val amount=9007199254740993L;val s=source(amount=amount,opening=amount)
        assertEquals(amount,plan(s).payment.transaction.amountMinor)
        val low=source(opening=69);assertEquals(TransactionValidationError.INSUFFICIENT_WALLET_BALANCE,(runCatching{plan(low)}.exceptionOrNull() as? TransactionValidationException)?.reason)
    }
    @Test fun ackOnlyMetadataDoesNotInvalidateTheFinancialConsent() {
        val s=source(60);val consent=(runCatching{plan(s)}.exceptionOrNull() as InvestmentFundUsageConfirmationRequired).review.consent
        val acknowledged=s.copy(money=s.money.copy(recordsByEntity=s.money.recordsByEntity.mapValues{(_,rows)->rows.map{r->
            r.copy(syncVersion=9007199254740993L,payload=JsonObject(r.payload+buildJsonObject{put("sync_version",9007199254740993L);put("updated_at",now);put("last_modified_by_device_id",id(90))}),updatedAt=now)
        }}))
        assertEquals(3,plan(acknowledged,request(s,consent)).mutations.size)
    }
    @Test fun aDeletedPreviousPaymentCanBePaidAgainWithoutRelabellingItsHistory() {
        val original=source();val first=plan(original);val saved=apply(original,first)
        val deleted="2026-10-22T00:00:03Z";val later="2026-10-22T00:00:04Z"
        var undone=change(saved,CloudEntity.LEDGER_TRANSACTION){r->if(r.id==first.payment.transaction.id)patch(patch(r,"deleted_at",JsonPrimitive(deleted)),"updated_at",JsonPrimitive(deleted)).copy(deletedAt=deleted,updatedAt=deleted)else r}
        undone=change(undone,CloudEntity.DUE_OCCURRENCE_RECORD){r->patch(patch(r,"deleted_at",JsonPrimitive(deleted)),"updated_at",JsonPrimitive(deleted)).copy(deletedAt=deleted,updatedAt=deleted)}
        val req=request(undone).let{it.copy(context=it.context.copy(creation=TransactionCreationIdentity(id(21),later)))}
        val next=planCreditCardStatementPayment(undone,req,device,later,zone)
        assertEquals(2,next.mutations.size);assertNotEquals(first.payment.occurrence.id,next.payment.occurrence.id)
        assertEquals(id(21),next.payment.occurrence.linkedTransactionId)
        assertTrue(next.mutations.none{it.first.id in setOf(first.payment.transaction.id,first.payment.occurrence.id)})
    }
    @Test fun legacyDueMonthMetadataIsNormalizedOnlyWhenItsScheduledDateMatchesThisStatement() {
        val s=source();val due=statement(s).dueDate
        val pending=DueOccurrenceRecord(id(40),owner.value,"creditCard",card.id,YearMonth.from(due.atZone(zone)).toString(),due.toString(),70,"pending",null,null,birth,birth,null,0,device)
        val input=source(additional=listOf(pending.toCloudRecord()));val p=plan(input)
        assertEquals(pending.id,p.payment.occurrence.id);assertEquals(month.toString(),p.payment.occurrence.selectedMonthKey)
    }
    @Test fun occupiedCreationCannotBeRepairedOrOverwritten() {
        val s=source(additional=listOf(charge(n=20)));val r=request(s)
        assertEquals(CreditCardStatementPaymentError.IDENTITY_CONFLICT,reason(s,r))
    }

    @Test fun nanosecondCreationReplaysLocallyWithoutASecondPayment() {
        val at="2026-10-22T00:00:02.123456789Z"
        val s=source();val r=request(s).let{it.copy(context=it.context.copy(creation=TransactionCreationIdentity(id(20),at)))}
        val first=planCreditCardStatementPayment(s,r,device,at,zone)
        val replay=planCreditCardStatementPayment(apply(s,first),r,device,"2026-10-22T00:00:03Z",zone)
        assertTrue(replay.mutations.isEmpty());assertEquals(first.payment,replay.payment)
    }

    @Test fun nanosecondIntentReplaysAfterPostgresMicrosecondAcknowledgement() {
        val at="2026-10-22T00:00:02.123456789Z"
        val s=source();val r=request(s).let{it.copy(context=it.context.copy(creation=TransactionCreationIdentity(id(20),at)))}
        val first=planCreditCardStatementPayment(s,r,device,at,zone)
        val saved=apply(s,first).let{input->input.copy(money=input.money.copy(recordsByEntity=input.money.recordsByEntity.mapValues{(_,rows)->rows.map{row->
            if(row.id !in first.mutations.map{it.first.id})row else {
                val fields=JsonObject(row.payload.mapValues{(key,value)->if(value!=JsonNull && key in setOf("created_at","occurred_at","paid_at","updated_at"))JsonPrimitive(cashEventInstant(value.jsonPrimitive.content).toString())else value}+("sync_version" to JsonPrimitive(1L)))
                row.copy(payload=fields,updatedAt=fields.financeRawString("updated_at"),syncVersion=1)
            }
        }}))}
        val replay=planCreditCardStatementPayment(saved,r,device,"2026-10-22T00:00:03Z",zone)
        assertTrue(replay.mutations.isEmpty());assertEquals(id(20),replay.payment.transaction.id)
    }

}
