package vn.com.quyln.mistia.core.model

import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class InvestmentTradeResultProjectionTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val channel="22222222-2222-2222-2222-222222222222"
    private val assetId="33333333-3333-3333-3333-333333333333"
    private val walletId="44444444-4444-4444-4444-444444444444"
    private val id="55555555-5555-5555-5555-555555555555"
    private val device="66666666-6666-6666-6666-666666666666"
    private val saleId="77777777-7777-7777-7777-777777777777"
    private val now="2026-10-26T00:00:00Z"
    private val serverTime="2026-10-26T00:30:00Z"
    private fun metadata(code:String="VND",walletCode:String=code):InvestmentPurchaseSnapshot {
        val asset=InvestmentAssetRecord(assetId,owner.value,channel,"Cards",code,null,"box",0,false,null,now,now,null,0,device)
        val channelRow=InvestmentChannelRecord(channel,owner.value,"Shop","shippingbox.fill","#9A67FF",0,false,null,now,now,null,0,device).toCloudRecord()
        val wallet=WalletDraft(id=walletId,name="Cash",kind=WalletKind.CASH,currencyCode=walletCode,openingBalanceMinor=10000).toMutation(owner,null,device,now).record
        val system=WalletDraft(id=investmentSystemWalletId(owner),name="Investment",kind=WalletKind.CASH,currencyCode="VND").toMutation(owner,null,device,now).record.let{
            it.copy(payload=JsonObject(it.payload+buildJsonObject{put("kind_raw_value","investment");put("system_purpose_raw_value","investmentProfit")}))
        }
        return InvestmentPurchaseSnapshot(owner,listOf(asset.toCloudRecord(),channelRow,wallet,system))
    }
    private fun buy(gross:Long=70,code:String="VND",walletCode:String=code):Pair<InvestmentPurchaseSnapshot,InvestmentPurchasePlan> {
        val s=metadata(code,walletCode);val asset=InvestmentAssetRecord.fromCloudRecord(s.rows.single{it.id==assetId})
        val wallet=LedgerWalletRecord.fromCloudRecord(s.rows.single{it.id==walletId})
        val accounting=if(code=="JPY")Math.multiplyExact(gross,165) else gross
        val request=InvestmentPurchaseRequest(InvestmentPurchaseDraft(id,assetId,"2.5","box",gross,accounting,"VND",if(code=="JPY" && gross>0)"165" else null,null,null,
            if(gross>0)walletId else null,if(gross>0)gross else null,if(walletCode=="JPY" && gross>0)"165" else null,null,now,now),asset,if(gross>0)wallet else null,null,"Reserve")
        return s to planInvestmentPurchase(s,request,device,now)
    }
    private fun source(s:InvestmentPurchaseSnapshot,mutations:List<Pair<CloudRecord,PendingMutation>>,tradeId:String=id):InvestmentTradePublicationSnapshot {
        val keys=mutations.map{it.first.entity to it.first.id}.toSet()
        return InvestmentTradePublicationSnapshot(owner,tradeId,s.rows.filterNot{it.entity to it.id in keys}+mutations.map{it.first},
            mutations.map{QueuedMutation(it.second,0,0,null)},keys)
    }
    private fun remote(raw:CloudRecord)=raw.copy(syncVersion=2,updatedAt=serverTime,payload=JsonObject(raw.payload+buildJsonObject{put("sync_version",2);put("updated_at",serverTime)}))
    private fun project(s:InvestmentTradePublicationSnapshot,trades:List<CloudRecord>)=projectInvestmentTradePublicationResult(s,trades,setOf(assetId),device,serverTime)
    private fun changed(raw:CloudRecord,key:String,value:JsonElement)=raw.copy(payload=JsonObject(raw.payload+(key to value)))
    @Test fun aValidBuyProducesTheDeterministicFundingLedgerAndPostingProof() {
        val(s,p)=buy();val result=project(source(s,p.mutations),listOf(remote(p.trade)))
        val ledger=result.singleOrNull{it.entity==CloudEntity.LEDGER_TRANSACTION.table};assertNotNull(ledger)
        assertEquals(investmentLedgerIdentity(id,"funding"),ledger!!.id);assertEquals(70L,ledger.payload.financeRawLong("amount_minor"))
        val posting=result.single{it.entity==CloudEntity.INVESTMENT_POSTING.table};assertEquals(-70L,posting.payload.financeRawLong("accounting_amount_minor"))
        assertEquals("funding",posting.payload.financeRawString("role_raw_value"))
    }
    @Test fun forgedCostProfitPositionOrFinancialReferencesCannotPassTheRemoteProjectionProof() {
        val(s,p)=buy();val src=source(s,p.mutations);val raw=remote(p.trade)
        for((key,value) in listOf("released_cost_basis_minor" to JsonPrimitive(1),"realized_profit_loss_minor" to JsonPrimitive(1),
            "position_quantity_after_decimal_string" to JsonPrimitive("9"),"position_cost_basis_after_minor" to JsonPrimitive(71),
            "funding_ledger_transaction_id" to JsonPrimitive(walletId),"funding_wallet_amount_minor" to JsonPrimitive(71)))
            assertTrue(key,runCatching{project(src,listOf(changed(raw,key,value)))}.isFailure)
    }
    @Test fun derivedWalletCurrenciesMustMatchTheRealSelectedWalletInsteadOfTheirCachedValues() {
        val(s,p)=buy();val raw=changed(remote(p.trade),"funding_wallet_currency_code",JsonPrimitive("JPY"))
        assertTrue(runCatching{project(source(s,p.mutations),listOf(raw))}.isFailure)
    }
    @Test fun exactFxKeepsTheFundingAndAccountingMinorUnitsPairedWithTheirCurrencies() {
        val(s,p)=buy(code="JPY",walletCode="JPY");val result=project(source(s,p.mutations),listOf(remote(p.trade)))
        val ledger=result.singleOrNull{it.entity==CloudEntity.LEDGER_TRANSACTION.table};assertNotNull(ledger)
        assertEquals(70L,ledger!!.payload.financeRawLong("amount_minor"));assertEquals("JPY",ledger.payload.financeRawString("source_currency_code"))
        assertEquals(11550L,ledger.payload.financeRawLong("reporting_amount_minor"));assertEquals("VND",ledger.payload.financeRawString("reporting_currency_code"))
    }
    @Test fun promotionalInventoryProducesNoInventedFundingRows() {
        val(s,p)=buy(0);val result=project(source(s,p.mutations),listOf(remote(p.trade)))
        assertEquals(1,result.size);assertEquals(JsonNull,result.single().payload["funding_ledger_transaction_id"])
        assertEquals(0L,result.single().payload.financeRawLong("position_cost_basis_after_minor"))
    }
    @Test fun legacyNullUnitsRemainNullWhileTheirOwnFifoBucketIsVerified() {
        val(s,p)=buy();val raw=changed(remote(p.trade),"unit_label",JsonNull);val result=project(source(s,p.mutations),listOf(raw))
        assertEquals(JsonNull,result.single{it.entity==CloudEntity.INVESTMENT_TRADE.table}.payload["unit_label"])
        assertEquals(3,result.size)
    }
    @Test fun duplicateForeignAndUnrelatedAssetTradesAreRejected() {
        val(s,p)=buy();val src=source(s,p.mutations);val raw=remote(p.trade)
        val foreign=raw.copy(ownerUserId=walletId,payload=JsonObject(raw.payload+("user_id" to JsonPrimitive(walletId))))
        for(rows in listOf(listOf(raw,raw),listOf(foreign),listOf(changed(raw,"asset_id",JsonPrimitive(walletId)))))
            assertTrue(runCatching{project(src,rows)}.isFailure)
    }
    @Test fun dirtyMetadataCannotAuthorizeACloudFinancialResultBeforeItsDependencyIsPublished() {
        val(s,p)=buy();val src=source(s,p.mutations);val asset=s.rows.single{it.id==assetId}
        val q=QueuedMutation(PendingMutation(CloudEntity.INVESTMENT_ASSET,assetId,owner.value,MutationKind.UPSERT,asset.payload,now,0,device),0,0,null)
        assertTrue(runCatching{project(src.copy(pending=src.pending+q,dirtyKeys=src.dirtyKeys+(asset.entity to asset.id)),listOf(remote(p.trade)))}.isFailure)
    }
    @Test fun anUnrelatedLedgerOrCashPostingCannotBeAdoptedThroughADeterministicIdentityCollision() {
        val(s,p)=buy();val src=source(s,p.mutations)
        for(entity in listOf(CloudEntity.LEDGER_TRANSACTION,CloudEntity.INVESTMENT_POSTING)) {
            val old=src.rows.single{it.entity==entity.table}
            val changed=if(entity==CloudEntity.LEDGER_TRANSACTION)changed(old,"settlement_role_raw_value",JsonPrimitive("investmentReconciliation"))
                else changed(old,"role_raw_value",JsonPrimitive("cashTransfer"))
            val current=src.copy(rows=src.rows.map{if(it.entity==old.entity && it.id==old.id)changed else it},
                pending=src.pending.map{if(it.mutation.entity==entity && it.mutation.recordId==old.id)it.copy(mutation=it.mutation.copy(payload=changed.payload)) else it})
            current.requireCoherent();assertTrue(entity.table,runCatching{project(current,listOf(remote(p.trade)))}.isFailure)
        }
    }
    @Test fun missingCanonicalRootOrCurrentAssetIsAnUnreadableProjectionContext() {
        val(s,p)=buy();val src=source(s,p.mutations)
        for(missing in listOf(assetId,investmentSystemWalletId(owner),walletId,channel))
            assertTrue(missing,runCatching{project(src.copy(rows=src.rows.filterNot{it.id==missing}),listOf(remote(p.trade)))}.isFailure)
    }
    private fun sale(gross:Long,buyGross:Long=70):Pair<InvestmentTradePublicationSnapshot,List<CloudRecord>> {
        val(s,p)=buy(buyGross);val after=s.copy(rows=s.rows+p.mutations.map{it.first})
        val request=InvestmentSaleRequest(InvestmentSaleDraft(saleId,assetId,"2.5","box",gross,gross,"VND",null,null,null,
            if(gross>0)walletId else null,null,null,now,now),InvestmentAssetRecord.fromCloudRecord(s.rows.single{it.id==assetId}),
            if(gross>0)LedgerWalletRecord.fromCloudRecord(s.rows.single{it.id==walletId}) else null,null,"Reserve")
        val sold=planInvestmentSale(after,request,device,now)
        val writes=(p.mutations+sold.mutations).associateBy{it.first.entity to it.first.id}.values.toList()
        val src=source(s,writes,saleId)
        return src to src.rows.filter{it.entity==CloudEntity.INVESTMENT_TRADE.table}.map(::remote)
    }
    @Test fun totalLossProducesOnlyTheRootLossLegAlongsideTheOriginalFunding() {
        val(src,trades)=sale(0);val projected=project(src,trades)
        val loss=projected.singleOrNull{it.entity==CloudEntity.LEDGER_TRANSACTION.table && it.id==investmentLedgerIdentity(saleId,"profit-loss")};assertNotNull(loss)
        assertEquals("expense",loss!!.payload.financeRawString("primary_kind_raw_value"));assertEquals(70L,loss.payload.financeRawLong("amount_minor"))
        assertEquals(investmentSystemWalletId(owner),loss.payload.financeRawString("source_wallet_id"))
        assertFalse(projected.any{it.id==investmentLedgerIdentity(saleId,"capital-return") && it.deletedAt==null})
    }
    @Test fun aPartialRemoteHistoryCannotBeUsedAsACompleteFifoResult() {
        val(src,trades)=sale(50)
        assertTrue(runCatching{project(src,trades.filter{it.id==id})}.isFailure)
    }
    @Test fun crossAssetResultsRebuildBothHistoriesWithTheirOwnNamesAndCosts() {
        val(s,p)=buy();val assetB="88888888-8888-8888-8888-888888888888"
        val secondAsset=InvestmentAssetRecord.fromCloudRecord(s.rows.single{it.id==assetId}).copy(id=assetB,name="Second asset")
        val src=source(s.copy(rows=s.rows+secondAsset.toCloudRecord()),p.mutations)
        val moved=changed(remote(p.trade),"asset_id",JsonPrimitive(assetB))
        val other=remote(p.trade).copy(id=saleId,payload=JsonObject(remote(p.trade).payload+buildJsonObject{
            put("id",saleId);put("quantity_decimal_string","1");put("gross_amount_minor",40);put("accounting_gross_amount_minor",40)
            put("funding_wallet_amount_minor",40);put("position_quantity_after_decimal_string","1");put("position_cost_basis_after_minor",40)
            put("funding_ledger_transaction_id",investmentLedgerIdentity(saleId,"funding"))
        }))
        val output=projectInvestmentTradePublicationResult(src,listOf(moved,other),setOf(assetId,assetB),device,serverTime)
        val ledger=output.singleOrNull{it.id==investmentLedgerIdentity(id,"funding")};assertNotNull(ledger)
        assertEquals("Second asset",ledger!!.payload.financeRawString("title"))
        assertEquals("Cards",output.single{it.id==investmentLedgerIdentity(saleId,"funding")}.payload.financeRawString("title"))
        assertEquals(2,output.count{it.entity==CloudEntity.INVESTMENT_TRADE.table})
    }
    @Test fun sellingPromotionalInventoryKeepsZeroCapitalAndTheEntireProfitSeparate() {
        val(src,trades)=sale(50,0);val projected=project(src,trades)
        val capital=projected.singleOrNull{it.id==investmentLedgerIdentity(saleId,"capital-return")};assertNotNull(capital)
        assertEquals(0L,capital!!.payload.financeRawLong("amount_minor"))
        val profit=projected.single{it.id==investmentLedgerIdentity(saleId,"profit-loss")};assertEquals(50L,profit.payload.financeRawLong("amount_minor"))
    }
    @Test fun provenActiveWalletCanFundThePendingTradeWhileItsFinalArchiveStaysQueued() {
        val(metadata,plan)=buy();val initial=source(metadata,plan.mutations)
        val before=initial.rows.single{it.entity==CloudEntity.LEDGER_WALLET.table && it.id==walletId}
            .let{it.copy(syncVersion=1,payload=JsonObject(it.payload+("sync_version" to JsonPrimitive(1))))}
        val archive=LedgerWalletRecord.fromCloudRecord(before).toArchiveMutation(device,"2026-10-26T00:10:00Z")
        val pending=initial.pending+QueuedMutation(archive.pending,0,0,null)
        val waiting=initial.copy(rows=initial.rows.map{if(it.entity==before.entity && it.id==walletId)archive.record else it},
            pending=pending,dirtyKeys=pending.map{it.mutation.entity.table to it.mutation.recordId}.toSet())
        assertEquals(InvestmentTradeResultError.DEPENDENCY_PENDING,(runCatching{project(waiting,listOf(remote(plan.trade)))}.exceptionOrNull() as InvestmentTradeResultException).reason)
        val prepared=prepareWalletInvestmentPrerequisite(waiting,walletId,before)
        assertFalse(prepared.needsWrite)
        val result=project(prepared.preparedSource,listOf(remote(plan.trade)))
        assertEquals(-70L,result.single{it.entity==CloudEntity.INVESTMENT_POSTING.table}.payload.financeRawLong("accounting_amount_minor"))
        assertEquals(70L,result.single{it.entity==CloudEntity.LEDGER_TRANSACTION.table}.payload.financeRawLong("amount_minor"))
        assertEquals(true,prepared.preparedRecord.payload.financeRawArchived())
    }

}
