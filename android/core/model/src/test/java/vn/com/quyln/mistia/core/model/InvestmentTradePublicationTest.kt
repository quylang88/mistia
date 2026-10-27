package vn.com.quyln.mistia.core.model

import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class InvestmentTradePublicationTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val id="22222222-2222-2222-2222-222222222222"
    private val device="33333333-3333-3333-3333-333333333333"
    private val asset="44444444-4444-4444-4444-444444444444"
    private val channel="55555555-5555-5555-5555-555555555555"
    private val wallet="66666666-6666-6666-6666-666666666666"
    private val now="2026-10-26T00:00:00Z"
    private val version=9007199254740993L
    private fun row()=CloudRecord(CloudEntity.INVESTMENT_TRADE.table,id,owner.value,buildJsonObject {
        put("id",id);put("user_id",owner.value);put("asset_id",asset);put("channel_id",channel);put("kind_raw_value","buy")
        put("quantity_decimal_string","1.250");put("unit_label","  Bó hoa  ");put("gross_amount_minor",Long.MAX_VALUE);put("currency_code","VND")
        put("accounting_gross_amount_minor",Long.MAX_VALUE);put("accounting_currency_code","VND");put("funding_wallet_id",wallet);put("capital_return_wallet_id",JsonNull)
        for(key in listOf("exchange_rate_decimal_string","exchange_rate_provider","exchange_rate_date","funding_to_accounting_rate_decimal_string","accounting_to_capital_return_rate_decimal_string","note"))put(key,JsonNull)
        put("created_at",now);put("updated_at",now);put("occurred_at",now);put("deleted_at",JsonNull);put("sync_version",version);put("last_modified_by_device_id",device)
        put("future_null",JsonNull);put("future_large",Long.MAX_VALUE)
    },now,null,version)
    private fun changed(fields:JsonObject)=row().let{it.copy(payload=JsonObject(it.payload+fields))}
    private fun rejects(raw:CloudRecord)=assertTrue(raw.toString(),runCatching{requireInvestmentTradeForPublication(owner,raw)}.isFailure)
    @Test fun exactLongQuantityUnitNullAndOpaqueIntentArePreserved() {
        val raw=row();requireInvestmentTradeForPublication(owner,raw)
        assertEquals(raw.payload,investmentTradePayloadForCloud(raw.payload));assertEquals(version,raw.syncVersion)
    }
    @Test fun foreignOwnerEntityOrPayloadIdentityNeverEntersTheTradePort() {
        rejects(row().copy(ownerUserId="aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"));rejects(row().copy(entity=CloudEntity.LEDGER_TRANSACTION.table))
        for(fields in listOf(buildJsonObject{put("id",asset)},buildJsonObject{put("user_id",asset)},buildJsonObject{put("asset_id","bad")},buildJsonObject{put("channel_id",JsonNull)}))rejects(changed(fields))
    }
    @Test fun roundedOrIncoherentVersionAndDatesAreRejected() {
        for(fields in listOf(buildJsonObject{put("sync_version",JsonPrimitive(9007199254740992L))},buildJsonObject{put("sync_version",JsonPrimitive("9007199254740993"))},
            buildJsonObject{put("created_at","bad")},buildJsonObject{put("updated_at","2026-10-26T00:01:00Z")},buildJsonObject{put("occurred_at",true)},buildJsonObject{put("last_modified_by_device_id","bad")}))rejects(changed(fields))
        rejects(row().copy(syncVersion=-1))
    }
    @Test fun invalidQuantityUnitAndGrossMoneyCannotBecomeAValidProposal() {
        for(fields in listOf(buildJsonObject{put("quantity_decimal_string","0")},buildJsonObject{put("quantity_decimal_string",1)},buildJsonObject{put("unit_label","  ")},
            buildJsonObject{put("unit_label",JsonNull)},buildJsonObject{put("gross_amount_minor",-1)},buildJsonObject{put("gross_amount_minor","100")},
            buildJsonObject{put("accounting_gross_amount_minor",0)},buildJsonObject{put("accounting_gross_amount_minor",1)},buildJsonObject{put("kind_raw_value","futureKind")}))rejects(changed(fields))
    }
    @Test fun positiveBuyAndSaleHaveOnlyTheirOwnWalletRole() {
        rejects(changed(buildJsonObject{put("funding_wallet_id",JsonNull)}));rejects(changed(buildJsonObject{put("capital_return_wallet_id",wallet)}))
        val sale=changed(buildJsonObject{put("kind_raw_value","sell");put("funding_wallet_id",JsonNull);put("capital_return_wallet_id",wallet)})
        requireInvestmentTradeForPublication(owner,sale)
        rejects(sale.copy(payload=JsonObject(sale.payload+("funding_wallet_id" to JsonPrimitive(wallet)))))
    }
    @Test fun zeroPromotionalBuyAndLiquidationHaveNoWalletOrFxRate() {
        for(kind in listOf("buy","sell")) {
            val zero=changed(buildJsonObject{put("kind_raw_value",kind);put("gross_amount_minor",0);put("accounting_gross_amount_minor",0);put("funding_wallet_id",JsonNull);put("capital_return_wallet_id",JsonNull)})
            requireInvestmentTradeForPublication(owner,zero)
            rejects(zero.copy(payload=JsonObject(zero.payload+("funding_wallet_id" to JsonPrimitive(wallet)))))
            rejects(zero.copy(payload=JsonObject(zero.payload+("exchange_rate_decimal_string" to JsonPrimitive("2")))))
        }
    }
    @Test fun positiveFxRequiresAnExactStoredRateWithoutChangingAmountUnits() {
        val fx=changed(buildJsonObject{put("gross_amount_minor",101);put("currency_code","JPY");put("accounting_currency_code","VND");put("accounting_gross_amount_minor",16665);put("exchange_rate_decimal_string","165")})
        requireInvestmentTradeForPublication(owner,fx)
        rejects(fx.copy(payload=JsonObject(fx.payload+("exchange_rate_decimal_string" to JsonNull))))
        rejects(fx.copy(payload=JsonObject(fx.payload+("accounting_gross_amount_minor" to JsonPrimitive(16664)))))
        rejects(fx.copy(payload=JsonObject(fx.payload+("funding_to_accounting_rate_decimal_string" to JsonPrimitive("NaN")))))
    }
    @Test fun tombstonesAndLegacyMissingUnitsAreReadableButNotPublishableAsActiveWrites() {
        val old=changed(buildJsonObject{put("unit_label",JsonNull);put("deleted_at",now)}).copy(deletedAt=now)
        requireInvestmentTradeForPublication(owner,old,forWrite=false);rejects(old)
        requireInvestmentTradeForPublication(owner,changed(buildJsonObject{put("unit_label",JsonNull)}),forWrite=false)
    }
    @Test fun serverDerivedFifoMoneyAndFinancialReferencesNeverBecomeEditableWireAuthority() {
        val derived=buildJsonObject {
            put("funding_wallet_currency_code","VND");put("capital_return_wallet_currency_code",JsonNull)
            put("funding_wallet_amount_minor",Long.MAX_VALUE);put("capital_return_wallet_amount_minor",JsonNull)
            put("funding_ledger_transaction_id",wallet);put("capital_return_ledger_transaction_id",JsonNull);put("profit_loss_ledger_transaction_id",JsonNull)
            put("released_cost_basis_minor",0);put("realized_profit_loss_minor",0);put("position_quantity_after_decimal_string","1.25");put("position_cost_basis_after_minor",Long.MAX_VALUE)
        }
        assertEquals(row().payload,investmentTradePayloadForCloud(JsonObject(row().payload+derived)))
    }
    @Test fun anotherDomainsLocalEvidenceCannotBeLaunderedThroughATrade() {
        for(key in LOCAL_ASSET_PUBLICATION_KEYS+LOCAL_INVESTMENT_WALLET_PARENTS_KEY)rejects(changed(buildJsonObject{put(key,JsonNull)}))
    }
}
