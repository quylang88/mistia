package vn.com.quyln.mistia.core.model

import java.math.BigInteger
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class InvestmentCashTransferPlanTest {
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
    private fun after(s:InvestmentCashReadSnapshot,p:InvestmentCashTransferPlan)=s.copy(rows=s.rows+p.mutations.map{it.first})
    @Test fun sameWalletDepositClassifiesCashWithoutChangingItsActualBalanceOrAnyWalletOpening() {
        val before=source();val result=plan(before);assertEquals(2,result.mutations.size)
        val ledger=result.mutations.single{it.first.entity==CloudEntity.LEDGER_TRANSACTION.table}.first
        val posting=result.mutations.single{it.first.entity==CloudEntity.INVESTMENT_POSTING.table}.first
        assertEquals(event,ledger.id);assertEquals(linkedId,ledger.payload.financeRawString("source_wallet_id"));assertEquals(linkedId,ledger.payload.financeRawString("destination_wallet_id"))
        assertEquals("investmentCashDeposit",ledger.payload.financeRawString("settlement_role_raw_value"));assertEquals(500L,ledger.payload.financeRawLong("destination_amount_minor"))
        assertEquals("Test note",ledger.payload.financeRawString("note"));assertEquals(occurred,ledger.payload.financeRawString("occurred_at"))
        assertEquals(investmentLedgerIdentity(event,"cash-transfer-posting"),posting.id);assertEquals(500L,posting.payload.financeRawLong("accounting_amount_minor"))
        for(key in listOf("trade_id","asset_id"))assertEquals(JsonNull,posting.payload[key])
        assertEquals("booked",posting.payload.financeRawString("cash_bucket_raw_value"));assertEquals("manual",posting.payload.financeRawString("cash_origin_raw_value"))
        val read=investmentCashFinancialView(after(before,result),"VND")
        assertEquals(n(10000),read.linkedActualMinor);assertEquals(n(800),read.availableMinor)
        assertTrue(result.mutations.all{(record,queue)->record.ownerUserId==owner.value && queue.subjectUserId==owner.value && record.syncVersion==0L && queue.payload==record.payload})
    }
    @Test fun otherWalletDepositMovesOnlyActualCashAndCreatesTwoMatchingFinancialQueues() {
        val before=source();val result=plan(before,request(before,selected=otherId));val after=after(before,result)
        val balances=financeWalletBalancesRaw(owner,after.rows.filter{it.entity==CloudEntity.LEDGER_TRANSACTION.table},after.rows.filter{it.entity==CloudEntity.LEDGER_WALLET.table})!!
        assertEquals(n(9500),balances[otherId]);assertEquals(n(10500),balances[linkedId]);assertEquals(n(800),investmentCashFinancialView(after,"VND").availableMinor)
        assertEquals(2,result.mutations.size);assertTrue(result.mutations.none{it.first.entity==CloudEntity.LEDGER_WALLET.table})
    }
    @Test fun otherWalletWithdrawalSubtractsLinkedBookedCashAndMovesTheActualLedgerPair() {
        val before=source();val result=plan(before,request(before,InvestmentCashTransferDirection.WITHDRAWAL,otherId,300));val after=after(before,result)
        val balances=financeWalletBalancesRaw(owner,after.rows.filter{it.entity==CloudEntity.LEDGER_TRANSACTION.table},after.rows.filter{it.entity==CloudEntity.LEDGER_WALLET.table})!!
        assertEquals(n(9700),balances[linkedId]);assertEquals(n(10300),balances[otherId]);assertEquals(BigInteger.ZERO,investmentCashFinancialView(after,"VND").availableMinor)
        assertEquals(-300L,result.mutations.single{it.first.entity==CloudEntity.INVESTMENT_POSTING.table}.first.payload.financeRawLong("amount_minor"))
    }
    @Test fun committedCreateReplaySucceedsBeforeTheNowExhaustedCapacityCheckWithoutWritingAgain() {
        val before=source();val request=request(before);val first=plan(before,request)
        val committed=after(before,first).let{it.copy(rows=it.rows.map{row ->if(row.id==event || row.entity==CloudEntity.INVESTMENT_POSTING.table && row.id!=before.rows.last().id)
            row.copy(syncVersion=9007199254740993L).with("sync_version",JsonPrimitive(9007199254740993L)) else row})}
        assertTrue(plan(committed,request).mutations.isEmpty())
    }
    @Test fun partialOrReusedEventAndDamagedReplayMoneyReferencesNullsOrTimeCannotBecomeSuccess() {
        val before=source();val request=request(before);val first=plan(before,request);val committed=after(before,first)
        failed(InvestmentCashTransferError.EVENT_CONFLICT){plan(after(before,first.copy(mutations=first.mutations.take(1))),request)}
        for((key,value) in listOf("amount_minor" to JsonPrimitive(501L),"destination_amount_minor" to JsonPrimitive(501L),"settlement_role_raw_value" to JsonPrimitive("investmentCashWithdrawal"),"occurred_at" to JsonPrimitive(now),"category_id" to JsonPrimitive(otherId)))
            failed(InvestmentCashTransferError.EVENT_CONFLICT){plan(committed.copy(rows=committed.rows.map{if(it.id==event)it.with(key,value) else it}),request)}
        for((key,value) in listOf("amount_minor" to JsonPrimitive(501L),"wallet_id" to JsonPrimitive(otherId),"trade_id" to JsonPrimitive(otherId),"occurred_at" to JsonPrimitive(now),"cash_origin_raw_value" to JsonPrimitive("derived")))
            failed(InvestmentCashTransferError.EVENT_CONFLICT){plan(committed.copy(rows=committed.rows.map{if(it.id==investmentLedgerIdentity(event,"cash-transfer-posting"))it.with(key,value) else it}),request)}
    }
    @Test fun sourceCurrencyOrFrozenVisibleWalletAndCapacityChangesCannotSilentlyChangeConsent() {
        val before=source();val request=request(before)
        failed(InvestmentCashTransferError.STALE_RECORD){plan(before.copy(rows=before.rows.map{if(it.id==linkedId)it.with("name",JsonPrimitive("Changed")) else it}),request)}
        failed(InvestmentCashTransferError.STALE_RECORD){plan(before.copy(rows=before.rows.map{if(it.entity==CloudEntity.INVESTMENT_TRADE.table)it.with("realized_profit_loss_minor",JsonPrimitive(900L)) else it}),request)}
        val wrong=before.copy(rows=before.rows.map{if(it.id==otherId)it.with("currency_code",JsonPrimitive("JPY")) else it})
        val selected=investmentLinkedWalletRecord(wrong.rows.single{it.id==otherId})
        failed(InvestmentCashTransferError.INVALID_WALLET){plan(wrong,request.copy(expectedSelected=selected,draft=request.draft.copy(walletId=otherId)))}
    }
    @Test fun foreignBodyAndMalformedRequiredDatesOrNonpositiveAmountsAreRejectedBeforePlanning() {
        val before=source();val request=request(before)
        failed(InvestmentCashTransferError.UNREADABLE_SOURCE){plan(before.copy(rows=before.rows.map{if(it.entity==CloudEntity.INVESTMENT_TRADE.table)it.with("user_id",JsonPrimitive(otherId)) else it}),request)}
        failed(InvestmentCashTransferError.INVALID_INPUT){plan(before,request.copy(draft=request.draft.copy(occurredAt="broken")))}
        failed(InvestmentCashTransferError.INVALID_INPUT){plan(before,request.copy(draft=request.draft.copy(amountMinor=0)))}
        failed(InvestmentCashTransferError.EXCEEDS_LIMIT){plan(before,this.request(before,amount=501))}
    }
    @Test fun sameWalletWithdrawalChangesOnlyAllocationAndLeavesActualCashUnchanged() {
        val before=source();val result=plan(before,request(before,InvestmentCashTransferDirection.WITHDRAWAL,linkedId,300))
        val read=investmentCashFinancialView(after(before,result),"VND")
        assertEquals(n(10000),read.linkedActualMinor);assertEquals(BigInteger.ZERO,read.availableMinor)
        assertEquals(n(10000),read.linkedBalances?.ordinaryMinor)
    }

    @Test fun anotherPostingAlreadyUsingThisEventCannotBeTreatedAsANewCashTransfer() {
        val before=source();val request=request(before)
        val reused=before.copy(rows=before.rows.map{if(it.entity==CloudEntity.INVESTMENT_POSTING.table)it.with("event_id",JsonPrimitive(event)) else it})
        failed(InvestmentCashTransferError.EVENT_CONFLICT){plan(reused,request)}
    }
    @Test fun normalizedUsdCentsStayCentsInBothLedgerLegsAndTheCashPosting() {
        val before=source();val original=request(before)
        val usd=before.copy(rows=before.rows.map{row ->row.copy(payload=JsonObject(row.payload.mapValues{(key,value)->
            if(key=="currency_code")JsonPrimitive(" usd ") else if(key=="accounting_currency_code")JsonPrimitive("USD") else value
        }))})
        fun wallet(id:String)=investmentLinkedWalletRecord(usd.rows.single{it.id==id})
        val request=original.copy(expectedSystem=wallet(investmentSystemWalletId(owner)),expectedLinked=wallet(linkedId),expectedSelected=wallet(linkedId))
        val result=plan(usd,request)
        val ledger=result.mutations.single{it.first.entity==CloudEntity.LEDGER_TRANSACTION.table}.first
        assertEquals("USD",ledger.payload.financeRawString("source_currency_code"));assertEquals(500L,ledger.payload.financeRawLong("amount_minor"));assertEquals(500L,ledger.payload.financeRawLong("destination_amount_minor"))
        val read=investmentCashFinancialView(after(usd,result),"VND")
        assertEquals("USD",read.currencyCode);assertEquals(n(800),read.availableMinor);assertEquals(n(10000),read.linkedActualMinor)
    }

    @Test fun noteUsesTheSourceFoundationWhitespaceSetRatherThanJavaControlTrimming() {
        val before=source();val request=request(before)
        for((input,expected) in listOf("\u0085\u200b Note \u200b\u0085" to JsonPrimitive("Note"),"\u0085\u200b" to JsonNull,"\u001cNote\u001c" to JsonPrimitive("\u001cNote\u001c"))) {
            val result=plan(before,request.copy(draft=request.draft.copy(note=input)))
            assertEquals(expected,result.mutations.single{it.first.entity==CloudEntity.LEDGER_TRANSACTION.table}.first.payload["note"])
        }
    }

    @Test fun formDefaultsToFirstEligibleDepositButAlwaysLinkedWalletForWithdrawal() {
        val before=source().let{it.copy(rows=it.rows.map{row ->if(row.id==otherId)row.with("sort_order",JsonPrimitive(-1)) else row})}
        val deposit=readInvestmentCashTransfer(before,InvestmentCashTransferDirection.DEPOSIT,null,0)
        assertEquals(otherId,deposit.selected.id);assertEquals(listOf(otherId,linkedId),deposit.eligibleWallets.map{it.id})
        assertEquals(500L,deposit.preview.maximumMinor);assertEquals(n(10000),deposit.preview.sourceOrdinaryMinor)
        val withdrawal=readInvestmentCashTransfer(before,InvestmentCashTransferDirection.WITHDRAWAL,null,0)
        assertEquals(linkedId,withdrawal.selected.id);assertEquals(300L,withdrawal.preview.maximumMinor)
    }
    @Test fun formCannotSilentlyReplaceAnExplicitWrongCurrencyWalletOrInventUnreadableCash() {
        val before=source();val wrong=before.copy(rows=before.rows.map{if(it.id==otherId)it.with("currency_code",JsonPrimitive("JPY")) else it})
        failed(InvestmentCashTransferError.INVALID_WALLET){readInvestmentCashTransfer(wrong,InvestmentCashTransferDirection.DEPOSIT,otherId,500)}
        val damaged=before.copy(rows=before.rows.map{if(it.entity==CloudEntity.INVESTMENT_POSTING.table)it.with("amount_minor",JsonNull) else it})
        failed(InvestmentCashTransferError.UNREADABLE_SOURCE){readInvestmentCashTransfer(damaged,InvestmentCashTransferDirection.DEPOSIT,linkedId,500)}
    }
    @Test fun formReadNeverDiscardsAForeignTradeFromItsWholeSourceScope() {
        val before=source();val foreign=before.copy(rows=before.rows.map{if(it.entity==CloudEntity.INVESTMENT_TRADE.table)it.with("user_id",JsonPrimitive(otherId)) else it})
        failed(InvestmentCashTransferError.UNREADABLE_SOURCE){readInvestmentCashTransfer(foreign,InvestmentCashTransferDirection.DEPOSIT,linkedId,500)}
    }
    @Test fun formCanWithdrawOneWireMaximumFromAnExactLinkedAllocationBeyondLong() {
        val before=source();val cash=before.rows.single{it.entity==CloudEntity.INVESTMENT_POSTING.table}.with("amount_minor",JsonPrimitive(Long.MAX_VALUE)).with("accounting_amount_minor",JsonPrimitive(Long.MAX_VALUE))
        val second=cash.copy(id="88888888-8888-4888-8888-888888888888").with("id",JsonPrimitive("88888888-8888-4888-8888-888888888888"))
        val large=before.copy(rows=before.rows.filter{it.entity!=CloudEntity.INVESTMENT_POSTING.table}+listOf(cash,second))
        val read=readInvestmentCashTransfer(large,InvestmentCashTransferDirection.WITHDRAWAL,linkedId,Long.MAX_VALUE)
        assertEquals(Long.MAX_VALUE,read.preview.maximumMinor);assertEquals(n(Long.MAX_VALUE)*BigInteger.TWO,read.preview.linkedBookedMinor);assertTrue(read.preview.isValid)
    }

}
