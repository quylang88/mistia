package vn.com.quyln.mistia.core.model

import java.time.*
import java.util.UUID
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class OverviewExpenseDayTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other="99999999-9999-9999-9999-999999999999"
    private val zone=ZoneId.of("Asia/Tokyo")
    private val day=LocalDate.of(2026,4,6)
    private val time="2026-04-06T00:00:00Z"
    private val titles=mapOf(GeneratedTransactionTitle.BALANCE_ADJUSTMENT to listOf("Balance adjustment","Điều chỉnh số dư","残高調整"))
    private fun row(amount:Long=100,kind:String="expense")=LedgerTransactionRecord.fromCloudRecord(CloudRecord(CloudEntity.LEDGER_TRANSACTION.table,UUID.randomUUID().toString(),owner.value,
        buildJsonObject {put("primary_kind_raw_value",kind);put("entry_status_raw_value","posted");put("amount_minor",amount);put("source_currency_code","JPY");put("title","Expense");put("occurred_at",time);put("created_at",time)},null,null,0))
    private fun wallet(code:String="VND",subject:String=owner.value)=LedgerWalletRecord.fromCloudRecord(CloudRecord(CloudEntity.LEDGER_WALLET.table,UUID.randomUUID().toString(),subject,
        buildJsonObject {put("name","Wallet");put("kind_raw_value","cash");put("currency_code",code);put("opening_balance_minor",0);put("created_at",time);put("updated_at",time)},time,null,0))
    private fun project(rows:List<LedgerTransactionRecord>,currency:String="JPY",rates:List<ExchangeRateSnapshot> = emptyList(),wallets:List<LedgerWalletRecord> = emptyList(),tz:ZoneId=zone)=
        overviewExpenseDay(owner,rows,wallets,day,currency,rates,titles,tz)
    @Test fun `only owned active posted spending with valid occurred and created dates contributes`() {
        val good=row(9007199254740993L)
        val invalid=listOf(good.copy(ownerUserId=other),good.copy(deletedAt="deleted"),good.copy(isArchived=true),good.copy(entryStatusWireValue="draft"),good.copy(entryStatusWireValue="unknown"),
            good.copy(primaryKindWireValue="unknown"),good.copy(occurredAt="broken"),good.copy(createdAt="broken"),good.copy(occurredAt="2026-04-07T00:00:00Z"))
        val result=project(invalid+good);assertEquals(listOf(good.id),result.rows.map {it.transaction.id});assertEquals(good.amountMinor,result.totalMinor)
    }
    @Test fun `day filter precedes unlimited recency sort with local midnight and created tie break`() {
        val records=(0L..6).map {row().copy(occurredAt=Instant.parse(time).plusSeconds(it).toString())}
        val late=records.last().copy(id=UUID.randomUUID().toString(),createdAt="2026-04-06T01:00:00Z")
        val result=project(records+late)
        assertEquals(8,result.rows.size);assertEquals(late.id,result.rows.first().transaction.id);assertEquals(records.last().id,result.rows[1].transaction.id)
        val boundary=row().copy(occurredAt="2026-04-05T15:00:00Z")
        assertEquals(1,project(listOf(boundary)).rows.size);assertTrue(project(listOf(boundary),tz=ZoneId.of("Asia/Ho_Chi_Minh")).rows.isEmpty())
    }
    @Test fun `spending classification retains zero signed and paid for without treating every reporting override as spending`() {
        val paid=row(20,"transfer").copy(transferSubtypeWireValue="debt",debtIntentWireValue="borrow",categoryId=UUID.randomUUID().toString())
        val kept=listOf(row(0),row(-3),paid,row(500).copy(reportingExpenseMinor=0))
        val excluded=listOf(row().copy(title="Balance adjustment"),row().copy(title="Card payment"),row().copy(categoryId=SystemCategoryIdentity.canonicalId("loan_repayment")),row(7,"income").copy(reportingExpenseMinor=7))
        val result=project(kept+excluded);assertEquals(kept.map {it.id},result.rows.map {it.transaction.id});assertEquals(517L,result.totalMinor)
    }
    @Test fun `original currency uses owned source metadata then primary and rejects malformed explicit code`() {
        val owned=wallet();val foreign=wallet("USD",other)
        val a=row(7).copy(sourceCurrencyCode=null,sourceWalletId=owned.id)
        val b=row(9).copy(sourceCurrencyCode=null,sourceWalletId=foreign.id)
        val bad=row().copy(sourceCurrencyCode="??")
        val result=project(listOf(a,b,bad),wallets=listOf(owned,foreign))
        assertEquals(mapOf(a.id to Money(7,"VND"),b.id to Money(9,"JPY")),result.rows.associate {it.transaction.id to it.money});assertNull(result.totalMinor)
    }
    @Test fun `current FX rounds originals per record and ignores reporting pair with inverse conversion`() {
        val rate=ExchangeRateSnapshot("JPY","VND","2.5","test",0,null)
        val a=row(3).copy(reportingCurrencyCode="VND",reportingAmountMinor=999)
        val result=project(listOf(a,a.copy(id=UUID.randomUUID().toString())),"VND",listOf(rate))
        assertEquals(16L,result.totalMinor);assertTrue(result.rows.all {it.money==Money(3,"JPY")})
        assertEquals(1L,project(listOf(a.copy(sourceCurrencyCode="VND")),"JPY",listOf(rate)).totalMinor)
    }
    @Test fun `missing or unsupported FX never produces a partial or relabeled total while source rows survive`() {
        val a=row(3);val b=row(10).copy(sourceCurrencyCode="VND")
        assertNull(project(listOf(a,b),"VND").totalMinor)
        val bad=ExchangeRateSnapshot("JPY","VND","0","test",0,null)
        assertNull(project(listOf(a),"VND",listOf(bad)).totalMinor)
        val imported=row(1375).copy(sourceCurrencyCode=" usd ")
        val result=project(listOf(imported));assertEquals(Money(1375,"USD"),result.rows.single().money);assertNull(result.totalMinor)
        assertEquals(1375L,project(listOf(imported),"USD").totalMinor)
    }
    @Test fun `exact original and converted sums retain signed overflow cancellation before final clamp`() {
        val original=listOf(Long.MAX_VALUE,Long.MAX_VALUE,-Long.MAX_VALUE).map {row(it)}
        for(order in listOf(original,original.reversed())) assertEquals(Long.MAX_VALUE,project(order).totalMinor)
        val converted=listOf(Long.MAX_VALUE,-Long.MAX_VALUE,3).map {row(it)}
        assertEquals(6L,project(converted,"VND",listOf(ExchangeRateSnapshot("JPY","VND","2","test",0,null))).totalMinor)
    }
    @Test fun `empty day has defined zero total in selected currency`() {
        val result=project(emptyList(),"VND");assertEquals(day,result.day);assertEquals("VND",result.currencyCode);assertTrue(result.rows.isEmpty());assertEquals(0L,result.totalMinor)
    }
}
