package vn.com.quyln.mistia.feature.overview

import java.math.BigInteger
import java.time.*
import java.util.UUID
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import vn.com.quyln.mistia.core.model.*

class OverviewMonthlyRawInputsTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other="99999999-9999-9999-9999-999999999999"
    private val time="2026-10-20T12:00:00Z"
    private val reference=Instant.parse(time)
    private val zone=ZoneOffset.UTC
    private val month=YearMonth.of(2026,10)
    private fun row(amount:Long=7,kind:String="expense",date:String=time):CloudRecord {
        val id=UUID.randomUUID().toString()
        return CloudRecord(CloudEntity.LEDGER_TRANSACTION.table,id,owner.value,buildJsonObject {
            put("id",id);put("user_id",owner.value);put("primary_kind_raw_value",kind);put("entry_status_raw_value","posted");put("title","Monthly raw")
            put("amount_minor",amount);put("source_currency_code","JPY");put("is_archived",false);put("occurred_at",date);put("created_at",time);put("updated_at",time)
        },time,null,0)
    }
    private fun CloudRecord.with(key:String,value:JsonElement)=copy(payload=JsonObject(payload+(key to value)))
    private fun project(vararg records:CloudRecord)=overviewRawMonthlyCashflow(owner,records.toList(),emptyList(),"JPY",reference=reference,zone=zone)
    private fun current(vararg records:CloudRecord)=project(*records).single {it.month==month}
    private fun minor(expected:Long,actual:BigInteger?)=assertEquals(BigInteger.valueOf(expected),actual)
    @Test fun `required unreadable posted amount holds whole direction while opposite stays known`() {
        val bad=row().with("amount_minor",JsonPrimitive("broken"))
        val totals=current(row(3),row(5,"income"),bad);assertNull(totals.expenseMinor);minor(5,totals.incomeMinor)
        minor(10,current(row(3),row(7)).expenseMinor)
    }
    @Test fun `numeric strings are unreadable required wire money never confident numbers`() {
        assertNull(current(row().with("amount_minor",JsonPrimitive("7"))).expenseMinor)
        assertNull(current(row().with("reporting_expense_minor",JsonPrimitive("2"))).expenseMinor)
        assertNull(current(row(5,"income").with("reporting_income_minor",JsonPrimitive("4"))).incomeMinor)
    }
    @Test fun `unused created calendar and destination money do not suppress monthly reporting`() {
        for(key in listOf("created_at","destination_amount_minor")) {
            val totals=current(row().with(key,JsonPrimitive("broken")));minor(7,totals.expenseMinor);minor(0,totals.incomeMinor)
        }
    }
    @Test fun `both reporting overrides can be known without an unused original amount`() {
        val original=row().with("amount_minor",JsonPrimitive("broken")).with("reporting_expense_minor",JsonPrimitive(2)).with("reporting_income_minor",JsonPrimitive(4))
        val totals=current(original);minor(2,totals.expenseMinor);minor(4,totals.incomeMinor)
    }
    @Test fun `unknown override in one direction never discards known opposite money`() {
        val incomeUnknown=current(row().with("reporting_income_minor",JsonPrimitive("broken")))
        assertNull(incomeUnknown.incomeMinor);minor(7,incomeUnknown.expenseMinor)
        val expenseUnknown=current(row(5,"income").with("reporting_expense_minor",JsonPrimitive("broken")))
        assertNull(expenseUnknown.expenseMinor);minor(5,expenseUnknown.incomeMinor)
    }
    @Test fun `unplaceable occurred calendar holds affected direction throughout known monthly history`() {
        val old=row(2,date="2026-09-12T00:00:00Z")
        val bad=row().with("occurred_at",JsonPrimitive("broken"))
        val pages=project(old,row(5,"income"),bad);assertEquals(listOf(month.minusMonths(1),month),pages.map {it.month})
        pages.forEach {assertNull(it.expenseMinor)};minor(0,pages.first().incomeMinor);minor(5,pages.last().incomeMinor)
    }
    @Test fun `unknown required eligibility cannot become partial zero cashflow`() {
        for(key in listOf("entry_status_raw_value","is_archived")) {
            val totals=current(row().with(key,JsonPrimitive("broken")),row(5,"income"));assertNull(totals.expenseMinor);minor(5,totals.incomeMinor)
        }
        val kindUnknown=current(row().with("primary_kind_raw_value",JsonPrimitive("futureKind")))
        assertNull(kindUnknown.expenseMinor);assertNull(kindUnknown.incomeMinor)
        assertNull(current(row().with("is_archived",JsonPrimitive("false"))).expenseMinor)
    }
    @Test fun `known excluded and future malformed rows do not poison owned current reports`() {
        val bad=row().with("amount_minor",JsonPrimitive("broken"))
        val excluded=listOf(bad.copy(ownerUserId=other),bad.with("user_id",JsonPrimitive(other)),bad.with("id",JsonPrimitive(UUID.randomUUID().toString())),
            bad.copy(entity=CloudEntity.LEDGER_WALLET.table),bad.copy(deletedAt=time),bad.with("deleted_at",JsonPrimitive(time)),bad.with("is_archived",JsonPrimitive(true)),
            bad.with("entry_status_raw_value",JsonPrimitive("draft")),bad.with("occurred_at",JsonPrimitive("2026-11-01T00:00:00Z")))
        val totals=current(*(excluded+row(3)).toTypedArray());minor(3,totals.expenseMinor);minor(0,totals.incomeMinor)
    }
    @Test fun `unreadable present source currency never becomes an absent legacy code`() {
        val totals=current(row().with("source_currency_code",buildJsonObject {}));assertNull(totals.expenseMinor);minor(0,totals.incomeMinor)
        minor(7,current(row().with("source_currency_code",JsonNull)).expenseMinor)
    }
    @Test fun `unreadable classification fields retain uncertainty instead of neutral enum defaults`() {
        val transfer=row(kind="transfer")
        assertNull(current(transfer.with("transfer_subtype_raw_value",JsonPrimitive("futureSubtype"))).expenseMinor)
        for(key in listOf("title","category_id")) assertNull(current(row().with(key,buildJsonObject {})).expenseMinor)
        val paidFor=transfer.with("transfer_subtype_raw_value",JsonPrimitive("debt")).with("category_id",JsonPrimitive(UUID.randomUUID().toString()))
        assertNull(current(paidFor.with("debt_intent_raw_value",JsonPrimitive("futureIntent"))).expenseMinor)
    }
    @Test fun `known neutral debt and zero effects do not need unused money or FX`() {
        val debt=row(kind="transfer").with("transfer_subtype_raw_value",JsonPrimitive("debt")).with("debt_intent_raw_value",JsonPrimitive("lend"))
            .with("amount_minor",JsonPrimitive("broken")).with("reporting_income_minor",JsonPrimitive("broken"))
        val neutral=current(debt);minor(0,neutral.incomeMinor);minor(0,neutral.expenseMinor)
        val zero=current(row(0).with("source_currency_code",buildJsonObject {}).with("occurred_at",JsonPrimitive("broken")))
        minor(0,zero.incomeMinor);minor(0,zero.expenseMinor)
    }
    @Test fun `an unreadable owned credit kind cannot silently classify a card title as neutral`() {
        val walletId=UUID.randomUUID().toString()
        val wallet=CloudRecord(CloudEntity.LEDGER_WALLET.table,walletId,owner.value,buildJsonObject {
            put("id",walletId);put("user_id",owner.value);put("currency_code","JPY");put("kind_raw_value","futureKind");put("opening_balance_minor",0)
        },time,null,0)
        val record=row(3).with("source_wallet_id",JsonPrimitive(walletId)).with("title",JsonPrimitive("Card payment"))
        assertNull(overviewRawMonthlyCashflow(owner,listOf(record),listOf(wallet),"JPY",reference=reference,zone=zone).single().expenseMinor)
    }
    @Test fun `unknown only past month creates history and undated income holds only income`() {
        val old=row(date="2026-09-12T00:00:00Z").with("amount_minor",JsonPrimitive("broken"))
        val pages=project(old,row(5,"income"));assertEquals(listOf(month.minusMonths(1),month),pages.map {it.month})
        assertNull(pages.first().expenseMinor);minor(0,pages.last().expenseMinor);minor(5,pages.last().incomeMinor)
        val undated=row(7,"income").with("occurred_at",JsonPrimitive("broken"))
        val unknown=project(row(2,date="2026-09-12T00:00:00Z"),undated)
        unknown.forEach {assertNull(it.incomeMinor)};minor(2,unknown.first().expenseMinor);minor(0,unknown.last().expenseMinor)
    }
    @Test fun `exact raw money retains overflow cancellation FX recovery and imported identity`() {
        val records=listOf(row(Long.MAX_VALUE,"income"),row(Long.MAX_VALUE,"income"),row(165).with("source_currency_code",JsonPrimitive("VND")))
        val missing=current(*records.toTypedArray());assertEquals(BigInteger.valueOf(Long.MAX_VALUE)*BigInteger.TWO,missing.incomeMinor);assertNull(missing.expenseMinor)
        val recovered=overviewRawMonthlyCashflow(owner,records,emptyList(),"JPY",listOf(ExchangeRateSnapshot("JPY","VND","165","test",0,null)),reference=reference,zone=zone).single()
        minor(1,recovered.expenseMinor);assertEquals(missing.incomeMinor,recovered.incomeMinor)
        minor(-1,current(row(Long.MAX_VALUE),row(Long.MIN_VALUE)).expenseMinor)
        val imported=overviewRawMonthlyCashflow(owner,listOf(row(1375).with("source_currency_code",JsonPrimitive("USD"))),emptyList(),"USD",reference=reference,zone=zone).single()
        minor(1375,imported.expenseMinor)
    }
    @Test fun `source currency metadata is independent of unused opening and unneeded wallet kind`() {
        val id=UUID.randomUUID().toString()
        val wallet=CloudRecord(CloudEntity.LEDGER_WALLET.table,id,owner.value,buildJsonObject {
            put("id",id);put("user_id",owner.value);put("currency_code","VND");put("kind_raw_value","futureKind");put("opening_balance_minor","broken")
        },time,null,0)
        val record=row(165).with("source_wallet_id",JsonPrimitive(id)).with("source_currency_code",JsonNull)
        fun totals(wallet:CloudRecord,record:CloudRecord)=overviewRawMonthlyCashflow(owner,listOf(record),listOf(wallet),"JPY",listOf(ExchangeRateSnapshot("JPY","VND","165","test",0,null)),reference=reference,zone=zone).single()
        minor(1,totals(wallet,record).expenseMinor)
        assertNull(totals(wallet.with("deleted_at",JsonPrimitive(false)),record).expenseMinor)
        minor(165,totals(wallet.with("deleted_at",JsonPrimitive(false)),record.with("source_currency_code",JsonPrimitive("JPY"))).expenseMinor)
    }
    @Test fun `shared resale paid for installment adjustment and legacy debt keep reporting semantics`() {
        fun debt(intent:String,role:String?=null)=row(kind="transfer").with("transfer_subtype_raw_value",JsonPrimitive("debt"))
            .with("debt_intent_raw_value",JsonPrimitive(intent)).let {if(role==null) it else it.with("settlement_role_raw_value",JsonPrimitive(role))}
        val resale=debt("lend","resaleReceivable").with("amount_minor",JsonPrimitive("broken")).with("reporting_expense_minor",JsonPrimitive(3))
        val receipt=debt("collect","resaleReceipt").with("reporting_income_minor",JsonPrimitive(11))
        val shared=debt("lend","sharedExpenseReceivable").with("reporting_expense_minor",JsonPrimitive(2))
        val paidFor=debt("borrow").with("category_id",JsonPrimitive(UUID.randomUUID().toString()))
        val excluded=listOf(row().with("category_id",JsonPrimitive(SystemCategoryIdentity.canonicalId("loan_repayment"))),
            row().with("category_id",JsonPrimitive(TransactionCategoryRecord.BALANCE_ADJUSTMENT_EXPENSE_ID)),
            row(kind="income").with("category_id",JsonPrimitive(SystemCategoryIdentity.canonicalId("people_repayment"))),row().with("title",JsonPrimitive("Card payment")))
        val totals=current(*(listOf(resale,receipt,shared,paidFor)+excluded).toTypedArray());minor(12,totals.expenseMinor);minor(11,totals.incomeMinor)
    }
}
