package vn.com.quyln.mistia.core.model

import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class InvestmentCashReconciliationPublicationTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val device="44444444-4444-4444-8444-444444444444"
    private fun id(n:Int)=java.util.UUID(0,n.toLong()).toString()
    private val event=id(20)
    private val now="2026-10-27T00:00:00Z"
    private fun source(amount:Long=80):InvestmentCashEventPublicationSnapshot {
        fun wallet(n:Int)=WalletDraft(id=id(n),name="Wallet$n",kind=WalletKind.CASH,currencyCode="JPY",openingBalanceMinor=150).toMutation(owner,null,device,now).record
        val system=wallet(99).let{it.copy(id=investmentSystemWalletId(owner),payload=JsonObject(it.payload+buildJsonObject {
            put("id",investmentSystemWalletId(owner));put("kind_raw_value","investment");put("system_purpose_raw_value","investmentProfit");put("investment_linked_wallet_id",id(2))
        }))}
        val cash=CloudRecord(CloudEntity.INVESTMENT_POSTING.table,id(10),owner.value,buildJsonObject {
            put("id",id(10));put("user_id",owner.value);put("created_at",now);put("updated_at",now);put("deleted_at",JsonNull);put("sync_version",1L)
            put("event_id",id(110));put("wallet_id",id(1));put("ledger_transaction_id",id(110));put("role_raw_value","cashAccrual")
            put("cash_bucket_raw_value","booked");put("cash_origin_raw_value","derived");put("amount_minor",50L);put("accounting_amount_minor",50L)
            put("currency_code","JPY");put("accounting_currency_code","JPY");put("occurred_at",now)
        },now,null,1)
        val before=InvestmentCashReadSnapshot(owner,listOf(system,wallet(1),wallet(2),cash))
        val plan=planInvestmentCashReconciliation(before,InvestmentCashReconciliationRequest(readInvestmentCashReconciliation(before),
            listOf(InvestmentCashReconciliationTransfer(event,id(1),amount)),now,now,"Reconciliation",true),device,now)
        val queues=plan.mutations.map{QueuedMutation(it.second,0,0,null)}
        return InvestmentCashEventPublicationSnapshot(owner,event,before.rows+plan.mutations.map{it.first},queues,queues.map{it.mutation.entity.table to it.mutation.recordId}.toSet())
    }
    private fun remote(row:CloudRecord,v:Long=9007199254740993L)=row.copy(syncVersion=v,payload=JsonObject(row.payload+buildJsonObject{put("sync_version",v);put("updated_at","2026-10-27T00:30:00Z")} ),updatedAt="2026-10-27T00:30:00Z")
    private fun candidate(s:InvestmentCashEventPublicationSnapshot):InvestmentCashReconciliationCloudSnapshot {
        val rows=s.rows.filter{it.id in s.pending.map{q->q.mutation.recordId}}.map{remote(it)}
        return InvestmentCashReconciliationCloudSnapshot(owner,event,rows.single{it.entity==CloudEntity.LEDGER_TRANSACTION.table},rows.filter{it.entity==CloudEntity.INVESTMENT_POSTING.table})
    }
    private fun CloudRecord.with(key:String,value:JsonElement)=copy(payload=JsonObject(payload+(key to value)))
    @Test fun actualEightyAndBookedFiftyAreProvedAndAcknowledgedTogether() {
        val s=source();val c=candidate(s);val p=planInvestmentCashReconciliationAcknowledgement(s,c)
        assertEquals(3,p.imports.size);assertEquals(3,p.acknowledgements.size);assertTrue(p.absentAcknowledgements.isEmpty())
        assertEquals(80L,c.ledger!!.payload.financeRawLong("amount_minor"));assertEquals(setOf(-50L,50L),c.postings.map{it.payload.financeRawLong("amount_minor")}.toSet())
        assertTrue(p.imports.all{it.syncVersion==9007199254740993L})
    }
    @Test fun partialThirtyKeepsExactSameCurrencyUnits() {
        val s=source(30);val p=planInvestmentCashReconciliationAcknowledgement(s,candidate(s));assertEquals(3,p.imports.size)
        assertEquals(setOf(-30L,30L),p.imports.filter{it.entity==CloudEntity.INVESTMENT_POSTING.table}.map{it.payload.financeRawLong("amount_minor")}.toSet())
    }
    @Test fun missingExtraForeignPrivateTombstoneOrDifferentIntentNeverAcknowledges() {
        val s=source();val c=candidate(s);val first=c.postings.first()
        val bad=listOf(c.copy(ledger=null),c.copy(postings=c.postings.take(1)),c.copy(postings=c.postings+first),
            c.copy(owner=UserId(device)),c.copy(eventId=id(21)),c.copy(ledger=c.ledger!!.with("amount_minor",JsonPrimitive(81))),
            c.copy(postings=c.postings.map{it.with("_mistia_android_unknown",JsonPrimitive(true))}),
            c.copy(postings=c.postings.map{it.with("user_id",JsonPrimitive(device))}),
            c.copy(postings=c.postings.map{it.with("ledger_transaction_id",JsonPrimitive(event))}),
            c.copy(postings=c.postings.map{it.with("accounting_currency_code",JsonPrimitive("VND"))}),
            c.copy(postings=c.postings.map{it.copy(deletedAt=now,payload=JsonObject(it.payload+("deleted_at" to JsonPrimitive(now))))}))
        for(value in bad)assertTrue("accepted malformed reconciliation",runCatching{planInvestmentCashReconciliationAcknowledgement(s,value)}.isFailure)
    }
    @Test fun cleanLedgerAndOneRemainingPostingQueueRecoverWithoutConsumingOtherQueues() {
        val s=source();val c=candidate(s);val clean=c.ledger!!
        val remaining=s.pending.takeLast(1)
        val mixed=s.copy(rows=s.rows.map{if(it.id==clean.id)clean else it},pending=remaining,dirtyKeys=remaining.map{it.mutation.entity.table to it.mutation.recordId}.toSet())
        val p=planInvestmentCashReconciliationAcknowledgement(mixed,c)
        assertEquals(1,p.acknowledgements.size);assertEquals(remaining,p.acknowledgements.map{it.first});assertEquals(3,p.imports.size)
    }
    @Test fun regressedVersionsAndChangedCreationOrOpaqueFieldsAreRejected() {
        val s=source();val c=candidate(s)
        val opaque=s.copy(rows=s.rows.map{if(it.id==c.ledger!!.id)it.with("future_null",JsonNull) else it},pending=s.pending.map{q->if(q.mutation.entity==CloudEntity.LEDGER_TRANSACTION)q.copy(mutation=q.mutation.copy(payload=JsonObject(requireNotNull(q.mutation.payload)+("future_null" to JsonNull)))) else q})
        assertTrue(runCatching{planInvestmentCashReconciliationAcknowledgement(opaque,c)}.isFailure)
        assertTrue(runCatching{planInvestmentCashReconciliationAcknowledgement(s,c.copy(ledger=c.ledger!!.with("created_at",JsonPrimitive("2026-10-26T00:00:00Z"))))}.isFailure)
        val advanced=s.copy(rows=s.rows.map{remote(it,Long.MAX_VALUE-1)},pending=s.pending.map{q->val row=remote(s.rows.single{it.id==q.mutation.recordId},Long.MAX_VALUE-1);q.copy(mutation=q.mutation.copy(payload=row.payload,baseVersion=row.syncVersion,modifiedAt=row.updatedAt!!))})
        assertTrue(runCatching{planInvestmentCashReconciliationAcknowledgement(advanced,c)}.isFailure)
    }
}
