package vn.com.quyln.mistia.core.model

import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class InvestmentCashEventResultAcknowledgementTest {
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

    private fun queue(row:CloudRecord,observed:Boolean=false)=QueuedMutation(PendingMutation(CloudEntity.fromTable(row.entity)!!,row.id,owner.value,
        if(row.deletedAt==null)MutationKind.UPSERT else MutationKind.DELETE,row.payload,row.updatedAt!!,row.syncVersion,device),0,0,null,remoteIdentityObserved=observed)
    private fun state(rows:List<CloudRecord> = listOf(transaction(0),posting(0)),pending:List<QueuedMutation> = rows.map(::queue))=
        InvestmentCashEventPublicationSnapshot(owner,id,rows,pending,pending.map{it.mutation.entity.table to it.mutation.recordId}.toSet())
    private fun cloud(ledger:CloudRecord?=transaction(),posts:List<CloudRecord> = listOf(posting()))=InvestmentCashEventCloudSnapshot(owner,id,ledger,posts)
    private fun prove(s:InvestmentCashEventPublicationSnapshot=state(),c:InvestmentCashEventCloudSnapshot=cloud())=planInvestmentCashEventResultAcknowledgement(s,c)
    private fun reject(s:InvestmentCashEventPublicationSnapshot=state(),c:InvestmentCashEventCloudSnapshot)=assertTrue(runCatching{prove(s,c)}.exceptionOrNull() is IllegalArgumentException)
    private fun deleted(row:CloudRecord)=row.copy(deletedAt=now,payload=JsonObject(row.payload+("deleted_at" to JsonPrimitive(now))))
    private fun fields(row:CloudRecord,vararg pairs:Pair<String,JsonElement>)=row.copy(payload=JsonObject(row.payload+pairs))
    @Test fun exactDepositAndWithdrawalAcknowledgeOnlyTheirCanonicalPair() {
        for(withdraw in listOf(false,true)) {
            val local=listOf(transaction(0,withdraw),posting(0,withdraw));val remote=listOf(transaction(1,withdraw),posting(1,withdraw))
            val p=prove(state(local),cloud(remote.first(),listOf(remote.last())))
            assertEquals(remote.toSet(),p.imports.toSet());assertEquals(local.map(::queue).toSet(),p.acknowledgements.map{it.first}.toSet());assertTrue(p.absentAcknowledgements.isEmpty())
        }
    }
    @Test fun forgedAmountSignCurrencyWalletRoleOrCanonicalIdentityCannotClearThePair() {
        val p=posting()
        for(bad in listOf(fields(p,"amount_minor" to JsonPrimitive(49)),fields(p,"accounting_amount_minor" to JsonPrimitive(-50)),
            fields(p,"currency_code" to JsonPrimitive("JPY")),fields(p,"wallet_id" to JsonPrimitive(source)),fields(p,"role_raw_value" to JsonPrimitive("cashCorrection")),
            p.copy(id=device,payload=JsonObject(p.payload+("id" to JsonPrimitive(device))))))reject(c=cloud(posts=listOf(bad)))
        reject(c=cloud(ledger=fields(transaction(),"destination_amount_minor" to JsonPrimitive(49))))
    }
    @Test fun changedIntentOrOpaqueValuesCannotBeSemanticallyAcknowledged() {
        for(key in listOf("note","title","future_null"))reject(c=cloud(ledger=fields(transaction(),key to JsonPrimitive("Unsubmitted"))))
        reject(c=cloud(ledger=fields(transaction(),"future_large" to JsonPrimitive(9007199254740993L))))
        reject(c=cloud(ledger=fields(transaction(),"created_at" to JsonPrimitive("2026-10-26T00:00:00Z"))))
    }
    @Test fun newPostingUsesTheLedgerCreationTimeWhileAnExistingPostingKeepsItsOwn() {
        val later="2026-10-27T00:05:00Z";val localPost=fields(posting(0),"created_at" to JsonPrimitive(later))
        assertEquals(2,prove(state(listOf(transaction(0),localPost))).acknowledgements.size)
        val existing=fields(posting(7),"created_at" to JsonPrimitive(later));val current=transaction(9)
        reject(state(listOf(current,existing)),cloud(transaction(10),listOf(posting(8))))
        assertEquals(2,prove(state(listOf(current,existing)),cloud(transaction(10),listOf(fields(posting(8),"created_at" to JsonPrimitive(later))))).acknowledgements.size)
    }
    @Test fun remotePrivateForeignDuplicateRegressedOrPartialResultsAreRejected() {
        reject(c=cloud(posts=emptyList()));reject(c=cloud(posts=listOf(posting(),posting())))
        reject(c=cloud(ledger=transaction().copy(ownerUserId=device)))
        reject(c=cloud(ledger=fields(transaction(),"_mistia_android_forged_cash_parent" to JsonNull)))
        reject(c=cloud(ledger=null));reject(c=cloud(ledger=transaction(0)))
        reject(state(listOf(transaction(9),posting(7))),cloud(transaction(8),listOf(posting(8))))
    }
    @Test fun unrelatedOrdinaryAndTradeQueuesRemainOutsideTheFinancialAcknowledgement() {
        val ordinary=fields(transaction(0),"settlement_role_raw_value" to JsonNull).let{it.copy(id=device,payload=JsonObject(it.payload+("id" to JsonPrimitive(device))))}
        val p=prove(state(listOf(transaction(0),posting(0),ordinary)))
        assertEquals(setOf(id,postingId),p.acknowledgements.map{it.first.mutation.recordId}.toSet());assertFalse(p.imports.any{it.id==device})
    }
    @Test fun dirtyRetainedSiblingIsPreservedWhileCleanCloudSiblingsMayBeImported() {
        val key="ffffffff-ffff-4fff-8fff-ffffffffffff"
        val extra=fields(posting(4),"id" to JsonPrimitive(key),"role_raw_value" to JsonPrimitive("cashCorrection"),"amount_minor" to JsonPrimitive(0),"accounting_amount_minor" to JsonPrimitive(0)).copy(id=key)
        val local=listOf(transaction(0),posting(0),extra);val c=cloud(posts=listOf(posting(),fields(extra,"future_null" to JsonNull)))
        val p=prove(state(local),c)
        assertEquals(setOf(id,postingId),p.imports.map{it.id}.toSet());assertFalse(p.acknowledgements.any{it.first.mutation.recordId==key})
        val clean=prove(state(local,local.take(2).map(::queue)),c);assertEquals(3,clean.imports.size)
        reject(state(local,local.take(2).map(::queue)),cloud())
    }
    @Test fun publishedDeletionUsesActualOldServerIntentAndAllEventTombstones() {
        val local=deleted(fields(transaction(4),"note" to JsonPrimitive("Discarded local note")))
        val p=prove(state(listOf(local,deleted(posting(7)))),cloud(deleted(transaction(5)),listOf(deleted(posting(8)))))
        assertEquals(2,p.acknowledgements.size);assertEquals(JsonNull,p.imports.single{it.id==id}.payload["note"]);assertTrue(p.imports.all{it.deletedAt!=null})
        reject(state(listOf(local,deleted(posting(7)))),cloud(deleted(transaction(5)),listOf(posting(8))))
    }
    @Test fun neverPublishedDeletionNeedsAbsenceOfBothTablesAndUnobservedBaseZeroQueues() {
        val rows=listOf(deleted(transaction(0)),deleted(posting(0)));val s=state(rows)
        val p=prove(s,cloud(null,emptyList()));assertEquals(rows.map(::queue),p.absentAcknowledgements);assertTrue(p.imports.isEmpty())
        reject(s.copy(pending=s.pending.map{it.copy(remoteIdentityObserved=true)}),cloud(null,emptyList()))
        reject(state(listOf(deleted(transaction(1)),deleted(posting(1)))),cloud(null,emptyList()))
        reject(s,cloud(null,listOf(deleted(posting()))))
    }
    @Test fun deletedEventCannotConsumeANewerAliveSiblingOrARegressedTombstone() {
        val rows=listOf(deleted(transaction(4)),posting(7))
        reject(state(rows),cloud(deleted(transaction(5)),listOf(deleted(posting(8)))))
        reject(state(listOf(deleted(transaction(4)),deleted(posting(7)))),cloud(deleted(transaction(5)),listOf(deleted(posting(6)))))
    }
    @Test fun lostNewEventReplyThenLocalDeletionUsesTheServersKnownPostingCreationRule() {
        val later="2026-10-27T00:05:00Z"
        val local=listOf(deleted(transaction(0)),deleted(fields(posting(0),"created_at" to JsonPrimitive(later))))
        val p=prove(state(local),cloud(deleted(transaction(2)),listOf(deleted(posting(2)))))
        assertEquals(2,p.acknowledgements.size);assertEquals(now,p.imports.single{it.id==postingId}.payload.financeRawString("created_at"))
    }
    @Test fun anExtraRemotePostingCannotReassignAnotherCleanLocalEventIdentity() {
        val key="ffffffff-ffff-4fff-8fff-ffffffffffff"
        val old=fields(posting(4),"id" to JsonPrimitive(key),"event_id" to JsonPrimitive(device),"ledger_transaction_id" to JsonPrimitive(device),
            "role_raw_value" to JsonPrimitive("cashCorrection")).copy(id=key)
        val reassigned=fields(old,"event_id" to JsonPrimitive(id),"ledger_transaction_id" to JsonPrimitive(id))
        reject(state(listOf(transaction(0),posting(0),old),listOf(transaction(0),posting(0)).map(::queue)),cloud(posts=listOf(posting(),reassigned)))
    }
    @Test fun aMalformedRemoteActorCannotBeHiddenAsAnAbsentOptionalField() {
        reject(c=cloud(ledger=fields(transaction(),"last_modified_by_device_id" to buildJsonObject{put("bad",true)})))
        reject(c=cloud(posts=listOf(fields(posting(),"last_modified_by_device_id" to JsonPrimitive(42)))))
    }

    @Test fun validatedLocalAncestryDoesNotBecomePartOfTheCloudSemanticIntent() {
        val old=transaction(0)
        val local=fields(old,"note" to JsonPrimitive("Current")).withPriorCashEventPublication(old)
        val remote=fields(transaction(),"note" to JsonPrimitive("Current"))
        assertEquals(2,prove(state(listOf(local,posting(0))),cloud(remote)).acknowledgements.size)
    }
    @Test fun relabelledAncestryStillRequiresTheDedicatedInvestmentDomain() {
        val raw=fields(transaction(),LOCAL_CASH_EVENT_PUBLICATION_PARENTS_KEY to JsonNull,"settlement_role_raw_value" to JsonNull)
        assertTrue(requiresInvestmentLedgerDomain(raw.payload))
    }

    @Test fun aForeignLaterWinnerRequiresItsCompleteCanonicalFinancialPair() {
        val later="2026-10-27T00:10:00Z"
        val remote=fields(transaction(5),"note" to JsonPrimitive("Other device"),"last_modified_by_device_id" to JsonPrimitive(source),"updated_at" to JsonPrimitive(later)).copy(updatedAt=later)
        val s=state(listOf(transaction(4),posting(4)))
        val candidate=cloud(remote,listOf(posting(5))).copy(remoteIntentWinner=true)
        val plan=prove(s,candidate)
        assertEquals(2,plan.acknowledgements.size);assertEquals(remote,plan.imports.single{it.id==id})
        reject(s,candidate.copy(postings=listOf(fields(posting(5),"accounting_amount_minor" to JsonPrimitive(999)))))
    }
    @Test fun aForeignTombstoneWinnerCanRetireTheQueuedAliveCanonicalPair() {
        val later="2026-10-27T00:10:00Z"
        val remote=fields(deleted(transaction(5)),"last_modified_by_device_id" to JsonPrimitive(source),"updated_at" to JsonPrimitive(later)).copy(updatedAt=later)
        val p=prove(state(listOf(transaction(4),posting(4))),cloud(remote,listOf(deleted(posting(5)))).copy(remoteIntentWinner=true))
        assertEquals(2,p.acknowledgements.size);assertTrue(p.imports.all{it.deletedAt!=null})
    }
    @Test fun aWinnerFlagCannotAuthorizeAnUnknownOwnIntentOrOlderForeignIntent() {
        val local=fields(transaction(4),"note" to JsonPrimitive("Keep local"))
        val s=state(listOf(local,posting(4)))
        reject(s,cloud(transaction(5),listOf(posting(5))).copy(remoteIntentWinner=true))
        val older=fields(transaction(5),"last_modified_by_device_id" to JsonPrimitive(source),"updated_at" to JsonPrimitive("2026-10-26T00:00:00Z")).copy(updatedAt="2026-10-26T00:00:00Z")
        reject(s,cloud(older,listOf(posting(5))).copy(remoteIntentWinner=true))
    }

}
