package vn.com.quyln.mistia.core.model

import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class InvestmentTradePublicationOrderTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val buy="22222222-2222-2222-2222-222222222222"
    private val sale="33333333-3333-3333-3333-333333333333"
    private val asset="44444444-4444-4444-4444-444444444444"
    private val device="55555555-5555-5555-5555-555555555555"
    private val now="2026-10-27T00:00:00Z"
    private fun row(id:String,kind:String,quantity:String,unit:String?="box",assetId:String=asset)=CloudRecord(CloudEntity.INVESTMENT_TRADE.table,id,owner.value,buildJsonObject {
        put("id",id);put("user_id",owner.value);put("asset_id",assetId);put("channel_id",asset);put("kind_raw_value",kind);put("quantity_decimal_string",quantity)
        put("unit_label",unit?.let(::JsonPrimitive) ?: JsonNull);put("gross_amount_minor",0);put("currency_code","VND");put("accounting_gross_amount_minor",0);put("accounting_currency_code","VND")
        put("funding_wallet_id",JsonNull);put("capital_return_wallet_id",JsonNull);put("created_at",now);put("updated_at",now);put("occurred_at",if(kind=="buy")now else "2026-10-27T00:01:00Z")
        put("deleted_at",JsonNull);put("sync_version",2);put("last_modified_by_device_id",device)
    },now,null,2)
    private fun valid(history:List<CloudRecord>,proposal:CloudRecord)=canApplyInvestmentTradeToCloudHistory(owner,history,proposal)
    @Test fun reducingTheEarlierAcquisitionDefersUntilItsDependentSaleIsReduced() {
        assertFalse(valid(listOf(row(buy,"buy","10"),row(sale,"sell","10")),row(buy,"buy","5")))
    }
    @Test fun reducingTheSaleFirstAllowsBothOfflineIntentsToReachTheValidFinalHistory() {
        val first=listOf(row(buy,"buy","10"),row(sale,"sell","10"));val reducedSale=row(sale,"sell","5")
        assertTrue(valid(first,reducedSale));assertTrue(valid(listOf(first.first(),reducedSale),row(buy,"buy","5")))
    }
    @Test fun aNewSaleWaitsForItsNewAcquisitionInsteadOfBecomingAPermanentBackendFailure() {
        assertFalse(valid(emptyList(),row(sale,"sell","5")));assertTrue(valid(emptyList(),row(buy,"buy","10")))
        assertTrue(valid(listOf(row(buy,"buy","10")),row(sale,"sell","5")))
    }
    @Test fun intermediateFifoCannotBorrowStockAcrossAssetsUnitsOrTheLegacyNullBucket() {
        val stock=listOf(row(buy,"buy","10"))
        assertFalse(valid(stock,row(sale,"sell","5",assetId=device)));assertFalse(valid(stock,row(sale,"sell","5",unit="card")))
        assertFalse(valid(listOf(row(buy,"buy","10",unit=null)),row(sale,"sell","5")))
        assertTrue(valid(listOf(row(buy,"buy","10",unit=null)),row(sale,"sell","5",unit=null)))
    }
    @Test fun aSaleCanBeDeletedBeforeTheAcquisitionItStillConsumes() {
        val stock=listOf(row(buy,"buy","10"),row(sale,"sell","10"))
        fun deleted(raw:CloudRecord)=raw.copy(deletedAt=now,payload=JsonObject(raw.payload+("deleted_at" to JsonPrimitive(now))))
        assertFalse(valid(stock,deleted(stock.first())));assertTrue(valid(stock,deleted(stock.last())))
    }
    @Test fun foreignOrDuplicatedServerHistoryIsRejectedInsteadOfTreatedAsAnOrderingDependency() {
        val stock=row(buy,"buy","10")
        assertThrows(IllegalArgumentException::class.java){valid(listOf(stock,stock),row(sale,"sell","5"))}
        val foreign=stock.copy(ownerUserId=device,payload=JsonObject(stock.payload+("user_id" to JsonPrimitive(device))))
        assertThrows(IllegalArgumentException::class.java){valid(listOf(foreign),row(sale,"sell","5"))}
    }
    @Test fun fifoUsesPostgresMicrosecondPrecisionBeforeRelyingOnCreatedDateToOrderTies() {
        val higherBuy="99999999-9999-9999-9999-999999999999"
        val existing=row(higherBuy,"buy","10").let{it.copy(payload=JsonObject(it.payload+("created_at" to JsonPrimitive("2026-10-27T00:00:00.123456Z"))))}
        val proposed=row(sale,"sell","5").let{it.copy(payload=JsonObject(it.payload+buildJsonObject{put("occurred_at",now);put("created_at","2026-10-27T00:00:00.123456400Z")}))}
        assertFalse(valid(listOf(existing),proposed))
    }
}
