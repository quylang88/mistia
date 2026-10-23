package vn.com.quyln.mistia.core.model

import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class TransactionInvestmentSavePlanTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val device="44444444-4444-4444-8444-444444444444"
    private val now="2026-10-22T00:00:00Z"
    private val later="2026-10-22T00:01:00Z"
    private fun id(n:Int)=java.util.UUID(0,n.toLong()).toString()
    private fun wallet(n:Int,opening:Long=100,kind:WalletKind=WalletKind.CASH)=WalletDraft(id=id(n),name="Wallet$n",kind=kind,currencyCode="JPY",openingBalanceMinor=opening).toMutation(owner,null,device,now).record
    private fun categories():List<CloudRecord> = TransactionCategoryKind.entries.flatMap { kind ->
        val key=if(kind==TransactionCategoryKind.EXPENSE)30 else 40
        val parent=CategoryDraft(id=id(key),name="Parent",kind=kind,hierarchyRole=CategoryHierarchyRole.PARENT).toMutation(owner,null,null,device,now).record
        listOf(parent.toCloudRecord(),CategoryDraft(id=id(key+1),name="Child",kind=kind,hierarchyRole=CategoryHierarchyRole.CHILD,parentCategoryId=parent.id).toMutation(owner,null,parent,device,now).record.toCloudRecord())
    }
    private fun draft(amount:Long=70,kind:TransactionPrimaryKind=TransactionPrimaryKind.EXPENSE)=TransactionDraft(primaryKind=kind,title="Expense",amountMinor=amount,occurredAt="2026-10-22T00:00:02Z",sourceWalletId=id(1),categoryId=id(if(kind==TransactionPrimaryKind.INCOME)41 else 31))
    private fun row(kind:TransactionPrimaryKind,amount:Long,n:Int)=draft(amount,kind).copy(id=id(n)).toMutation(owner,null,LedgerWalletRecord.fromCloudRecord(wallet(1)),null,
        TransactionCategoryRecord.fromCloudRecord(categories().single{it.id==id(if(kind==TransactionPrimaryKind.INCOME)41 else 31)}),device,now).record.toCloudRecord()
    private fun snapshot(opening:Long=100,reserve:Long=0,additional:List<CloudRecord> = emptyList()):TransactionInvestmentSaveSnapshot {
        val system=wallet(99).let{it.copy(id=investmentSystemWalletId(owner),payload=JsonObject(it.payload+buildJsonObject{put("id",investmentSystemWalletId(owner));put("kind_raw_value","investment");put("system_purpose_raw_value","investmentProfit")}))}
        val posting=CloudRecord(CloudEntity.INVESTMENT_POSTING.table,id(10),owner.value,buildJsonObject {
            put("id",id(10));put("user_id",owner.value);put("sync_version",0L);put("deleted_at",JsonNull);put("created_at",now);put("updated_at",now)
            put("event_id",id(11));put("ledger_transaction_id",id(11));put("wallet_id",id(1));put("role_raw_value","cashAccrual");put("cash_bucket_raw_value","booked");put("cash_origin_raw_value","derived")
            put("amount_minor",reserve);put("accounting_amount_minor",reserve);put("currency_code","JPY");put("accounting_currency_code","JPY");put("occurred_at","2026-10-22T00:00:01Z")
        },now,null,0)
        val rows=listOf(wallet(1,opening),system)+categories()+(if(reserve>0)listOf(posting)else emptyList())+additional
        return TransactionInvestmentSaveSnapshot(owner,TransactionInvestmentSaveSnapshot.entities.associateWith{entity->rows.filter{it.entity==entity.table}})
    }
    private fun request(draft:TransactionDraft=draft(),consent:InvestmentFundUsageConsent?=null)=TransactionInvestmentSaveRequest(draft,if(draft.id==null)TransactionCreationIdentity(id(20),now)else null,consent,"Automatic adjustment","JPY")
    private fun plan(s:TransactionInvestmentSaveSnapshot,r:TransactionInvestmentSaveRequest=request(),at:String=now)=planTransactionInvestmentSave(s,r,device,at)
    private fun apply(s:TransactionInvestmentSaveSnapshot,p:TransactionInvestmentSavePlan):TransactionInvestmentSaveSnapshot {
        val writes=p.mutations.map{it.first};return s.copy(recordsByEntity=s.recordsByEntity.mapValues{(entity,rows)->rows.filter{old->writes.none{it.entity==entity.table && it.id==old.id}}+writes.filter{it.entity==entity.table}})
    }
    @Test fun creationKeepsSeparateStableIdentityAndFirstTimestampAcrossRetries() {
        val r=request();val p=plan(snapshot(),r,later)
        assertNull(r.draft.id);assertEquals(id(20),p.record.id);assertEquals(now,p.record.createdAt);assertEquals(later,p.record.updatedAt)
        assertEquals(1,p.mutations.size);assertEquals(p.record.toPayload(),p.mutations.single().second.payload)
    }
    @Test fun consentProducesPrimaryAndThirtyReservedMinorInOnePlan() {
        val s=snapshot(reserve=60)
        val review=(runCatching{plan(s)}.exceptionOrNull() as InvestmentFundUsageConfirmationRequired).review
        val p=plan(s,request(consent=review.consent));assertEquals(2,p.mutations.size)
        assertEquals(setOf(CloudEntity.LEDGER_TRANSACTION.table,CloudEntity.INVESTMENT_POSTING.table),p.mutations.map{it.first.entity}.toSet())
        assertEquals(-30L,p.mutations.single{it.first.entity==CloudEntity.INVESTMENT_POSTING.table}.first.payload.financeRawLong("amount_minor"))
    }
    @Test fun completedCreationAfterAckReturnsNoWritesEvenWhenBalanceIsNowInsufficient() {
        val s=snapshot(reserve=60);val consent=(runCatching{plan(s)}.exceptionOrNull() as InvestmentFundUsageConfirmationRequired).review.consent
        val p=plan(s,request(consent=consent));val saved=apply(s,p).let{it.copy(recordsByEntity=it.recordsByEntity.mapValues{(_,rows)->rows.map{row->row.copy(syncVersion=9007199254740993L,payload=JsonObject(row.payload+buildJsonObject{put("sync_version",9007199254740993L);put("updated_at",later);put("last_modified_by_device_id",id(77))}),updatedAt=later)}})}
        val retry=plan(saved,request(consent=consent),later);assertTrue(retry.mutations.isEmpty());assertEquals(9007199254740993L,retry.record.syncVersion)
    }
    @Test fun occupiedCreationAndMissingEditCannotBecomeAccidentalUpdatesOrCreates() {
        val s=snapshot(additional=listOf(row(TransactionPrimaryKind.EXPENSE,1,20)))
        assertEquals(InvestmentFundUsageError.EVENT_CONFLICT,(runCatching{plan(s)}.exceptionOrNull() as? InvestmentFundUsageException)?.reason)
        assertEquals(InvestmentFundUsageError.EVENT_CONFLICT,(runCatching{plan(snapshot(),request(draft().copy(id=id(21))))}.exceptionOrNull() as? InvestmentFundUsageException)?.reason)
    }
    @Test fun editingPreservesUnknownPrimaryFieldsVersionAndOriginalCreator() {
        val old=row(TransactionPrimaryKind.EXPENSE,70,20).let{it.copy(syncVersion=9007199254740993L,payload=JsonObject(it.payload+buildJsonObject{put("future_field",buildJsonObject{put("keep",true)});put("sync_version",9007199254740993L);put("created_by_user_id",id(77))}))}
        val p=plan(snapshot(additional=listOf(old)),request(draft(50).copy(id=id(20))),later)
        val raw=p.mutations.single().first;assertEquals(old.payload["future_field"],raw.payload["future_field"]);assertEquals(old.payload["created_by_user_id"],raw.payload["created_by_user_id"])
        assertEquals(9007199254740993L,p.mutations.single().second.baseVersion);assertEquals(now,p.record.createdAt)
    }
    @Test fun exactCashAboveLongRangeRemainsSpendableAfterIncomeAndExpense() {
        val s=snapshot(Long.MAX_VALUE,additional=listOf(row(TransactionPrimaryKind.INCOME,200,51),row(TransactionPrimaryKind.EXPENSE,100,52)))
        assertEquals(Long.MAX_VALUE,plan(s,request(draft(Long.MAX_VALUE))).record.amountMinor)
    }
    @Test fun exactCreditDebtAboveLimitCannotBecomeAvailableAfterSaturatingThenRepaying() {
        val card=wallet(1,0).let{it.copy(payload=JsonObject(it.payload+("kind_raw_value" to JsonPrimitive("creditCard"))))}
        val profile=CreditCardProfileRecord(id(60),owner.value,"Issuer","visa","1234",Long.MAX_VALUE,10,26,null,id(1),null,true,now,now,null,0,device).toCloudRecord()
        val payment=row(TransactionPrimaryKind.INCOME,100,53).let{it.copy(payload=JsonObject(it.payload+buildJsonObject{put("primary_kind_raw_value","transfer");put("transfer_subtype_raw_value","internalTransfer");put("source_wallet_id",investmentSystemWalletId(owner));put("destination_wallet_id",id(1));put("destination_amount_minor",100L);put("destination_currency_code","JPY");put("category_id",JsonNull)}))}
        val s=snapshot(additional=listOf(row(TransactionPrimaryKind.EXPENSE,Long.MAX_VALUE,51),row(TransactionPrimaryKind.EXPENSE,200,52),payment,profile)).let{it.copy(recordsByEntity=it.recordsByEntity+ (CloudEntity.LEDGER_WALLET to listOf(card)+it.recordsByEntity.getValue(CloudEntity.LEDGER_WALLET).filterNot{r->r.id==id(1)}))}
        val error=runCatching{plan(s,request(draft(1)))}.exceptionOrNull()
        assertTrue(error.toString(),error is TransactionValidationException);assertEquals(TransactionValidationError.CREDIT_LIMIT_EXCEEDED,(error as TransactionValidationException).reason)
    }
    @Test fun exactAffordableCardChargeDoesNotOverflowThePaidStatementGuard() {
        val card=wallet(1,0).let{it.copy(payload=JsonObject(it.payload+("kind_raw_value" to JsonPrimitive("creditCard"))))}
        val profile=CreditCardProfileRecord(id(60),owner.value,"Issuer","visa","1234",Long.MAX_VALUE,10,26,null,id(1),null,true,now,now,null,0,device).toCloudRecord()
        val payment=row(TransactionPrimaryKind.INCOME,300,53).let{it.copy(payload=JsonObject(it.payload+buildJsonObject{put("primary_kind_raw_value","transfer");put("transfer_subtype_raw_value","internalTransfer");put("source_wallet_id",investmentSystemWalletId(owner));put("destination_wallet_id",id(1));put("destination_amount_minor",300L);put("destination_currency_code","JPY");put("category_id",JsonNull)}))}
        val s=snapshot(additional=listOf(row(TransactionPrimaryKind.EXPENSE,Long.MAX_VALUE,51),row(TransactionPrimaryKind.EXPENSE,200,52),payment,profile)).let{it.copy(recordsByEntity=it.recordsByEntity+(CloudEntity.LEDGER_WALLET to listOf(card)+it.recordsByEntity.getValue(CloudEntity.LEDGER_WALLET).filterNot{r->r.id==id(1)}))}
        assertEquals(1L,plan(s,request(draft(1))).record.amountMinor)
    }
    @Test fun existingPaidOccurrenceStillLocksAnEditAtTheNewCombinedBoundary() {
        val old=row(TransactionPrimaryKind.EXPENSE,70,20)
        val occurrence=old.copy(entity=CloudEntity.DUE_OCCURRENCE_RECORD.table,id=id(71),payload=JsonObject(old.payload+buildJsonObject{put("id",id(71));put("source_kind_raw_value","creditCard");put("source_id",id(1));put("status_raw_value","paid");put("linked_transaction_id",old.id)}))
        val error=runCatching{plan(snapshot(additional=listOf(old,occurrence)),request(draft(50).copy(id=old.id)))}.exceptionOrNull()
        assertEquals(TransactionValidationError.PAID_CREDIT_CARD_STATEMENT,(error as? TransactionValidationException)?.reason)
    }
    private fun foreignReserve():TransactionInvestmentSaveSnapshot {
        val base=snapshot(100_000,2)
        return base.copy(recordsByEntity=base.recordsByEntity.mapValues{(entity,rows)->rows.map{row->when {
            entity==CloudEntity.LEDGER_WALLET && row.id==id(1)->row.copy(payload=JsonObject(row.payload+("currency_code" to JsonPrimitive("VND"))))
            entity==CloudEntity.INVESTMENT_POSTING->row.copy(payload=JsonObject(row.payload+buildJsonObject{put("currency_code","VND");put("amount_minor",40_000L)}))
            else->row
        }}}+(CloudEntity.LEDGER_WALLET to (base.recordsByEntity.getValue(CloudEntity.LEDGER_WALLET).map{row->if(row.id==id(1))row.copy(payload=JsonObject(row.payload+("currency_code" to JsonPrimitive("VND"))))else row}+wallet(2,0))))
    }
    @Test fun foreignReserveDoesNotBlockFxThatUsesOnlyOrdinaryLocalMoney() {
        val d=TransactionDraft(primaryKind=TransactionPrimaryKind.TRANSFER,transferSubtype=TransactionTransferSubtype.INTERNAL_TRANSFER,title="FX",amountMinor=50_000,occurredAt="2026-10-22T00:00:02Z",sourceWalletId=id(1),destinationWalletId=id(2),destinationAmountMinor=1_000,conversionMode=CurrencyConversionMode.MANUAL)
        val p=plan(foreignReserve(),request(d))
        assertEquals(1,p.mutations.size);assertEquals("VND",p.record.sourceCurrencyCode);assertEquals("JPY",p.record.destinationCurrencyCode);assertEquals(1_000L,p.record.destinationAmountMinor)
    }
    @Test fun foreignReserveSpendingIsBlockedUsingLocalEarmarksRatherThanAccountingMinor() {
        val error=runCatching{plan(foreignReserve(),request(draft(70_000)))}.exceptionOrNull()
        assertEquals(InvestmentFundUsageError.CURRENCY_MISMATCH,(error as? InvestmentFundUsageException)?.reason)
    }
    @Test fun sameCurrencyReservedMoneyCannotBeCarriedThroughAForeignFxDestination() {
        val s=snapshot(reserve=60,additional=listOf(wallet(2,0).let{it.copy(payload=JsonObject(it.payload+("currency_code" to JsonPrimitive("VND"))))}))
        val d=TransactionDraft(primaryKind=TransactionPrimaryKind.TRANSFER,transferSubtype=TransactionTransferSubtype.INTERNAL_TRANSFER,title="FX",amountMinor=70,occurredAt="2026-10-22T00:00:02Z",sourceWalletId=id(1),destinationWalletId=id(2),destinationAmountMinor=70_000,conversionMode=CurrencyConversionMode.MANUAL)
        assertEquals(InvestmentFundUsageError.CURRENCY_MISMATCH,(runCatching{plan(s,request(d))}.exceptionOrNull() as? InvestmentFundUsageException)?.reason)
    }
    @Test fun unrelatedForeignReserveCannotBlockAnOrdinarySameCurrencySave() {
        val base=foreignReserve();val wallets=base.recordsByEntity.getValue(CloudEntity.LEDGER_WALLET).map{if(it.id==id(2))it.copy(payload=JsonObject(it.payload+("opening_balance_minor" to JsonPrimitive(100L))))else it}
        val s=base.copy(recordsByEntity=base.recordsByEntity+(CloudEntity.LEDGER_WALLET to wallets))
        assertEquals(1,plan(s,request(draft(50).copy(sourceWalletId=id(2)))).mutations.size)
    }
}
