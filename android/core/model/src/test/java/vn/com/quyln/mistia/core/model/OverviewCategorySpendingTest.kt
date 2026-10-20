package vn.com.quyln.mistia.core.model

import java.math.BigInteger
import java.time.*
import java.util.UUID
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class OverviewCategorySpendingTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other="99999999-9999-9999-9999-999999999999"
    private val zone=ZoneId.of("Asia/Tokyo")
    private val now=Instant.parse("2026-04-09T03:00:00Z")
    private val april=YearMonth.of(2026,4)
    private val time="2026-04-06T00:00:00Z"
    private fun category(name:String,parent:String?=null)=TransactionCategoryRecord.fromCloudRecord(CloudRecord(CloudEntity.TRANSACTION_CATEGORY.table,UUID.randomUUID().toString(),owner.value,
        buildJsonObject {put("name",name);put("kind_raw_value","expense");put("icon_symbol_name","fork.knife");put("icon_color_hex","#FF8A4C");put("created_at",time);put("updated_at",time);parent?.let {put("parent_category_id",it)}},time,null,0))
    private fun row(amount:Long=100,categoryId:String?=null,date:String=time,kind:String="expense")=LedgerTransactionRecord.fromCloudRecord(CloudRecord(CloudEntity.LEDGER_TRANSACTION.table,UUID.randomUUID().toString(),owner.value,
        buildJsonObject {put("primary_kind_raw_value",kind);put("entry_status_raw_value","posted");put("amount_minor",amount);put("source_currency_code","JPY");put("title","Ordinary");put("occurred_at",date);put("created_at",date);categoryId?.let {put("category_id",it)}},time,null,0))
    private fun wallet(code:String="VND",subject:String=owner.value)=LedgerWalletRecord.fromCloudRecord(CloudRecord(CloudEntity.LEDGER_WALLET.table,UUID.randomUUID().toString(),subject,
        buildJsonObject {put("name","Wallet");put("kind_raw_value","cash");put("currency_code",code);put("opening_balance_minor",0);put("created_at",time);put("updated_at",time)},time,null,0))
    private fun project(rows:List<LedgerTransactionRecord>,categories:List<TransactionCategoryRecord> = emptyList(),currency:String="JPY",rates:List<ExchangeRateSnapshot> = emptyList(),
        wallets:List<LedgerWalletRecord> = emptyList(),language:String="vi",catalog:SystemCategoryCatalog?=null,tz:ZoneId=zone)=
        overviewCategorySpendingMonths(owner,rows,wallets,categories,currency,rates,language,catalog,now,tz)
    private fun n(value:Long)=BigInteger.valueOf(value)
    @Test fun `parent rollup includes direct parent and separate sorted children with exact branch styling`() {
        val food=category("Food");val grocery=category("Grocery",food.id);val dining=category("Dining",food.id);val health=category("Health")
        val page=project(listOf(row(5000,grocery.id),row(3000,dining.id),row(1000,food.id),row(2000,health.id)),listOf(food,grocery,dining,health)).single()
        assertEquals(n(11000),page.totalMinor);assertEquals(listOf("Food","Health"),page.slices.map {it.name});assertEquals(listOf(n(9000),n(2000)),page.slices.map {it.amountMinor})
        val root=page.slices.first();assertEquals(food.id,root.categoryId);assertEquals("#FF8A4C",root.colorHex);assertTrue(root.canDrillDown)
        assertEquals(listOf("Grocery","Dining","Food"),root.childSlices.map {it.name});assertEquals(listOf(n(5000),n(3000),n(1000)),root.childSlices.map {it.amountMinor})
        assertTrue(root.childSlices.all {it.childSlices.isEmpty()})
    }
    @Test fun `same normalized names merge across category and parent IDs including Unicode whitespace and case`() {
        val first=category("Ăn uống");val second=category(" ăn\u00a0\u0085\u3000 UỐNG ")
        val result=project(listOf(row(5000,first.id),row(3000,second.id)),listOf(first,second)).single()
        assertEquals(listOf("Ăn uống"),result.slices.map {it.name});assertEquals(n(8000),result.slices.single().amountMinor);assertEquals(1,result.slices.single().childSlices.size)
        val decomposed=first.copy(id=UUID.randomUUID().toString(),name=java.text.Normalizer.normalize(first.name,java.text.Normalizer.Form.NFD))
        assertEquals(1,project(listOf(row(5000,first.id),row(3000,decomposed.id)),listOf(first,decomposed)).single().slices.size)
        val parentA=category("HOME");val parentB=category(" home ");val childA=category("Food",parentA.id);val childB=category("Food",parentB.id)
        assertEquals(1,project(listOf(row(2,childA.id),row(3,childB.id)),listOf(parentA,parentB,childA,childB)).single().slices.size)
    }
    @Test fun `missing or foreign category metadata is one uncategorized branch without exposing names`() {
        val foreign=category("Private foreign").copy(ownerUserId=other)
        val result=project(listOf(row(2000),row(2000,foreign.id)),listOf(foreign)).single()
        val slice=result.slices.single();assertEquals("uncategorized-expense",slice.id);assertNull(slice.categoryId);assertNull(slice.name);assertEquals("tray.full.fill",slice.iconSymbolName)
        assertEquals("#8A8A8E",slice.colorHex);assertEquals(n(4000),slice.amountMinor);assertFalse(slice.canDrillDown)
    }
    @Test fun `only owned active posted known ordinary domain and valid calendars contribute`() {
        val good=row(9007199254740993L)
        val invalid=listOf(good.copy(ownerUserId=other),good.copy(deletedAt="deleted"),good.copy(isArchived=true),good.copy(entryStatusWireValue="draft"),good.copy(entryStatusWireValue="unknown"),
            good.copy(primaryKindWireValue="unknown"),good.copy(occurredAt="broken"),good.copy(settlementRoleWireValue="investmentPurchase"))
        assertEquals(n(good.amountMinor),project(invalid+good).single().totalMinor)
    }
    @Test fun `category eligibility honors signed explicit reporting zero override paid for and identity-only adjustment rule`() {
        val paidCategory=category("Paid for")
        val paid=row(20,paidCategory.id,kind="transfer").copy(transferSubtypeWireValue="debt",debtIntentWireValue="borrow")
        val zero=row(0,date="2026-02-01T00:00:00Z")
        val rows=listOf(row(777,kind="income").copy(reportingExpenseMinor=7),row(33).copy(reportingExpenseMinor=-3),paid,row().copy(title="Balance adjustment"),zero,
            row(500).copy(reportingExpenseMinor=0),row(400,TransactionCategoryRecord.BALANCE_ADJUSTMENT_EXPENSE_ID),row(500,SystemCategoryIdentity.canonicalId("loan_repayment")),row(600).copy(title="Card payment"))
        val pages=project(rows,listOf(paidCategory));assertEquals(listOf(april.minusMonths(2),april.minusMonths(1),april),pages.map {it.month});assertEquals(n(124),pages.last().totalMinor)
        assertEquals(BigInteger.ZERO,pages.first().totalMinor)
    }
    @Test fun `continuous history includes current month future days excludes future months and respects local month boundary`() {
        val pages=project(listOf(row(100,date="2026-01-01T00:00:00Z"),row(200,date="2026-04-30T00:00:00Z"),row(999,date="2026-05-01T00:00:00Z")))
        assertEquals(listOf(april.minusMonths(3),april.minusMonths(2),april.minusMonths(1),april),pages.map {it.month});assertEquals(listOf(n(100),n(0),n(0),n(200)),pages.map {it.totalMinor})
        assertEquals(listOf(april),project(listOf(row(date="2026-05-01T00:00:00Z"))).map {it.month})
        val boundary=row(date="2026-02-28T15:00:00Z")
        assertEquals(april.minusMonths(1),project(listOf(boundary)).first().month);assertEquals(april.minusMonths(2),project(listOf(boundary),tz=ZoneId.of("Asia/Ho_Chi_Minh")).first().month)
    }
    @Test fun `source FX rounds each reported record ignores stored reporting pair and uses owned wallet currency fallback`() {
        val rate=ExchangeRateSnapshot("JPY","VND","2.5","test",0,null)
        val a=row(3).copy(reportingCurrencyCode="VND",reportingAmountMinor=999)
        assertEquals(n(16),project(listOf(a,a.copy(id=UUID.randomUUID().toString())),currency="VND",rates=listOf(rate)).single().totalMinor)
        assertEquals(n(1),project(listOf(a.copy(sourceCurrencyCode="VND")),rates=listOf(rate)).single().totalMinor)
        assertEquals(n(8),project(listOf(a.copy(amountMinor=999,reportingExpenseMinor=3)),currency="VND",rates=listOf(rate)).single().totalMinor)
        val owned=wallet();assertEquals(n(3),project(listOf(a.copy(sourceCurrencyCode=null,sourceWalletId=owned.id)),currency="VND",wallets=listOf(owned)).single().totalMinor)
    }
    @Test fun `missing unsupported or malformed FX holds whole month without partial or relabeled pie then recovers`() {
        val a=row(3);val b=row(10).copy(sourceCurrencyCode="VND")
        val missing=project(listOf(a,b),currency="VND").single();assertNull(missing.totalMinor);assertTrue(missing.slices.isEmpty())
        val rate=ExchangeRateSnapshot("JPY","VND","2.5","test",0,null)
        assertEquals(n(18),project(listOf(a,b),currency="VND",rates=listOf(rate)).single().totalMinor)
        assertNull(project(listOf(a.copy(sourceCurrencyCode="USD",amountMinor=1375))).single().totalMinor)
        assertEquals(n(1375),project(listOf(a.copy(sourceCurrencyCode="USD",amountMinor=1375)),currency="USD").single().totalMinor)
        assertNull(project(listOf(a.copy(sourceCurrencyCode="??"))).single().totalMinor)
        val foreign=wallet(subject=other);assertNull(project(listOf(a.copy(sourceCurrencyCode=null,sourceWalletId=foreign.id)),currency="VND",wallets=listOf(foreign)).single().totalMinor)
    }
    @Test fun `localized category names use explicit translations then immutable system catalog while historical labels remain owned`() {
        val catalog=SystemCategoryCatalog.parse("""[{"id":"parent_expense_food","kind":"expense","active":true,"icon":"fork.knife","fallbackIcon":"fork.knife","color":"#FF8A4C","translations":{"vi":"Thực phẩm","en":"Food","ja":"食費"},"aliases":[],"children":[]}]""")
        val system=category("Tên gốc").copy(systemKey="parent_expense_food",nameEnglish=null,nameJapanese=" ",isArchived=true,deletedAt="deleted")
        val record=row(100,system.id)
        assertEquals("Food",project(listOf(record),listOf(system),language="en",catalog=catalog).single().slices.single().name)
        assertEquals("食費",project(listOf(record),listOf(system),language="ja",catalog=catalog).single().slices.single().name)
        assertEquals("Tên gốc",project(listOf(record),listOf(system),language="vi",catalog=catalog).single().slices.single().name)
        assertEquals("Custom",project(listOf(record),listOf(system.copy(nameEnglish=" Custom ")),language="en",catalog=catalog).single().slices.single().name)
        assertEquals("Food",project(listOf(record),listOf(system.copy(nameEnglish="\u0085")),language="en",catalog=catalog).single().slices.single().name)
        assertEquals("食費",project(listOf(record),listOf(system.copy(nameJapanese="\u0085")),language="ja",catalog=catalog).single().slices.single().name)
    }
    @Test fun `aggregate and converted sums remain exact beyond Long and cancel signed overflow across branches`() {
        val food=category("Food");val health=category("Health")
        val rows=listOf(row(Long.MAX_VALUE,food.id),row(Long.MAX_VALUE,food.id),row(-Long.MAX_VALUE,health.id))
        val page=project(rows,listOf(food,health)).single();assertEquals(n(Long.MAX_VALUE),page.totalMinor);assertEquals(n(Long.MAX_VALUE)*n(2),page.slices.first().amountMinor)
        val converted=listOf(row(Long.MAX_VALUE),row(-Long.MAX_VALUE),row(3))
        assertEquals(n(6),project(converted,currency="VND",rates=listOf(ExchangeRateSnapshot("JPY","VND","2","test",0,null))).single().totalMinor)
    }
    @Test fun `display keeps five positive slices plus exact Other with one-level selection and exact rounded percentages`() {
        val source=(8L downTo 1).map {value -> OverviewCategorySpendingSlice("category-$value","$value","Name$value","fork.knife","#FF8A4C",n(value),listOf(OverviewCategorySpendingSlice("child$value","child$value","Child$value","fork.knife","#FF8A4C",n(value),emptyList())))}
        val display=overviewCategoryChartSlices(source+source.first().copy(id="negative",amountMinor=n(-100)),"root-april")
        assertEquals(6,display.size);assertEquals(source.take(5).map {it.id},display.take(5).map {it.id});val overflow=display.last()
        assertTrue(overflow.isOverflow);assertTrue(overflow.canSelect);assertEquals(n(6),overflow.amountMinor);assertEquals(3,overflow.children.size)
        assertTrue(overviewCategoryChartSlices(overflow.children,"drill-april",allowSelection=false).none {it.canSelect})
        assertEquals(50,overviewCategoryPercentage(n(Long.MAX_VALUE)*n(2),n(Long.MAX_VALUE)*n(4)));assertEquals(13,overviewCategoryPercentage(n(1),n(8)));assertEquals(0,overviewCategoryPercentage(n(1),n(0)))
    }
}
