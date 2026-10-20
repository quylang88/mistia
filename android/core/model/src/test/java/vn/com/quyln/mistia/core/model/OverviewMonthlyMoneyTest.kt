package vn.com.quyln.mistia.core.model

import java.math.BigInteger
import java.time.*
import java.util.UUID
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class OverviewMonthlyMoneyTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other="99999999-9999-9999-9999-999999999999"
    private val now=Instant.parse("2026-10-20T00:00:00Z")
    private val zone=ZoneId.of("Asia/Tokyo")
    private val month=YearMonth.of(2026,10)
    private val rate=ExchangeRateSnapshot("JPY","VND","2.5","test",0,null)
    private fun row(kind:String="expense",amount:Long=100,code:String?="JPY")=LedgerTransactionRecord.fromCloudRecord(
        CloudRecord(CloudEntity.LEDGER_TRANSACTION.table,UUID.randomUUID().toString(),owner.value,buildJsonObject {
            put("primary_kind_raw_value",kind);put("entry_status_raw_value","posted");put("title","Ordinary")
            put("amount_minor",amount);code?.let {put("source_currency_code",it)};put("occurred_at",now.toString())
            put("created_at",now.toString());put("updated_at",now.toString());put("is_archived",false)
        },null,null,0))
    private fun wallet()=LedgerWalletRecord.fromCloudRecord(CloudRecord(CloudEntity.LEDGER_WALLET.table,UUID.randomUUID().toString(),owner.value,
        buildJsonObject {put("name","Owned VND");put("kind_raw_value","cash");put("currency_code","VND");put("created_at",now.toString());put("updated_at",now.toString())},null,null,0))
    private fun pages(rows:List<LedgerTransactionRecord>,currency:String="JPY",rates:List<ExchangeRateSnapshot> = emptyList(),wallets:List<LedgerWalletRecord> = emptyList())=
        overviewMonthlyCashflow(owner,rows,wallets,currency,rates,reference=now,zone=zone)
    private fun n(value:Long)=BigInteger.valueOf(value)
    // Decimal golden values prove numeric behavior independently of the model's API type.
    private fun minor(expected:BigInteger,actual:Any?)=assertEquals(expected.toString(),actual?.toString())
    @Test fun `income and expense sums retain values above and below signed Long bounds`() {
        val before=listOf(row(amount=Long.MAX_VALUE),row(amount=Long.MAX_VALUE),row("income",Long.MAX_VALUE),row("income",Long.MAX_VALUE))
        val page=pages(before).single();minor(n(Long.MAX_VALUE)*BigInteger.TWO,page.expenseMinor);minor(n(Long.MAX_VALUE)*BigInteger.TWO,page.incomeMinor)
        val negative=pages(listOf(row().copy(reportingExpenseMinor=Long.MIN_VALUE),row().copy(reportingExpenseMinor=Long.MIN_VALUE))).single()
        minor(n(Long.MIN_VALUE)*BigInteger.TWO,negative.expenseMinor);assertEquals(4,before.size)
    }
    @Test fun `per record FX retains conversion overflow signed cancellation and half up rounding`() {
        val doubled=rate.copy(rateDecimalString="2")
        minor(n(Long.MAX_VALUE)*BigInteger.TWO,pages(listOf(row(amount=Long.MAX_VALUE)),"VND",listOf(doubled)).single().expenseMinor)
        val signed=listOf(Long.MAX_VALUE,-Long.MAX_VALUE,3L).map {row().copy(reportingExpenseMinor=it)}
        for(order in listOf(signed,signed.reversed())) minor(n(6),pages(order,"VND",listOf(doubled)).single().expenseMinor)
        val originals=listOf(row(amount=3),row(amount=3)).map {it.copy(reportingCurrencyCode="VND",reportingAmountMinor=999)}
        minor(n(16),pages(originals,"VND",listOf(rate)).single().expenseMinor)
        minor(n(-8),pages(listOf(row().copy(reportingExpenseMinor=-3)),"VND",listOf(rate)).single().expenseMinor)
    }
    @Test fun `missing expense conversion holds complete expense independently of available income`() {
        val rows=listOf(row(amount=3),row(amount=500,code="VND"),row("income",70,"VND"))
        val unavailable=pages(rows,"VND").single();assertNull(unavailable.expenseMinor);minor(n(70),unavailable.incomeMinor)
        val recovered=pages(rows,"VND",listOf(rate)).single();minor(n(508),recovered.expenseMinor);minor(n(70),recovered.incomeMinor)
        assertNull(pages(rows.reversed(),"VND").single().expenseMinor)
    }
    @Test fun `missing income conversion preserves available expense and does not become zero`() {
        val page=pages(listOf(row("income",3),row("income",500,"VND"),row(amount=90,code="VND")),"VND").single()
        assertNull(page.incomeMinor);minor(n(90),page.expenseMinor)
    }
    @Test fun `invalid or unrelated rates never provide a numeric partial total`() {
        for(text in listOf("broken","0","-1")) assertNull(pages(listOf(row()),"VND",listOf(rate.copy(rateDecimalString=text))).single().expenseMinor)
        assertNull(pages(listOf(row()),"VND",listOf(rate.copy(baseCurrencyCode="USD"))).single().expenseMinor)
        val zero=pages(listOf(row(amount=0)),"VND").single();minor(BigInteger.ZERO,zero.expenseMinor);minor(BigInteger.ZERO,zero.incomeMinor)
    }
    @Test fun `same ISO imported cents remain exact while unsupported or malformed cross currency is held`() {
        minor(n(1375),pages(listOf(row("income",1375," usd ")),"USD").single().incomeMinor)
        for(code in listOf("USD","??","US","JPY!")) assertNull(pages(listOf(row(code=code))).single().expenseMinor)
        assertNull(pages(listOf(row()),"USD",listOf(rate)).single().expenseMinor)
    }
    @Test fun `missing source uses owned live wallet currency and explicit source has priority`() {
        val wallet=wallet();val record=row(amount=50,code=null).copy(sourceWalletId=wallet.id)
        minor(n(50),pages(listOf(record),"VND",wallets=listOf(wallet)).single().expenseMinor)
        minor(n(50),pages(listOf(record.copy(sourceCurrencyCode=" ")),"VND",wallets=listOf(wallet)).single().expenseMinor)
        for(bad in listOf(wallet.copy(ownerUserId=other),wallet.copy(deletedAt=now.toString())))
            assertNull(pages(listOf(record),"VND",wallets=listOf(bad)).single().expenseMinor)
        assertNull(pages(listOf(record.copy(sourceCurrencyCode="JPY")),"VND",wallets=listOf(wallet)).single().expenseMinor)
        minor(n(50),pages(listOf(record.copy(sourceWalletId=null))).single().expenseMinor)
    }
    @Test fun `ineligible and zero original rows never poison available owned totals`() {
        val unknown=row(code="USD")
        val excluded=listOf(unknown.copy(ownerUserId=other),unknown.copy(isArchived=true),unknown.copy(deletedAt=now.toString()),
            unknown.copy(entryStatusWireValue="draft"),unknown.copy(entryStatusWireValue="unknown"),unknown.copy(primaryKindWireValue="unknown"),
            unknown.copy(occurredAt="broken"),unknown.copy(occurredAt="2026-11-01T00:00:00Z"),unknown.copy(amountMinor=0),
            unknown.copy(reportingExpenseMinor=0,reportingIncomeMinor=0),unknown.copy(categoryId=TransactionCategoryRecord.BALANCE_ADJUSTMENT_EXPENSE_ID))
        val page=pages(excluded+row(amount=100,code="VND")+row("income",70,"VND"),"VND").single()
        minor(n(100),page.expenseMinor);minor(n(70),page.incomeMinor)
    }
    @Test fun `historical unavailable month and empty gaps retain independent totals with current future days`() {
        val old=row(amount=3).copy(occurredAt="2026-08-15T00:00:00Z")
        val income=row("income",100,"VND").copy(occurredAt=old.occurredAt)
        val futureDay=row(amount=900,code="VND").copy(occurredAt="2026-10-31T00:00:00Z")
        val futureMonth=row(amount=999,code="VND").copy(occurredAt="2026-11-01T00:00:00Z")
        val result=pages(listOf(old,income,futureDay,futureMonth),"VND")
        assertEquals((8..10).map {YearMonth.of(2026,it)},result.map {it.month})
        assertNull(result.first().expenseMinor);minor(n(100),result.first().incomeMinor)
        minor(BigInteger.ZERO,result[1].expenseMinor);minor(BigInteger.ZERO,result[1].incomeMinor)
        assertEquals(month,result.last().month);minor(n(900),result.last().expenseMinor)
    }
}
