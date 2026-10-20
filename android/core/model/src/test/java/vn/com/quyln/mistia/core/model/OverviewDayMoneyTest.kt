package vn.com.quyln.mistia.core.model

import java.math.BigInteger
import java.time.*
import java.util.UUID
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class OverviewDayMoneyTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other="99999999-9999-9999-9999-999999999999"
    private val zone=ZoneId.of("Asia/Tokyo")
    private val now=Instant.parse("2026-04-09T03:00:00Z")
    private val day=LocalDate.of(2026,4,6)
    private val time="2026-04-06T00:00:00Z"
    private val rate=ExchangeRateSnapshot("JPY","VND","2.5","test",0,null)
    private fun row(amount:Long=100,code:String?="JPY",date:LocalDate=day)=LedgerTransactionRecord.fromCloudRecord(
        CloudRecord(CloudEntity.LEDGER_TRANSACTION.table,UUID.randomUUID().toString(),owner.value,buildJsonObject {
            put("primary_kind_raw_value","expense");put("entry_status_raw_value","posted");put("title","Day money");put("amount_minor",amount)
            code?.let {put("source_currency_code",it)};put("occurred_at",date.atStartOfDay(zone).plusHours(12).toInstant().toString());put("created_at",time);put("updated_at",time)
        },null,null,0))
    private fun wallet()=LedgerWalletRecord.fromCloudRecord(CloudRecord(CloudEntity.LEDGER_WALLET.table,UUID.randomUUID().toString(),owner.value,
        buildJsonObject {put("name","Owned VND");put("kind_raw_value","cash");put("currency_code","VND");put("created_at",time);put("updated_at",time)},null,null,0))
    private fun weeks(rows:List<LedgerTransactionRecord>,currency:String?="JPY",rates:List<ExchangeRateSnapshot> = emptyList(),wallets:List<LedgerWalletRecord> = emptyList())=
        overviewWeeklySpending(owner,rows,wallets,currency,rates,reference=now,zone=zone)
    private fun details(rows:List<LedgerTransactionRecord>,currency:String="JPY",rates:List<ExchangeRateSnapshot> = emptyList(),wallets:List<LedgerWalletRecord> = emptyList(),date:LocalDate=day)=
        overviewExpenseDay(owner,rows,wallets,date,currency,rates,zone=zone)
    private fun point(rows:List<LedgerTransactionRecord>,currency:String?="JPY",rates:List<ExchangeRateSnapshot> = emptyList(),wallets:List<LedgerWalletRecord> = emptyList())=weeks(rows,currency,rates,wallets).last().points.first().amountMinor
    private fun n(value:Long)=BigInteger.valueOf(value)
    private fun minor(expected:BigInteger,actual:Any?)=assertEquals(expected.toString(),actual?.toString())
    @Test fun `weekly bars and original day totals retain positive and negative values beyond Long`() {
        for(value in listOf(Long.MAX_VALUE,Long.MIN_VALUE)) {
            val rows=listOf(row(value),row(value));val expected=n(value)*BigInteger.TWO
            minor(expected,point(rows));minor(expected,details(rows).totalMinor)
            val week=weeks(rows).single();minor(expected,week.totalMinor);assertFalse(week.hasUnavailableConversion)
        }
    }
    @Test fun `converted overflow cancels exactly and rounds each original before both daily sums`() {
        val doubled=rate.copy(rateDecimalString="2")
        minor(n(Long.MAX_VALUE)*BigInteger.TWO,point(listOf(row(Long.MAX_VALUE)),"VND",listOf(doubled)))
        minor(n(Long.MAX_VALUE)*BigInteger.TWO,details(listOf(row(Long.MAX_VALUE)),"VND",listOf(doubled)).totalMinor)
        val signed=listOf(Long.MAX_VALUE,-Long.MAX_VALUE,3L).map {row(it)}
        for(order in listOf(signed,signed.reversed())) {minor(n(6),point(order,"VND",listOf(doubled)));minor(n(6),details(order,"VND",listOf(doubled)).totalMinor)}
        val rounded=listOf(row(3),row(3)).map {it.copy(reportingCurrencyCode="VND",reportingAmountMinor=999)}
        minor(n(16),point(rounded,"VND",listOf(rate)));minor(n(16),details(rounded,"VND",listOf(rate)).totalMinor)
    }
    @Test fun `one missing conversion holds the affected day instead of retaining a partial numeric sum`() {
        val monday=listOf(row(3),row(500,"VND"));val tuesday=row(70,"VND",day.plusDays(1));val rows=monday+tuesday
        val week=weeks(rows,"VND").single();assertTrue(week.hasUnavailableConversion);assertNull(week.totalMinor);assertNull(week.points[0].amountMinor);minor(n(70),week.points[1].amountMinor)
        assertNull(details(rows,"VND").totalMinor);assertEquals(2,details(rows,"VND").rows.size)
        val repaired=weeks(rows,"VND",listOf(rate)).single();minor(n(508),repaired.points[0].amountMinor);minor(n(70),repaired.points[1].amountMinor)
        minor(n(508),details(rows,"VND",listOf(rate)).totalMinor)
        assertNull(point(monday.reversed(),"VND"))
    }
    @Test fun `imported original cents stay visible while unsupported cross conversion is unavailable`() {
        val imported=row(1375," usd ")
        minor(n(1375),point(listOf(imported),"USD"));minor(n(1375),details(listOf(imported),"USD").totalMinor)
        assertNull(point(listOf(imported)));val result=details(listOf(imported));assertNull(result.totalMinor);assertEquals(Money(1375,"USD"),result.rows.single().money)
        for(text in listOf("broken","0","-1")) assertNull(point(listOf(row()),"VND",listOf(rate.copy(rateDecimalString=text))))
    }
    @Test fun `owned source wallet currency is used without borrowing foreign or deleted metadata`() {
        val wallet=wallet();val record=row(50,code=null).copy(sourceWalletId=wallet.id)
        minor(n(50),point(listOf(record),"VND",wallets=listOf(wallet)));minor(n(50),details(listOf(record),"VND",wallets=listOf(wallet)).totalMinor)
        for(bad in listOf(wallet.copy(ownerUserId=other),wallet.copy(deletedAt=time))) {
            assertNull(point(listOf(record),"VND",wallets=listOf(bad)))
            val result=details(listOf(record),"VND",wallets=listOf(bad));assertEquals(Money(50,"JPY"),result.rows.single().money);assertNull(result.totalMinor)
        }
        assertNull(point(listOf(record.copy(sourceCurrencyCode="JPY")),"VND",wallets=listOf(wallet)))
    }
    @Test fun `legacy missing source is JPY consistently and absent reporting target never sums raw mixed units`() {
        val legacy=row(100,code=null)
        val result=details(listOf(legacy),"VND",listOf(rate));assertEquals(Money(100,"JPY"),result.rows.single().money);minor(n(250),result.totalMinor)
        val mixed=listOf(row(100),row(100,"VND"));assertNull(point(mixed,currency=null))
        minor(n(140),point(mixed,currency=null,rates=listOf(rate)))
    }
    @Test fun `malformed original currency retains a countable unknown row and never a partial day total`() {
        val malformed=row(1375,"??");val valid=row(100)
        val result=details(listOf(malformed,valid));assertEquals(listOf(malformed.id,valid.id),result.rows.map {it.transaction.id})
        assertNull(result.rows.first().money);assertEquals(Money(100,"JPY"),result.rows.last().money);assertNull(result.totalMinor)
        assertNull(point(listOf(malformed,valid)))
    }
    @Test fun `unknown original zero remains countable but needs no FX for a zero total`() {
        val unknown=row(0,"??");val result=details(listOf(unknown),"VND")
        assertEquals(1,result.rows.size);assertNull(result.rows.single().money);minor(BigInteger.ZERO,result.totalMinor)
        assertTrue(weeks(listOf(unknown),"VND").single().points.all {it.amountMinor.toString()=="0"})
    }
    @Test fun `unavailable history gaps and current future days respect Monday calendar and future weeks`() {
        val old=row(3,date=day.minusWeeks(2));val pages=weeks(listOf(old),"VND")
        assertEquals(listOf(day.minusWeeks(2),day.minusWeeks(1),day),pages.map {it.start});assertNull(pages.first().points.first().amountMinor)
        assertTrue(pages.drop(1).flatMap {it.points}.all {it.amountMinor.toString()=="0"})
        val sunday=day.plusDays(6);val futureCurrent=listOf(row(Long.MAX_VALUE,date=sunday),row(Long.MAX_VALUE,date=sunday))
        minor(n(Long.MAX_VALUE)*BigInteger.TWO,weeks(futureCurrent).single().points.last().amountMinor)
        minor(n(Long.MAX_VALUE)*BigInteger.TWO,details(futureCurrent,date=sunday).totalMinor)
        assertTrue(weeks(listOf(row(100,"USD",day.plusWeeks(1)))).single().points.all {it.amountMinor.toString()=="0"})
    }
    @Test fun `owner status and neutral invalid dated rows do not poison eligible zero spending`() {
        val bad=row(100,"USD")
        val excluded=listOf(bad.copy(ownerUserId=other),bad.copy(isArchived=true),bad.copy(deletedAt=time),bad.copy(entryStatusWireValue="draft"),
            bad.copy(entryStatusWireValue="unknown"),bad.copy(primaryKindWireValue="unknown"),bad.copy(occurredAt="broken"),bad.copy(primaryKindWireValue="income"))
        val zero=row(0);minor(BigInteger.ZERO,point(excluded+zero));minor(BigInteger.ZERO,details(excluded+zero).totalMinor)
        assertEquals(listOf(zero.id),details(excluded+zero).rows.map {it.transaction.id})
    }
}
