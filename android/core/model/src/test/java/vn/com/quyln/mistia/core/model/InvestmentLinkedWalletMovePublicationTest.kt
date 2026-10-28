package vn.com.quyln.mistia.core.model

import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class InvestmentLinkedWalletMovePublicationTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val device="44444444-4444-4444-8444-444444444444"
    private fun id(n:Int)=java.util.UUID(0,n.toLong()).toString()
    private val event=id(20)
    private val now="2026-10-28T00:00:00Z"
    private fun source():InvestmentCashEventPublicationSnapshot {
        fun wallet(n:Int)=WalletDraft(id=id(n),name="Wallet$n",kind=WalletKind.CASH,currencyCode="JPY",openingBalanceMinor=150).toMutation(owner,null,device,now).record
        val root=wallet(99).let{it.copy(id=investmentSystemWalletId(owner),payload=JsonObject(it.payload+buildJsonObject {
            put("id",investmentSystemWalletId(owner));put("kind_raw_value","investment");put("system_purpose_raw_value","investmentProfit");put("investment_linked_wallet_id",id(1));put("opening_balance_minor",0)
        }))}
        val cash=CloudRecord(CloudEntity.INVESTMENT_POSTING.table,id(10),owner.value,buildJsonObject {
            put("id",id(10));put("user_id",owner.value);put("created_at",now);put("updated_at",now);put("deleted_at",JsonNull);put("sync_version",1L)
            put("event_id",id(110));put("wallet_id",id(1));put("ledger_transaction_id",id(110));put("role_raw_value","cashAccrual")
            put("cash_bucket_raw_value","booked");put("cash_origin_raw_value","derived");put("amount_minor",50L);put("accounting_amount_minor",50L)
            put("currency_code","JPY");put("accounting_currency_code","JPY");put("occurred_at",now)
        },now,null,1)
        val before=InvestmentWalletSnapshot(owner,listOf(root,wallet(1),wallet(2),cash))
        val plan=planInvestmentWalletLink(before,InvestmentWalletLinkRequest(LedgerWalletRecord.fromCloudRecord(root),LedgerWalletRecord.fromCloudRecord(before.rows.single{it.id==id(2)}),event,true,50,"Change and transfer all"),device,now)
        val changed=plan.mutations.map{it.first}.associateBy{it.entity to it.id}
        val rows=before.rows.map{changed[it.entity to it.id] ?: it}+changed.values.filter{row->before.rows.none{it.entity==row.entity && it.id==row.id}}
        val queues=plan.mutations.map{QueuedMutation(it.second,0,0,null)}
        return InvestmentCashEventPublicationSnapshot(owner,event,rows,queues,queues.map{it.mutation.entity.table to it.mutation.recordId}.toSet())
    }
    private fun remote(row:CloudRecord,v:Long=9007199254740993L)=row.copy(syncVersion=v,updatedAt="2026-10-28T00:30:00Z",payload=JsonObject(row.payload+buildJsonObject{put("sync_version",v);put("updated_at","2026-10-28T00:30:00Z")}))
    private fun candidate(s:InvestmentCashEventPublicationSnapshot):InvestmentLinkedWalletMoveCloudSnapshot {
        val relevant=s.rows.filter{it.entity!=CloudEntity.LEDGER_WALLET.table && it.id in s.pending.map{q->q.mutation.recordId}}.map{remote(it)}
        return InvestmentLinkedWalletMoveCloudSnapshot(owner,event,relevant.single{it.entity==CloudEntity.LEDGER_TRANSACTION.table},relevant.filter{it.entity==CloudEntity.INVESTMENT_POSTING.table})
    }
    private fun CloudRecord.with(key:String,value:JsonElement)=copy(payload=JsonObject(payload+(key to value)))
    @Test fun actualMoveHasOneRealFiftyTransferAndOppositeFullBookAmountsWhileRootQueueStaysSeparate() {
        val s=source();val c=candidate(s);val result=planInvestmentLinkedWalletMoveAcknowledgement(s,c)
        assertEquals(4,s.pending.size);assertEquals(3,result.imports.size);assertEquals(3,result.acknowledgements.size)
        assertTrue(result.acknowledgements.none{it.first.mutation.entity==CloudEntity.LEDGER_WALLET});assertTrue(result.absentAcknowledgements.isEmpty())
        assertEquals(50L,c.ledger!!.payload.financeRawLong("amount_minor"));assertEquals(setOf(-50L,50L),c.postings.map{it.payload.financeRawLong("amount_minor")}.toSet())
        assertTrue(result.imports.all{it.syncVersion==9007199254740993L})
    }
    @Test fun partialBookedPairCannotUseTheReconciliationRealGreaterThanBookedRule() {
        val s=source();val c=candidate(s);val partial=c.copy(postings=c.postings.map{row->
            val sign=if(row.payload.financeRawLong("amount_minor")!!<0)-1 else 1
            row.with("amount_minor",JsonPrimitive(sign*30)).with("accounting_amount_minor",JsonPrimitive(sign*30))
        })
        assertTrue(runCatching{planInvestmentLinkedWalletMoveAcknowledgement(s,partial)}.isFailure)
    }
    @Test fun incompleteForeignPrivateTombstoneOrOtherDomainIdentityNeverAcknowledges() {
        val s=source();val c=candidate(s);val ledger=c.ledger!!
        val wrongId=investmentLedgerIdentity(event,"cash-reconciliation")
        val wrongLedger=ledger.copy(id=wrongId,payload=JsonObject(ledger.payload+("id" to JsonPrimitive(wrongId))))
        val invalid=listOf(
            c.copy(ledger=null),c.copy(postings=c.postings.take(1)),c.copy(postings=c.postings+c.postings.first()),c.copy(owner=UserId(device)),c.copy(eventId=id(21)),c.copy(ledger=wrongLedger),
            c.copy(postings=c.postings.map{it.with("role_raw_value",JsonPrimitive("cashReconciliation"))}),
            c.copy(postings=c.postings.map{it.with("cash_origin_raw_value",JsonPrimitive("derived"))}),
            c.copy(postings=c.postings.map{it.with("_mistia_android_fake",JsonPrimitive(true))}),
            c.copy(postings=c.postings.map{it.with("user_id",JsonPrimitive(device))}),
            c.copy(postings=c.postings.map{it.with("currency_code",JsonPrimitive("VND"))}),
            c.copy(postings=c.postings.map{it.copy(deletedAt=now,payload=JsonObject(it.payload+("deleted_at" to JsonPrimitive(now))))})
        )
        for(value in invalid)assertTrue(runCatching{planInvestmentLinkedWalletMoveAcknowledgement(s,value)}.isFailure)
    }
    @Test fun cleanLedgerAndOnlyOneRemainingPostingRecoverWithoutTouchingRootOrOtherQueues() {
        val s=source();val c=candidate(s);val clean=c.ledger!!
        val pending=s.pending.filter{it.mutation.entity==CloudEntity.LEDGER_WALLET || it.mutation.recordId==c.postings.first().id}
        val changed=s.copy(rows=s.rows.map{if(it.id==clean.id)clean else it},pending=pending,dirtyKeys=pending.map{it.mutation.entity.table to it.mutation.recordId}.toSet())
        val result=planInvestmentLinkedWalletMoveAcknowledgement(changed,c)
        assertEquals(1,result.acknowledgements.size);assertEquals(CloudEntity.INVESTMENT_POSTING,result.acknowledgements.single().first.mutation.entity)
    }
    @Test fun immutableBusinessOpaqueCreationAndVersionChangesNeverSilentlyWin() {
        val s=source();val c=candidate(s);val ledger=c.ledger!!
        for(row in listOf(ledger.with("title",JsonPrimitive("Different")),ledger.with("created_at",JsonPrimitive("2026-10-27T00:00:00Z")),ledger.with("future_null",JsonNull)))
            assertTrue(runCatching{planInvestmentLinkedWalletMoveAcknowledgement(s,c.copy(ledger=row))}.isFailure)
        val known=s.copy(rows=s.rows.map{if(it.id==ledger.id)remote(it,Long.MAX_VALUE-1) else it},pending=s.pending.map{q->if(q.mutation.recordId==ledger.id){val row=remote(s.rows.single{it.id==ledger.id},Long.MAX_VALUE-1);q.copy(mutation=q.mutation.copy(payload=row.payload,baseVersion=row.syncVersion,modifiedAt=row.updatedAt!!))}else q})
        assertTrue(runCatching{planInvestmentLinkedWalletMoveAcknowledgement(known,c)}.isFailure)
    }    @Test fun currentAccountingCurrencyCannotBeBypassedByAnOtherwiseMatchingRealTransferAndPair() {
        val source=source();val c=candidate(source);val rootId=investmentSystemWalletId(owner)
        val root=source.rows.single{it.id==rootId}.with("currency_code",JsonPrimitive("VND"))
        val s=source.copy(rows=source.rows.map{if(it.id==rootId)root else it},pending=source.pending.map{q->if(q.mutation.recordId==rootId)q.copy(mutation=q.mutation.copy(payload=root.payload)) else q})
        assertTrue(runCatching{planInvestmentLinkedWalletMoveAcknowledgement(s,c)}.isFailure)
    }

}
