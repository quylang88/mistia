package vn.com.quyln.mistia.core.model

import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class InvestmentWalletLinkPlanTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val device="44444444-4444-4444-4444-444444444444"
    private val previous="55555555-5555-5555-5555-555555555555"
    private val target="66666666-6666-6666-6666-666666666666"
    private val event="77777777-7777-7777-7777-777777777777"
    private val postingId="88888888-8888-8888-8888-888888888888"
    private val old="2026-10-21T00:00:00Z"
    private val now="2026-10-22T00:00:00Z"
    private fun change(raw:CloudRecord,fields:JsonObject)=raw.copy(payload=JsonObject(raw.payload+fields))
    private fun wallet(id:String)=WalletDraft(id=id,name="Wallet",kind=WalletKind.CASH,currencyCode="VND",openingBalanceMinor=10000).toMutation(owner,null,device,old).record
    private fun system(link:String?=previous)=change(wallet(investmentSystemWalletId(owner)),buildJsonObject {
        put("kind_raw_value","investment");put("system_purpose_raw_value","investmentProfit");put("opening_balance_minor",0L)
        put("investment_linked_wallet_id",link?.let(::JsonPrimitive) ?: JsonNull);put("sync_version",9007199254740993L)
        put("future_field","preserve")
    }).copy(syncVersion=9007199254740993L)
    private fun cash(amount:Long=1250,bucket:String="booked",id:String=postingId,deleted:Boolean=false)=CloudRecord(
        CloudEntity.INVESTMENT_POSTING.table,id,owner.value,buildJsonObject {
            put("id",id);put("user_id",owner.value);put("event_id",event);put("trade_id",JsonNull);put("asset_id",JsonNull)
            put("wallet_id",previous);put("ledger_transaction_id","99999999-9999-9999-9999-999999999999")
            put("role_raw_value","cashAccrual");put("cash_bucket_raw_value",bucket);put("cash_origin_raw_value","derived")
            put("amount_minor",amount);put("currency_code","VND");put("accounting_amount_minor",amount);put("accounting_currency_code","VND")
            put("occurred_at",old);put("created_at",old);put("updated_at",old);put("deleted_at",if(deleted)JsonPrimitive(old) else JsonNull)
            put("sync_version",0L);put("last_modified_by_device_id",device)
        },old,if(deleted)old else null,0L)
    private fun snapshot(system:CloudRecord=system(),selected:CloudRecord=wallet(target),postings:List<CloudRecord> = listOf(cash()))=
        InvestmentWalletSnapshot(owner,listOf(system,wallet(previous),selected)+postings)
    private fun request(system:CloudRecord=system(),selected:CloudRecord=wallet(target),move:Boolean=true,amount:Long=1250)=
        InvestmentWalletLinkRequest(LedgerWalletRecord.fromCloudRecord(system),LedgerWalletRecord.fromCloudRecord(selected),event,move,amount,"Move investment cash")
    private fun plan(source:InvestmentWalletSnapshot=snapshot(),request:InvestmentWalletLinkRequest=request())=planInvestmentWalletLink(source,request,device,now)
    private fun failure(expected:InvestmentWalletLinkError,action:()->Unit) {
        val result=runCatching(action);assertEquals(expected,(result.exceptionOrNull() as? InvestmentWalletLinkException)?.reason)
    }
    @Test fun firstLinkChangesOnlyTheCanonicalWalletAndRetainsExactVersionNullsAndUnknownFields() {
        val system=system(null);val result=plan(snapshot(system=system),request(system=system,move=false,amount=0))
        assertEquals(target,result.linkedWalletId);assertEquals(1,result.mutations.size)
        val (raw,pending)=result.mutations.single()
        assertEquals(investmentSystemWalletId(owner),raw.id);assertEquals(target,raw.payload.financeRawString("investment_linked_wallet_id"))
        assertEquals(9007199254740993L,raw.syncVersion);assertEquals(raw.syncVersion,pending.baseVersion)
        for(key in listOf("created_at","opening_balance_minor","currency_code","future_field","deleted_at","sync_version"))assertEquals(key,system.payload[key],raw.payload[key])
        assertEquals(raw.payload,pending.payload);assertEquals(owner.value,pending.subjectUserId)
    }
    @Test fun changingOnlyDefaultNeverMovesMoneyOrRewritesAnExistingPosting() {
        val source=snapshot();val result=plan(source,request(move=false))
        assertEquals(1,result.mutations.size);assertEquals(CloudEntity.LEDGER_WALLET.table,result.mutations.single().first.entity)
        assertEquals(1250L,source.rows.single{it.id==postingId}.payload.financeRawLong("amount_minor"))
    }
    @Test fun moveAllCreatesOneTransferAndTwoOppositeBookedManualPostingsAtomicallyWithTheLink() {
        val result=plan();assertEquals(4,result.mutations.size)
        val ledger=result.mutations.map{it.first}.single{it.entity==CloudEntity.LEDGER_TRANSACTION.table}
        assertEquals(investmentLedgerIdentity(event,"linked-wallet-move"),ledger.id)
        assertEquals("investmentReconciliation",ledger.payload.financeRawString("settlement_role_raw_value"))
        assertEquals("transfer",ledger.payload.financeRawString("primary_kind_raw_value"))
        assertEquals(previous,ledger.payload.financeRawString("source_wallet_id"));assertEquals(target,ledger.payload.financeRawString("destination_wallet_id"))
        for(key in listOf("amount_minor","destination_amount_minor","reporting_amount_minor"))assertEquals(1250L,ledger.payload.financeRawLong(key))
        val postings=result.mutations.map{it.first}.filter{it.entity==CloudEntity.INVESTMENT_POSTING.table}
        assertEquals(setOf(investmentLedgerIdentity(event,"old-linked-cash-posting"),investmentLedgerIdentity(event,"new-linked-cash-posting")),postings.map{it.id}.toSet())
        assertEquals(setOf(-1250L,1250L),postings.map{it.payload.financeRawLong("amount_minor")}.toSet())
        postings.forEach {
            assertEquals("booked",it.payload.financeRawString("cash_bucket_raw_value"));assertEquals("manual",it.payload.financeRawString("cash_origin_raw_value"))
            assertEquals("cashTransfer",it.payload.financeRawString("role_raw_value"));assertSame(JsonNull,it.payload["trade_id"]);assertSame(JsonNull,it.payload["asset_id"])
            assertEquals(it.payload.financeRawLong("amount_minor"),it.payload.financeRawLong("accounting_amount_minor"))
        }
        assertTrue(result.mutations.none{it.first.id==previous || it.first.id==target || it.first.id==postingId})
    }
    @Test fun bookedMoveSkipsKnownUnreconciledAndDeletedCashWithoutMovingEither() {
        val source=snapshot(postings=listOf(cash(),cash(999,"unreconciled","88888888-8888-8888-8888-888888888889"),cash(999,id="88888888-8888-8888-8888-888888888890",deleted=true)))
        assertEquals(1250L,plan(source).mutations.single{it.first.entity==CloudEntity.LEDGER_TRANSACTION.table}.first.payload.financeRawLong("amount_minor"))
    }
    @Test fun archivedCreditInvestmentAndMismatchedCurrencyTargetsAreRejected() {
        for(fields in listOf(buildJsonObject{put("is_archived",true)},buildJsonObject{put("kind_raw_value","creditCard")},
            buildJsonObject{put("kind_raw_value","investment")},buildJsonObject{put("currency_code","JPY")})) {
            val selected=change(wallet(target),fields)
            failure(InvestmentWalletLinkError.INVALID_WALLET){plan(snapshot(selected=selected),request(selected=selected))}
        }
    }
    @Test fun changedVisibleSourceOrBookedAmountCannotMoveUnconfirmedCash() {
        val changed=change(system(),buildJsonObject{put("investment_linked_wallet_id","dddddddd-dddd-dddd-dddd-dddddddddddd")})
        failure(InvestmentWalletLinkError.STALE_RECORD){plan(snapshot(system=changed))}
        failure(InvestmentWalletLinkError.STALE_RECORD){plan(snapshot(postings=listOf(cash(1251))))}
    }
    @Test fun malformedCashAndOverflowDoNotBecomeAnInventedZeroOrRoundedTransfer() {
        val damaged=change(cash(),buildJsonObject{put("accounting_amount_minor",JsonNull)})
        failure(InvestmentWalletLinkError.UNREADABLE_CASH){plan(snapshot(postings=listOf(damaged)))}
        failure(InvestmentWalletLinkError.UNREADABLE_CASH){plan(snapshot(postings=listOf(cash(Long.MAX_VALUE),cash(1,id="88888888-8888-8888-8888-888888888889"))),request(amount=Long.MAX_VALUE))}
    }
    @Test fun replayOfACompleteCommittedMovementCannotProduceAnotherTransfer() {
        val before=snapshot();val first=plan(before)
        val changed=first.mutations.map{it.first};val keys=changed.map{it.entity to it.id}.toSet()
        val after=before.copy(rows=before.rows.filter{it.entity to it.id !in keys}+changed)
        assertTrue(plan(after).mutations.isEmpty())
    }
    @Test fun partialOrUnrelatedDeterministicEventCannotBeAdoptedAsASuccessfulMovement() {
        val id=investmentLedgerIdentity(event,"linked-wallet-move")
        val collision=CloudRecord(CloudEntity.LEDGER_TRANSACTION.table,id,owner.value,buildJsonObject {
            put("id",id);put("user_id",owner.value);put("updated_at",old);put("deleted_at",JsonNull)
            put("settlement_role_raw_value","ordinary")
        },old,null,0)
        failure(InvestmentWalletLinkError.EVENT_CONFLICT){plan(snapshot().let{it.copy(rows=it.rows+collision)})}
    }
    @Test fun malformedOrForeignWalletIdentityNeverEnablesAnOwnedLink() {
        val foreign=change(wallet(target),buildJsonObject{put("user_id","aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")})
        failure(InvestmentWalletLinkError.UNREADABLE_SOURCE){plan(snapshot(selected=foreign))}
        val damaged=change(wallet(target),buildJsonObject{put("opening_balance_minor",JsonNull)})
        failure(InvestmentWalletLinkError.UNREADABLE_SOURCE){plan(snapshot(selected=damaged))}
    }
    @Test fun ackOnlyMetadataUsesTheLatestExactVersionWithoutInvalidatingVisibleConsent() {
        val ack=change(system(),buildJsonObject{put("updated_at",now);put("sync_version",9007199254740995L)}).copy(updatedAt=now,syncVersion=9007199254740995L)
        val result=plan(snapshot(system=ack),request(move=false))
        assertEquals(9007199254740995L,result.mutations.single().second.baseVersion)
        assertEquals(9007199254740995L,result.mutations.single().first.payload.financeRawLong("sync_version"))
    }

    @Test fun unreadableOrIncompatiblePreviousWalletCannotAdvertiseAMovableCashAmount() {
        for(fields in listOf(buildJsonObject{put("currency_code","JPY")},buildJsonObject{put("deleted_at",old)},buildJsonObject{put("kind_raw_value","creditCard")})) {
            val source=snapshot().let{snapshot ->snapshot.copy(rows=snapshot.rows.map{if(it.id==previous)change(it,fields) else it})}
            val view=investmentLinkedWalletView(source)
            assertNull(view.bookedMinor);assertTrue(view.eligibleWallets.any{it.id==target})
        }
    }
    @Test fun missingPreviousWalletCannotConvertOrphanCashIntoAConfirmedMove() {
        val view=investmentLinkedWalletView(snapshot().let{it.copy(rows=it.rows.filterNot{it.id==previous})})
        assertNull(view.bookedMinor);assertTrue(view.eligibleWallets.any{it.id==target})
    }

    @Test fun damagedOrArchivedReplayProvenanceCannotBeReportedAsACompleteMovement() {
        val before=snapshot();val changes=plan(before).mutations.map{it.first};val keys=changes.map{it.entity to it.id}.toSet()
        val applied=before.copy(rows=before.rows.filter{it.entity to it.id !in keys}+changes)
        for(fields in listOf(buildJsonObject{put("is_archived",true)},buildJsonObject{put("created_at","invalid")},buildJsonObject{put("sync_version",-1L)})) {
            val damaged=applied.copy(rows=applied.rows.map{if(it.entity==CloudEntity.LEDGER_TRANSACTION.table)change(it,fields) else it})
            failure(InvestmentWalletLinkError.EVENT_CONFLICT){plan(damaged)}
        }
        val mixedDate=applied.copy(rows=applied.rows.map{if(it.id==investmentLedgerIdentity(event,"new-linked-cash-posting"))change(it,buildJsonObject{put("occurred_at",old)}) else it})
        failure(InvestmentWalletLinkError.EVENT_CONFLICT){plan(mixedDate)}
    }

    @Test fun validNoncashAssetTransfersCannotMakeABookedCashMoveUnreadable() {
        val ignored=cash(999).let{it.copy(id="aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",payload=JsonObject(it.payload+buildJsonObject {
            put("id","aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");put("role_raw_value","transferOut");put("cash_bucket_raw_value",JsonNull)
        }))}
        val result=plan(snapshot(postings=listOf(cash(),ignored)))
        assertEquals(1250L,result.mutations.single{it.first.entity==CloudEntity.LEDGER_TRANSACTION.table}.first.payload.financeRawLong("amount_minor"))
    }

    @Test fun recognizedCurrencyCodesAreCanonicalBeforeBeingPassedToMoneyFormatting() {
        val raw=change(wallet(target),buildJsonObject{put("currency_code"," usd ")})
        assertEquals("USD",investmentLinkedWalletRecord(raw).currencyCode)
    }
    @Test fun canonicalCurrencyReadDoesNotInventAChangedVisibleWalletOrRewriteRawFields() {
        val sourceSystem=change(system(),buildJsonObject{put("currency_code"," vnd ")})
        val sourceTarget=change(wallet(target),buildJsonObject{put("currency_code"," vnd ")})
        val result=plan(snapshot(system=sourceSystem,selected=sourceTarget),request(system=sourceSystem,selected=sourceTarget,move=false))
        assertEquals(1,result.mutations.size)
        assertEquals(" vnd ",result.mutations.single().first.payload.financeRawString("currency_code"))
    }

}
