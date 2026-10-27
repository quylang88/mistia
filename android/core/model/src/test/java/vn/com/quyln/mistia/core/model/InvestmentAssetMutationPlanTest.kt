package vn.com.quyln.mistia.core.model

import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class InvestmentAssetMutationPlanTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val assetId="22222222-2222-2222-2222-222222222222"
    private val channelId="33333333-3333-3333-3333-333333333333"
    private val device="44444444-4444-4444-4444-444444444444"
    private val buyId="66666666-6666-6666-6666-666666666666"
    private val sellId="77777777-7777-7777-7777-777777777777"
    private val fundingId="88888888-8888-8888-8888-888888888888"
    private val returnId="99999999-9999-9999-9999-999999999999"
    private val old="2026-10-20T00:00:00Z"
    private val now="2026-10-21T00:00:00Z"
    private fun row(entity:CloudEntity,id:String,fields:JsonObject=buildJsonObject{}):CloudRecord {
        val p=buildJsonObject {
            put("id",id);put("user_id",owner.value);put("name","Cards");put("created_at",old);put("updated_at",old)
            put("is_archived",false);put("archived_at",JsonNull);put("deleted_at",JsonNull);put("sync_version",0L)
            put("last_modified_by_device_id",device);put("sort_order",0)
            fields.forEach{put(it.key,it.value)}
        }
        return CloudRecord(entity.table,id,owner.value,p,p.financeRawString("updated_at"),p.financeRawString("deleted_at"),p.financeRawLong("sync_version")!!)
    }
    private fun channel()=InvestmentChannelRecord(channelId,owner.value,"Collectibles","chart.line.uptrend.xyaxis","#9A67FF",0,false,null,old,old,null,0,device).toCloudRecord()
    private fun assetFields(unit:String?="box")=buildJsonObject {
        put("channel_id",channelId);put("currency_code","VND");put("image_path","private-preserved.jpg")
        put("default_unit_label",unit?.let(::JsonPrimitive) ?: JsonNull)
    }
    private fun asset(unit:String?="box")=row(CloudEntity.INVESTMENT_ASSET,assetId,assetFields(unit))
    private fun typed(unit:String?="box")=InvestmentAssetRecord(assetId,owner.value,channelId,"Cards","VND","private-preserved.jpg",unit,0,false,null,old,old,null,0,device)
    private fun draft(expected:InvestmentAssetRecord?=null,name:String=" Cards ",currency:String="VND",channel:String=channelId,unit:String=" Gift   Box ")=
        InvestmentAssetDraft(assetId,channel,name,currency,unit,expected)
    private fun snapshot(vararg rows:CloudRecord)=InvestmentAssetSnapshot(owner,rows.toList())
    private fun plan(snapshot:InvestmentAssetSnapshot,draft:InvestmentAssetDraft)=planInvestmentAssetMutation(snapshot,InvestmentAssetRequest.Save(draft),device,now)
    private fun error(expected:InvestmentAssetError,action:()->Unit) {
        val result=runCatching(action)
        assertEquals(expected,(result.exceptionOrNull() as? InvestmentAssetException)?.reason)
    }
    private fun wallet(id:String)=row(CloudEntity.LEDGER_WALLET,id,buildJsonObject {
        put("name","VND wallet");put("kind_raw_value",if(id==investmentSystemWalletId(owner)) "investment" else "cash")
        put("currency_code","VND");put("opening_balance_minor",0L)
    })
    private fun trade(id:String,kind:String,gross:Long,at:String)=row(CloudEntity.INVESTMENT_TRADE,id,buildJsonObject {
        put("channel_id",channelId);put("asset_id",assetId);put("kind_raw_value",kind);put("quantity_decimal_string","1")
        put("unit_label",JsonNull);put("gross_amount_minor",gross);put("currency_code","VND")
        put("accounting_gross_amount_minor",gross);put("accounting_currency_code","VND");put("occurred_at",at)
        put("funding_wallet_id",if(kind=="buy") JsonPrimitive(fundingId) else JsonNull)
        put("capital_return_wallet_id",if(kind=="sell") JsonPrimitive(returnId) else JsonNull)
        put("funding_wallet_currency_code",if(kind=="buy") JsonPrimitive("VND") else JsonNull)
        put("capital_return_wallet_currency_code",if(kind=="sell") JsonPrimitive("VND") else JsonNull)
        put("funding_wallet_amount_minor",if(kind=="buy") JsonPrimitive(gross) else JsonNull)
        put("capital_return_wallet_amount_minor",JsonNull)
        put("funding_to_accounting_rate_decimal_string",JsonNull);put("accounting_to_capital_return_rate_decimal_string",JsonNull)
        put("funding_ledger_transaction_id",JsonNull);put("capital_return_ledger_transaction_id",JsonNull);put("profit_loss_ledger_transaction_id",JsonNull)
        put("released_cost_basis_minor",0L);put("realized_profit_loss_minor",0L);put("position_quantity_after_decimal_string","0")
        put("position_cost_basis_after_minor",0L);put("note",JsonNull)
    })

    @Test fun createUsesStableIdentityAndCompleteWireFieldsWithOnlyOneAssetMutation() {
        val result=plan(snapshot(channel()),draft())
        assertEquals(assetId,result.asset.id);assertEquals("Cards",result.asset.name);assertEquals("Gift Box",result.asset.defaultUnitLabel)
        assertEquals("VND",result.asset.currencyCode);assertEquals(0,result.asset.sortOrder);assertNull(result.asset.imagePath)
        assertEquals(1,result.mutations.size)
        val (record,queue)=result.mutations.single()
        assertEquals(CloudEntity.INVESTMENT_ASSET.table,record.entity);assertEquals(0L,record.syncVersion)
        assertEquals(now,record.updatedAt);assertEquals(now,record.payload.financeRawString("created_at"))
        for(key in listOf("image_path","archived_at","deleted_at"))assertSame(JsonNull,record.payload[key])
        assertEquals(record.payload,queue.payload);assertEquals(owner.value,queue.subjectUserId);assertEquals(0L,queue.baseVersion)
    }
    @Test fun missingArchivedForeignOrUnreadableChannelNeverInventsAnAllowedSave() {
        error(InvestmentAssetError.MISSING_CHANNEL){plan(snapshot(),draft())}
        val archived=channel().copy(payload=JsonObject(channel().payload+("is_archived" to JsonPrimitive(true))))
        error(InvestmentAssetError.MISSING_CHANNEL){plan(snapshot(archived),draft())}
        val foreign=channel().copy(ownerUserId="aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
        error(InvestmentAssetError.UNREADABLE_SOURCE){plan(snapshot(foreign),draft())}
    }
    @Test fun requiredNameUnitAndCurrencyFollowActualSourceAdmission() {
        error(InvestmentAssetError.NAME_REQUIRED){plan(snapshot(channel()),draft(name="\u0085\u200b"))}
        error(InvestmentAssetError.UNIT_REQUIRED){plan(snapshot(channel()),draft(unit="\u200b \n"))}
        error(InvestmentAssetError.INVALID_CURRENCY){plan(snapshot(channel()),draft(currency="???"))}
    }
    @Test fun renamePreservesCurrencyImageUnknownFieldsAndLatestExactLongVersionAfterAck() {
        val original=asset().copy(syncVersion=9007199254740999L,payload=JsonObject(asset().payload+buildJsonObject {
            put("sync_version",9007199254740999L);put("future_field","preserve");put("updated_at",now)
        }),updatedAt=now)
        val result=plan(snapshot(channel(),original),draft(expected=typed(),name="Renamed",unit="box"))
        val changed=result.mutations.single().first
        assertEquals(9007199254740999L,changed.syncVersion);assertEquals(9007199254740999L,result.mutations.single().second.baseVersion)
        assertEquals("Renamed",result.asset.name)
        for(key in listOf("image_path","created_at","currency_code","channel_id","future_field","sync_version"))assertEquals(key,original.payload[key],changed.payload[key])
    }
    @Test fun anyHistoryIncludingTombstoneLocksChannelAndCurrencyWhileNameAndUnitRemainEditable() {
        val history=trade(buyId,"buy",100,old).copy(deletedAt=old)
        error(InvestmentAssetError.HISTORY_LOCKS_ACCOUNTING){plan(snapshot(channel(),asset(),history),draft(expected=typed(),currency="JPY"))}
        val result=plan(snapshot(channel(),asset(),history),draft(expected=typed(),name="Renamed",unit="pack"))
        assertEquals(1,result.mutations.size);assertEquals("pack",result.asset.defaultUnitLabel)
        assertEquals("Renamed",result.asset.name)
    }
    @Test fun newerVisibleSourceCannotBeOverwrittenAndCreateReplayDoesNotDuplicate() {
        val changed=asset().copy(payload=JsonObject(asset().payload+("name" to JsonPrimitive("Newer name"))))
        error(InvestmentAssetError.STALE_RECORD){plan(snapshot(channel(),changed),draft(expected=typed()))}
        val replay=plan(snapshot(channel(),asset("Gift Box")),draft())
        assertTrue(replay.mutations.isEmpty());assertEquals(assetId,replay.asset.id)
    }
    @Test fun archiveRefusesPositiveStockAndRestoreKeepsIdentityWithoutChangingHistory() {
        val stock=trade(buyId,"buy",100,old).copy(payload=JsonObject(trade(buyId,"buy",100,old).payload+("position_quantity_after_decimal_string" to JsonPrimitive("0.5"))))
        error(InvestmentAssetError.OPEN_POSITION){planInvestmentAssetMutation(snapshot(channel(),asset(),stock),InvestmentAssetRequest.Archive(typed(),true),device,now)}
        val archived=typed().copy(isArchived=true,archivedAt=old)
        val raw=asset().copy(payload=JsonObject(asset().payload+mapOf("is_archived" to JsonPrimitive(true),"archived_at" to JsonPrimitive(old))))
        val result=planInvestmentAssetMutation(snapshot(channel(),raw),InvestmentAssetRequest.Archive(archived,false),device,now)
        assertEquals(1,result.mutations.size);assertEquals(assetId,result.asset.id);assertFalse(result.asset.isArchived);assertNull(result.asset.archivedAt)
    }
    @Test fun firstDefaultUnitResolutionRebuildsFifoLedgerCapitalProfitAndCashInOneBatch() {
        val source=snapshot(channel(),asset(null),wallet(investmentSystemWalletId(owner)),wallet(fundingId),wallet(returnId),
            trade(buyId,"buy",100,old),trade(sellId,"sell",150,now))
        val result=plan(source,draft(expected=typed(null),unit=" Box "))
        assertEquals("Box",result.asset.defaultUnitLabel)
        val records=result.mutations.map{it.first}
        val trades=records.filter{it.entity==CloudEntity.INVESTMENT_TRADE.table}.associateBy{it.id}
        assertEquals(setOf(buyId,sellId),trades.keys)
        assertTrue(trades.values.all{it.payload.financeRawString("unit_label")=="Box"})
        assertEquals(100L,trades.getValue(sellId).payload.financeRawLong("released_cost_basis_minor"))
        assertEquals(50L,trades.getValue(sellId).payload.financeRawLong("realized_profit_loss_minor"))
        assertEquals("0",trades.getValue(sellId).payload.financeRawString("position_quantity_after_decimal_string"))
        val ledger=records.filter{it.entity==CloudEntity.LEDGER_TRANSACTION.table}
        assertEquals(3,ledger.size)
        val roles=ledger.associateBy{it.payload.financeRawString("settlement_role_raw_value")}
        assertEquals(100L,roles.getValue("investmentFunding").payload.financeRawLong("amount_minor"))
        assertEquals(100L,roles.getValue("investmentCapitalReturn").payload.financeRawLong("amount_minor"))
        assertEquals(50L,roles.getValue("investmentRealizedProfit").payload.financeRawLong("amount_minor"))
        val postings=records.filter{it.entity==CloudEntity.INVESTMENT_POSTING.table}
        assertEquals(4,postings.size)
        val cash=postings.single{it.payload.financeRawString("role_raw_value")=="cashAccrual"}
        assertEquals(50L,cash.payload.financeRawLong("amount_minor"));assertEquals(returnId,cash.payload.financeRawString("wallet_id"))
        assertEquals("booked",cash.payload.financeRawString("cash_bucket_raw_value"));assertEquals("derived",cash.payload.financeRawString("cash_origin_raw_value"))
        assertEquals(10,records.size);assertTrue(records.none{it.entity==CloudEntity.LEDGER_WALLET.table})
        result.mutations.forEach{(record,queue)->assertEquals(record.payload,queue.payload);assertEquals(owner.value,record.ownerUserId);assertEquals(owner.value,queue.subjectUserId)}
    }
    @Test fun malformedHistoryUnitCannotBeSilentlyTreatedAsReadableWhenResolvingDefault() {
        val raw=trade(buyId,"buy",100,old)
        val damaged=raw.copy(payload=JsonObject(raw.payload+("unit_label" to buildJsonObject{put("bad",true)})))
        error(InvestmentAssetError.UNREADABLE_SOURCE) {
            plan(snapshot(channel(),asset(null),damaged),draft(expected=typed(null),unit="box"))
        }
    }
    @Test fun labellingDeletedHistoryNeverResurrectsItsAuthoritativeEnvelopeTombstone() {
        val raw=trade(buyId,"buy",100,old).copy(deletedAt=old)
        val result=plan(snapshot(channel(),asset(null),raw),draft(expected=typed(null),unit="box"))
        val deleted=result.mutations.single{it.first.entity==CloudEntity.INVESTMENT_TRADE.table}
        assertEquals(old,deleted.first.deletedAt)
        assertEquals(old,deleted.first.payload.financeRawString("deleted_at"))
        assertEquals(old,deleted.second.payload!!.financeRawString("deleted_at"))
        assertEquals("box",deleted.first.payload.financeRawString("unit_label"))
        assertEquals(MutationKind.DELETE,deleted.second.kind)
        assertEquals(2,result.mutations.size)
    }

    @Test fun obsoleteCanonicalLedgerIsTombstonedEvenWhenOldLinksAndPostingsAreMissing() {
        // Actual Swift InvestmentLedgerIdentity for buyId and capital-return.
        val oldId="ccf1bc15-b45f-56bd-9598-653fbf3f711f"
        val obsolete=row(CloudEntity.LEDGER_TRANSACTION,oldId,buildJsonObject {
            put("settlement_role_raw_value","investmentCapitalReturn");put("amount_minor",999L);put("future_field","preserve")
        })
        val result=plan(snapshot(channel(),asset(null),wallet(investmentSystemWalletId(owner)),wallet(fundingId),
            trade(buyId,"buy",100,old),obsolete),draft(expected=typed(null),unit="box"))
        val deleted=result.mutations.map{it.first}.singleOrNull{it.entity==CloudEntity.LEDGER_TRANSACTION.table && it.id==oldId}
        assertNotNull("Canonical obsolete leg must not remain financially active",deleted)
        assertEquals(now,deleted!!.deletedAt);assertEquals(now,deleted.payload.financeRawString("deleted_at"))
        assertEquals(JsonPrimitive("preserve"),deleted.payload["future_field"])
        assertEquals(MutationKind.DELETE,result.mutations.single{it.first.entity==deleted.entity && it.first.id==deleted.id}.second.kind)
    }
    @Test fun freeLegacyBuyStillRequiresTheFundingDependencyUsedBySwiftRebuild() {
        val raw=trade(buyId,"buy",0,old)
        val noFunding=raw.copy(payload=JsonObject(raw.payload+("funding_wallet_id" to JsonNull)))
        error(InvestmentAssetError.MISSING_WALLET) {
            plan(snapshot(channel(),asset(null),wallet(investmentSystemWalletId(owner)),noFunding),draft(expected=typed(null),unit="box"))
        }
    }
    @Test fun storedFxRebuildPostsLocalCashAmountsAndIndependentAccountingAmounts() {
        fun code(raw:CloudRecord,value:String)=raw.copy(payload=JsonObject(raw.payload+("currency_code" to JsonPrimitive(value))))
        val originalBuy=trade(buyId,"buy",100,old);val originalSale=trade(sellId,"sell",150,now)
        val purchase=originalBuy.copy(payload=JsonObject(originalBuy.payload+mapOf(
            "funding_wallet_currency_code" to JsonPrimitive("USD"),"funding_to_accounting_rate_decimal_string" to JsonPrimitive("2.5"))))
        val sale=originalSale.copy(payload=JsonObject(originalSale.payload+mapOf(
            "capital_return_wallet_currency_code" to JsonPrimitive("JPY"),"accounting_to_capital_return_rate_decimal_string" to JsonPrimitive("0.5"))))
        val result=plan(snapshot(channel(),asset(null),wallet(investmentSystemWalletId(owner)),code(wallet(fundingId),"USD"),
            code(wallet(returnId),"JPY"),purchase,sale),draft(expected=typed(null),unit="box"))
        val records=result.mutations.map{it.first}
        val ledger=records.filter{it.entity==CloudEntity.LEDGER_TRANSACTION.table}.associateBy{it.payload.financeRawString("settlement_role_raw_value")}
        assertEquals(4000L,ledger.getValue("investmentFunding").payload.financeRawLong("amount_minor"))
        assertEquals(50L,ledger.getValue("investmentCapitalReturn").payload.financeRawLong("amount_minor"))
        assertEquals(25L,ledger.getValue("investmentRealizedProfit").payload.financeRawLong("amount_minor"))
        assertEquals(50L,ledger.getValue("investmentRealizedProfit").payload.financeRawLong("reporting_amount_minor"))
        val accrual=records.single{it.entity==CloudEntity.INVESTMENT_POSTING.table && it.payload.financeRawString("role_raw_value")=="cashAccrual"}
        assertEquals(25L,accrual.payload.financeRawLong("amount_minor"));assertEquals("JPY",accrual.payload.financeRawString("currency_code"))
        assertEquals(50L,accrual.payload.financeRawLong("accounting_amount_minor"));assertEquals("VND",accrual.payload.financeRawString("accounting_currency_code"))
    }
    @Test fun missingStoredFxRateCannotReuseTheObsoleteWalletAmountSnapshot() {
        val usd=wallet(fundingId).copy(payload=JsonObject(wallet(fundingId).payload+("currency_code" to JsonPrimitive("USD"))))
        error(InvestmentAssetError.MISSING_EXCHANGE_RATE) {
            plan(snapshot(channel(),asset(null),wallet(investmentSystemWalletId(owner)),usd,trade(buyId,"buy",100,old)),draft(expected=typed(null),unit="box"))
        }
    }

    @Test fun absentRequiredTradeAssetMembershipCannotInventAnUnlockedAccountingHistory() {
        val original=trade(buyId,"buy",100,old)
        for(payload in listOf(JsonObject(original.payload- "asset_id"),JsonObject(original.payload+("asset_id" to JsonNull)))) {
            error(InvestmentAssetError.UNREADABLE_SOURCE) {
                plan(snapshot(channel(),asset(),original.copy(payload=payload)),draft(expected=typed(),currency="JPY",unit="box"))
            }
        }
    }

    @Test fun invalidFrozenCreationMetadataInAnExistingDerivedLegCannotBePublishedAsAValidRebuild() {
        // Actual Swift funding ledger identity for buyId.
        val oldLedger=row(CloudEntity.LEDGER_TRANSACTION,"1789f27c-2440-570b-b363-46ff11f061a2",buildJsonObject {
            put("settlement_role_raw_value","investmentFunding");put("created_at","damaged");put("amount_minor",100L)
        })
        error(InvestmentAssetError.UNREADABLE_SOURCE) {
            plan(snapshot(channel(),asset(null),wallet(investmentSystemWalletId(owner)),wallet(fundingId),trade(buyId,"buy",100,old),oldLedger),
                draft(expected=typed(null),unit="box"))
        }
    }

    @Test fun archiveRecomputesValidFifoBeforeTrustingAStalePersistedPosition() {
        val buy=trade(buyId,"buy",100,old)
        error(InvestmentAssetError.OPEN_POSITION) {
            planInvestmentAssetMutation(snapshot(channel(),asset(),buy),InvestmentAssetRequest.Archive(typed(),true),device,now)
        }
    }
    @Test fun archiveAllowsAComputedClosedPositionEvenIfPersistedQuantityIsStalePositive() {
        val sell=trade(sellId,"sell",150,now).let { it.copy(payload=JsonObject(it.payload+("position_quantity_after_decimal_string" to JsonPrimitive("9")))) }
        val result=planInvestmentAssetMutation(snapshot(channel(),asset(),trade(buyId,"buy",100,old),sell),InvestmentAssetRequest.Archive(typed(),true),device,now)
        assertTrue(result.asset.isArchived);assertEquals(1,result.mutations.size)
    }

    @Test fun storedMajorUnitRatesRespectUsdCentsInBothFundingAndCapitalDirections() {
        fun fields(raw:CloudRecord,values:JsonObject)=raw.copy(payload=JsonObject(raw.payload+values))
        val buy=fields(trade(buyId,"buy",2500000,old),buildJsonObject {
            put("funding_wallet_currency_code","USD");put("funding_to_accounting_rate_decimal_string","25000")
        })
        val sell=fields(trade(sellId,"sell",3750000,now),buildJsonObject {
            put("capital_return_wallet_currency_code","USD");put("accounting_to_capital_return_rate_decimal_string","0.00004")
        })
        val result=plan(snapshot(channel(),asset(null),wallet(investmentSystemWalletId(owner)),
            fields(wallet(fundingId),buildJsonObject{put("currency_code","USD")}),
            fields(wallet(returnId),buildJsonObject{put("currency_code","USD")}),buy,sell),draft(expected=typed(null),unit="box"))
        val records=result.mutations.map{it.first}
        val ledger=records.filter{it.entity==CloudEntity.LEDGER_TRANSACTION.table}.associateBy{it.payload.financeRawString("settlement_role_raw_value")}
        assertEquals(10000L,ledger.getValue("investmentFunding").payload.financeRawLong("amount_minor"))
        assertEquals(10000L,ledger.getValue("investmentCapitalReturn").payload.financeRawLong("amount_minor"))
        assertEquals(5000L,ledger.getValue("investmentRealizedProfit").payload.financeRawLong("amount_minor"))
        assertEquals(1250000L,ledger.getValue("investmentRealizedProfit").payload.financeRawLong("reporting_amount_minor"))
        val postings=records.filter{it.entity==CloudEntity.INVESTMENT_POSTING.table}.associateBy{it.payload.financeRawString("role_raw_value")}
        assertEquals(-10000L,postings.getValue("funding").payload.financeRawLong("amount_minor"))
        assertEquals(5000L,postings.getValue("cashAccrual").payload.financeRawLong("amount_minor"))
        assertEquals("USD",postings.getValue("cashAccrual").payload.financeRawString("currency_code"))
    }

    @Test fun archiveCannotTreatMissingRawQuantityAsAReadablePersistedFallback() {
        val damaged=trade(buyId,"buy",100,old).let{it.copy(payload=JsonObject(it.payload-"quantity_decimal_string"))}
        error(InvestmentAssetError.UNREADABLE_POSITION) {
            planInvestmentAssetMutation(snapshot(channel(),asset(),damaged),InvestmentAssetRequest.Archive(typed(),true),device,now)
        }
    }
    @Test fun engineFailureOnTypedLegacyHistoryRetainsTheSwiftPersistedFallback() {
        val oversold=trade(sellId,"sell",100,old)
        val result=planInvestmentAssetMutation(snapshot(channel(),asset(),oversold),InvestmentAssetRequest.Archive(typed(),true),device,now)
        assertTrue(result.asset.isArchived);assertEquals(1,result.mutations.size)
        val open=oversold.copy(payload=JsonObject(oversold.payload+("position_quantity_after_decimal_string" to JsonPrimitive("1"))))
        error(InvestmentAssetError.OPEN_POSITION) {
            planInvestmentAssetMutation(snapshot(channel(),asset(),open),InvestmentAssetRequest.Archive(typed(),true),device,now)
        }
    }

}
