package vn.com.quyln.mistia.core.model

import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class InvestmentWalletPublicationTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other=UserId("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
    private val id=investmentSystemWalletId(owner)
    private val device="33333333-3333-3333-3333-333333333333"
    private val now="2026-10-26T00:00:00Z"
    private fun root(version:Long=9007199254740993L)=CloudRecord(CloudEntity.LEDGER_WALLET.table,id,owner.value,buildJsonObject {
        put("id",id);put("user_id",owner.value);put("name","Investment wallet");put("kind_raw_value","investment")
        put("currency_code","VND");put("opening_balance_minor",0L);put("system_purpose_raw_value","investmentProfit")
        put("investment_linked_wallet_id",JsonNull);put("icon_symbol_name",WalletKind.INVESTMENT.defaultIcon);put("icon_color_hex",WalletKind.INVESTMENT.defaultColorHex)
        put("institution_display_name",JsonNull);put("institution_preset_key",JsonNull);put("sort_order",Int.MAX_VALUE-100)
        put("is_archived",false);put("archived_at",JsonNull);put("deleted_at",JsonNull);put("created_at",now);put("updated_at",now)
        put("sync_version",version);put("last_modified_by_device_id",device);put("future_null",JsonNull);put("future_object",buildJsonObject{put("large",Long.MAX_VALUE)})
    },now,null,version)
    @Test fun exactCanonicalActiveWalletIsAcceptedWithoutLosingLongNullOrOpaqueValues() {
        val raw=root();val before=raw.payload
        val wallet=canonicalInvestmentWalletForPublication(owner,raw,forWrite=true)
        assertEquals(id,wallet.id);assertEquals(owner.value,wallet.ownerUserId)
        assertEquals(WalletKind.INVESTMENT,wallet.kind);assertEquals("investmentProfit",wallet.systemPurposeRawValue)
        assertEquals(0L,wallet.openingBalanceMinor);assertEquals(9007199254740993L,wallet.syncVersion)
        assertNull(wallet.investmentLinkedWalletId);assertEquals(before,raw.payload)
    }
    @Test fun aCanonicalLinkedIdentityIsPreservedWithoutChangingItsAccountingCurrency() {
        val target="44444444-4444-4444-4444-444444444444"
        val raw=root().let{it.copy(payload=JsonObject(it.payload+("investment_linked_wallet_id" to JsonPrimitive(target))))}
        val wallet=canonicalInvestmentWalletForPublication(owner,raw,true)
        assertEquals(target,wallet.investmentLinkedWalletId);assertEquals("VND",wallet.currencyCode)
    }
    @Test fun otherOwnersOrdinaryKindsAndArbitraryInvestmentIdsCannotEnterThisDomain() {
        val raw=root()
        val bad=listOf(raw.copy(ownerUserId=other.value),raw.copy(entity=CloudEntity.INVESTMENT_POSTING.table),
            raw.copy(id=other.value,payload=JsonObject(raw.payload+("id" to JsonPrimitive(other.value)))),
            raw.copy(payload=JsonObject(raw.payload+("kind_raw_value" to JsonPrimitive("cash")))),
            raw.copy(payload=JsonObject(raw.payload+("system_purpose_raw_value" to JsonNull))),
            raw.copy(payload=JsonObject(raw.payload+("user_id" to JsonPrimitive(other.value)))))
        for(row in bad)assertTrue(runCatching{canonicalInvestmentWalletForPublication(owner,row,true)}.exceptionOrNull() is IllegalArgumentException)
    }
    @Test fun changedOrUnreadableOpeningBalanceCannotBecomeAMetadataWrite() {
        for(value in listOf<JsonElement>(JsonPrimitive(1L),JsonPrimitive(-1L),JsonPrimitive("0"),JsonNull)) {
            val raw=root().let{it.copy(payload=JsonObject(it.payload+("opening_balance_minor" to value)))}
            assertTrue(runCatching{canonicalInvestmentWalletForPublication(owner,raw,true)}.exceptionOrNull() is IllegalArgumentException)
        }
    }
    @Test fun readableRemoteTombstonesAndArchivesAreNotAuthorizedAsLocalWrites() {
        val raw=root()
        val deleted=raw.copy(deletedAt=now,payload=JsonObject(raw.payload+("deleted_at" to JsonPrimitive(now))))
        val archived=raw.copy(payload=JsonObject(raw.payload+mapOf("is_archived" to JsonPrimitive(true),"archived_at" to JsonPrimitive(now))))
        for(row in listOf(deleted,archived)) {
            assertEquals(id,canonicalInvestmentWalletForPublication(owner,row).id)
            assertTrue(runCatching{canonicalInvestmentWalletForPublication(owner,row,true)}.exceptionOrNull() is IllegalArgumentException)
        }
    }
    @Test fun theRootCannotLinkToItselfOrAnUnparseableIdentity() {
        for(value in listOf(id,"../wallet","https://example.invalid/wallet")) {
            val raw=root().let{it.copy(payload=JsonObject(it.payload+("investment_linked_wallet_id" to JsonPrimitive(value))))}
            assertTrue(runCatching{canonicalInvestmentWalletForPublication(owner,raw,true)}.exceptionOrNull() is IllegalArgumentException)
        }
    }
    @Test fun mismatchedOrStringVersionsAndTimestampAuthorityAreHeld() {
        val raw=root()
        val bad=listOf(raw.copy(payload=JsonObject(raw.payload+("sync_version" to JsonPrimitive("9007199254740993")))),
            raw.copy(syncVersion=4),raw.copy(updatedAt="2026-10-26T01:00:00Z"))
        for(row in bad)assertTrue(runCatching{canonicalInvestmentWalletForPublication(owner,row,true)}.exceptionOrNull() is IllegalArgumentException)
    }
}
