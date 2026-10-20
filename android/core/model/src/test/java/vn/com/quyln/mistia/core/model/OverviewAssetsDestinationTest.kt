package vn.com.quyln.mistia.core.model

import java.math.BigInteger
import java.util.UUID
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class OverviewAssetsDestinationTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val time="2026-10-20T00:00:00Z"
    private val rate=ExchangeRateSnapshot("JPY","VND","165","test",0,null)
    private fun raw(entity:CloudEntity,fields:JsonObject):CloudRecord {
        val id=UUID.randomUUID().toString()
        return CloudRecord(entity.table,id,owner.value,JsonObject(buildJsonObject {put("id",id);put("user_id",owner.value);put("created_at",time);put("occurred_at",time);put("updated_at",time)}+fields),time,null,0)
    }
    private fun wallet(code:String="JPY",amount:Long=0)=LedgerWalletRecord.fromCloudRecord(raw(CloudEntity.LEDGER_WALLET,buildJsonObject {
        put("name","Paired cash");put("kind_raw_value","cash");put("currency_code",code);put("opening_balance_minor",amount)
    }))
    private fun transfer(source:LedgerWalletRecord,destination:LedgerWalletRecord,amount:Long=100)=LedgerTransactionRecord.fromCloudRecord(raw(CloudEntity.LEDGER_TRANSACTION,buildJsonObject {
        put("primary_kind_raw_value","transfer");put("transfer_subtype_raw_value","internalTransfer");put("entry_status_raw_value","posted");put("amount_minor",amount)
        put("source_wallet_id",source.id);put("destination_wallet_id",destination.id);put("source_currency_code",source.currencyCode);put("destination_currency_code",destination.currencyCode)
    }))
    private fun total(wallets:List<LedgerWalletRecord>,row:LedgerTransactionRecord)=overviewTotalAssets(owner,wallets,listOf(row),"JPY",listOf(rate))
    @Test fun `nonzero cross currency destination without paired minor units is unavailable`() {
        val source=wallet(amount=1000);val destination=wallet("VND")
        assertNull(total(listOf(source,destination),transfer(source,destination)))
        assertNull(total(listOf(source,destination),transfer(source,destination).copy(sourceCurrencyCode="VND")))
    }
    @Test fun `same currency legacy pairing and explicit cross destination remain exact`() {
        val source=wallet(amount=1000);val same=wallet();val cross=wallet("VND")
        assertEquals(BigInteger.valueOf(1000),total(listOf(source,same),transfer(source,same)))
        assertEquals(BigInteger.valueOf(1000),total(listOf(source,cross),transfer(source,cross).copy(destinationAmountMinor=16500)))
    }
    @Test fun `missing foreign destination and zero transfer cannot poison owned balances`() {
        val source=wallet(amount=1000);val outside=wallet("VND")
        assertEquals(BigInteger.valueOf(900),total(listOf(source),transfer(source,outside)))
        val zero=wallet();assertEquals(BigInteger.ZERO,total(listOf(zero,outside),transfer(zero,outside,0)))
    }
}
