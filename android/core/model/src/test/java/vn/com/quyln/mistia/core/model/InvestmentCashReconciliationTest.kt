package vn.com.quyln.mistia.core.model

import java.math.BigInteger
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class InvestmentCashReconciliationTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val device="44444444-4444-4444-8444-444444444444"
    private fun id(n:Int)=java.util.UUID(0,n.toLong()).toString()
    private val now="2026-10-22T00:00:00Z"
    private fun n(v:Long)=BigInteger.valueOf(v)
    private fun wallet(key:Int,opening:Long=150,code:String="JPY")=WalletDraft(id=id(key),name="Wallet$key",kind=WalletKind.CASH,currencyCode=code,openingBalanceMinor=opening).toMutation(owner,null,device,now).record
    private fun row(entity:CloudEntity,key:Int,fields:JsonObject)=CloudRecord(entity.table,id(key),owner.value,JsonObject(buildJsonObject {
        put("id",id(key));put("user_id",owner.value);put("created_at",now);put("updated_at",now);put("deleted_at",JsonNull);put("sync_version",0L)
    }+fields),now,null,0)
    private fun cash(key:Int=10,wallet:Int=1,amount:Long=50,local:Long=amount,code:String="JPY")=row(CloudEntity.INVESTMENT_POSTING,key,buildJsonObject {
        put("event_id",id(key+100));put("wallet_id",id(wallet));put("ledger_transaction_id",id(key+100));put("role_raw_value","cashAccrual")
        put("cash_bucket_raw_value","booked");put("cash_origin_raw_value","derived");put("amount_minor",local);put("currency_code",code)
        put("accounting_amount_minor",amount);put("accounting_currency_code","JPY");put("occurred_at",now)
    })
    private fun source(extra:Boolean=false):InvestmentCashReadSnapshot {
        val system=wallet(99,0).let{it.copy(id=investmentSystemWalletId(owner),payload=JsonObject(it.payload+buildJsonObject {
            put("id",investmentSystemWalletId(owner));put("kind_raw_value","investment");put("system_purpose_raw_value","investmentProfit");put("investment_linked_wallet_id",id(2))
        }))}
        return InvestmentCashReadSnapshot(owner,listOf(system,wallet(1),wallet(2,0),cash())+if(extra)listOf(wallet(3,200),cash(11,3,60)) else emptyList())
    }
    private fun request(s:InvestmentCashReadSnapshot=source(),amount:Long=80,all:Boolean=false)=InvestmentCashReconciliationRequest(readInvestmentCashReconciliation(s),
        if(all)listOf(InvestmentCashReconciliationTransfer(id(20),id(1),80),InvestmentCashReconciliationTransfer(id(21),id(3),100)) else listOf(InvestmentCashReconciliationTransfer(id(20),id(1),amount)),now,now,"Reconciliation",true)
    private fun plan(s:InvestmentCashReadSnapshot=source(),r:InvestmentCashReconciliationRequest=request(s))=planInvestmentCashReconciliation(s,r,device,now)
    private fun after(s:InvestmentCashReadSnapshot,p:InvestmentCashReconciliationPlan)=s.copy(rows=s.rows+p.mutations.map{it.first})
    private fun CloudRecord.with(k:String,v:JsonElement)=copy(payload=JsonObject(payload+(k to v)))
    private fun fails(reason:InvestmentCashReconciliationError,action:()->Unit)=assertEquals(reason,(runCatching(action).exceptionOrNull() as? InvestmentCashReconciliationException)?.reason)

    @Test fun realEightyMovesActualCashWhileOnlyFiftyBookedProfitMovesAndThreeQueuesMatchSourceIdentities() {
        val s=source();val result=plan(s);assertEquals(3,result.mutations.size)
        val a=after(s,result);val balances=financeWalletBalancesRaw(owner,a.rows.filter{it.entity==CloudEntity.LEDGER_TRANSACTION.table},a.rows.filter{it.entity==CloudEntity.LEDGER_WALLET.table})!!
        assertEquals(n(70),balances[id(1)]);assertEquals(n(80),balances[id(2)])
        val allocation=investmentCashAllocation(a.walletSnapshot(),"JPY");assertEquals(n(50),allocation.totalMinor)
        assertEquals(n(50),allocation.locations.single{it.walletId==id(2)}.bookedMinor)
        val ledger=result.mutations.single{it.first.entity==CloudEntity.LEDGER_TRANSACTION.table}.first
        assertEquals(investmentLedgerIdentity(id(20),"cash-reconciliation"),ledger.id);assertEquals("investmentReconciliation",ledger.payload.financeRawString("settlement_role_raw_value"))
        assertEquals(80L,ledger.payload.financeRawLong("amount_minor"));assertEquals(80L,ledger.payload.financeRawLong("destination_amount_minor"))
        assertEquals(setOf(investmentLedgerIdentity(id(20),"holder-cash-posting"),investmentLedgerIdentity(id(20),"linked-cash-posting")),result.mutations.filter{it.first.entity==CloudEntity.INVESTMENT_POSTING.table}.map{it.first.id}.toSet())
        assertTrue(result.mutations.all{(row,q)->row.ownerUserId==owner.value && q.subjectUserId==owner.value && q.payload==row.payload && q.kind==MutationKind.UPSERT && q.baseVersion==0L})
        assertTrue(result.mutations.none{it.first.entity==CloudEntity.LEDGER_WALLET.table || it.first.entity==CloudEntity.INVESTMENT_TRADE.table})
    }
    @Test fun allSourcesPlanAsOneSixRowBatchAndExactReplayWorksAfterAllSourceAllocationIsExhausted() {
        val s=source(true);val r=request(s,all=true);val p=plan(s,r);assertEquals(6,p.mutations.size)
        val a=after(s,p);assertEquals(n(110),investmentCashAllocation(a.walletSnapshot(),"JPY").locations.single().bookedMinor)
        assertTrue(plan(a,r).mutations.isEmpty())
    }
    @Test fun explicitRealTransferConfirmationAndActualBalanceLimitsAreRequiredBeforeAnyPlan() {
        val s=source();val r=request(s)
        fails(InvestmentCashReconciliationError.CONFIRMATION_REQUIRED){plan(s,r.copy(confirmedRealTransfer=false))}
        fails(InvestmentCashReconciliationError.EXCEEDS_BALANCE){plan(s,request(s,151))}
        assertEquals(3,plan(s,request(s,150)).mutations.size)
        fails(InvestmentCashReconciliationError.INVALID_INPUT){plan(s,request(s,0))}
    }
    @Test fun foreignHolderIsExcludedWhileForeignLinkedAccountingOrSameCurrencyContradictionsHold() {
        val s=source(true);val foreign=s.copy(rows=s.rows.map{when(it.id){id(3)->it.with("currency_code",JsonPrimitive("VND"));id(11)->it.with("currency_code",JsonPrimitive("VND"));else->it}})
        assertEquals(listOf(id(1)),readInvestmentCashReconciliation(foreign).locations.map{it.wallet.id})
        fails(InvestmentCashReconciliationError.STALE_RECORD){plan(foreign,request(s,all=true))}
        fails(InvestmentCashReconciliationError.INVALID_WALLET){readInvestmentCashReconciliation(s.copy(rows=s.rows.map{if(it.id==id(2))it.with("currency_code",JsonPrimitive("VND")) else it}))}
        fails(InvestmentCashReconciliationError.UNREADABLE_SOURCE){readInvestmentCashReconciliation(s.copy(rows=s.rows.map{if(it.id==id(10))it.with("amount_minor",JsonPrimitive(51L)) else it}))}
    }
    @Test fun partialTamperedOrImportedEventCollisionIsNeverRepairedAsASecondTransfer() {
        val s=source();val r=request(s);val p=plan(s,r)
        for(i in p.mutations.indices)fails(InvestmentCashReconciliationError.EVENT_CONFLICT){plan(s.copy(rows=s.rows+p.mutations.take(i+1).dropLast(if(i==2)1 else 0).map{it.first}),r)}
        val a=after(s,p);val changed=a.copy(rows=a.rows.map{if(it.id==p.mutations.first().first.id)it.with("amount_minor",JsonPrimitive(81L)) else it})
        fails(InvestmentCashReconciliationError.EVENT_CONFLICT){plan(changed,r)}
        val collision=cash(12).with("event_id",JsonPrimitive(id(20)))
        fails(InvestmentCashReconciliationError.EVENT_CONFLICT){plan(s.copy(rows=s.rows+collision),r)}
    }
    @Test fun financialConsentIsFrozenButMetadataAckCanAdvanceWithoutOverwritingWallets() {
        val s=source();val r=request(s)
        val changed=s.copy(rows=s.rows.map{if(it.id==id(1))it.with("opening_balance_minor",JsonPrimitive(151L)) else it})
        fails(InvestmentCashReconciliationError.STALE_RECORD){plan(changed,r)}
        val acknowledged=s.copy(rows=s.rows.map{it.copy(syncVersion=9007199254740993L,payload=JsonObject(it.payload+("sync_version" to JsonPrimitive(9007199254740993L))))})
        assertEquals(3,plan(acknowledged,r).mutations.size)
        assertEquals(9007199254740993L,acknowledged.rows.first().syncVersion)
    }
    @Test fun allAmountsRemainExactBeyondLongReadLimitsAndSinglePartialWireAmountStaysValid() {
        val s=source().let{it.copy(rows=it.rows.map{row->if(row.id==id(1))row.with("opening_balance_minor",JsonPrimitive(Long.MAX_VALUE)) else row}+cash(11,amount=Long.MAX_VALUE-50))}
        assertEquals(n(Long.MAX_VALUE),readInvestmentCashReconciliation(s).locations.single().bookedMinor)
        assertEquals(3,plan(s,request(s,Long.MAX_VALUE)).mutations.size)
        val huge=s.copy(rows=s.rows+cash(12,amount=50));assertEquals(n(Long.MAX_VALUE)+n(50),readInvestmentCashReconciliation(huge).locations.single().bookedMinor)
        assertEquals(3,plan(huge,request(huge,50)).mutations.size)
    }
    @Test fun ownerDuplicatesMalformedReferencesAndRepeatedBatchSourcesNeverProduceAPartialPlan() {
        val s=source();val r=request(s)
        fails(InvestmentCashReconciliationError.INVALID_INPUT){plan(s,r.copy(transfers=r.transfers+r.transfers))}
        fails(InvestmentCashReconciliationError.UNREADABLE_SOURCE){readInvestmentCashReconciliation(s.copy(rows=s.rows+s.rows.first()))}
        fails(InvestmentCashReconciliationError.UNREADABLE_SOURCE){readInvestmentCashReconciliation(s.copy(rows=s.rows.map{it.with("user_id",JsonPrimitive(id(99)))}))}
        fails(InvestmentCashReconciliationError.UNREADABLE_SOURCE){readInvestmentCashReconciliation(s.copy(rows=s.rows.map{if(it.id==id(10))it.with("accounting_amount_minor",JsonPrimitive("50")) else it}))}
    }
    @Test fun consumedCashEventReferencesRoleOriginAndDatesMustBeReadableBeforeAnyReconciliation() {
        val s=source()
        for((key,value) in listOf("event_id" to JsonPrimitive("bad"),"ledger_transaction_id" to JsonNull,"role_raw_value" to JsonPrimitive("unknown"),
            "cash_origin_raw_value" to JsonPrimitive("unknown"),"occurred_at" to JsonPrimitive("bad"))) {
            fails(InvestmentCashReconciliationError.UNREADABLE_SOURCE){readInvestmentCashReconciliation(s.copy(rows=s.rows.map{if(it.id==id(10))it.with(key,value) else it}))}
        }
    }
    @Test fun completeReplayAcceptsAckMetadataButNeverTamperedFinancialBindingsOrACompletedPrefixOfABatch() {
        val s=source(true);val r=request(s,all=true);val p=plan(s,r)
        val a=after(s,p).let{it.copy(rows=it.rows.map{row->if(row.id in p.mutations.map{it.first.id})row.copy(syncVersion=9007199254740993L,payload=JsonObject(row.payload+buildJsonObject{put("sync_version",9007199254740993L);put("last_modified_by_device_id",id(999));put("future_field","keep")})) else row})}
        assertTrue(plan(a,r).mutations.isEmpty())
        val ledgerId=investmentLedgerIdentity(id(20),"cash-reconciliation")
        fails(InvestmentCashReconciliationError.EVENT_CONFLICT){plan(a.copy(rows=a.rows.map{if(it.id==ledgerId)it.with("category_id",JsonPrimitive(id(88))) else it}),r)}
        fails(InvestmentCashReconciliationError.EVENT_CONFLICT){plan(s.copy(rows=s.rows+p.mutations.take(3).map{it.first}),r)}
    }
}
