package vn.com.quyln.mistia.feature.overview

import java.math.BigInteger
import java.time.*
import java.util.UUID
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import vn.com.quyln.mistia.core.model.*

class OverviewOriginalDayRawInputsTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other="99999999-9999-9999-9999-999999999999"
    private val time="2026-10-20T12:00:00Z"
    private val day=LocalDate.of(2026,10,20)
    private val zone=ZoneOffset.UTC
    private fun row(amount:Long=7,kind:String="expense",occurred:String=time,created:String=time):CloudRecord {
        val id=UUID.randomUUID().toString()
        return CloudRecord(CloudEntity.LEDGER_TRANSACTION.table,id,owner.value,buildJsonObject {
            put("id",id);put("user_id",owner.value);put("title","Original day raw");put("primary_kind_raw_value",kind);put("entry_status_raw_value","posted")
            put("amount_minor",amount);put("source_currency_code","JPY");put("is_archived",false);put("occurred_at",occurred);put("created_at",created);put("updated_at",time)
        },time,null,0)
    }
    private fun CloudRecord.with(key:String,value:JsonElement)=copy(payload=JsonObject(payload+(key to value)))
    private fun project(vararg records:CloudRecord)=overviewRawExpenseDay(owner,records.toList(),emptyList(),day,"JPY",zone=zone)
    private fun minor(expected:Long,actual:BigInteger?)=assertEquals(BigInteger.valueOf(expected),actual)
    @Test fun `unreadable original expense retains its identity and count without inventing zero money`() {
        val damaged=row().with("amount_minor",JsonPrimitive("broken"));val details=project(damaged)
        assertEquals(listOf(damaged.id),details.rows.map {it.transaction.id});assertNull(details.rows.single().money);assertNull(details.rows.single().originalMinor);assertFalse(details.hasUncertainEntries);assertNull(details.totalMinor)
    }
    @Test fun `numeric strings and fractional original minor are unknown despite readable reporting override`() {
        for(value in listOf(JsonPrimitive("7"),JsonPrimitive(1.5),JsonNull)) {
            val original=row().with("amount_minor",value).with("reporting_expense_minor",JsonPrimitive(300))
            val details=project(original);assertNull(details.totalMinor);assertEquals(1,details.rows.size);assertNull(details.rows.single().money)
        }
    }
    @Test fun `unused reporting destination and created clock do not discard original expense money`() {
        for(key in listOf("reporting_expense_minor","reporting_income_minor","destination_amount_minor","created_at")) {
            val details=project(row().with(key,JsonPrimitive("broken")));minor(7,details.totalMinor);assertEquals(Money(7,"JPY"),details.rows.single().money)
        }
    }
    @Test fun `original classification and money remain distinct from reporting only effects`() {
        val original=row().with("reporting_expense_minor",JsonPrimitive(300))
        val reportingOnly=row(9,"income").with("reporting_expense_minor",JsonPrimitive(500))
        val details=project(original,reportingOnly);minor(7,details.totalMinor);assertEquals(listOf(original.id),details.rows.map {it.transaction.id})
    }
    @Test fun `unplaceable expense cannot leave a confident partial selected day total`() {
        val known=row(3);val unknown=row().with("occurred_at",JsonPrimitive("broken"))
        val details=project(known,unknown);assertNull(details.totalMinor);assertTrue(details.hasUncertainEntries);assertEquals(listOf(known.id),details.rows.map {it.transaction.id})
    }
    @Test fun `unknown required eligibility cannot silently become an empty zero day`() {
        for(key in listOf("entry_status_raw_value","is_archived","primary_kind_raw_value")) {
            val details=project(row().with(key,JsonPrimitive("unknown")));assertNull(details.totalMinor);assertTrue(details.hasUncertainEntries);assertTrue(details.rows.isEmpty())
        }
        assertNull(project(row().with("is_archived",JsonPrimitive("false"))).totalMinor)
    }
    @Test fun `unreadable creation metadata keeps money and sorts after readable creation ties`() {
        val unreadable=row(created="broken");val known=row(created="2026-10-20T11:00:00Z")
        val tied=project(unreadable,known);assertEquals(listOf(known.id,unreadable.id),tied.rows.map {it.transaction.id});minor(14,tied.totalMinor)
        val newer=row(2,occurred="2026-10-20T12:00:01Z",created="broken")
        val ordered=project(known,newer);assertEquals(listOf(newer.id,known.id),ordered.rows.map {it.transaction.id});minor(9,ordered.totalMinor)
    }
    @Test fun `original source currency survives unneeded wallet fields and malformed currency stays unknown`() {
        val id=UUID.randomUUID().toString()
        val wallet=CloudRecord(CloudEntity.LEDGER_WALLET.table,id,owner.value,buildJsonObject {
            put("id",id);put("user_id",owner.value);put("name","Day VND");put("currency_code","VND");put("kind_raw_value","futureKind");put("opening_balance_minor","broken")
        },time,null,0)
        val original=row(165).with("source_wallet_id",JsonPrimitive(id)).with("source_currency_code",JsonNull)
        val details=overviewRawExpenseDay(owner,listOf(original),listOf(wallet),day,"JPY",listOf(ExchangeRateSnapshot("JPY","VND","165","test",0,null)),zone=zone)
        minor(1,details.totalMinor);assertEquals(Money(165,"VND"),details.rows.single().money)
        val unknown=project(row().with("source_currency_code",buildJsonObject {}));assertNull(unknown.totalMinor);assertNull(unknown.rows.single().money)
        val zero=project(row(0).with("source_currency_code",buildJsonObject {}));minor(0,zero.totalMinor);assertNull(zero.rows.single().money)
    }
    @Test fun `foreign known inactive other date and non spending rows never poison selected day`() {
        val bad=row().with("amount_minor",JsonPrimitive("broken"))
        val excluded=listOf(bad.copy(ownerUserId=other),bad.with("user_id",JsonPrimitive(other)),bad.with("id",JsonPrimitive(UUID.randomUUID().toString())),bad.copy(deletedAt=time),
            bad.with("is_archived",JsonPrimitive(true)),bad.with("entry_status_raw_value",JsonPrimitive("draft")),bad.with("occurred_at",JsonPrimitive("2026-10-19T12:00:00Z")),
            bad.with("primary_kind_raw_value",JsonPrimitive("income")),bad.with("category_id",JsonPrimitive(SystemCategoryIdentity.canonicalId("loan_repayment"))),
            bad.with("settlement_role_raw_value",JsonPrimitive("investmentBuy")))
        val known=row(3);val details=project(*(excluded+known).toTypedArray());minor(3,details.totalMinor);assertEquals(listOf(known.id),details.rows.map {it.transaction.id})
        assertEquals(BigInteger.valueOf(Long.MAX_VALUE)*BigInteger.TWO,project(row(Long.MAX_VALUE),row(Long.MAX_VALUE)).totalMinor)
        minor(-1,project(row(Long.MAX_VALUE),row(Long.MIN_VALUE)).totalMinor)
    }
    @Test fun `zero original contribution needs no currency but cannot prove the row count`() {
        val known=row(3)
        for(key in listOf("occurred_at","entry_status_raw_value","primary_kind_raw_value","is_archived")) {
            val uncertain=row(0).with(key,JsonPrimitive("broken")).with("source_currency_code",buildJsonObject {}).with("reporting_expense_minor",JsonPrimitive(500))
            val details=project(known,uncertain);minor(3,details.totalMinor);assertTrue(details.hasUncertainEntries);assertEquals(listOf(known.id),details.rows.map {it.transaction.id})
        }
    }
    @Test fun `paid for debt uses original money while uncertain required category cannot invent eligibility`() {
        val paid=row(7,"transfer").with("transfer_subtype_raw_value",JsonPrimitive("debt")).with("debt_intent_raw_value",JsonPrimitive("borrow"))
            .with("category_id",JsonPrimitive(UUID.randomUUID().toString())).with("reporting_expense_minor",JsonPrimitive(300))
        val details=project(paid);minor(7,details.totalMinor);assertFalse(details.hasUncertainEntries);assertEquals(listOf(paid.id),details.rows.map {it.transaction.id})
        val uncertain=project(paid.with("category_id",buildJsonObject {}));assertNull(uncertain.totalMinor);assertTrue(uncertain.hasUncertainEntries);assertTrue(uncertain.rows.isEmpty())
    }
    @Test fun `stable original ordering and historical wallet labels preserve owner identity without unused fields`() {
        val first=row();val second=row();assertEquals(listOf(first.id,second.id),project(first,second).rows.map {it.transaction.id})
        val id=UUID.randomUUID().toString();val wallet=CloudRecord(CloudEntity.LEDGER_WALLET.table,id,owner.value,buildJsonObject {
            put("id",id);put("user_id",owner.value);put("name","Historical VND");put("is_archived",true);put("kind_raw_value","future");put("opening_balance_minor","broken")
        },time,null,0)
        assertEquals("Historical VND",overviewDayWalletMetadata(owner,listOf(wallet)).getValue(id).name)
        for(excluded in listOf(wallet.copy(ownerUserId=other),wallet.with("user_id",JsonPrimitive(other)),wallet.copy(deletedAt=time),wallet.with("deleted_at",buildJsonObject {}))) {
            assertTrue(overviewDayWalletMetadata(owner,listOf(excluded)).isEmpty())
        }
    }

}
