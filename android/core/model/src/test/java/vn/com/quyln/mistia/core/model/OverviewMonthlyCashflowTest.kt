package vn.com.quyln.mistia.core.model

import java.time.*
import java.math.BigInteger
import java.util.UUID
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class OverviewMonthlyCashflowTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other="99999999-9999-9999-9999-999999999999"
    private val now=Instant.parse("2026-10-16T00:00:00Z")
    private val zone=ZoneId.of("Asia/Tokyo")
    private val october=YearMonth.of(2026,10)
    private val titles=mapOf(GeneratedTransactionTitle.BALANCE_ADJUSTMENT to listOf("Điều chỉnh số dư","Balance adjustment","残高調整"),
        GeneratedTransactionTitle.COLLECT to listOf("Thu nợ","Collect debt","貸したお金の回収"),GeneratedTransactionTitle.BORROW to listOf("Đi vay","Borrow","借入"))
    private fun record(kind:String="expense",amount:Long=100)=LedgerTransactionRecord.fromCloudRecord(CloudRecord(CloudEntity.LEDGER_TRANSACTION.table,
        UUID.randomUUID().toString(),owner.value,buildJsonObject {put("primary_kind_raw_value",kind);put("entry_status_raw_value","posted");put("title","Ordinary")
            put("amount_minor",amount);put("source_currency_code","JPY");put("occurred_at",now.toString());put("created_at",now.toString());put("updated_at",now.toString());put("is_archived",false)},null,null,0))
    private fun wallet(kind:WalletKind=WalletKind.CASH)=LedgerWalletRecord.fromCloudRecord(CloudRecord(CloudEntity.LEDGER_WALLET.table,UUID.randomUUID().toString(),owner.value,
        buildJsonObject {put("name","Cash");put("kind_raw_value",kind.wireValue);put("currency_code","JPY");put("created_at",now.toString());put("updated_at",now.toString())},null,null,0))
    private fun project(records:List<LedgerTransactionRecord>,wallets:List<LedgerWalletRecord> = emptyList(),currency:String="JPY",rates:List<ExchangeRateSnapshot> = emptyList(),tz:ZoneId=zone)=
        overviewMonthlyCashflow(owner,records,wallets,currency,rates,titles,now,tz)
    private fun money(expected:Long,actual:BigInteger?)=assertEquals(BigInteger.valueOf(expected),actual)
    @Test fun `all owned active posted records contribute exact money rather than only five recent rows`() {
        val rows=(1..7).map {record(amount=9007199254740993L)}
        val hidden=listOf(record().copy(ownerUserId=other),record().copy(isArchived=true),record().copy(deletedAt=now.toString()),
            record().copy(entryStatusWireValue="draft"),record().copy(entryStatusWireValue="unknown"),record().copy(occurredAt="broken"))
        val before=rows.toList()
        money(63050394783186951L,project(rows+hidden).last().expenseMinor);assertEquals(before,rows)
    }
    @Test fun `calendar months include gaps current empty month and exclude future month`() {
        val rows=listOf(record().copy(occurredAt="2026-07-31T14:59:59Z"),record().copy(occurredAt="2026-09-30T15:00:00Z"),record().copy(occurredAt="2026-10-31T15:00:00Z"))
        val result=project(rows)
        assertEquals((7..10).map {YearMonth.of(2026,it)},result.map {it.month});assertEquals(listOf(100L,0L,0L,100L).map(BigInteger::valueOf),result.map {it.expenseMinor})
        assertEquals(YearMonth.of(2026,9),project(listOf(rows[1]),tz=ZoneId.of("Asia/Ho_Chi_Minh")).first().month)
    }
    @Test fun `adjustments installments and cash card payments are excluded while card purchase is expense`() {
        val cash=wallet();val card=wallet(WalletKind.CREDIT_CARD)
        val excluded=listOf(record().copy(categoryId=TransactionCategoryRecord.BALANCE_ADJUSTMENT_EXPENSE_ID),record().copy(categoryId=SystemCategoryIdentity.canonicalId("loan_repayment")))+
            titles.getValue(GeneratedTransactionTitle.BALANCE_ADJUSTMENT).map {record().copy(title=" $it ")}+
            listOf("Card payment","THANH TOÁN THẺ","thanh toan the","カード支払い").map {record().copy(title=it,sourceWalletId=cash.id)}
        money(100L,project(excluded+record().copy(title="Card payment",sourceWalletId=card.id),listOf(cash,card)).last().expenseMinor)
    }
    @Test fun `paid for debt has expense only with category and signed overrides take precedence`() {
        val paid=record("transfer").copy(transferSubtypeWireValue="debt",debtIntentWireValue="borrow",categoryId=UUID.randomUUID().toString(),sourceWalletId=null)
        money(100L,project(listOf(paid,paid.copy(categoryId=null),paid.copy(categoryId=SystemCategoryIdentity.canonicalId("loan_repayment")))) .last().expenseMinor)
        val override=record().copy(reportingExpenseMinor=-25,reportingIncomeMinor=7)
        val zero=record().copy(reportingExpenseMinor=0)
        val sum=project(listOf(override,zero)).last();money(-25L,sum.expenseMinor);money(7L,sum.incomeMinor)
    }
    @Test fun `debt and legacy generated incomes are excluded except resale receipt override`() {
        val debt=record("income").copy(debtIntentWireValue="collect",reportingIncomeMinor=1000)
        val legacy=titles.getValue(GeneratedTransactionTitle.COLLECT).map {record("income").copy(title=it)}+
            titles.getValue(GeneratedTransactionTitle.BORROW).map {record("income").copy(title=it)}+
            record("income").copy(categoryId=SystemCategoryIdentity.canonicalId("people_repayment"))
        val result=project(legacy+debt+debt.copy(settlementRoleWireValue="resaleReceipt",reportingIncomeMinor=75)+record("income",25)).last()
        money(100L,result.incomeMinor)
    }
    @Test fun `matching owned live wallet kind alone controls credit card payment title classification`() {
        val card=wallet(WalletKind.CREDIT_CARD);val row=record().copy(title="Card payment",sourceWalletId=card.id)
        money(100L,project(listOf(row),listOf(card)).last().expenseMinor)
        for(bad in listOf(card.copy(ownerUserId=other),card.copy(deletedAt=now.toString()))) money(0L,project(listOf(row),listOf(bad)).last().expenseMinor)
    }
    @Test fun `reporting conversion uses current source rates with signed rounding ignores snapshot and unavailable for missing rate`() {
        val row=record(amount=3).copy(reportingCurrencyCode="VND",reportingAmountMinor=999)
        assertNull(project(listOf(row),currency="VND").last().expenseMinor)
        val rate=ExchangeRateSnapshot("JPY","VND","2.5","test",0,null)
        money(8L,project(listOf(row),currency="VND",rates=listOf(rate)).last().expenseMinor)
        money(-8L,project(listOf(row.copy(reportingExpenseMinor=-3)),currency="VND",rates=listOf(rate)).last().expenseMinor)
        money(1L,project(listOf(row.copy(sourceCurrencyCode="VND")),rates=listOf(rate)).last().expenseMinor)
    }
    @Test fun `sum stays exact after positive and negative cancellation without a final clamp`() {
        val values=listOf(Long.MAX_VALUE,Long.MAX_VALUE,-Long.MAX_VALUE)
        for(order in listOf(values,values.reversed())) money(Long.MAX_VALUE,project(order.map {record().copy(reportingExpenseMinor=it)}).last().expenseMinor)
        assertEquals(BigInteger.valueOf(Long.MAX_VALUE)+BigInteger.valueOf(100),project(listOf(record(amount=Long.MAX_VALUE),record())).last().expenseMinor)
    }
    @Test fun `conversion overflow cancels exactly before final boundary and invalid rates hold conversion`() {
        val rate=ExchangeRateSnapshot("JPY","VND","2","test",0,null)
        val rows=listOf(Long.MAX_VALUE,-Long.MAX_VALUE,3).map {record().copy(reportingExpenseMinor=it)}
        for(order in listOf(rows,rows.reversed())) money(6L,project(order,currency="VND",rates=listOf(rate)).last().expenseMinor)
        for(value in listOf("broken","0","-1")) assertNull(project(listOf(record()),currency="VND",rates=listOf(rate.copy(rateDecimalString=value))).last().expenseMinor)
    }
    @Test fun `empty zero neutral future or invalid rows still yield current zero page`() {
        val neutral=record("transfer").copy(transferSubtypeWireValue="internalTransfer")
        assertEquals(listOf(OverviewMonthlyCashflow(october,0,0)),project(listOf(neutral,record(amount=0),record().copy(occurredAt="2027-01-01T00:00:00Z"))))
        assertEquals(listOf(OverviewMonthlyCashflow(october,0,0)),project(emptyList()))
    }
}
