package vn.com.quyln.mistia.feature.overview

import org.junit.Assert.*
import org.junit.Test
import java.time.Instant
import java.util.UUID
import kotlinx.serialization.json.*
import vn.com.quyln.mistia.core.model.*

class OverviewRecentTransactionsTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other=UserId("99999999-9999-9999-9999-999999999999")
    private fun id(number:Int)=UUID(0,number.toLong()).toString()
    private fun row(number:Int,occurred:String="2026-10-16T00:00:00Z",created:String=occurred):CloudRecord {
        val payload=buildJsonObject {
            put("id",id(number));put("user_id",owner.value);put("primary_kind_raw_value","expense");put("entry_status_raw_value","posted")
            put("title","Row $number");put("amount_minor",9007199254740993L);put("source_currency_code","JPY")
            put("occurred_at",occurred);put("created_at",created);put("updated_at",created);put("is_archived",false)
        }
        return CloudRecord(CloudEntity.LEDGER_TRANSACTION.table,id(number),owner.value,payload,created,null,0)
    }
    private fun CloudRecord.with(vararg fields:Pair<String,JsonElement>)=copy(payload=JsonObject(payload+fields.toMap()))
    private fun project(records:List<CloudRecord>,wallets:List<CloudRecord> = emptyList(),primary:String="JPY")=
        overviewRecentTransactions(owner,records,wallets,primary)
    @Test fun `hidden financial rows and mismatched scopes never consume five recent slots`() {
        val hidden=listOf(
            row(1).copy(ownerUserId=other.value),row(2).with("user_id" to JsonPrimitive(other.value)),
            row(3).with("id" to JsonPrimitive(id(99))),row(4).copy(entity=CloudEntity.LEDGER_WALLET.table),
            row(5).with("entry_status_raw_value" to JsonPrimitive("draft")),row(6).with("is_archived" to JsonPrimitive(true)),
            row(7).copy(deletedAt="2026-10-16T00:00:00Z"),row(8).with("deleted_at" to JsonPrimitive("2026-10-16T00:00:00Z")),
            row(9).with("settlement_role_raw_value" to JsonPrimitive("investmentFunding")),row(10).with("primary_kind_raw_value" to JsonPrimitive("unknown")),
        )
        val visible=(20..25).map {row(it,"2026-10-15T00:00:00Z")}
        assertEquals(visible.take(5).map {it.id},project(hidden+visible).map {it.transaction.id})
    }
    @Test fun `five rows sort by actual occurred instant then created instant rather than update time or wire text`() {
        val records=listOf(
            row(1,"2026-10-16T00:00:00Z","2026-10-16T00:00:01Z"),
            row(2,"2026-10-16T09:00:00+09:00","2026-10-16T00:00:02Z"),
            row(3,"2026-10-16T00:00:01Z"),row(4,"2026-10-15T23:59:59Z"),
            row(5,"2026-10-14T00:00:00Z"),row(6,"2026-10-13T00:00:00Z"),row(7,"2026-10-12T00:00:00Z"),
        )
        val before=records.toList()
        assertEquals(listOf(3,2,1,4,5).map(::id),project(records.reversed()).map {it.transaction.id})
        assertEquals(before,records)
    }
    @Test fun `original source money stays exact and reporting destination do not change its currency`() {
        val original=row(1).with("source_currency_code" to JsonPrimitive("VND"),"reporting_currency_code" to JsonPrimitive("JPY"),
            "reporting_amount_minor" to JsonPrimitive(1),"destination_currency_code" to JsonPrimitive("USD"),"destination_amount_minor" to JsonPrimitive(2))
        assertEquals(Money(9007199254740993L,"VND"),project(listOf(original),primary="JPY").single().money)
        val usd=row(2).with("source_currency_code" to JsonPrimitive("USD"),"amount_minor" to JsonPrimitive(1375))
        assertEquals(Money(1375,"USD"),project(listOf(usd),primary="VND").single().money)
    }
    @Test fun `legacy source currency uses only matching owned live source wallet then current primary`() {
        val source=id(80);val dest=id(81)
        fun wallet(walletId:String,code:String)=CloudRecord(CloudEntity.LEDGER_WALLET.table,walletId,owner.value,buildJsonObject {
            put("id",walletId);put("user_id",owner.value);put("name","Cash");put("kind_raw_value","cash");put("currency_code",code)
            put("created_at","2026-10-16T00:00:00Z");put("updated_at","2026-10-16T00:00:00Z");put("is_archived",false)
        },null,null,0)
        val raw=row(1).with("source_currency_code" to JsonNull,"source_wallet_id" to JsonPrimitive(source),"destination_wallet_id" to JsonPrimitive(dest))
        val sourceWallet=wallet(source,"VND");val destination=wallet(dest,"USD")
        assertEquals("VND",project(listOf(raw),listOf(sourceWallet,destination)).single().money.currencyCode)
        for(ineligible in listOf(sourceWallet.copy(ownerUserId=other.value),sourceWallet.with("user_id" to JsonPrimitive(other.value)),
            sourceWallet.with("id" to JsonPrimitive(dest)),sourceWallet.copy(deletedAt="2026-10-16T00:00:00Z"),sourceWallet.with("deleted_at" to JsonPrimitive("2026-10-16T00:00:00Z")))) {
            assertEquals("VND",project(listOf(raw),listOf(ineligible,destination)," vnd ").single().money.currencyCode)
            assertEquals("JPY",project(listOf(raw),listOf(ineligible,destination),"JPY").single().money.currencyCode)
        }
        assertEquals("JPY",project(listOf(raw),primary="USD").single().money.currencyCode)
    }
    @Test fun `malformed monetary or calendar data is hidden instead of rendered as fallback zero`() {
        val invalidAmounts=listOf(JsonNull,JsonPrimitive("invalid"),JsonPrimitive("9223372036854775808"),JsonPrimitive("1.25"),JsonPrimitive(true))
        for(value in invalidAmounts) assertTrue(project(listOf(row(1).with("amount_minor" to value))).isEmpty())
        assertTrue(project(listOf(row(1).copy(payload=JsonObject(row(1).payload-"amount_minor")))).isEmpty())
        for(key in listOf("occurred_at","created_at")) assertTrue(project(listOf(row(1).with(key to JsonPrimitive("invalid")))).isEmpty())
        assertEquals(Long.MAX_VALUE,project(listOf(row(1).with("amount_minor" to JsonPrimitive(Long.MAX_VALUE)))).single().money.minor)
    }
}
