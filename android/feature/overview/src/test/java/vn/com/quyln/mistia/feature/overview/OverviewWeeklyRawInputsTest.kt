package vn.com.quyln.mistia.feature.overview

import java.math.BigInteger
import java.time.*
import java.util.UUID
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import vn.com.quyln.mistia.core.model.*

class OverviewWeeklyRawInputsTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other="99999999-9999-9999-9999-999999999999"
    private val time="2026-10-20T12:00:00Z"
    private val reference=Instant.parse(time)
    private val zone=ZoneOffset.UTC
    private fun row(amount:Long=7,kind:String="expense",date:String=time):CloudRecord {
        val id=UUID.randomUUID().toString()
        return CloudRecord(CloudEntity.LEDGER_TRANSACTION.table,id,owner.value,buildJsonObject {
            put("id",id);put("user_id",owner.value);put("primary_kind_raw_value",kind);put("entry_status_raw_value","posted");put("title","Weekly raw")
            put("amount_minor",amount);put("source_currency_code","JPY");put("is_archived",false);put("occurred_at",date);put("created_at",time);put("updated_at",time)
        },time,null,0)
    }
    private fun CloudRecord.with(key:String,value:JsonElement)=copy(payload=JsonObject(payload+(key to value)))
    private fun project(vararg records:CloudRecord,reference:Instant=this.reference)=overviewRawWeeklySpending(owner,records.toList(),emptyList(),"JPY",reference=reference,zone=zone)
    private fun current(vararg records:CloudRecord)=project(*records).last()
    private fun minor(expected:Long,actual:BigInteger?)=assertEquals(BigInteger.valueOf(expected),actual)
    @Test fun `required unreadable posted expense holds the whole week instead of a partial sum`() {
        val week=current(row(3),row().with("amount_minor",JsonPrimitive("broken")))
        assertTrue(week.hasUnavailableConversion);assertNull(week.totalMinor)
        assertNull(week.points.single {it.date==reference.atZone(zone).toLocalDate()}.amountMinor)
        minor(10,current(row(3),row()).totalMinor)
    }
    @Test fun `unused income override destination money and created clock cannot drop known spending`() {
        for(key in listOf("reporting_income_minor","destination_amount_minor","created_at")) minor(7,current(row().with(key,JsonPrimitive("broken"))).totalMinor)
    }
    @Test fun `reporting override removes original amount dependency and exact money remains unclamped`() {
        minor(3,current(row().with("amount_minor",JsonPrimitive("broken")).with("reporting_expense_minor",JsonPrimitive(3))).totalMinor)
        assertEquals(BigInteger.valueOf(Long.MAX_VALUE)*BigInteger.TWO,current(row(Long.MAX_VALUE),row(Long.MAX_VALUE)).totalMinor)
        minor(-1,current(row(Long.MAX_VALUE),row(Long.MIN_VALUE)).totalMinor)
    }
    @Test fun `unplaceable expense holds all known weeks without assigning an invented day`() {
        val old=row(2,date="2026-10-05T12:00:00Z")
        val weeks=project(old,row(3),row().with("occurred_at",JsonPrimitive("broken")))
        assertEquals(3,weeks.size)
        weeks.forEach {assertTrue(it.hasUnavailableConversion);assertNull(it.totalMinor);assertTrue(it.points.all {point ->point.amountMinor!=null})}
        minor(2,weeks.first().points.fold(BigInteger.ZERO) {sum,point ->sum+checkNotNull(point.amountMinor)})
    }
    @Test fun `numeric strings are not valid required reporting wire money`() {
        assertNull(current(row().with("amount_minor",JsonPrimitive("7"))).totalMinor)
        assertNull(current(row().with("reporting_expense_minor",JsonPrimitive("3"))).totalMinor)
    }
    @Test fun `unknown required eligibility cannot silently become a zero week`() {
        for(key in listOf("entry_status_raw_value","is_archived","primary_kind_raw_value")) {
            val week=current(row().with(key,JsonPrimitive("unknown")));assertTrue(week.hasUnavailableConversion);assertNull(week.totalMinor)
        }
        assertNull(current(row().with("is_archived",JsonPrimitive("false"))).totalMinor)
    }
    @Test fun `source metadata is independent of unused opening and kind and malformed currency stays unknown`() {
        val id=UUID.randomUUID().toString()
        val wallet=CloudRecord(CloudEntity.LEDGER_WALLET.table,id,owner.value,buildJsonObject {
            put("id",id);put("user_id",owner.value);put("currency_code","VND");put("kind_raw_value","futureKind");put("opening_balance_minor","broken")
        },time,null,0)
        val original=row(165).with("source_wallet_id",JsonPrimitive(id)).with("source_currency_code",JsonNull)
        minor(1,overviewRawWeeklySpending(owner,listOf(original),listOf(wallet),"JPY",listOf(ExchangeRateSnapshot("JPY","VND","165","test",0,null)),reference=reference,zone=zone).last().totalMinor)
        assertNull(current(row().with("source_currency_code",buildJsonObject {})).totalMinor)
    }
    @Test fun `foreign inactive future weeks and income only unknowns cannot poison current spending`() {
        val bad=row().with("amount_minor",JsonPrimitive("broken"))
        val excluded=listOf(bad.copy(ownerUserId=other),bad.with("user_id",JsonPrimitive(other)),bad.with("id",JsonPrimitive(UUID.randomUUID().toString())),bad.copy(deletedAt=time),
            bad.with("entry_status_raw_value",JsonPrimitive("draft")),bad.with("is_archived",JsonPrimitive(true)),bad.with("occurred_at",JsonPrimitive("2026-10-26T00:00:00Z")),
            row(kind="income").with("amount_minor",JsonPrimitive("broken")).with("occurred_at",JsonPrimitive("broken")))
        val week=current(*(excluded+row(3)).toTypedArray());minor(3,week.totalMinor);assertFalse(week.hasUnavailableConversion)
    }
    @Test fun `current week includes future posted dates across month boundary with its own availability`() {
        val endOfMonth=Instant.parse("2026-08-31T12:00:00Z")
        val nextMonth=row(date="2026-09-01T12:00:00Z")
        minor(7,project(nextMonth,reference=endOfMonth).single().totalMinor)
        val unreadable=project(nextMonth.with("amount_minor",JsonPrimitive("broken")),reference=endOfMonth).single()
        assertTrue(unreadable.hasUnavailableConversion);assertNull(unreadable.totalMinor)
        val monthly=overviewRawMonthlyCashflow(owner,listOf(nextMonth),emptyList(),"JPY",reference=endOfMonth,zone=zone).single()
        minor(0,monthly.expenseMinor)
    }
    @Test fun `known zero expense is independent of uncertain income classification and calendar`() {
        val originalZero=row(0).with("reporting_income_minor",JsonPrimitive(7))
        val overrideZero=row().with("amount_minor",JsonPrimitive("broken")).with("reporting_expense_minor",JsonPrimitive(0)).with("reporting_income_minor",JsonPrimitive(7))
        for(original in listOf(originalZero,overrideZero)) {
            val record=original.with("primary_kind_raw_value",JsonPrimitive("futureKind")).with("occurred_at",JsonPrimitive("broken")).with("source_currency_code",buildJsonObject {})
            val week=current(record);minor(0,week.totalMinor);assertFalse(week.hasUnavailableConversion)
            val monthly=overviewRawMonthlyCashflow(owner,listOf(record),emptyList(),"JPY",reference=reference,zone=zone).single()
            minor(0,monthly.expenseMinor);assertNull(monthly.incomeMinor)
        }
    }
    @Test fun `week cutoff crosses year boundary and uses the reporting timezone`() {
        val yearEnd=Instant.parse("2026-12-31T12:00:00Z")
        val nextYear=row(date="2027-01-01T00:00:00Z")
        val future=row(date="2027-01-04T00:00:00Z").with("amount_minor",JsonPrimitive("broken"))
        val yearWeek=project(nextYear,future,reference=yearEnd).single()
        assertEquals(LocalDate.of(2026,12,28),yearWeek.start);minor(7,yearWeek.totalMinor)
        val tokyo=ZoneId.of("Asia/Tokyo");val sundayUTC=Instant.parse("2026-10-25T16:00:00Z")
        val localMonday=row(date="2026-10-25T18:00:00Z")
        val nextLocalWeek=row(date="2026-11-01T18:00:00Z").with("amount_minor",JsonPrimitive("broken"))
        val zoned=overviewRawWeeklySpending(owner,listOf(localMonday,nextLocalWeek),emptyList(),"JPY",reference=sundayUTC,zone=tokyo).single()
        assertEquals(LocalDate.of(2026,10,26),zoned.start);minor(7,zoned.totalMinor);minor(7,zoned.points.first().amountMinor)
    }
}
