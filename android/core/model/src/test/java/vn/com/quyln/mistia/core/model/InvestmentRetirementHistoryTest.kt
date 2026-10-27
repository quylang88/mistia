package vn.com.quyln.mistia.core.model

import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class InvestmentRetirementHistoryTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val channel="22222222-2222-2222-2222-222222222222"
    private val asset="33333333-3333-3333-3333-333333333333"
    private val other="44444444-4444-4444-4444-444444444444"
    private val device="55555555-5555-5555-5555-555555555555"
    private val now="2026-10-27T00:00:00Z"
    private fun assetRow(id:String=asset)=InvestmentAssetRecord(id,owner.value,channel,"Cards","VND",null,"box",0,false,null,now,now,null,1,device).toCloudRecord()
    private fun trade(index:Int,kind:String="buy",target:String=asset,unit:String?="box",deleted:Boolean=false)=CloudRecord(CloudEntity.INVESTMENT_TRADE.table,
        "66666666-6666-6666-6666-66666666666$index",owner.value,buildJsonObject {
            put("id","66666666-6666-6666-6666-66666666666$index");put("user_id",owner.value);put("asset_id",target);put("channel_id",channel)
            put("kind_raw_value",kind);put("quantity_decimal_string","1");put("unit_label",unit?.let(::JsonPrimitive) ?: JsonNull)
            put("gross_amount_minor",0);put("accounting_gross_amount_minor",0);put("currency_code","VND");put("accounting_currency_code","VND")
            for(key in listOf("funding_wallet_id","capital_return_wallet_id","exchange_rate_decimal_string","exchange_rate_provider","exchange_rate_date","funding_to_accounting_rate_decimal_string","accounting_to_capital_return_rate_decimal_string","note"))put(key,JsonNull)
            put("created_at",now);put("updated_at",now);put("occurred_at",now);put("deleted_at",if(deleted)JsonPrimitive(now) else JsonNull)
            put("sync_version",2);put("last_modified_by_device_id",device);put("position_quantity_after_decimal_string","0")
        },now,if(deleted)now else null,2)
    private fun history(trades:List<CloudRecord> = emptyList(),assets:List<CloudRecord> = listOf(assetRow()),entity:CloudEntity=CloudEntity.INVESTMENT_ASSET)=
        InvestmentRetirementHistory(owner,entity,if(entity==CloudEntity.INVESTMENT_ASSET)asset else channel,assets,trades)
    @Test fun emptyAndFullyClosedOwnedHistoriesPermitRetirement() {
        assertTrue(investmentRetirementHistoryIsClosed(history()))
        assertTrue(investmentRetirementHistoryIsClosed(history(listOf(trade(1),trade(2,"sell")))))
        assertTrue(investmentRetirementHistoryIsClosed(history(listOf(trade(1,deleted=true)))))
    }
    @Test fun forgedDerivedZeroDoesNotHideAnActuallyOpenPosition() {
        assertFalse(investmentRetirementHistoryIsClosed(history(listOf(trade(1)))))
    }
    @Test fun everyAssetAndEveryUnitMustBeClosed() {
        assertFalse(investmentRetirementHistoryIsClosed(history(listOf(trade(1),trade(2,"sell"),trade(3,target=other)),listOf(assetRow(),assetRow(other)),CloudEntity.INVESTMENT_CHANNEL)))
        assertFalse(investmentRetirementHistoryIsClosed(history(listOf(trade(1,unit=null),trade(2,"sell",unit="box")))))
    }
    @Test fun foreignDuplicatePrivateAndUnrelatedHistoryIsRejected() {
        val t=trade(1);val foreign=t.copy(ownerUserId=device,payload=JsonObject(t.payload+("user_id" to JsonPrimitive(device))))
        val injected=t.copy(payload=JsonObject(t.payload+(LOCAL_TRADE_PUBLICATION_PARENTS_KEY to JsonArray(emptyList()))))
        for(rows in listOf(listOf(foreign),listOf(t,t),listOf(injected),listOf(trade(1,target=other))))
            assertTrue(runCatching{investmentRetirementHistoryIsClosed(history(rows))}.isFailure)
        assertTrue(runCatching{investmentRetirementHistoryIsClosed(history(entity=CloudEntity.LEDGER_WALLET))}.isFailure)
    }
    @Test fun foreignOrMissingChannelAssetsCannotCertifyACompleteChannel() {
        val wrong=assetRow().let{it.copy(payload=JsonObject(it.payload+("channel_id" to JsonPrimitive(other))))}
        assertTrue(runCatching{investmentRetirementHistoryIsClosed(history(assets=listOf(wrong),entity=CloudEntity.INVESTMENT_CHANNEL))}.isFailure)
        assertTrue(runCatching{investmentRetirementHistoryIsClosed(history(listOf(trade(1)),emptyList(),CloudEntity.INVESTMENT_CHANNEL))}.isFailure)
    }
    @Test fun individuallyValidCrossReadRelationsSignalAChangedSnapshot() {
        val t=trade(1)
        val moved=t.copy(payload=JsonObject(t.payload+("channel_id" to JsonPrimitive(other))))
        val deletedAsset=assetRow().let{it.copy(deletedAt=now,payload=JsonObject(it.payload+("deleted_at" to JsonPrimitive(now))))}
        for(candidate in listOf(history(listOf(t),emptyList(),CloudEntity.INVESTMENT_CHANNEL),history(listOf(moved)),history(listOf(t),listOf(deletedAsset))))
            assertTrue(runCatching{candidate.requireValid()}.exceptionOrNull() is InvestmentRetirementHistoryChanged)
        val foreign=t.copy(ownerUserId=device,payload=JsonObject(t.payload+("user_id" to JsonPrimitive(device))))
        assertTrue(runCatching{history(listOf(foreign)).requireValid()}.exceptionOrNull() is IllegalArgumentException)
    }
    @Test fun aMovedPendingTradeIsStillADependencyOfItsOriginalCloudAsset() {
        val cloud=history(listOf(trade(1)));val moved=trade(1,target=other)
        val q=QueuedMutation(PendingMutation(CloudEntity.INVESTMENT_TRADE,moved.id,owner.value,MutationKind.UPSERT,moved.payload,now,2,device),0,0,null)
        val source=InvestmentTradePublicationSnapshot(owner,moved.id,listOf(assetRow(),assetRow(other),moved),listOf(q),setOf(moved.entity to moved.id))
        assertTrue(investmentRetirementHasPendingDependencies(source,cloud))
    }
}
