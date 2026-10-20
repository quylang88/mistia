package vn.com.quyln.mistia.feature.overview

import java.math.BigInteger
import java.time.*
import java.util.UUID
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import vn.com.quyln.mistia.core.model.*

class OverviewCategoryRawInputsTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other="99999999-9999-9999-9999-999999999999"
    private val time="2026-10-20T12:00:00Z"
    private val reference=Instant.parse(time)
    private val zone=ZoneOffset.UTC
    private val month=YearMonth.of(2026,10)
    private fun row(amount:Long=7,kind:String="expense",date:String=time):CloudRecord {
        val id=UUID.randomUUID().toString()
        return CloudRecord(CloudEntity.LEDGER_TRANSACTION.table,id,owner.value,buildJsonObject {
            put("id",id);put("user_id",owner.value);put("primary_kind_raw_value",kind);put("entry_status_raw_value","posted");put("title","Category raw")
            put("amount_minor",amount);put("source_currency_code","JPY");put("is_archived",false);put("occurred_at",date);put("created_at",time);put("updated_at",time)
        },time,null,0)
    }
    private fun CloudRecord.with(key:String,value:JsonElement)=copy(payload=JsonObject(payload+(key to value)))
    private fun project(vararg records:CloudRecord)=overviewRawCategorySpendingMonths(owner,records.toList(),emptyList(),emptyList(),"JPY",reference=reference,zone=zone)
    private fun current(vararg records:CloudRecord)=project(*records).single {it.month==month}
    private fun minor(expected:Long,actual:BigInteger?)=assertEquals(BigInteger.valueOf(expected),actual)
    @Test fun `required unreadable expense holds whole chart instead of partial or empty zero`() {
        val unknown=row().with("amount_minor",JsonPrimitive("broken"))
        val page=current(row(3),unknown);assertNull(page.totalMinor);assertTrue(page.slices.isEmpty())
        assertNull(current(unknown).totalMinor)
        for(value in listOf(JsonPrimitive("7"),JsonPrimitive(1.5),JsonNull)) assertNull(current(row().with("amount_minor",value)).totalMinor)
    }
    @Test fun `unknown only historical expense creates selectable month and contiguous pages`() {
        val pages=project(row(date="2026-08-12T00:00:00Z").with("amount_minor",JsonPrimitive("broken")))
        assertEquals(listOf(month.minusMonths(2),month.minusMonths(1),month),pages.map {it.month});assertNull(pages.first().totalMinor);minor(0,pages.last().totalMinor)
    }
    @Test fun `unused created destination and income fields cannot remove known category spending`() {
        for(key in listOf("created_at","destination_amount_minor","reporting_income_minor")) {
            val page=current(row().with(key,JsonPrimitive("broken")));minor(7,page.totalMinor);minor(7,page.slices.single().amountMinor)
        }
    }
    @Test fun `explicit expense override removes unused original and primary dependencies`() {
        val overridden=row().with("amount_minor",JsonPrimitive("broken")).with("primary_kind_raw_value",JsonPrimitive("futureKind")).with("reporting_expense_minor",JsonPrimitive(3))
        minor(3,current(overridden).totalMinor)
        assertNull(current(row(kind="income").with("reporting_expense_minor",JsonPrimitive("broken"))).totalMinor)
        minor(0,current(row().with("reporting_expense_minor",JsonPrimitive(0))).totalMinor)
    }
    @Test fun `unknown status archive grouping or required classification never becomes confident pie`() {
        for(key in listOf("entry_status_raw_value","is_archived","primary_kind_raw_value","category_id")) assertNull(current(row().with(key,buildJsonObject {})).totalMinor)
        val record=row().with("reporting_expense_minor",JsonPrimitive(3)).with("category_id",buildJsonObject {})
        assertNull(current(record).totalMinor)
    }
    @Test fun `undated eligible spending holds all known pages without invented history`() {
        val pages=project(row(3,date="2026-09-12T00:00:00Z"),row().with("occurred_at",JsonPrimitive("broken")))
        assertEquals(listOf(month.minusMonths(1),month),pages.map {it.month});pages.forEach {assertNull(it.totalMinor);assertTrue(it.slices.isEmpty())}
    }
    @Test fun `wallet currency survives unused opening and kind while strict bad currency holds chart`() {
        val id=UUID.randomUUID().toString();val wallet=CloudRecord(CloudEntity.LEDGER_WALLET.table,id,owner.value,buildJsonObject {
            put("id",id);put("user_id",owner.value);put("currency_code","VND");put("kind_raw_value","futureKind");put("opening_balance_minor","broken")
        },time,null,0)
        val record=row(165).with("source_currency_code",JsonNull).with("source_wallet_id",JsonPrimitive(id))
        val page=overviewRawCategorySpendingMonths(owner,listOf(record),listOf(wallet),emptyList(),"JPY",listOf(ExchangeRateSnapshot("JPY","VND","165","test",0,null)),reference=reference,zone=zone).single()
        minor(1,page.totalMinor);minor(1,page.slices.single().amountMinor)
        assertNull(current(row().with("source_currency_code",buildJsonObject {})).totalMinor)
    }
    @Test fun `known inactive foreign future neutral and zero cannot poison category money`() {
        val bad=row().with("amount_minor",JsonPrimitive("broken"))
        val excluded=listOf(bad.copy(ownerUserId=other),bad.with("user_id",JsonPrimitive(other)),bad.with("id",JsonPrimitive(UUID.randomUUID().toString())),bad.copy(deletedAt=time),
            bad.with("entry_status_raw_value",JsonPrimitive("draft")),bad.with("is_archived",JsonPrimitive(true)),bad.with("occurred_at",JsonPrimitive("2026-11-01T00:00:00Z")),
            bad.with("primary_kind_raw_value",JsonPrimitive("income")),bad.with("category_id",JsonPrimitive(SystemCategoryIdentity.canonicalId("loan_repayment"))),bad.with("settlement_role_raw_value",JsonPrimitive("investmentBuy")))
        minor(3,current(*(excluded+row(3)).toTypedArray()).totalMinor)
        minor(0,current(row(0).with("source_currency_code",buildJsonObject {}).with("occurred_at",JsonPrimitive("broken"))).totalMinor)
        assertEquals(BigInteger.valueOf(Long.MAX_VALUE)*BigInteger.TWO,current(row(Long.MAX_VALUE),row(Long.MAX_VALUE)).totalMinor)
        minor(-1,current(row(Long.MAX_VALUE),row(Long.MIN_VALUE)).totalMinor)
    }
    @Test fun `unreadable category reference cannot prove a paid for debt has no category relationship`() {
        val id=UUID.randomUUID().toString()
        val category=TransactionCategoryRecord.fromCloudRecord(CloudRecord(CloudEntity.TRANSACTION_CATEGORY.table,id,owner.value,buildJsonObject {put("id",id);put("user_id",owner.value);put("name","Paid for");put("kind_raw_value","expense")},time,null,0))
        val paid=row(kind="transfer").with("transfer_subtype_raw_value",JsonPrimitive("debt")).with("debt_intent_raw_value",JsonPrimitive("borrow")).with("category_id",buildJsonObject {})
        val page=overviewRawCategorySpendingMonths(owner,listOf(paid),emptyList(),listOf(category),"JPY",reference=reference,zone=zone).single()
        assertNull(page.totalMinor);assertTrue(page.slices.isEmpty())
        minor(0,current(paid).totalMinor)
    }
    @Test fun `unreadable domain role cannot silently become ordinary expense even with an override`() {
        for(record in listOf(row(),row().with("reporting_expense_minor",JsonPrimitive(3)))) assertNull(current(record.with("settlement_role_raw_value",buildJsonObject {})).totalMinor)
        minor(0,current(row(0).with("settlement_role_raw_value",buildJsonObject {})).totalMinor)
    }

    @Test fun `original zero creates known dated history but explicit zero override cannot`() {
        val old=row(0,date="2026-08-12T00:00:00Z").with("source_currency_code",buildJsonObject {})
        val original=project(old);assertEquals(month.minusMonths(2),original.first().month);original.forEach {minor(0,it.totalMinor)}
        assertEquals(listOf(month),project(old.with("reporting_expense_minor",JsonPrimitive(0))).map {it.month})
        val uncertain=project(old.with("entry_status_raw_value",buildJsonObject {}));uncertain.forEach {minor(0,it.totalMinor)}
    }
    @Test fun `raw category relationships preserve parent rollup first representative and per record FX`() {
        fun category(name:String,parent:String?=null):TransactionCategoryRecord {
            val id=UUID.randomUUID().toString();return TransactionCategoryRecord.fromCloudRecord(CloudRecord(CloudEntity.TRANSACTION_CATEGORY.table,id,owner.value,buildJsonObject {
                put("id",id);put("user_id",owner.value);put("name",name);put("kind_raw_value","expense");parent?.let {put("parent_category_id",it)}
            },time,null,0))
        }
        val parent=category("Food");val child=category("Grocery",parent.id)
        val first=row(3).with("category_id",JsonPrimitive(child.id)).with("created_at",JsonPrimitive("broken"))
        val second=row(3).with("category_id",JsonPrimitive(parent.id))
        val page=overviewRawCategorySpendingMonths(owner,listOf(first,second),emptyList(),listOf(parent,child),"VND",listOf(ExchangeRateSnapshot("JPY","VND","2.5","test",0,null)),reference=reference,zone=zone).single()
        minor(16,page.totalMinor);val root=page.slices.single();assertEquals(parent.id,root.categoryId);minor(16,root.amountMinor);assertEquals(setOf(child.id,parent.id),root.childSlices.map {it.categoryId}.toSet());root.childSlices.forEach {minor(8,it.amountMinor)}
        val paid=row(5,"transfer").with("transfer_subtype_raw_value",JsonPrimitive("debt")).with("debt_intent_raw_value",JsonPrimitive("borrow")).with("category_id",JsonPrimitive(child.id))
        fun paidPage(categories:List<TransactionCategoryRecord>)=overviewRawCategorySpendingMonths(owner,listOf(paid),emptyList(),categories,"JPY",reference=reference,zone=zone).single()
        minor(5,paidPage(listOf(parent,child)).totalMinor);minor(0,paidPage(listOf(child.copy(ownerUserId=other))).totalMinor)
    }
    @Test fun `local month boundaries and explicit source identity preserve imported money without FX`() {
        val record=row(1375,date="2026-08-31T15:00:00Z").with("source_currency_code",JsonPrimitive("USD"))
        val pages=overviewRawCategorySpendingMonths(owner,listOf(record),emptyList(),emptyList(),"USD",reference=reference,zone=ZoneId.of("Asia/Tokyo"))
        assertEquals(month.minusMonths(1),pages.first().month);minor(1375,pages.first().totalMinor)
        assertNull(project(record).first().totalMinor)
    }

}
