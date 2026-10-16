package vn.com.quyln.mistia.core.model

import java.time.*
import java.util.UUID
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class OverviewWeeklySpendingTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other="99999999-9999-9999-9999-999999999999"
    private val zone=ZoneId.of("Asia/Tokyo")
    private val now=Instant.parse("2026-04-09T03:00:00Z")
    private val monday=LocalDate.of(2026,4,6)
    private val titles=mapOf(GeneratedTransactionTitle.BALANCE_ADJUSTMENT to listOf("Balance adjustment","Điều chỉnh số dư","残高調整"))
    private fun record(amount:Long=100,date:String="2026-04-06T00:00:00Z",kind:String="expense")=LedgerTransactionRecord.fromCloudRecord(CloudRecord(CloudEntity.LEDGER_TRANSACTION.table,UUID.randomUUID().toString(),owner.value,
        buildJsonObject {put("primary_kind_raw_value",kind);put("entry_status_raw_value","posted");put("amount_minor",amount);put("source_currency_code","JPY");put("title","Ordinary");put("occurred_at",date);put("created_at",date)},null,null,0))
    private fun project(rows:List<LedgerTransactionRecord>,currency:String?=null,rates:List<ExchangeRateSnapshot> = emptyList(),wallets:List<LedgerWalletRecord> = emptyList(),reference:Instant=now,tz:ZoneId=zone)=
        overviewWeeklySpending(owner,rows,wallets,currency,rates,titles,reference,tz)
    @Test fun `current Monday to Sunday includes future days in current week and exact source amounts`() {
        val rows=listOf(record(1000),record(2000,"2026-04-08T09:00:00Z"),record(3000,"2026-04-12T01:00:00Z"))
        val week=project(rows).single();assertEquals(monday,week.start);assertEquals(monday.plusDays(6),week.end);assertTrue(week.isCurrent)
        assertEquals(listOf(1000L,0L,2000L,0L,0L,0L,3000L),week.points.map {it.amountMinor});assertEquals(1.0/3,week.points.first().intensity,0.00001)
    }
    @Test fun `weekly history retains empty gaps until current week and earliest nonzero record before missing conversion`() {
        val old=record(date="2026-03-23T00:00:00Z")
        val pages=project(listOf(old),currency="VND")
        assertEquals(listOf(monday.minusWeeks(2),monday.minusWeeks(1),monday),pages.map {it.start});assertTrue(pages.flatMap {it.points}.all {it.amountMinor==0L})
        assertEquals(listOf(false,false,true),pages.map {it.isCurrent})
    }
    @Test fun `future weeks never create pages and current zero page remains when future records are the only expenses`() {
        val future=record(date="2026-04-13T00:00:00Z")
        val pages=project(listOf(future));assertEquals(listOf(monday),pages.map {it.start});assertTrue(pages.single().points.all {it.amountMinor==0L})
    }
    @Test fun `owner active posted known kind and valid occurred calendar alone contribute`() {
        val good=record(9007199254740993L)
        val bad=listOf(good.copy(ownerUserId=other),good.copy(isArchived=true),good.copy(deletedAt="deleted"),good.copy(entryStatusWireValue="draft"),
            good.copy(entryStatusWireValue="unknown"),good.copy(primaryKindWireValue="unknown"),good.copy(occurredAt="broken"))
        assertEquals(9007199254740993L,project(bad+good).last().points.first().amountMinor)
    }
    @Test fun `local Monday boundary and year crossing use local calendar rather than UTC or ISO week number`() {
        val row=record(date="2026-04-05T15:00:00Z")
        assertEquals(monday,project(listOf(row)).first().start)
        assertEquals(monday.minusWeeks(1),project(listOf(row),tz=ZoneId.of("Asia/Ho_Chi_Minh")).first().start)
        val year=project(listOf(record(date="2026-01-01T00:00:00Z")),reference=Instant.parse("2026-01-02T00:00:00Z"))
        assertEquals(LocalDate.of(2025,12,29),year.single().start);assertEquals(100L,year.single().points[3].amountMinor)
    }
    @Test fun `source conversion rounds per record ignores reporting snapshot and supports inverse negative override`() {
        val rate=ExchangeRateSnapshot("JPY","VND","2.5","test",0,null)
        val row=record(3).copy(reportingCurrencyCode="VND",reportingAmountMinor=999)
        assertEquals(16L,project(listOf(row,row.copy(id=UUID.randomUUID().toString())),"VND",listOf(rate)).last().points.first().amountMinor)
        assertEquals(1L,project(listOf(row.copy(sourceCurrencyCode="VND")),"JPY",listOf(rate)).last().points.first().amountMinor)
        assertEquals(-8L,project(listOf(row.copy(reportingExpenseMinor=-3)),"VND",listOf(rate)).last().points.first().amountMinor)
    }
    @Test fun `reported expense classification is shared with monthly adjustment installment debt and explicit overrides`() {
        val paid=record(20,kind="transfer").copy(transferSubtypeWireValue="debt",debtIntentWireValue="borrow",categoryId=UUID.randomUUID().toString())
        val hidden=listOf(record().copy(title="Balance adjustment"),record().copy(categoryId=SystemCategoryIdentity.canonicalId("loan_repayment")),record().copy(title="Card payment"),record(kind="income"))
        val rows=hidden+paid+record().copy(reportingExpenseMinor=-5)+record().copy(reportingExpenseMinor=0)
        assertEquals(15L,project(rows).last().points.first().amountMinor)
    }
    @Test fun `daily sum and conversion retain overflow until cancellation before final daily clamp`() {
        val rows=listOf(Long.MAX_VALUE,Long.MAX_VALUE,-Long.MAX_VALUE).map {record().copy(reportingExpenseMinor=it)}
        for(order in listOf(rows,rows.reversed())) assertEquals(Long.MAX_VALUE,project(order).last().points.first().amountMinor)
        val rate=ExchangeRateSnapshot("JPY","VND","2","test",0,null)
        val converted=listOf(Long.MAX_VALUE,-Long.MAX_VALUE,3).map {record().copy(reportingExpenseMinor=it)}
        assertEquals(6L,project(converted,"VND",listOf(rate)).last().points.first().amountMinor)
    }
    @Test fun `intensity safely spans signed Long extremes and equal nonzero values have neutral half intensity`() {
        val rows=listOf(record().copy(reportingExpenseMinor=Long.MIN_VALUE),record(date="2026-04-07T00:00:00Z").copy(reportingExpenseMinor=Long.MAX_VALUE))
        val points=project(rows).last().points;assertEquals(0.0,points[0].intensity,0.0);assertEquals(1.0,points[1].intensity,0.0)
        assertTrue(points.all {it.intensity.isFinite() && it.intensity in 0.0..1.0})
        val equal=(0L..6).map {record(date=monday.plusDays(it).atStartOfDay(zone).toInstant().toString())}
        assertTrue(project(equal).last().points.all {it.intensity==0.5})
    }
    @Test fun `empty and neutral records provide seven zero daily values and zero intensity`() {
        val pages=project(listOf(record(0),record(kind="transfer").copy(transferSubtypeWireValue="internalTransfer")))
        assertEquals(1,pages.size);assertEquals((0L..6).map {monday.plusDays(it)},pages.single().points.map {it.date})
        assertTrue(pages.single().points.all {it.amountMinor==0L && it.intensity==0.0})
    }
}
