package vn.com.quyln.mistia.core.model

import java.math.BigInteger
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class InvestmentCashTransferLifecycleTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val linkedId="22222222-2222-4222-8222-222222222222"
    private val otherId="33333333-3333-4333-8333-333333333333"
    private val device="44444444-4444-4444-8444-444444444444"
    private val event="55555555-5555-4555-8555-555555555555"
    private val now="2026-10-22T00:00:00Z"
    private val occurred="2026-10-20T12:34:00Z"
    private fun n(value:Long)=BigInteger.valueOf(value)
    private fun wallet(id:String)=WalletDraft(id=id,name="Cash",kind=WalletKind.CASH,currencyCode="VND",openingBalanceMinor=10000).toMutation(owner,null,device,now).record
    private fun row(entity:CloudEntity,id:String,fields:JsonObject)=CloudRecord(entity.table,id,owner.value,JsonObject(fields+buildJsonObject{
        put("id",id);put("user_id",owner.value);put("created_at",now);put("updated_at",now);put("deleted_at",JsonNull);put("sync_version",0L)
    }),now,null,0)
    private fun source():InvestmentCashReadSnapshot {
        val system=wallet(investmentSystemWalletId(owner)).with("kind_raw_value",JsonPrimitive("investment")).with("opening_balance_minor",JsonPrimitive(0L))
            .with("system_purpose_raw_value",JsonPrimitive("investmentProfit")).with("investment_linked_wallet_id",JsonPrimitive(linkedId))
        val profit=row(CloudEntity.INVESTMENT_TRADE,"66666666-6666-4666-8666-666666666666",buildJsonObject{put("realized_profit_loss_minor",800L);put("accounting_currency_code","VND")})
        val cash=row(CloudEntity.INVESTMENT_POSTING,"77777777-7777-4777-8777-777777777777",buildJsonObject{
            put("wallet_id",linkedId);put("role_raw_value","cashAccrual");put("cash_bucket_raw_value","booked");put("cash_origin_raw_value","derived")
            put("amount_minor",300L);put("accounting_amount_minor",300L);put("currency_code","VND");put("accounting_currency_code","VND")
        })
        return InvestmentCashReadSnapshot(owner,listOf(system,wallet(linkedId),wallet(otherId),profit,cash))
    }
    private fun request(snapshot:InvestmentCashReadSnapshot=source(),direction:InvestmentCashTransferDirection=InvestmentCashTransferDirection.DEPOSIT,
        selected:String=linkedId,amount:Long=500):InvestmentCashTransferRequest {
        fun wallet(id:String)=investmentLinkedWalletRecord(snapshot.rows.single{it.id==id})
        val actual=financeWalletBalancesRaw(owner,snapshot.rows.filter{it.entity==CloudEntity.LEDGER_TRANSACTION.table},snapshot.rows.filter{it.entity==CloudEntity.LEDGER_WALLET.table},setOf(if(direction==InvestmentCashTransferDirection.DEPOSIT)selected else linkedId))!!.values.single()
        val allocation=investmentCashAllocation(snapshot.walletSnapshot(),"VND")
        val sourceId=if(direction==InvestmentCashTransferDirection.DEPOSIT)selected else linkedId
        val reserved=allocation.locations.singleOrNull{it.walletId==sourceId}?.originalTotalMinor ?: BigInteger.ZERO
        val preview=investmentCashTransferPreview(direction,amount,n(800),allocation.totalMinor,n(300),actual,reserved)
        return InvestmentCashTransferRequest(wallet(investmentSystemWalletId(owner)),wallet(linkedId),wallet(selected),
            InvestmentCashTransferDraft(event,direction,selected,amount,"  Test note  ",occurred,now),preview,"Transfer")
    }
    private fun plan(s:InvestmentCashReadSnapshot=source(),r:InvestmentCashTransferRequest=request(s))=planInvestmentCashTransfer(s,r,device,now)
    private fun CloudRecord.with(key:String,value:JsonElement)=copy(payload=JsonObject(payload+(key to value)))
    private fun failed(reason:InvestmentCashTransferError,action:()->Unit){assertEquals(reason,(runCatching(action).exceptionOrNull() as? InvestmentCashTransferException)?.reason)}
    private fun after(s:InvestmentCashReadSnapshot,p:InvestmentCashTransferPlan)=s.copy(rows=s.rows.filterNot{old ->p.mutations.any{it.first.entity==old.entity && it.first.id==old.id}}+p.mutations.map{it.first})

    private val later="2026-10-22T01:00:00Z"
    private fun deposited():InvestmentCashReadSnapshot {val before=source();return after(before,plan(before))}
    private fun withdrawn():InvestmentCashReadSnapshot {val before=source();return after(before,plan(before,request(before,InvestmentCashTransferDirection.WITHDRAWAL,otherId,300)))}
    private fun read(before:InvestmentCashReadSnapshot)=readInvestmentCashTransferLifecycle(before,event)
    private fun review(before:InvestmentCashReadSnapshot,amount:Long?=null,target:String?=null,note:String?=null):InvestmentCashTransferRequest {
        val read=read(before);val baseline=if(target==null)read.baseline else readInvestmentCashTransfer(
            before.copy(rows=before.rows.filter{it.id!=event && !(it.entity==CloudEntity.INVESTMENT_POSTING.table && it.payload.financeRawReference("event_id").id==event)}),read.event.draft.direction,target,amount ?: read.event.draft.amountMinor)
        val draft=read.event.draft.copy(walletId=target ?: read.event.draft.walletId,amountMinor=amount ?: read.event.draft.amountMinor,note=note ?: read.event.draft.note)
        return InvestmentCashTransferRequest(baseline.system,baseline.linked,baseline.selected,draft,baseline.preview.copy(requestedMinor=draft.amountMinor),"Edited transfer")
    }
    private fun changed(before:InvestmentCashReadSnapshot,request:InvestmentCashTransferLifecycleRequest)=planInvestmentCashTransferLifecycle(before,request,device,later)

    @Test fun reopeningExcludesTheWholeOriginalEventFromCapacityAndRestoresItsOriginalValues() {
        val before=deposited();val view=read(before)
        assertEquals(500L,view.event.draft.amountMinor);assertEquals(occurred,view.event.draft.occurredAt);assertEquals(now,view.event.draft.createdAt)
        assertEquals("Test note",view.event.draft.note);assertEquals(linkedId,view.event.draft.walletId)
        assertEquals(500L,view.baseline.preview.maximumMinor);assertEquals(n(300),view.baseline.preview.availableInvestmentMinor)
        assertEquals(300L,read(withdrawn()).baseline.preview.maximumMinor)
    }
    @Test fun editReusesThePairAndPreservesVersionsUnknownFieldsAndCreatedMetadataWhileChangingMoneyAndWallet() {
        val initial=deposited();val before=initial.copy(rows=initial.rows.map{raw ->if(raw.id==event || raw.entity==CloudEntity.INVESTMENT_POSTING.table && raw.payload.financeRawReference("event_id").id==event)
            raw.copy(syncVersion=9007199254740993L).with("sync_version",JsonPrimitive(9007199254740993L)).with("future_field",JsonPrimitive("keep")) else raw})
        val edit=InvestmentCashTransferLifecycleRequest.Save(read(before).event,review(before,400,otherId,"  Edited note  "))
        val plan=changed(before,edit);assertEquals(2,plan.mutations.size);assertEquals(setOf(event,investmentLedgerIdentity(event,"cash-transfer-posting")),plan.mutations.map{it.first.id}.toSet())
        for((row,mutation) in plan.mutations){assertEquals(9007199254740993L,row.syncVersion);assertEquals(9007199254740993L,mutation.baseVersion);assertEquals("keep",row.payload.financeRawString("future_field"));assertEquals(now,row.payload.financeRawString("created_at"))}
        val result=after(before,plan);val ledger=result.rows.single{it.id==event};assertEquals(400L,ledger.payload.financeRawLong("amount_minor"));assertEquals("Edited note",ledger.payload.financeRawString("note"));assertEquals(otherId,ledger.payload.financeRawString("source_wallet_id"))
        assertEquals(n(700),investmentCashFinancialView(result,"VND").availableMinor)
        val balances=financeWalletBalancesRaw(owner,result.rows.filter{it.entity==CloudEntity.LEDGER_TRANSACTION.table},result.rows.filter{it.entity==CloudEntity.LEDGER_WALLET.table})!!
        assertEquals(n(9600),balances[otherId]);assertEquals(n(10400),balances[linkedId])
        assertTrue(changed(result,edit).mutations.isEmpty())
    }
    @Test fun directionAndOriginalIdentityAreLockedEvenWhenNewInputsCouldOtherwiseBeValid() {
        val before=deposited();val original=read(before).event;val request=review(before)
        for(draft in listOf(request.draft.copy(direction=InvestmentCashTransferDirection.WITHDRAWAL),request.draft.copy(id=otherId),request.draft.copy(createdAt=later)))
            assertTrue(runCatching{changed(before,InvestmentCashTransferLifecycleRequest.Save(original,request.copy(draft=draft)))}.isFailure)
    }
    @Test fun deletionTombstonesBothRowsWithDeleteQueuesAndCompleteReplayCannotQueueAgain() {
        val before=deposited();val delete=InvestmentCashTransferLifecycleRequest.Delete(read(before).event,review(before))
        val plan=changed(before,delete);assertEquals(2,plan.mutations.size)
        for((row,mutation) in plan.mutations){assertEquals(later,row.deletedAt);assertEquals(later,row.payload.financeRawString("deleted_at"));assertEquals(MutationKind.DELETE,mutation.kind)}
        val result=after(before,plan);assertEquals(n(300),investmentCashFinancialView(result,"VND").availableMinor)
        assertTrue(changed(result,delete).mutations.isEmpty())
    }
    @Test fun consumedDepositAndExcessRestoredWithdrawalCannotBeDeletedEvenWithSufficientActualMoney() {
        val before=deposited();val delete=InvestmentCashTransferLifecycleRequest.Delete(read(before).event,review(before))
        val spent=before.copy(rows=before.rows+row(CloudEntity.INVESTMENT_POSTING,"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",buildJsonObject{
            put("wallet_id",linkedId);put("role_raw_value","cashConsumption");put("cash_bucket_raw_value","booked");put("amount_minor",-400L);put("accounting_amount_minor",-400L);put("currency_code","VND");put("accounting_currency_code","VND")
        }))
        val freshDelete=InvestmentCashTransferLifecycleRequest.Delete(read(spent).event,review(spent))
        assertTrue(runCatching{changed(spent,freshDelete)}.isFailure);assertTrue(runCatching{changed(spent,delete)}.isFailure)
        val withdrawal=withdrawn().let{it.copy(rows=it.rows.map{raw ->if(raw.entity==CloudEntity.INVESTMENT_TRADE.table)raw.with("realized_profit_loss_minor",JsonPrimitive(100L)) else raw})}
        assertTrue(runCatching{changed(withdrawal,InvestmentCashTransferLifecycleRequest.Delete(read(withdrawal).event,review(withdrawal)))}.isFailure)
    }
    @Test fun staleVisibleChangesPartialEventsAndTamperedRetryCannotMasqueradeAsAnAcknowledgment() {
        val before=deposited();val edit=InvestmentCashTransferLifecycleRequest.Save(read(before).event,review(before,400))
        val stale=before.copy(rows=before.rows.map{if(it.id==event)it.with("note",JsonPrimitive("Changed elsewhere")) else it})
        assertTrue(runCatching{changed(stale,edit)}.isFailure)
        val missing=before.copy(rows=before.rows.filterNot{it.entity==CloudEntity.INVESTMENT_POSTING.table && it.payload.financeRawReference("event_id").id==event})
        assertTrue(runCatching{changed(missing,edit)}.isFailure)
        val saved=after(before,changed(before,edit));val tampered=saved.copy(rows=saved.rows.map{if(it.id==event)it.with("destination_amount_minor",JsonPrimitive(399L)) else it})
        assertTrue(runCatching{changed(tampered,edit)}.isFailure)
    }
    @Test fun semanticAckAloneDoesNotInvalidateFrozenEditAndForeignOwnershipCannotBeRelabelled() {
        val before=deposited();val edit=InvestmentCashTransferLifecycleRequest.Save(read(before).event,review(before,400))
        val ack=before.copy(rows=before.rows.map{raw ->if(raw.id==event || raw.payload.financeRawReference("event_id").id==event)
            raw.copy(syncVersion=9007199254740993L,updatedAt=later).with("sync_version",JsonPrimitive(9007199254740993L)).with("updated_at",JsonPrimitive(later)).with("last_modified_by_device_id",JsonPrimitive(otherId)) else raw})
        assertEquals(2,changed(ack,edit).mutations.size)
        val foreign=before.copy(rows=before.rows.map{if(it.id==event)it.with("user_id",JsonPrimitive(otherId)) else it})
        assertTrue(runCatching{changed(foreign,edit)}.isFailure)
    }
    @Test fun anotherFinancialBindingCannotBeSilentlyClearedAsIfItWereOnlyAckMetadata() {
        val before=deposited();val edit=InvestmentCashTransferLifecycleRequest.Save(read(before).event,review(before,400))
        for((key,value) in listOf("category_id" to JsonPrimitive(otherId),"settlement_group_id" to JsonPrimitive(otherId),"debt_intent_raw_value" to JsonPrimitive("borrow"),"exchange_rate_decimal_string" to JsonPrimitive("2"))) {
            val changed=before.copy(rows=before.rows.map{if(it.id==event)it.with(key,value) else it})
            assertTrue("Silently cleared "+key,runCatching{changed(changed,edit)}.isFailure)
        }
    }
    @Test fun deletingAnEventTombstonesEveryLiveOwnedCashPostingAndRetainsOriginalCreatorMetadata() {
        val initial=deposited();val canonical=initial.rows.single{it.entity==CloudEntity.INVESTMENT_POSTING.table && it.payload.financeRawReference("event_id").id==event}
        val extra=canonical.copy(id=otherId).with("id",JsonPrimitive(otherId)).with("amount_minor",JsonPrimitive(100L)).with("accounting_amount_minor",JsonPrimitive(100L)).with("role_raw_value",JsonPrimitive("cashCorrection"))
        val before=initial.copy(rows=initial.rows.map{if(it.id==event)it.with("created_by_user_id",JsonPrimitive(otherId)) else it}+extra)
        val delete=InvestmentCashTransferLifecycleRequest.Delete(read(before).event,review(before));val plan=changed(before,delete)
        assertEquals(3,plan.mutations.size);assertTrue(plan.mutations.all{it.second.kind==MutationKind.DELETE})
        assertEquals(otherId,plan.mutations.single{it.first.id==event}.first.payload.financeRawString("created_by_user_id"))
        assertTrue(changed(after(before,plan),delete).mutations.isEmpty())
        val only=initial.copy(rows=initial.rows.map{if(it.id==event)it.with("created_by_user_id",JsonPrimitive(otherId)) else it})
        val edited=changed(only,InvestmentCashTransferLifecycleRequest.Save(read(only).event,review(only,400)))
        assertEquals(otherId,edited.mutations.single{it.first.id==event}.first.payload.financeRawString("created_by_user_id"))
    }
    @Test fun aPartiallyTombstonedPairCannotBeReplayedAsACompletedDelete() {
        val before=deposited();val delete=InvestmentCashTransferLifecycleRequest.Delete(read(before).event,review(before))
        val partial=before.copy(rows=before.rows.map{if(it.id==investmentLedgerIdentity(event,"cash-transfer-posting"))it.copy(deletedAt=later).with("deleted_at",JsonPrimitive(later)) else it})
        assertTrue(runCatching{changed(partial,delete)}.isFailure)
    }
    @Test fun editingAnImportedEventPreservesItsOtherCashPostingsAndCanReplayTheCompleteFrozenChange() {
        val initial=deposited();val canonical=initial.rows.single{it.entity==CloudEntity.INVESTMENT_POSTING.table && it.payload.financeRawReference("event_id").id==event}
        val extra=canonical.copy(id=otherId).with("id",JsonPrimitive(otherId)).with("role_raw_value",JsonPrimitive("cashCorrection")).with("amount_minor",JsonPrimitive(100L)).with("accounting_amount_minor",JsonPrimitive(100L))
        val before=initial.copy(rows=initial.rows+extra);val edit=InvestmentCashTransferLifecycleRequest.Save(read(before).event,review(before,400))
        val plan=changed(before,edit);assertEquals(2,plan.mutations.size);assertFalse(plan.mutations.any{it.first.id==otherId})
        val saved=after(before,plan);assertEquals(extra,saved.rows.single{it.entity==CloudEntity.INVESTMENT_POSTING.table && it.id==otherId})
        assertEquals(n(800),investmentCashFinancialView(saved,"VND").availableMinor);assertTrue(changed(saved,edit).mutations.isEmpty())
        val altered=saved.copy(rows=saved.rows.map{if(it.entity==CloudEntity.INVESTMENT_POSTING.table && it.id==otherId)it.with("amount_minor",JsonPrimitive(101L)).with("accounting_amount_minor",JsonPrimitive(101L)) else it})
        assertTrue(runCatching{changed(altered,edit)}.isFailure)
    }
}
