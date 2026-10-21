package vn.com.quyln.mistia.feature.planning

import java.math.BigInteger
import java.time.*
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import vn.com.quyln.mistia.core.model.*

class BudgetRawPlansTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val id="22222222-2222-2222-2222-222222222222"
    private val second="33333333-3333-3333-3333-333333333333"
    private val category="44444444-4444-4444-4444-444444444444"
    private val parent="55555555-5555-5555-5555-555555555555"
    private val other="99999999-9999-9999-9999-999999999999"
    private val zone=ZoneId.of("Asia/Tokyo")
    private val month=YearMonth.of(2026,10)
    private val now=Instant.parse("2026-10-20T00:00:00Z")
    private fun row():CloudRecord = CloudRecord(CloudEntity.BUDGET_PLAN.table,id,owner.value,buildJsonObject {
        put("id",id);put("user_id",owner.value);put("category_id",category);put("category_id_snapshot",category)
        put("category_name_snapshot","Food");put("category_parent_id_snapshot",parent);put("category_is_parent_snapshot",false)
        put("month_anchor","2026-09-30T15:00:00Z");put("limit_minor",1000);put("currency_code","JPY");put("rollover_enabled",false);put("is_archived",false)
        put("created_at",now.toString());put("updated_at",now.toString());put("sync_version",0)
    },now.toString(),null,0)
    private fun CloudRecord.change(key:String,value:JsonElement)=copy(payload=JsonObject(payload+(key to value)))
    private fun project(rows:List<CloudRecord>?)=projectRawBudgetPlans(owner,rows,emptyList(),emptyList(),emptyList(),month,now,zone,emptyList(),CategoryNameLanguage.ENGLISH,emptySet(),"JPY")
    private fun held(projection:BudgetProjection) {assertNull(projection.totalLimitMinor);assertNull(projection.totalSpentMinor);assertNull(projection.remainingMinor);assertTrue(projection.branches.isEmpty())}
    @Test fun `unreadable required money cannot become an empty zero budget`() {
        for(value in listOf(JsonPrimitive("1000"),JsonPrimitive(1.5),JsonNull,JsonPrimitive("9223372036854775808"))) held(project(listOf(row().change("limit_minor",value))))
        held(project(listOf(row().copy(payload=JsonObject(row().payload-"limit_minor")))))
    }
    @Test fun `unknown latest month cannot resurrect an older known continuity plan`() {
        val old=row().copy(id=second).change("id",JsonPrimitive(second)).change("month_anchor",JsonPrimitive("2026-08-31T15:00:00Z")).change("limit_minor",JsonPrimitive(500))
        held(project(listOf(old,row().change("month_anchor",JsonPrimitive("broken")))))
    }
    @Test fun `uncertain archive or body deletion cannot publish the other known plan`() {
        for((key,value) in listOf("is_archived" to JsonPrimitive("false"),"is_archived" to JsonNull,"deleted_at" to buildJsonObject {put("bad",true)})) {
            held(project(listOf(row().change(key,value))))
        }
    }
    @Test fun `not yet loaded is unavailable while loaded empty is a known zero`() {
        held(project(null));assertEquals(BigInteger.ZERO,project(emptyList()).totalLimitMinor)
    }
    @Test fun `known archived deleted and future damage stays neutral`() {
        val bad=row().change("limit_minor",JsonPrimitive("bad"))
        val excluded=listOf(bad.change("is_archived",JsonPrimitive(true)),bad.copy(deletedAt=now.toString()),bad.change("deleted_at",JsonPrimitive(now.toString())),bad.change("month_anchor",JsonPrimitive("2026-10-31T15:00:00Z")))
        for(value in excluded) assertEquals(BigInteger.ZERO,project(listOf(value)).totalLimitMinor)
    }
    @Test fun `foreign or body mismatched plan cannot leak or hold owned money`() {
        val foreign=row().copy(ownerUserId=other).change("user_id",JsonPrimitive(other))
        val wrongBody=row().change("user_id",JsonPrimitive(other))
        val wrongId=row().change("id",JsonPrimitive(second)).change("limit_minor",JsonPrimitive(2000))
        val wrongTable=row().copy(entity=CloudEntity.SAVINGS_GOAL.table)
        for(value in listOf(foreign,wrongBody,wrongId,wrongTable)) assertEquals(BigInteger.ZERO,project(listOf(value)).totalLimitMinor)
    }
    @Test fun `unplaceable owned plan cannot disappear into no budgets`() {
        val raw=row().change("category_id",JsonNull).change("category_id_snapshot",JsonNull).change("category_parent_id_snapshot",JsonNull)
        held(project(listOf(raw)))
    }
    @Test fun `nonpositive saved limit cannot publish a stable negative or empty allowance`() {
        for(amount in listOf(0L,-1L,Long.MIN_VALUE)) held(project(listOf(row().change("limit_minor",JsonPrimitive(amount)))))
    }
    @Test fun `foreign duplicate before an owned plan cannot hide owned money`() {
        val foreign=row().copy(ownerUserId=other).change("user_id",JsonPrimitive(other))
        assertEquals(BigInteger.valueOf(1000),project(listOf(foreign,row())).totalLimitMinor)
    }
    @Test fun `editor reload uses exact owned original and rejects missing malformed or foreign rows`() {
        val raw=row().change("limit_minor",JsonPrimitive(Long.MAX_VALUE))
        assertEquals(BudgetPlanRecord.fromCloudRecord(raw),storedBudgetReadPlan(owner,id,listOf(raw)))
        assertEquals(Long.MAX_VALUE,storedBudgetReadPlan(owner,id,listOf(raw))!!.limitMinor)
        assertNull(storedBudgetReadPlan(owner,second,listOf(raw)))
        assertNull(storedBudgetReadPlan(UserId(other),id,listOf(raw)))
        assertNull(storedBudgetReadPlan(owner,id,listOf(raw.change("limit_minor",JsonNull))))
        assertNull(storedBudgetReadPlan(owner,id,listOf(raw.change("deleted_at",buildJsonObject {put("bad",true)}))))
        assertNull(storedBudgetReadPlan(owner,id,listOf(raw.change("is_archived",JsonPrimitive(true)))))
    }
    @Test fun `valid plan retains exact Long maximum without rewriting payload`() {
        val original=row().change("limit_minor",JsonPrimitive(Long.MAX_VALUE));val before=original.payload
        assertEquals(BigInteger.valueOf(Long.MAX_VALUE),project(listOf(original)).totalLimitMinor);assertEquals(before,original.payload)
    }
    @Test fun `only required current damage holds a known neighbouring branch`() {
        val damaged=row().copy(id=second).change("id",JsonPrimitive(second)).change("limit_minor",JsonPrimitive("bad"))
        held(project(listOf(row(),damaged)))
        assertEquals(BigInteger.valueOf(1000),project(listOf(row(),damaged.change("is_archived",JsonPrimitive(true)))).totalLimitMinor)
    }
}
