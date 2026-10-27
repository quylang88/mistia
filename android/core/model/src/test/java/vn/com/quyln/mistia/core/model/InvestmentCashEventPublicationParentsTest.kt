package vn.com.quyln.mistia.core.model

import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class InvestmentCashEventPublicationParentsTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val id="22222222-2222-2222-2222-222222222222"
    private val device="33333333-3333-3333-3333-333333333333"
    private val source="77777777-7777-7777-7777-777777777777"
    private val linked="88888888-8888-8888-8888-888888888888"
    private val postingId="625e1715-81fd-57c6-91e1-596e53e42db5"
    private val now="2026-10-27T00:00:00Z"
    private fun transaction(v:Long=1,withdraw:Boolean=false)=CloudRecord(CloudEntity.LEDGER_TRANSACTION.table,id,owner.value,buildJsonObject {
        put("id",id);put("user_id",owner.value);put("primary_kind_raw_value","transfer");put("transfer_subtype_raw_value","internalTransfer");put("entry_status_raw_value","posted")
        put("settlement_role_raw_value",if(withdraw)"investmentCashWithdrawal" else "investmentCashDeposit");put("title","Cash event");put("note",JsonNull)
        put("amount_minor",if(withdraw)20 else 50);put("source_wallet_id",if(withdraw)linked else source);put("destination_wallet_id",if(withdraw)source else linked)
        put("destination_amount_minor",if(withdraw)20 else 50);put("reporting_amount_minor",if(withdraw)20 else 50);put("reporting_expense_minor",0);put("reporting_income_minor",0)
        for(key in listOf("source_currency_code","destination_currency_code","reporting_currency_code"))put(key,"VND")
        for(key in listOf("category_id","debt_intent_raw_value","settlement_group_id","settlement_obligation_id","conversion_mode_raw_value","exchange_rate_decimal_string","exchange_rate_provider","exchange_rate_date","counterparty_name","normalized_counterparty_key","archived_at","deleted_at"))put(key,JsonNull)
        put("created_by_user_id",owner.value);put("last_modified_by_user_id",owner.value);put("is_archived",false)
        put("occurred_at",now);put("created_at",now);put("updated_at",now);put("sync_version",v);put("last_modified_by_device_id",device)
        put("future_null",JsonNull);put("future_large",Long.MAX_VALUE)
    },now,null,v)
    private fun posting(v:Long=1,withdraw:Boolean=false)=CloudRecord(CloudEntity.INVESTMENT_POSTING.table,postingId,owner.value,buildJsonObject {
        put("id",postingId);put("user_id",owner.value);put("event_id",id);put("ledger_transaction_id",id);put("trade_id",JsonNull);put("asset_id",JsonNull);put("wallet_id",linked)
        put("role_raw_value","cashTransfer");put("cash_bucket_raw_value","booked");put("cash_origin_raw_value","manual")
        put("amount_minor",if(withdraw)-20 else 50);put("accounting_amount_minor",if(withdraw)-20 else 50);put("currency_code","VND");put("accounting_currency_code","VND")
        put("occurred_at",now);put("created_at",now);put("updated_at",now);put("deleted_at",JsonNull);put("sync_version",v);put("last_modified_by_device_id",device)
    },now,null,v)


    private fun changed(old:CloudRecord,name:String)=old.copy(payload=JsonObject(old.payload+("note" to JsonPrimitive(name)))).withPriorCashEventPublication(old)
    private fun version(row:CloudRecord,v:Long)=row.copy(syncVersion=v,payload=JsonObject(row.payload+("sync_version" to JsonPrimitive(v))))
    private fun state(row:CloudRecord):InvestmentCashEventPublicationSnapshot {
        val q=QueuedMutation(PendingMutation(CloudEntity.LEDGER_TRANSACTION,id,owner.value,if(row.deletedAt==null)MutationKind.UPSERT else MutationKind.DELETE,row.payload,row.updatedAt!!,row.syncVersion,device),3,60000,"network_io")
        return InvestmentCashEventPublicationSnapshot(owner,id,listOf(row),listOf(q),setOf(row.entity to id))
    }
    @Test fun actualPriorIntentIsRecognizedOnlyAtTheNextCashRpcVersion() {
        val old=transaction(7);val local=changed(old,"New local");val remote=version(old,8)
        assertTrue(isKnownPriorCashEventPublication(local,remote,device));assertFalse(isKnownPriorCashEventPublication(local,version(old,9),device))
        assertEquals(old.payload,cashEventPayloadForCloud(local).let{JsonObject(it+("note" to JsonNull))})
        assertEquals(listOf(InvestmentCashEventPublicationParent(7,null,device,false,cashEventIntentFingerprint(old))),localCashEventPublicationParents(local))
    }
    @Test fun identityCreationOpaqueAndActorDifferencesCannotForgeTheOldIntent() {
        val old=transaction(7);val local=changed(old,"New local")
        for((key,value) in listOf("created_at" to JsonPrimitive("2026-10-26T00:00:00Z"),"future_large" to JsonPrimitive(42),"last_modified_by_device_id" to JsonPrimitive(source))) {
            val remote=version(old,8).let{it.copy(payload=JsonObject(it.payload+(key to value)))}
            assertFalse(isKnownPriorCashEventPublication(local,remote,device))
        }
    }
    @Test fun malformedOrForeignPrivateParentsCannotBeSilentlyStrippedOrReplaced() {
        val old=transaction(7);val local=changed(old,"New local")
        val bad=listOf(local.copy(ownerUserId=device),local.copy(payload=JsonObject(local.payload+(LOCAL_CASH_EVENT_PUBLICATION_PARENTS_KEY to JsonNull))),
            local.copy(payload=JsonObject(local.payload+("_mistia_android_unknown" to JsonNull))))
        for(row in bad)assertTrue(runCatching{cashEventPayloadForCloud(row)}.exceptionOrNull() is IllegalArgumentException)
        assertTrue(runCatching{changed(bad[1],"Another")}.exceptionOrNull() is IllegalArgumentException)
    }
    @Test fun theBoundedHistoryKeepsOnlyTheLatest64DistinctIntents() {
        var row=transaction(9007199254740993L)
        repeat(70){row=changed(row,"Intent $it")}
        assertEquals(64,localCashEventPublicationParents(row).size)
        assertTrue(isKnownPriorCashEventPublication(row,version(transaction(9007199254740993L).let{it.copy(payload=JsonObject(it.payload+("note" to JsonPrimitive("Intent 68"))))},9007199254740994L),device))
        assertFalse(isKnownPriorCashEventPublication(row,version(transaction(9007199254740993L),9007199254740994L),device))
    }
    @Test fun aDefiniteReplyAddsOnlyEvidenceToANewerDescendantAndPreservesItsQueueGeneration() {
        val old=transaction(7);val current=state(changed(old,"New local"));val sent=version(old,901);val remote=version(old,901)
        val receipt=InvestmentCashEventPublicationReceipt(state(old),sent,900,42,remote)
        val changed=planInvestmentCashEventPublicationReceipt(receipt,current).single()
        assertEquals(cashEventPayloadForCloud(current.requestedRecord!!),cashEventPayloadForCloud(changed));assertEquals(7L,changed.syncVersion);assertEquals(now,changed.updatedAt)
        assertTrue(isKnownPriorCashEventPublication(changed,remote,device));assertFalse(isKnownPriorCashEventPublication(current.requestedRecord!!,remote,device))
        assertEquals(3,current.requestedQueue!!.attemptCount);assertEquals(60000L,current.requestedQueue!!.nextAttemptAtEpochMillis)
    }
    @Test fun currentSameProposalOrAnUnrelatedLaterProposalCannotReceiveSupersededEvidence() {
        val old=transaction(7);val receipt=InvestmentCashEventPublicationReceipt(state(old),version(old,8),7,null,version(old,8))
        assertTrue(planInvestmentCashEventPublicationReceipt(receipt,state(old)).isEmpty())
        val unrelated=transaction(7).let{it.copy(payload=JsonObject(it.payload+("note" to JsonPrimitive("Unrelated no ancestry"))))}
        assertTrue(planInvestmentCashEventPublicationReceipt(receipt,state(unrelated)).isEmpty())
        assertTrue(planInvestmentCashEventPublicationReceipt(receipt,state(version(changed(old,"New local"),8))).isEmpty())
    }
    @Test fun forgedReplyVersionIntentActorOrPreparedSourceIsRejected() {
        val old=transaction(7);val current=state(changed(old,"New local"));val sent=version(old,8)
        val receipt=InvestmentCashEventPublicationReceipt(state(old),sent,7,null,sent)
        val bad=listOf(receipt.copy(returned=version(old,9)),receipt.copy(returned=sent.copy(payload=JsonObject(sent.payload+("note" to JsonPrimitive("Other"))))),
            receipt.copy(returned=sent.copy(payload=JsonObject(sent.payload+("last_modified_by_device_id" to JsonPrimitive(source))))),receipt.copy(sent=version(changed(old,"Unsubmitted"),8)))
        for(item in bad)assertTrue(runCatching{planInvestmentCashEventPublicationReceipt(item,current)}.exceptionOrNull() is IllegalArgumentException)
    }
}
