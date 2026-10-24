package vn.com.quyln.mistia.core.model

import java.math.BigInteger
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class InvestmentFundUsagePlanTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val device="44444444-4444-4444-8444-444444444444"
    private fun id(n:Int)=java.util.UUID(0,n.toLong()).toString()
    private val now="2026-10-22T00:00:00Z"
    private fun row(entity:CloudEntity,key:String,fields:JsonObject)=CloudRecord(entity.table,key,owner.value,JsonObject(buildJsonObject {
        put("id",key);put("user_id",owner.value);put("created_at",now);put("updated_at",now);put("deleted_at",JsonNull);put("sync_version",0L)
    }+fields),now,null,0)
    private fun wallet(key:Int,opening:Long=100)=WalletDraft(id=id(key),name="Wallet$key",kind=WalletKind.CASH,currencyCode="JPY",openingBalanceMinor=opening).toMutation(owner,null,device,now).record
    private fun expense(amount:Long=70,kind:String="expense",to:Int?=null)=row(CloudEntity.LEDGER_TRANSACTION,id(20),buildJsonObject {
        put("primary_kind_raw_value",kind);put("entry_status_raw_value","posted");put("amount_minor",amount);put("source_wallet_id",id(1));put("source_currency_code","JPY")
        put("destination_wallet_id",to?.let{JsonPrimitive(id(it))} ?: JsonNull);put("transfer_subtype_raw_value",if(to!=null)JsonPrimitive("internalTransfer") else JsonNull)
        put("destination_amount_minor",if(to!=null)JsonPrimitive(amount) else JsonNull);put("occurred_at","2026-10-22T00:00:02Z");put("is_archived",false)
        put("title","Ordinary transaction");put("settlement_role_raw_value",JsonNull)
    })
    private fun cash(booked:Long=60,bucket:String="booked")=row(CloudEntity.INVESTMENT_POSTING,id(10),buildJsonObject {
        put("event_id",id(11));put("ledger_transaction_id",id(11));put("wallet_id",id(1));put("role_raw_value","cashAccrual")
        put("cash_bucket_raw_value",bucket);put("cash_origin_raw_value","derived");put("amount_minor",booked);put("currency_code","JPY")
        put("accounting_amount_minor",booked);put("accounting_currency_code","JPY");put("occurred_at","2026-10-22T00:00:01Z")
    })
    private fun source(opening:Long=100,booked:Long=60,bucket:String="booked"):InvestmentCashReadSnapshot {
        val system=wallet(99).let{it.copy(id=investmentSystemWalletId(owner),payload=JsonObject(it.payload+buildJsonObject{put("id",investmentSystemWalletId(owner));put("kind_raw_value","investment");put("system_purpose_raw_value","investmentProfit")}))}
        return InvestmentCashReadSnapshot(owner,listOf(system,wallet(1,opening),wallet(2,0),cash(booked,bucket)))
    }
    private fun review(s:InvestmentCashReadSnapshot,p:CloudRecord)=reviewInvestmentFundUsage(s,"JPY",p)
    private fun plan(s:InvestmentCashReadSnapshot,p:CloudRecord,consent:InvestmentFundUsageConsent?=review(s,p).consent)=planInvestmentFundUsage(s,"JPY",p,consent,"Automatic cash reconciliation",device,now)
    private fun applied(s:InvestmentCashReadSnapshot,p:CloudRecord,derived:InvestmentFundUsagePlan):InvestmentCashReadSnapshot {
        val changes=listOf(p)+derived.mutations.map{it.first};val keys=changes.map{it.entity to it.id}.toSet()
        return s.copy(rows=s.rows.filter{(it.entity to it.id) !in keys}+changes)
    }
    @Test fun actualSeventyExpenseRequiresExplicitThirtyFundUseAndProducesOneCanonicalOwnedQueue() {
        val s=source();val p=expense();val before=s.copy(rows=s.rows.toList());val review=review(s,p)
        assertTrue(review.requiresConfirmation);assertEquals(BigInteger.valueOf(30),review.comparison.proposed.usages.getValue(p.id).investmentToUseMinor)
        val error=runCatching{plan(s,p,null)}.exceptionOrNull();assertTrue(error is InvestmentFundUsageConfirmationRequired)
        val result=plan(s,p);val (posting,queue)=result.mutations.single()
        assertEquals(investmentLedgerIdentity(p.id,"cash-consumption-booked"),posting.id);assertEquals("cashConsumption",posting.payload.financeRawString("role_raw_value"));assertEquals(-30L,posting.payload.financeRawLong("amount_minor"))
        assertEquals("derived",posting.payload.financeRawString("cash_origin_raw_value"));assertEquals(owner.value,posting.ownerUserId);assertEquals(posting.payload,queue.payload);assertEquals(MutationKind.UPSERT,queue.kind)
        val after=applied(s,p,result);assertEquals(BigInteger.valueOf(30),investmentCashAllocation(after.walletSnapshot(),"JPY").totalMinor)
        assertTrue(plan(after,p,review.consent).mutations.isEmpty());assertEquals(before,s)
    }
    @Test fun reducingExpenseRestoresTwentyAndPreservesOriginalDerivedVersionCreationAndUnknownMetadata() {
        val s=source();val old=expense();val first=plan(s,old)
        val current=applied(s,old,first).let{snapshot->snapshot.copy(rows=snapshot.rows.map{row->if(row.entity==CloudEntity.INVESTMENT_POSTING.table && row.id!=id(10))row.copy(syncVersion=9007199254740993L,payload=JsonObject(row.payload+buildJsonObject{put("sync_version",9007199254740993L);put("future_field","keep")})) else row})}
        val p=expense(50);val review=review(current,p);assertTrue(review.requiresConfirmation);assertEquals(BigInteger.valueOf(20),review.comparison.primaryChange!!.restoreMinor)
        val (posting,queue)=plan(current,p).mutations.single();assertEquals(-10L,posting.payload.financeRawLong("amount_minor"));assertEquals(9007199254740993L,queue.baseVersion)
        assertEquals(JsonPrimitive("keep"),posting.payload["future_field"]);assertEquals(JsonPrimitive(now),posting.payload["created_at"])
    }
    @Test fun changingExpenseToIncomeRetiresItsOldDerivedUsageWithADeleteQueueAndRestoresAllocation() {
        val s=source();val old=expense();val current=applied(s,old,plan(s,old));val p=expense(70,"income")
        assertTrue(review(current,p).requiresConfirmation)
        val result=plan(current,p);val (posting,queue)=result.mutations.single()
        assertEquals(MutationKind.DELETE,queue.kind);assertEquals(now,posting.deletedAt);assertEquals(JsonPrimitive(now),posting.payload["deleted_at"])
        assertEquals(BigInteger.valueOf(60),investmentCashAllocation(applied(current,p,result).walletSnapshot(),"JPY").totalMinor)
    }
    @Test fun internalTransferCarriesReservedAllocationWithTwoDerivedPostingsAndNoExtraActualCash() {
        val s=source();val p=expense(70,"transfer",2);val result=plan(s,p)
        assertEquals(2,result.mutations.size);assertEquals(setOf(-30L,30L),result.mutations.map{it.first.payload.financeRawLong("accounting_amount_minor")}.toSet())
        assertTrue(result.mutations.all{it.first.payload.financeRawString("role_raw_value")=="cashTransfer"})
        val after=applied(s,p,result);assertEquals(BigInteger.valueOf(60),investmentCashAllocation(after.walletSnapshot(),"JPY").totalMinor)
        val actual=financeWalletBalancesRaw(owner,after.rows.filter{it.entity==CloudEntity.LEDGER_TRANSACTION.table},after.rows.filter{it.entity==CloudEntity.LEDGER_WALLET.table})!!
        assertEquals(BigInteger.valueOf(30),actual[id(1)]);assertEquals(BigInteger.valueOf(70),actual[id(2)])
    }
    @Test fun unreconciledUseCreatesItsVirtualAdjustmentAndConsumptionExactlyOnce() {
        val s=source(40,60,"unreconciled");val p=expense(60);val result=plan(s,p)
        assertEquals(2,result.mutations.size)
        val ledger=result.mutations.single{it.first.entity==CloudEntity.LEDGER_TRANSACTION.table}.first
        assertEquals(investmentLedgerIdentity(p.id,"cash-unreconciled-adjustment"),ledger.id);assertEquals("investmentReserveUse",ledger.payload.financeRawString("settlement_role_raw_value"));assertEquals(20L,ledger.payload.financeRawLong("amount_minor"))
        val after=applied(s,p,result);val actual=financeWalletBalancesRaw(owner,after.rows.filter{it.entity==CloudEntity.LEDGER_TRANSACTION.table},after.rows.filter{it.entity==CloudEntity.LEDGER_WALLET.table})!!
        assertEquals(BigInteger.ZERO,actual[id(1)]);assertEquals(BigInteger.valueOf(80),actual[investmentSystemWalletId(owner)])
        assertEquals(BigInteger.valueOf(40),investmentCashAllocation(after.walletSnapshot(),"JPY").totalMinor)
    }
    @Test fun changedMoneyInvalidatesConsentWhileAnAckDoesNotAndOrdinaryOnlyNeedsNoConfirmation() {
        val s=source();val p=expense();val consent=review(s,p).consent
        val changed=s.copy(rows=s.rows.map{if(it.id==id(1))it.copy(payload=JsonObject(it.payload+("opening_balance_minor" to JsonPrimitive(101L)))) else it})
        assertEquals(InvestmentFundUsageError.STALE_CONSENT,(runCatching{plan(changed,p,consent)}.exceptionOrNull() as? InvestmentFundUsageException)?.reason)
        val ack=s.copy(rows=s.rows.map{it.copy(syncVersion=9007199254740993L,payload=JsonObject(it.payload+("sync_version" to JsonPrimitive(9007199254740993L))))})
        assertEquals(1,plan(ack,p,consent).mutations.size)
        val ordinary=source(booked=0);assertFalse(review(ordinary,p).requiresConfirmation);assertTrue(plan(ordinary,p,null).mutations.isEmpty())
    }
    @Test fun changingAnUnrelatedIncomeDateRestoresDownstreamFundsWithTheOriginalSwift943Vector() {
        val base=source(2090,3399)
        val capital=row(CloudEntity.LEDGER_TRANSACTION,id(30),JsonObject(expense(4290,"income").payload+buildJsonObject{put("id",id(30));put("occurred_at","2026-10-22T00:00:01Z");put("settlement_role_raw_value","investmentCapitalReturn")}))
        val oldExpense=expense(4000).copy(payload=JsonObject(expense(4000).payload+("occurred_at" to JsonPrimitive("2026-10-22T00:00:03Z"))))
        val income=row(CloudEntity.LEDGER_TRANSACTION,id(21),JsonObject(expense(943,"income").payload+buildJsonObject{put("id",id(21));put("occurred_at","2026-10-22T00:00:04Z")}))
        val before=base.copy(rows=base.rows+capital+oldExpense+income)
        val current=applied(before,income,plan(before,income))
        val proposed=income.copy(payload=JsonObject(income.payload+("occurred_at" to JsonPrimitive("2026-10-22T00:00:02Z"))))
        val review=review(current,proposed);assertTrue(review.requiresConfirmation);assertEquals(BigInteger.valueOf(943),review.comparison.primaryChange!!.restoreMinor)
        val posting=plan(current,proposed).mutations.single().first
        assertEquals(investmentLedgerIdentity(oldExpense.id,"cash-consumption-booked"),posting.id);assertEquals(-76L,posting.payload.financeRawLong("amount_minor"))
    }
    @Test fun aManualAllocationOccupyingTheDerivedIdentityCannotBeOverwrittenOrRetired() {
        val base=source();val p=expense();val id=investmentLedgerIdentity(p.id,"cash-consumption-booked")
        val manual=row(CloudEntity.INVESTMENT_POSTING,id,JsonObject(cash().payload+buildJsonObject{
            put("id",id);put("event_id",p.id);put("ledger_transaction_id",p.id);put("role_raw_value","cashTransfer");put("cash_origin_raw_value","manual");put("amount_minor",-1L);put("accounting_amount_minor",-1L)
        }))
        val s=base.copy(rows=base.rows+manual)
        assertEquals(InvestmentFundUsageError.EVENT_CONFLICT,(runCatching{plan(s,p)}.exceptionOrNull() as? InvestmentFundUsageException)?.reason)
        assertEquals(manual,s.rows.last())
    }
    @Test fun aManualConsumptionAtTheCanonicalIdentityCannotBecomeDerived() {
        val s=source();val p=expense();val derived=plan(s,p).mutations.single().first
        val manual=derived.copy(payload=JsonObject(derived.payload+("cash_origin_raw_value" to JsonPrimitive("manual"))))
        val error=runCatching{plan(s.copy(rows=s.rows+manual),p)}.exceptionOrNull()
        assertEquals(InvestmentFundUsageError.EVENT_CONFLICT,(error as? InvestmentFundUsageException)?.reason)
    }
    @Test fun anUnrelatedManualConsumptionCannotBeRetiredByAnOrdinarySave() {
        val s=source();val derived=plan(s,expense()).mutations.single().first
        val manual=derived.copy(payload=JsonObject(derived.payload+("cash_origin_raw_value" to JsonPrimitive("manual"))))
        val changes=plan(s.copy(rows=s.rows+manual),expense(10)).mutations
        assertTrue(changes.none{it.first.id==manual.id})
    }
    @Test fun ownedCanonicalDerivedTombstoneCanBeRestoredWithoutResettingVersionCreationOrUnknownFields() {
        val s=source();val p=expense();val original=plan(s,p).mutations.single().first
        val tombstone=original.copy(syncVersion=9007199254740993L,deletedAt=now,payload=JsonObject(original.payload+buildJsonObject{
            put("deleted_at",now);put("sync_version",9007199254740993L);put("future_field","preserve")
        }))
        val (restored,queue)=plan(s.copy(rows=s.rows+tombstone),p).mutations.single()
        assertEquals(MutationKind.UPSERT,queue.kind);assertNull(restored.deletedAt);assertEquals(JsonNull,restored.payload["deleted_at"])
        assertEquals(9007199254740993L,queue.baseVersion);assertEquals(JsonPrimitive("preserve"),restored.payload["future_field"]);assertEquals(original.payload["created_at"],restored.payload["created_at"])
    }
    @Test fun automaticAdjustmentWithAnUnexpectedFinancialBindingCannotBeSilentlyCleared() {
        val s=source(40,60,"unreconciled");val p=expense(60)
        val adjustment=plan(s,p).mutations.single{it.first.entity==CloudEntity.LEDGER_TRANSACTION.table}.first.let{it.copy(payload=JsonObject(it.payload+("category_id" to JsonPrimitive(id(88)))))}
        val input=s.copy(rows=s.rows+adjustment)
        assertEquals(InvestmentFundUsageError.EVENT_CONFLICT,(runCatching{plan(input,p)}.exceptionOrNull() as? InvestmentFundUsageException)?.reason)
    }
    @Test fun automaticAdjustmentEditsPreserveItsOriginalCreatorVersionAndUnknownMetadata() {
        val s=source(40,60,"unreconciled");val old=expense(60)
        val current=applied(s,old,plan(s,old)).let{read->read.copy(rows=read.rows.map{row->
            if(row.payload.financeRawString("settlement_role_raw_value")=="investmentReserveUse")row.copy(syncVersion=9007199254740993L,payload=JsonObject(row.payload+buildJsonObject{
                put("created_by_user_id",id(77));put("sync_version",9007199254740993L);put("future_field","keep")
            })) else row
        })}
        val (adjustment,queue)=plan(current,expense(65)).mutations.single{it.first.entity==CloudEntity.LEDGER_TRANSACTION.table}
        assertEquals(25L,adjustment.payload.financeRawLong("amount_minor"));assertEquals(JsonPrimitive(id(77)),adjustment.payload["created_by_user_id"])
        assertEquals(9007199254740993L,queue.baseVersion);assertEquals(JsonPrimitive("keep"),adjustment.payload["future_field"]);assertEquals(JsonPrimitive(now),adjustment.payload["created_at"])
    }
    @Test fun completedAutomaticAdjustmentAckDoesNotRewriteAuditMetadataOrInvalidateKnownSuccess() {
        val s=source(40,60,"unreconciled");val p=expense(60);val consent=review(s,p).consent
        val after=applied(s,p,plan(s,p)).let{read->read.copy(rows=read.rows.map{row->
            if(row.payload.financeRawString("settlement_role_raw_value")=="investmentReserveUse")row.copy(syncVersion=9007199254740993L,
                updatedAt="2026-10-22T00:01:00Z",payload=JsonObject(row.payload+buildJsonObject{
                    put("sync_version",9007199254740993L);put("updated_at","2026-10-22T00:01:00Z");put("last_modified_by_device_id",id(77));put("last_modified_by_user_id",id(78))
                })) else row
        })}
        val replay=runCatching{plan(after,p,consent)}
        assertTrue("A metadata-only ACK must not invalidate a complete save: "+replay.exceptionOrNull(),replay.isSuccess)
        assertTrue(replay.getOrThrow().mutations.isEmpty())
        val adjustment=after.rows.single{it.payload.financeRawString("settlement_role_raw_value")=="investmentReserveUse"}
        assertEquals(JsonPrimitive(id(78)),adjustment.payload["last_modified_by_user_id"])
    }
    @Test fun anIncomeMovingTheSameReservedTotalBetweenExpensesRequiresExplicitConsent() {
        val first=expense(900)
        val second=expense(50).let{it.copy(id=id(21),payload=JsonObject(it.payload+buildJsonObject{put("id",id(21));put("occurred_at","2026-10-22T00:00:03Z")}))}
        val raw=source(900,50).let{it.copy(rows=it.rows+first+second)}
        val current=applied(raw,first,planInvestmentFundEffects(raw,"JPY",investmentFundUsageTimeline(raw,"JPY"),"Automatic cash reconciliation",device,now))
        val income=expense(50,"income").let{it.copy(id=id(22),payload=JsonObject(it.payload+buildJsonObject{put("id",id(22));put("occurred_at","2026-10-22T00:00:01.500Z")}))}
        val review=review(current,income)
        assertTrue("A different transaction consumes the same reserved total",review.requiresConfirmation)
        val change=review.comparison.changes.single();assertEquals(50.toBigInteger(),change.previousMinor);assertEquals(50.toBigInteger(),change.proposedMinor)
        assertEquals(50.toBigInteger(),review.comparison.current.usages[first.id]?.investmentToUseMinor)
        assertEquals(50.toBigInteger(),review.comparison.proposed.usages[second.id]?.investmentToUseMinor)
        assertTrue(runCatching{plan(current,income,null)}.exceptionOrNull() is InvestmentFundUsageConfirmationRequired)
        val accepted=plan(current,income,review.consent);val after=applied(current,income,accepted)
        assertEquals(MutationKind.DELETE,accepted.mutations.single{it.first.id==investmentLedgerIdentity(first.id,"cash-consumption-booked")}.second.kind)
        assertEquals(-50L,accepted.mutations.single{it.first.id==investmentLedgerIdentity(second.id,"cash-consumption-booked")}.first.payload.financeRawLong("amount_minor"))
        assertTrue(plan(after,income,review.consent).mutations.isEmpty())
    }

    @Test fun changingDeviceLanguageDoesNotRewriteAnExistingAutomaticAdjustmentTitle() {
        val raw=source(40,60,"unreconciled");val transaction=expense(60)
        val current=applied(raw,transaction,plan(raw,transaction))
        val adjustment=current.rows.single{it.payload.financeRawString("settlement_role_raw_value")=="investmentReserveUse"}
        val result=planInvestmentFundUsage(current,"JPY",transaction,review(current,transaction).consent,"別の端末の言語",device,now)
        assertTrue("A translated label is not a new financial mutation",result.mutations.isEmpty())
        assertEquals("Automatic cash reconciliation",adjustment.payload.financeRawString("title"))
    }

}
