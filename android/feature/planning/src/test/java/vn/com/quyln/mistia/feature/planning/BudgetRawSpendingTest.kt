package vn.com.quyln.mistia.feature.planning

import java.math.BigInteger
import java.time.*
import java.util.UUID
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import vn.com.quyln.mistia.core.model.*

class BudgetRawSpendingTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other="99999999-9999-9999-9999-999999999999"
    private val parent="22222222-2222-2222-2222-222222222222"
    private val child="33333333-3333-3333-3333-333333333333"
    private val walletId="44444444-4444-4444-4444-444444444444"
    private val budgetId="55555555-5555-5555-5555-555555555555"
    private val now="2026-10-21T00:00:00Z"
    private val zone=ZoneId.of("Asia/Tokyo")
    private val month=YearMonth.of(2026,10)
    private fun CloudRecord.with(key:String,value:JsonElement)=copy(payload=JsonObject(payload+(key to value)))
    private fun category(id:String=child,name:String="Food",parentId:String?=parent)=CloudRecord(CloudEntity.TRANSACTION_CATEGORY.table,id,owner.value,buildJsonObject {
        put("id",id);put("user_id",owner.value);put("name",name);put("name_english",name);put("kind_raw_value","expense")
        put("parent_category_id",parentId?.let(::JsonPrimitive) ?: JsonNull);put("hierarchy_role_raw_value",if(parentId==null) "parent" else "child")
        put("system_key",JsonNull);put("is_system",false);put("is_archived",false);put("created_at",now);put("updated_at",now);put("sync_version",0)
    },now,null,0)
    private fun plan(code:String="JPY")=CloudRecord(CloudEntity.BUDGET_PLAN.table,budgetId,owner.value,buildJsonObject {
        put("id",budgetId);put("user_id",owner.value);put("category_id",child);put("category_id_snapshot",child);put("category_name_snapshot","Food");put("category_name_english_snapshot","Food")
        put("category_parent_id_snapshot",parent);put("category_parent_name_snapshot","Living");put("category_is_parent_snapshot",false)
        put("limit_minor",1000);put("currency_code",code);put("month_anchor","2026-09-30T15:00:00Z");put("rollover_enabled",false);put("is_archived",false)
        put("created_at",now);put("updated_at",now);put("sync_version",0)
    },now,null,0)
    private fun wallet(code:String="JPY")=CloudRecord(CloudEntity.LEDGER_WALLET.table,walletId,owner.value,buildJsonObject {
        put("id",walletId);put("user_id",owner.value);put("name","Budget cash");put("kind_raw_value","cash");put("currency_code",code);put("opening_balance_minor",1000)
        put("is_archived",false);put("created_at",now);put("updated_at",now)
    },now,null,0)
    private fun row(amount:Long=7,kind:String="expense"):CloudRecord {val id=UUID.randomUUID().toString();return CloudRecord(CloudEntity.LEDGER_TRANSACTION.table,id,owner.value,buildJsonObject {
        put("id",id);put("user_id",owner.value);put("title","Budget expense");put("primary_kind_raw_value",kind);put("entry_status_raw_value","posted")
        put("amount_minor",amount);put("source_currency_code","JPY");put("source_wallet_id",walletId);put("category_id",child);put("is_archived",false)
        put("occurred_at",now);put("created_at",now);put("updated_at",now)
    },now,null,0)}
    private fun project(vararg records:CloudRecord,wallets:List<CloudRecord> = listOf(wallet()),categories:List<CloudRecord> = listOf(category(parent,"Living",null),category()),plans:List<CloudRecord> = listOf(plan()),code:String="JPY",rates:List<ExchangeRateSnapshot> = emptyList(),titles:Set<String> = setOf("Balance adjustment","Điều chỉnh số dư")):BudgetProjection =
        projectRawBudgetReadSnapshot(owner,BudgetReadSnapshot(owner,plans+records.toList()+wallets+categories),month,Instant.parse(now),zone,rates,CategoryNameLanguage.ENGLISH,titles,code)
    private fun minor(expected:Long,actual:BigInteger?)=assertEquals(BigInteger.valueOf(expected),actual)
    private fun unavailable(result:BudgetProjection){minor(1000,result.totalLimitMinor);assertNull(result.totalSpentMinor);assertNull(result.remainingMinor);assertNull(result.branches.single().pace.health)}
    @Test fun `required raw amount cannot become quoted money or a confident zero`() {
        for(value in listOf(JsonPrimitive("7"),JsonPrimitive("broken"),JsonNull,JsonPrimitive(1.5),Json.parseToJsonElement("9223372036854775808"))) unavailable(project(row().with("amount_minor",value)))
        val missing=row().let {it.copy(payload=JsonObject(it.payload-"amount_minor"))}
        unavailable(project(missing))
    }
    @Test fun `fixed expense override ignores unusable original income destination and creation fields`() {
        val raw=row().with("amount_minor",buildJsonObject {}).with("reporting_expense_minor",JsonPrimitive(2)).with("reporting_income_minor",buildJsonObject {})
            .with("destination_amount_minor",buildJsonObject {}).with("created_at",buildJsonObject {}).with("primary_kind_raw_value",buildJsonObject {})
        minor(2,project(raw).totalSpentMinor);minor(998,project(raw).remainingMinor)
    }
    @Test fun `unreadable present expense override cannot fall through to original money`() {
        for(value in listOf(JsonPrimitive("2"),JsonPrimitive("broken"),buildJsonObject {})) unavailable(project(row().with("reporting_expense_minor",value)))
        minor(7,project(row().with("reporting_expense_minor",JsonNull)).totalSpentMinor)
    }
    @Test fun `required eligibility and unplaced occurred calendar retain unknown spending`() {
        for((key,value) in listOf("entry_status_raw_value" to buildJsonObject {},"is_archived" to JsonPrimitive("false"),"deleted_at" to buildJsonObject {},"deleted_at" to JsonPrimitive("broken"),"occurred_at" to buildJsonObject {})) unavailable(project(row().with(key,value)))
    }
    @Test fun `known unrelated excluded and zero records need no unused damaged fields`() {
        val bad=row().with("amount_minor",JsonPrimitive("broken"));val excluded=listOf(bad.with("is_archived",JsonPrimitive(true)),bad.copy(deletedAt=now),bad.with("entry_status_raw_value",JsonPrimitive("draft")),bad.with("occurred_at",JsonPrimitive("2026-11-01T00:00:00Z")),bad.with("primary_kind_raw_value",JsonPrimitive("income")))
        minor(0,project(*excluded.toTypedArray()).totalSpentMinor)
        val travel="66666666-6666-6666-6666-666666666666"
        minor(0,project(bad.with("category_id",JsonPrimitive(travel)).with("occurred_at",buildJsonObject {}),categories=listOf(category(parent,"Living",null),category(),category(travel,"Travel"))).totalSpentMinor)
        minor(0,project(row(0).with("category_id",buildJsonObject {}).with("source_currency_code",buildJsonObject {}).with("occurred_at",buildJsonObject {})).totalSpentMinor)
        val debt=bad.with("primary_kind_raw_value",JsonPrimitive("transfer")).with("transfer_subtype_raw_value",JsonPrimitive("debt")).with("debt_intent_raw_value",JsonPrimitive("lend"))
        minor(0,project(debt).totalSpentMinor)
    }
    @Test fun `historical wallet currency ignores unused name opening clocks and ordinary expense kind`() {
        val rate=listOf(ExchangeRateSnapshot("JPY","VND","165","fixture",0,null))
        val record=row(165).with("source_currency_code",JsonNull)
        for(key in listOf("name","opening_balance_minor","created_at","kind_raw_value")) minor(1,project(record,wallets=listOf(wallet("VND").with(key,buildJsonObject {})),rates=rate).totalSpentMinor)
        minor(1,project(record,wallets=listOf(wallet("VND").with("is_archived",JsonPrimitive(true))),rates=rate).totalSpentMinor)
    }
    @Test fun `present bad source and missing required source metadata never impersonate legacy yen`() {
        unavailable(project(row().with("source_currency_code",buildJsonObject {})))
        unavailable(project(row().with("source_currency_code",JsonNull),wallets=emptyList()))
        minor(7,project(row(),wallets=emptyList()).totalSpentMinor)
        minor(7,project(row().with("source_wallet_id",JsonNull).with("source_currency_code",JsonNull),wallets=emptyList()).totalSpentMinor)
    }
    @Test fun `required title kind and category reference uncertainty never becomes neutral zero`() {
        unavailable(project(row().with("title",buildJsonObject {})))
        unavailable(project(row().with("category_id",buildJsonObject {})))
        unavailable(project(row().with("title",JsonPrimitive("Card payment")),wallets=listOf(wallet().with("kind_raw_value",buildJsonObject {}))))
        minor(7,project(row().with("title",JsonPrimitive("Card payment")),wallets=listOf(wallet().with("kind_raw_value",JsonPrimitive("creditCard")))).totalSpentMinor)
    }
    @Test fun `canonical equivalent generated and card titles retain neutral expense classification`() {
        for(title in listOf("Thanh toán thẻ","Điều chỉnh số dư","カード支払い")) {
            val decomposed=java.text.Normalizer.normalize(title,java.text.Normalizer.Form.NFD)
            minor(0,project(row().with("title",JsonPrimitive(decomposed))).totalSpentMinor)
        }
        minor(0,project(row().with("title",JsonPrimitive("Thanh toán the"))).totalSpentMinor)
        for(title in listOf("ｃａｒｄ ｐａｙｍｅｎｔ","ｶｰﾄﾞ支払い")) minor(7,project(row().with("title",JsonPrimitive(title))).totalSpentMinor)
    }
    @Test fun `raw exact totals keep overflow cancellation per record rounding and imported same ISO`() {
        assertEquals(BigInteger.valueOf(Long.MAX_VALUE)*BigInteger.TWO,project(row(Long.MAX_VALUE),row(Long.MAX_VALUE)).totalSpentMinor)
        minor(-1,project(row(Long.MAX_VALUE),row(Long.MIN_VALUE)).totalSpentMinor)
        minor(16,project(row(3),row(3),plans=listOf(plan("VND")),code="VND",rates=listOf(ExchangeRateSnapshot("JPY","VND","2.5","fixture",0,null))).totalSpentMinor)
        minor(1375,project(row(1375).with("source_currency_code",JsonPrimitive("USD")),plans=listOf(plan("USD")),code="USD").totalSpentMinor)
    }
    @Test fun `foreign mismatched and duplicate records cannot hide or add owned money`() {
        val owned=row();val foreign=owned.copy(ownerUserId=other).with("user_id",JsonPrimitive(other))
        val mismatch=row(100).with("id",JsonPrimitive(UUID.randomUUID().toString()))
        minor(7,project(foreign,owned,mismatch).totalSpentMinor)
        val snapshot=BudgetReadSnapshot(UserId(other),listOf(plan(),owned,wallet(),category(parent,"Living",null),category()))
        val held=projectRawBudgetReadSnapshot(owner,snapshot,month,Instant.parse(now),zone,emptyList(),CategoryNameLanguage.ENGLISH,emptySet(),"JPY")
        assertNull(held.totalLimitMinor);assertNull(held.totalSpentMinor)
    }
    @Test fun `unreadable parent holds parent spending while direct child amount stays known`() {
        val parentPlan=plan().copy(id=UUID.randomUUID().toString()).let {it.with("id",JsonPrimitive(it.id))}.with("category_id",JsonPrimitive(parent)).with("category_id_snapshot",JsonPrimitive(parent))
            .with("category_name_snapshot",JsonPrimitive("Living")).with("category_name_english_snapshot",JsonPrimitive("Living")).with("category_is_parent_snapshot",JsonPrimitive(true)).with("category_parent_id_snapshot",JsonNull).with("limit_minor",JsonPrimitive(2000))
        val badCategory=category().with("parent_category_id",buildJsonObject {})
        val result=project(row(),categories=listOf(category(parent,"Living",null),badCategory),plans=listOf(parentPlan,plan()))
        minor(2000,result.totalLimitMinor);assertNull(result.totalSpentMinor);minor(7,result.branches.single().children.single().spentMinor)
        minor(7,project(row(),categories=listOf(category(parent,"Living",null),badCategory)).totalSpentMinor)
    }
    @Test fun `canonical equivalent and Unicode whitespace legacy names still match spending`() {
        for((frozen,live) in listOf("CAFE\u0301" to "Café","Food Travel" to "Food\u00a0\u0085Travel")) {
            val legacy=plan().with("category_id",JsonNull).with("category_id_snapshot",JsonNull).with("category_name_snapshot",JsonPrimitive(frozen)).with("category_name_english_snapshot",JsonPrimitive(frozen))
            minor(7,project(row(),plans=listOf(legacy),categories=listOf(category(parent,"Living",null),category(name=live))).totalSpentMinor)
        }
    }
}
